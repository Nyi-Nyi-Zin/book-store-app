#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This script must run on macOS with Xcode installed." >&2
  exit 1
fi

command -v flutter >/dev/null || { echo "Flutter SDK is not installed or not on PATH." >&2; exit 1; }
command -v xcodebuild >/dev/null || { echo "Xcode command-line tools are not installed." >&2; exit 1; }

flutter pub get
if [[ -d ios ]]; then
  (cd ios && pod install)
fi

cat <<'EOF'
Next steps in Xcode:
1. Open ios/Runner.xcworkspace.
2. Select Runner > Signing & Capabilities.
3. Choose your Apple Developer Team.
4. Replace com.manus.flutterBookApp with your owned Bundle Identifier.
5. Confirm the App Store Connect subscription products.
6. Select a generic iOS device and archive, or run the command below.
EOF

flutter build ipa --release
printf '\nIPA output:\n'
find build/ios/ipa -maxdepth 1 -type f -name '*.ipa' -print
