#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEAM_ID="${TEAM_ID:-49PHJ38L7T}"
if [[ ! "$TEAM_ID" =~ ^[A-Z0-9]{10}$ ]]; then
  echo 'TEAM_ID must have ten uppercase letters/digits' >&2
  exit 1
fi
mkdir -p build
xcodebuild -project Yeti3Cleaner.xcodeproj -scheme Yeti3Cleaner \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath build/Yeti3Cleaner.xcarchive \
  DEVELOPMENT_TEAM="$TEAM_ID" -allowProvisioningUpdates archive
