#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Toggler"
BUNDLE_ID="com.paolo.Toggler"
MIN_SYSTEM_VERSION="13.0"
XCODE_BETA_DEVELOPER_DIR="/Applications/Xcode-beta.app/Contents/Developer"

if [[ -z "${DEVELOPER_DIR:-}" && -d "$XCODE_BETA_DEVELOPER_DIR" ]]; then
  export DEVELOPER_DIR="$XCODE_BETA_DEVELOPER_DIR"
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
RESOURCE_DIR="$ROOT_DIR/Sources/Toggler/Resources"
APP_VERSION="$(
  git describe --tags --exact-match --abbrev=0 2>/dev/null \
    || git describe --tags --abbrev=0 2>/dev/null \
    || printf '0.0.0'
)"
APP_VERSION="${APP_VERSION#v}"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

swift build
BUILD_DIR="$(swift build --show-bin-path)"
BUILD_BINARY="$BUILD_DIR/$APP_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"
cp -X "$RESOURCE_DIR/AppIcon.icns" "$APP_RESOURCES/AppIcon.icns"
cp -X "$RESOURCE_DIR/MenuBarIconTemplate.png" "$APP_RESOURCES/MenuBarIconTemplate.png"

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon.icns</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$APP_VERSION</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSAppleEventsUsageDescription</key>
  <string>Toggler uses Apple Events as a fallback to hide the frontmost app assigned to a shortcut.</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

# Ad-hoc sign so the bundle is well-formed for TCC (Accessibility). Note: an ad-hoc
# signature has no stable identity, so macOS may still reset the Accessibility grant on
# each rebuild — re-grant Toggler (or toggle it off/on in Settings) after rebuilding.
xattr -cr "$APP_BUNDLE"
codesign --force --sign - "$APP_BUNDLE"

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  build|--build)
    ;;
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [build|run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
