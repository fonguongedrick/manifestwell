const test = require("node:test");
const assert = require("node:assert/strict");
const L = require("../src/logic");

const HOUR = 60 * 60 * 1000;
const DAY = 24 * HOUR;
const NOW = Date.UTC(2026, 10, 10, 15, 0, 0); // 10:00 in New York

const wish = (over = {}) => ({authorUid: "u1", luck: 1, hidden: false, ...over});

test("luck: notifies when luck rises", () => {
  assert.equal(L.shouldNotifyLuck(wish({luck: 0}), wish({luck: 1}), null, NOW), true);
});

test("luck: ignores edits that are not a new luck", () => {
  assert.equal(L.shouldNotifyLuck(wish({luck: 3}), wish({luck: 3}), null, NOW), false);
  assert.equal(L.shouldNotifyLuck(wish({luck: 3}), wish({luck: 2}), null, NOW), false);
});

test("luck: stays quiet for hidden wishes and missing authors", () => {
  assert.equal(L.shouldNotifyLuck(wish({luck: 0}), wish({luck: 1, hidden: true}), null, NOW), false);
  assert.equal(L.shouldNotifyLuck(wish({luck: 0}), wish({luck: 1, authorUid: ""}), null, NOW), false);
});

test("luck: one push per wish per window, then again", () => {
  const b = wish({luck: 1});
  const a = wish({luck: 2});
  assert.equal(L.shouldNotifyLuck(b, a, NOW - HOUR, NOW), false);
  assert.equal(L.shouldNotifyLuck(b, a, NOW - L.LUCK_PUSH_GAP_MS - 1, NOW), true);
});

test("luck: handles deletes and creates", () => {
  assert.equal(L.shouldNotifyLuck(null, wish(), null, NOW), false);
  assert.equal(L.shouldNotifyLuck(wish(), null, null, NOW), false);
});

test("snippet: short text is untouched, long text breaks on a word", () => {
  assert.equal(L.snippet("A calm new home"), "A calm new home");
  const long = "I am so grateful for the calm, steady, wonderful life that is arriving for me now";
  const s = L.snippet(long, 40);
  assert.ok(s.length <= 40);
  assert.ok(s.endsWith("…"));
  assert.ok(!s.includes("  "));
});

test("snippet: collapses whitespace and tolerates nothing", () => {
  assert.equal(L.snippet("  a\n\n b   c "), "a b c");
  assert.equal(L.snippet(null), "");
});

test("luck message: first luck vs a running total", () => {
  assert.equal(L.buildLuckMessage("A calm new home", 1).body, "Someone sent luck to “A calm new home”.");
  assert.equal(L.buildLuckMessage("A calm new home", 12).body, "“A calm new home” has now received 12 luck.");
});

test("local hour follows the time zone", () => {
  assert.equal(L.localHour("America/New_York", NOW), 10);
  assert.equal(L.localHour("Europe/London", NOW), 15);
  assert.equal(L.localHour("Asia/Tokyo", NOW), 0);
});

test("local hour: midnight is 0, never 24; bad zones are null", () => {
  assert.equal(L.localHour("UTC", Date.UTC(2026, 0, 1, 0, 30)), 0);
  assert.equal(L.localHour("Not/AZone", NOW), null);
  assert.equal(L.localHour("", NOW), null);
});

test("revisit window: any device at the nudge hour counts", () => {
  assert.equal(L.inRevisitWindow(["Europe/London", "America/New_York"], NOW), true);
  assert.equal(L.inRevisitWindow(["Europe/London"], NOW), false);
  assert.equal(L.inRevisitWindow(["bad"], NOW), false);
  assert.equal(L.inRevisitWindow([], NOW), false);
});

const aged = (id, days, over = {}) => ({id, createdAt: NOW - days * DAY, hidden: false, ...over});

test("revisit: picks the oldest wish that is at least 30 days old", () => {
  const picked = L.pickRevisitWish([aged("new", 5), aged("mid", 40), aged("old", 90)], new Set(), null, NOW);
  assert.equal(picked.id, "old");
});

test("revisit: nothing young enough, hidden, or already nudged qualifies", () => {
  assert.equal(L.pickRevisitWish([aged("a", 29)], new Set(), null, NOW), null);
  assert.equal(L.pickRevisitWish([aged("a", 60, {hidden: true})], new Set(), null, NOW), null);
  assert.equal(L.pickRevisitWish([aged("a", 60)], new Set(["a"]), null, NOW), null);
  assert.equal(L.pickRevisitWish([aged("a", 60), aged("b", 45)], new Set(["a"]), null, NOW).id, "b");
});

test("revisit: a member is nudged at most once a week", () => {
  assert.equal(L.pickRevisitWish([aged("a", 60)], new Set(), NOW - 2 * DAY, NOW), null);
  assert.equal(L.pickRevisitWish([aged("a", 60)], new Set(), NOW - 8 * DAY, NOW).id, "a");
});

