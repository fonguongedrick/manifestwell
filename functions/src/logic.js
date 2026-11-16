// Decisions and wording for ManifestWell's server-side notifications. Pure
// functions only (no Firebase calls), so they are tested in plain Node.

const HOUR_MS = 60 * 60 * 1000;
const DAY_MS = 24 * HOUR_MS;

/** At most one "luck received" push per wish in this window. */
const LUCK_PUSH_GAP_MS = 3 * HOUR_MS;

/** A wish is offered a revisit nudge once it is this old. */
const REVISIT_AFTER_MS = 30 * DAY_MS;

/** A member gets at most one revisit nudge in this window. */
const REVISIT_USER_GAP_MS = 7 * DAY_MS;

/** Local hour of day at which revisit nudges are delivered. */
const REVISIT_LOCAL_HOUR = 10;

/**
 * @param {*} value A Firestore timestamp, a Date, a number or null.
 * @return {?number} Milliseconds since the epoch, or null.
 */
function toMillis(value) {
  if (value == null) return null;
  if (typeof value === "number") return value;
  if (typeof value.toMillis === "function") return value.toMillis();
  if (value instanceof Date) return value.getTime();
  return null;
}

/**
 * Shortens wish text for a notification, on a word boundary where possible.
 * @param {string} text The wish.
 * @param {number} max Longest allowed result, including the ellipsis.
 * @return {string} The text, trimmed.
 */
function snippet(text, max = 60) {
  const clean = String(text || "").replace(/\s+/g, " ").trim();
  if (clean.length <= max) return clean;
  const cut = clean.slice(0, max - 1);
  const space = cut.lastIndexOf(" ");
  return `${(space > max * 0.6 ? cut.slice(0, space) : cut).trimEnd()}…`;
}

/**
 * Whether a wish update should tell its author they received luck.
 * @param {?object} before The wish before the write.
 * @param {?object} after The wish after the write.
 * @param {?number} lastPushedMs When we last notified about this wish.
 * @param {number} nowMs Current time.
 * @return {boolean} True if a push should go out.
 */
function shouldNotifyLuck(before, after, lastPushedMs, nowMs) {
  if (!before || !after) return false;
  if (after.hidden === true || !after.authorUid) return false;
  if (!(Number(after.luck) > Number(before.luck))) return false;
  if (lastPushedMs != null && nowMs - lastPushedMs < LUCK_PUSH_GAP_MS) return false;
  return true;
}

/**
 * @param {string} wishText The wish.
 * @param {number} luck Luck received so far.
 * @return {{title: string, body: string}} The notification.
 */
function buildLuckMessage(wishText, luck) {
  const quoted = `“${snippet(wishText)}”`;
  return {
    title: "Luck is on its way",
    body: luck > 1 ?
      `${quoted} has now received ${luck} luck.` :
      `Someone sent luck to ${quoted}.`,
  };
}

/**
 * The hour (0-23) it currently is in an IANA time zone.
 * @param {string} timeZone For example "America/New_York".
 * @param {number} nowMs Current time.
 * @return {?number} The hour, or null if the zone is not valid.
 */
function localHour(timeZone, nowMs) {
  try {
    const parts = new Intl.DateTimeFormat("en-US", {
      timeZone,
      hour: "numeric",
      hourCycle: "h23",
    }).formatToParts(new Date(nowMs));
    const hour = parts.find((p) => p.type === "hour");
    return hour ? Number(hour.value) % 24 : null;
  } catch (_) {
    return null;
  }
}

/**
 * @param {string[]} timeZones The zones of a member's devices.
 * @param {number} nowMs Current time.
 * @return {boolean} True if it is the nudge hour on any of them.
 */
function inRevisitWindow(timeZones, nowMs) {
  return timeZones.some((tz) => localHour(tz, nowMs) === REVISIT_LOCAL_HOUR);
}

/**
 * Chooses the wish to nudge a member about: their oldest eligible one.
 * @param {{id: string, createdAt: *, hidden: ?boolean}[]} wishes Their wishes.
 * @param {Set<string>} alreadyNudged Wish ids that have had a nudge.
 * @param {?number} lastUserNudgeMs When this member was last nudged.
 * @param {number} nowMs Current time.
 * @return {?object} The wish to nudge about, or null.
 */
function pickRevisitWish(wishes, alreadyNudged, lastUserNudgeMs, nowMs) {
  if (lastUserNudgeMs != null && nowMs - lastUserNudgeMs < REVISIT_USER_GAP_MS) {
    return null;
  }
  const eligible = wishes
      .filter((w) => w.hidden !== true && !alreadyNudged.has(w.id))
      .map((w) => ({wish: w, created: toMillis(w.createdAt)}))
      .filter((x) => x.created != null && nowMs - x.created >= REVISIT_AFTER_MS)
      .sort((a, b) => a.created - b.created);
  return eligible.length ? eligible[0].wish : null;
}

