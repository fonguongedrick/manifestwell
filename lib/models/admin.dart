import 'wish.dart';

/// Remote settings an admin controls and every phone reads (config/app).
class AppConfig {
  static const bannerMax = 200;
  static const termsMax = 100;
  static const termLengthMax = 40;

  /// New wishes can't be shared while this is on. Daily Sparks and proof are
  /// private, so they carry on.
  final bool wishingPaused;

  /// A short notice shown at the top of the Well. Empty means none.
  final String banner;

  /// Words and phrases that keep a wish out of the Well.
  final List<String> blockedTerms;

  /// When and by whom these were last saved. For display only: not part of
  /// equality, so it never makes the Controls page think something changed.
  final DateTime? updatedAt;
  final String? updatedBy;

  const AppConfig({
    this.wishingPaused = false,
    this.banner = '',
    this.blockedTerms = const [],
    this.updatedAt,
    this.updatedBy,
  });

  static const defaults = AppConfig();

  AppConfig copyWith({bool? wishingPaused, String? banner, List<String>? blockedTerms}) => AppConfig(
        wishingPaused: wishingPaused ?? this.wishingPaused,
        banner: banner ?? this.banner,
        blockedTerms: blockedTerms ?? this.blockedTerms,
        updatedAt: updatedAt,
        updatedBy: updatedBy,
      );

  /// Tolerant of a missing or half-written document: anything unreadable falls
  /// back to the default, so a bad edit can never lock people out of the app.
  factory AppConfig.fromMap(Map<String, dynamic>? m) {
    if (m == null) return defaults;
    final terms = m['blockedTerms'];
    return AppConfig(
      wishingPaused: m['wishingPaused'] == true,
      banner: m['banner'] is String ? (m['banner'] as String).trim() : '',
      blockedTerms: terms is List ? [for (final t in terms) if (t is String && t.trim().isNotEmpty) t.trim()] : const [],
      updatedAt: m['updatedAt'] is DateTime ? m['updatedAt'] as DateTime : null,
      updatedBy: m['updatedBy'] is String ? m['updatedBy'] as String : null,
    );
  }

  /// Turns what an admin typed ("spam, buy now\nscam") into a clean list:
  /// lower-cased, de-duplicated, no empties, nothing absurdly long.
  static List<String> parseTerms(String raw) {
    final seen = <String>{};
    final out = <String>[];
    for (final part in raw.split(RegExp(r'[,\n]'))) {
      final t = part.trim().toLowerCase();
      if (t.length < 2 || t.length > termLengthMax) continue;
      if (seen.add(t)) out.add(t);
    }
    return out.take(termsMax).toList();
  }

  @override
  bool operator ==(Object other) =>
      other is AppConfig &&
      other.wishingPaused == wishingPaused &&
      other.banner == banner &&
      _sameList(other.blockedTerms, blockedTerms);

  @override
  int get hashCode => Object.hash(wishingPaused, banner, Object.hashAll(blockedTerms));

