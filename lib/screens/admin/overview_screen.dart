import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show NumberFormat;
import 'package:provider/provider.dart';

import '../../models/admin.dart';
import '../../models/wish.dart';
import '../../state/admin_backend.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/glyphs.dart';
import '../../widgets/ui.dart';
import 'admin_kit.dart';

/// The numbers: what is in the Well, how busy it was, who can be reached.
class OverviewScreen extends StatefulWidget {
  const OverviewScreen({super.key});

  @override
  State<OverviewScreen> createState() => _OverviewScreenState();
}

class _OverviewScreenState extends State<OverviewScreen> {
  static const _days = 14;
  late final AdminBackend _tools;
  late Future<OverviewStats> _stats;

  @override
  void initState() {
    super.initState();
    _tools = context.read<AppState>().adminTools!;
    _stats = _tools.loadOverview(days: _days);
  }

  Future<void> _refresh() async {
    final next = _tools.loadOverview(days: _days);
    // A block body, not `=> _stats = next`: setState rejects a closure that
    // returns a Future.
    setState(() {
      _stats = next;
    });
    try {
      await next;
    } catch (_) {
      // The builder shows the error; the refresh indicator just stops.
    }
  }

  @override
  Widget build(BuildContext context) => AdminPage(
        title: 'Overview',
        actions: [RoundIconButton(glyph: GlyphKind.refresh, semanticLabel: 'Refresh', onPressed: _refresh)],
        child: FutureBuilder<OverviewStats>(
          future: _stats,
          builder: (context, snap) {
            if (snap.hasError) {
              return AdminMessage(adminLoadError, action: QuietLink('Try again', color: MW.lilac, onPressed: _refresh));
            }
            if (!snap.hasData) return const Center(child: CircularProgressIndicator(color: MW.lilac));
            return RefreshIndicator(
              color: MW.violet,
              onRefresh: _refresh,
              child: _Content(stats: snap.data!),
            );
          },
        ),
      );
}

class _Content extends StatelessWidget {
  final OverviewStats stats;
  const _Content({required this.stats});

  @override
  Widget build(BuildContext context) {
    final cats = stats.byCategory.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final top = cats.isEmpty ? 0 : cats.first.value;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(MW.gutter, 0, MW.gutter, 40),
      children: [
        MetricGrid(tiles: [
          MetricTile(label: 'Wishes in the Well', value: stats.wishes),
          MetricTile(label: 'Luck given', value: stats.luck),
          MetricTile(
            label: 'Open reports',
            value: stats.openReports,
            color: stats.openReports > 0 ? adminDanger : MW.gold,
          ),
          MetricTile(label: 'Hidden', value: stats.hidden, color: MW.lilac),
          MetricTile(label: 'Plus members', value: stats.plusMembers),
          MetricTile(label: 'People blocked', value: stats.blocked, color: MW.lilac),
        ]),
        const SizedBox(height: 28),
        const SectionHeading('Last 14 days', glyph: GlyphKind.spark),
        const SizedBox(height: 6),
        Text(
          '${_n(stats.windowWishes)} wish${stats.windowWishes == 1 ? '' : 'es'} from '
          '${_n(stats.wishers)} ${stats.wishers == 1 ? 'person' : 'people'}, '
          '${_n(stats.windowLuck)} luck received.',
          style: MW.ui(13.5, color: MW.textDim, height: 1.4),
        ),
        const SizedBox(height: 14),
        GlassCard(
          radius: 22,
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
          child: DailyBars(days: stats.daily),
        ),
        if (stats.windowCapped)
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 6),
            child: Text('Busier than this chart can read: figures above are a minimum.',
                style: MW.ui(12.5, color: MW.goldBright, height: 1.4)),
          ),
        const SizedBox(height: 28),
        const SectionHeading('By category'),
        const SizedBox(height: 12),
        GlassCard(
          radius: 22,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Column(children: [
            for (final e in cats) _CategoryBar(category: e.key, count: e.value, top: top),
          ]),
        ),
        const SizedBox(height: 28),
        const SectionHeading('Reach', glyph: GlyphKind.bell),
        const SizedBox(height: 12),
        GlassCard(
          radius: 22,
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
          child: Column(children: [
            _Line('Phones with notifications on', stats.devices),
            _Line('Android', stats.androidDevices),
            _Line('iPhone', stats.iosDevices),
            _Line('Luck alerts on', stats.luckAlertDevices),
            _Line('Revisit reminders on', stats.revisitDevices, last: true),
          ]),
        ),
        const SizedBox(height: 14),
        Text(
          'Counts cover wishes still in the Well: a wish is removed from it once its author '
          'resolves it. Reach counts phones, not people, and does not include anyone who has '
          'notifications off. There is no total of sign-ups here; those live in Firebase Authentication.',
          style: MW.ui(12.5, color: MW.textFaint, height: 1.5),
        ),
      ],
    );
  }

  static String _n(int v) => NumberFormat.decimalPattern().format(v);
}

class _Line extends StatelessWidget {
  final String label;
  final int value;
  final bool last;
  const _Line(this.label, this.value, {this.last = false});

  @override
  Widget build(BuildContext context) => Semantics(
        container: true,
        label: '$label: $value',
        excludeSemantics: true,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 13),
            child: Row(children: [
              Expanded(child: Text(label, style: MW.ui(15, color: MW.text, weight: 600))),
              Text(NumberFormat.decimalPattern().format(value), style: MW.ui(15, color: MW.gold, weight: 800)),
            ]),
          ),
          if (!last) const Hairline(),
        ]),
      );
}

class _CategoryBar extends StatelessWidget {
  final WishCategory category;
  final int count;
  final int top;
  const _CategoryBar({required this.category, required this.count, required this.top});

  @override
  Widget build(BuildContext context) => Semantics(
        container: true,
        label: '${category.label}: $count wishes',
        excludeSemantics: true,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Glyph(category.glyph, size: 16, color: MW.lilac, stroke: 1.6),
              const SizedBox(width: 8),
              Expanded(child: Text(category.label, style: MW.ui(14.5, color: MW.text, weight: 700))),
              Text(NumberFormat.decimalPattern().format(count), style: MW.ui(14.5, color: MW.gold, weight: 800)),
            ]),
            const SizedBox(height: 7),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Stack(children: [
                Container(height: 7, color: const Color(0x26FFFFFF)),
                FractionallySizedBox(
                  widthFactor: top == 0 ? 0 : (count / top).clamp(0.0, 1.0),
                  child: Container(height: 7, decoration: const BoxDecoration(gradient: MW.glow)),
                ),
              ]),
            ),
          ]),
        ),
      );
}
