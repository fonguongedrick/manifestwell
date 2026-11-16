import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/admin.dart';
import '../../models/moderation.dart';
import '../../state/admin_backend.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/ui.dart';
import 'admin_kit.dart';

enum _Tab { reports, wishes }

enum _Filter { all, reported, hidden }

/// The moderation queue: reported wishes first, then every wish in the Well.
class ModerationScreen extends StatefulWidget {
  const ModerationScreen({super.key});

  @override
  State<ModerationScreen> createState() => _ModerationScreenState();
}

class _ModerationScreenState extends State<ModerationScreen> {
  _Tab _tab = _Tab.reports;
  _Filter _filter = _Filter.all;
  late final AdminBackend _tools;
  late final Stream<List<ModWish>> _wishes;
  late final Stream<List<WishReport>> _reports;
  late final Stream<List<BlockedPerson>> _blocked;

  @override
  void initState() {
    super.initState();
    _tools = context.read<AppState>().adminTools!;
    // Held here and shown through an IndexedStack, so each stream is listened
    // to exactly once however often the tab is switched.
    _wishes = _tools.watchAllWishes();
    _reports = _tools.watchReports();
    _blocked = _tools.watchBlocked();
  }

  @override
  Widget build(BuildContext context) => AdminPage(
        title: 'Moderation',
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: MW.gutter),
            child: SlidingSegment<_Tab>(
              options: const [(_Tab.reports, 'Reports'), (_Tab.wishes, 'All wishes')],
              value: _tab,
              onChanged: (t) => setState(() => _tab = t),
            ),
          ),
          if (_tab == _Tab.wishes) ...[
            const SizedBox(height: 12),
            FilterPills<_Filter>(
              options: const [(_Filter.all, 'All'), (_Filter.reported, 'Reported'), (_Filter.hidden, 'Hidden')],
              value: _filter,
              onChanged: (f) => setState(() => _filter = f),
            ),
          ],
          const SizedBox(height: 14),
          Expanded(
            child: LiveView3<List<ModWish>, List<WishReport>, List<BlockedPerson>>(
              a: _wishes,
              b: _reports,
              c: _blocked,
              builder: (context, wishes, reports, blocked) {
                final blockedIds = {for (final b in blocked) b.uid};
                return IndexedStack(
                  index: _tab.index,
                  children: [
                    _ReportsList(tools: _tools, wishes: wishes, reports: reports, blocked: blockedIds),
                    _WishesList(
                      tools: _tools,
                      wishes: wishes,
                      reports: reports,
                      blocked: blockedIds,
                      filter: _filter,
                    ),
                  ],
                );
              },
            ),
          ),
        ]),
      );
}

class _ReportsList extends StatelessWidget {
  final AdminBackend tools;
  final List<ModWish> wishes;
  final List<WishReport> reports;
  final Set<String> blocked;
  const _ReportsList({required this.tools, required this.wishes, required this.reports, required this.blocked});

  @override
  Widget build(BuildContext context) {
    final byWish = <String, List<WishReport>>{};
    for (final r in reports) {
      byWish.putIfAbsent(r.wishId, () => []).add(r);
    }
    if (byWish.isEmpty) return const AdminMessage('Nothing reported. The Well is calm.');
    // Most-reported first.
    final ids = byWish.keys.toList()..sort((a, b) => byWish[b]!.length.compareTo(byWish[a]!.length));
    return ListView(
      padding: const EdgeInsets.fromLTRB(MW.gutter, 0, MW.gutter, 32),
      children: [
        for (final id in ids)
          _ModCard(
            tools: tools,
            wish: wishes.where((w) => w.wish.id == id).firstOrNull,
            reports: byWish[id]!,
            blocked: blocked,
            orphanId: id,
          ),
      ],
    );
  }
}

class _WishesList extends StatelessWidget {
  final AdminBackend tools;
  final List<ModWish> wishes;
  final List<WishReport> reports;
  final Set<String> blocked;
  final _Filter filter;
  const _WishesList({
    required this.tools,
    required this.wishes,
    required this.reports,
    required this.blocked,
    required this.filter,
  });

