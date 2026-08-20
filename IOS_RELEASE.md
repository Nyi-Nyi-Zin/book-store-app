# iOS Release Guide

The Flutter project already contains the iOS runner under `ios/` and is ready to open on macOS with Xcode. The current placeholder bundle identifier is `com.manus.flutterBookApp`; replace it in Xcode with an identifier owned by your Apple Developer account, for example `com.yourcompany.bookapp`, before distribution.

## Requirements

A macOS machine with Xcode, the Xcode command-line tools, CocoaPods, an Apple Developer Program membership, and an App Store Connect app record are required. The current Linux build environment cannot create a signed iOS archive or IPA because Apple’s signing and archive toolchain requires macOS/Xcode.

## Prepare the project on macOS

```bash
git clone https://github.com/Nyi-Nyi-Zin/flutter-book-app.git
cd flutter-book-app
flutter pub get
cd ios
pod install
cd ..
open ios/Runner.xcworkspace
```

In Xcode, select the `Runner` target, set **Bundle Identifier** to an identifier owned by your Apple Developer account, select the Apple Developer **Team**, enable **Automatically manage signing** for the first build, and verify the minimum iOS deployment target (currently 15.0) and app display name. Add the App Store Connect in-app purchase products using the IDs defined in `lib/premium_service.dart`.

## Test build

```bash
flutter build ios --release
```

For a signed archive suitable for TestFlight:

```bash
flutter build ipa --release
```

Alternatively, open the workspace in Xcode, select a generic iOS device, choose **Product → Archive**, then distribute the archive through the Organizer to TestFlight or the App Store.

## Required production configuration

Before submission, replace demo authentication and demo Premium activation with the production backend URL, configure Apple receipt verification on the backend, configure the App Store subscription products, add the privacy policy and terms URLs, provide the account-deletion flow, and upload only books for which distribution rights are available.

The Android and iOS apps share the Flutter codebase, but each platform still needs its own application identifier, signing credentials, store listing, privacy declarations, and purchase product configuration.

## GitHub Actions macOS build

The repository includes `.github/workflows/ios.yml`. A push to `main` or a manual workflow dispatch runs on a macOS runner. Without signing secrets, it uploads an unsigned `Runner.app.zip` artifact. To produce a signed IPA, configure these repository secrets: `IOS_TEAM_ID`, `IOS_BUNDLE_ID`, `IOS_P12_BASE64`, `IOS_P12_PASSWORD`, `IOS_PROVISION_PROFILE_BASE64`, and `IOS_KEYCHAIN_PASSWORD`.

The certificate secret must contain a base64-encoded Apple distribution `.p12` file, and the provisioning-profile secret must contain a base64-encoded App Store provisioning profile matching the bundle ID. After those secrets are configured, open the **Actions** tab, select **iOS Build**, choose **Run workflow**, and download the `ios-ipa-<commit>` artifact after the run succeeds. The workflow also keeps an unsigned artifact available for UI/testing purposes when signing is not configured.
