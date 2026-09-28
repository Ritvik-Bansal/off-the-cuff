#!/bin/zsh
# Archives the app and uploads it to App Store Connect / TestFlight.
# Build number = UTC timestamp so every upload is unique and increasing.
# Usage: scripts/testflight.sh [--no-upload]
set -euo pipefail
cd "$(dirname "$0")/.."
BUILD_NUMBER=$(date -u +%Y%m%d%H%M)
ARCHIVE="build/Speak-$BUILD_NUMBER.xcarchive"
mkdir -p build

xcodegen generate --quiet
xcodebuild -project Speak.xcodeproj -scheme Speak -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  archive > "build/archive-$BUILD_NUMBER.log" 2>&1 || {
    grep -E "error:" "build/archive-$BUILD_NUMBER.log" | sort -u | head -30
    echo "Archive failed — see build/archive-$BUILD_NUMBER.log"; exit 1; }
echo "Archived build $BUILD_NUMBER -> $ARCHIVE"

if [[ "${1:-}" == "--no-upload" ]]; then exit 0; fi
xcodebuild -exportArchive -archivePath "$ARCHIVE" \
  -exportOptionsPlist Config/ExportOptions.plist \
  -exportPath "build/export-$BUILD_NUMBER" -allowProvisioningUpdates
echo "Uploaded build $BUILD_NUMBER to App Store Connect"