  @override
  Widget build(BuildContext context) {
    final reportedIds = {for (final r in reports) r.wishId};
    final shown = wishes.where((w) => switch (filter) {
          _Filter.all => true,
          _Filter.reported => reportedIds.contains(w.wish.id),
          _Filter.hidden => w.hidden,
        }).toList();
    if (shown.isEmpty) {
      return AdminMessage(switch (filter) {
        _Filter.all => 'No wishes in the Well yet.',
        _Filter.reported => 'No reported wishes.',
        _Filter.hidden => 'Nothing is hidden.',
      });
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(MW.gutter, 0, MW.gutter, 32),
      children: [
        for (final w in shown)
          _ModCard(
            tools: tools,
            wish: w,
            reports: reports.where((r) => r.wishId == w.wish.id).toList(),
            blocked: blocked,
          ),
      ],
    );
  }
}

class _ModCard extends StatelessWidget {
  final AdminBackend tools;
  final ModWish? wish;
  final List<WishReport> reports;
  final Set<String> blocked;
  final String? orphanId;
  const _ModCard({
    required this.tools,
    required this.wish,
    required this.reports,
    required this.blocked,
    this.orphanId,
  });

  Future<void> _remove(BuildContext context, String id) async {
    final yes = await confirmDialog(
      context,
      title: 'Remove this wish?',
      body: 'It is deleted for everyone, along with its reports. This cannot be undone.',
      confirm: 'Remove',
    );
    if (yes && context.mounted) await runAdmin(context, () => tools.removeWish(id));
  }

  Future<void> _block(BuildContext context, ModWish w) async {
    final uid = w.authorUid!;
    final yes = await confirmDialog(
      context,
      title: 'Block this person?',
      body: 'They can no longer share wishes or send luck, and everything they have shared is hidden '
          'from the Well. You can unblock them later in People.',
      confirm: 'Block',
    );
    if (yes && context.mounted) {
      await runAdmin(context, () => tools.block(uid, reason: 'Blocked from a reported wish'), done: 'Blocked.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = wish;
    final uid = w?.authorUid;
    final isBlocked = uid != null && blocked.contains(uid);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: GlassCard(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (w == null)
            Text('This wish was already removed.', style: MW.ui(15, color: MW.textFaint))
          else ...[
            Text(w.wish.text, style: MW.voice(17.5)),
            const SizedBox(height: 8),
            Text(
              '${w.wish.category.label} · ${w.wish.luck} luck${w.hidden ? ' · Hidden' : ''}',
              style: MW.ui(12.5, color: w.hidden ? MW.goldBright : MW.textFaint, weight: 700),
            ),
            const SizedBox(height: 2),
            Text(
              '${whenLabel(w.wish.createdAt)} · by ${shortId(uid)}${isBlocked ? ' · Blocked' : ''}',
              style: MW.ui(12, color: MW.textFaint),
            ),
          ],
          if (reports.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('${reports.length} report${reports.length == 1 ? '' : 's'}',
                style: MW.ui(13, color: adminDanger, weight: 800)),
            const SizedBox(height: 2),
            Text(reports.map((r) => r.reason).where((r) => r.isNotEmpty).toSet().join(' · '),
                style: MW.ui(13, color: MW.textDim)),
          ],
          const SizedBox(height: 4),
          Wrap(children: [
            if (w != null)
              _Act(w.hidden ? 'Restore' : 'Hide',
                  color: MW.lilac, onPressed: () => runAdmin(context, () => tools.setHidden(w.wish.id, !w.hidden))),
            if (w != null) _Act('Remove', color: adminDanger, onPressed: () => _remove(context, w.wish.id)),
            if (w != null && uid != null && !isBlocked)
              _Act('Block author', color: adminDanger, onPressed: () => _block(context, w)),
            if (reports.isNotEmpty)
              _Act(
                'Dismiss reports',
                onPressed: () => runAdmin(
                  context,
                  () => tools.dismissReports(w?.wish.id ?? orphanId ?? reports.first.wishId, [for (final r in reports) r.id]),
                ),
              ),
          ]),
        ]),
      ),
    );
  }
}

/// A card action sized to its label, so several sit side by side. (A bare
/// QuietLink fills the width it is given and would stack one per line.)
class _Act extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onPressed;
  const _Act(this.label, {this.color = MW.textDim, required this.onPressed});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 14),
        child: IntrinsicWidth(child: QuietLink(label, color: color, onPressed: onPressed)),
      );
}