test("revisit: accepts Firestore-style timestamps", () => {
  const ts = {toMillis: () => NOW - 40 * DAY};
  assert.equal(L.pickRevisitWish([{id: "t", createdAt: ts}], new Set(), null, NOW).id, "t");
  assert.equal(L.pickRevisitWish([{id: "t", createdAt: null}], new Set(), null, NOW), null);
});

test("revisit message states how long ago", () => {
  const m = L.buildRevisitMessage("Launching my new app", NOW - 33 * DAY, NOW);
  assert.equal(m.title, "How is your wish doing?");
  assert.ok(m.body.includes("33 days ago"));
  assert.ok(m.body.includes("Launching my new app"));
});

test("dead tokens are recognised, transient errors are not", () => {
  assert.equal(L.isDeadToken("messaging/registration-token-not-registered"), true);
  assert.equal(L.isDeadToken("messaging/invalid-registration-token"), true);
  assert.equal(L.isDeadToken("messaging/internal-error"), false);
  assert.equal(L.isDeadToken(undefined), false);
});

test("blocked terms: matches whole words and phrases, ignoring case", () => {
  assert.equal(L.findBlockedTerm("This is SPAM, sorry", ["spam"]), "spam");
  assert.equal(L.findBlockedTerm("buy now please", ["buy now"]), "buy now");
});

test("blocked terms: never trips inside a longer word", () => {
  assert.equal(L.findBlockedTerm("I passed my class", ["ass"]), null);
  assert.equal(L.findBlockedTerm("a classic wish", ["ass"]), null);
});

test("blocked terms: punctuation, accents and regex characters are safe", () => {
  assert.equal(L.findBlockedTerm("(spam)!", ["spam"]), "spam");
  assert.equal(L.findBlockedTerm("café au lait", ["café"]), "café");
  assert.equal(L.findBlockedTerm("what is a.b?", ["a.b"]), "a.b");
  assert.equal(L.findBlockedTerm("axb", ["a.b"]), null);
});

test("blocked terms: tolerates a missing list and junk entries", () => {
  assert.equal(L.findBlockedTerm("hello", undefined), null);
  assert.equal(L.findBlockedTerm("hello", [null, "", " ", "x"]), null);
});

test("announcement: valid only when queued, within limits, known audience", () => {
  const ok = {status: "queued", title: "Hello", body: "A note", audience: "all"};
  assert.equal(L.isValidAnnouncement(ok), true);
  assert.equal(L.isValidAnnouncement({...ok, status: "sent"}), false);
  assert.equal(L.isValidAnnouncement({...ok, title: "  "}), false);
  assert.equal(L.isValidAnnouncement({...ok, body: "x".repeat(181)}), false);
  assert.equal(L.isValidAnnouncement({...ok, audience: "everyone"}), false);
  assert.equal(L.isValidAnnouncement(null), false);
});

test("announcement audience: platform filter, and opted-out phones are skipped", () => {
  const phone = (over) => ({platform: "ios", luckAlerts: true, revisitNudges: false, ...over});
  assert.equal(L.matchesAudience(phone(), "all"), true);
  assert.equal(L.matchesAudience(phone(), "ios"), true);
  assert.equal(L.matchesAudience(phone(), "android"), false);
  assert.equal(L.matchesAudience(phone({luckAlerts: false, revisitNudges: true}), "all"), true);
  assert.equal(L.matchesAudience(phone({luckAlerts: false}), "all"), false);
  assert.equal(L.matchesAudience(null, "all"), false);
});

test("chunk: splits into groups no bigger than the limit", () => {
  assert.deepEqual(L.chunk([1, 2, 3, 4, 5], 2), [[1, 2], [3, 4], [5]]);
  assert.deepEqual(L.chunk([], 500), []);
  assert.equal(L.chunk(Array.from({length: 1203}, (_, i) => i), 500).length, 3);
});

test("announcement message is trimmed", () => {
  assert.deepEqual(L.buildAnnouncementMessage({title: " Hi ", body: " there "}),
      {title: "Hi", body: "there"});
});

test("email: normalised, and junk is rejected", () => {
  assert.equal(L.normalizeEmail("  Boss@Example.COM "), "boss@example.com");
  for (const bad of ["", "nope", "a@b", "a b@c.d", null, undefined]) {
    assert.equal(L.normalizeEmail(bad), "", String(bad));
  }
});

test("removing admins: not yourself, not the last, owners only by owners", () => {
  const base = {callerUid: "a", targetUid: "b", callerIsOwner: false, targetIsOwner: false, adminCount: 3};
  assert.equal(L.whyCannotRemoveAdmin(base), null);
  assert.match(L.whyCannotRemoveAdmin({...base, targetUid: "a"}), /yourself/);
  assert.match(L.whyCannotRemoveAdmin({...base, adminCount: 1}), /at least one/);
  assert.match(L.whyCannotRemoveAdmin({...base, targetIsOwner: true}), /owner/);
  assert.equal(L.whyCannotRemoveAdmin({...base, targetIsOwner: true, callerIsOwner: true}), null);
});

