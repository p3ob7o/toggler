#!/usr/bin/env bash
# Build (and optionally run) Toggler via Xcode. The Xcode project is generated
# from project.yml by XcodeGen; this script regenerates it when needed, then
# builds with xcodebuild. Xcode owns icon compilation, Info.plist, signing, etc.
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Toggler"
SCHEME="Toggler"
CONFIG="Debug"
BUNDLE_ID="com.paolo.Toggler"
XCODE_BETA_DEVELOPER_DIR="/Applications/Xcode-beta.app/Contents/Developer"

if [[ -z "${DEVELOPER_DIR:-}" && -d "$XCODE_BETA_DEVELOPER_DIR" ]]; then
  export DEVELOPER_DIR="$XCODE_BETA_DEVELOPER_DIR"
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT_DIR/$APP_NAME.xcodeproj"
DERIVED="$ROOT_DIR/build/DerivedData"
APP_BUNDLE="$DERIVED/Build/Products/$CONFIG/$APP_NAME.app"

# Regenerate the Xcode project when it's missing or project.yml is newer.
if [[ ! -d "$PROJECT" || "$ROOT_DIR/project.yml" -nt "$PROJECT" ]]; then
  "$ROOT_DIR/script/bootstrap.sh"
fi

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIG" \
  -derivedDataPath "$DERIVED" \
  build

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
    lldb -- "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
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
