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
print "Generated: $DMG_PATH"
shasum -a 256 "$DMG_PATH"
