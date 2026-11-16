# ManifestWell

A calm app for making wishes and noticing what comes of them. Cast a wish into a
shared, anonymous Wishing Well, send luck to strangers' wishes, keep proof when
things happen, and break big wishes into small steps.

- **App:** Flutter (iOS and Android). Bundle / package ID `com.tribesofkin.manifestwell`.
- **Backend:** Firebase project `braidstribeapp`, using its own Firestore
  database named `manifestwell`. Never the `(default)` database, which belongs
  to BraidsTribe.
- **Server code:** Cloud Functions in `functions/` (push notifications, the admin
  tools, automatic moderation).
- **Purchases:** RevenueCat (entitlement `plus`).

## Run it

```
flutter pub get
flutter run
```

With no Firebase connection the app still runs: it falls back to local seed
wishes and says so.

## Check it

```
flutter analyze
flutter test
cd functions && npm install && npm test
```

## Deploy the server side

Always target this app only. A bare `firebase deploy` would also touch
BraidsTribe's database and functions.

```
firebase deploy --only firestore:manifestwell --project braidstribeapp
firebase deploy --only functions:manifestwell --project braidstribeapp
```

## Documentation

- [`docs/launch-checklist.md`](docs/launch-checklist.md): every console and
  account step (Firebase, push, subscriptions, the admin dashboard).
- [`docs/ios-release.md`](docs/ios-release.md): building and releasing on iOS.
- [`store/README.md`](store/README.md): regenerating the App Store and Google
  Play images.

## Notes

- The Firebase config files (`google-services.json`, `GoogleService-Info.plist`)
  are committed because a build needs them. They identify the app; they are not
  passwords. Keep this repository **private**.
- Secrets never go in the repository. The functions read settings from
  `functions/.env`, which is git-ignored.
