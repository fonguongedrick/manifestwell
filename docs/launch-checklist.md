# ManifestWell launch checklist

Everything here is something the code cannot do for itself: accounts, keys and
console settings. Tick each one before relying on the matching feature.

Package / bundle ID everywhere: `com.tribesofkin.manifestwell`
Firebase project: `braidstribeapp`, database: `manifestwell`

## 1. Firebase (rules, index, functions)

Run from this folder. Never use a bare `firebase deploy`: it would also touch
BraidsTribe's default database and functions.

```
firebase deploy --only firestore:manifestwell --project braidstribeapp
firebase deploy --only functions:manifestwell --project braidstribeapp
```

- [ ] Rules deployed (includes `devices`, `pushState`, `userPush` and the admin
      dashboard's `config`, `blocked`, `announcements` and `adminLog`).
      **Redeploy after pulling this update**: the dashboard needs the new rules.
- [ ] Functions deployed: `onLuckReceived`, `revisitNudges`, `onWishCreated`
      (auto-hides wishes with a blocked word), `onAnnouncementCreated` (sends
      dashboard announcements), and the admin tools `mwAdminList`,
      `mwAdminAdd`, `mwAdminRemove`, `mwSubLookup`, `mwSubGrant`,
      `mwSubRevoke` and `mwRevenueCatWebhook`. The first deploy may ask to
      enable the Cloud Scheduler and Eventarc APIs; accept. No keys or secrets
      are needed for any of them.
- [ ] Run `flutter pub get`: the app now depends on `cloud_functions`.
- [ ] Authentication > Sign-in method: Anonymous, Google, Apple and
      **Email/Password** enabled (the admin signs in with email and password).
- [ ] An email/password user created for each admin (Authentication > Users >
      Add user), and that user's id added as a document `admins/<uid>` in the
      `manifestwell` database. Any field works.

Check the functions: Firebase console > Functions > Logs. A luck event logs
`luck push`; each hour the scheduler logs `revisit nudges`; an announcement logs
`announcement sent` with how many phones it reached.

## Admin dashboard

Open it in the app: Settings, then press and hold the **Version** row, sign in
with the admin email and password. Once signed in, Settings shows an
**Admin dashboard** row.

| Module | What it does |
| --- | --- |
| Overview | Wishes, luck, reports, 14-day chart, categories, push reach |
| Moderation | Reports and every wish: hide, restore, remove, dismiss, block author |
| People | Blocked people, unblock |
| Announcements | Push to everyone, Android only or iPhone only, with delivery results |
| Controls | Pause new wishes, a banner on the Well, blocked words |
| Activity | Append-only log of every admin action (nobody can edit or delete it) |
| Export data | Wishes, reports or the activity log as CSV |
| Subscriptions | Find a person by email, give Plus (1 week to lifetime) or take back Plus you gave, list of members |
| Admins | Add an admin by email, remove admins, see who is an owner |

### Admins: how it works

- **Owners** are admins you create in the Firebase console (a document at
  `admins/<uid>`). **Admins** added from the dashboard are recorded with who
  added them. Any admin can add another. Nobody can remove themselves, the last
  admin can't be removed, and only an owner can remove an owner.
- The person you add must already have a Firebase account (they have signed in
  to the app with Google, Apple or email). Adding is by email and runs on the
  server (`mwAdminAdd`), because an app can't look other people up.
- They sign in the same way: press and hold the Version row, then enter an
  email and password. **A Google/Apple-only account has no password**, so
  create one in Firebase Authentication (reset password on the user) first.

### Subscriptions: how it works

**Giving Plus needs no setup beyond the deploy above, and no RevenueCat key.**
A gift is saved on the person's own record in your database, and the app treats
the account as Plus while it lasts (it shows up the next time they open the app,
and follows them to a new phone). Giving Plus never charges anyone, and a gift
works even with no store subscription configured.

- **What an admin cannot do:** cancel or refund a paid subscription. Apple and
  Google own those. "Take back given Plus" only ends Plus an admin gave.
- Only signed-in accounts can be found or given Plus, because the lookup is by
  email. A guest who bought before signing in appears as "Guest purchase".

**Optional: list real purchases in the dashboard.** Without this the page still
works for giving Plus, but the Members list only shows people you have given
Plus to, not people who paid. To include purchases:

- [ ] Choose any long random string. In `functions/.env` add the
      line `REVENUECAT_WEBHOOK_AUTH=<that string>` (this file stays out of git).
- [ ] Deploy the functions. Copy the URL of **mwRevenueCatWebhook** from the
      output.
- [ ] RevenueCat > Integrations > Webhooks > New: paste that URL, and as the
      **Authorization header** enter exactly the same string. Send a test event;
      the function answers `ok`.
- [ ] It only reports changes from now on, so people who subscribed earlier
      appear after their next renewal. Until the string is set, the webhook
      answers "not configured" and everything else is unaffected.

- [ ] After deploying, open Controls and Announcements once to confirm they load.
- [ ] Send yourself a test announcement (Announcements > Android or iPhone) from
      a phone that has notifications on. If it stays "Queued", the
      `onAnnouncementCreated` function is not deployed.
- [ ] Announcements go to every phone that has any notification switched on in
      Settings. Use them sparingly, and mention them in your privacy policy.
- [ ] Wishes with a blocked word are refused on the phone, and hidden by the
      server a second or two after posting if someone gets around the app.
- [ ] Not in the dashboard: total sign-ups (see Firebase Authentication) and
      subscription revenue (see RevenueCat).

## 2. Push notifications

- [ ] **iOS:** Project settings > Cloud Messaging > Apple app configuration:
      upload an APNs Authentication Key (.p8) with its Key ID and your Team ID.
      Without it iPhones receive nothing.
- [ ] **iOS:** Apple Developer > Identifiers > `com.tribesofkin.manifestwell`:
      enable Push Notifications (and Sign in with Apple, In-App Purchase).
- [ ] **iOS:** `ios/Runner/Runner.entitlements` holds `aps-environment` =
      `development`; Xcode switches it to production when you archive.
- [ ] **Android:** nothing extra. Android 13+ asks for permission at runtime.
- [ ] Test: install on a real phone, cast a Big Wish, accept the notification
      offer, then send luck to it from a second device or account.

Push tokens only exist on real devices; iOS simulators never get one.

## 3. In-app subscriptions (RevenueCat)

Purchases use RevenueCat so receipts are validated server-side and Plus follows
the account across phones. No store credentials are kept in this repository.

- [ ] Create a RevenueCat project; add an Android app and an iOS app with the
      package / bundle ID above.
- [ ] Connect the stores as RevenueCat's setup guide describes (Google Play
      service credentials; App Store Connect in-app purchase key).
