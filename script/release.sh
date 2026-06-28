#!/usr/bin/env bash
# release.sh — build, sign (Developer ID), notarize, staple, and publish a
# Toggler release zip to GitHub.
#
# Prereqs:
#   1. A "Developer ID Application" certificate in the keychain.
#   2. A notarytool keychain profile (default name AC_PASSWORD), e.g.:
#        xcrun notarytool store-credentials AC_PASSWORD \
#          --apple-id YOU@EXAMPLE.COM --team-id <TEAM> --password <APP_SPECIFIC_PW>
#   3. gh authenticated to push the release.
#
# Usage:
#   script/release.sh [version]      # version defaults to MARKETING_VERSION in project.yml
#   RELEASE_DRY_RUN=1 script/release.sh   # build + sign + verify only; no notarize/publish
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

APP_NAME="Toggler"
SCHEME="Toggler"
KEYCHAIN_PROFILE="${KEYCHAIN_PROFILE:-AC_PASSWORD}"
BUILD_DIR="build/release"
ARCHIVE_PATH="$BUILD_DIR/$APP_NAME.xcarchive"
EXPORT_PATH="$BUILD_DIR/export"
EXPORT_OPTIONS="$BUILD_DIR/ExportOptions.plist"
APP_PATH="$EXPORT_PATH/$APP_NAME.app"
LOG_DIR="$BUILD_DIR/logs"

XCODE_BETA="/Applications/Xcode-beta.app/Contents/Developer"
if [[ -z "${DEVELOPER_DIR:-}" && -d "$XCODE_BETA" ]]; then
  export DEVELOPER_DIR="$XCODE_BETA"
fi

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
  VERSION=$(awk -F'"' '/MARKETING_VERSION:/{print $2; exit}' project.yml)
fi
if [[ -z "$VERSION" ]]; then
  echo "error: no version (pass as arg or set MARKETING_VERSION in project.yml)." >&2
  exit 64
fi
TAG="v$VERSION"
ZIP="$BUILD_DIR/$APP_NAME-$VERSION.zip"

# ---- Tool checks ----
for t in xcodegen xcodebuild xcrun gh ditto; do
  command -v "$t" >/dev/null 2>&1 || { echo "error: '$t' not found in PATH." >&2; exit 70; }
done

# ---- Developer ID identity + team ----
IDENTITY_LINE=$(security find-identity -p codesigning -v 2>/dev/null | grep "Developer ID Application" | head -1 || true)
if [[ -z "$IDENTITY_LINE" ]]; then
  echo "error: no 'Developer ID Application' certificate found in the keychain." >&2
  exit 71
fi
IDENTITY=$(echo "$IDENTITY_LINE" | sed -nE 's/.*"(.+)"/\1/p')
TEAM_ID=$(echo "$IDENTITY" | sed -nE 's/.*\(([A-Z0-9]{10})\).*/\1/p')
echo "==> Signing identity: $IDENTITY (team $TEAM_ID)"

# ---- notarytool profile check ----
if ! xcrun notarytool history --keychain-profile "$KEYCHAIN_PROFILE" >/dev/null 2>&1; then
  echo "error: notarytool keychain profile '$KEYCHAIN_PROFILE' is not configured." >&2
  echo "       Set it up with: xcrun notarytool store-credentials $KEYCHAIN_PROFILE --apple-id ... --team-id $TEAM_ID --password ..." >&2
  exit 72
fi

echo "==> Releasing $APP_NAME $VERSION"
xcodegen generate >/dev/null
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR" "$EXPORT_PATH" "$LOG_DIR"

