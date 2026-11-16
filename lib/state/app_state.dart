import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/seed_wishes.dart';
import '../models/admin.dart';
import '../models/wish.dart';
import '../utils/haptics.dart';
import 'admin_backend.dart';
import 'push.dart';
import 'reminders.dart';
import 'subscriptions.dart';
import 'well_backend.dart';

/// Single seam between the UI and storage. Personal data (my wishes, the
/// Proof Vault, settings) stays on the device; the shared Well goes through
/// [WellBackend] when one is available and degrades to seed wishes when not.
class AppState extends ChangeNotifier {
  static const freeBigWishLimit = 1;
  static const luckForGoldenOrb = 5;

  final SharedPreferences _prefs;
  final DateTime Function() _now;
  final WellBackend? _backend;
  final Reminders _reminders;
  final Push _pushSvc;
  final Subscriptions _subs;
  StreamSubscription<bool>? _plusSub;
  StreamSubscription<String>? _tokenSub;
  StreamSubscription<PushTap>? _tapSub;

  /// The token this phone is currently registered under, so it can be removed
  /// when the person turns alerts off, signs out, or deletes their account.
  String? _registeredToken;

  /// Set when a notification is tapped; the home screen switches to that tab
  /// and clears it. A notifier (not a field) so a tap that launched the app is
  /// still seen by a screen that mounts afterwards.
  final ValueNotifier<int?> openTab = ValueNotifier(null);
  StreamSubscription<List<Wish>>? _wellSub;
  StreamSubscription<AppConfig>? _configSub;
  StreamSubscription<bool>? _adminSub;
  StreamSubscription<Map<String, int>>? _luckSub;
  Map<String, int> _myLuck = {};
  List<Wish> _remote = [];

  late final List<Wish> _seeds;
  List<Wish> _mine = [];
  final Set<String> _sentIds = {};
  WishCategory? filter;

  /// Text typed into the Well's Make a Wish card, waiting for the Cast ritual.
  String? pendingWish;

  bool onboarded;
  int reminderHour;
  int reminderMinute;
  bool remindersEnabled;
  bool hapticsEnabled;

  /// Which server pushes this phone wants. Both off means no device record.
  bool pushLuck;
  bool pushRevisit;

  /// The notification offer has been shown once; never nag.
  bool pushAsked;
  bool isAdmin = false;

  /// Remote settings from the admin dashboard. The defaults apply until (or
  /// unless) they load, so an unreachable server never blocks anything.
  AppConfig config = AppConfig.defaults;
  bool get wishingPaused => config.wishingPaused;

  /// Email or name of the signed-in account; null for a guest.
  String? accountLabel;

  /// Whether ManifestWell Plus is active. Driven by the store (via
  /// [Subscriptions]); the last known answer is remembered so an offline
  /// launch doesn't take it away from someone who paid.
  ///
  /// Plus an admin gave counts too, for as long as the gift lasts.
  bool get isPro => _plus || (_grant?.isActive(_now()) ?? false);
  bool _plus;
  PlusGrant? _grant;
  StreamSubscription<PlusGrant?>? _grantSub;
  int _luckSentToday = 0;
  String _luckDay = '';

  AppState._(this._prefs, this._now, this._backend, this._reminders, this._pushSvc, this._subs)
      : _plus = _prefs.getBool('plusCached') ?? false,
        onboarded = _prefs.getBool('onboarded') ?? false,
        reminderHour = _prefs.getInt('reminderHour') ?? 19,
        reminderMinute = _prefs.getInt('reminderMinute') ?? 0,
        remindersEnabled = _prefs.getBool('remindersEnabled') ?? false,
        hapticsEnabled = _prefs.getBool('hapticsEnabled') ?? true,
        pushLuck = _prefs.getBool('pushLuck') ?? false,
        pushRevisit = _prefs.getBool('pushRevisit') ?? false,
        pushAsked = _prefs.getBool('pushAsked') ?? false,
        _registeredToken = _prefs.getString('pushToken');

