#!/usr/bin/env bash
# bump_build.sh — set the iOS build number (CFBundleVersion) to the current git
# commit count, which is always monotonically increasing. Run this once before
# you archive in Xcode so every TestFlight/App Store upload gets a unique,
# higher build number (App Store Connect rejects a build number it has seen
# before for the same marketing version).
#
# The marketing version (MARKETING_VERSION, e.g. 2.0 — the number users see) is
# left untouched; bump that by hand when you cut a real new version.
#
# Usage:  ./bump_build.sh
set -euo pipefail
cd "$(dirname "$0")"

PBXPROJ="ShelfV2/Shelf.xcodeproj/project.pbxproj"
BUILD="$(git rev-list --count HEAD)"

# Update every CURRENT_PROJECT_VERSION line (Debug + Release) to the new number.
sed -i '' -E "s/CURRENT_PROJECT_VERSION = [0-9]+;/CURRENT_PROJECT_VERSION = ${BUILD};/g" "$PBXPROJ"

VERSION="$(grep -m1 -E "MARKETING_VERSION = " "$PBXPROJ" | sed -E 's/.*= ([^;]+);/\1/')"
echo "✅ Build number set to ${BUILD} (marketing version ${VERSION})."
echo "   Now in Xcode: Product → Archive → Distribute App → TestFlight & App Store."
