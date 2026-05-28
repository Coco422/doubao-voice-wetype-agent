#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="${APP_NAME:-Doubao Voice WeType Agent.app}"
PRODUCT_NAME="${PRODUCT_NAME:-Doubao Voice WeType Agent}"
BUNDLE_ID="${BUNDLE_ID:-com.github.Coco422.doubao-voice-wetype-agent}"
VERSION_RAW="${VERSION:-$(git -C "$ROOT" describe --tags --always --dirty 2>/dev/null || date +%Y%m%d%H%M%S)}"
VERSION="$(printf '%s' "$VERSION_RAW" | tr -c 'A-Za-z0-9._-' '-')"
DIST="$ROOT/dist"
BUILD_DIR="$DIST/dmg-build"
APP="$DIST/$APP_NAME"
STAGE="$BUILD_DIR/stage"
DMG="$DIST/DoubaoVoiceWeTypeAgent-$VERSION.dmg"

rm -rf "$BUILD_DIR" "$APP" "$DMG"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$STAGE"

swift build -c release --package-path "$ROOT"

cp "$ROOT/.build/release/doubao-voice-wetype-agent" "$APP/Contents/MacOS/doubao-voice-wetype-agent"
cp "$ROOT/.build/release/im-switch" "$APP/Contents/Resources/im-switch"
chmod +x "$APP/Contents/MacOS/doubao-voice-wetype-agent" "$APP/Contents/Resources/im-switch"

if [ -f "$ROOT/Sources/DoubaoVoiceWeTypeAgent/Resources/AppIcon.icns" ]; then
  cp "$ROOT/Sources/DoubaoVoiceWeTypeAgent/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>doubao-voice-wetype-agent</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$PRODUCT_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$VERSION</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

if [ -n "${CODESIGN_IDENTITY:-}" ]; then
  codesign --force --deep --options runtime --timestamp --sign "$CODESIGN_IDENTITY" "$APP"
else
  codesign --force --deep --sign - "$APP"
fi

ditto "$APP" "$STAGE/$APP_NAME"
cp "$ROOT/scripts/install_or_update_app.sh" "$STAGE/1 Double-click to Install or Update.command"
chmod +x "$STAGE/1 Double-click to Install or Update.command"
mkdir -p "$STAGE/launchd"
cp "$ROOT/launchd/com.github.Coco422.doubao-voice-wetype-agent.plist.template" "$STAGE/launchd/"

cat > "$STAGE/README - Start Here.txt" <<README
Doubao Voice WeType Agent

Recommended install or update:
1. Double-click "1 Double-click to Install or Update.command".
2. On first install, grant Accessibility and Input Monitoring permissions to:
   ~/Applications/Doubao Voice WeType Agent.app/Contents/MacOS/doubao-voice-wetype-agent

You can also double-click the app directly. It will copy itself to ~/Applications,
register the LaunchAgent, then run from the installed location.

Updates use the same app path and LaunchAgent label. For best permission stability,
build releases with the same Developer ID codesigning identity:

  CODESIGN_IDENTITY="Developer ID Application: ..." ./scripts/package_dmg.sh
README

hdiutil create \
  -volname "$PRODUCT_NAME" \
  -srcfolder "$STAGE" \
  -ov \
  -format UDZO \
  "$DMG"

rm -rf "$BUILD_DIR"

cat <<MSG
Created:
  $APP
  $DMG

Codesigning:
  ${CODESIGN_IDENTITY:-ad-hoc}
MSG
