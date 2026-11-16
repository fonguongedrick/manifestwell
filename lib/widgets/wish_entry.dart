import 'package:flutter/material.dart';
import '../utils/haptics.dart';
import 'package:provider/provider.dart';

import '../models/wish.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'effects.dart';
import 'glyphs.dart';
import 'ui.dart';

String timeAgo(DateTime t, DateTime now) {
  final d = now.difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  if (d.inHours < 24) return '${d.inHours}h ago';
  return '${d.inDays}d ago';
}

/// One wish in the Well: a frosted card with an anonymous avatar, the words,
/// a luck count and the SEND LUCK pill.
class WishEntry extends StatefulWidget {
  final Wish wish;
  const WishEntry({super.key, required this.wish});

  @override
  State<WishEntry> createState() => _WishEntryState();
}

class _WishEntryState extends State<WishEntry> {
  int _burst = 0;

  Future<void> _send() async {
    final state = context.read<AppState>();
    final wasUnlocked = state.goldenOrbUnlocked;
    final sent = await state.sendLuck(widget.wish.id);
    if (!sent) return;
    // Two quick pulses read as a flutter, not a tap.
    Haptics.medium();
    Future.delayed(const Duration(milliseconds: 90), Haptics.light);
    setState(() => _burst++);
    if (!wasUnlocked && state.goldenOrbUnlocked && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Five wishes lifted today. Your golden orb is unlocked.'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.wish;
    final sent = context.select<AppState, bool>((s) => s.hasSentLuck(w.id));
    final spark = w.kind == WishKind.spark;
    final meta = w.isMine
        ? 'Your wish · ${timeAgo(w.createdAt, DateTime.now())}'
        : '${spark ? 'Daily spark' : w.category.label} · ${timeAgo(w.createdAt, DateTime.now())}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(MW.gutter, 0, MW.gutter, 14),
      child: GlassCard(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            AnonAvatar(seed: w.id, glyph: spark ? GlyphKind.spark : w.category.glyph, mine: w.isMine),
            const SizedBox(width: 14),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(w.text, style: MW.voice(18.5)),
              ),
            ),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            LuckChip(count: w.luck),
            const SizedBox(width: 10),
            if (w.isMine)
              Expanded(
                child: Text('luck received',
                    style: MW.ui(14, color: MW.textDim, weight: 700)),
              )
            else
              Expanded(
                child: Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
                  sent
                      ? const _SentPill()
                      : GlowButton('Send luck', glyph: GlyphKind.spark, compact: true, onPressed: _send),
                  StarBurst(trigger: _burst),
                ]),
              ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            if (!w.isMine && !w.isSeed && context.read<AppState>().hasBackend)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => showReportSheet(context, w.id),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
                  child: Text('Report', style: MW.ui(12, color: MW.textFaint, weight: 700)),
                ),
              ),
            const Spacer(),
            Text(meta, style: MW.ui(12, color: MW.textFaint, weight: 600)),
          ]),
        ]),
      ),
    );
  }
}

/// A round avatar that stays anonymous: a soft tinted orb with the wish's
/// category glyph, never a name or photo.
class AnonAvatar extends StatelessWidget {
  final String seed;
  final GlyphKind glyph;
  final bool mine;
  final double size;
  const AnonAvatar({
    super.key,
    required this.seed,
    required this.glyph,
    this.mine = false,
    this.size = 46,
  });

  static const _tints = [
    [Color(0xFFEBDDFF), Color(0xFFB993F5)],
    [Color(0xFFD8E6FF), Color(0xFF8FB2F5)],
    [Color(0xFFFFE0F3), Color(0xFFE79BD6)],
    [Color(0xFFDFF3FF), Color(0xFF8ED0F0)],
  ];

  @override
  Widget build(BuildContext context) {
    final tint = mine
        ? const [Color(0xFFFFF1BF), Color(0xFFF2C14E)]
        : _tints[seed.codeUnits.fold<int>(0, (a, b) => a + b) % _tints.length];
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: tint,
        ),
        boxShadow: mine ? [BoxShadow(color: MW.gold.withValues(alpha: 0.5), blurRadius: 14)] : null,
      ),
      alignment: Alignment.center,
      child: Glyph(mine ? GlyphKind.spark : glyph,
          size: size * 0.5, color: const Color(0xFF3B2A7C), filled: mine, stroke: 1.7),
    );
  }
}

/// The frosted number pill ("124") beside SEND LUCK. The count rolls up when
/// it changes.
class LuckChip extends StatelessWidget {
  final int count;
  const LuckChip({super.key, required this.count});

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minWidth: 60),
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: MW.glassStrong,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0x40FFFFFF)),
        ),
        alignment: Alignment.center,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 380),
          switchInCurve: Curves.easeOutCubic,
          transitionBuilder: (child, a) => ClipRect(
            child: SlideTransition(
              position: Tween(begin: const Offset(0, 0.7), end: Offset.zero).animate(a),
              child: FadeTransition(opacity: a, child: child),
            ),
          ),
          child: Text(
            '$count',
            key: ValueKey(count),
            style: MW.ui(17, color: Colors.white, weight: 800)
                .copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
          ),
        ),
      );
}

class _SentPill extends StatelessWidget {
  const _SentPill();

  @override
  Widget build(BuildContext context) => Container(
        height: 44,
        decoration: BoxDecoration(
          color: MW.glass,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0x4DFFFFFF)),
        ),
        alignment: Alignment.center,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Glyph(GlyphKind.check, size: 18, color: MW.goldBright, stroke: 2.2),
          const SizedBox(width: 8),
          Text('SENT', style: MW.ui(14, color: MW.textDim, weight: 900).copyWith(letterSpacing: 0.8)),
        ]),
      );
}

/// Asks why, then sends the flag to the admins. Reporting never reveals
/// who wrote the wish or who reported it.
Future<void> showReportSheet(BuildContext context, String wishId) async {
  final state = context.read<AppState>();
  final messenger = ScaffoldMessenger.of(context);
  const reasons = ['Unkind or harmful', 'Personal information', 'Spam or links', 'Something else'];
  final reason = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: MW.inkDeep,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(MW.gutter, 22, MW.gutter, 12),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('REPORT THIS WISH', style: MW.display(20)),
          const SizedBox(height: 6),
          Text('Why does it not belong in the Well?', style: MW.ui(14, color: MW.textDim)),
          const SizedBox(height: 8),
          for (final r in reasons)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(r, style: MW.ui(16, color: MW.text, weight: 700)),
              onTap: () => Navigator.pop(ctx, r),
            ),
        ]),
      ),
    ),
  );
  if (reason == null) return;
  try {
    await state.report(wishId, reason);
    messenger.showSnackBar(const SnackBar(content: Text('Thank you. We will take a look.')));
  } catch (_) {
    messenger.showSnackBar(const SnackBar(content: Text('Could not send the report. Try again.')));
  }
}
