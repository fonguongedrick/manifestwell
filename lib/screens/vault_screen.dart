import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import '../utils/haptics.dart';
import 'package:provider/provider.dart';

import '../models/wish.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/glyphs.dart';
import '../widgets/proof_row.dart';
import '../widgets/steps_sheet.dart';
import '../widgets/ui.dart';

class VaultScreen extends StatelessWidget {
  final VoidCallback onCast;
  const VaultScreen({super.key, required this.onCast});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final active = state.activeWishes;
    final proof = state.proof;

    return CustomScrollView(
      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      slivers: [
        SliverSafeArea(
          sliver: SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(MW.gutter + 4, 22, MW.gutter, 0),
              child: const Reveal(child: GlowTitle('Proof Vault', size: 31)),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(MW.gutter + 4, 26, MW.gutter, 0),
            child: Reveal(delay: const Duration(milliseconds: 80), child: _Hero(count: proof.length)),
          ),
        ),
        SliverToBoxAdapter(
          child: Reveal(
            delay: const Duration(milliseconds: 160),
            child: SizedBox(
              height: 150,
              child: CustomPaint(painter: ConstellationPainter(proof.length), size: Size.infinite),
            ),
          ),
        ),
        if (active.isNotEmpty) ...[
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(MW.gutter + 2, 10, MW.gutter, 12),
              child: SectionHeading('Still glowing', glyph: GlyphKind.spark),
            ),
          ),
          SliverList.builder(
            itemCount: active.length,
            itemBuilder: (_, i) => _ActiveCard(wish: active[i]),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
        ],
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(MW.gutter + 2, 10, MW.gutter, 12),
            child: SectionHeading('Grants & gratitude', glyph: GlyphKind.trophy),
          ),
        ),
        if (proof.isEmpty)
          SliverToBoxAdapter(child: _EmptyProof(onCast: onCast))
        else
          SliverList.builder(
            itemCount: proof.length,
            itemBuilder: (_, i) => ProofRow(wish: proof[i]),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 130)),
      ],
    );
  }
}

class _Hero extends StatelessWidget {
  final int count;
  const _Hero({required this.count});

  @override
  Widget build(BuildContext context) {
    if (count == 0) {
      return Text('YOUR PROOF STARTS HERE', style: MW.display(30).copyWith(shadows: MW.titleGlow));
    }
    return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      Text('$count', style: MW.display(76, color: MW.goldBright).copyWith(shadows: [
        Shadow(color: MW.gold.withValues(alpha: 0.7), blurRadius: 24),
      ])),
      const SizedBox(width: 16),
      Expanded(
        child: Text(
          count == 1 ? 'thing has worked out for you.' : 'things have worked out for you.',
          style: MW.ui(17, color: MW.text, weight: 700, height: 1.35),
        ),
      ),
    ]);
  }
}

class _EmptyProof extends StatelessWidget {
  final VoidCallback onCast;
  const _EmptyProof({required this.onCast});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: MW.gutter),
        child: GlassCard(
          blur: 10,
          radius: 22,
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              'When a wish comes true, or a small win happens, it becomes a star here. '
              'On the hard days, this is where you come to remember.',
              style: MW.ui(15, color: MW.textDim, height: 1.55),
            ),
            const SizedBox(height: 18),
            GlowButton('Record a little win', glyph: GlyphKind.spark, compact: true, onPressed: onCast),
          ]),
        ),
      );
}

class _ActiveCard extends StatelessWidget {
  final Wish wish;
  const _ActiveCard({required this.wish});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(MW.gutter, 0, MW.gutter, 12),
        child: Semantics(
          button: true,
          label: 'Revisit wish: ${wish.text}',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => showRevisitSheet(context, wish),
            child: GlassCard(
              blur: 10,
              radius: 22,
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(wish.text, style: MW.voice(18)),
                    const SizedBox(height: 6),
                    Text(
                      wish.status == WishStatus.closer
                          ? '${wish.luck} luck · getting closer'
                          : '${wish.luck} luck received',
                      style: MW.ui(13, color: MW.goldBright, weight: 800),
                    ),
                    const SizedBox(height: 10),
                    _StepsStrip(wish: wish),
                  ]),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
                  decoration: BoxDecoration(
                    color: MW.glassStrong,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0x40FFFFFF)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('Revisit', style: MW.ui(13, color: Colors.white, weight: 800)),
                    const Glyph(GlyphKind.chevronRight, size: 16, color: Colors.white, stroke: 2),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      );
}

