import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/admin.dart';
import '../../state/admin_backend.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/ui.dart';
import 'admin_kit.dart';

/// Who can open this dashboard. Admins can add each other here; the server
/// decides who may be removed.
class AdminsScreen extends StatefulWidget {
  const AdminsScreen({super.key});

  @override
  State<AdminsScreen> createState() => _AdminsScreenState();
}

class _AdminsScreenState extends State<AdminsScreen> {
  final _email = TextEditingController();
  late final AdminBackend _tools;
  late Future<List<AdminAccount>> _admins;
  bool _adding = false;

  @override
  void initState() {
    super.initState();
    _tools = context.read<AppState>().adminTools!;
    _admins = _tools.listAdmins();
    _email.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  void _reload() {
    // A block body: setState rejects a closure that returns a Future.
    setState(() {
      _admins = _tools.listAdmins();
    });
  }

  bool get _canAdd => _email.text.contains('@') && !_adding;

  Future<void> _add() async {
    final email = _email.text.trim();
    setState(() => _adding = true);
    final ok = await runAdmin(context, () => _tools.addAdmin(email), done: '$email is now an admin.');
    if (!mounted) return;
    setState(() => _adding = false);
    if (ok) {
      _email.clear();
      _reload();
    }
  }

  Future<void> _remove(AdminAccount a) async {
    final yes = await confirmDialog(
      context,
      title: 'Remove this admin?',
      body: '${a.label} will no longer be able to open the dashboard. Their account and anything they did stays.',
      confirm: 'Remove',
    );
    if (!yes || !mounted) return;
    final ok = await runAdmin(context, () => _tools.removeAdmin(a.uid), done: 'Removed.');
    if (ok && mounted) _reload();
  }

  @override
  Widget build(BuildContext context) => AdminPage(
        title: 'Admins',
        child: ListView(
          padding: const EdgeInsets.fromLTRB(MW.gutter, 0, MW.gutter, 40),
          children: [
            Text(
              'Anyone here can open this dashboard. Add someone by the email they use in the app. They must '
              'have signed in to ManifestWell at least once.',
              style: MW.ui(13.5, color: MW.textDim, height: 1.5),
            ),
            const SizedBox(height: 16),
            AdminField(
              key: const ValueKey('field-admin-email'),
              controller: _email,
              hint: 'Email address',
              keyboard: TextInputType.emailAddress,
              onSubmit: _canAdd ? _add : null,
            ),
            const SizedBox(height: 14),
            GlowButton('Add admin', isLoading: _adding, onPressed: _canAdd ? _add : null),
            const SizedBox(height: 28),
            const SectionHeading('Current admins'),
            const SizedBox(height: 12),
            FutureBuilder<List<AdminAccount>>(
              future: _admins,
              builder: (context, snap) {
                if (snap.hasError) {
                  final e = snap.error;
                  return AdminMessage(
                    e is AdminActionException ? e.message : adminLoadError,
                    action: QuietLink('Try again', color: MW.lilac, onPressed: _reload),
                  );
                }
                if (!snap.hasData) {
                  return const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator(color: MW.lilac)),
                  );
                }
                return Column(children: [for (final a in snap.data!) _AdminTile(account: a, onRemove: () => _remove(a))]);
              },
            ),
            const SizedBox(height: 10),
            Text(
              'Owners are the admins first set up in the Firebase console. Only an owner can remove another '
              'owner, nobody can remove themselves, and there is always at least one admin.',
              style: MW.ui(12.5, color: MW.textFaint, height: 1.5),
            ),
          ],
        ),
      );
}

class _AdminTile extends StatelessWidget {
  final AdminAccount account;
  final VoidCallback onRemove;
  const _AdminTile({required this.account, required this.onRemove});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: GlassCard(
          radius: 20,
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(account.label, style: MW.ui(15.5, color: MW.text, weight: 800)),
                const SizedBox(height: 4),
                Text(
                  [if (account.owner) 'Owner' else 'Admin', if (account.you) 'You'].join(' · '),
                  style: MW.ui(12.5, color: account.owner ? MW.goldBright : MW.textFaint, weight: 700),
                ),
              ]),
            ),
            if (!account.you) QuietLink('Remove', color: adminDanger, onPressed: onRemove),
          ]),
        ),
      );
}
