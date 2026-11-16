import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/admin.dart';
import '../models/moderation.dart';
import '../state/admin_backend.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/glyphs.dart';
import '../widgets/settings_kit.dart';
import '../widgets/ui.dart';
import 'admin/activity_screen.dart';
import 'admin/admin_kit.dart';
import 'admin/admins_screen.dart';
import 'admin/subscriptions_screen.dart';
import 'admin/announcements_screen.dart';
import 'admin/controls_screen.dart';
import 'admin/moderation_screen.dart';
import 'admin/overview_screen.dart';
import 'admin/people_screen.dart';

/// Admin sign-in. Only an account with a document in admins/{uid} gets in;
/// anyone else is signed straight back out, and the message doesn't say which
/// part was wrong.
Future<void> showAdminSignIn(BuildContext context) async {
  final opened = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: MW.inkDeep,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (_) => const _AdminSignInSheet(),
  );
  if (opened == true && context.mounted) {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AdminScreen()));
  }
}

class _AdminSignInSheet extends StatefulWidget {
  const _AdminSignInSheet();

  @override
  State<_AdminSignInSheet> createState() => _AdminSignInSheetState();
}

class _AdminSignInSheetState extends State<_AdminSignInSheet> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ok = await context.read<AppState>().signInAdmin(_email.text, _password.text);
      if (!mounted) return;
      if (ok) {
        Navigator.of(context).pop(true);
        return;
      }
    } catch (_) {
      // Wrong password, unknown email, offline: all look the same on purpose.
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = 'Those details did not open the admin area.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(MW.gutter, 22, MW.gutter, MediaQuery.viewInsetsOf(context).bottom + 24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('ADMIN', style: MW.display(22)),
        const SizedBox(height: 6),
        Text('Sign in with your admin account to open the dashboard.',
            style: MW.ui(14, color: MW.textDim, height: 1.45)),
        const SizedBox(height: 18),
        AdminField(controller: _email, hint: 'Email', keyboard: TextInputType.emailAddress),
        const SizedBox(height: 12),
        AdminField(controller: _password, hint: 'Password', obscure: true, onSubmit: _submit),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: MW.ui(13.5, color: adminDanger, weight: 600)),
        ],
        const SizedBox(height: 20),
        GlowButton('Sign in', isLoading: _busy, onPressed: _busy ? null : _submit),
      ]),
    );
  }
}