  static Future<AppState> load({
    DateTime Function()? now,
    WellBackend? backend,
    Reminders reminders = const NoReminders(),
    Push push = const NoPush(),
    Subscriptions subscriptions = const NoSubscriptions(),
  }) async {
    final s = AppState._(
      await SharedPreferences.getInstance(),
      now ?? DateTime.now,
      backend,
      reminders,
      push,
      subscriptions,
    );
    Haptics.enabled = s.hapticsEnabled;
    // Re-arm the reminder on every launch so a changed timezone or a restored
    // phone can't leave it silently dead.
    if (s.remindersEnabled) {
      unawaited(reminders
          .schedule(hour: s.reminderHour, minute: s.reminderMinute)
          .catchError((Object e) => debugPrint('Reminder schedule failed: $e')));
    }
    s._seeds = buildSeedWishes(s._now());
    final raw = s._prefs.getString('mine');
    if (raw != null) {
      s._mine = [
        for (final j in jsonDecode(raw) as List) Wish.fromJson(j as Map<String, dynamic>)
      ];
    }
    s._sentIds.addAll(s._prefs.getStringList('sentIds') ?? const []);
    s._luckDay = s._prefs.getString('luckDay') ?? '';
    s._luckSentToday = s._prefs.getInt('luckSentToday') ?? 0;
    s._rollDay();
    s.isAdmin = await backend?.checkAdmin() ?? false;
    s.accountLabel = backend?.accountLabel;
    s._listenMyLuck();
    unawaited(s._sync());
    s._wellSub = backend?.watchWell().listen((w) {
      s._remote = w;
      s.notifyListeners();
    }, onError: (Object e) => debugPrint('Well feed error: $e'));
    s._configSub = backend?.watchConfig().listen((c) {
      s.config = c;
      s.notifyListeners();
    }, onError: (Object e) => debugPrint('Config feed error: $e'));
    s._tokenSub = push.tokenChanges.listen((_) => unawaited(s._syncDevice()));
    s._tapSub = push.taps.listen(s._onPushTap);
    unawaited(push.launchTap().then((t) {
      if (t != null) s._onPushTap(t);
    }));
    unawaited(s._syncDevice());
    s._plusSub = subscriptions.plusChanges.listen(s._setPlus);
    unawaited(s._refreshPlus());
    return s;
  }

  String get _today => DateFormat('yyyy-MM-dd').format(_now());

  void _rollDay() {
    if (_luckDay != _today) {
      _luckDay = _today;
      _luckSentToday = 0;
    }
  }

  // ---- Well feed ----------------------------------------------------------

  List<Wish> get feed {
    final all = [
      ..._mineLive.where((w) => w.status.isOpen),
      ..._remote,
      ..._seeds,
    ].where((w) => filter == null || w.category == filter).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return all.map((w) {
      // Seeds have no server counter, so show the local +1. Remote wishes
      // already include it once the write reaches the snapshot.
      return _sentIds.contains(w.id) && w.isSeed ? w.copyWith(luck: w.luck + 1) : w;
    }).toList();
  }

  bool hasSentLuck(String id) => _sentIds.contains(id);

  int get luckSentToday {
    _rollDay();
    return _luckSentToday;
  }

  bool get goldenOrbUnlocked => luckSentToday >= luckForGoldenOrb;

  /// Returns true if the luck was newly sent. One send per wish per person.
  Future<bool> sendLuck(String id) async {
    if (_sentIds.contains(id) || _mine.any((w) => w.id == id)) return false;
    _rollDay();
    _sentIds.add(id);
    _luckSentToday++;
    notifyListeners();
    if (!_seeds.any((w) => w.id == id)) {
      unawaited(_backend?.sendLuck(id).catchError((Object e) {
        debugPrint('sendLuck failed: $e');
      }));
    }
    await _prefs.setStringList('sentIds', _sentIds.toList());
    await _prefs.setString('luckDay', _luckDay);
    await _prefs.setInt('luckSentToday', _luckSentToday);
    return true;
  }

  void stagePending(String text) {
    pendingWish = text;
    notifyListeners();
  }

  String? takePending() {
    final t = pendingWish;
    pendingWish = null;
    return t;
  }

  void setFilter(WishCategory? c) {
    filter = c;
    notifyListeners();
  }

  // ---- My wishes ----------------------------------------------------------

  /// My wishes with the luck the Well has reported for them.
  List<Wish> get _mineLive => [
        for (final w in _mine) w.copyWith(luck: math.max(w.luck, _myLuck[w.id] ?? 0)),
      ];

  List<Wish> get activeWishes => _mineLive.where((w) => w.status.isOpen).toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  /// Newest first. Granted and "different door" wishes are the proof.
  List<Wish> get proof => _mineLive.where((w) => w.status.isProof).toList()
    ..sort((a, b) => (b.resolvedAt ?? b.createdAt).compareTo(a.resolvedAt ?? a.createdAt));

