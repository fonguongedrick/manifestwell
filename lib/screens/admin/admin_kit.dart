import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' show DateFormat, NumberFormat;

import 'package:provider/provider.dart';

import '../../models/admin.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/backdrop.dart';
import '../../widgets/glyphs.dart';
import '../../widgets/settings_kit.dart';
import '../../widgets/ui.dart';

const adminDanger = Color(0xFFFF9AA8);

/// The frame every dashboard page shares: the night sky, a back button, and a
/// glowing title.
class AdminPage extends StatelessWidget {
  final String title;
  final Widget child;
  final List<Widget> actions;
  final bool root;
  const AdminPage({super.key, required this.title, required this.child, this.actions = const [], this.root = false});

  @override
  Widget build(BuildContext context) {
    // Admin access is watched live. If it is taken away while a page is open,
    // the page closes rather than sitting there showing errors. (Without a
    // backend there is no admin at all, and the hub explains that itself.)
    final revoked = context.select<AppState, bool>((s) => s.hasBackend && !s.isAdmin);
    if (revoked) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
      });
      return const Scaffold(
        body: Backdrop(child: SafeArea(child: AdminMessage('Admin access has ended for this account.'))),
      );
    }
    return _frame(context);
  }

  Widget _frame(BuildContext context) => Scaffold(
        body: Backdrop(
          child: SafeArea(
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(MW.gutter, 12, MW.gutter, 0),
                child: Row(children: [
                  RoundIconButton(
                    glyph: root ? GlyphKind.close : GlyphKind.chevronLeft,
                    semanticLabel: root ? 'Close' : 'Back',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const Spacer(),
                  ...actions,
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(MW.gutter + 4, 14, MW.gutter, 16),
                child: Align(alignment: Alignment.centerLeft, child: GlowTitle(title, size: 28)),
              ),
              Expanded(child: child),
            ]),
          ),
        ),
      );
}

/// A centred note: an empty list, an error.
class AdminMessage extends StatelessWidget {
  final String text;
  final Widget? action;
  const AdminMessage(this.text, {super.key, this.action});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(text, textAlign: TextAlign.center, style: MW.ui(15, color: MW.textDim, height: 1.5)),
            if (action != null) ...[const SizedBox(height: 8), action!],
          ]),
        ),
      );
}

const adminLoadError = 'Could not load. Check that this account is an admin and you are online.';

/// Builds from a stream with the same loading and error states everywhere.
/// The stream must be created once (in initState), not in build.
class LiveView<T> extends StatelessWidget {
  final Stream<T> stream;
  final Widget Function(BuildContext context, T data) builder;
  const LiveView({super.key, required this.stream, required this.builder});

  @override
  Widget build(BuildContext context) => StreamBuilder<T>(
        stream: stream,
        builder: (context, snap) {
          if (snap.hasError) return const AdminMessage(adminLoadError);
          if (!snap.hasData) return const Center(child: CircularProgressIndicator(color: MW.lilac));
          return builder(context, snap.data as T);
        },
      );
}

/// Like [LiveView] for three streams at once. All three are subscribed
/// together, so they load in parallel rather than one after another.
class LiveView3<A, B, C> extends StatelessWidget {
  final Stream<A> a;
  final Stream<B> b;
  final Stream<C> c;
  final Widget Function(BuildContext context, A a, B b, C c) builder;
  const LiveView3({super.key, required this.a, required this.b, required this.c, required this.builder});

  @override
  Widget build(BuildContext context) => StreamBuilder<A>(
        stream: a,
        builder: (context, sa) => StreamBuilder<B>(
          stream: b,
          builder: (context, sb) => StreamBuilder<C>(
            stream: c,
            builder: (context, sc) {
              if (sa.hasError || sb.hasError || sc.hasError) return const AdminMessage(adminLoadError);
              if (!sa.hasData || !sb.hasData || !sc.hasData) {
                return const Center(child: CircularProgressIndicator(color: MW.lilac));
              }
              return builder(context, sa.data as A, sb.data as B, sc.data as C);
            },
          ),
        ),
      );
}

/// One figure and its caption on a frosted tile.
class MetricTile extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  final String? hint;
  const MetricTile({super.key, required this.label, required this.value, this.color = MW.gold, this.hint});

  @override
  Widget build(BuildContext context) => Semantics(
        container: true,
        label: '$label: $value${hint == null ? '' : ', $hint'}',
        excludeSemantics: true,
        child: GlassCard(
          radius: 20,
          blur: 10,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(NumberFormat.decimalPattern().format(value), style: MW.display(28, color: color)),
            ),
            const SizedBox(height: 6),
            Caps(label, size: 10),
            if (hint != null) ...[
              const SizedBox(height: 4),
              Text(hint!, style: MW.ui(12, color: MW.textFaint, height: 1.3)),
            ],
          ]),
        ),
      );
}

