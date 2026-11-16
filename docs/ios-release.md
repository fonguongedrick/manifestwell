# Releasing ManifestWell on iOS

**Bundle ID: `com.tribesofkin.manifestwell`**
(BraidsTribe is a different app: `com.tribesofkin.braidstribe`.)

Nothing here has been built on a real Mac or iPhone yet. The project files were
prepared on Windows, so treat the first archive as the real test.

## What is already done in the project

- Bundle ID, display name "ManifestWell", iOS 15 minimum, version 1.0.0 (1).
- `GoogleService-Info.plist` is part of the Xcode app target and matches the
  bundle ID. (It was on disk before but not in the project, so the app would
  have launched without Firebase.)
- `Podfile` created with iOS 15 (the Firebase plugins need it).
- Sign in with Apple: capability in `Runner.entitlements`, button on iPhone,
  and deleting an account now also revokes the Apple token, as App Review
  requires.
- Push Notifications capability and `remote-notification` background mode.
- `PrivacyInfo.xcprivacy` (Apple's privacy manifest) added to the app.
- `ITSAppUsesNonExemptEncryption = false`, so App Store Connect does not ask
  the export-compliance question on every upload.
- Signing team set to `XCJSC98CNN`. **That is BraidsTribe's team id, copied
  because both apps use `com.tribesofkin`.** If ManifestWell belongs to a
  different Apple Developer team, change it in Xcode (Runner > Signing &
  Capabilities).

## 1. Apple Developer account (developer.apple.com)

- [ ] Certificates, Identifiers & Profiles > Identifiers > **+** > App IDs >
      App, with Bundle ID **`com.tribesofkin.manifestwell`** (Explicit).
- [ ] Tick the capabilities: **Sign in with Apple**, **Push Notifications**,
      **In-App Purchase**.
- [ ] Keys > **+**: create an **APNs** key (Apple Push Notifications service).
      Download the `.p8` once, and note its Key ID and your Team ID.

## 2. App Store Connect (appstoreconnect.apple.com)

- [ ] My Apps > **+** > New App. Platform iOS, name **ManifestWell**
      (names are unique across the App Store, so have a backup), bundle ID from
      the list above, any SKU.
- [ ] App Privacy: answer to match `ios/Runner/PrivacyInfo.xcprivacy`: email
      address, user ID, other user content (wishes), device ID (push token) and
      purchase history, all linked to the person, none used for tracking.
- [ ] Privacy Policy URL and Support URL: **both must load.** They are
      placeholders in `lib/config/links.dart` today. Replace them first.
- [ ] Age rating questionnaire. Pricing. Screenshots: use the files in
      `store/appstore_6.3in_1206x2622` and `store/appstore_6.1in_1179x2556`.
- [ ] Subscriptions (see `launch-checklist.md` section 3): create the group
      and products, add the review screenshot and localised names.

## 3. Firebase console (project braidstribeapp)

- [ ] Authentication > Sign-in method: **Apple** enabled (no Services ID is
      needed for an iOS-only app), plus Google, Anonymous.
- [ ] Project settings > Cloud Messaging > Apple app configuration: upload the
      APNs `.p8` with its Key ID and Team ID. Without it iPhones get no push.
- [ ] Deploy the rules and functions (`launch-checklist.md` section 1).

## 4. Build and upload (needs a Mac, or a cloud Mac service)

An iPhone build cannot be made on Windows. Options: a Mac, or a service that
rents one (Codemagic, Xcode Cloud, GitHub Actions `macos` runners).

On the Mac:

```
cd manifestwellapp
flutter pub get
cd ios && pod install && cd ..
flutter build ipa --release --dart-define=RC_IOS_KEY=appl_xxx
```

Then upload `build/ios/ipa/*.ipa` with the **Transporter** app (or open
`ios/Runner.xcworkspace` in Xcode, Product > Archive > Distribute App).

- Open `Runner.xcworkspace`, not `Runner.xcodeproj`.
- In Xcode, Runner > Signing & Capabilities: "Automatically manage signing"
  on, team selected. Check **Sign in with Apple** and **Push Notifications**
  are listed. Xcode switches `aps-environment` to production when archiving.
- If `pod install` complains about a deployment target, the Podfile and the
  Xcode project should both say 15.0.

## 5. Test, then submit

- [ ] TestFlight: install on a real iPhone. Check: guest launch shows the Well,
      sign in with Apple, cast a wish, **break it into small steps**, push
      permission and a luck notification, restore purchases, delete account.
- [ ] Sign in with Apple must be shown wherever Google sign-in is offered
      (App Review guideline 4.8). It is.
- [ ] Account deletion must be inside the app (guideline 5.1.1). It is:
      Settings > Delete account.
- [ ] Submit for review with a demo path: the app works as a guest with no
      login, so no demo account is needed.
