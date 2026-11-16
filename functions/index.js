// ManifestWell server-side push notifications.
//
// Both functions work on the named Firestore database "manifestwell", never on
// BraidsTribe's (default) database, and are deployed as their own codebase:
//   firebase deploy --only functions:manifestwell --project braidstribeapp
//
// What gets sent, and when, is decided by the pure functions in src/logic.js,
// which are tested in Node. This file only reads and writes Firestore and
// hands messages to FCM.

const admin = require("firebase-admin");
const {getFirestore, Timestamp} = require("firebase-admin/firestore");
const {onDocumentCreated, onDocumentUpdated} = require("firebase-functions/v2/firestore");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const logger = require("firebase-functions/logger");
const logic = require("./src/logic");

admin.initializeApp();

const DATABASE = "manifestwell";
// The database is multi-region nam5; its triggers run in us-central1.
const REGION = "us-central1";

const db = getFirestore(admin.app(), DATABASE);

/** Android small-icon resource and brand colour used on every push. */
const ICON = "ic_stat_manifestwell";
const COLOR = "#A25CFF";

/**
 * Sends one message to every device a member has registered for a kind of
 * push, and forgets any device FCM says is gone for good.
 * @param {string} uid The member.
 * @param {string} preference "luckAlerts" or "revisitNudges".
 * @param {{title: string, body: string}} message What to show.
 * @param {object} data Extra data for the app (type, wishId).
 * @param {string} channelId Android notification channel.
 * @return {Promise<number>} How many devices it reached.
 */
async function pushToMember(uid, preference, message, data, channelId) {
  const devices = await db.collection("devices")
      .where("uid", "==", uid)
      .where(preference, "==", true)
      .get();
  if (devices.empty) return 0;

  const result = await admin.messaging().sendEachForMulticast({
    tokens: devices.docs.map((d) => d.id),
    notification: {title: message.title, body: message.body},
    data,
    android: {
      priority: "normal",
      notification: {channelId, icon: ICON, color: COLOR},
    },
    apns: {payload: {aps: {sound: "default"}}},
  });

  const dead = db.batch();
  let removed = 0;
  result.responses.forEach((r, i) => {
    if (!r.success && logic.isDeadToken(r.error && r.error.code)) {
      dead.delete(devices.docs[i].ref);
      removed++;
    } else if (!r.success) {
      logger.warn("push failed", {uid, code: r.error && r.error.code});
    }
  });
  if (removed) await dead.commit();
  return result.successCount;
}

/**
 * Tells a wish's author when someone sends it luck. A burst of luck becomes
 * one push per window, with the running total in the text.
 */
exports.onLuckReceived = onDocumentUpdated(
    {document: "wishes/{wishId}", database: DATABASE, region: REGION},
    async (event) => {
      const before = event.data.before.data();
      const after = event.data.after.data();
      const wishId = event.params.wishId;

      // Claim the slot inside a transaction so two luck events arriving
      // together cannot both pass the throttle.
      const state = db.collection("pushState").doc(wishId);
      const claimed = await db.runTransaction(async (tx) => {
        const snap = await tx.get(state);
        const last = snap.exists ? logic.toMillis(snap.get("luckPushedAt")) : null;
        if (!logic.shouldNotifyLuck(before, after, last, Date.now())) return false;
        tx.set(state, {luckPushedAt: Timestamp.now()}, {merge: true});
        return true;
      });
      if (!claimed) return;

      const reached = await pushToMember(
          after.authorUid,
          "luckAlerts",
          logic.buildLuckMessage(after.text, Number(after.luck)),
          {type: "luck", wishId},
          "luck_alerts",
      );
      logger.info("luck push", {wishId, reached});
    },
);

/**
 * Every hour, finds members for whom it is now 10:00 local time and who hold
 * a wish that is 30+ days old, and invites them to revisit it. At most one
 * nudge per member per week, and each wish is only ever nudged once.
 * Scans devices that opted in; fine to many thousands, revisit if it grows.
 */
