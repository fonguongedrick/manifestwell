import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/admin.dart';
import '../../state/admin_backend.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/ui.dart';
import 'admin_kit.dart';

/// People an admin has blocked from sharing wishes and sending luck.
class PeopleScreen extends StatefulWidget {
  const PeopleScreen({super.key});

  @override
  State<PeopleScreen> createState() => _PeopleScreenState();
}

class _PeopleScreenState extends State<PeopleScreen> {
  late final AdminBackend _tools;
  late final Stream<List<BlockedPerson>> _blocked;

  @override
  void initState() {
    super.initState();
    _tools = context.read<AppState>().adminTools!;
    _blocked = _tools.watchBlocked();
  }

  Future<void> _unblock(BuildContext context, BlockedPerson p) async {
    final yes = await confirmDialog(
      context,
      title: 'Unblock this person?',
      body: 'They can share wishes and send luck again. Wishes hidden when they were blocked stay hidden '
          'until you restore them in Moderation.',
      confirm: 'Unblock',
    );
    if (yes && context.mounted) await runAdmin(context, () => _tools.unblock(p.uid), done: 'Unblocked.');
  }

  @override
  Widget build(BuildContext context) => AdminPage(
        title: 'People',
        child: LiveView<List<BlockedPerson>>(
          stream: _blocked,
          builder: (context, people) => ListView(
            padding: const EdgeInsets.fromLTRB(MW.gutter, 0, MW.gutter, 32),
            children: [
              if (people.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 24, bottom: 8),
                  child: AdminMessage('No one is blocked.'),
                ),
              for (final p in people)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: GlassCard(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Person ${shortId(p.uid)}', style: MW.ui(16.5, color: MW.text, weight: 800)),
                      const SizedBox(height: 4),
                      Text('Blocked ${whenLabel(p.at)}', style: MW.ui(12.5, color: MW.textFaint, weight: 700)),
                      if (p.reason.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(p.reason, style: MW.ui(14, color: MW.textDim, height: 1.4)),
                      ],
                      Align(
                        alignment: Alignment.centerLeft,
                        child: QuietLink('Unblock', color: MW.lilac, onPressed: () => _unblock(context, p)),
                      ),
                    ]),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 8, 6, 0),
                child: Text(
                  'People are anonymous, so each is shown by the first characters of an id. Block someone '
                  'from one of their wishes in Moderation. A blocked person keeps their own private wishes; '
                  'they just cannot share new ones or send luck.',
                  style: MW.ui(12.5, color: MW.textFaint, height: 1.5),
                ),
              ),
            ],
          ),
        ),
      );
}
