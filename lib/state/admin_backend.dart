import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/admin.dart';
import '../models/moderation.dart';
import '../models/wish.dart';
import '../utils/csv.dart';
import 'firestore_codec.dart';

enum AdminExport {
  wishes('wishes', 'Wishes'),
  reports('reports', 'Reports'),
  activity('activity', 'Activity log');

  final String file;
  final String label;
  const AdminExport(this.file, this.label);
}

/// Everything the admin dashboard does. Kept apart from [WellBackend] so the
/// member-facing app never carries it, and so tests can drive every screen
/// without Firestore.
abstract class AdminBackend {
  // ---- Moderation ----------------------------------------------------------

  /// Every wish, hidden ones included, newest first. [limit] is how many to
  /// read: it grows when an admin asks to load more.
  Stream<List<ModWish>> watchAllWishes({int limit = 200});

  /// Open reports, newest first.
  Stream<List<WishReport>> watchReports({int limit = 200});

  Future<void> setHidden(String wishId, bool hidden);

  /// Hides or restores several wishes at once, as one entry in the audit log.
  Future<void> setHiddenMany(List<String> wishIds, bool hidden);

  /// Removes a wish for good and clears the reports against it. A reason is
  /// required, and goes into the audit log, so every removal can be explained.
  Future<void> removeWish(String wishId, {required ModerationReason reason, String note = ''});

  /// [removeWish] for several wishes at once, as one entry in the audit log.
  Future<void> removeWishes(List<String> wishIds, {required ModerationReason reason, String note = ''});

  /// Clears reports without touching the wish (it was fine).
  Future<void> dismissReports(String wishId, List<String> reportIds);

  /// Clears every report on each of these wishes.
  Future<void> dismissReportsFor(List<String> wishIds);

  // ---- People ---------------------------------------------------------------

  Stream<List<BlockedPerson>> watchBlocked();

  /// Stops a person sharing wishes or sending luck, and hides what they have
  /// already shared. Their own private copy is untouched. A reason is required
  /// and is kept with the block.
  Future<void> block(String uid, {required ModerationReason reason, String note = ''});

  /// Lets them share again. Wishes hidden by the block stay hidden until an
  /// admin restores them one by one.
  Future<void> unblock(String uid);

  // ---- Admins ---------------------------------------------------------------

  Future<List<AdminAccount>> listAdmins();

  /// Makes the person with this email an admin, with [role]. They must already
  /// have an account; throws [AdminActionException] with a readable reason if not.
  Future<void> addAdmin(String email, {AdminRole role = AdminRole.admin});

  /// Changes an admin's role. Only an owner can, never for yourself, and never
  /// so that no owner is left.
  Future<void> setAdminRole(String uid, AdminRole role);

  /// Removes an admin. The server refuses to remove yourself, the last admin,
  /// or an owner (unless you are one).
  Future<void> removeAdmin(String uid);

  // ---- Subscriptions ----------------------------------------------------------

  /// People with Plus (or who had it), most recently changed first.
  Stream<List<SubscriberRecord>> watchSubscribers();

  /// One person's Plus: any store subscription (as the RevenueCat webhook
  /// recorded it) and any Plus an admin gave. [query] is an email or id.
  Future<SubscriberDetail> lookupSubscriber(String query);

  /// Gives Plus for a while, free. Never charges anyone. The person's phone
  /// reads it from their own record, so no store or key is involved.
  Future<SubscriberDetail> grantPlus(String uid, GrantLength length);

  /// Takes back Plus an admin gave. A store purchase can't be touched from
  /// here: only Apple or Google can cancel or refund that.
  Future<SubscriberDetail> revokeGivenPlus(String uid);

  // ---- Overview -------------------------------------------------------------

  /// The figures for the last [days] days. [includeReach] is false for a role
  /// that may not read phone and Plus figures (a moderator).
  Future<OverviewStats> loadOverview({DateTime? now, int days = 14, bool includeReach = true});

  // ---- Controls ---------------------------------------------------------------

  Future<void> saveConfig(AppConfig config);

  // ---- Announcements ----------------------------------------------------------

  Stream<List<Announcement>> watchAnnouncements();

  /// How many phones an announcement to [audience] would reach right now.
  Future<int> estimateReach(Audience audience);