/// A two-column grid of tiles that sizes itself to its content.
class MetricGrid extends StatelessWidget {
  final List<Widget> tiles;
  const MetricGrid({super.key, required this.tiles});

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        const gap = 12.0;
        final w = (c.maxWidth - gap) / 2;
        return Wrap(spacing: gap, runSpacing: gap, children: [
          for (final t in tiles) SizedBox(width: w, child: t),
        ]);
      });
}

/// A hub card that opens one part of the dashboard.
class ModuleCard extends StatelessWidget {
  final GlyphKind glyph;
  final String title;
  final String subtitle;
  final Color tint;
  final int badge;
  final VoidCallback onTap;
  const ModuleCard({
    super.key,
    required this.glyph,
    required this.title,
    required this.subtitle,
    required this.tint,
    required this.onTap,
    this.badge = 0,
  });

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: title,
        hint: badge > 0 ? '$badge waiting. $subtitle' : subtitle,
        excludeSemantics: true,
        child: Pressable(
          onPressed: onTap,
          builder: (_) => GlassCard(
            radius: 22,
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                IconTile(glyph, tint: tint),
                const Spacer(),
                if (badge > 0) _Badge(badge),
              ]),
              const Spacer(),
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: MW.ui(16.5, color: MW.text, weight: 800)),
              const SizedBox(height: 3),
              Text(subtitle,
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: MW.ui(12.5, color: MW.textFaint, height: 1.3)),
            ]),
          ),
        ),
      );
}

class _Badge extends StatelessWidget {
  final int count;
  const _Badge(this.count);

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minWidth: 24),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFFFF5A76),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: const Color(0xFFFF5A76).withValues(alpha: 0.5), blurRadius: 10)],
        ),
        child: Text(count > 99 ? '99+' : '$count',
            textAlign: TextAlign.center, style: MW.ui(12, color: Colors.white, weight: 900)),
      );
}

/// A text field in the sign-in sheet's style, single or multi-line.
class AdminField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final bool obscure;
  final TextInputType? keyboard;
  final VoidCallback? onSubmit;
  final ValueChanged<String>? onChanged;
  final int minLines;
  final int maxLines;
  final int? maxLength;
  const AdminField({
    super.key,
    required this.controller,
    required this.hint,
    this.obscure = false,
    this.keyboard,
    this.onSubmit,
    this.onChanged,
    this.minLines = 1,
    this.maxLines = 1,
    this.maxLength,
  });

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0x1AFFFFFF),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: MW.violet.withValues(alpha: 0.6), width: 1.2),
          ),
          child: TextField(
            controller: controller,
            obscureText: obscure,
            keyboardType: minLines > 1 || maxLines > 1 ? TextInputType.multiline : keyboard,
            minLines: obscure ? 1 : minLines,
            maxLines: obscure ? 1 : maxLines,
            inputFormatters: [if (maxLength != null) LengthLimitingTextInputFormatter(maxLength)],
            autocorrect: false,
            enableSuggestions: false,
            onChanged: onChanged,
            onSubmitted: onSubmit == null ? null : (_) => onSubmit!(),
            cursorColor: MW.lilac,
            style: MW.ui(16, color: MW.text, weight: 600),
            decoration: InputDecoration(
              border: InputBorder.none,
              hintText: hint,
              hintStyle: MW.ui(16, color: MW.textFaint),
            ),
          ),
        ),
        if (maxLength != null)
          ListenableBuilder(
            listenable: controller,
            builder: (_, _) => Padding(
              padding: const EdgeInsets.only(top: 6, right: 6),
              child: Text('${controller.text.characters.length}/$maxLength',
                  style: MW.ui(12, color: MW.textFaint, weight: 700)),
            ),
          ),
      ]);
}

class _Pill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _Pill({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: selected,
        label: label,
        excludeSemantics: true,
        child: Pressable(
          onPressed: onTap,
          builder: (_) => AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: selected ? MW.glow : null,
              color: selected ? null : MW.glass,
              border: Border.all(color: Colors.white.withValues(alpha: selected ? 0.5 : 0.22)),
            ),
            child: Text(label, style: MW.ui(13.5, color: selected ? Colors.white : MW.textDim, weight: 800)),
          ),
        ),
      );
}

/// A row of pills that scrolls sideways; the chosen one glows.
class FilterPills<T> extends StatelessWidget {
  final List<(T, String)> options;
  final T value;
  final ValueChanged<T> onChanged;
  const FilterPills({super.key, required this.options, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: MW.gutter),
        child: Row(children: [
          for (final o in options)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _Pill(label: o.$2, selected: o.$1 == value, onTap: () => onChanged(o.$1)),
            ),
        ]),
      );
}