/// Under a wish: how far its small steps have come, or an invitation to make
/// some. Opens the steps sheet.
class _StepsStrip extends StatelessWidget {
  final Wish wish;
  const _StepsStrip({required this.wish});

  void _open(BuildContext context) {
    showStepsSheet(
      context,
      wish.id,
      onRevisit: () {
        if (!context.mounted) return;
        showRevisitSheet(context, context.read<AppState>().myWish(wish.id) ?? wish);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = wish.progress;
    final empty = p.total == 0;
    return Semantics(
      button: true,
      label: empty ? 'Break this wish into small steps' : 'Small steps, ${p.done} of ${p.total} done',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _open(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: empty
              ? Row(mainAxisSize: MainAxisSize.min, children: [
                  const Glyph(GlyphKind.starPlus, size: 15, color: MW.lilac, stroke: 1.7),
                  const SizedBox(width: 7),
                  Text('Break it into small steps', style: MW.ui(13.5, color: MW.lilac, weight: 800)),
                ])
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${p.done} of ${p.total} small steps',
                      style: MW.ui(12.5, color: p.done == p.total ? MW.goldBright : MW.textDim, weight: 800)),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: Stack(children: [
                      Container(height: 5, color: const Color(0x26FFFFFF)),
                      FractionallySizedBox(
                        widthFactor: (p.done / p.total).clamp(0.0, 1.0),
                        child: Container(height: 5, decoration: const BoxDecoration(gradient: MW.glow)),
                      ),
                    ]),
                  ),
                ]),
        ),
      ),
    );
  }
}

/// All your proof, drawn as stars joined into one constellation. With no
/// proof yet it shows the same shape unlit, as something waiting to be filled.
class ConstellationPainter extends CustomPainter {
  final int count;
  ConstellationPainter(this.count);

  static const _slots = 9;

  @override
  void paint(Canvas canvas, Size size) {
    final lit = math.min(count, _slots);
    final pts = <Offset>[
      for (var i = 0; i < _slots; i++)
        Offset(
          size.width * (0.08 + 0.84 * (i / (_slots - 1))),
          size.height * (0.56 - 0.2 * math.sin(i * 0.8) + 0.07 * math.cos(i * 2.7)),
        ),
    ];

    for (var i = 0; i < _slots - 1; i++) {
      final both = i + 1 < lit;
      canvas.drawLine(
        pts[i],
        pts[i + 1],
        Paint()
          ..strokeWidth = both ? 1.2 : 0.8
          ..color = both ? MW.goldBright.withValues(alpha: 0.7) : Colors.white.withValues(alpha: 0.2),
      );
    }
    for (var i = 0; i < _slots; i++) {
      final on = i < lit;
      final r = on ? 6.5 + (i % 3) * 1.6 : 3.4;
      if (on) {
        canvas.drawCircle(
          pts[i],
          r * 3.4,
          Paint()
            ..shader = RadialGradient(colors: [
              MW.gold.withValues(alpha: 0.5),
              Colors.transparent,
            ]).createShader(Rect.fromCircle(center: pts[i], radius: r * 3.4)),
        );
        canvas.drawPath(starPath(pts[i], r * 1.5, pinch: 0.1), Paint()..color = Colors.white);
      } else {
        canvas.drawCircle(pts[i], 2.2, Paint()..color = Colors.white.withValues(alpha: 0.4));
      }
    }
  }

  @override
  bool shouldRepaint(ConstellationPainter old) => old.count != count;
}

// ---- Revisit sheet ---------------------------------------------------------

const _outcomeHints = <WishStatus, String>{
  WishStatus.granted: 'Celebrate the outcome',
  WishStatus.closer: 'Record progress',
  WishStatus.changed: 'Rewrite the intention',
  WishStatus.doorOpened: 'Record an unexpected opportunity',
  WishStatus.letGo: 'Archive it, without guilt',
};

Future<void> showRevisitSheet(BuildContext context, Wish wish) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (_) => _RevisitSheet(wish: wish),
  );
}

class _RevisitSheet extends StatefulWidget {
  final Wish wish;
  const _RevisitSheet({required this.wish});