  /// Sends the announcement to the admin's own phones only, marked as a test.
  /// Returns how many phones got it. Throws if this account has none.
  Future<int> sendTestAnnouncement({required String title, required String body});

  /// Queues a push; a Cloud Function delivers it and records the result.
  Future<void> sendAnnouncement({required String title, required String body, required Audience audience});

  // ---- Activity & export ------------------------------------------------------

  /// Newest first. [limit] grows when an admin asks to load more.
  Stream<List<AdminLogEntry>> watchLog({int limit = 100});

  /// The whole table as CSV text, ready to share as a file.
  Future<String> exportCsv(AdminExport what);
}

/// Firestore implementation. Every change an admin makes writes an entry to
/// `adminLog` in the same batch, so the trail can't miss an action.
class FirestoreAdminBackend implements AdminBackend {
  FirestoreAdminBackend(this._db, this._auth, this._functions);

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;
  final FirebaseFunctions _functions;

  /// Calls a Cloud Function and turns its failure into something readable.
  Future<Map<String, dynamic>> _call(String name, [Map<String, dynamic>? data]) async {
    try {
      final result = await _functions.httpsCallable(name).call<Object?>(data);
      final body = result.data;
      return body is Map ? Map<String, dynamic>.from(body) : const {};
    } on FirebaseFunctionsException catch (e) {
      throw AdminActionException(_friendly(e));
    }
  }

  /// A message the admin can act on. The server writes the ones for mistakes a
  /// person can fix; anything else is a fault on our side.
  static String _friendly(FirebaseFunctionsException e) {
    const fixable = {'not-found', 'invalid-argument', 'already-exists', 'failed-precondition', 'permission-denied'};
    final message = e.message ?? '';
    // A function that was never deployed answers "NOT_FOUND" and nothing else.
    if (e.code == 'not-found' && (message.isEmpty || message == 'NOT_FOUND')) {
      return 'The server side of this is not set up yet. Deploy the functions first.';
    }
    if (fixable.contains(e.code) && message.isNotEmpty) return message;
    return 'The server could not do that right now. Try again in a moment.';
  }

  static DateTime? _ms(Object? v) => v is num ? DateTime.fromMillisecondsSinceEpoch(v.toInt()) : null;

  static SubscriberDetail _detail(Map<String, dynamic> m) => SubscriberDetail(
        uid: m['uid'] as String,
        email: (m['email'] as String?) ?? '',
        purchaseActive: m['purchaseActive'] == true,
        purchaseExpiresAt: _ms(m['purchaseExpiresMs']),
        store: m['store'] as String?,
        grantActive: m['grantActive'] == true,
        grantLifetime: m['grantLifetime'] == true,
        grantExpiresAt: _ms(m['grantExpiresMs']),
      );

  /// A subscriptions document as a list row. A person who was only ever given
  /// Plus has no purchase fields, which reads as "expired" for the purchase.
  static SubscriberRecord _record(String id, Map<String, dynamic> d) {
    final lifetime = d['grantLifetime'] == true;
    final until = dateOf(d['grantUntil']);
    return SubscriberRecord(
      uid: id,
      email: d['email'] as String?,
      guest: d['guest'] == true,
      status: d['status'] == null ? SubscriptionStatus.expired : SubscriptionStatus.fromId(d['status'] as String?),
      expiresAt: dateOf(d['expiresAt']),
      store: d['store'] as String?,
      grant: lifetime || until != null ? PlusGrant(lifetime: lifetime, until: until) : null,
      updatedAt: dateOf(d['updatedAt']),
    );
  }

  CollectionReference<Map<String, dynamic>> get _wishes => _db.collection('wishes');
  CollectionReference<Map<String, dynamic>> get _reports => _db.collection('reports');
  CollectionReference<Map<String, dynamic>> get _blocked => _db.collection('blocked');
  CollectionReference<Map<String, dynamic>> get _devices => _db.collection('devices');

  String get _me => _auth.currentUser!.uid;

  void _log(WriteBatch batch, String action, String detail) {
    batch.set(_db.collection('adminLog').doc(), {
      'action': action,
      'detail': detail.length > 300 ? detail.substring(0, 300) : detail,
      'by': _me,
      'byLabel': _auth.currentUser?.email ?? '',
      'at': FieldValue.serverTimestamp(),
    });
  }

