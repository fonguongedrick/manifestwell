import 'package:flutter/material.dart';

import '../theme.dart';
import '../utils/haptics.dart';
import 'glyphs.dart';
import 'ui.dart';

const _danger = Color(0xFFFF7A90);

Future<T?> _showSheet<T>(BuildContext context, WidgetBuilder builder) => showModalBottomSheet<T>(
      context: context,
      backgroundColor: MW.inkDeep,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: builder,
    );

/// Asks before doing something that can't be undone. Resolves to true only on
/// an explicit confirm; swiping the sheet away or tapping Cancel is false.
Future<bool> showConfirmSheet(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  String cancelLabel = 'Cancel',
  bool destructive = false,
}) async {
  final yes = await _showSheet<bool>(
    context,
    (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(MW.gutter, 4, MW.gutter, 12),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title.toUpperCase(), style: MW.display(21)),
          const SizedBox(height: 12),
          Text(message, style: MW.ui(15, color: MW.textDim, height: 1.55)),
          const SizedBox(height: 24),
          destructive
              ? _DangerButton(confirmLabel, onPressed: () => Navigator.pop(ctx, true))
              : GlowButton(confirmLabel, onPressed: () => Navigator.pop(ctx, true)),
          Center(child: QuietLink(cancelLabel, onPressed: () => Navigator.pop(ctx, false))),
        ]),
      ),
    ),
  );
  return yes ?? false;
}

/// A short, calm explainer made of icon-led points.
Future<void> showInfoSheet(
  BuildContext context, {
  required String title,
  required List<(GlyphKind, String, String)> points,
}) =>
    _showSheet<void>(
      context,
      (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(MW.gutter, 4, MW.gutter, 12),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title.toUpperCase(), style: MW.display(21)),
            const SizedBox(height: 18),
            for (final p in points) ...[
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Glyph(p.$1, size: 22, color: MW.lilac, stroke: 1.7),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(p.$2, style: MW.ui(15.5, color: MW.text, weight: 800)),
                    const SizedBox(height: 3),
                    Text(p.$3, style: MW.ui(14, color: MW.textDim, height: 1.5)),
                  ]),
                ),
              ]),
              const SizedBox(height: 18),
            ],
            GlowButton('Got it', onPressed: () => Navigator.pop(ctx)),
          ]),
        ),
      ),
    );

/// The one-time offer to turn notifications on, shown right after the first
/// wish goes into the Well. Resolves to true only if they accept.
Future<bool> showPushOfferSheet(BuildContext context) async {
  final yes = await _showSheet<bool>(
    context,
    (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(MW.gutter, 4, MW.gutter, 12),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(
            child: Container(
              width: 64,
              height: 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: MW.glow,
                boxShadow: [BoxShadow(color: MW.violet.withValues(alpha: 0.5), blurRadius: 24)],
              ),
              child: const Glyph(GlyphKind.bell, size: 30, color: Colors.white, stroke: 1.8),
            ),
          ),
          const SizedBox(height: 20),
          Text('KNOW WHEN LUCK ARRIVES', style: MW.display(21)),
          const SizedBox(height: 12),
          Text(
            'Your wish is in the Well. We can tell you when someone sends it luck, '
            'grouped so you are never flooded, and gently remind you to revisit it '
            'after a month. We never share who sent it.',
            style: MW.ui(15, color: MW.textDim, height: 1.55),
          ),
          const SizedBox(height: 24),
          GlowButton('Turn on notifications', onPressed: () => Navigator.pop(ctx, true)),
          Center(child: QuietLink('Not now', onPressed: () => Navigator.pop(ctx, false))),
        ]),
      ),
    ),
  );
  return yes ?? false;
}

class _DangerButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  const _DangerButton(this.label, {required this.onPressed});

  @override
  Widget build(BuildContext context) => Pressable(
        onPressed: () {
          Haptics.heavy();
          onPressed();
        },
        haptic: false,
        builder: (_) => Container(
          height: 54,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(27),
            color: _danger.withValues(alpha: 0.16),
            border: Border.all(color: _danger.withValues(alpha: 0.85), width: 1.3),
          ),
          child: Text(label.toUpperCase(), style: MW.heading(15, color: _danger)),
        ),
      );
}