/// The same pills, wrapping onto new lines, for use inside a card.
class FilterPillsInline<T> extends StatelessWidget {
  final List<(T, String)> options;
  final T value;
  final ValueChanged<T> onChanged;
  const FilterPillsInline({super.key, required this.options, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) => Wrap(spacing: 8, runSpacing: 8, children: [
        for (final o in options) _Pill(label: o.$2, selected: o.$1 == value, onTap: () => onChanged(o.$1)),
      ]);
}

/// A yes/no question before something that can't be undone. Returns true on yes.
Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String body,
  required String confirm,
}) async {
  final yes = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: MW.inkDeep,
      title: Text(title, style: MW.heading(18)),
      content: Text(body, style: MW.ui(14.5, color: MW.textDim, height: 1.45)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(confirm)),
      ],
    ),
  );
  return yes == true;
}

/// Runs an admin action and says so if it fails, instead of failing silently.
Future<bool> runAdmin(BuildContext context, Future<void> Function() action, {String? done}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    await action();
    if (done != null) messenger?.showSnackBar(SnackBar(content: Text(done)));
    return true;
  } on AdminActionException catch (e) {
    // The server explained what is wrong, in words an admin can act on.
    messenger?.showSnackBar(SnackBar(content: Text(e.message)));
    return false;
  } catch (_) {
    messenger?.showSnackBar(const SnackBar(content: Text('That did not go through. Check your connection and try again.')));
    return false;
  }
}

/// "Today 14:05", "Yesterday 09:30", "Nov 3, 18:22".
String whenLabel(DateTime? at, {DateTime? now}) {
  if (at == null) return 'Just now';
  final clock = now ?? DateTime.now();
  final local = at.toLocal();
  final today = DateTime(clock.year, clock.month, clock.day);
  final that = DateTime(local.year, local.month, local.day);
  final days = today.difference(that).inDays;
  final time = DateFormat('HH:mm').format(local);
  if (days == 0) return 'Today $time';
  if (days == 1) return 'Yesterday $time';
  return '${DateFormat('MMM d').format(local)}, $time';
}

/// First few characters of an id: enough to tell people apart, not to find them.
String shortId(String? id) => id == null || id.isEmpty ? 'unknown' : id.substring(0, id.length < 6 ? id.length : 6);

/// Wishes cast per day: one bar a day, the busiest labelled.
class DailyBars extends StatelessWidget {
  final List<DailyCount> days;
  const DailyBars({super.key, required this.days});

  @override
  Widget build(BuildContext context) {
    final total = days.fold(0, (a, d) => a + d.count);
    final peak = days.isEmpty ? 0 : days.map((d) => d.count).reduce((a, b) => a > b ? a : b);
    return Semantics(
      label: 'Wishes cast per day over the last ${days.length} days: $total in total, '
          'at most $peak in one day.',
      excludeSemantics: true,
      child: SizedBox(height: 150, child: CustomPaint(painter: _BarsPainter(days), size: Size.infinite)),
    );
  }
}

class _BarsPainter extends CustomPainter {
  final List<DailyCount> days;
  _BarsPainter(this.days);

  @override
  void paint(Canvas canvas, Size size) {
    if (days.isEmpty) return;
    const labelH = 18.0;
    const topPad = 18.0;
    final chartH = size.height - labelH - topPad;
    final base = topPad + chartH;
    final peak = days.map((d) => d.count).reduce((a, b) => a > b ? a : b);
    final slot = size.width / days.length;
    final barW = (slot * 0.58).clamp(4.0, 22.0);

    canvas.drawLine(
      Offset(0, base),
      Offset(size.width, base),
      Paint()
        ..color = MW.hairline
        ..strokeWidth = 1,
    );

    for (var i = 0; i < days.length; i++) {
      final cx = slot * i + slot / 2;
      final n = days[i].count;
      // A day with no wishes still shows a sliver, so it reads as "nothing"
      // and not as a gap in the data.
      final h = peak == 0 ? 2.0 : (n / peak * chartH).clamp(2.0, chartH);
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(cx - barW / 2, base - h, barW, h),
        const Radius.circular(5),
      );
      canvas.drawRRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: n == 0 ? const [Color(0x33FFFFFF), Color(0x33FFFFFF)] : const [Color(0xFF55A9FF), Color(0xFFA65DFF)],
          ).createShader(rect.outerRect),
      );
      if (n == peak && n > 0) _text(canvas, size.width, '$n', Offset(cx, base - h - 4), MW.gold, 12, bottom: true);
    }

    for (final i in {0, days.length ~/ 2, days.length - 1}) {
      _text(canvas, size.width, DateFormat('MMM d').format(days[i].day),
          Offset(slot * i + slot / 2, base + 4), MW.textFaint, 11);
    }
  }

  /// Draws [s] centred on [at], nudged to stay inside the canvas.
  void _text(Canvas canvas, double width, String s, Offset at, Color color, double size, {bool bottom = false}) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: MW.ui(size, color: color, weight: 800)),
      textDirection: TextDirection.ltr,
    )..layout();
    final x = (at.dx - tp.width / 2).clamp(0.0, (width - tp.width).clamp(0.0, double.infinity));
    tp.paint(canvas, Offset(x, bottom ? at.dy - tp.height : at.dy));
  }

  @override
  bool shouldRepaint(_BarsPainter old) => old.days != days;
}
