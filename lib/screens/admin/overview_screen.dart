import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat, NumberFormat;
import 'package:provider/provider.dart';

import '../../models/admin.dart';
import '../../models/wish.dart';
import '../../state/admin_backend.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/glyphs.dart';
import '../../widgets/ui.dart';
import 'admin_kit.dart';
import 'moderation_screen.dart';

/// The numbers: what is waiting for a moderator, how busy the Well was over a
/// period you choose (against the period before it), and who can be reached.
class OverviewScreen extends StatefulWidget {
  const OverviewScreen({super.key});

  @override
  State<OverviewScreen> createState() => _OverviewScreenState();
}

class _OverviewScreenState extends State<OverviewScreen> {
  static const ranges = [7, 14, 30, 90];

  int _days = 14;
  late final AdminBackend _tools;
  late final bool _reach;
  late Future<OverviewStats> _stats;
  DateTime? _loadedAt;

  @override
  void initState() {
    super.initState();
    final state = context.read<AppState>();
    _tools = state.adminTools!;
    // Phone and Plus figures are for owners and admins only.
    _reach = state.canAdmin(AdminArea.subscriptions);
    _stats = _load();
  }

  Future<OverviewStats> _load() async {
    final stats = await _tools.loadOverview(days: _days, includeReach: _reach);
    _loadedAt = DateTime.now();
    return stats;
  }

  Future<void> _refresh() async {
    final next = _load();
    // A block body: setState rejects a closure that returns a Future.
    setState(() {
      _stats = next;
    });
    try {
      await next;
    } catch (_) {
      // The builder shows the error; the refresh indicator just stops.
    }
  }

  void _setRange(int days) {
    if (days == _days) return;
    _days = days;
    _refresh();
  }

  @override
  Widget build(BuildContext context) => AdminPage(
        title: 'Overview',
        area: AdminArea.overview,
        actions: [RoundIconButton(glyph: GlyphKind.refresh, semanticLabel: 'Refresh', onPressed: _refresh)],
        child: FutureBuilder<OverviewStats>(
          future: _stats,
          builder: (context, snap) {
            if (snap.hasError) {
              return AdminMessage(adminLoadError, action: QuietLink('Try again', color: MW.lilac, onPressed: _refresh));
            }
            if (!snap.hasData) return const AdminSkeleton(rows: 5);
            return RefreshIndicator(
              color: MW.violet,
              onRefresh: _refresh,
              child: _Content(
                stats: snap.data!,
                days: _days,
                loadedAt: _loadedAt,
                onRange: _setRange,
              ),
            );
          },
        ),
      );
}

class _Content extends StatelessWidget {
  final OverviewStats stats;
  final int days;
  final DateTime? loadedAt;
  final ValueChanged<int> onRange;
  const _Content({required this.stats, required this.days, required this.loadedAt, required this.onRange});

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final cats = stats.byCategory.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final top = cats.isEmpty ? 0 : cats.first.value;
    final prev = stats.previous;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(MW.gutter, 0, MW.gutter, 40),
      children: [
        _Attention(
          waiting: stats.openReports,
          oldest: stats.oldestOpenReport,
          onReview: state.canAdmin(AdminArea.moderation)
              ? () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ModerationScreen()))
              : null,
        ),
        const SizedBox(height: 26),
        Row(children: [
          Expanded(child: SectionHeading('Last $days days', glyph: GlyphKind.spark)),
        ]),
        const SizedBox(height: 12),
        FilterPills<int>(
          options: [for (final r in _OverviewScreenState.ranges) (r, '$r days')],
          value: days,
          onChanged: onRange,
        ),
        const SizedBox(height: 14),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: MetricTile(
              label: 'New wishes',
              value: stats.windowWishes,
              trend: prev == null ? null : TrendChip(trendOf(stats.windowWishes, prev.wishes)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: MetricTile(
              label: 'People',
              value: stats.wishers,
              trend: prev == null ? null : TrendChip(trendOf(stats.wishers, prev.wishers)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: MetricTile(
              label: 'Luck',
              value: stats.windowLuck,
              trend: prev == null ? null : TrendChip(trendOf(stats.windowLuck, prev.luck)),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        Text(
          prev == null
              ? 'Wishes cast each day. Too busy to compare with the period before.'
              : 'Arrows compare with the $days days before. Wishes cast each day:',
          style: MW.ui(12.5, color: MW.textFaint, height: 1.4),
        ),
        const SizedBox(height: 10),
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
        const SectionHeading('In the Well now'),
        const SizedBox(height: 12),
        MetricGrid(tiles: [
          MetricTile(label: 'Wishes in the Well', value: stats.wishes),
          MetricTile(label: 'Luck given', value: stats.luck),
          MetricTile(
            label: 'Open reports',
            value: stats.openReports,
            color: stats.openReports > 0 ? adminDanger : MW.gold,
          ),
          MetricTile(label: 'Hidden', value: stats.hidden, color: MW.lilac),
          if (stats.includesReach) MetricTile(label: 'Plus members', value: stats.plusMembers),
          MetricTile(label: 'People blocked', value: stats.blocked, color: MW.lilac),
        ]),
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
        if (stats.includesReach) ...[
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
        ],
        const SizedBox(height: 14),
        Text(
          'Counts cover wishes still in the Well: a wish is removed from it once its author '
          'resolves it.${stats.includesReach ? ' Reach counts phones, not people, and does not include anyone who has '
              'notifications off. There is no total of sign-ups here; those live in Firebase Authentication.' : ''}',
          style: MW.ui(12.5, color: MW.textFaint, height: 1.5),
        ),
        if (loadedAt != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text('Updated ${DateFormat('HH:mm').format(loadedAt!)}. Pull down or tap refresh for the latest.',
                style: MW.ui(12, color: MW.textFaint, weight: 700)),
          ),
      ],
    );
  }
}

/// What needs a moderator now, with how long the longest wait has been.
class _Attention extends StatelessWidget {
  final int waiting;
  final DateTime? oldest;
  final VoidCallback? onReview;
  const _Attention({required this.waiting, required this.oldest, required this.onReview});

  @override
  Widget build(BuildContext context) {
    if (waiting == 0) {
      return GlassCard(
        radius: 22,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Row(children: [
          const Glyph(GlyphKind.check, size: 20, color: MW.goldBright, stroke: 2),
          const SizedBox(width: 12),
          Expanded(
            child: Text('Nothing is waiting. The Well is calm.', style: MW.ui(15, color: MW.text, weight: 700)),
          ),
        ]),
      );
    }
    // A report that has waited more than a day is a promise not kept.
    final stale = oldest != null && DateTime.now().difference(oldest!).inHours >= 24;
    final color = stale ? adminDanger : MW.goldBright;
    return Semantics(
      container: true,
      label: '$waiting report${waiting == 1 ? '' : 's'} waiting'
          '${oldest == null ? '' : ', the oldest for ${ageLabel(oldest!)}'}',
      child: GlassCard(
        radius: 22,
        borderColor: color.withValues(alpha: 0.7),
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('$waiting report${waiting == 1 ? '' : 's'} waiting', style: MW.ui(16, color: color, weight: 800)),
              if (oldest != null) ...[
                const SizedBox(height: 3),
                Text('The oldest has waited ${ageLabel(oldest!)}.',
                    style: MW.ui(13, color: MW.textDim, height: 1.35)),
              ],
            ]),
          ),
          if (onReview != null) QuietLink('Review', color: MW.lilac, onPressed: onReview),
        ]),
      ),
    );
  }
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
