import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/admin.dart';
import '../../state/admin_backend.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/glyphs.dart';
import '../../widgets/settings_kit.dart';
import '../../widgets/ui.dart';
import 'admin_kit.dart';

/// Who did what: the audit trail every admin action writes to. It can only
/// grow; nobody, admins included, can edit or delete an entry. Filter it by
/// kind of action, or search it.
class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key});

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  static const _pageSize = 100;
  static const _maxLimit = 1000;

  int _limit = _pageSize;
  ActivityGroup? _group;
  String _query = '';
  final _search = TextEditingController();
  late final AdminBackend _tools;
  late Stream<List<AdminLogEntry>> _log;

  @override
  void initState() {
    super.initState();
    _tools = context.read<AppState>().adminTools!;
    _log = _tools.watchLog(limit: _limit);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _loadMore() {
    setState(() {
      _limit = (_limit + _pageSize).clamp(0, _maxLimit);
      _log = _tools.watchLog(limit: _limit);
    });
  }

  static String label(String action) => switch (action) {
        'hide' => 'Hid wishes',
        'restore' => 'Restored wishes',
        'remove' => 'Removed wishes',
        'dismiss' => 'Dismissed reports',
        'block' => 'Blocked a person',
        'unblock' => 'Unblocked a person',
        'announce' => 'Sent an announcement',
        'announce-test' => 'Sent a test announcement',
        'settings' => 'Changed controls',
        'auto-hide' => 'Auto-hidden a wish',
        'admin-add' => 'Added an admin',
        'admin-remove' => 'Removed an admin',
        'admin-role' => 'Changed an admin’s role',
        'grant' => 'Gave Plus',
        'revoke' => 'Took back given Plus',
        _ => action,
      };

  static GlyphKind glyphFor(String action) => switch (ActivityGroup.of(action)) {
        ActivityGroup.moderation => GlyphKind.shield,
        ActivityGroup.people => GlyphKind.user,
        ActivityGroup.announcements => GlyphKind.bell,
        ActivityGroup.subscriptions => GlyphKind.starPlus,
        ActivityGroup.admins => GlyphKind.lock,
        ActivityGroup.settings => GlyphKind.sliders,
        null => GlyphKind.document,
      };

  bool _matches(AdminLogEntry e, String q) =>
      label(e.action).toLowerCase().contains(q) ||
      e.detail.toLowerCase().contains(q) ||
      e.by.toLowerCase().contains(q);

  @override
  Widget build(BuildContext context) => AdminPage(
        title: 'Activity',
        area: AdminArea.activity,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: MW.gutter),
            child: AdminSearchField(
              controller: _search,
              hint: 'Search who, what, which wish',
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          const SizedBox(height: 10),
          FilterPills<ActivityGroup?>(
            options: [(null, 'All'), for (final g in ActivityGroup.values) (g, g.label)],
            value: _group,
            onChanged: (g) => setState(() => _group = g),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: LiveView<List<AdminLogEntry>>(
              stream: _log,
              builder: (context, entries) {
                final q = _query.trim().toLowerCase();
                final shown = [
                  for (final e in entries)
                    if ((_group == null || ActivityGroup.of(e.action) == _group) && (q.isEmpty || _matches(e, q))) e,
                ];
                final canLoadMore = entries.length >= _limit && _limit < _maxLimit;
                if (entries.isEmpty) {
                  return const AdminMessage('Nothing yet. Every admin action will be listed here.');
                }
                return ListView(
                  padding: const EdgeInsets.fromLTRB(MW.gutter, 0, MW.gutter, 32),
                  children: [
                    if (shown.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 24),
                        child: AdminMessage(q.isEmpty ? 'Nothing of that kind yet.' : 'Nothing matches “$q”.'),
                      ),
                    for (final e in shown)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Semantics(
                          container: true,
                          label: '${label(e.action)}. ${e.detail}. ${e.by}, ${whenLabel(e.at)}',
                          excludeSemantics: true,
                          child: GlassCard(
                            radius: 18,
                            blur: 8,
                            padding: const EdgeInsets.fromLTRB(14, 12, 16, 12),
                            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              IconTile(glyphFor(e.action), tint: _tint(e.action)),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(label(e.action), style: MW.ui(15, color: MW.text, weight: 800)),
                                  if (e.detail.isNotEmpty) ...[
                                    const SizedBox(height: 3),
                                    Text(e.detail, style: MW.ui(13, color: MW.textDim, height: 1.4)),
                                  ],
                                  const SizedBox(height: 5),
                                  Text('${e.by} · ${whenLabel(e.at)}',
                                      style: MW.ui(12, color: MW.textFaint, weight: 700)),
                                ]),
                              ),
                            ]),
                          ),
                        ),
                      ),
                    if (canLoadMore) Center(child: QuietLink('Load older activity', color: MW.lilac, onPressed: _loadMore)),
                  ],
                );
              },
            ),
          ),
        ]),
      );

  /// Destructive actions are tinted warm, so they stand out in a long list.
  Color _tint(String action) => switch (action) {
        'remove' || 'block' || 'admin-remove' || 'revoke' => const Color(0xFFFF7A90),
        'auto-hide' => MW.goldDeep,
        _ => switch (ActivityGroup.of(action)) {
            ActivityGroup.announcements => MW.violet,
            ActivityGroup.subscriptions => MW.goldDeep,
            ActivityGroup.admins => MW.violet,
            ActivityGroup.settings => MW.water,
            _ => MW.sky,
          },
      };
}
