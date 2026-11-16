import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/admin.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/ui.dart';
import 'admin_kit.dart';

/// Who did what: the audit trail every admin action writes to. It can only
/// grow; nobody, admins included, can edit or delete an entry.
class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key});

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  late final Stream<List<AdminLogEntry>> _log;

  @override
  void initState() {
    super.initState();
    _log = context.read<AppState>().adminTools!.watchLog();
  }

  static String label(String action) => switch (action) {
        'hide' => 'Hid a wish',
        'restore' => 'Restored a wish',
        'remove' => 'Removed a wish',
        'dismiss' => 'Dismissed reports',
        'block' => 'Blocked a person',
        'unblock' => 'Unblocked a person',
        'announce' => 'Sent an announcement',
        'settings' => 'Changed controls',
        'auto-hide' => 'Auto-hidden a wish',
        'admin-add' => 'Added an admin',
        'admin-remove' => 'Removed an admin',
        'grant' => 'Gave Plus',
        'revoke' => 'Took back given Plus',
        _ => action,
      };

  @override
  Widget build(BuildContext context) => AdminPage(
        title: 'Activity',
        child: LiveView<List<AdminLogEntry>>(
          stream: _log,
          builder: (context, entries) => entries.isEmpty
              ? const AdminMessage('Nothing yet. Every admin action will be listed here.')
              : ListView(
                  padding: const EdgeInsets.fromLTRB(MW.gutter, 0, MW.gutter, 32),
                  children: [
                    for (final e in entries)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: GlassCard(
                          radius: 18,
                          blur: 8,
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
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
                      ),
                  ],
                ),
        ),
      );
}