  // ---- Moderation ----------------------------------------------------------

  @override
  Stream<List<ModWish>> watchAllWishes({int limit = 200}) =>
      _wishes.orderBy('createdAt', descending: true).limit(limit).snapshots().map((s) => [
            for (final d in s.docs)
              if (d.data()['createdAt'] != null)
                ModWish(
                  wishFromDoc(d.id, d.data()),
                  hidden: d.data()['hidden'] == true,
                  authorUid: d.data()['authorUid'] as String?,
                ),
          ]);

  @override
  Stream<List<WishReport>> watchReports({int limit = 200}) =>
      _reports.orderBy('at', descending: true).limit(limit).snapshots().map((s) => [
            for (final d in s.docs)
              WishReport(
                id: d.id,
                wishId: d.data()['wishId'] as String,
                reason: (d.data()['reason'] as String?) ?? '',
                at: dateOf(d.data()['at']),
              ),
          ]);

  /// Writes in one batch, leaving room for the audit entry.
  static const _batchSize = 400;

  /// Firestore's limit for a `whereIn` query.
  static const _inLimit = 30;

  /// "k3f9a2, q8m2b7 and 4 more": enough to find the wishes again, short enough
  /// for one audit line.
  static String _ids(List<String> ids) {
    String short(String id) => id.length < 8 ? id : id.substring(id.length - 8);
    final shown = ids.take(3).map(short).join(', ');
    return ids.length > 3 ? '$shown and ${ids.length - 3} more' : shown;
  }

  /// "Spam or links: posted the same link three times", trimmed to fit.
  static String _why(ModerationReason reason, String note) {
    final n = note.trim();
    final text = n.isEmpty ? reason.label : '${reason.label}: $n';
    return text.length > 150 ? text.substring(0, 150) : text;
  }

  @override
  Future<void> setHidden(String wishId, bool hidden) {
    final batch = _db.batch()..update(_wishes.doc(wishId), {'hidden': hidden});
    _log(batch, hidden ? 'hide' : 'restore', 'wish $wishId');
    return batch.commit();
  }

  @override
  Future<void> setHiddenMany(List<String> wishIds, bool hidden) async {
    for (var i = 0; i < wishIds.length; i += _batchSize) {
      final batch = _db.batch();
      for (final id in wishIds.skip(i).take(_batchSize)) {
        batch.update(_wishes.doc(id), {'hidden': hidden});
      }
      // The audit entry rides in the first batch, so it can't be missed.
      if (i == 0) _log(batch, hidden ? 'hide' : 'restore', '${wishIds.length} wishes: ${_ids(wishIds)}');
      await batch.commit();
    }
  }

  @override
  Future<void> removeWish(String wishId, {required ModerationReason reason, String note = ''}) =>
      removeWishes([wishId], reason: reason, note: note);

  @override
  Future<void> removeWishes(List<String> wishIds, {required ModerationReason reason, String note = ''}) async {
    if (wishIds.isEmpty) return;
    final doomed = <DocumentReference<Map<String, dynamic>>>[for (final id in wishIds) _wishes.doc(id)];
    var reportCount = 0;
    for (var i = 0; i < wishIds.length; i += _inLimit) {
      final reports = await _reports.where('wishId', whereIn: wishIds.skip(i).take(_inLimit).toList()).get();
      reportCount += reports.size;
      doomed.addAll(reports.docs.map((r) => r.reference));
    }
    final summary = wishIds.length == 1 ? 'wish ${wishIds.single}' : '${wishIds.length} wishes: ${_ids(wishIds)}';
    for (var i = 0; i < doomed.length; i += _batchSize) {
      final batch = _db.batch();
      for (final ref in doomed.skip(i).take(_batchSize)) {
        batch.delete(ref);
      }
      if (i == 0) {
        _log(batch, 'remove', '$summary; $reportCount report${reportCount == 1 ? '' : 's'} cleared. Reason: ${_why(reason, note)}');
      }
      await batch.commit();
    }
  }

  @override
  Future<void> dismissReports(String wishId, List<String> reportIds) {
    final batch = _db.batch();
    for (final id in reportIds) {
      batch.delete(_reports.doc(id));
    }
    _log(batch, 'dismiss', '${reportIds.length} report${reportIds.length == 1 ? '' : 's'} on wish $wishId');
    return batch.commit();
  }

