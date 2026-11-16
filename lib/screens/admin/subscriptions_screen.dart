import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:provider/provider.dart';

import '../../models/admin.dart';
import '../../state/admin_backend.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/ui.dart';
import 'admin_kit.dart';

/// Who has ManifestWell Plus, and the means to give it or take back a gift.
/// Purchases themselves belong to Apple and Google; this never charges, cancels
/// or refunds anyone.
class SubscriptionsScreen extends StatefulWidget {
  const SubscriptionsScreen({super.key});

  @override
  State<SubscriptionsScreen> createState() => _SubscriptionsScreenState();
}

class _SubscriptionsScreenState extends State<SubscriptionsScreen> {
  final _query = TextEditingController();
  late final AdminBackend _tools;
  late final Stream<List<SubscriberRecord>> _people;
  SubscriberDetail? _detail;
  GrantLength _length = GrantLength.month;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _tools = context.read<AppState>().adminTools!;
    _people = _tools.watchSubscribers();
    _query.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  bool get _canFind => _query.text.trim().isNotEmpty && !_busy;

  /// Runs a server call that returns the person's updated state.
  Future<void> _run(Future<SubscriberDetail> Function() call, {String? done}) async {
    setState(() => _busy = true);
    SubscriberDetail? result;
    await runAdmin(context, () async => result = await call(), done: done);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (result != null) _detail = result;
    });
  }

  Future<void> _find([String? query]) async {
    if (query != null) _query.text = query;
    final q = _query.text.trim();
    if (q.isEmpty) return;
    await _run(() => _tools.lookupSubscriber(q));
  }

  Future<void> _give(SubscriberDetail d) async {
    final who = d.email.isNotEmpty ? d.email : 'this person';
    final yes = await confirmDialog(
      context,
      title: 'Give Plus?',
      body: '$who gets ManifestWell Plus for ${_length.label.toLowerCase()}, free. Nobody is charged. '
          'If they already pay, this adds to what they have.',
      confirm: 'Give Plus',
    );
    if (!yes || !mounted) return;
    await _run(() => _tools.grantPlus(d.uid, _length), done: 'Plus given.');
  }

  Future<void> _take(SubscriberDetail d) async {
    final yes = await confirmDialog(
      context,
      title: 'Take back given Plus?',
      body: 'Ends the Plus you gave ${d.email.isNotEmpty ? d.email : 'this person'}. A subscription they bought '
          'themselves is not affected.',
      confirm: 'Take back',
    );
    if (!yes || !mounted) return;
    await _run(() => _tools.revokeGivenPlus(d.uid), done: 'Given Plus removed.');
  }

  @override
  Widget build(BuildContext context) => AdminPage(
        title: 'Subscriptions',
        area: AdminArea.subscriptions,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(MW.gutter, 0, MW.gutter, 40),
          children: [
            const SectionHeading('Find someone'),
            const SizedBox(height: 6),
            Text('Search by the email they use in the app.', style: MW.ui(13.5, color: MW.textDim, height: 1.45)),
            const SizedBox(height: 12),
            AdminField(
              key: const ValueKey('field-find'),
              controller: _query,
              hint: 'Email address',
              keyboard: TextInputType.emailAddress,
              onSubmit: _canFind ? _find : null,
            ),
            const SizedBox(height: 14),
            GlowButton('Find', isLoading: _busy && _detail == null, onPressed: _canFind ? _find : null),
            if (_detail != null) ...[
              const SizedBox(height: 18),
              _DetailCard(
                detail: _detail!,
                length: _length,
                busy: _busy,
                onLength: (l) => setState(() => _length = l),
                onGive: () => _give(_detail!),
                onTake: () => _take(_detail!),
              ),
            ],
            const SizedBox(height: 30),
            const SectionHeading('Members'),
            const SizedBox(height: 12),
            LiveView<List<SubscriberRecord>>(
              stream: _people,
              builder: (context, people) {
                if (people.isEmpty) {
                  return const AdminMessage(
                    'No subscriptions recorded yet. They appear here as people subscribe, once the '
                    'RevenueCat webhook is connected.',
                  );
                }
                final now = DateTime.now();
                final active = people.where((p) => p.hasPlus(now)).length;
                return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  MetricGrid(tiles: [
                    MetricTile(label: 'With Plus now', value: active),
                    MetricTile(label: 'Lapsed', value: people.length - active, color: MW.lilac),
                  ]),
                  const SizedBox(height: 14),
                  for (final p in people) _MemberTile(person: p, onTap: () => _find(p.email ?? p.uid)),
                ]);
              },
            ),
          ],
        ),
      );
}

