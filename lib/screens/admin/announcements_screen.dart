import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/admin.dart';
import '../../state/admin_backend.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/sheets.dart';
import '../../widgets/ui.dart';
import 'admin_kit.dart';

/// Sends one push notification to every phone in an audience, and shows how
/// each earlier one went.
class AnnouncementsScreen extends StatefulWidget {
  const AnnouncementsScreen({super.key});

  @override
  State<AnnouncementsScreen> createState() => _AnnouncementsScreenState();
}

class _AnnouncementsScreenState extends State<AnnouncementsScreen> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  Audience _audience = Audience.all;
  bool _sending = false;
  late final AdminBackend _tools;
  late final Stream<List<Announcement>> _history;

  @override
  void initState() {
    super.initState();
    _tools = context.read<AppState>().adminTools!;
    _history = _tools.watchAnnouncements();
    _title.addListener(_changed);
    _body.addListener(_changed);
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  bool get _ready => _title.text.trim().isNotEmpty && _body.text.trim().isNotEmpty && !_sending;

  Future<void> _send() async {
    final who = switch (_audience) {
      Audience.all => 'every phone',
      Audience.android => 'every Android phone',
      Audience.ios => 'every iPhone',
    };
    final yes = await showConfirmSheet(
      context,
      title: 'Send this now?',
      message: 'This sends a notification to $who that has notifications turned on. '
          'It goes out within seconds and cannot be taken back.',
      confirmLabel: 'Send',
    );
    if (!yes || !mounted) return;
    setState(() => _sending = true);
    final ok = await runAdmin(
      context,
      () => _tools.sendAnnouncement(title: _title.text, body: _body.text, audience: _audience),
      done: 'Queued. The result appears below in a moment.',
    );
    if (!mounted) return;
    setState(() => _sending = false);
    if (ok) {
      _title.clear();
      _body.clear();
    }
  }

  @override
  Widget build(BuildContext context) => AdminPage(
        title: 'Announcements',
        child: ListView(
          padding: const EdgeInsets.fromLTRB(MW.gutter, 0, MW.gutter, 40),
          children: [
            Text(
              'A short note to everyone who has notifications on. Use it sparingly: people turned them on for '
              'luck and reminders.',
              style: MW.ui(13.5, color: MW.textDim, height: 1.5),
            ),
            const SizedBox(height: 16),
            AdminField(
              key: const ValueKey('announce-title'),
              controller: _title,
              hint: 'Title',
              maxLength: Announcement.titleMax,
            ),
            const SizedBox(height: 6),
            AdminField(
              key: const ValueKey('announce-body'),
              controller: _body,
              hint: 'Message',
              minLines: 3,
              maxLines: 5,
              maxLength: Announcement.bodyMax,
            ),
            const SizedBox(height: 14),
            SlidingSegment<Audience>(
              options: [for (final a in Audience.values) (a, a.label)],
              value: _audience,
              onChanged: (a) => setState(() => _audience = a),
            ),
            const SizedBox(height: 18),
            GlowButton('Send', isLoading: _sending, onPressed: _ready ? _send : null),
            const SizedBox(height: 30),
            const SectionHeading('Sent'),
            const SizedBox(height: 12),
            LiveView<List<Announcement>>(
              stream: _history,
              builder: (context, items) => items.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Text('Nothing sent yet.', style: TextStyle(color: MW.textDim)),
                    )
                  : Column(children: [for (final a in items) _AnnouncementTile(a)]),
            ),
          ],
        ),
      );
}

class _AnnouncementTile extends StatelessWidget {
  final Announcement a;
  const _AnnouncementTile(this.a);

  /// Still waiting this long means nothing picked it up.
  static const _stuckAfter = Duration(minutes: 2);

  (String, Color) get _status {
    switch (a.status) {
      case AnnouncementStatus.sent:
        final failed = a.failed > 0 ? ', ${a.failed} could not be reached' : '';
        return ('Delivered to ${a.sent} phone${a.sent == 1 ? '' : 's'}$failed', MW.goldBright);
      case AnnouncementStatus.failed:
        return ('Failed to send', adminDanger);
      case AnnouncementStatus.sending:
        return ('Sending…', MW.lilac);
      case AnnouncementStatus.queued:
        final waited = a.at != null && DateTime.now().difference(a.at!) > _stuckAfter;
        return (
          waited ? 'Still queued. Check that the announcement function is deployed.' : 'Queued…',
          waited ? adminDanger : MW.lilac,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final (text, color) = _status;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        radius: 20,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(a.title, style: MW.ui(16, color: MW.text, weight: 800)),
          const SizedBox(height: 4),
          Text(a.body, style: MW.ui(14, color: MW.textDim, height: 1.4)),
          const SizedBox(height: 8),
          Text('${a.audience.label} · ${whenLabel(a.at)}', style: MW.ui(12, color: MW.textFaint, weight: 700)),
          const SizedBox(height: 2),
          Text(text, style: MW.ui(12.5, color: color, weight: 800)),
        ]),
      ),
    );
  }
}
