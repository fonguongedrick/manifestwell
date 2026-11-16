import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../models/admin.dart';
import '../models/wish.dart';
import 'admin_backend.dart';
import 'firestore_codec.dart';

/// The shared, anonymous Wishing Well. AppState talks only to this seam, so
/// the app runs unchanged offline (no backend) or against Firestore.
abstract class WellBackend {
  /// Wishes from other people, newest first. Never includes the caller's own.
  Stream<List<Wish>> watchWell();

  /// Put one of the caller's Big Wishes into the shared Well.
  Future<void> publish(Wish wish);

  /// Add one luck to a wish. Must be a no-op the second time for the same person.
  Future<void> sendLuck(String wishId);

  /// Take the caller's wish back out of the Well.
  Future<void> withdraw(String wishId);

  /// Flag a wish for an admin to review.
  Future<void> report(String wishId, String reason);

  // ---- My wishes (private, signed-in accounts only) ------------------------------

  /// The caller's own wishes from the cloud: every Big Wish and Daily Spark,
  /// resolved or not. Empty for a guest.
  Future<List<Wish>> fetchMyWishes();

  /// Create or replace one of the caller's wishes in their private space.
  Future<void> saveMyWish(Wish wish);

  /// Luck received per wish id, for the caller's wishes that are in the Well.
  Stream<Map<String, int>> watchMyLuck();

  // ---- Push notifications ---------------------------------------------------

  /// Tells the server this phone may be sent pushes for the caller's wishes,
  /// and which kinds. Replaces any earlier record for the same token, even one
  /// left by a previous account on this phone.
  Future<void> registerDevice({
    required String token,
    required String platform,
    required String timezone,
    required bool luckAlerts,
    required bool revisitNudges,
  });

  /// Stops the server sending to this phone. Safe to call when it isn't registered.
  Future<void> unregisterDevice(String token);

  // ---- Account --------------------------------------------------------------

  /// Email or name of the signed-in account, or null while the person is a guest.
  String? get accountLabel;

  /// Stable id of the signed-in account, or null for a guest. Purchases are
  /// attached to this so they follow the account to a new phone.
  String? get accountId;

  /// Each returns false when the person dismissed the system sheet, and throws
  /// on a real failure. A guest session is upgraded in place, so wishes they
  /// already cast stay theirs.
  Future<bool> signInWithGoogle();
  Future<bool> signInWithApple();

  /// Signs out and goes back to a fresh guest session.
  Future<void> signOut();

  /// Permanently deletes the caller's account and everything they put in the
  /// Well or their private space, then starts a fresh guest session. Returns
  /// false (changing nothing) if they backed out of the confirmation.
  Future<bool> deleteAccount();

  // ---- Admin ----------------------------------------------------------------

  /// Whether the current Firebase user is a BraidsTribe/ManifestWell admin.
  Future<bool> checkAdmin();

  /// Signs in with email and password. Returns false (and goes back to an
  /// anonymous session) when the account isn't an admin.
  Future<bool> signInAdmin(String email, String password);

  /// Whether the signed-in account is an admin, kept live: it flips to false
  /// the moment the admin record is removed, so a removed admin loses the
  /// dashboard while the app is open, not at the next launch. False for a guest.
  Stream<bool> watchAdmin();

  /// The dashboard's tools (moderation, people, announcements, settings).
  /// Null in local-only mode. Only an admin's account can use them; the
  /// security rules enforce that, not this getter.
  AdminBackend? get adminTools;

  /// Plus an admin has given the signed-in account, or null. Emits null for a
  /// guest. The app decides whether it has run out.
  Stream<PlusGrant?> watchPlusGrant();

  /// Remote settings every phone follows: the pause switch, the banner, the
  /// blocked terms. Emits the defaults when none are set or they can't load.
  Stream<AppConfig> watchConfig();
}

