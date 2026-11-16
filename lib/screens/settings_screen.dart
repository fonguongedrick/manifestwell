import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/links.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../utils/app_info.dart';
import '../widgets/account_sheet.dart';
import '../widgets/glyphs.dart';
import '../widgets/settings_kit.dart';
import '../widgets/sheets.dart';
import '../widgets/ui.dart';
import 'admin_screen.dart';
import 'paywall_screen.dart';

/// The Settings tab: who you are, how the app behaves, your data, and help.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _busy = false;

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _open(String url) async {
    try {
      final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      if (!ok) _toast('Could not open the link.');
    } catch (e) {
      debugPrint('launchUrl failed: $e');
      _toast('Could not open the link.');
    }
  }

  Rect? _shareOrigin() {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  Future<void> _setReminder(AppState state, {int? hour, int? minute, bool? enabled}) async {
    final wanted = enabled ?? state.remindersEnabled;
    final ok = await state.setReminder(
      hour: hour ?? state.reminderHour,
      minute: minute ?? state.reminderMinute,
      enabled: wanted,
    );
    if (!ok) {
      _toast('Notifications are off for ManifestWell. Turn them on in your phone settings to get reminders.');
    }
  }

  Future<void> _restorePurchases(AppState state) async {
    setState(() => _busy = true);
    try {
      final active = await state.restorePurchases();
      _toast(active
          ? 'Plus restored. Welcome back.'
          : 'We could not find an active Plus subscription for this account.');
    } catch (e) {
      debugPrint('Restore failed: $e');
      _toast('Could not reach the store. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setPush(AppState state, {bool? luck, bool? revisit}) async {
    final ok = await state.setPush(luck: luck, revisit: revisit);
    if (!ok) {
      _toast('Notifications are off for ManifestWell. Turn them on in your phone settings to get alerts.');
    }
  }

  Future<void> _pickTime(AppState state) async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: state.reminderHour, minute: state.reminderMinute),
    );
    if (t != null) await _setReminder(state, hour: t.hour, minute: t.minute);
  }

  Future<void> _export(AppState state) async {
    try {
      await SharePlus.instance.share(ShareParams(
        files: [XFile.fromData(Uint8List.fromList(utf8.encode(state.exportData())), mimeType: 'application/json')],
        fileNameOverrides: const ['manifestwell-data.json'],
        subject: 'My ManifestWell data',
        sharePositionOrigin: _shareOrigin(),
      ));
    } catch (e) {
      debugPrint('Export failed: $e');
      _toast('Could not export your data. Please try again.');
    }
  }

  Future<void> _share() async {
    try {
      await SharePlus.instance.share(ShareParams(
        text: 'Cast a wish and send luck to people around the world. ${Links.website}',
        subject: 'ManifestWell',
        sharePositionOrigin: _shareOrigin(),
      ));
    } catch (e) {
      debugPrint('Share failed: $e');
    }
  }

  Future<void> _contactSupport() async {
    final body = '\n\n—\nApp version: ${AppInfo.label}\nPlatform: ${defaultTargetPlatform.name}';
    await _open('mailto:${Links.supportEmail}'
        '?subject=${Uri.encodeComponent('ManifestWell support')}'
        '&body=${Uri.encodeComponent(body)}');
  }

  Future<void> _signOut(AppState state) async {
    final yes = await showConfirmSheet(
      context,
      title: 'Sign out?',
      message: 'Your wishes stay safe in your account and come back when you sign in again. '
          'They will be removed from this phone.',
      confirmLabel: 'Sign out',
    );
    if (!yes || !mounted) return;
    setState(() => _busy = true);
    try {
      await state.signOut();
    } catch (e) {
      debugPrint('Sign-out blocked: $e');
      _toast('Could not save your wishes first. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(AppState state) async {
    final guest = state.accountLabel == null;
    final yes = await showConfirmSheet(
      context,
      title: guest ? 'Delete your data?' : 'Delete your account?',
      message: 'This permanently removes your wishes, Proof Vault and settings from this phone'
          '${guest ? '' : ' and from our servers'}, along with any wishes you shared in the Well. '
          'It cannot be undone.'
          '${guest ? '' : ' You will be asked to confirm with your sign-in first.'}'
          '${state.isPro ? ' Deleting does not cancel your Plus subscription: cancel it in your App Store or Google Play account, or you will keep being charged.' : ''}',
      confirmLabel: 'Delete everything',
      destructive: true,
    );
    if (!yes || !mounted) return;
    setState(() => _busy = true);
    try {
      // On success the app returns to the welcome screen and this page goes away.
      await state.deleteEverything();
    } catch (e) {
      debugPrint('Delete failed: $e');
      _toast('Could not delete your account. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final time = TimeOfDay(hour: state.reminderHour, minute: state.reminderMinute);
    final signedIn = state.accountLabel != null;

    return LoadingOverlay(
      isLoading: _busy,
      child: ListView(
        padding: EdgeInsets.fromLTRB(
            MW.gutter, MediaQuery.paddingOf(context).top + 22, MW.gutter, 130),
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 4),
            child: Align(alignment: Alignment.centerLeft, child: GlowTitle('Settings', size: 30)),
          ),
          const SizedBox(height: 24),
          _ProfileCard(state: state),
          const SizedBox(height: 18),
          _PlusCard(onTap: () => PaywallScreen.show(context), active: state.isPro),
          if (state.purchasesAvailable) ...[
            const SizedBox(height: 18),
            SettingsSection(
              children: [
                if (state.isPro)
                  SettingsRow(
                    glyph: GlyphKind.gear,
                    title: 'Manage subscription',
                    subtitle: 'Change or cancel in your store account',
                    tint: MW.goldDeep,
                    onTap: () async => _open((await state.manageSubscriptionUrl()).toString()),
                  ),
                SettingsRow(
                  glyph: GlyphKind.refresh,
                  title: 'Restore purchases',
                  subtitle: 'Already subscribed on another phone?',
                  tint: MW.violet,
                  onTap: () => _restorePurchases(state),
                ),
              ],
            ),
          ],
          const SizedBox(height: 30),
          SettingsSection(
            label: 'Notifications',
            footer: state.hasBackend
                ? 'The reminder is one gentle nudge a day. Alerts are only ever about your own wishes, '
                    'and never say who sent luck.'
                : 'One gentle nudge a day. You can change the time or turn it off whenever you like.',
            children: [
              SettingsRow(
                glyph: GlyphKind.bell,
                title: 'Daily reminder',
                subtitle: 'Notice what went right today',
                tint: MW.sky,
                trailing: GlowSwitch(
                  key: const ValueKey('switch-reminder'),
                  semanticLabel: 'Daily reminder',
                  value: state.remindersEnabled,
                  onChanged: (v) => _setReminder(state, enabled: v),
                ),
              ),
              Opacity(
                opacity: state.remindersEnabled ? 1 : 0.45,
                child: IgnorePointer(
                  ignoring: !state.remindersEnabled,
                  child: SettingsRow(
                    glyph: GlyphKind.sun,
                    title: 'Reminder time',
                    tint: MW.goldDeep,
                    onTap: () => _pickTime(state),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(time.format(context), style: MW.ui(15, color: MW.goldBright, weight: 800)),
                      const SizedBox(width: 6),
                      const Glyph(GlyphKind.chevronRight, size: 18, color: MW.textFaint),
                    ]),
                  ),
                ),
              ),
              if (state.hasBackend) ...[
                SettingsRow(
                  glyph: GlyphKind.spark,
                  title: 'Luck on my wishes',
                  subtitle: 'When someone sends luck to a wish you shared',
                  tint: MW.goldDeep,
                  trailing: GlowSwitch(
                    key: const ValueKey('switch-push-luck'),
                    semanticLabel: 'Luck on my wishes',
                    value: state.pushLuck,
                    onChanged: (v) => _setPush(state, luck: v),
                  ),
                ),
                SettingsRow(
                  glyph: GlyphKind.refresh,
                  title: 'Revisit reminders',
                  subtitle: 'A nudge to revisit a wish after a month',
                  tint: MW.violet,
                  trailing: GlowSwitch(
                    key: const ValueKey('switch-push-revisit'),
                    semanticLabel: 'Revisit reminders',
                    value: state.pushRevisit,
                    onChanged: (v) => _setPush(state, revisit: v),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 26),
          SettingsSection(
            label: 'Feel',
            children: [
              SettingsRow(
                glyph: GlyphKind.vibrate,
                title: 'Haptics',
                subtitle: 'A soft pulse when you cast a wish or send luck',
                tint: MW.violet,
                trailing: GlowSwitch(
                  key: const ValueKey('switch-haptics'),
                  semanticLabel: 'Haptics',
                  value: state.hapticsEnabled,
                  onChanged: state.setHaptics,
                ),
              ),
            ],
          ),
          const SizedBox(height: 26),
          SettingsSection(
            label: 'Account & data',
            children: [
              if (!signedIn && state.hasBackend)
                SettingsRow(
                  glyph: GlyphKind.user,
                  title: 'Sign in',
                  subtitle: 'Keep your wishes on any phone',
                  onTap: () => showAccountSheet(context),
                ),
              SettingsRow(
                glyph: GlyphKind.download,
                title: 'Export my data',
                subtitle: 'A copy of your wishes and settings',
                tint: MW.sky,
                onTap: () => _export(state),
              ),
              if (signedIn)
                SettingsRow(
                  glyph: GlyphKind.door,
                  title: 'Sign out',
                  tint: MW.textFaint,
                  onTap: () => _signOut(state),
                ),
              SettingsRow(
                glyph: GlyphKind.trash,
                title: signedIn ? 'Delete account' : 'Delete my data',
                subtitle: 'Permanently remove everything',
                destructive: true,
                onTap: () => _delete(state),
              ),
            ],
          ),
          const SizedBox(height: 26),
          SettingsSection(
            label: 'Privacy & safety',
            children: [
              SettingsRow(
                glyph: GlyphKind.lock,
                title: 'How the Well stays anonymous',
                tint: MW.violet,
                onTap: () => showInfoSheet(
                  context,
                  title: 'Anonymous by design',
                  points: const [
                    (GlyphKind.user, 'No name, ever', 'Wishes in the Well never show your name, email or photo.'),
                    (GlyphKind.lock, 'Only Big Wishes are shared',
                        'Daily Sparks, your notes and your Proof Vault stay private to you.'),
                    (GlyphKind.shield, 'Kept kind',
                        'Anyone can report a wish, and our team reviews every report.'),
                    (GlyphKind.trash, 'Yours to remove',
                        'Withdraw a wish or delete everything at any time.'),
                  ],
                ),
              ),
              SettingsRow(
                glyph: GlyphKind.shield,
                title: 'Privacy Policy',
                tint: MW.sky,
                onTap: () => _open(Links.privacy),
              ),
              SettingsRow(
                glyph: GlyphKind.document,
                title: 'Terms of Use',
                tint: MW.sky,
                onTap: () => _open(Links.terms),
              ),
              SettingsRow(
                glyph: GlyphKind.heart,
                title: 'Community Guidelines',
                tint: MW.sky,
                onTap: () => _open(Links.guidelines),
              ),
            ],
          ),
          const SizedBox(height: 26),
          SettingsSection(
            label: 'Support',
            children: [
              SettingsRow(
                glyph: GlyphKind.mail,
                title: 'Contact support',
                subtitle: Links.supportEmail,
                tint: MW.violet,
                onTap: _contactSupport,
              ),
              SettingsRow(
                glyph: GlyphKind.share,
                title: 'Share ManifestWell',
                tint: MW.violet,
                onTap: _share,
              ),
            ],
          ),
          if (state.isAdmin) ...[
            const SizedBox(height: 26),
            SettingsSection(
              label: 'Admin',
              children: [
                SettingsRow(
                  glyph: GlyphKind.shield,
                  title: 'Admin dashboard',
                  subtitle: 'Moderation, announcements and controls',
                  tint: MW.goldDeep,
                  onTap: () => Navigator.of(context)
                      .push(MaterialPageRoute<void>(builder: (_) => const AdminScreen())),
                ),
              ],
            ),
          ],
          const SizedBox(height: 26),
          SettingsSection(
            label: 'About',
            children: [
              GestureDetector(
                // Long-press opens the admin sign-in. Nothing advertises it.
                behavior: HitTestBehavior.opaque,
                onLongPress: state.hasBackend && !state.isAdmin ? () => showAdminSignIn(context) : null,
                child: SettingsRow(
                  glyph: GlyphKind.info,
                  title: 'Version',
                  tint: MW.textFaint,
                  trailing: Text(AppInfo.label, style: MW.ui(14, color: MW.textFaint, weight: 700)),
                ),
              ),
              SettingsRow(
                glyph: GlyphKind.document,
                title: 'Open-source licenses',
                tint: MW.textFaint,
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: 'ManifestWell',
                  applicationVersion: AppInfo.current.version,
                  applicationLegalese: '© 2026 Tribes of Kin',
                ),
              ),
            ],
          ),
          const SizedBox(height: 34),
          const _Footer(),
        ],
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  final AppState state;
  const _ProfileCard({required this.state});

  @override
  Widget build(BuildContext context) {
    final label = state.accountLabel;
    final signedIn = label != null;
    final status = signedIn
        ? 'Signed in · synced to your account'
        : state.hasBackend
            ? 'Guest · saved on this phone only'
            : 'Offline · saved on this phone';
    return GlassCard(
      radius: 28,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
      child: Column(children: [
        Row(children: [
          ProfileAvatar(label: label),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // An email is set in the UI face: Cinzel's capitals and its
              // decorative "@" would make an address hard to read.
              Text(
                signedIn ? label : 'Guest',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: signedIn ? MW.ui(18, weight: 800) : MW.heading(19),
              ),
              const SizedBox(height: 5),
              Row(children: [
                Glyph(signedIn ? GlyphKind.check : GlyphKind.lock, size: 14, color: signedIn ? MW.gold : MW.textFaint, stroke: 1.9),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(status, style: MW.ui(12.5, color: MW.textFaint, weight: 600, height: 1.3)),
                ),
              ]),
            ]),
          ),
        ]),
        const SizedBox(height: 16),
        const Hairline(),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: StatCell(value: state.wishesCast, label: 'Wishes\ncast')),
          Expanded(child: StatCell(value: state.totalLuckReceived, label: 'Luck\nreceived')),
          Expanded(child: StatCell(value: state.luckSentTotal, label: 'Luck\nsent')),
        ]),
      ]),
    );
  }
}

