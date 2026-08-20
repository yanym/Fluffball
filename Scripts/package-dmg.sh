#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
APP_PATH="$PROJECT_DIR/dist/Furball.app"
ARCHIVE_PATH="$PROJECT_DIR/dist/Furball.zip"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PROJECT_DIR/Support/Info.plist")"
DMG_PATH="$PROJECT_DIR/dist/Furball-v${VERSION}-macOS-Apple-Silicon.dmg"
STAGE_DIR=""

cleanup() {
  if [[ -n "$STAGE_DIR" && "$STAGE_DIR" == /tmp/fluffball-dmg.* && -d "$STAGE_DIR" ]]; then
    rm -rf "$STAGE_DIR"
  fi
}
trap cleanup EXIT

if [[ ! -d "$APP_PATH" || ! -f "$ARCHIVE_PATH" ]]; then
  "$SCRIPT_DIR/package-app.sh"
fi

STAGE_DIR="$(mktemp -d /tmp/fluffball-dmg.XXXXXX)"
ditto -x -k --norsrc --noextattr "$ARCHIVE_PATH" "$STAGE_DIR"
codesign --verify --deep --strict "$STAGE_DIR/Furball.app"
ln -s /Applications "$STAGE_DIR/Applications"

hdiutil create \
  -volname "Furball ${VERSION}" \
  -srcfolder "$STAGE_DIR" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -ov \
  "$DMG_PATH"
hdiutil verify "$DMG_PATH"

# Sign and notarize the artifact users actually download. The app inside the
# image has already been signed/stapled by package-app.sh; notarizing the DMG as
# well lets Gatekeeper validate the outer container before it is mounted.
SIGN_IDENTITY="${FURBALL_CODESIGN_IDENTITY:--}"
NOTARY_PROFILE="${FURBALL_NOTARY_PROFILE:-}"
if [[ "$SIGN_IDENTITY" != "-" ]]; then
  codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG_PATH"
  codesign --verify --verbose=2 "$DMG_PATH"
fi
if [[ -n "$NOTARY_PROFILE" ]]; then
  if [[ "$SIGN_IDENTITY" == "-" ]]; then
    print -u2 "FURBALL_NOTARY_PROFILE requires a Developer ID signing identity"
    exit 1
  fi
  xcrun notarytool submit "$DMG_PATH" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait
  xcrun stapler staple "$DMG_PATH"
  xcrun stapler validate "$DMG_PATH"
  codesign --verify --verbose=2 "$DMG_PATH"
fi

print "Generated: $DMG_PATH"
shasum -a 256 "$DMG_PATH"
