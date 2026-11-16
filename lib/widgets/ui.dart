import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import '../utils/haptics.dart';

import '../theme.dart';
import 'glyphs.dart';

/// Small tracked-out uppercase label.
class Caps extends StatelessWidget {
  final String text;
  final Color color;
  final double size;
  final TextAlign? align;
  const Caps(this.text, {super.key, this.color = MW.textFaint, this.size = 11, this.align});

  @override
  Widget build(BuildContext context) =>
      Text(text.toUpperCase(), textAlign: align, style: MW.caps(color: color, size: size));
}

/// A 1px rule that fades out at both ends.
class Hairline extends StatelessWidget {
  final EdgeInsetsGeometry margin;
  const Hairline({super.key, this.margin = EdgeInsets.zero});

  @override
  Widget build(BuildContext context) => Container(
        height: 1,
        margin: margin,
        decoration: const BoxDecoration(
          gradient: LinearGradient(colors: [Colors.transparent, Color(0x33FFFFFF), Colors.transparent]),
        ),
      );
}

/// Fades and lifts its child in once, after [delay].
class Reveal extends StatefulWidget {
  final Widget child;
  final Duration delay;
  final double dy;
  const Reveal({super.key, required this.child, this.delay = Duration.zero, this.dy = 14});

  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> with SingleTickerProviderStateMixin {
  static const _dur = Duration(milliseconds: 700);
  late final AnimationController _c;
  late final Animation<double> _a;

  @override
  void initState() {
    super.initState();
    final total = _dur + widget.delay;
    _c = AnimationController(vsync: this, duration: total);
    _a = CurvedAnimation(
      parent: _c,
      curve: Interval(widget.delay.inMilliseconds / total.inMilliseconds, 1, curve: Curves.easeOutCubic),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _c.value = 1;
    } else if (_c.status == AnimationStatus.dismissed) {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _a,
        child: widget.child,
        builder: (_, child) => Opacity(
          opacity: _a.value,
          child: Transform.translate(offset: Offset(0, (1 - _a.value) * widget.dy), child: child),
        ),
      );
}

class Pressable extends StatefulWidget {
  final VoidCallback? onPressed;
  final Widget Function(bool pressed) builder;
  final bool haptic;
  const Pressable({super.key, required this.onPressed, required this.builder, this.haptic = true});

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _set(bool v) {
    if (widget.onPressed != null && _down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _set(true),
        onTapUp: (_) => _set(false),
        onTapCancel: () => _set(false),
        onTap: widget.onPressed == null
            ? null
            : () {
                if (widget.haptic) Haptics.selection();
                widget.onPressed!();
              },
        child: AnimatedScale(
          scale: _down ? 0.97 : 1,
          duration: const Duration(milliseconds: 110),
          curve: Curves.easeOut,
          child: widget.builder(_down),
        ),
      );
}

/// The primary action: the glowing purple-to-blue pill from the brand sample.
/// [isLoading] swaps the label for a spinner (pattern from BraidsTribe's
/// AppButton).
class GlowButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final GlyphKind? glyph;
  final bool isLoading;
  final bool compact;
  final bool expand;
  const GlowButton(
    this.label, {
    super.key,
    required this.onPressed,
    this.glyph,
    this.isLoading = false,
    this.compact = false,
    this.expand = true,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !isLoading;
    final height = compact ? 44.0 : 56.0;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: Pressable(
        onPressed: enabled ? onPressed : null,
        builder: (_) => Container(
          width: expand ? double.infinity : null,
          height: height,
          padding: EdgeInsets.symmetric(horizontal: compact ? 22 : 28),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(height / 2),
            gradient: enabled || isLoading ? MW.glow : null,
            color: enabled || isLoading ? null : MW.glass,
            border: Border.all(
              color: Colors.white.withValues(alpha: enabled || isLoading ? 0.55 : 0.2),
              width: 1.2,
            ),
            boxShadow: enabled || isLoading
                ? [
                    BoxShadow(color: MW.violet.withValues(alpha: 0.55), blurRadius: 22, offset: const Offset(-4, 4)),
                    BoxShadow(color: MW.sky.withValues(alpha: 0.4), blurRadius: 22, offset: const Offset(4, 4)),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: isLoading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : Row(mainAxisSize: MainAxisSize.min, children: [
                  Flexible(
                    child: Text(
                      label.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: MW.ui(compact ? 14 : 16, color: enabled ? Colors.white : MW.textFaint, weight: 900)
                          .copyWith(letterSpacing: 0.8),
                    ),
                  ),
                  if (glyph != null) ...[
                    const SizedBox(width: 10),
                    Glyph(glyph!,
                        size: compact ? 18 : 22,
                        color: enabled ? MW.gold : MW.textFaint,
                        filled: glyph == GlyphKind.spark || glyph == GlyphKind.starPlus,
                        stroke: 1.8),
                  ],
                ]),
        ),
      ),
    );
  }
}

/// Secondary action: frosted pill.
class GhostButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final Widget? leading;
  const GhostButton(this.label, {super.key, required this.onPressed, this.leading});

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: Pressable(
          onPressed: onPressed,
          builder: (_) => Container(
            width: double.infinity,
            height: 56,
            decoration: BoxDecoration(
              color: MW.glass,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: const Color(0x4DFFFFFF)),
            ),
            alignment: Alignment.center,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (leading != null) ...[leading!, const SizedBox(width: 10)],
              Text(label, style: MW.ui(15.5, color: MW.text, weight: 800)),
            ]),
          ),
        ),
      );
}

