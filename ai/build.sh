#!/bin/bash

# Derive the version from the latest `chore(release): X.Y.Z` commit. The Info.plist uses
# $(CURRENT_PROJECT_VERSION) for both CFBundleVersion and CFBundleShortVersionString; without a
# value, App.version force-unwraps nil and the app crashes on launch. The CI release pipeline
# injects this; for local builds we recover it from git. Fallback keeps the build runnable.
# `git log --grep` matches the whole message, body included, so a commit that merely MENTIONS
# `chore(release):` in prose used to win — and `sed` passed the unmatched subject straight
# through, so the build got a version like "local: fix the thing". That string then lands in
# `preferencesVersion`, where it compares greater than any real version and silently disables
# every future preferences migration. Match anchored subjects only, and validate the result.
#
# The subjects are captured first rather than piped into `grep -m1`: `-m1` closes the pipe on the
# first match, `git log` dies of SIGPIPE, and under `set -o pipefail` that aborts the whole script
# (exit 141) before it builds anything. A here-string has no producer left to signal.
SUBJECTS=$(git log --pretty=%s 2>/dev/null || true)
VERSION=$(grep -m1 -E '^chore\(release\): [0-9]+\.[0-9]+\.[0-9]+' <<< "$SUBJECTS" \
  | sed -E 's/^chore\(release\): ([0-9]+\.[0-9]+\.[0-9]+).*/\1/' || true)
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || VERSION="0.0.0"

xcodebuild \
  -project alt-tab-macos.xcodeproj \
  -scheme Debug \
  -configuration Debug \
  -derivedDataPath DerivedData \
  CURRENT_PROJECT_VERSION="$VERSION" \
  MARKETING_VERSION="$VERSION"
