# Store listing images

Generated from the real app, so they match it exactly. All are PNG with no
transparency, at the exact size each store asks for.

| Folder | Upload to | Size |
| --- | --- | --- |
| `appstore_6.3in_1206x2622` | App Store Connect, iPhone 6.3" | 1206 x 2622 |
| `appstore_6.1in_1179x2556` | App Store Connect, iPhone 6.1" | 1179 x 2556 |
| `play_phone_1080x1920` | Google Play, phone screenshots | 1080 x 1920 |
| `play_feature_graphic_1024x500` | Google Play, feature graphic | 1024 x 500 |
| `play_icon_512x512` | Google Play, app icon | 512 x 512 |

Screens, in the order to upload them: `01_well`, `02_cast`, `03_vault`,
`04_revisit`, `05_spark`, `06_notifications`. The Well comes first because it is
the strongest.

## Regenerate after the app changes

```
STORE=1 flutter test test/store_shots_test.dart --update-goldens
powershell -File store\finish.ps1
```

The headlines live in `test/store_shots_test.dart`. All wishes and numbers shown
are made-up demo data; no real person's content appears.