  static bool _sameList(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Someone an admin has stopped from sharing wishes or sending luck.
class BlockedPerson {
  final String uid;
  final String reason;
  final DateTime? at;
  const BlockedPerson({required this.uid, this.reason = '', this.at});
}

enum Audience {
  all('all', 'Everyone'),
  android('android', 'Android'),
  ios('ios', 'iPhone');

  final String id;
  final String label;
  const Audience(this.id, this.label);

  static Audience fromId(String? id) => values.firstWhere((a) => a.id == id, orElse: () => all);
}

enum AnnouncementStatus { queued, sending, sent, failed }

/// A push an admin queued for every phone in an audience.
class Announcement {
  static const titleMax = 60;
  static const bodyMax = 180;

  final String id;
  final String title;
  final String body;
  final Audience audience;
  final AnnouncementStatus status;
  final int sent;
  final int failed;
  final DateTime? at;
  const Announcement({
    required this.id,
    required this.title,
    required this.body,
    required this.audience,
    required this.status,
    this.sent = 0,
    this.failed = 0,
    this.at,
  });

  static AnnouncementStatus statusFrom(String? s) =>
      AnnouncementStatus.values.firstWhere((v) => v.name == s, orElse: () => AnnouncementStatus.queued);
}

/// One line of the admin audit trail.
class AdminLogEntry {
  final String id;
  final String action;
  final String detail;
  final String by;
  final DateTime? at;
  const AdminLogEntry({required this.id, required this.action, required this.detail, required this.by, this.at});
}

/// The parts of the dashboard. A role may or may not be allowed into each.
enum AdminArea { overview, moderation, people, announcements, subscriptions, controls, admins, activity, export }

/// What an admin may do. The server enforces this (security rules and the
/// functions); the app only uses it to hide what would be refused anyway.
///
/// - **Owner**: everything, including adding, removing and changing owners.
///   An admin created in the Firebase console, with no role, is an owner.
/// - **Admin**: everything except managing owners.
/// - **Moderator**: reviews wishes and reports and blocks people. Cannot send
///   announcements, change the app's controls, touch subscriptions, export
///   data or manage other admins.
enum AdminRole {
  owner('Owner', 'Everything, including other owners'),
  admin('Admin', 'Everything except managing owners'),
  moderator('Moderator', 'Reviews wishes and reports, blocks people');

  final String label;
  final String summary;
  const AdminRole(this.label, this.summary);

  String get id => name;

  /// The role stored on an admins/{uid} document. A document with no role is
  /// an owner if it was created in the console (no addedBy), and an admin if
  /// the app created it, which is how every admin added before roles existed
  /// was recorded.
  static AdminRole fromDoc(Map<String, dynamic>? data) {
    final role = data?['role'];
    for (final r in values) {
      if (r.name == role) return r;
    }
    return data?['addedBy'] == null ? owner : admin;
  }

  bool can(AdminArea area) => switch (this) {
        owner || admin => true,
        moderator => const {
            AdminArea.overview,
            AdminArea.moderation,
            AdminArea.people,
            AdminArea.activity,
          }.contains(area),
      };

  /// Whether this role may add, remove or change owners.
  bool get managesOwners => this == owner;
}

/// An admin as the Admins page lists them.
class AdminAccount {
  final String uid;
  final String email;
  final AdminRole role;

  /// The person looking at the list.
  final bool you;
  const AdminAccount({required this.uid, required this.email, this.role = AdminRole.admin, this.you = false});

  /// Created in the Firebase console. Only another owner can remove them.
  bool get owner => role == AdminRole.owner;

  /// What to show when the account has no email.
  String get label => email.isNotEmpty ? email : 'Admin ${uid.substring(0, uid.length < 6 ? uid.length : 6)}';
}

/// The reasons an admin picks from when removing or blocking. A reason goes
/// into the audit log so that every destructive action can be explained later.
enum ModerationReason {
  harassment('Harassment or unkindness'),
  spam('Spam or links'),
  personalInfo('Personal information'),
  selfHarm('Self-harm concern'),
  other('Something else');

  final String label;
  const ModerationReason(this.label);
}

/// Groups the audit log's actions, for filtering it.
enum ActivityGroup {
  moderation('Moderation', {'hide', 'restore', 'remove', 'dismiss', 'auto-hide', 'bulk'}),
  people('People', {'block', 'unblock'}),
  announcements('Announcements', {'announce', 'announce-test'}),
  subscriptions('Plus', {'grant', 'revoke'}),
  admins('Admins', {'admin-add', 'admin-remove', 'admin-role'}),
  settings('Controls', {'settings'});

  final String label;
  final Set<String> actions;
  const ActivityGroup(this.label, this.actions);

  static ActivityGroup? of(String action) {
    for (final g in values) {
      if (g.actions.contains(action)) return g;
    }
    return null;
  }
}

/// How long an admin can give Plus for. [id] is what the server expects.
enum GrantLength {
  week('week', '1 week'),
  month('month', '1 month'),
  quarter('quarter', '3 months'),
  year('year', '1 year'),
  lifetime('lifetime', 'Lifetime');

  final String id;
  final String label;
  const GrantLength(this.id, this.label);
}

enum SubscriptionStatus {
  active('Active'),

  /// Turned off renewal but still has access until the period ends.
  cancelled('Cancelled, still active'),
  billingIssue('Billing problem'),
  expired('Expired');

  final String label;
  const SubscriptionStatus(this.label);

  static SubscriptionStatus fromId(String? id) => switch (id) {
        'cancelled' => cancelled,
        'billing_issue' => billingIssue,
        'expired' => expired,
        _ => active,
      };

  bool get hasAccess => this != expired;
}

/// Plus an admin has given a person: for a while, or for life. Lives in the
/// person's own subscriptions record, so their phone can read it.
class PlusGrant {
  final bool lifetime;

  /// When it ends. Null for a lifetime gift.
  final DateTime? until;
  const PlusGrant({this.lifetime = false, this.until});

  bool isActive(DateTime now) => lifetime || (until != null && until!.isAfter(now));
}

/// "Bought on the App Store" for a store id as RevenueCat reports it. Its
/// webhook writes them in capitals (APP_STORE), so case is ignored.
String? storeLabel(String? store) => switch (store?.toLowerCase()) {
      null => null,
      'app_store' || 'mac_app_store' => 'Bought on the App Store',
      'play_store' => 'Bought on Google Play',
      'stripe' => 'Bought on the web',
      'amazon' => 'Bought on Amazon',
      _ => 'Bought in a store',
    };

/// One person's Plus for the dashboard's list: what they bought (recorded by
/// the RevenueCat webhook) and what an admin gave them.
class SubscriberRecord {
  final String uid;
  final String? email;

  /// Bought before ever signing in, so there is no account to show.
  final bool guest;

  /// The purchase's state. [SubscriptionStatus.expired] when they never bought.
  final SubscriptionStatus status;

  /// When the purchase ends. Null for a lifetime purchase or none at all.
  final DateTime? expiresAt;
  final String? store;
  final PlusGrant? grant;
  final DateTime? updatedAt;
  const SubscriberRecord({
    required this.uid,
    this.email,
    this.guest = false,
    required this.status,
    this.expiresAt,
    this.store,
    this.grant,
    this.updatedAt,
  });

  String get label => email ?? (guest ? 'Guest purchase' : 'Person ${uid.substring(0, uid.length < 6 ? uid.length : 6)}');

  /// Whether they have Plus at all right now, by purchase or by gift.
  bool hasPlus(DateTime now) => status.hasAccess || (grant?.isActive(now) ?? false);
}

/// What one person has right now, as the dashboard shows it.
class SubscriberDetail {
  final String uid;
  final String email;

  /// A store subscription, recorded by the RevenueCat webhook.
  final bool purchaseActive;
  final DateTime? purchaseExpiresAt;
  final String? store;

  /// Plus an admin gave, if it has not run out.
  final bool grantActive;
  final bool grantLifetime;
  final DateTime? grantExpiresAt;
  const SubscriberDetail({
    required this.uid,
    required this.email,
    this.purchaseActive = false,
    this.purchaseExpiresAt,
    this.store,
    this.grantActive = false,
    this.grantLifetime = false,
    this.grantExpiresAt,
  });

  bool get active => purchaseActive || grantActive;

  /// For life: only a gift can be.
  bool get lifetime => grantActive && grantLifetime;

  /// When Plus ends, counting whichever of the two lasts longer. Null for life
  /// or when there is none.
  DateTime? get expiresAt {
    if (!active || lifetime) return null;
    final ends = [
      if (purchaseActive && purchaseExpiresAt != null) purchaseExpiresAt!,
      if (grantActive && grantExpiresAt != null) grantExpiresAt!,
    ];
    if (ends.isEmpty) return null;
    return ends.reduce((a, b) => a.isAfter(b) ? a : b);
  }

  /// Plus an admin gave, which an admin can take back.
  bool get promotional => grantActive;

  /// "Bought on the App Store", or null if they have no purchase.
  String? get purchaseSource => purchaseActive ? storeLabel(store) : null;
}

/// A failure the admin can act on, with a message fit to show.
class AdminActionException implements Exception {
  final String message;
  const AdminActionException(this.message);

  @override
  String toString() => message;
}

class DailyCount {
  final DateTime day;
  final int count;
  const DailyCount(this.day, this.count);
}

/// Wishes, people and luck over one period.
class PeriodTotals {
  final int wishes;
  final int wishers;
  final int luck;
  const PeriodTotals({required this.wishes, required this.wishers, required this.luck});
}

/// How a figure changed against the period before: "up 12%", "down 3%".
/// Null when there is nothing sensible to say (no earlier figure, or it was
/// zero, where a percentage means nothing).
double? trendOf(int now, int before) => before <= 0 ? null : (now - before) / before;

/// Everything the Overview screen shows, gathered in one go.
class OverviewStats {
  final int wishes;
  final int hidden;
  final int openReports;
  final int luck;
  final int blocked;
  final int devices;
  final int androidDevices;
  final int iosDevices;
  final int luckAlertDevices;
  final int revisitDevices;

  /// People whose Plus is currently active (from the RevenueCat mirror).
  final int plusMembers;
  final Map<WishCategory, int> byCategory;

  /// Wishes cast per day over the window, oldest first, zeros included.
  final List<DailyCount> daily;

  /// Distinct people behind the wishes in the window.
  final int wishers;

  /// Luck on the wishes cast in the window.
  final int windowLuck;

  /// True when the window had more wishes than were read, so figures that come
  /// from it are a floor, not a total.
  final bool windowCapped;

  /// The same three figures for the period just before the window, for the
  /// trend arrows. Null when the window was too busy to read both in full, so
  /// a trend is never shown from partial data.
  final PeriodTotals? previous;

  /// When the oldest still-open report was filed: how long someone has been
  /// waiting for a moderator.
  final DateTime? oldestOpenReport;

  /// False when the figures about phones and Plus were not loaded because the
  /// role (a moderator) is not allowed to see them.
  final bool includesReach;

  const OverviewStats({
    required this.wishes,
    required this.hidden,
    required this.openReports,
    required this.luck,
    required this.blocked,
    required this.devices,
    required this.androidDevices,
    required this.iosDevices,
    required this.luckAlertDevices,
    required this.revisitDevices,
    this.plusMembers = 0,
    required this.byCategory,
    required this.daily,
    required this.wishers,
    required this.windowLuck,
    required this.windowCapped,
    this.previous,
    this.oldestOpenReport,
    this.includesReach = true,
  });

  int get windowWishes => daily.fold(0, (a, d) => a + d.count);
}

/// Buckets wish timestamps into one count per local day, oldest first, ending
/// on [now]'s day. Days with no wishes are present with a zero so a chart
/// never skips a day.
List<DailyCount> bucketByDay(Iterable<DateTime> times, {required DateTime now, required int days}) {
  final today = DateTime(now.year, now.month, now.day);
  final counts = <DateTime, int>{
    // Built from calendar fields, not by subtracting 24h, so a daylight-saving
    // change can't leave a key at 23:00 and miss its day.
    for (var i = days - 1; i >= 0; i--) DateTime(today.year, today.month, today.day - i): 0,
  };
  for (final t in times) {
    final local = t.toLocal();
    final key = DateTime(local.year, local.month, local.day);
    if (counts.containsKey(key)) counts[key] = counts[key]! + 1;
  }
  return [for (final e in counts.entries) DailyCount(e.key, e.value)];
}