# ---- Archive (universal, Developer ID, hardened runtime) ----
echo "==> Archiving (a few minutes; full log: $LOG_DIR/archive.log)"
if ! xcodebuild archive \
      -project "$APP_NAME.xcodeproj" \
      -scheme "$SCHEME" \
      -configuration Release \
      -archivePath "$ARCHIVE_PATH" \
      -destination "generic/platform=macOS" \
      ARCHS="arm64 x86_64" \
      ONLY_ACTIVE_ARCH=NO \
      CODE_SIGN_STYLE=Manual \
      CODE_SIGN_IDENTITY="$IDENTITY" \
      DEVELOPMENT_TEAM="$TEAM_ID" \
      PROVISIONING_PROFILE_SPECIFIER="" \
      ENABLE_HARDENED_RUNTIME=YES \
      > "$LOG_DIR/archive.log" 2>&1; then
  echo "error: archive failed. Tail of log:" >&2; tail -40 "$LOG_DIR/archive.log" >&2; exit 73
fi

# ---- ExportOptions.plist ----
cat > "$EXPORT_OPTIONS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>$TEAM_ID</string>
    <key>signingStyle</key>
    <string>manual</string>
</dict>
</plist>
PLIST

# ---- Export the signed .app ----
echo "==> Exporting signed .app (full log: $LOG_DIR/export.log)"
if ! xcodebuild -exportArchive \
      -archivePath "$ARCHIVE_PATH" \
      -exportPath "$EXPORT_PATH" \
      -exportOptionsPlist "$EXPORT_OPTIONS" \
      > "$LOG_DIR/export.log" 2>&1; then
  echo "error: export failed. Tail of log:" >&2; tail -40 "$LOG_DIR/export.log" >&2; exit 74
fi
[[ -d "$APP_PATH" ]] || { echo "error: export did not produce $APP_PATH" >&2; exit 75; }

# ---- Verify signature ----
echo "==> Verifying signature"
codesign --verify --strict --verbose=2 "$APP_PATH" 2>&1 | grep -E "valid on disk|Designated Requirement" || true
codesign --display --verbose=2 "$APP_PATH" 2>&1 | grep -E "Authority=Developer ID|TeamIdentifier|flags"
echo "    archs: $(lipo -archs "$APP_PATH/Contents/MacOS/$APP_NAME")"

if [[ "${RELEASE_DRY_RUN:-0}" == "1" ]]; then
  echo "==> DRY RUN: signed app at $APP_PATH (skipping notarize + publish)"
  exit 0
fi

# ---- Zip + notarize ----
ditto -c -k --keepParent "$APP_PATH" "$ZIP"
echo "==> Submitting for notarization (typically 2-10 minutes)"
xcrun notarytool submit "$ZIP" --keychain-profile "$KEYCHAIN_PROFILE" --wait

# ---- Staple + re-zip (so the downloaded copy carries the ticket) ----
echo "==> Stapling"
xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"
ditto -c -k --keepParent "$APP_PATH" "$ZIP"
spctl -a -vv -t exec "$APP_PATH" 2>&1 || true

# ---- Tag + GitHub release ----
SHA=$(shasum -a 256 "$ZIP" | awk '{print $1}')
PREV_TAG=$(git tag -l 'v*' --sort=-v:refname | grep -v "^$TAG$" | head -1 || true)
NOTES_FILE="$BUILD_DIR/notes.md"
{
  echo "## Changes"
  if [[ -n "$PREV_TAG" ]]; then
    git log --pretty='- %s' "$PREV_TAG"..HEAD
  fi
  echo
  echo "Artifact: $APP_NAME-$VERSION.zip — Universal (arm64 + x86_64), Developer ID signed, notarized + stapled."
  echo "SHA-256: $SHA"
  echo
  echo "Install: unzip and move $APP_NAME.app to /Applications. Requires macOS 13+."
} > "$NOTES_FILE"

git tag -fa "$TAG" -m "Toggler $VERSION"
GIT_TERMINAL_PROMPT=0 git -c pack.threads=1 push -f origin "$TAG"
gh release create "$TAG" "$ZIP" --title "$APP_NAME $VERSION" --notes-file "$NOTES_FILE" --latest

echo
echo "Done. Released $TAG"
echo "    zip:    $ZIP"
echo "    sha256: $SHA"
