#!/bin/sh
# Packages build/Dropsmith.app into build/Dropsmith-$VERSION.dmg with an Applications shortcut
# for drag-to-install. Run through `make dmg`, which builds the app first.
set -eu
VERSION="${VERSION:-0.1.0}"
cd "$(dirname "$0")/.."

APP=build/Dropsmith.app
DMG="build/Dropsmith-$VERSION.dmg"
STAGING="$(mktemp -d)/Dropsmith"

mkdir -p "$STAGING"
ditto "$APP" "$STAGING/Dropsmith.app"
ln -s /Applications "$STAGING/Applications"

rm -f "$DMG"
hdiutil create -volname "Dropsmith" -srcfolder "$STAGING" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
echo "Built $DMG"