class _PlusCard extends StatelessWidget {
  final VoidCallback onTap;
  final bool active;
  const _PlusCard({required this.onTap, required this.active});

  @override
  Widget build(BuildContext context) => Pressable(
        onPressed: onTap,
        builder: (_) => Container(
          padding: const EdgeInsets.fromLTRB(20, 18, 16, 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: Colors.white.withValues(alpha: 0.5), width: 1.2),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [MW.violet.withValues(alpha: 0.75), MW.sky.withValues(alpha: 0.55)],
            ),
            boxShadow: [BoxShadow(color: MW.violet.withValues(alpha: 0.4), blurRadius: 24)],
          ),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Glyph(GlyphKind.spark, size: 15, color: MW.gold, filled: true),
                  const SizedBox(width: 8),
                  Text(active ? 'PLUS · ACTIVE' : 'PLUS', style: MW.heading(13, color: MW.goldBright)),
                ]),
                const SizedBox(height: 8),
                Text(active ? 'You are on Plus' : 'Hold every dream at once', style: MW.heading(19)),
                const SizedBox(height: 6),
                Text(
                    active
                        ? 'Thank you. Hold as many wishes as you like.'
                        : 'Keep many wishes glowing together.',
                    style: MW.ui(13.5, color: Colors.white, height: 1.4, weight: 600)),
              ]),
            ),
            const SizedBox(width: 10),
            const Glyph(GlyphKind.chevronRight, size: 22, color: Colors.white),
          ]),
        ),
      );
}

class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) => Column(children: [
        const Glyph(GlyphKind.spark, size: 14, color: MW.gold, filled: true),
        const SizedBox(height: 10),
        Text('Words are spells.', style: MW.heading(15, color: MW.textDim)),
        const SizedBox(height: 6),
        Text('Made with care by Tribes of Kin', style: MW.ui(12, color: MW.textFaint, weight: 600)),
      ]);
}
