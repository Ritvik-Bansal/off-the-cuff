#!/bin/zsh
# Usage: scripts/check.sh <agent-name> [filter-regex]
# Builds the app for the iOS Simulator with a private DerivedData folder and prints
# compiler errors (and warnings from the Speak sources), optionally filtered by a path regex.
set -o pipefail
NAME=${1:-default}
FILTER=${2:-.}
cd "$(dirname "$0")/.."
SCRATCH="${TMPDIR:-/tmp}/speak-check"
mkdir -p "$SCRATCH"
LOG=$SCRATCH/build-$NAME.log
xcodebuild -project Speak.xcodeproj -scheme Speak \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$SCRATCH/dd-$NAME" \
  -clonedSourcePackagesDirPath "$SCRATCH/spm" \
  build > "$LOG" 2>&1
STATUS=$?
grep -E "(error|warning): " "$LOG" | grep "/Speak/" | grep -E "$FILTER" | sort -u | head -80
if [ $STATUS -eq 0 ]; then echo "BUILD SUCCEEDED"; else
  echo "BUILD FAILED (all errors, any file):"; grep -E "error: " "$LOG" | sort -u | head -40
fi