  int get wishesCast => _mine.length;
  int get luckSentTotal => _sentIds.length;

  int get totalLuckReceived => _mineLive.fold(0, (a, w) => a + w.luck);

  bool get canCastBigWish =>
      isPro ||
      _mine.where((w) => w.kind == WishKind.big && w.status.isOpen).length < freeBigWishLimit;

  /// Daily Sparks already happened, so they never count against the free limit.
  Future<Wish?> cast(String text, WishKind kind, WishCategory category,
      {String? tag}) async {
    if (kind == WishKind.big && !canCastBigWish) return null;
    final now = _now();
    final wish = Wish(
      id: 'w_${now.microsecondsSinceEpoch}',
      text: text.trim(),
      kind: kind,
      category: kind == WishKind.spark ? WishCategory.daily : category,
      createdAt: now,
      // A spark is a win that already happened, so it goes straight to the vault.
      status: kind == WishKind.spark ? WishStatus.granted : WishStatus.active,
      resolvedAt: kind == WishKind.spark ? now : null,
      isMine: true,
      tag: tag,
      updatedAt: now,
    );
    _mine = [wish, ..._mine];
    await _persistMine();
    _push(wish);
    // Sparks are private wins; only Big Wishes go into the shared Well.
    if (kind == WishKind.big) {
      unawaited(_backend?.publish(wish).catchError((Object e) {
        debugPrint('publish failed: $e');
      }));
    }
    return wish;
  }

  Future<void> resolve(String id, WishStatus status, {String? note, String? newText}) async {
    _mine = [
      for (final w in _mine)
        if (w.id == id)
          w.copyWith(
            status: status,
            note: (note?.trim().isEmpty ?? true) ? w.note : note!.trim(),
            text: newText,
            resolvedAt: status.isOpen ? null : _now(),
            updatedAt: _now(),
            // The Well copy is deleted on resolve, so keep the luck it earned.
            luck: math.max(w.luck, _myLuck[w.id] ?? 0),
          )
        else
          w
    ];
    await _persistMine();
    _push(_mine.firstWhere((w) => w.id == id));
    if (!status.isOpen) {
      unawaited(_backend?.withdraw(id).catchError((Object e) {
        debugPrint('withdraw failed: $e');
      }));
    }
  }

  // ---- Small steps --------------------------------------------------------
  //
  // A wish can be broken into small steps. They live on the wish, so they
  // are saved with it, sync with the account, and are never shared in the Well.

  /// One of my own wishes, with the luck the Well has reported for it.
  Wish? myWish(String id) => _mineLive.where((w) => w.id == id).firstOrNull;

  /// Adds steps to a wish and returns how many were really added. Blank and
  /// repeated steps are skipped, long ones are trimmed, and a wish holds at
  /// most [WishStep.maxPerWish].
  Future<int> addSteps(String wishId, Iterable<String> texts) async {
    final wish = _mine.where((w) => w.id == wishId).firstOrNull;
    if (wish == null) return 0;
    final steps = [...wish.steps];
    final stamp = _now().microsecondsSinceEpoch;
    var added = 0;
    var n = 0;
    for (final raw in texts) {
      var text = raw.trim();
      if (text.isEmpty || steps.length >= WishStep.maxPerWish) continue;
      // By characters (runes), so an emoji is never cut in half.
      if (text.runes.length > WishStep.maxLength) {
        text = String.fromCharCodes(text.runes.take(WishStep.maxLength)).trimRight();
      }
      if (steps.any((s) => s.text.toLowerCase() == text.toLowerCase())) continue;
      String id;
      do {
        id = 's_${stamp}_${n++}';
      } while (steps.any((s) => s.id == id));
      steps.add(WishStep(id: id, text: text));
      added++;
    }
    if (added > 0) await _changeWish(wishId, (w) => w.copyWith(steps: steps));
    return added;
  }

  Future<void> toggleStep(String wishId, String stepId) => _changeWish(
        wishId,
        (w) => w.copyWith(steps: [for (final s in w.steps) s.id == stepId ? s.toggled(_now()) : s]),
      );

  Future<void> removeStep(String wishId, String stepId) =>
      _changeWish(wishId, (w) => w.copyWith(steps: [for (final s in w.steps) if (s.id != stepId) s]));

