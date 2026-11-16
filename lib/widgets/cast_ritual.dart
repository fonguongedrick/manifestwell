import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../utils/haptics.dart';
import 'package:provider/provider.dart';

import '../models/wish.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../utils/moderation.dart';
import 'effects.dart';
import 'glyphs.dart';
import 'ui.dart';
import 'well_painter.dart';

enum _Stage { compose, orb, dropping, done }

const _orbSize = 84.0;

const _sparkTags = <(String, GlyphKind)>[
  ('Treat', GlyphKind.cup),
  ('Windfall', GlyphKind.coin),
  ('Peace', GlyphKind.moon),
  ('Kindness', GlyphKind.heart),
];

/// Write a wish, watch it become light, carry it to the well and let go.
/// Shared by the Cast tab and the onboarding first-wish step.
class CastRitual extends StatefulWidget {
  final VoidCallback onPaywall;
  final VoidCallback? onFinished;
  final ValueChanged<bool>? onImmersive;
  final String finishedLabel;
  final bool allowAnother;
  const CastRitual({
    super.key,
    required this.onPaywall,
    this.onFinished,
    this.onImmersive,
    this.finishedLabel = 'Back to the Well',
    this.allowAnother = true,
  });

  @override
  State<CastRitual> createState() => _CastRitualState();
}

class _CastRitualState extends State<CastRitual> with TickerProviderStateMixin {
  final _text = TextEditingController();
  final _focus = FocusNode();
  late final AnimationController _sink;
  late final AnimationController _back;
  late final AnimationController _idle;
  late final AnimationController _rings;
  late final AppState _app;

  _Stage _stage = _Stage.compose;
  WishKind _kind = WishKind.big;
  WishCategory _category = WishCategory.career;
  String? _tag;
  String? _error;

  Offset? _pos; // orb centre while held; null means resting at home
  Offset _from = Offset.zero;
  Size _scene = Size.zero;
  bool _near = false;
  bool _landed = false;

