#!/bin/bash
# Build the PRODUCTION (Release) build of the personal AltTabFix fork and install it to
# /Applications, replacing the running copy. Release strips all `#if DEBUG` code (QA menu, live
# queue graph, debug-tools window, benchmark) and optimizes (-O), so the daily driver carries no
# debug machinery. Signing/bundle-id come from config/local.xcconfig, so the new build inherits the
# already-granted Accessibility / Screen Recording permissions.
#
# Use this to refresh your daily driver (e.g. after merging a new upstream version).
# For iterative testing use ai/build.sh + ai/run.sh (Debug, keeps the benchmark CLI).
set -euo pipefail
cd "$(dirname "$0")/.."

# `git log --grep` matches the whole message, body included, so a commit that merely MENTIONS
# `chore(release):` in prose used to win — and `sed` passed the unmatched subject straight
# through, so the build got a version like "local: fix the thing". That string then lands in
# `preferencesVersion`, where it compares greater than any real version and silently disables
# every future preferences migration. Match anchored subjects only, and validate the result.
VERSION=$(git log --pretty=%s 2>/dev/null \
  | grep -m1 -E '^chore\(release\): [0-9]+\.[0-9]+\.[0-9]+' \
  | sed -E 's/^chore\(release\): ([0-9]+\.[0-9]+\.[0-9]+).*/\1/')
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || VERSION="0.0.0"
echo "Building AltTabFix $VERSION (Release)…"

# Clean Release tree: avoids incremental codesign flakiness on embedded frameworks (Sparkle).
rm -rf DerivedDataRelease
xcodebuild \
  -project alt-tab-macos.xcodeproj \
  -scheme Release -configuration Release \
  -derivedDataPath DerivedDataRelease \
  CURRENT_PROJECT_VERSION="$VERSION" MARKETING_VERSION="$VERSION" \
  OTHER_CODE_SIGN_FLAGS="--timestamp=none" \
  | tail -1

APP="DerivedDataRelease/Build/Products/Release/AltTab.app"
echo "Installing → /Applications/AltTabFix.app"
osascript -e 'tell application "AltTabFix" to quit' 2>/dev/null || true
pkill -f "/Applications/AltTabFix.app" 2>/dev/null || true
rm -rf /Applications/AltTabFix.app
ditto "$APP" /Applications/AltTabFix.app
open /Applications/AltTabFix.app
echo "Done: AltTabFix $VERSION is running."