/**
 * @param {string} wishText The wish.
 * @param {number} createdMs When it was cast.
 * @param {number} nowMs Current time.
 * @return {{title: string, body: string}} The notification.
 */
function buildRevisitMessage(wishText, createdMs, nowMs) {
  const days = Math.max(1, Math.floor((nowMs - createdMs) / DAY_MS));
  return {
    title: "How is your wish doing?",
    body: `“${snippet(wishText)}” was cast ${days} days ago. Take a moment to revisit it.`,
  };
}

/**
 * FCM error codes that mean a token will never work again.
 * @param {?string} code The error code.
 * @return {boolean} True if the device record should be removed.
 */
function isDeadToken(code) {
  return code === "messaging/registration-token-not-registered" ||
    code === "messaging/invalid-registration-token" ||
    code === "messaging/invalid-argument";
}

/**
 * The first blocked term found in a wish, matched as a whole word or phrase so
 * that "class" never trips on "ass". Case and accents are ignored.
 * @param {string} text The wish.
 * @param {*} terms The admin's blocked terms (anything that isn't an array
 *     is treated as none).
 * @return {?string} The term that matched, or null.
 */
function findBlockedTerm(text, terms) {
  if (!Array.isArray(terms)) return null;
  const haystack = String(text || "");
  for (const raw of terms) {
    const term = String(raw || "").trim();
    if (term.length < 2) continue;
    const escaped = term.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    const re = new RegExp(`(^|[^\\p{L}\\p{N}])${escaped}($|[^\\p{L}\\p{N}])`, "iu");
    if (re.test(haystack)) return term;
  }
  return null;
}

/** An announcement's limits, mirrored by the security rules. */
const ANNOUNCEMENT_TITLE_MAX = 60;
const ANNOUNCEMENT_BODY_MAX = 180;
const AUDIENCES = ["all", "android", "ios"];

/**
 * @param {?object} a An announcement document.
 * @return {boolean} True if it is well formed and still waiting to be sent.
 */
function isValidAnnouncement(a) {
  if (!a || a.status !== "queued") return false;
  const title = typeof a.title === "string" ? a.title.trim() : "";
  const body = typeof a.body === "string" ? a.body.trim() : "";
  return title.length > 0 && title.length <= ANNOUNCEMENT_TITLE_MAX &&
    body.length > 0 && body.length <= ANNOUNCEMENT_BODY_MAX &&
    AUDIENCES.includes(a.audience);
}

/**
 * Whether a registered phone should get an announcement. A phone that turned
 * every notification off in the app is left alone.
 * @param {{platform: string, luckAlerts: boolean, revisitNudges: boolean}} device
 * @param {string} audience "all", "android" or "ios".
 * @return {boolean} True if it should be sent to.
 */
function matchesAudience(device, audience) {
  if (!device) return false;
  if (!device.luckAlerts && !device.revisitNudges) return false;
  return audience === "all" || device.platform === audience;
}

/**
 * @param {{title: string, body: string}} a The announcement.
 * @return {{title: string, body: string}} The text to show, trimmed.
 */
function buildAnnouncementMessage(a) {
  return {title: String(a.title).trim(), body: String(a.body).trim()};
}

/**
 * Splits a list into groups of at most `size` (FCM takes 500 tokens a call).
 * @param {Array} items The list.
 * @param {number} size Largest group.
 * @return {Array[]} The groups, in order.
 */
function chunk(items, size) {
  const out = [];
  for (let i = 0; i < items.length; i += size) out.push(items.slice(i, i + size));
  return out;
}

// ---- Admins -------------------------------------------------------------------

/**
 * @param {string} raw What an admin typed.
 * @return {string} A lower-cased, trimmed email, or "" if it can't be one.
 */
function normalizeEmail(raw) {
  const email = String(raw || "").trim().toLowerCase();
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) ? email : "";
}

/**
 * Who may remove whom. An "owner" is an admin created in the Firebase console
 * (their document has no addedBy); admins added through the app are not.
 * @param {{callerUid: string, targetUid: string, callerIsOwner: boolean,
 *     targetIsOwner: boolean, adminCount: number}} p The situation.
 * @return {?string} Why not, or null if it is allowed.
 */
function whyCannotRemoveAdmin(p) {
  if (p.callerUid === p.targetUid) return "You cannot remove yourself.";
  if (p.adminCount <= 1) return "There must always be at least one admin.";
  if (p.targetIsOwner && !p.callerIsOwner) {
    return "Only an owner can remove another owner.";
  }
  return null;
}