/// Tertiary action: quiet text.
class QuietLink extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final Color color;
  const QuietLink(this.label, {super.key, required this.onPressed, this.color = MW.textDim});

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: Pressable(
          onPressed: onPressed,
          haptic: false,
          builder: (_) => Container(
            height: 48,
            alignment: Alignment.center,
            child: Text(label, style: MW.ui(14.5, color: color, weight: 700)),
          ),
        ),
      );
}

/// Round frosted icon button.
class RoundIconButton extends StatelessWidget {
  final GlyphKind glyph;
  final VoidCallback onPressed;
  final String semanticLabel;
  const RoundIconButton({
    super.key,
    required this.glyph,
    required this.onPressed,
    required this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: semanticLabel,
        excludeSemantics: true,
        child: Pressable(
          onPressed: onPressed,
          builder: (_) => Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: MW.glassStrong,
              border: Border.all(color: MW.hairline),
            ),
            alignment: Alignment.center,
            child: Glyph(glyph, size: 20, color: MW.text, stroke: 1.7),
          ),
        ),
      );
}

/// Frosted container, the sample's core surface. Blurs the nebula behind it.
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? borderColor;
  final double blur;
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 24,
    this.borderColor,
    this.blur = 14,
  });

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(radius);
    final surface = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: shape,
        border: Border.all(color: borderColor ?? const Color(0x40FFFFFF)),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0x33FFFFFF), Color(0x14FFFFFF)],
        ),
      ),
      child: Padding(padding: padding, child: child),
    );
    return ClipRRect(
      borderRadius: shape,
      child: blur <= 0
          ? surface
          : BackdropFilter(filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur), child: surface),
    );
  }
}

/// A section title in Cinzel with an optional gold glyph, as in the sample's
/// RECENT WISHES and GRANTS & GRATITUDE.
class SectionHeading extends StatelessWidget {
  final String title;
  final GlyphKind? glyph;
  final Widget? trailing;
  const SectionHeading(this.title, {super.key, this.glyph, this.trailing});

  @override
  Widget build(BuildContext context) => Row(children: [
        Flexible(child: Text(title.toUpperCase(), style: MW.heading(18), overflow: TextOverflow.ellipsis)),
        if (glyph != null) ...[
          const SizedBox(width: 8),
          Glyph(glyph!, size: 18, color: MW.gold, filled: glyph == GlyphKind.spark, stroke: 1.6),
        ],
        if (trailing != null) ...[const Spacer(), trailing!],
      ]);
}

/// The glowing wordmark with sparkles, as at the top of the sample.
class GlowTitle extends StatelessWidget {
  final String text;
  final double size;
  const GlowTitle(this.text, {super.key, this.size = 30});

  @override
  Widget build(BuildContext context) => Stack(clipBehavior: Clip.none, children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Text(
            text.toUpperCase(),
            style: MW.display(size).copyWith(shadows: MW.titleGlow),
          ),
        ),
        Positioned(left: -6, top: -10, child: _spark(16)),
        Positioned(right: -4, top: -6, child: _spark(9)),
        Positioned(left: size * 3.1, bottom: -8, child: _spark(7)),
      ]);

  Widget _spark(double s) =>
      Glyph(GlyphKind.spark, size: s, color: Colors.white, filled: true);
}