String _date(DateTime d) => DateFormat('MMM d, y').format(d);

class _DetailCard extends StatelessWidget {
  final SubscriberDetail detail;
  final GrantLength length;
  final bool busy;
  final ValueChanged<GrantLength> onLength;
  final VoidCallback onGive;
  final VoidCallback onTake;
  const _DetailCard({
    required this.detail,
    required this.length,
    required this.busy,
    required this.onLength,
    required this.onGive,
    required this.onTake,
  });

  String get _headline {
    if (!detail.active) return 'No Plus right now';
    if (detail.lifetime) return 'Plus for life';
    return detail.expiresAt == null ? 'Plus active' : 'Plus until ${_date(detail.expiresAt!)}';
  }

  @override
  Widget build(BuildContext context) => GlassCard(
        radius: 22,
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(detail.email.isNotEmpty ? detail.email : 'Person ${shortId(detail.uid)}',
              style: MW.ui(15, color: MW.textDim, weight: 700)),
          const SizedBox(height: 8),
          Text(_headline, style: MW.display(22, color: detail.active ? MW.gold : MW.textFaint)),
          // Both can be true at once: a paying member who was also given Plus.
          for (final line in [
            if (detail.grantActive) 'Given by an admin',
            if (detail.purchaseSource != null) detail.purchaseSource!,
          ]) ...[
            const SizedBox(height: 4),
            Text(line, style: MW.ui(13.5, color: MW.textDim, weight: 600)),
          ],
          const SizedBox(height: 18),
          const Caps('Give Plus for'),
          const SizedBox(height: 10),
          FilterPillsInline<GrantLength>(
            options: [for (final l in GrantLength.values) (l, l.label)],
            value: length,
            onChanged: onLength,
          ),
          const SizedBox(height: 16),
          GlowButton('Give Plus', compact: true, isLoading: busy, onPressed: busy ? null : onGive),
          if (detail.promotional && detail.active) ...[
            const SizedBox(height: 4),
            Center(child: QuietLink('Take back given Plus', color: adminDanger, onPressed: busy ? null : onTake)),
          ],
          const SizedBox(height: 10),
          Text(
            'Giving Plus never charges anyone. Apple and Google run paid subscriptions, so cancelling or '
            'refunding one is done there.',
            style: MW.ui(12, color: MW.textFaint, height: 1.45),
          ),
        ]),
      );
}

class _MemberTile extends StatelessWidget {
  final SubscriberRecord person;
  final VoidCallback onTap;
  const _MemberTile({required this.person, required this.onTap});

  Color get _color => switch (person.status) {
        SubscriptionStatus.active => MW.goldBright,
        SubscriptionStatus.cancelled => MW.lilac,
        SubscriptionStatus.billingIssue => adminDanger,
        SubscriptionStatus.expired => MW.textFaint,
      };

  /// The line under the name: the purchase if there is a live one, otherwise a
  /// gift if there is, otherwise how the purchase ended.
  (String, Color) _line(DateTime now) {
    if (person.status.hasAccess) {
      return (
        [person.status.label, person.expiresAt == null ? 'lifetime' : 'until ${_date(person.expiresAt!)}'].join(' · '),
        _color,
      );
    }
    final g = person.grant;
    if (g != null && g.isActive(now)) {
      return (
        ['Given by an admin', g.lifetime ? 'for life' : 'until ${_date(g.until!)}'].join(' · '),
        MW.goldBright,
      );
    }
    final ended = person.expiresAt;
    return ([person.status.label, if (ended != null) 'ended ${_date(ended)}'].join(' · '), MW.textFaint);
  }

  @override
  Widget build(BuildContext context) {
    final (text, color) = _line(DateTime.now());
    return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Semantics(
          button: true,
          label: '${person.label}, $text',
          excludeSemantics: true,
          child: Pressable(
            onPressed: onTap,
            builder: (_) => GlassCard(
              radius: 18,
              blur: 8,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(person.label, style: MW.ui(15, color: MW.text, weight: 800)),
                const SizedBox(height: 3),
                Text(text, style: MW.ui(12.5, color: color, weight: 800)),
              ]),
            ),
          ),
        ),
      );
  }
}
