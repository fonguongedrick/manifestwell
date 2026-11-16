import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show NumberFormat;
import 'package:provider/provider.dart';

import '../../models/admin.dart';
import '../../state/admin_backend.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/glyphs.dart';
import '../../widgets/sheets.dart';
import '../../widgets/ui.dart';
import 'admin_kit.dart';

/// Sends one push notification to every phone in an audience, and shows how
/// each earlier one went. You see exactly how it will look, can send it to your
/// own phone first, and after sending the button locks for a minute so a double
/// tap can never notify everyone twice.
class AnnouncementsScreen extends StatefulWidget {
  const AnnouncementsScreen({super.key});

  @override
  State<AnnouncementsScreen> createState() => _AnnouncementsScreenState();
}

class _AnnouncementsScreenState extends State<AnnouncementsScreen> with SingleTickerProviderStateMixin {
  /// How long Send stays locked after a send.
  static const lockout = Duration(seconds: 60);

  final _title = TextEditingController();
  final _body = TextEditingController();
  Audience _audience = Audience.all;
  bool _sending = false;
  bool _testing = false;
  late final AdminBackend _tools;
  late final Stream<List<Announcement>> _history;
  late final AnimationController _lock = AnimationController(vsync: this, duration: lockout)
    ..value = 1; // 1 = finished = not locked

  /// Phones each audience would reach; absent until counted.
  final _reach = <Audience, int>{};

  @override
  void initState() {
    super.initState();
    _tools = context.read<AppState>().adminTools!;
    _history = _tools.watchAnnouncements();
    _title.addListener(_changed);
    _body.addListener(_changed);
    _countReach(_audience);
  }

  void _changed() => setState(() {});

  Future<void> _countReach(Audience audience) async {
    if (_reach.containsKey(audience)) return;
    try {
      final n = await _tools.estimateReach(audience);
      if (mounted) setState(() => _reach[audience] = n);
    } catch (_) {
      // Leave it uncounted: the page then simply says nothing about reach.
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _lock.dispose();
    super.dispose();
  }

  bool get _filled => _title.text.trim().isNotEmpty && _body.text.trim().isNotEmpty;
  bool get _locked => _lock.value < 1;

  String get _reachText {
    final n = _reach[_audience];
    if (n == null) return 'Counting phones…';
    if (n == 0) return 'No phone has notifications on yet, so nobody would get this.';
    return 'Reaches about ${NumberFormat.decimalPattern().format(n)} phone${n == 1 ? '' : 's'}.';
  }

  Future<void> _test() async {
    setState(() => _testing = true);
    int? sent;
    final ok = await runAdmin(context, () async => sent = await _tools.sendTestAnnouncement(title: _title.text, body: _body.text));
    if (!mounted) return;
    setState(() => _testing = false);
    if (ok) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
        content: Text('Test sent to ${sent ?? 1} of your phone${sent == 1 ? '' : 's'}.'),
      ));
    }
  }

  Future<void> _send() async {
    final who = switch (_audience) {
      Audience.all => 'every phone',
      Audience.android => 'every Android phone',
      Audience.ios => 'every iPhone',
    };
    final n = _reach[_audience];
    final yes = await showConfirmSheet(
      context,
      title: 'Send this now?',
      message: 'This sends a notification to ${n == null ? who : 'about ${NumberFormat.decimalPattern().format(n)} phones ($who)'} '
          'that has notifications turned on. It goes out within seconds and cannot be taken back.',
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
      _lock.forward(from: 0); // locks Send for a minute
    }
  }

  @override
  Widget build(BuildContext context) => AdminPage(
        title: 'Announcements',
        area: AdminArea.announcements,
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
              onChanged: (a) {
                setState(() => _audience = a);
                _countReach(a);
              },
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Text(_reachText, style: MW.ui(13, color: MW.textDim, weight: 700, height: 1.4)),
            ),
            const SizedBox(height: 18),
            const Caps('Preview'),
            const SizedBox(height: 10),
            _Preview(title: _title.text.trim(), body: _body.text.trim()),
            const SizedBox(height: 20),
            GhostButton(
              _testing ? 'Sending a test…' : 'Send me a test',
              onPressed: _filled && !_testing ? _test : null,
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 6, bottom: 10),
              child: Text('Goes only to your own phone, so you can see it for real first.',
                  style: MW.ui(12.5, color: MW.textFaint, height: 1.4)),
            ),
            AnimatedBuilder(
              animation: _lock,
              builder: (_, _) {
                final secs = (lockout.inSeconds * (1 - _lock.value)).ceil();
                return GlowButton(
                  _locked ? 'Sent. Wait ${secs}s' : 'Send',
                  isLoading: _sending,
                  onPressed: _filled && !_locked && !_sending ? _send : null,
                );
              },
            ),
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
                  : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [for (final a in items) _AnnouncementTile(a)]),
            ),
          ],
        ),
      );
}

/// How the notification will look on a phone, drawn from what is typed.
class _Preview extends StatelessWidget {
  final String title;
  final String body;
  const _Preview({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    final empty = title.isEmpty && body.isEmpty;
    return Semantics(
      container: true,
      label: 'Preview. ${title.isEmpty ? 'No title yet' : title}. ${body.isEmpty ? 'No message yet' : body}',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        decoration: BoxDecoration(
          color: const Color(0x26FFFFFF),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0x33FFFFFF)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), gradient: MW.glow),
            child: const Center(child: Glyph(GlyphKind.spark, size: 20, color: Colors.white, filled: true)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text('MANIFESTWELL', style: MW.caps(color: MW.textDim, size: 10.5))),
                Text('now', style: MW.ui(12, color: MW.textFaint)),
              ]),
              const SizedBox(height: 4),
              Text(
                title.isEmpty ? 'Your title' : title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: MW.ui(14.5, color: empty || title.isEmpty ? MW.textFaint : MW.text, weight: 800),
              ),
              const SizedBox(height: 2),
              Text(
                body.isEmpty ? 'Your message will look like this.' : body,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: MW.ui(13.5, color: body.isEmpty ? MW.textFaint : MW.textDim, height: 1.35),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
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