/// The dashboard home: a card for each thing an admin looks after, with what
/// needs attention shown on it.
class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  late final AdminBackend? _tools;
  late final Stream<List<WishReport>> _reports;

  @override
  void initState() {
    super.initState();
    _tools = context.read<AppState>().adminTools;
    _reports = _tools?.watchReports() ?? const Stream.empty();
  }

  Future<void> _signOut() async {
    await context.read<AppState>().signOut();
    if (mounted) Navigator.of(context).pop();
  }

  void _open(Widget page) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final account = state.accountLabel;
    bool can(AdminArea area) => state.canAdmin(area);
    return AdminPage(
      title: 'Admin',
      root: true,
      actions: [QuietLink('Sign out', onPressed: _signOut)],
      child: _tools == null
          ? const AdminMessage('The dashboard needs a connection to the Well. Check your internet and reopen it.')
          : ListView(
              padding: const EdgeInsets.fromLTRB(MW.gutter, 0, MW.gutter, 40),
              children: [
                if (account != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 6, bottom: 16),
                    child: Row(children: [
                      Flexible(
                        child: Text('Signed in as $account',
                            overflow: TextOverflow.ellipsis, style: MW.ui(13.5, color: MW.textDim, weight: 600)),
                      ),
                      const SizedBox(width: 10),
                      RolePill(state.adminRole),
                    ]),
                  ),
                StreamBuilder<List<WishReport>>(
                  stream: _reports,
                  builder: (context, snap) {
                    final waiting = snap.data?.length ?? 0;
                    return GridView(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisSpacing: 14,
                        crossAxisSpacing: 14,
                        mainAxisExtent: 148,
                      ),
                      children: [
                        if (can(AdminArea.overview)) ModuleCard(
                          glyph: GlyphKind.constellation,
                          title: 'Overview',
                          subtitle: 'Wishes, luck and reach',
                          tint: MW.sky,
                          onTap: () => _open(const OverviewScreen()),
                        ),
                        if (can(AdminArea.moderation)) ModuleCard(
                          glyph: GlyphKind.shield,
                          title: 'Moderation',
                          subtitle: waiting > 0 ? 'Reports waiting for you' : 'Reports and every wish',
                          tint: MW.goldDeep,
                          badge: waiting,
                          onTap: () => _open(const ModerationScreen()),
                        ),
                        if (can(AdminArea.people)) ModuleCard(
                          glyph: GlyphKind.user,
                          title: 'People',
                          subtitle: 'Blocked from sharing',
                          tint: MW.lilac,
                          onTap: () => _open(const PeopleScreen()),
                        ),
                        if (can(AdminArea.announcements)) ModuleCard(
                          glyph: GlyphKind.bell,
                          title: 'Announcements',
                          subtitle: 'Notify every phone',
                          tint: MW.violet,
                          onTap: () => _open(const AnnouncementsScreen()),
                        ),
                        if (can(AdminArea.subscriptions)) ModuleCard(
                          glyph: GlyphKind.starPlus,
                          title: 'Subscriptions',
                          subtitle: 'See and give Plus',
                          tint: MW.gold,
                          onTap: () => _open(const SubscriptionsScreen()),
                        ),
                        if (can(AdminArea.admins)) ModuleCard(
                          glyph: GlyphKind.lock,
                          title: 'Admins',
                          subtitle: 'Who can open this',
                          tint: MW.violet,
                          onTap: () => _open(const AdminsScreen()),
                        ),
                        if (can(AdminArea.controls)) ModuleCard(
                          glyph: GlyphKind.sliders,
                          title: 'Controls',
                          subtitle: 'Pause, banner, words',
                          tint: MW.water,
                          onTap: () => _open(const ControlsScreen()),
                        ),
                        if (can(AdminArea.activity)) ModuleCard(
                          glyph: GlyphKind.document,
                          title: 'Activity',
                          subtitle: 'Who did what',
                          tint: MW.textFaint,
                          onTap: () => _open(const ActivityScreen()),
                        ),
                      ],
                    );
                  },
                ),
                if (can(AdminArea.export)) ...[
                const SizedBox(height: 22),
                SettingsSection(
                  footer: 'Opens as a spreadsheet file you can share or save.',
                  children: [
                    SettingsRow(
                      glyph: GlyphKind.download,
                      title: 'Export data',
                      subtitle: 'Wishes, reports or the activity log',
                      tint: MW.sky,
                      onTap: () => showAdminExport(context, _tools),
                    ),
                  ],
                ),
                ],
              ],
            ),
    );
  }
}

/// Lets an admin choose a table and shares it as a CSV file.
Future<void> showAdminExport(BuildContext context, AdminBackend tools) => showModalBottomSheet<void>(
      context: context,
      backgroundColor: MW.inkDeep,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => _ExportSheet(tools: tools),
    );

class _ExportSheet extends StatefulWidget {
  final AdminBackend tools;
  const _ExportSheet({required this.tools});

  @override
  State<_ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends State<_ExportSheet> {
  AdminExport? _busy;

  Future<void> _export(AdminExport what) async {
    setState(() => _busy = what);
    // Taken before the awaits: the share sheet on an iPad needs to know where
    // it came from.
    final box = context.findRenderObject();
    final origin = box is RenderBox && box.hasSize ? box.localToGlobal(Offset.zero) & box.size : null;
    final navigator = Navigator.of(context);
    final ok = await runAdmin(context, () async {
      final csv = await widget.tools.exportCsv(what);
      final day = DateFormat('yyyy-MM-dd').format(DateTime.now());
      await SharePlus.instance.share(ShareParams(
        // The byte-order mark makes Excel read accents and emoji correctly.
        files: [XFile.fromData(Uint8List.fromList(utf8.encode('﻿$csv')), mimeType: 'text/csv')],
        fileNameOverrides: ['manifestwell-${what.file}-$day.csv'],
        subject: 'ManifestWell ${what.label.toLowerCase()}',
        sharePositionOrigin: origin,
      ));
    });
    if (!mounted) return;
    if (ok) {
      navigator.pop();
    } else {
      setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(MW.gutter, 22, MW.gutter, 18),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('EXPORT', style: MW.display(22)),
            const SizedBox(height: 6),
            Text('Contains what people wrote. Keep it private and delete it when you are done.',
                style: MW.ui(13.5, color: MW.textDim, height: 1.45)),
            const SizedBox(height: 16),
            SettingsSection(children: [
              for (final what in AdminExport.values)
                SettingsRow(
                  glyph: GlyphKind.share,
                  title: what.label,
                  tint: MW.sky,
                  trailing: _busy == what
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.2, color: MW.lilac),
                        )
                      : null,
                  onTap: _busy == null ? () => _export(what) : null,
                ),
            ]),
          ]),
        ),
      );
}