exports.revisitNudges = onSchedule(
    {schedule: "every 60 minutes", timeZone: "UTC", region: REGION},
    async () => {
      const now = Date.now();
      const optedIn = await db.collection("devices").where("revisitNudges", "==", true).get();

      const zonesByUid = new Map();
      optedIn.forEach((d) => {
        const {uid, timezone} = d.data();
        if (!uid || !timezone) return;
        if (!zonesByUid.has(uid)) zonesByUid.set(uid, []);
        zonesByUid.get(uid).push(timezone);
      });
      const due = [...zonesByUid.entries()]
          .filter(([, zones]) => logic.inRevisitWindow(zones, now))
          .map(([uid]) => uid);
      if (!due.length) return;

      let sent = 0;
      for (let i = 0; i < due.length; i += 30) {
        const chunk = due.slice(i, i + 30); // Firestore "in" allows 30 values
        const wishSnap = await db.collection("wishes").where("authorUid", "in", chunk).get();
        const byUid = new Map();
        wishSnap.forEach((d) => {
          const w = {id: d.id, ...d.data()};
          if (!byUid.has(w.authorUid)) byUid.set(w.authorUid, []);
          byUid.get(w.authorUid).push(w);
        });

        for (const uid of chunk) {
          const wishes = byUid.get(uid) || [];
          if (!wishes.length) continue;

          const nudged = new Set();
          const states = await db.getAll(
              ...wishes.map((w) => db.collection("pushState").doc(w.id)));
          states.forEach((s, idx) => {
            if (s.exists && s.get("revisitNudgedAt")) nudged.add(wishes[idx].id);
          });
          const userState = db.collection("userPush").doc(uid);
          const userSnap = await userState.get();
          const lastUser = userSnap.exists ? logic.toMillis(userSnap.get("lastRevisitAt")) : null;

          const pick = logic.pickRevisitWish(wishes, nudged, lastUser, now);
          if (!pick) continue;

          const reached = await pushToMember(
              uid,
              "revisitNudges",
              logic.buildRevisitMessage(pick.text, logic.toMillis(pick.createdAt), now),
              {type: "revisit", wishId: pick.id},
              "revisit",
          );
          // Only count it as nudged if a device actually received it, so a
          // member with no reachable device is not silently skipped forever.
          if (reached > 0) {
            const stamp = Timestamp.now();
            await db.collection("pushState").doc(pick.id).set({revisitNudgedAt: stamp}, {merge: true});
            await userState.set({lastRevisitAt: stamp}, {merge: true});
            sent++;
          }
        }
      }
      logger.info("revisit nudges", {candidates: due.length, sent});
    },
);

/**
 * Hides a new wish the moment it contains one of the admin's blocked terms
 * (config/app.blockedTerms) and files a report so it shows up in the
 * moderation queue. The app already refuses these on the phone; this covers
 * anyone who bypasses it. The wish is public for the second or two this takes.
 */
exports.onWishCreated = onDocumentCreated(
    {document: "wishes/{wishId}", database: DATABASE, region: REGION},
    async (event) => {
      const wish = event.data.data();
      if (!wish || wish.hidden === true) return;

      const config = await db.collection("config").doc("app").get();
      const term = logic.findBlockedTerm(wish.text, config.exists ? config.get("blockedTerms") : []);
      if (!term) return;

      const batch = db.batch();
      batch.update(event.data.ref, {hidden: true});
      batch.set(db.collection("reports").doc(), {
        wishId: event.params.wishId,
        reason: `Auto-hidden: blocked term "${term}"`.slice(0, 200),
        reporterUid: "system",
        at: Timestamp.now(),
      });
      batch.set(db.collection("adminLog").doc(), {
        action: "auto-hide",
        detail: `wish ${event.params.wishId} matched "${term}"`.slice(0, 300),
        by: "system",
        byLabel: "Automatic",
        at: Timestamp.now(),
      });
      await batch.commit();
      logger.info("wish auto-hidden", {wishId: event.params.wishId});
    },
);

/**
 * Sends an announcement an admin queued: one push to every registered phone in
 * the audience that still has notifications on. It records how many phones it
 * reached, and forgets any phone FCM says is gone for good.
 */
exports.onAnnouncementCreated = onDocumentCreated(
    {document: "announcements/{id}", database: DATABASE, region: REGION},
    async (event) => {
      const ref = event.data.ref;
      const announcement = event.data.data();

      if (!logic.isValidAnnouncement(announcement)) {
        await ref.update({status: "failed", error: "Not a valid announcement."});
        return;
      }
      // Claim it, so a retried delivery of this event can never send twice.
      const claimed = await db.runTransaction(async (tx) => {
        const snap = await tx.get(ref);
        if (snap.get("status") !== "queued") return false;
        tx.update(ref, {status: "sending"});
        return true;
      });
      if (!claimed) return;

      try {
        let query = db.collection("devices");
        if (announcement.audience !== "all") {
          query = query.where("platform", "==", announcement.audience);
        }
        const snap = await query.get();
        const targets = snap.docs.filter((d) => logic.matchesAudience(d.data(), announcement.audience));
        const message = logic.buildAnnouncementMessage(announcement);

        let sent = 0;
        let failed = 0;
        for (const group of logic.chunk(targets, 500)) {
          const result = await admin.messaging().sendEachForMulticast({
            tokens: group.map((d) => d.id),
            notification: message,
            data: {type: "announcement"},
            android: {
              priority: "normal",
              notification: {channelId: "announcements", icon: ICON, color: COLOR},
            },
            apns: {payload: {aps: {sound: "default"}}},
          });
          const dead = db.batch();
          let removed = 0;
          result.responses.forEach((r, i) => {
            if (r.success) return;
            if (logic.isDeadToken(r.error && r.error.code)) {
              dead.delete(group[i].ref);
              removed++;
            }
          });
          if (removed) await dead.commit();
          sent += result.successCount;
          failed += result.failureCount;
        }
        await ref.update({status: "sent", sent, failed, completedAt: Timestamp.now()});
        logger.info("announcement sent", {id: event.params.id, sent, failed});
      } catch (e) {
        logger.error("announcement failed", e);
        await ref.update({status: "failed", error: String(e && e.message || e).slice(0, 200)});
      }
    },
);

// Admin management and subscriptions live in their own file.
Object.assign(exports, require("./admin_tools"));
