# Android Build Handoff

The Android artifacts were built from the latest verified source at commit `4280eb1` and the low-memory Gradle configuration was preserved in commit `b802b54`.

| Artifact | Purpose | Size |
|---|---|---:|
| `app-release.apk` | Direct installation on Android devices | 63 MB |
| `app-release.aab` | Upload to Google Play Console | 57 MB |

## Install the APK

Copy `app-release.apk` to an Android phone, allow installation from the selected file manager if Android requests it, and open the file. The APK is a release build created with `--no-shrink` for reliable sandbox compilation.

## Publish the AAB

Upload `app-release.aab` through Google Play Console as a new release. Before production publication, configure the final application ID, signing/upload keystore, Play Billing products, privacy policy URL, and backend production endpoint.

## SHA-256

```text
5b104af891f783c94a91639b2db6e21b384a57ada7462c1adc69b092cc6e41a8  app-release.apk
328ee10edd0edd9c4f812d6b464bbb01d00cc5d89e69f3fc88b3603daf161a94  app-release.aab
```

The current artifacts use the project’s development signing configuration. A new production upload keystore should be used before publishing to Google Play.
