#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
APP_DIR="$PROJECT_DIR/dist/Furball2D.app"
ARCHIVE_PATH="$PROJECT_DIR/dist/Furball2D.zip"
BUILD_DIR=""
STAGE_DIR=""
STAGE_APP=""

cleanup_stage() {
  if [[ -n "$STAGE_DIR" && "$STAGE_DIR" == /tmp/furball-package.* && -d "$STAGE_DIR" ]]; then
    rm -rf "$STAGE_DIR"
  fi
}
trap cleanup_stage EXIT

cd "$PROJECT_DIR"

PETS_DIR="$PROJECT_DIR/Sources/Furball2D/Assets/Pets"
NINA_PACK_DIR="$PETS_DIR/Nina"
MANIFEST_PATH="$NINA_PACK_DIR/manifest.json"
video_mode_enabled=false
image_mode_enabled=false
if grep -Eq '"videoMode"[[:space:]]*:[[:space:]]*true' "$MANIFEST_PATH"; then
  video_mode_enabled=true
fi
if grep -Eq '"imageMode"[[:space:]]*:[[:space:]]*true' "$MANIFEST_PATH"; then
  image_mode_enabled=true
fi

typeset -a required_clips=(
  stand-idle stand-to-sit sit-idle sit-to-lie
  lie-idle lie-to-sleep sleep-idle sleep-to-stand
  walk-start walk-loop walk-stop
  slow-run-start slow-run-loop slow-run-stop
  fast-run-start fast-run-loop fast-run-stop
  look-around-images
)
assets_missing=false
if [[ "$video_mode_enabled" == true ]]; then
  for clip_name in "${required_clips[@]}"; do
    if [[ ! -f "$NINA_PACK_DIR/Clips/left-profile/$clip_name.mov" ]]; then
      assets_missing=true
      break
    fi
  done
fi
typeset -a required_image_views=(
  left-profile front-near-profile-left front-three-quarter-left
  front-near-center-left front front-near-center-right
  front-three-quarter-right front-near-profile-right right-profile
)
if [[ "$video_mode_enabled" == true ]]; then
  for view_name in "${required_image_views[@]}"; do
    if [[ ! -f "$NINA_PACK_DIR/Clips/image-views/$view_name.mov" ]]; then
      assets_missing=true
      break
    fi
  done
fi
if [[ "$assets_missing" == true ]]; then
  "$SCRIPT_DIR/build-assets.sh"
fi

if [[ ! -f "$PROJECT_DIR/Support/AppIcon.icns" ]]; then
  "$SCRIPT_DIR/build-app-icon.sh"
fi

# A Pet Pack is runtime data, not best-effort content. Reject incomplete or
# malformed packs before compiling/signing an application that cannot recover.
for pack_dir in "$PETS_DIR"/*; do
  [[ -d "$pack_dir" ]] || continue
  "$SCRIPT_DIR/validate-pet-pack.swift" "$pack_dir"
done

# Exercise one complete interaction instead of treating compilation as product
# QA. This catches orphan treat windows, never-ending locomotion, missing pet
# content, and a lost menu-bar recovery entry. Headless release automation may
# explicitly opt out after running an equivalent UI test stage.
if [[ "${FURBALL_SKIP_BEHAVIOR_QA:-0}" != "1" ]]; then
  "$SCRIPT_DIR/behavior-qa.sh"
fi

swift build -c release
BUILD_DIR="$(swift build -c release --show-bin-path)"
STAGE_DIR="$(mktemp -d /tmp/furball-package.XXXXXX)"
STAGE_APP="$STAGE_DIR/Furball2D.app"

mkdir -p "$STAGE_APP/Contents/MacOS" "$STAGE_APP/Contents/Resources"
cp "$BUILD_DIR/Furball2D" "$STAGE_APP/Contents/MacOS/Furball2D"
cp "$PROJECT_DIR/Support/Info.plist" "$STAGE_APP/Contents/Info.plist"
cp "$PROJECT_DIR/Support/AppIcon.icns" "$STAGE_APP/Contents/Resources/AppIcon.icns"
cp -R "$BUILD_DIR/Furball2D_Furball2D.bundle/Assets" "$STAGE_APP/Contents/Resources/Assets"
cp -R "$BUILD_DIR/Furball2D_Furball2D.bundle/CreatorSkill" "$STAGE_APP/Contents/Resources/CreatorSkill"
find "$STAGE_APP" -type f -name '.DS_Store' -delete

# Desktop may be managed by File Provider and can add FinderInfo to a new app. Sign and verify
# in a clean /tmp staging area, then create a ZIP without extended attributes.
xattr -cr "$STAGE_APP"
SIGN_IDENTITY="${FURBALL_CODESIGN_IDENTITY:--}"
if [[ "$SIGN_IDENTITY" == "-" ]]; then
  codesign --force --deep --sign - "$STAGE_APP"
else
  codesign --force --deep --options runtime --timestamp --sign "$SIGN_IDENTITY" "$STAGE_APP"
fi
codesign --verify --deep --strict "$STAGE_APP"

mkdir -p "$PROJECT_DIR/dist"
if [[ -e "$ARCHIVE_PATH" ]]; then
  rm -f "$ARCHIVE_PATH"
fi
ditto -c -k --keepParent --norsrc --noextattr "$STAGE_APP" "$ARCHIVE_PATH"

# Optional commercial release path. Configure a notarytool keychain profile
# once, then package with FURBALL_CODESIGN_IDENTITY and
# FURBALL_NOTARY_PROFILE. Local preview builds remain ad-hoc signed.
if [[ -n "${FURBALL_NOTARY_PROFILE:-}" ]]; then
  if [[ "$SIGN_IDENTITY" == "-" ]]; then
    print -u2 "FURBALL_NOTARY_PROFILE requires a Developer ID signing identity"
    exit 1
  fi
  xcrun notarytool submit "$ARCHIVE_PATH" \
    --keychain-profile "$FURBALL_NOTARY_PROFILE" \
    --wait
  xcrun stapler staple "$STAGE_APP"
  codesign --verify --deep --strict "$STAGE_APP"
  rm -f "$ARCHIVE_PATH"
  ditto -c -k --keepParent --norsrc --noextattr "$STAGE_APP" "$ARCHIVE_PATH"
fi

# Keep a directly launchable copy. File Provider display metadata does not affect local use;
# use the ZIP for transfer or strict signature verification.
if [[ -d "$APP_DIR" ]]; then
  rm -rf "$APP_DIR"
fi
ditto --norsrc --noextattr "$STAGE_APP" "$APP_DIR"

print "Generated: $APP_DIR"
print "Transfer archive: $ARCHIVE_PATH"