  @override
  Future<void> dismissReportsFor(List<String> wishIds) async {
    final refs = <DocumentReference<Map<String, dynamic>>>[];
    for (var i = 0; i < wishIds.length; i += _inLimit) {
      final reports = await _reports.where('wishId', whereIn: wishIds.skip(i).take(_inLimit).toList()).get();
      refs.addAll(reports.docs.map((r) => r.reference));
    }
    if (refs.isEmpty) return;
    for (var i = 0; i < refs.length; i += _batchSize) {
      final batch = _db.batch();
      for (final ref in refs.skip(i).take(_batchSize)) {
        batch.delete(ref);
      }
      if (i == 0) _log(batch, 'dismiss', '${refs.length} reports on ${wishIds.length} wishes: ${_ids(wishIds)}');
      await batch.commit();
    }
  }

  // ---- People ---------------------------------------------------------------

  @override
  Stream<List<BlockedPerson>> watchBlocked() =>
      _blocked.orderBy('at', descending: true).snapshots().map((s) => [
            for (final d in s.docs)
              BlockedPerson(uid: d.id, reason: (d.data()['reason'] as String?) ?? '', at: dateOf(d.data()['at'])),
          ]);

  @override
  Future<void> block(String uid, {required ModerationReason reason, String note = ''}) async {
    final theirs = await _wishes.where('authorUid', isEqualTo: uid).get();
    // A batch holds 500 writes; the block record and log entry take two.
    final groups = <List<DocumentReference<Map<String, dynamic>>>>[];
    for (var i = 0; i < theirs.docs.length; i += _batchSize) {
      groups.add([for (final d in theirs.docs.skip(i).take(_batchSize)) d.reference]);
    }
    if (groups.isEmpty) groups.add(const []);
    final why = _why(reason, note);
    for (var i = 0; i < groups.length; i++) {
      final batch = _db.batch();
      for (final ref in groups[i]) {
        batch.update(ref, {'hidden': true});
      }
      if (i == 0) {
        batch.set(_blocked.doc(uid), {
          'reason': why,
          'by': _me,
          'at': FieldValue.serverTimestamp(),
        });
        _log(batch, 'block', 'person $uid; ${theirs.size} wish${theirs.size == 1 ? '' : 'es'} hidden. Reason: $why');
      }
      await batch.commit();
    }
  }

  @override
  Future<void> unblock(String uid) {
    final batch = _db.batch()..delete(_blocked.doc(uid));
    _log(batch, 'unblock', 'person $uid');
    return batch.commit();
  }

  // ---- Admins ---------------------------------------------------------------

  @override
  Future<List<AdminAccount>> listAdmins() async {
    final r = await _call('mwAdminList');
    final rows = r['admins'];
    return [
      if (rows is List)
        for (final a in rows.whereType<Map>())
          AdminAccount(
            uid: a['uid'] as String,
            email: (a['email'] as String?) ?? '',
            role: AdminRole.values.firstWhere((r) => r.name == a['role'], orElse: () => AdminRole.admin),
            you: a['you'] == true,
          ),
    ];
  }

  @override
  Future<void> addAdmin(String email, {AdminRole role = AdminRole.admin}) =>
      _call('mwAdminAdd', {'email': email.trim(), 'role': role.id});

  @override
  Future<void> setAdminRole(String uid, AdminRole role) => _call('mwAdminSetRole', {'uid': uid, 'role': role.id});

  @override
  Future<void> removeAdmin(String uid) => _call('mwAdminRemove', {'uid': uid});

  // ---- Subscriptions ----------------------------------------------------------

  @override
  Stream<List<SubscriberRecord>> watchSubscribers() =>
      _db.collection('subscriptions').orderBy('updatedAt', descending: true).limit(200).snapshots().map((s) => [
            for (final d in s.docs) _record(d.id, d.data()),
          ]);

  @override
  Future<SubscriberDetail> lookupSubscriber(String query) async =>
      _detail(await _call('mwSubLookup', {'query': query.trim()}));