  /// Applies a change to one of my wishes, stamps it as modified (so the newest
  /// copy wins when two devices disagree), saves it and uploads it.
  Future<void> _changeWish(String id, Wish Function(Wish) change) async {
    if (!_mine.any((w) => w.id == id)) return;
    _mine = [for (final w in _mine) w.id == id ? change(w).copyWith(updatedAt: _now()) : w];
    await _persistMine();
    _push(_mine.firstWhere((w) => w.id == id));
  }

  // ---- Account sync -------------------------------------------------------
  //
  // A signed-in account keeps its wishes in a private cloud space so a new
  // phone gets them back. A guest stays local-only, and nothing a guest writes
  // (sparks and notes included) leaves the device.

  /// Fire-and-forget upload of one wish; a failure is retried by the next sync.
  void _push(Wish w) {
    final backend = _backend;
    if (backend == null || accountLabel == null) return;
    unawaited(backend.saveMyWish(w).catchError((Object e) {
      debugPrint('saveMyWish failed: $e');
    }));
  }

  /// Re-attaches everything that belongs to the current account. Called at
  /// launch and whenever the account changes.
  void _listenMyLuck() {
    _luckSub?.cancel();
    _myLuck = {};
    _luckSub = _backend?.watchMyLuck().listen((m) {
      _myLuck = m;
      notifyListeners();
    }, onError: (Object e) => debugPrint('Luck feed error: $e'));
    _listenGrant();
    _listenAdmin();
  }

  /// Keeps [isAdmin] true to the account's admin record. An error (offline,
  /// rules) is ignored on purpose: it must never promote anyone, and the
  /// server rules are what actually protect the data.
  void _listenAdmin() {
    _adminSub?.cancel();
    _adminSub = _backend?.watchAdmin().listen((admin) {
      if (admin == isAdmin) return;
      isAdmin = admin;
      notifyListeners();
    }, onError: (Object e) => debugPrint('Admin status feed error: $e'));
  }

  /// Plus an admin has given this account. It is read from the account's own
  /// record, so it follows them to a new phone, and the store subscription
  /// (RevenueCat) is untouched.
  void _listenGrant() {
    _grantSub?.cancel();
    _grant = null;
    _grantSub = _backend?.watchPlusGrant().listen((g) {
      _grant = g;
      notifyListeners();
    }, onError: (Object e) => debugPrint('Plus grant feed error: $e'));
  }

  /// Merges this device with the cloud, newest change wins per wish, then
  /// uploads anything the cloud is missing or has an older copy of.
  Future<void> _sync() async {
    final backend = _backend;
    if (backend == null || accountLabel == null) return;
    try {
      final remote = {for (final w in await backend.fetchMyWishes()) w.id: w};
      final local = {for (final w in _mine) w.id: w};
      final merged = <String, Wish>{};
      final upload = <Wish>[];
      for (final id in {...remote.keys, ...local.keys}) {
        final r = remote[id];
        final l = local[id];
        if (l == null) {
          merged[id] = r!;
        } else if (r == null || l.modified.isAfter(r.modified)) {
          merged[id] = l;
          upload.add(l);
        } else {
          merged[id] = r;
        }
      }
      _mine = merged.values.toList();
      await _persistMine();
      for (final w in upload) {
        await backend.saveMyWish(w);
      }
    } catch (e) {
      debugPrint('Account sync failed: $e');
    }
  }

  // ---- Plus subscription --------------------------------------------------

  /// False when no store is configured (no key, or an unsupported platform).
  bool get purchasesAvailable => _subs.available;

  Future<void> _setPlus(bool value) async {
    if (value == _plus) return;
    _plus = value;
    notifyListeners();
    await _prefs.setBool('plusCached', value);
  }

  /// Links purchases to the current account, then reads the entitlement. A
  /// failed read (offline) leaves the remembered answer alone.
  Future<void> _refreshPlus() async {
    await _subs.identify(_backend?.accountId);
    final known = await _subs.isPlus();
    if (known != null) await _setPlus(known);
  }

  Future<List<Plan>> loadPlans() => _subs.plans();

  Future<BuyResult> buyPlan(Plan plan) async {
    final result = await _subs.buy(plan);
    if (result.outcome == PurchaseOutcome.success) await _setPlus(true);
    return result;
  }

  /// True if Plus is active after restoring. Throws if the store can't be reached.
  Future<bool> restorePurchases() async {
    final active = await _subs.restore();
    await _setPlus(active);
    return active;
  }

  Future<Uri> manageSubscriptionUrl() => _subs.managementUrl();

