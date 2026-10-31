#!/bin/zsh
# Builds Sway.app next to this script. Needs Xcode (actool) for the Liquid Glass app icon.
set -euo pipefail
cd "$(dirname "$0")"

APP=Sway.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# Universal binary, so the app runs on both Apple silicon and Intel Macs.
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
for arch in arm64 x86_64; do
    swiftc -O -target "$arch-apple-macosx13.0" -o "$TMP/Sway-$arch" Sources/*.swift
done
lipo -create -output "$APP/Contents/MacOS/Sway" "$TMP/Sway-arm64" "$TMP/Sway-x86_64"
# Compiles the layered Icon Composer icon (Assets.car), plus an .icns fallback for older macOS.
xcrun actool Resources/AppIcon.icon --compile "$APP/Contents/Resources" --app-icon AppIcon \
    --platform macosx --minimum-deployment-target 13.0 --target-device mac \
    --output-partial-info-plist /dev/null > /dev/null
# Translations: one <language>.lproj folder per language.
cp -R Resources/*.lproj "$APP/Contents/Resources/"
# The mascot's poses, cut out from docs/brand/mascot-sheet.webp.
cp -R Resources/Mascot "$APP/Contents/Resources/"
# The break chimes, made by tools/sounds.swift.
cp -R Resources/Sounds "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>local.sway</string>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleName</key><string>Sway</string>
    <key>CFBundleDisplayName</key><string>Sway</string>
    <key>CFBundleExecutable</key><string>Sway</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIconName</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.2</string>
    <key>CFBundleVersion</key><string>3</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "Built $(pwd)/$APP"