- [ ] In **App Store Connect** and **Google Play Console** create one
      subscription group with the products you want to sell. Suggested ids:
      `manifestwell_plus_weekly`, `manifestwell_plus_monthly`,
      `manifestwell_plus_yearly`. Set your own prices there.
- [ ] RevenueCat: create the entitlement **`plus`**, attach the products, and
      add them as the Weekly / Monthly / Annual packages of the **current
      offering**. The app shows whatever packages that offering contains.
- [ ] Copy the public SDK keys (Android `goog_...`, iOS `appl_...`).
- [ ] Run or build with the keys:

```
flutter run --dart-define=RC_ANDROID_KEY=goog_xxx --dart-define=RC_IOS_KEY=appl_xxx
flutter build appbundle --dart-define=RC_ANDROID_KEY=goog_xxx
```

- [ ] Google Play only returns products for an app that has been uploaded to a
      testing track and for testers added to it. Add licence testers.
- [ ] iOS sandbox: create a Sandbox Apple ID in App Store Connect and sign in
      with it in Settings > Developer on the test iPhone.
- [ ] RevenueCat > Project settings > "Restoring behavior": choose what happens
      when a guest who bought Plus later signs in to an existing account.

With no key the app still runs; the paywall says subscriptions are not
available yet.

## 4. Things to replace before store submission

- [ ] `lib/config/links.dart`: the privacy, terms and guidelines pages and the
      support address are placeholders. They must open, or the stores reject
      the app.
- [ ] Paywall and Plus card copy must describe only what Plus really unlocks
      (today: unlimited active Big Wishes).
- [ ] App Privacy / Data Safety forms: the app collects an anonymous account id,
      wishes the person chooses to share, a push token, and (if signed in) an
      email address.

## 5. Before every release

```
flutter analyze
flutter test
(cd functions && npm test)
```