  // ---- Push notifications -------------------------------------------------
  //
  // The server pushes for a member's own wishes (luck received, revisit
  // nudges). This phone is registered with the server only while the person
  // has at least one of those switched on AND the OS allows notifications.

  bool get pushAnyOn => pushLuck || pushRevisit;

  /// Whether now is a good moment to offer notifications: the first time the
  /// person has put a wish into the Well, and only once.
  bool get shouldOfferPush =>
      hasBackend &&
      !pushAsked &&
      !pushAnyOn &&
      _mine.any((w) => w.kind == WishKind.big);

  Future<void> markPushAsked() async {
    pushAsked = true;
    await _prefs.setBool('pushAsked', true);
  }

  /// Turns server pushes on or off. Returns false, changing nothing, when a
  /// switch was turned on but the OS permission was refused.
  Future<bool> setPush({bool? luck, bool? revisit}) async {
    final nextLuck = luck ?? pushLuck;
    final nextRevisit = revisit ?? pushRevisit;
    final turningOn = (nextLuck && !pushLuck) || (nextRevisit && !pushRevisit);
    if (turningOn && !await _pushSvc.requestPermission()) return false;
    pushLuck = nextLuck;
    pushRevisit = nextRevisit;
    notifyListeners();
    await _prefs.setBool('pushLuck', nextLuck);
    await _prefs.setBool('pushRevisit', nextRevisit);
    await _syncDevice();
    return true;
  }

  /// Makes the server's record of this phone match what the person wants.
  Future<void> _syncDevice() async {
    final backend = _backend;
    if (backend == null) return;
    try {
      if (!pushAnyOn) {
        await _unregisterDevice();
        return;
      }
      // The person may have revoked permission in the phone's own settings.
      if (!await _pushSvc.isAuthorized()) return;
      final token = await _pushSvc.token();
      if (token == null) return;
      final previous = _registeredToken;
      await backend.registerDevice(
        token: token,
        platform: defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
        timezone: await _pushSvc.timezone(),
        luckAlerts: pushLuck,
        revisitNudges: pushRevisit,
      );
      _registeredToken = token;
      await _prefs.setString('pushToken', token);
      // A rotated token leaves the old record behind; remove it.
      if (previous != null && previous != token) {
        await backend.unregisterDevice(previous);
      }
    } catch (e) {
      debugPrint('Push registration failed: $e');
    }
  }

  Future<void> _unregisterDevice() async {
    final token = _registeredToken;
    if (token == null) return;
    await _backend?.unregisterDevice(token);
    _registeredToken = null;
    await _prefs.remove('pushToken');
  }

  void _onPushTap(PushTap tap) {
    // Luck and revisit pushes are about the person's own wishes, which live in
    // the Vault. A note from the team has nowhere in particular to go.
    if (tap.type == 'announcement') return;
    openTab.value = 2;
  }

  // ---- Moderation ---------------------------------------------------------

  /// False in local-only mode, where there is nothing to report or moderate.
  bool get hasBackend => _backend != null;

  Future<void> report(String wishId, String reason) async {
    await _backend?.report(wishId, reason);
  }

  /// Returns true when the account is an admin. Throws on a wrong password.
  Future<bool> signInAdmin(String email, String password) async {
    final ok = await _backend?.signInAdmin(email, password) ?? false;
    isAdmin = ok;
    accountLabel = _backend?.accountLabel;
    if (ok) {
      _listenMyLuck();
      await _sync();
      unawaited(_syncDevice());
    }
    notifyListeners();
    return ok;
  }

  Future<void> signOut() async {
    final wasAccount = accountLabel != null;
    if (wasAccount) {
      // Signing out wipes this phone's copy, so every wish must already be in
      // the account. If any upload fails this throws and nothing is signed out.
      for (final w in _mine) {
        await _backend?.saveMyWish(w);
      }
    }
    // Stop this phone receiving the old account's pushes before the account
    // goes; it re-registers under the new guest session below.
    try {
      await _unregisterDevice();
    } catch (e) {
      debugPrint('Could not unregister the device: $e');
    }
    await _backend?.signOut();
    unawaited(_syncDevice());
    unawaited(_refreshPlus());
    isAdmin = false;
    accountLabel = null;
    if (wasAccount) {
      // These wishes live in the account now. Leaving them here would hand
      // them to whoever signs in on this phone next.
      _mine = [];
      await _prefs.remove('mine');
    }
    _listenMyLuck();
    notifyListeners();
  }

