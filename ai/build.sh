#!/bin/bash

# Derive the version from the latest `chore(release): X.Y.Z` commit. The Info.plist uses
# $(CURRENT_PROJECT_VERSION) for both CFBundleVersion and CFBundleShortVersionString; without a
# value, App.version force-unwraps nil and the app crashes on launch. The CI release pipeline
# injects this; for local builds we recover it from git. Fallback keeps the build runnable.
VERSION=$(git log -1 --grep='chore(release):' --pretty=%s 2>/dev/null \
  | sed -E 's/.*chore\(release\): ([0-9]+\.[0-9]+\.[0-9]+).*/\1/')
[ -z "$VERSION" ] && VERSION="0.0.0"

xcodebuild \
  -project alt-tab-macos.xcodeproj \
  -scheme Debug \
  -configuration Debug \
  -derivedDataPath DerivedData \
  CURRENT_PROJECT_VERSION="$VERSION" \
  MARKETING_VERSION="$VERSION"
