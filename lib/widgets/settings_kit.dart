import 'package:flutter/material.dart';

import '../theme.dart';
import '../utils/haptics.dart';
import 'glyphs.dart';
import 'ui.dart';

const _danger = Color(0xFFFF7A90);

// Labels sit straight on the star field, so they get a soft dark halo to stay
// readable wherever a bright star happens to fall behind them.
final _halo = [Shadow(color: MW.inkDeep.withValues(alpha: 0.95), blurRadius: 7)];

/// A titled group of rows inside one frosted card, like a system settings list
/// but in the app's own material.
class SettingsSection extends StatelessWidget {
  final String? label;
  final String? footer;
  final List<Widget> children;
  const SettingsSection({super.key, this.label, this.footer, required this.children});

  // Rule starts under the title text, past the icon tile.
  static const _inset = EdgeInsets.only(left: 64);

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (label != null)
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 10),
            child: Text(
              label!.toUpperCase(),
              style: MW.caps(color: MW.textDim, size: 11.5).copyWith(shadows: _halo),
            ),
          ),
        GlassCard(
          padding: EdgeInsets.zero,
          radius: 22,
          child: Column(children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const Hairline(margin: _inset),
              children[i],
            ],
          ]),
        ),
        if (footer != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 10, 8, 0),
            child: Text(
              footer!,
              style: MW.ui(12.5, color: MW.textDim, height: 1.45).copyWith(shadows: _halo),
            ),
          ),
      ]);
}

/// A rounded-square icon tile, the visual anchor of every settings row.
class IconTile extends StatelessWidget {
  final GlyphKind glyph;
  final Color tint;
  const IconTile(this.glyph, {super.key, this.tint = MW.violet});

  @override
  Widget build(BuildContext context) => Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(11),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [tint.withValues(alpha: 0.95), tint.withValues(alpha: 0.55)],
          ),
          border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
          boxShadow: [BoxShadow(color: tint.withValues(alpha: 0.35), blurRadius: 10)],
        ),
        child: Glyph(glyph, size: 19, color: Colors.white, stroke: 1.7),
      );
}

class SettingsRow extends StatefulWidget {
  final GlyphKind glyph;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color tint;
  final bool destructive;

  /// Shown after the title when the row opens something and has no trailing.
  final bool chevron;

  const SettingsRow({
    super.key,
    required this.glyph,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.tint = MW.violet,
    this.destructive = false,
    this.chevron = true,
  });

  @override
  State<SettingsRow> createState() => _SettingsRowState();
}

class _SettingsRowState extends State<SettingsRow> {
  bool _down = false;

  void _set(bool v) {
    if (widget.onTap != null && _down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final tint = widget.destructive ? _danger : widget.tint;
    final trailing = widget.trailing ??
        (widget.onTap != null && widget.chevron
            ? const Glyph(GlyphKind.chevronRight, size: 18, color: MW.textFaint)
            : null);
    return Semantics(
      button: widget.onTap != null,
      label: widget.title,
      hint: widget.subtitle,
      excludeSemantics: widget.onTap != null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _set(true),
        onTapUp: (_) => _set(false),
        onTapCancel: () => _set(false),
        onTap: widget.onTap == null
            ? null
            : () {
                Haptics.selection();
                widget.onTap!();
              },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          constraints: const BoxConstraints(minHeight: 60),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          color: _down ? Colors.white.withValues(alpha: 0.07) : Colors.transparent,
          child: Row(children: [
            IconTile(widget.glyph, tint: tint),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: MW.ui(16, color: widget.destructive ? _danger : MW.text, weight: 700),
                ),
                if (widget.subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(widget.subtitle!,
                        style: MW.ui(13, color: MW.textFaint, height: 1.35)),
                  ),
              ]),
            ),
            if (trailing != null) ...[const SizedBox(width: 10), trailing],
          ]),
        ),
      ),
    );
  }
}

/// The app's own on/off switch: the violet-to-blue glow when on, frosted glass
/// when off.
class GlowSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  final String semanticLabel;
  const GlowSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    required this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) => Semantics(
        toggled: value,
        label: semanticLabel,
        excludeSemantics: true,
        onTap: () => onChanged(!value),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            Haptics.selection();
            onChanged(!value);
          },
          // The visible switch is small; the touch area is not.
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              width: 52,
              height: 31,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: value ? MW.glow : null,
                color: value ? null : const Color(0x33FFFFFF),
                border: Border.all(
                  color: value ? Colors.white.withValues(alpha: 0.55) : const Color(0x40FFFFFF),
                ),
                boxShadow: value
                    ? [BoxShadow(color: MW.violet.withValues(alpha: 0.5), blurRadius: 14)]
                    : null,
              ),
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
                alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  width: 25,
                  height: 25,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.28), blurRadius: 4, offset: const Offset(0, 1.5)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}

/// One figure and its caption, for the profile summary.
class StatCell extends StatelessWidget {
  final int value;
  final String label;
  const StatCell({super.key, required this.value, required this.label});

  @override
  Widget build(BuildContext context) => Semantics(
        label: '$value $label',
        excludeSemantics: true,
        child: Column(children: [
          Text('$value', style: MW.display(27, color: MW.gold)),
          const SizedBox(height: 6),
          Caps(label, size: 9.5, align: TextAlign.center),
        ]),
      );
}

/// The round identity mark: an initial for a signed-in account, a quiet
/// silhouette for a guest.
class ProfileAvatar extends StatelessWidget {
  final String? label;
  final double size;
  const ProfileAvatar({super.key, required this.label, this.size = 66});

  @override
  Widget build(BuildContext context) {
    final signedIn = label != null && label!.isNotEmpty;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: signedIn
            ? MW.glow
            : const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0x40FFFFFF), Color(0x14FFFFFF)],
              ),
        border: Border.all(
          color: signedIn ? MW.gold.withValues(alpha: 0.9) : const Color(0x55FFFFFF),
          width: signedIn ? 1.6 : 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: (signedIn ? MW.violet : Colors.white).withValues(alpha: signedIn ? 0.5 : 0.12),
            blurRadius: 20,
          ),
        ],
      ),
      child: signedIn
          ? Text(label!.characters.first.toUpperCase(), style: MW.display(size * 0.4))
          : Glyph(GlyphKind.user, size: size * 0.42, color: MW.lilac, stroke: 1.7),
    );
  }
}