  @override
  void initState() {
    super.initState();
    _sink = AnimationController(vsync: this, duration: const Duration(milliseconds: 1900))
      ..addListener(_onSink)
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) _finishDrop();
      });
    _back = AnimationController(vsync: this, duration: const Duration(milliseconds: 520))
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) setState(() => _pos = null);
      });
    _idle = AnimationController(vsync: this, duration: const Duration(seconds: 5));
    _rings = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400));
    _focus.addListener(() => setState(() {}));
    _app = context.read<AppState>()..addListener(_takeStagedWish);
    WidgetsBinding.instance.addPostFrameCallback((_) => _takeStagedWish());
  }

  /// A wish typed into the Well's Make a Wish card goes straight to the orb.
  void _takeStagedWish() {
    if (!mounted || _stage != _Stage.compose) return;
    final staged = _app.takePending();
    if (staged == null) return;
    _text.text = staged;
    _kind = WishKind.big;
    _toOrb();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _idle.stop();
    } else if (!_idle.isAnimating) {
      _idle.repeat();
    }
  }

  @override
  void dispose() {
    _app.removeListener(_takeStagedWish);
    _text.dispose();
    _focus.dispose();
    _sink.dispose();
    _back.dispose();
    _idle.dispose();
    _rings.dispose();
    super.dispose();
  }

  void _setStage(_Stage s) {
    setState(() => _stage = s);
    widget.onImmersive?.call(s == _Stage.orb || s == _Stage.dropping);
  }

  // ---- geometry ----------------------------------------------------------

  double get _wellWidth => math.min(_scene.width - 56, 330);
  Rect get _wellRect {
    final w = _wellWidth;
    final h = WellPainter.heightFor(w);
    return Rect.fromLTWH((_scene.width - w) / 2, _scene.height - h - 8, w, h);
  }

  Offset get _water => _wellRect.topLeft + WellPainter.waterCenter(_wellRect.size);
  Offset get _home => Offset(_scene.width / 2, _scene.height * 0.24);

  double _proximity(Offset p) =>
      (1 - (_water - p).distance / (_scene.height * 0.78)).clamp(0.0, 1.0);

  // ---- compose -> orb ----------------------------------------------------

  void _toOrb() {
    if (_kind == WishKind.big && !context.read<AppState>().canCastBigWish) {
      widget.onPaywall();
      return;
    }
    final state = context.read<AppState>();
    // The admin can pause sharing. Sparks are private, so they carry on.
    if (_kind == WishKind.big && state.wishingPaused) {
      Haptics.light();
      setState(() => _error = 'New wishes are paused for a little while. Try again soon.');
      return;
    }
    final problem = Moderation.check(_text.text, extraBlocked: state.config.blockedTerms);
    if (problem != null) {
      Haptics.light();
      setState(() => _error = problem);
      return;
    }
    _focus.unfocus();
    Haptics.medium();
    _error = null;
    _pos = null;
    _near = false;
    _landed = false;
    _sink.value = 0;
    _setStage(_Stage.orb);
  }

  // ---- drag --------------------------------------------------------------

  void _onPanUpdate(DragUpdateDetails d) {
    if (_stage != _Stage.orb) return;
    _back.stop();
    final next = (_pos ?? _home) + d.delta;
    final clamped = Offset(
      next.dx.clamp(_orbSize / 2, _scene.width - _orbSize / 2),
      next.dy.clamp(_orbSize / 2, _scene.height - _orbSize / 2),
    );
    final p = _proximity(clamped);
    if (p > 0.6 && !_near) {
      _near = true;
      Haptics.selection();
    } else if (p < 0.5) {
      _near = false;
    }
    setState(() => _pos = clamped);
  }

  void _onPanEnd(DragEndDetails _) {
    if (_stage != _Stage.orb) return;
    final pos = _pos ?? _home;
    if ((_water - pos).distance < _wellWidth * 0.5) {
      _release();
    } else {
      _from = pos;
      _back.forward(from: 0);
    }
  }

  // ---- release -----------------------------------------------------------

  Future<void> _release() async {
    if (_stage != _Stage.orb) return;
    _from = _pos ?? _home;
    _setStage(_Stage.dropping);
    _wish = context.read<AppState>().cast(_text.text, _kind, _category, tag: _tag);
    _sink.forward(from: 0);
  }

  Future<Wish?>? _wish;

  void _onSink() {
    if (!_landed && _sink.value >= 0.62) {
      _landed = true;
      Haptics.heavy();
    }
    setState(() {});
  }

  Future<void> _finishDrop() async {
    Haptics.light();
    final wish = await _wish;
    if (!mounted) return;
    if (wish == null) {
      _setStage(_Stage.compose);
      widget.onPaywall();
      return;
    }
    _rings.forward(from: 0);
    _setStage(_Stage.done);
  }

  void _again() {
    _text.clear();
    _tag = null;
    _setStage(_Stage.compose);
  }

  // ---- build -------------------------------------------------------------

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
        duration: const Duration(milliseconds: 420),
        switchInCurve: Curves.easeOut,
        child: switch (_stage) {
          _Stage.compose => _compose(),
          _Stage.done => _done(),
          _ => _orbStage(),
        },
      );

  Widget _compose() {
    final spark = _kind == WishKind.spark;
    final len = _text.text.characters.length;
    return SingleChildScrollView(
      key: const ValueKey('compose'),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.fromLTRB(
          MW.gutter, 12, MW.gutter, MediaQuery.viewInsetsOf(context).bottom + 150),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SlidingSegment<WishKind>(
          options: const [(WishKind.big, 'Big wish'), (WishKind.spark, 'Daily spark')],
          value: _kind,
          onChanged: (k) => setState(() {
            _kind = k;
            _error = null;
          }),
        ),
        const SizedBox(height: 34),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: Align(
            key: ValueKey(_kind),
            alignment: Alignment.centerLeft,
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: spark ? 'What went ' : 'What are you '),
                TextSpan(
                  text: spark ? 'right today?' : 'hoping for?',
                  style: MW.display(28, color: MW.goldBright),
                ),
              ]),
              style: MW.display(28),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          spark
              ? 'A tiny win that already happened. Proof counts.'
              : 'Say it as if it is already on its way.',
          style: MW.ui(14, color: MW.textFaint),
        ),
        const SizedBox(height: 26),
        SizedBox(
          height: 96,
          child: ListView(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            children: spark
                ? [
                    for (final t in _sparkTags)
                      _Choice(
                        label: t.$1,
                        glyph: t.$2,
                        selected: _tag == t.$1,
                        onTap: () => setState(() => _tag = _tag == t.$1 ? null : t.$1),
                      ),
                  ]
                : [
                    for (final c in WishCategory.values.where((c) => c != WishCategory.daily))
                      _Choice(
                        label: c.label,
                        glyph: c.glyph,
                        selected: _category == c,
                        onTap: () => setState(() => _category = c),
                      ),
                  ],
          ),
        ),
        const SizedBox(height: 22),
        TextField(
          controller: _text,
          focusNode: _focus,
          minLines: 2,
          maxLines: 5,
          maxLength: Moderation.maxLength,
          buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
          onChanged: (_) => setState(() => _error = null),
          textCapitalization: TextCapitalization.sentences,
          cursorColor: MW.gold,
          cursorHeight: 30,
          style: MW.voice(24),
          decoration: InputDecoration(
            isCollapsed: true,
            border: InputBorder.none,
            hintText: spark ? 'My morning coffee was free…' : 'My dream apartment comes through…',
            hintStyle: MW.voice(24, color: MW.textFaint),
          ),
        ),
        const SizedBox(height: 14),
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          height: 1.5,
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [
              _focus.hasFocus ? MW.gold.withValues(alpha: 0.9) : const Color(0x2EFFFFFF),
              Colors.transparent,
            ]),
          ),
        ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: _error == null
                  ? const SizedBox(key: ValueKey('ok'), height: 18)
                  : Text(_error!,
                      key: ValueKey(_error),
                      style: MW.ui(13, color: const Color(0xFFFFA9A0), weight: 600)),
            ),
          ),
          Text(
            '$len / ${Moderation.maxLength}',
            style: MW.ui(12, color: len > 190 ? MW.gold : MW.textFaint, weight: 600),
          ),
        ]),
        const SizedBox(height: 28),
        GlowButton(
          'Turn it into light',
          glyph: GlyphKind.spark,
          onPressed: _text.text.trim().isEmpty ? null : _toOrb,
        ),
        const SizedBox(height: 14),
        Center(
          child: Text(
            spark
                ? 'Saved privately to your Proof Vault.'
                : 'Wishes are anonymous. Others can send you lucky energy.',
            textAlign: TextAlign.center,
            style: MW.ui(12.5, color: MW.textFaint),
          ),
        ),
      ]),
    );
  }

  Widget _orbStage() {
    final golden = context.read<AppState>().goldenOrbUnlocked;
    final dropping = _stage == _Stage.dropping;
    return Column(key: const ValueKey('orb'), children: [
      const SizedBox(height: 28),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Text(
          _text.text.trim(),
          textAlign: TextAlign.center,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: MW.voice(25, color: MW.textDim),
        ),
      ),
      Expanded(
        child: LayoutBuilder(builder: (context, c) {
          _scene = Size(c.maxWidth, c.maxHeight);
          return AnimatedBuilder(
            animation: Listenable.merge([_sink, _back, _idle]),
            builder: (_, _) {
              final wr = _wellRect;
              final t = _sink.value;

              Offset pos;
              var sinkScale = 1.0;
              var opacity = 1.0;
              if (dropping) {
                final travel = Curves.easeInOutCubic.transform((t / 0.62).clamp(0.0, 1.0));
                pos = Offset.lerp(_from, _water, travel)!;
                sinkScale = 1 - 0.85 * Curves.easeIn.transform(((t - 0.45) / 0.55).clamp(0.0, 1.0));
                opacity = 1 - ((t - 0.66) / 0.34).clamp(0.0, 1.0);
              } else if (_back.isAnimating) {
                pos = Offset.lerp(_from, _home, Curves.easeOutBack.transform(_back.value))!;
              } else {
                final bob = _pos == null ? math.sin(_idle.value * math.pi * 2) * 7 : 0.0;
                pos = (_pos ?? _home) + Offset(0, bob);
              }

              final p = dropping ? 1.0 : _proximity(pos);
              final scale = (1 - 0.42 * p * p) * sinkScale;
              final land = ((t - 0.62) / 0.38).clamp(0.0, 1.0);

              return Stack(clipBehavior: Clip.none, children: [
                Positioned.fromRect(
                  rect: wr,
                  child: CustomPaint(
                    painter: WellPainter(
                      glow: dropping ? 0.9 : p,
                      ripple: dropping ? land : 0,
                      bloom: dropping ? math.sin(math.pi * land) : 0,
                      phase: _idle.value,
                    ),
                  ),
                ),
                Positioned(
                  left: pos.dx - 70,
                  top: pos.dy - 70,
                  width: 140,
                  height: 140,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanStart: (_) => Haptics.selection(),
                    onPanUpdate: _onPanUpdate,
                    onPanEnd: _onPanEnd,
                    child: Center(
                      child: Opacity(
                        opacity: opacity,
                        child: Transform.scale(
                          scale: scale,
                          child: GlowOrb(size: _orbSize, golden: golden),
                        ),
                      ),
                    ),
                  ),
                ),
              ]);
            },
          );
        }),
      ),
      AnimatedOpacity(
        opacity: dropping ? 0 : 1,
        duration: const Duration(milliseconds: 250),
        child: Column(children: [
          const Caps('Carry your light to the well', color: MW.textDim),
          QuietLink('or tap to release', onPressed: dropping ? null : _release),
          const SizedBox(height: 12),
        ]),
      ),
    ]);
  }

  Widget _done() {
    final spark = _kind == WishKind.spark;
    return Center(
      key: const ValueKey('done'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: MW.gutter),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
            width: 280,
            height: 220,
            child: Stack(alignment: Alignment.center, children: [
              AnimatedBuilder(
                animation: _rings,
                builder: (_, _) => CustomPaint(
                  size: const Size(280, 220),
                  painter: RingsPainter(_rings.value),
                ),
              ),
              const GlowOrb(size: 44, golden: true),
            ]),
          ),
          Text('Released.', style: MW.display(34)),
          const SizedBox(height: 10),
          Text(
            spark
                ? 'Added to your Proof Vault.\nGood things keep finding you.'
                : 'Your wish is in the Well.\nOthers can now send you lucky energy.',
            textAlign: TextAlign.center,
            style: MW.ui(15, color: MW.textDim, height: 1.55),
          ),
          const SizedBox(height: 36),
          GlowButton(widget.finishedLabel, onPressed: () {
            _again();
            widget.onFinished?.call();
          }),
          if (widget.allowAnother) QuietLink('Cast another', onPressed: _again),
        ]),
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  final String label;
  final GlyphKind glyph;
  final bool selected;
  final VoidCallback onTap;
  const _Choice({
    required this.label,
    required this.glyph,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: selected,
        label: label,
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            Haptics.selection();
            onTap();
          },
          child: SizedBox(
            width: 76,
            child: Column(children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? MW.gold.withValues(alpha: 0.14) : MW.glass,
                  border: Border.all(
                    color: selected ? MW.gold.withValues(alpha: 0.8) : MW.hairline,
                    width: selected ? 1.4 : 1,
                  ),
                  boxShadow: selected
                      ? [BoxShadow(color: MW.gold.withValues(alpha: 0.25), blurRadius: 18)]
                      : null,
                ),
                alignment: Alignment.center,
                child: Glyph(glyph,
                    size: 23, color: selected ? MW.goldBright : MW.textDim, stroke: 1.5),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                style: MW.ui(11.5,
                    color: selected ? MW.goldBright : MW.textFaint, weight: 700, height: 1.25),
              ),
            ]),
          ),
        ),
      );
}