  @override
  Future<SubscriberDetail> grantPlus(String uid, GrantLength length) async =>
      _detail(await _call('mwSubGrant', {'uid': uid, 'kind': length.id}));

  @override
  Future<SubscriberDetail> revokeGivenPlus(String uid) async => _detail(await _call('mwSubRevoke', {'uid': uid}));

  // ---- Overview -------------------------------------------------------------

  static const _windowCap = 1000;

  Future<int> _count(Query<Map<String, dynamic>> q) async => (await q.count().get()).count ?? 0;

  @override
  Future<OverviewStats> loadOverview({DateTime? now, int days = 14, bool includeReach = true}) async {
    final clock = now ?? DateTime.now();
    final since = DateTime(clock.year, clock.month, clock.day - (days - 1));
    // The period just before, the same length, for the trend arrows.
    final before = DateTime(since.year, since.month, since.day - days);

    // Phone and Plus figures are for owners and admins. A moderator's role is
    // not allowed to read them, so they are not even asked for.
    Future<int> reach(Query<Map<String, dynamic>> q) => includeReach ? _count(q) : Future.value(0);

    final totals = _wishes.aggregate(count(), sum('luck')).get();
    final hidden = _count(_wishes.where('hidden', isEqualTo: true));
    final reports = _count(_reports);
    final oldestReport = _reports.orderBy('at').limit(1).get();
    final blocked = _count(_blocked);
    final devices = reach(_devices);
    final android = reach(_devices.where('platform', isEqualTo: 'android'));
    final ios = reach(_devices.where('platform', isEqualTo: 'ios'));
    final luckAlerts = reach(_devices.where('luckAlerts', isEqualTo: true));
    final revisit = reach(_devices.where('revisitNudges', isEqualTo: true));
    // Counted here, not by a query, so a gift that has run out is not counted.
    final plus = includeReach ? _db.collection('subscriptions').limit(_windowCap).get() : null;
    final categories = {
      for (final c in WishCategory.values.where((c) => c != WishCategory.daily))
        c: _count(_wishes.where('category', isEqualTo: c.name)),
    };
    // Both periods in one read, newest first.
    final window = _wishes
        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(before))
        .orderBy('createdAt', descending: true)
        .limit(_windowCap + 1)
        .get();

    final t = await totals;
    final w = await window;
    final capped = w.docs.length > _windowCap;
    final read = w.docs.take(_windowCap).toList();

    DateTime? created(QueryDocumentSnapshot<Map<String, dynamic>> d) => dateOf(d.data()['createdAt']);
    final current = [for (final d in read) if (created(d) != null && !created(d)!.isBefore(since)) d];
    final prior = [for (final d in read) if (created(d) != null && created(d)!.isBefore(since)) d];

    PeriodTotals totalsOf(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) => PeriodTotals(
          wishes: docs.length,
          wishers: {for (final d in docs) if (d.data()['authorUid'] != null) d.data()['authorUid']}.length,
          luck: docs.fold(0, (a, d) => a + ((d.data()['luck'] as num?)?.toInt() ?? 0)),
        );

    final now0 = totalsOf(current);
    final oldest = (await oldestReport).docs.firstOrNull;