/// Anonymous Firebase Auth + Firestore. Auth is shared with BraidsTribe (one
/// Firebase project), but the data lives in its own named database,
/// [databaseId], with its own rules and indexes:
///  - `wishes/{id}`: text, kind, category, createdAt, luck, authorUid, hidden
///  - `wishes/{id}/luck/{uid}`: one marker per sender, which is what makes
///    "one luck per person per wish" enforceable in security rules
///  - `reports/{auto}`: create-only flags; only an admin can read them
///  - `admins/{uid}`: a document here makes that user an admin
///
/// Rules in another database can't read BraidsTribe's `users` collection, so
/// admin is its own list rather than users/{uid}.isAdmin.
class FirestoreWellBackend implements WellBackend {
  static const databaseId = 'manifestwell';

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;
  FirestoreWellBackend._(this._db, this._auth);

  /// Returns null when Firebase isn't configured for this build (no
  /// google-services / firebase_options yet) or sign-in fails, so the caller
  /// can fall back to local-only mode instead of crashing at launch.
  static Future<FirestoreWellBackend?> tryCreate() async {
    try {
      if (Firebase.apps.isEmpty) await Firebase.initializeApp();
      final auth = FirebaseAuth.instance;
      if (auth.currentUser == null) await auth.signInAnonymously();
      return FirestoreWellBackend._(
        FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: databaseId),
        auth,
      );
    } catch (e) {
      debugPrint('Firebase unavailable, running local-only: $e');
      return null;
    }
  }

  String get _uid => _auth.currentUser!.uid;

  CollectionReference<Map<String, dynamic>> get _wishes => _db.collection('wishes');
  CollectionReference<Map<String, dynamic>> get _reports => _db.collection('reports');

  @override
  Stream<List<Wish>> watchWell() => _wishes
      .where('hidden', isEqualTo: false)
      .orderBy('createdAt', descending: true)
      .limit(100)
      .snapshots()
      .map((s) => [
            for (final d in s.docs)
              // createdAt is null for a moment on our own pending writes.
              if (d.data()['authorUid'] != _uid && d.data()['createdAt'] != null)
                wishFromDoc(d.id, d.data()),
          ]);

  @override
  Future<void> publish(Wish wish) => _wishes.doc(wish.id).set({
        'text': wish.text,
        'kind': wish.kind.name,
        'category': wish.category.name,
        'createdAt': FieldValue.serverTimestamp(),
        'luck': 0,
        'authorUid': _uid,
        'hidden': false,
      });

  @override
  Future<void> sendLuck(String wishId) async {
    final wish = _wishes.doc(wishId);
    final marker = wish.collection('luck').doc(_uid);
    // Both writes land together or not at all; the rules require the marker
    // to be new and the counter to rise by exactly one.
    final batch = _db.batch()
      ..set(marker, {'at': FieldValue.serverTimestamp()})
      ..update(wish, {'luck': FieldValue.increment(1)});
    await batch.commit();
  }

  @override
  Future<void> withdraw(String wishId) => _wishes.doc(wishId).delete();

  @override
  Future<void> report(String wishId, String reason) => _reports.add({
        'wishId': wishId,
        'reason': reason,
        'reporterUid': _uid,
        'at': FieldValue.serverTimestamp(),
      });

  // ---- Admin ----------------------------------------------------------------

  @override
  Future<bool> checkAdmin() async {
    final user = _auth.currentUser;
    if (user == null || user.isAnonymous) return false;
    try {
      final doc = await _db.collection('admins').doc(user.uid).get();
      return doc.exists;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> signInAdmin(String email, String password) async {
    await _auth.signInWithEmailAndPassword(email: email.trim(), password: password);
    if (await checkAdmin()) return true;
    // A valid account that isn't an admin gets no foothold here.
    await signOut();
    return false;
  }

  // ---- My wishes ------------------------------------------------------------

  // members/{uid}/wishes/{id}. Readable only by that signed-in account, which
  // is what makes it safe to keep private sparks and notes there.
  CollectionReference<Map<String, dynamic>> get _mineRef =>
      _db.collection('members').doc(_uid).collection('wishes');

  @override
  Future<List<Wish>> fetchMyWishes() async {
    if (accountLabel == null) return [];
    final snap = await _mineRef.get();
    return [for (final d in snap.docs) Wish.fromJson(d.data())];
  }

  @override
  Future<void> saveMyWish(Wish wish) async {
    if (accountLabel == null) return;
    await _mineRef.doc(wish.id).set(wish.toJson());
  }

  @override
  Stream<Map<String, int>> watchMyLuck() => _wishes
      .where('authorUid', isEqualTo: _uid)
      .snapshots()
      .map((s) => {for (final d in s.docs) d.id: (d.data()['luck'] as num?)?.toInt() ?? 0});

  // ---- Push notifications ---------------------------------------------------

  @override
  Future<void> registerDevice({
    required String token,
    required String platform,
    required String timezone,
    required bool luckAlerts,
    required bool revisitNudges,
  }) =>
      _db.collection('devices').doc(token).set({
        'uid': _uid,
        'platform': platform,
        'timezone': timezone,
        'luckAlerts': luckAlerts,
        'revisitNudges': revisitNudges,
        'updatedAt': FieldValue.serverTimestamp(),
      });

  @override
  Future<void> unregisterDevice(String token) async {
    try {
      await _db.collection('devices').doc(token).delete();
    } on FirebaseException catch (e) {
      // A record that already belongs to another account can't be deleted by
      // this one, and that is fine: it is no longer ours to remove.
      if (e.code != 'permission-denied' && e.code != 'not-found') rethrow;
    }
  }

  // ---- Account --------------------------------------------------------------

  // The web client ID from google-services.json (client_type 3). Google Sign-In
  // needs it to mint an ID token Firebase will accept.
  static const _googleServerClientId =
      '959593379629-b14u9i3libsf1eio58mvemfmr12nnbrd.apps.googleusercontent.com';
  bool _googleReady = false;

  @override
  String? get accountId {
    final u = _auth.currentUser;
    return (u == null || u.isAnonymous) ? null : u.uid;
  }

  @override
  String? get accountLabel {
    final u = _auth.currentUser;
    if (u == null || u.isAnonymous) return null;
    return u.email ?? u.displayName ?? 'Signed in';
  }

  /// Upgrades a guest by linking, which keeps the uid. If the credential
  /// already belongs to an account, signs into that account instead.
  Future<void> _useCredential(AuthCredential credential) async {
    final user = _auth.currentUser;
    if (user != null && user.isAnonymous) {
      try {
        await user.linkWithCredential(credential);
        await _auth.currentUser?.reload();
        return;
      } on FirebaseAuthException catch (e) {
        if (e.code != 'credential-already-in-use' && e.code != 'email-already-in-use') rethrow;
        credential = e.credential ?? credential;
      }
    }
    await _auth.signInWithCredential(credential);
  }

  /// Null when the person dismissed the Google sheet.
  Future<AuthCredential?> _googleCredential() async {
    if (!_googleReady) {
      await GoogleSignIn.instance.initialize(serverClientId: _googleServerClientId);
      _googleReady = true;
    }
    final GoogleSignInAccount account;
    try {
      account = await GoogleSignIn.instance.authenticate();
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      rethrow;
    }
    final idToken = account.authentication.idToken;
    if (idToken == null) throw StateError('Google did not return an ID token.');
    return GoogleAuthProvider.credential(idToken: idToken);
  }

  /// Null when the person dismissed the Apple sheet.
  Future<AuthCredential?> _appleCredential() async {
    // The nonce ties the identity token to this request, so a stolen token
    // can't be replayed. Apple gets the hash; Firebase gets the raw value.
    final rand = Random.secure();
    final raw = base64UrlEncode(List<int>.generate(32, (_) => rand.nextInt(256)));
    final hashed = sha256.convert(utf8.encode(raw)).toString();
    final AuthorizationCredentialAppleID apple;
    try {
      apple = await SignInWithApple.getAppleIDCredential(
        scopes: [AppleIDAuthorizationScopes.email, AppleIDAuthorizationScopes.fullName],
        nonce: hashed,
      );
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) return null;
      rethrow;
    }
    // Kept so deleting the account can hand Apple back this authorization and
    // revoke the Sign in with Apple link, as App Review requires.
    _appleAuthorizationCode = apple.authorizationCode;
    return OAuthProvider('apple.com').credential(
      idToken: apple.identityToken,
      rawNonce: raw,
      accessToken: apple.authorizationCode,
    );
  }

  String? _appleAuthorizationCode;

  @override
  Future<bool> signInWithGoogle() async {
    final credential = await _googleCredential();
    if (credential == null) return false;
    await _useCredential(credential);
    return true;
  }

  @override
  Future<bool> signInWithApple() async {
    final credential = await _appleCredential();
    if (credential == null) return false;
    await _useCredential(credential);
    return true;
  }

  @override
  Future<bool> deleteAccount() async {
    final user = _auth.currentUser;
    if (user == null) return true;
    // Firebase refuses to delete an account that signed in a while ago, so
    // ask the person to confirm with the same provider first. Doing it before
    // touching any data means a cancel leaves everything as it was.
    if (!user.isAnonymous) {
      final providers = user.providerData.map((p) => p.providerId).toSet();
      final AuthCredential? fresh;
      if (providers.contains('google.com')) {
        fresh = await _googleCredential();
      } else if (providers.contains('apple.com')) {
        fresh = await _appleCredential();
      } else {
        throw FirebaseAuthException(
          code: 'requires-recent-login',
          message: 'Sign in with Google or Apple to delete this account.',
        );
      }
      if (fresh == null) return false;
      await user.reauthenticateWithCredential(fresh);
      // Apple: deleting an account must also revoke the Sign in with Apple
      // token. Done here, before any data is touched, so if Apple can't be
      // reached nothing has been deleted and the person can simply try again.
      final code = _appleAuthorizationCode;
      if (providers.contains('apple.com') && !providers.contains('google.com') && code != null) {
        await _auth.revokeTokenWithAuthorizationCode(code);
      }
      _appleAuthorizationCode = null;
    }
    final uid = user.uid;
    await _deleteAll(_wishes.where('authorUid', isEqualTo: uid));
    await _deleteAll(_db.collection('members').doc(uid).collection('wishes'));
    await _deleteAll(_db.collection('devices').where('uid', isEqualTo: uid));
    await user.delete();
    if (_googleReady) await GoogleSignIn.instance.signOut();
    await _auth.signInAnonymously();
    return true;
  }

  Future<void> _deleteAll(Query<Map<String, dynamic>> query) async {
    while (true) {
      final snap = await query.limit(400).get();
      if (snap.docs.isEmpty) return;
      final batch = _db.batch();
      for (final d in snap.docs) {
        batch.delete(d.reference);
      }
      await batch.commit();
    }
  }

  @override
  Future<void> signOut() async {
    if (_googleReady) await GoogleSignIn.instance.signOut();
    await _auth.signOut();
    await _auth.signInAnonymously();
  }

  @override
  AdminBackend get adminTools => FirestoreAdminBackend(
        _db,
        _auth,
        // Same region as the functions in functions/admin_tools.js.
        FirebaseFunctions.instanceFor(app: Firebase.app(), region: 'us-central1'),
      );

  @override
  Stream<bool> watchAdmin() {
    final user = _auth.currentUser;
    if (user == null || user.isAnonymous) return Stream.value(false);
    return _db.collection('admins').doc(user.uid).snapshots().map((s) => s.exists);
  }

  @override
  Stream<PlusGrant?> watchPlusGrant() {
    final user = _auth.currentUser;
    if (user == null || user.isAnonymous) return Stream.value(null);
    return _db.collection('subscriptions').doc(user.uid).snapshots().map((s) {
      final d = s.data();
      if (d == null) return null;
      final lifetime = d['grantLifetime'] == true;
      final until = dateOf(d['grantUntil']);
      return lifetime || until != null ? PlusGrant(lifetime: lifetime, until: until) : null;
    });
  }

  @override
  Stream<AppConfig> watchConfig() =>
      _db.collection('config').doc('app').snapshots().map((s) => AppConfig.fromMap(s.data()));
}