  /// Returns false when the person dismissed the sheet; throws on failure.
  Future<bool> signInWithGoogle() => _signInWith(() => _backend?.signInWithGoogle());
  Future<bool> signInWithApple() => _signInWith(() => _backend?.signInWithApple());

  Future<bool> _signInWith(Future<bool>? Function() attempt) async {
    final ok = await attempt() ?? false;
    if (ok) {
      // The account may be an admin one, and the label changes either way.
      isAdmin = await _backend?.checkAdmin() ?? false;
      accountLabel = _backend?.accountLabel;
      _listenMyLuck();
      notifyListeners();
      await _sync();
      // The phone may now belong to a different account than before.
      unawaited(_syncDevice());
      unawaited(_refreshPlus());
    }
    return ok;
  }

  /// The dashboard's tools; null in local-only mode.
  AdminBackend? get adminTools => _backend?.adminTools;

  @override
  void dispose() {
    _wellSub?.cancel();
    _configSub?.cancel();
    _adminSub?.cancel();
    _grantSub?.cancel();
    _luckSub?.cancel();
    _tokenSub?.cancel();
    _tapSub?.cancel();
    _plusSub?.cancel();
    openTab.dispose();
    super.dispose();
  }

  Future<void> _persistMine() async {
    notifyListeners();
    await _prefs.setString('mine', jsonEncode(_mine.map((w) => w.toJson()).toList()));
  }

  // ---- Onboarding / settings ----------------------------------------------

  Future<void> completeOnboarding() async {
    onboarded = true;
    notifyListeners();
    await _prefs.setBool('onboarded', true);
  }

  /// Returns false when reminders were asked for but the OS permission was
  /// refused; the switch then stays off so the screen never lies.
  Future<bool> setReminder({required int hour, required int minute, required bool enabled}) async {
    var on = enabled;
    if (on && !await _reminders.requestPermission()) on = false;
    reminderHour = hour;
    reminderMinute = minute;
    remindersEnabled = on;
    notifyListeners();
    await _prefs.setInt('reminderHour', hour);
    await _prefs.setInt('reminderMinute', minute);
    await _prefs.setBool('remindersEnabled', on);
    try {
      if (on) {
        await _reminders.schedule(hour: hour, minute: minute);
      } else {
        await _reminders.cancel();
      }
    } catch (e) {
      debugPrint('Reminder update failed: $e');
    }
    return on == enabled;
  }

  Future<void> setHaptics(bool on) async {
    hapticsEnabled = on;
    Haptics.enabled = on;
    notifyListeners();
    await _prefs.setBool('hapticsEnabled', on);
  }

  // ---- Your data ----------------------------------------------------------

  /// Everything the app holds about you, as readable JSON, for the person to
  /// keep or take elsewhere.
  String exportData() => const JsonEncoder.withIndent('  ').convert({
        'app': 'ManifestWell',
        'exportedAt': _now().toIso8601String(),
        'account': accountLabel ?? 'Guest',
        'settings': {
          'dailyReminder': remindersEnabled,
          'reminderTime':
              '${reminderHour.toString().padLeft(2, '0')}:${reminderMinute.toString().padLeft(2, '0')}',
          'haptics': hapticsEnabled,
          'pushLuckAlerts': pushLuck,
          'pushRevisitNudges': pushRevisit,
        },
        'plus': isPro,
        'wishes': [for (final w in _mine) w.toJson()],
      });

  /// Deletes the account (if any) and everything stored for it, on the server
  /// and on this phone, then returns the app to its first-run state. Returns
  /// false if the person backed out; throws if the server refused.
  Future<bool> deleteEverything() async {
    final done = await _backend?.deleteAccount() ?? true;
    if (!done) return false;
    await _reminders.cancel();
    await _pushSvc.revoke();
    // The store subscription itself is not ours to cancel; only the link to
    // this account is dropped. The person is told so before they delete.
    await _subs.identify(null);
    await _prefs.clear();
    _plus = false;
    _registeredToken = null;
    pushLuck = false;
    pushRevisit = false;
    pushAsked = false;
    _mine = [];
    _sentIds.clear();
    _myLuck = {};
    _luckSentToday = 0;
    isAdmin = false;
    accountLabel = null;
    remindersEnabled = false;
    hapticsEnabled = true;
    Haptics.enabled = true;
    reminderHour = 19;
    reminderMinute = 0;
    onboarded = false;
    _listenMyLuck();
    notifyListeners();
    return true;
  }
}