    return OverviewStats(
      wishes: t.count ?? 0,
      luck: (t.getSum('luck') ?? 0).toInt(),
      hidden: await hidden,
      openReports: await reports,
      blocked: await blocked,
      devices: await devices,
      androidDevices: await android,
      iosDevices: await ios,
      luckAlertDevices: await luckAlerts,
      revisitDevices: await revisit,
      plusMembers: plus == null ? 0 : (await plus).docs.where((d) => _record(d.id, d.data()).hasPlus(clock)).length,
      byCategory: {for (final e in categories.entries) e.key: await e.value},
      daily: bucketByDay([for (final d in current) created(d)!], now: clock, days: days),
      wishers: now0.wishers,
      windowLuck: now0.luck,
      // If the read stopped while still inside the current period, that period
      // is incomplete. If it stopped later, the current period is complete but
      // the earlier one is not, so no trend is shown rather than a wrong one.
      windowCapped: capped && prior.isEmpty,
      previous: capped ? null : totalsOf(prior),
      oldestOpenReport: oldest == null ? null : dateOf(oldest.data()['at']),
      includesReach: includeReach,
    );
  }

  // ---- Controls ---------------------------------------------------------------

  @override
  Future<void> saveConfig(AppConfig config) {
    final batch = _db.batch()
      ..set(_db.collection('config').doc('app'), {
        'wishingPaused': config.wishingPaused,
        'banner': config.banner,
        'blockedTerms': config.blockedTerms,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': _me,
      });
    _log(
      batch,
      'settings',
      'wishing ${config.wishingPaused ? 'paused' : 'open'}; '
          'banner ${config.banner.isEmpty ? 'off' : 'on'}; ${config.blockedTerms.length} blocked terms',
    );
    return batch.commit();
  }

  // ---- Announcements ----------------------------------------------------------

  @override
  Stream<List<Announcement>> watchAnnouncements() =>
      _db.collection('announcements').orderBy('createdAt', descending: true).limit(30).snapshots().map((s) => [
            for (final d in s.docs)
              Announcement(
                id: d.id,
                title: (d.data()['title'] as String?) ?? '',
                body: (d.data()['body'] as String?) ?? '',
                audience: Audience.fromId(d.data()['audience'] as String?),
                status: Announcement.statusFrom(d.data()['status'] as String?),
                sent: (d.data()['sent'] as num?)?.toInt() ?? 0,
                failed: (d.data()['failed'] as num?)?.toInt() ?? 0,
                at: dateOf(d.data()['createdAt']),
              ),
          ]);

  @override
  Future<void> sendAnnouncement({required String title, required String body, required Audience audience}) {
    final batch = _db.batch()
      ..set(_db.collection('announcements').doc(), {
        'title': title.trim(),
        'body': body.trim(),
        'audience': audience.id,
        'createdBy': _me,
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'queued',
        'sent': 0,
        'failed': 0,
      });
    _log(batch, 'announce', '"${title.trim()}" to ${audience.label}');
    return batch.commit();
  }

  @override
  Future<int> estimateReach(Audience audience) => _count(
        audience == Audience.all ? _devices : _devices.where('platform', isEqualTo: audience.id),
      );

  @override
  Future<int> sendTestAnnouncement({required String title, required String body}) async {
    final r = await _call('mwAnnounceTest', {'title': title.trim(), 'body': body.trim()});
    return (r['sent'] as num?)?.toInt() ?? 0;
  }

  // ---- Activity & export ------------------------------------------------------

  @override
  Stream<List<AdminLogEntry>> watchLog({int limit = 100}) =>
      _db.collection('adminLog').orderBy('at', descending: true).limit(limit).snapshots().map((s) => [
            for (final d in s.docs)
              AdminLogEntry(
                id: d.id,
                action: (d.data()['action'] as String?) ?? '',
                detail: (d.data()['detail'] as String?) ?? '',
                by: (d.data()['byLabel'] as String?)?.isNotEmpty == true
                    ? d.data()['byLabel'] as String
                    : (d.data()['by'] as String?) ?? '',
                at: dateOf(d.data()['at']),
              ),
          ]);

  @override
  Future<String> exportCsv(AdminExport what) async {
    switch (what) {
      case AdminExport.wishes:
        final s = await _wishes.orderBy('createdAt', descending: true).limit(5000).get();
        return Csv.encode([
          ['id', 'created', 'category', 'luck', 'hidden', 'author', 'text'],
          for (final d in s.docs)
            [
              d.id,
              dateOf(d.data()['createdAt']),
              d.data()['category'],
              d.data()['luck'],
              d.data()['hidden'],
              d.data()['authorUid'],
              d.data()['text'],
            ],
        ]);
      case AdminExport.reports:
        final s = await _reports.orderBy('at', descending: true).limit(5000).get();
        return Csv.encode([
          ['id', 'reported', 'wish', 'reason'],
          for (final d in s.docs) [d.id, dateOf(d.data()['at']), d.data()['wishId'], d.data()['reason']],
        ]);
      case AdminExport.activity:
        final s = await _db.collection('adminLog').orderBy('at', descending: true).limit(5000).get();
        return Csv.encode([
          ['time', 'by', 'action', 'detail'],
          for (final d in s.docs) [dateOf(d.data()['at']), d.data()['byLabel'], d.data()['action'], d.data()['detail']],
        ]);
    }
  }
}