// ---- Subscriptions (RevenueCat) -----------------------------------------------

/** How long an admin can grant Plus for. "lifetime" never expires. */
const GRANT_DAYS = {week: 7, month: 30, quarter: 90, year: 365};

/**
 * What a grant of Plus looks like once stored: it ends at a time, or never.
 * @param {string} kind "week", "month", "quarter", "year" or "lifetime".
 * @param {number} nowMs Current time.
 * @return {?{lifetime: boolean, untilMs: ?number}} The terms, or null if kind
 *     isn't one we offer.
 */
function grantTerms(kind, nowMs) {
  if (kind === "lifetime") return {lifetime: true, untilMs: null};
  const days = GRANT_DAYS[kind];
  return days ? {lifetime: false, untilMs: nowMs + days * DAY_MS} : null;
}

/**
 * Whether a stored grant still gives Plus.
 * @param {?{lifetime: ?boolean, untilMs: ?number}} grant What is stored.
 * @param {number} nowMs Current time.
 * @return {boolean} True if it is lifetime, or has not yet ended.
 */
function isGrantActive(grant, nowMs) {
  if (!grant) return false;
  if (grant.lifetime === true) return true;
  return typeof grant.untilMs === "number" && grant.untilMs > nowMs;
}

/**
 * Turns a RevenueCat webhook event into the record kept for the dashboard.
 * @param {object} event The webhook's `event` object.
 * @param {string} entitlementId For example "plus".
 * @param {number} nowMs Current time.
 * @return {?object} The record to store, or null to ignore this event.
 */
function recordFromEvent(event, entitlementId, nowMs) {
  if (!event || !event.app_user_id || event.type === "TEST") return null;
  // A product that unlocks something other than Plus is not ours to track.
  const ids = event.entitlement_ids;
  if (Array.isArray(ids) && !ids.includes(entitlementId)) return null;

  const expiresMs = typeof event.expiration_at_ms === "number" ? event.expiration_at_ms : null;
  let status;
  if (event.type === "EXPIRATION") {
    status = "expired";
  } else if (expiresMs !== null && expiresMs <= nowMs) {
    status = "expired";
  } else if (event.type === "BILLING_ISSUE") {
    status = "billing_issue";
  } else if (event.type === "CANCELLATION") {
    status = "cancelled"; // still has access until the period ends
  } else {
    status = "active";
  }
  return {
    uid: String(event.app_user_id),
    guest: String(event.app_user_id).startsWith("$RCAnonymousID"),
    status,
    active: status !== "expired",
    expiresMs,
    productId: event.product_id || null,
    store: event.store || null,
    periodType: event.period_type || null,
    lastEvent: String(event.type || ""),
    eventMs: typeof event.event_timestamp_ms === "number" ? event.event_timestamp_ms : nowMs,
  };
}

/**
 * Whether an incoming event is newer than what is stored. RevenueCat can
 * deliver events out of order, and an old one must not undo a newer one.
 * @param {?number} storedMs eventMs of the stored record, if any.
 * @param {number} incomingMs eventMs of the new event.
 * @return {boolean} True if the event should be applied.
 */
function isNewerEvent(storedMs, incomingMs) {
  return storedMs == null || incomingMs >= storedMs;
}

/**
 * Compares two secrets without leaking how much of them matched.
 * @param {?string} a One value.
 * @param {?string} b The other.
 * @return {boolean} True if they are identical and non-empty.
 */
function safeEqual(a, b) {
  if (typeof a !== "string" || typeof b !== "string" || !a || !b) return false;
  const crypto = require("node:crypto");
  const ha = crypto.createHash("sha256").update(a).digest();
  const hb = crypto.createHash("sha256").update(b).digest();
  return crypto.timingSafeEqual(ha, hb);
}

module.exports = {
  normalizeEmail,
  whyCannotRemoveAdmin,
  GRANT_DAYS,
  grantTerms,
  isGrantActive,
  recordFromEvent,
  isNewerEvent,
  safeEqual,
  findBlockedTerm,
  isValidAnnouncement,
  matchesAudience,
  buildAnnouncementMessage,
  chunk,
  ANNOUNCEMENT_TITLE_MAX,
  ANNOUNCEMENT_BODY_MAX,
  LUCK_PUSH_GAP_MS,
  REVISIT_AFTER_MS,
  REVISIT_USER_GAP_MS,
  REVISIT_LOCAL_HOUR,
  toMillis,
  snippet,
  shouldNotifyLuck,
  buildLuckMessage,
  localHour,
  inRevisitWindow,
  pickRevisitWish,
  buildRevisitMessage,
  isDeadToken,
};
