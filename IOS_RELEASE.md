# iOS Release Guide

The Flutter project already contains the iOS runner under `ios/` and is ready to open on macOS with Xcode. The current bundle identifier is `com.manus.flutterBookApp`-style project configuration generated from the app scaffold; set the final identifier in Xcode before distribution, for example `com.yourcompany.bookapp`.

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

In Xcode, select the `Runner` target, choose the final **Bundle Identifier**, select the Apple Developer **Team**, enable **Automatically manage signing** for the first build, and verify the minimum iOS deployment target and app display name. Add the App Store Connect in-app purchase products using the IDs defined in `lib/premium_service.dart`.

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
