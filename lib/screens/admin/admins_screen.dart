import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/admin.dart';
import '../../state/admin_backend.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/glyphs.dart';
import '../../widgets/ui.dart';
import 'admin_kit.dart';

/// Who can open this dashboard, and what each of them may do. Owners and
/// admins add people here; only an owner can change a role or manage owners.
/// The server decides, so these rules hold even if the app is bypassed.
class AdminsScreen extends StatefulWidget {
  const AdminsScreen({super.key});

  @override
  State<AdminsScreen> createState() => _AdminsScreenState();
}

class _AdminsScreenState extends State<AdminsScreen> {
  final _email = TextEditingController();
  late final AdminBackend _tools;
  late final AdminRole _me;
  late Future<List<AdminAccount>> _admins;
  AdminRole _role = AdminRole.admin;
  bool _adding = false;

  @override
  void initState() {
    super.initState();
    final state = context.read<AppState>();
    _tools = state.adminTools!;
    _me = state.adminRole;
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

  /// The roles this admin may hand out. Only an owner can make an owner.
  List<AdminRole> get _grantable => [
        if (_me.managesOwners) AdminRole.owner,
        AdminRole.admin,
        AdminRole.moderator,
      ];

  bool get _canAdd => _email.text.contains('@') && !_adding;

  Future<void> _add() async {
    final email = _email.text.trim();
    setState(() => _adding = true);
    final ok = await runAdmin(
      context,
      () => _tools.addAdmin(email, role: _role),
      done: '$email is now ${_role == AdminRole.admin ? 'an' : 'a'} ${_role.label.toLowerCase()}.',
    );
    if (!mounted) return;
    setState(() => _adding = false);
    if (ok) {
      _email.clear();
      _reload();
    }
  }

  Future<void> _changeRole(AdminAccount a) async {
    final picked = await showModalBottomSheet<AdminRole>(
      context: context,
      backgroundColor: MW.inkDeep,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(MW.gutter, 0, MW.gutter, 12),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('CHANGE ROLE', style: MW.display(21)),
            const SizedBox(height: 6),
            Text(a.label, style: MW.ui(14, color: MW.textDim)),
            const SizedBox(height: 10),
            for (final r in AdminRole.values)
              Semantics(
                button: true,
                selected: r == a.role,
                label: '${r.label}. ${r.summary}',
                excludeSemantics: true,
                child: GestureDetector(
                  key: ValueKey('role-${r.name}'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.of(ctx).pop(r),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    child: Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(r.label,
                              style: MW.ui(16, color: r == a.role ? MW.goldBright : MW.text, weight: 800)),
                          const SizedBox(height: 2),
                          Text(r.summary, style: MW.ui(13, color: MW.textFaint, height: 1.35)),
                        ]),
                      ),
                      if (r == a.role) const Glyph(GlyphKind.check, size: 18, color: MW.goldBright, stroke: 2),
                    ]),
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
    if (picked == null || picked == a.role || !mounted) return;
    final ok = await runAdmin(context, () => _tools.setAdminRole(a.uid, picked),
        done: '${a.label} is now ${picked == AdminRole.admin ? 'an' : 'a'} ${picked.label.toLowerCase()}.');
    if (ok && mounted) _reload();
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
        area: AdminArea.admins,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(MW.gutter, 0, MW.gutter, 40),
          children: [
            Text(
              'Add someone by the email they use in the app. They must have signed in to ManifestWell at least once.',
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
            const Caps('Role'),
            const SizedBox(height: 10),
            FilterPillsInline<AdminRole>(
              options: [for (final r in _grantable) (r, r.label)],
              value: _role,
              onChanged: (r) => setState(() => _role = r),
            ),
            const SizedBox(height: 8),
            Text(_role.summary, style: MW.ui(13, color: MW.textFaint, height: 1.4)),
            const SizedBox(height: 16),
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
                if (!snap.hasData) return const SizedBox(height: 220, child: AdminSkeleton(rows: 2));
                return Column(children: [
                  for (final a in snap.data!)
                    _AdminTile(
                      account: a,
                      // An owner can change anyone's role but their own.
                      onChangeRole: _me.managesOwners && !a.you ? () => _changeRole(a) : null,
                      // Only an owner can remove an owner; nobody removes themselves.
                      onRemove: !a.you && (!a.owner || _me.managesOwners) ? () => _remove(a) : null,
                    ),
                ]);
              },
            ),
            const SizedBox(height: 22),
            const SectionHeading('What each role can do'),
            const SizedBox(height: 12),
            GlassCard(
              radius: 22,
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final r in AdminRole.values)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      SizedBox(width: 96, child: Align(alignment: Alignment.topLeft, child: RolePill(r))),
                      Expanded(child: Text(r.summary, style: MW.ui(13.5, color: MW.textDim, height: 1.4))),
                    ]),
                  ),
              ]),
            ),
            const SizedBox(height: 10),
            Text(
              'Owners are the admins first set up in the Firebase console. Nobody can remove or demote themselves, '
              'and there is always at least one owner.',
              style: MW.ui(12.5, color: MW.textFaint, height: 1.5),
            ),
          ],
        ),
      );
}

class _AdminTile extends StatelessWidget {
  final AdminAccount account;
  final VoidCallback? onChangeRole;
  final VoidCallback? onRemove;
  const _AdminTile({required this.account, this.onChangeRole, this.onRemove});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: GlassCard(
          radius: 20,
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(account.label, style: MW.ui(15.5, color: MW.text, weight: 800)),
            const SizedBox(height: 8),
            Row(children: [
              RolePill(account.role),
              if (account.you) ...[
                const SizedBox(width: 8),
                Text('You', style: MW.ui(12.5, color: MW.textFaint, weight: 800)),
              ],
            ]),
            if (onChangeRole != null || onRemove != null)
              Wrap(children: [
                if (onChangeRole != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 14),
                    child: IntrinsicWidth(child: QuietLink('Change role', color: MW.lilac, onPressed: onChangeRole)),
                  ),
                if (onRemove != null)
                  IntrinsicWidth(child: QuietLink('Remove', color: adminDanger, onPressed: onRemove)),
              ])
            else
              const SizedBox(height: 12),
          ]),
        ),
      );
}
