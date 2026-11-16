// Admin management and subscriptions for the ManifestWell dashboard.
//
// These are callable functions rather than direct database access because they
// need things a phone must never have: the Admin SDK (to find a person by
// email) and RevenueCat's secret key. Each one first checks that the caller has
// a document in admins/{uid}. Names start with "mw" so they can never clash
// with another codebase's functions in the same project.
//
// Loaded by index.js, which has already initialised the Admin SDK.

const admin = require("firebase-admin");
const {getFirestore, Timestamp} = require("firebase-admin/firestore");
const {onCall, onRequest, HttpsError} = require("firebase-functions/v2/https");
const {defineString} = require("firebase-functions/params");
const logic = require("./src/logic");

const DATABASE = "manifestwell";
const REGION = "us-central1";
const db = getFirestore(admin.app(), DATABASE);

/**
 * Optional. Only needed to list real purchases in the dashboard: the exact
 * Authorization header value you type into RevenueCat's webhook. Left empty,
 * the webhook refuses everything and the rest of the dashboard is unaffected.
 */
const RC_WEBHOOK_AUTH = defineString("REVENUECAT_WEBHOOK_AUTH", {default: ""});

/** Must match PurchasesConfig.entitlement in the app. */
const ENTITLEMENT = "plus";

/**
 * Stops anyone who isn't an admin.
 * @param {object} request The callable request.
 * @return {Promise<{uid: string, isOwner: boolean, label: string}>} The caller.
 */
async function requireAdmin(request) {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign in first.");
  const snap = await db.collection("admins").doc(request.auth.uid).get();
  if (!snap.exists) throw new HttpsError("permission-denied", "Admins only.");
  return {
    uid: request.auth.uid,
    // An admin created in the console has no addedBy: that is an owner.
    isOwner: !snap.get("addedBy"),
    label: (request.auth.token && request.auth.token.email) || request.auth.uid,
  };
}

/**
 * Appends to the audit trail. These actions happen here, on the server.
 * @param {{uid: string, label: string}} who The admin.
 * @param {string} action Short name, such as "grant".
 * @param {string} detail What happened.
 */
async function audit(who, action, detail) {
  await db.collection("adminLog").add({
    action,
    detail: String(detail).slice(0, 300),
    by: who.uid,
    byLabel: who.label,
    at: Timestamp.now(),
  });
}

/**
 * Finds a person by email address or user id.
 * @param {string} query An email or a uid.
 * @return {Promise<object>} Their Firebase Auth account.
 */
async function findUser(query) {
  const q = String(query || "").trim();
  if (!q) throw new HttpsError("invalid-argument", "Enter an email address.");
  try {
    if (q.includes("@")) {
      const email = logic.normalizeEmail(q);
      if (!email) throw new HttpsError("invalid-argument", "That is not a valid email address.");
      return await admin.auth().getUserByEmail(email);
    }
    return await admin.auth().getUser(q);
  } catch (e) {
    if (e instanceof HttpsError) throw e;
    if (e && e.code === "auth/user-not-found") {
      throw new HttpsError("not-found",
          "No account has that email. They need to sign in to the app first.");
    }
    throw e;
  }
}

/**
 * What a person has: Plus bought in a store (recorded by the RevenueCat
 * webhook) and Plus an admin gave (recorded here). Both live in one document,
 * subscriptions/{uid}. The app itself honours the gift by reading that
 * document, so nothing here needs to call RevenueCat.
 * @param {object} user Their Firebase Auth account.
 * @return {Promise<object>} The state returned to the dashboard.
 */
async function subscriberState(user) {
  const snap = await db.collection("subscriptions").doc(user.uid).get();
  const d = snap.exists ? snap.data() : {};
  const now = Date.now();
  const grantUntilMs = logic.toMillis(d.grantUntil);
  const purchaseExpiresMs = logic.toMillis(d.expiresAt);
  const grantActive = logic.isGrantActive({lifetime: d.grantLifetime === true, untilMs: grantUntilMs}, now);
  return {
    uid: user.uid,
    email: user.email || "",
    purchaseActive: d.active === true && (purchaseExpiresMs === null || purchaseExpiresMs > now),
    purchaseExpiresMs,
    store: d.store || null,
    grantActive,
    grantLifetime: grantActive && d.grantLifetime === true,
    grantExpiresMs: grantActive ? grantUntilMs : null,
  };
}

const CALLABLE = {region: REGION};

exports.mwAdminList = onCall(CALLABLE, async (request) => {
  const me = await requireAdmin(request);
  const snap = await db.collection("admins").get();
  const ids = snap.docs.slice(0, 100).map((d) => ({uid: d.id}));
  const users = ids.length ? (await admin.auth().getUsers(ids)).users : [];
  const byUid = new Map(users.map((u) => [u.uid, u]));
  return {
    admins: snap.docs.map((d) => ({
      uid: d.id,
      email: (byUid.get(d.id) && byUid.get(d.id).email) || d.get("email") || "",
      owner: !d.get("addedBy"),
      you: d.id === me.uid,
    })),
  };
});

