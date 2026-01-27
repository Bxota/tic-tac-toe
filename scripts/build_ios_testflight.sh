#!/usr/bin/env bash
set -euo pipefail

# Build an iOS IPA for TestFlight.
# Prereqs: Xcode installed, Apple Developer account, signing configured in ios/Runner.
# Optional env:
#   SERVER_URL (default: wss://tictactoe.bxota.com/ws)
#   BUILD_NAME (default: 1.0.0)
#   BUILD_NUMBER (default: 1)
#   EXPORT_OPTIONS_PLIST (optional path for export options)

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

SERVER_URL="${SERVER_URL:-wss://tictactoe.bxota.com/ws}"
BUILD_NAME="${BUILD_NAME:-1.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
EXPORT_OPTIONS_PLIST="${EXPORT_OPTIONS_PLIST:-}"

flutter pub get

if [[ -n "$EXPORT_OPTIONS_PLIST" ]]; then
  flutter build ipa \
    --release \
    --dart-define=SERVER_URL="$SERVER_URL" \
    --build-name="$BUILD_NAME" \
    --build-number="$BUILD_NUMBER" \
    --export-options-plist="$EXPORT_OPTIONS_PLIST"
else
  flutter build ipa \
    --release \
    --dart-define=SERVER_URL="$SERVER_URL" \
    --build-name="$BUILD_NAME" \
    --build-number="$BUILD_NUMBER"
fi

IPA_PATH=$(ls -1 build/ios/ipa/*.ipa | head -n 1 || true)

if [[ -z "$IPA_PATH" ]]; then
  echo "IPA not found. Check Xcode signing settings and try again." >&2
  exit 1
fi

echo "IPA generated: $IPA_PATH"
echo "Upload to TestFlight via Xcode Organizer: Xcode > Window > Organizer > Distribute App"
