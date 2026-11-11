#!/bin/bash
# Builds Flowly.app (release, Apple Silicon) into ./dist
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
APP=dist/Flowly.app
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Flowly "$APP/Contents/MacOS/Flowly"
# Icon
TMP=$(mktemp -d); swift scripts/make_icon.swift "$TMP/icon.png"
mkdir "$TMP/Flowly.iconset"
for s in 16 32 128 256 512; do
  sips -z $s $s "$TMP/icon.png" --out "$TMP/Flowly.iconset/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) "$TMP/icon.png" --out "$TMP/Flowly.iconset/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$TMP/Flowly.iconset" -o "$APP/Contents/Resources/Flowly.icns"
cat > "$APP/Contents/Info.plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Flowly</string>
<key>CFBundleDisplayName</key><string>Flowly</string>
<key>CFBundleIdentifier</key><string>com.flowly.app</string>
<key>CFBundleExecutable</key><string>Flowly</string>
<key>CFBundleIconFile</key><string>Flowly</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSMicrophoneUsageDescription</key><string>Flowly listens while you hold the dictation key and transcribes your speech on this Mac.</string>
</dict></plist>
PL
# Stable signing identity: a self-signed "Flowly Dev" certificate keeps macOS permissions (Accessibility, Input Monitoring) across rebuilds.
# Without it the app is ad-hoc signed and macOS asks again after every rebuild. See README for how to create the certificate.
IDENT="-"
HASH=$(security find-identity -p codesigning 2>/dev/null | grep "Flowly Dev" | head -1 | awk '{print $2}')
[ -n "$HASH" ] && IDENT="$HASH"
codesign --force --deep --sign "$IDENT" --entitlements scripts/Flowly.entitlements "$APP"
echo "Built $APP (signed: $IDENT)"
