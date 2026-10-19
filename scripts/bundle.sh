#!/bin/sh
# Builds a release DesktopEdit.app into build/ (SwiftPM can't produce app bundles itself).
# Run through `make app` so SDKROOT is set when only the Command Line Tools are installed.
set -eu
cd "$(dirname "$0")/.."

swift build -c release
BIN="$(swift build -c release --show-bin-path)/DesktopEdit"
APP=build/DesktopEdit.app

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/DesktopEdit"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Desktop Edit</string>
    <key>CFBundleDisplayName</key><string>Desktop Edit</string>
    <key>CFBundleIdentifier</key><string>dev.desktopedit.DesktopEdit</string>
    <key>CFBundleExecutable</key><string>DesktopEdit</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "Built $APP"
