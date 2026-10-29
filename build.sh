#!/bin/zsh
# Builds Sway.app next to this script. Needs Xcode (actool) for the Liquid Glass app icon.
set -euo pipefail
cd "$(dirname "$0")"

APP=Sway.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O -target "$(uname -m)-apple-macosx13.0" -o "$APP/Contents/MacOS/Sway" Sources/*.swift
# Compiles the layered Icon Composer icon (Assets.car), plus an .icns fallback for older macOS.
xcrun actool Resources/AppIcon.icon --compile "$APP/Contents/Resources" --app-icon AppIcon \
    --platform macosx --minimum-deployment-target 13.0 --target-device mac \
    --output-partial-info-plist /dev/null > /dev/null

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>local.sway</string>
    <key>CFBundleName</key><string>Sway</string>
    <key>CFBundleDisplayName</key><string>Sway</string>
    <key>CFBundleExecutable</key><string>Sway</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIconName</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "Built $(pwd)/$APP"
