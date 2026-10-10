#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/.cargo/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
bash scripts/build-app.sh universal 14.0
bundle="$TARGET_BUILD_DIR/$WRAPPER_NAME"
# Copy only this build's bundle; user data and installed applications are untouched.
/usr/bin/ditto dist/universal/Yeti3-Cleaner.app "$bundle"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $MARKETING_VERSION" "$bundle/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $CURRENT_PROJECT_VERSION" "$bundle/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :LSApplicationCategoryType string public.app-category.utilities' "$bundle/Contents/Info.plist"
if [[ "${CODE_SIGNING_ALLOWED:-YES}" != NO && -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ]]; then
 for binary in "$bundle/Contents/MacOS/yeti3-cleaner-engine" "$bundle/Contents/Helpers/Yeti3-DiskMap.app"; do
  /usr/bin/codesign --force --options runtime --sign "$EXPANDED_CODE_SIGN_IDENTITY" "$binary"
 done
fi