exports.mwAdminAdd = onCall(CALLABLE, async (request) => {
  const me = await requireAdmin(request);
  const email = logic.normalizeEmail(request.data && request.data.email);
  if (!email) throw new HttpsError("invalid-argument", "That is not a valid email address.");
  const user = await findUser(email);
  if (user.disabled) throw new HttpsError("failed-precondition", "That account is disabled.");
  const ref = db.collection("admins").doc(user.uid);
  if ((await ref.get()).exists) throw new HttpsError("already-exists", "They are already an admin.");
  await ref.set({email, addedBy: me.uid, addedAt: Timestamp.now()});
  await audit(me, "admin-add", `${email} made an admin`);
  return {uid: user.uid, email};
});

exports.mwAdminRemove = onCall(CALLABLE, async (request) => {
  const me = await requireAdmin(request);
  const targetUid = String((request.data && request.data.uid) || "");
  if (!targetUid) throw new HttpsError("invalid-argument", "Missing admin.");
  const admins = await db.collection("admins").get();
  const target = admins.docs.find((d) => d.id === targetUid);
  if (!target) throw new HttpsError("not-found", "They are not an admin.");
  const why = logic.whyCannotRemoveAdmin({
    callerUid: me.uid,
    targetUid,
    callerIsOwner: me.isOwner,
    targetIsOwner: !target.get("addedBy"),
    adminCount: admins.size,
  });
  if (why) throw new HttpsError("failed-precondition", why);
  await target.ref.delete();
  await audit(me, "admin-remove", `${target.get("email") || targetUid} is no longer an admin`);
  return {ok: true};
});

exports.mwSubLookup = onCall(CALLABLE, async (request) => {
  await requireAdmin(request);
  return subscriberState(await findUser(request.data && request.data.query));
});

exports.mwSubGrant = onCall(CALLABLE, async (request) => {
  const me = await requireAdmin(request);
  const kind = String((request.data && request.data.kind) || "");
  const terms = logic.grantTerms(kind, Date.now());
  if (!terms) throw new HttpsError("invalid-argument", "Choose how long to give Plus for.");
  const user = await findUser(request.data && request.data.uid);
  await db.collection("subscriptions").doc(user.uid).set({
    uid: user.uid,
    email: user.email || null,
    grantLifetime: terms.lifetime,
    grantUntil: terms.untilMs === null ? null : Timestamp.fromMillis(terms.untilMs),
    grantedBy: me.uid,
    grantedAt: Timestamp.now(),
    updatedAt: Timestamp.now(),
  }, {merge: true});
  await audit(me, "grant", `Plus (${kind}) given to ${user.email || user.uid}`);
  return subscriberState(user);
});

exports.mwSubRevoke = onCall(CALLABLE, async (request) => {
  const me = await requireAdmin(request);
  const user = await findUser(request.data && request.data.uid);
  await db.collection("subscriptions").doc(user.uid).set({
    grantLifetime: false,
    grantUntil: null,
    updatedAt: Timestamp.now(),
  }, {merge: true});
  await audit(me, "revoke", `Given Plus removed from ${user.email || user.uid}`);
  return subscriberState(user);
});

/**
 * RevenueCat calls this on every purchase, renewal, cancellation and expiry.
 * It keeps `subscriptions/{uid}` current so the dashboard can list members and
 * count them. Set it up in RevenueCat > Integrations > Webhooks, with the
 * Authorization header value stored as REVENUECAT_WEBHOOK_AUTH.
 */
exports.mwRevenueCatWebhook = onRequest(
    {region: REGION},
    async (req, res) => {
      if (req.method !== "POST") {
        res.status(405).send("POST only");
        return;
      }
      if (!RC_WEBHOOK_AUTH.value()) {
        res.status(503).send("Webhook not configured");
        return;
      }
      if (!logic.safeEqual(req.get("Authorization"), RC_WEBHOOK_AUTH.value())) {
        res.status(401).send("Unauthorized");
        return;
      }
      const record = logic.recordFromEvent(req.body && req.body.event, ENTITLEMENT, Date.now());
      if (!record) {
        res.status(200).send("ignored");
        return;
      }
      let email = null;
      if (!record.guest) {
        try {
          email = (await admin.auth().getUser(record.uid)).email || null;
        } catch (_) {
          // Not a Firebase account (or since deleted): keep the id only.
        }
      }
      const ref = db.collection("subscriptions").doc(record.uid);
      await db.runTransaction(async (tx) => {
        const snap = await tx.get(ref);
        // An older event arriving late must not undo a newer one.
        if (snap.exists && !logic.isNewerEvent(snap.get("eventMs"), record.eventMs)) return;
        tx.set(ref, {
          uid: record.uid,
          email,
          guest: record.guest,
          active: record.active,
          status: record.status,
          expiresAt: record.expiresMs === null ? null : Timestamp.fromMillis(record.expiresMs),
          productId: record.productId,
          store: record.store,
          periodType: record.periodType,
          lastEvent: record.lastEvent,
          eventMs: record.eventMs,
          updatedAt: Timestamp.now(),
        }, {merge: true});
      });
      res.status(200).send("ok");
    },
);