/// A white social sign-in button. Adapted from BraidsTribe's SquareTile, using
/// the same Apple and Google logo assets.
class SocialButton extends StatelessWidget {
  final String label;
  final String assetPath;
  final VoidCallback onPressed;
  const SocialButton({
    super.key,
    required this.label,
    required this.assetPath,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: Pressable(
          onPressed: onPressed,
          builder: (_) => Container(
            width: double.infinity,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 14, offset: const Offset(0, 6))],
            ),
            alignment: Alignment.center,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Image.asset(assetPath, height: 24),
              const SizedBox(width: 12),
              Text(label, style: MW.ui(15.5, color: const Color(0xFF1A1240), weight: 800)),
            ]),
          ),
        ),
      );
}

/// Dims [child] and shows a spinner while [isLoading]. Ported from BraidsTribe
/// (Components/core/loading_overlay.dart).
class LoadingOverlay extends StatelessWidget {
  final bool isLoading;
  final Widget child;
  const LoadingOverlay({super.key, required this.isLoading, required this.child});

  @override
  Widget build(BuildContext context) => Stack(children: [
        child,
        if (isLoading)
          Positioned.fill(
            child: ColoredBox(
              color: MW.inkDeep.withValues(alpha: 0.6),
              child: const Center(
                child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(MW.lilac)),
              ),
            ),
          ),
      ]);
}

/// Segmented switch with a sliding glowing thumb.
class SlidingSegment<T> extends StatelessWidget {
  final List<(T, String)> options;
  final T value;
  final ValueChanged<T> onChanged;
  const SlidingSegment({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final i = options.indexWhere((o) => o.$1 == value).clamp(0, options.length - 1);
    return Container(
      height: 52,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: MW.glass,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: const Color(0x40FFFFFF)),
      ),
      child: Stack(children: [
        AnimatedAlign(
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
          alignment: Alignment(options.length == 1 ? 0 : -1 + 2 * i / (options.length - 1), 0),
          child: FractionallySizedBox(
            widthFactor: 1 / options.length,
            heightFactor: 1,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                gradient: MW.glow,
                border: Border.all(color: Colors.white.withValues(alpha: 0.5)),
                boxShadow: [BoxShadow(color: MW.violet.withValues(alpha: 0.5), blurRadius: 16)],
              ),
            ),
          ),
        ),
        Row(children: [
          for (final o in options)
            Expanded(
              child: Semantics(
                button: true,
                selected: o.$1 == value,
                label: o.$2,
                excludeSemantics: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    if (o.$1 != value) {
                      Haptics.selection();
                      onChanged(o.$1);
                    }
                  },
                  child: Center(
                    child: AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 200),
                      style: MW.ui(14.5, color: o.$1 == value ? Colors.white : MW.textDim, weight: 800),
                      child: Text(o.$2),
                    ),
                  ),
                ),
              ),
            ),
        ]),
      ]),
    );
  }
}

/// Multi-line input with the glowing violet outline from the sample's
/// "Make a wish" field.
class GlowInput extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;
  final int minLines;
  final int maxLines;
  final int? maxLength;
  final ValueChanged<String>? onChanged;
  final double fontSize;
  const GlowInput({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.hint,
    this.minLines = 3,
    this.maxLines = 5,
    this.maxLength,
    this.onChanged,
    this.fontSize = 18,
  });

  @override
  Widget build(BuildContext context) {
    final focused = focusNode.hasFocus;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: const Color(0x1AFFFFFF),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: MW.violet.withValues(alpha: focused ? 0.95 : 0.6), width: 1.4),
        boxShadow: [BoxShadow(color: MW.violet.withValues(alpha: focused ? 0.45 : 0.22), blurRadius: 18)],
      ),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        minLines: minLines,
        maxLines: maxLines,
        maxLength: maxLength,
        buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
        onChanged: onChanged,
        textCapitalization: TextCapitalization.sentences,
        cursorColor: MW.lilac,
        style: MW.voice(fontSize, weight: 600),
        decoration: InputDecoration(
          isCollapsed: true,
          border: InputBorder.none,
          hintText: hint,
          hintStyle: MW.voice(fontSize, color: MW.textFaint, weight: 500),
        ),
      ),
    );
  }
}