  @override
  State<_RevisitSheet> createState() => _RevisitSheetState();
}

class _RevisitSheetState extends State<_RevisitSheet> {
  final _note = TextEditingController();
  late final _rewrite = TextEditingController(text: widget.wish.text);
  WishStatus? _picked;

  @override
  void dispose() {
    _note.dispose();
    _rewrite.dispose();
    super.dispose();
  }

  String get _noteHint => switch (_picked) {
        WishStatus.granted => 'How did it happen? (optional)',
        WishStatus.closer => 'What progress did you notice? (optional)',
        WishStatus.doorOpened => 'What opened up instead? (optional)',
        _ => 'A note (optional)',
      };

  Future<void> _save() async {
    final status = _picked;
    if (status == null) return;
    final state = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    final rewritten = _rewrite.text.trim();
    await state.resolve(
      widget.wish.id,
      // A rewritten intention stays open as a fresh active wish.
      status == WishStatus.changed ? WishStatus.active : status,
      note: _note.text,
      newText: status == WishStatus.changed && rewritten.isNotEmpty ? rewritten : null,
    );
    nav.pop();
    if (status == WishStatus.granted) {
      Haptics.heavy();
      messenger.showSnackBar(const SnackBar(
        content: Text('Evidence unlocked. Added to your Proof Vault.'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final options = WishStatus.values.where((s) => s != WishStatus.active);
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: Color(0x59FFFFFF))),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xE6372A80), Color(0xF21A1146)],
            ),
          ),
          padding: EdgeInsets.fromLTRB(MW.gutter, 12, MW.gutter, MediaQuery.viewInsetsOf(context).bottom + 20),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(color: Colors.white38, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 20),
                const SectionHeading('Revisit your wish', glyph: GlyphKind.spark),
                const SizedBox(height: 12),
                Text(widget.wish.text, style: MW.voice(19)),
                const SizedBox(height: 14),
                const Hairline(),
                for (final s in options) ...[
                  _OutcomeRow(status: s, selected: _picked == s, onTap: () => setState(() => _picked = s)),
                  if (_picked == s) _detail(s),
                  const Hairline(),
                ],
                const SizedBox(height: 20),
                GlowButton('Save', onPressed: _picked == null ? null : _save),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _detail(WishStatus s) {
    if (s == WishStatus.letGo) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 16, left: 54),
        child: Text('Letting go is part of it. No guilt, ever.', style: MW.ui(14.5, color: MW.textDim)),
      );
    }
    final rewriting = s == WishStatus.changed;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16, left: 54),
      child: TextField(
        controller: rewriting ? _rewrite : _note,
        maxLines: rewriting ? 3 : 2,
        minLines: 1,
        cursorColor: MW.lilac,
        style: MW.voice(16),
        decoration: InputDecoration(
          hintText: rewriting ? null : _noteHint,
          hintStyle: MW.ui(15, color: MW.textFaint),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
          enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: MW.hairline)),
          focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: MW.lilac)),
        ),
      ),
    );
  }
}

class _OutcomeRow extends StatelessWidget {
  final WishStatus status;
  final bool selected;
  final VoidCallback onTap;
  const _OutcomeRow({required this.status, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: selected,
        label: status.label,
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            Haptics.selection();
            onTap();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 13),
            child: Row(children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 240),
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: selected ? MW.glow : null,
                  color: selected ? null : MW.glass,
                  border: Border.all(color: selected ? Colors.white54 : MW.hairline),
                  boxShadow: selected ? [BoxShadow(color: MW.violet.withValues(alpha: 0.5), blurRadius: 14)] : null,
                ),
                alignment: Alignment.center,
                child: Glyph(status.glyph,
                    size: 21,
                    color: selected ? Colors.white : MW.lilac,
                    filled: status == WishStatus.granted,
                    stroke: 1.7),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(status.label, style: MW.ui(16, color: Colors.white, weight: 800)),
                  Text(_outcomeHints[status] ?? '', style: MW.ui(12.5, color: MW.textFaint)),
                ]),
              ),
              AnimatedOpacity(
                opacity: selected ? 1 : 0,
                duration: const Duration(milliseconds: 200),
                child: const Glyph(GlyphKind.check, size: 20, color: MW.goldBright, stroke: 2.4),
              ),
            ]),
          ),
        ),
      );
}
