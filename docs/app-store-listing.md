# App Store listing: ManifestWell

Everything App Store Connect asks for, ready to paste. Character counts are
checked against Apple's limits. Nothing here promises a feature the app does
not have.

## App information

| Field | Value | Limit |
| --- | --- | --- |
| Name | `ManifestWell` | 30 |
| Subtitle | `Wish, believe, and glow` | 30 |
| Bundle ID | `com.tribesofkin.manifestwell` | |
| SKU | `manifestwell-ios` | |
| Primary language | English (U.S.) | |
| Primary category | Lifestyle | |
| Secondary category | Health & Fitness | |
| Content rights | Does not use third-party content | |

## Promotional text (can be changed any time without a new review)

```
Make a wish, send luck to strangers, and watch your Vault fill with dreams that came true. One calm place to hope on purpose.
```

## Description

```
ManifestWell is a quiet place to hope on purpose.

Write a wish. Send it into the Well. Strangers who read it can send you a spark of luck, and you can send some back. Over time your wishes become a Vault of dreams you chose to believe in, and the ones that came true.

CAST A WISH
A short, guided ritual turns a passing thought into an intention. Say what you want, and let it go.

THE WELL
Read wishes from people around the world and send luck to the ones that move you. No likes, no followers, no feed to fall behind on. Just kindness in small sparks.

YOUR VAULT
Every wish you make is kept privately in your Vault. Mark one as a Big Wish to keep it glowing, and celebrate when it comes true.

SMALL STEPS
Break a Big Wish into small, doable steps and tick them off. Big dreams feel lighter in pieces.

GENTLE REMINDERS
Turn on a daily reminder, and get a soft nudge when someone sends luck to one of your wishes. You choose what you hear about, and you can turn it all off.

PRIVATE BY DESIGN
Start without an account. Sign in with Apple or Google only if you want your wishes to follow you to a new phone. Your Vault is private. Only wishes you cast into the Well are public, and you can remove them at any time.

KIND BY DESIGN
Wishes are checked for harmful content, any wish can be reported, and people who break the rules are removed. This is a place meant to feel safe.

MANIFESTWELL PLUS
Your first Big Wish is always free. ManifestWell Plus lets you keep as many Big Wishes glowing at once. Plus is an optional auto-renewing subscription. Payment is charged to your Apple ID at confirmation of purchase, and the subscription renews automatically unless cancelled at least 24 hours before the end of the current period. Manage or cancel it any time in your Apple ID settings. Any free trial ends when you subscribe.

Terms of Use: https://manifestwell.app/terms
Privacy Policy: https://manifestwell.app/privacy

Questions? support@manifestwell.app
```

## Keywords (comma-separated, no spaces after commas)

```
wish,manifest,manifestation,affirmation,intention,gratitude,luck,vision,goals,mindful,hope,dream
```

## What's New (version 1.0.0)

```
Welcome to ManifestWell. Cast your first wish, send luck to others, and start your Vault.
```

## URLs

| Field | Value |
| --- | --- |
| Support URL | https://manifestwell.app |
| Marketing URL | https://manifestwell.app |
| Privacy Policy URL | https://manifestwell.app/privacy |

These pages must open before you submit. Apple rejects a build whose privacy
link is dead. `support@manifestwell.app` must also be a mailbox you read.

## Copyright

```
2026 Tribes of Kin
```

(Use the legal name of the Apple Developer account holder if it differs.)

## Age rating questionnaire

Answer **None** to every content question except:

| Question | Answer |
| --- | --- |
| User-generated content / unfiltered content | Yes (wishes are public and moderated) |

Expected rating: **12+**. Do not answer "no UGC": the Well shows other
people's wishes, and an honest answer avoids a rejection.

## App Privacy ("nutrition label")

Data is collected and linked to the person, never used for tracking.

| Data type | Linked to you | Used for | Tracking |
| --- | --- | --- | --- |
| Email address (only if they sign in) | Yes | App functionality, account | No |
| User ID | Yes | App functionality | No |
| Other user content (wishes, steps) | Yes | App functionality | No |
| Device ID / push token | Yes | App functionality (notifications) | No |
| Purchases | Yes | App functionality (Plus) | No |

Choose **No** for "Do you or your third-party partners use data for tracking".
The app has no ads and no tracking SDKs. Check this against the final build's
dependencies before you answer.

## Subscription (create under Monetization > Subscriptions)

| Field | Value |
| --- | --- |
| Group name | ManifestWell Plus |
| Product IDs | must match the ones in RevenueCat (entitlement `plus`) |
| Display name | ManifestWell Plus |
| Description | `Keep as many Big Wishes glowing at once.` (40 characters; Apple allows 45) |
| Review screenshot | a screenshot of the paywall screen |

Prices, trials and durations are yours to choose in App Store Connect. The app
reads them from the store, so nothing is hard-coded.

## App Review information

| Field | Value |
| --- | --- |
| Sign-in required | **No.** The app works as a guest. |
| Contact | your name, phone and email |

Notes for the reviewer:

```
ManifestWell needs no account: open the app and tap through the short intro to reach the Well. Signing in with Apple or Google is optional and only lets a person keep their wishes across devices.

User-generated content: every public wish has a Report link. Wishes are screened automatically for harmful words, reported or flagged wishes are reviewed by our moderators, and offending users can be blocked. Support contact: support@manifestwell.app.

Account deletion: Settings > Delete account and data. It removes the person's public wishes, synced Vault and sign-in.

Subscription: ManifestWell Plus is optional and only appears when a free person tries to keep a second Big Wish, or from Settings. The first Big Wish is free.

Push notifications are optional and requested only when the person turns on reminders.
```

## Screenshots

Upload from `store/appstore_6.3in_1206x2622` (and `appstore_6.1in_1179x2556`
if Apple asks for it). Order: Well, Cast, Vault, Revisit, Spark, Notifications.

## Before you press Submit

1. Privacy, terms and support pages are live (see URLs above).
2. The subscription exists, is "Ready to Submit", and is attached to the version.
3. Codemagic build is signed for **App Store**, uploaded, and processed in TestFlight.
4. Export compliance: the build already declares no non-exempt encryption.
5. Sign in with Apple, delete account and a purchase were tried once on a real
   iPhone.