test("grant: fixed lengths end where they should; lifetime has no end; junk is refused", () => {
  const now = Date.UTC(2026, 10, 10);
  assert.deepEqual(L.grantTerms("week", now), {lifetime: false, untilMs: now + 7 * DAY});
  assert.deepEqual(L.grantTerms("month", now), {lifetime: false, untilMs: now + 30 * DAY});
  assert.deepEqual(L.grantTerms("quarter", now), {lifetime: false, untilMs: now + 90 * DAY});
  assert.deepEqual(L.grantTerms("year", now), {lifetime: false, untilMs: now + 365 * DAY});
  assert.deepEqual(L.grantTerms("lifetime", now), {lifetime: true, untilMs: null});
  assert.equal(L.grantTerms("forever", now), null);
  assert.equal(L.grantTerms(undefined, now), null);
});

test("grant: gives Plus until it ends, always for lifetime, never when absent", () => {
  assert.equal(L.isGrantActive({lifetime: false, untilMs: NOW + 1}, NOW), true);
  assert.equal(L.isGrantActive({lifetime: false, untilMs: NOW}, NOW), false);
  assert.equal(L.isGrantActive({lifetime: false, untilMs: NOW - DAY}, NOW), false);
  assert.equal(L.isGrantActive({lifetime: true, untilMs: null}, NOW), true);
  assert.equal(L.isGrantActive(null, NOW), false);
  assert.equal(L.isGrantActive({}, NOW), false);
});

const ev = (over) => ({
  type: "RENEWAL", app_user_id: "uid1", entitlement_ids: ["plus"], product_id: "p_month",
  expiration_at_ms: NOW + DAY, store: "APP_STORE", period_type: "NORMAL", event_timestamp_ms: NOW, ...over,
});

test("webhook: a purchase or renewal is an active member", () => {
  const r = L.recordFromEvent(ev(), "plus", NOW);
  assert.equal(r.status, "active");
  assert.equal(r.active, true);
  assert.equal(r.uid, "uid1");
  assert.equal(r.guest, false);
});

test("webhook: cancelled keeps access to the end of the period; expiry ends it", () => {
  const c = L.recordFromEvent(ev({type: "CANCELLATION"}), "plus", NOW);
  assert.equal(c.status, "cancelled");
  assert.equal(c.active, true);
  const x = L.recordFromEvent(ev({type: "EXPIRATION", expiration_at_ms: NOW - 1}), "plus", NOW);
  assert.equal(x.status, "expired");
  assert.equal(x.active, false);
  const late = L.recordFromEvent(ev({expiration_at_ms: NOW - 5}), "plus", NOW);
  assert.equal(late.active, false);
});

test("webhook: billing trouble is flagged, and a guest purchase is marked", () => {
  assert.equal(L.recordFromEvent(ev({type: "BILLING_ISSUE"}), "plus", NOW).status, "billing_issue");
  assert.equal(L.recordFromEvent(ev({app_user_id: "$RCAnonymousID:abc"}), "plus", NOW).guest, true);
});

test("webhook: ignores tests, other products, and events with no user", () => {
  assert.equal(L.recordFromEvent(ev({type: "TEST"}), "plus", NOW), null);
  assert.equal(L.recordFromEvent(ev({entitlement_ids: ["other"]}), "plus", NOW), null);
  assert.equal(L.recordFromEvent(ev({app_user_id: undefined}), "plus", NOW), null);
  assert.equal(L.recordFromEvent(null, "plus", NOW), null);
  assert.notEqual(L.recordFromEvent(ev({entitlement_ids: null}), "plus", NOW), null);
});

test("webhook: lifetime purchases have no expiry and stay active", () => {
  const r = L.recordFromEvent(ev({type: "NON_RENEWING_PURCHASE", expiration_at_ms: null}), "plus", NOW);
  assert.equal(r.expiresMs, null);
  assert.equal(r.active, true);
});

test("webhook: an older event never overwrites a newer one", () => {
  assert.equal(L.isNewerEvent(null, 5), true);
  assert.equal(L.isNewerEvent(100, 200), true);
  assert.equal(L.isNewerEvent(100, 100), true);
  assert.equal(L.isNewerEvent(200, 100), false);
});

test("secret comparison: equal only when identical and non-empty", () => {
  assert.equal(L.safeEqual("Bearer abc", "Bearer abc"), true);
  assert.equal(L.safeEqual("Bearer abc", "Bearer abd"), false);
  assert.equal(L.safeEqual("a", "abc"), false);
  assert.equal(L.safeEqual("", ""), false);
  assert.equal(L.safeEqual(undefined, "x"), false);
});
