#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
APP_DIR="$PROJECT_DIR/dist/Furball.app"
ARCHIVE_PATH="$PROJECT_DIR/dist/Furball.zip"
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

# Shipping is blocked if Finder automation or a user-file mutation API ever
# re-enters the runtime target.
"$SCRIPT_DIR/audit-runtime-safety.sh"

PETS_DIR="$PROJECT_DIR/Sources/Furball2D/Assets/Pets"
typeset -a live_motion_pet_ids=()
for pack_dir in "$PETS_DIR"/*; do
  [[ -d "$pack_dir" ]] || continue
  manifest="$pack_dir/manifest.json"
  if grep -Eq '"videoMode"[[:space:]]*:[[:space:]]*true' "$manifest"; then
    pet_id="$(plutil -extract pet.id raw -o - "$manifest")"
    live_motion_pet_ids+=("$pet_id")
    while IFS= read -r relative_clip; do
      [[ -f "$pack_dir/$relative_clip" ]] && continue
      if [[ "$pet_id" == "furball-demo-dog" ]]; then
        "$SCRIPT_DIR/build-assets.sh"
      elif [[ "$pet_id" == "fortune" ]]; then
        "$SCRIPT_DIR/build-fortune-live-motion-assets.sh"
      else
        print -u2 "Missing Live Motion clip for $pet_id: $relative_clip"
        exit 1
      fi
      break
    done < <(awk '
      /"clips"[[:space:]]*:[[:space:]]*\[/ { in_clips=1; next }
      in_clips && /^[[:space:]]*\]/ { exit }
      in_clips && match($0, /"file"[[:space:]]*:[[:space:]]*"[^"]+"/) {
        value=substr($0, RSTART, RLENGTH)
        sub(/^.*"file"[[:space:]]*:[[:space:]]*"/, "", value)
        sub(/"$/, "", value)
        print value
      }
    ' "$manifest")
  fi
done

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
  for pet_id in "${live_motion_pet_ids[@]}"; do
    FURBALL_PET_ID="$pet_id" FURBALL_BEHAVIOR_QA_APPEARANCE=continuous-video "$SCRIPT_DIR/behavior-qa.sh"
  done
fi
if [[ "${FURBALL_SKIP_LIVE_MOTION_QA:-0}" != "1" ]]; then
  for pet_id in "${live_motion_pet_ids[@]}"; do
    FURBALL_PET_ID="$pet_id" "$SCRIPT_DIR/live-motion-qa.sh"
  done
fi

swift build -c release
BUILD_DIR="$(swift build -c release --show-bin-path)"
STAGE_DIR="$(mktemp -d /tmp/furball-package.XXXXXX)"
STAGE_APP="$STAGE_DIR/Furball.app"

mkdir -p "$STAGE_APP/Contents/MacOS" "$STAGE_APP/Contents/Resources"
cp "$BUILD_DIR/Furball" "$STAGE_APP/Contents/MacOS/Furball"
cp "$PROJECT_DIR/Support/Info.plist" "$STAGE_APP/Contents/Info.plist"
cp "$PROJECT_DIR/Support/AppIcon.icns" "$STAGE_APP/Contents/Resources/AppIcon.icns"
cp -R "$BUILD_DIR/Furball_Furball.bundle/Assets" "$STAGE_APP/Contents/Resources/Assets"
cp -R "$BUILD_DIR/Furball_Furball.bundle/CreatorSkill" "$STAGE_APP/Contents/Resources/CreatorSkill"
cp -R "$BUILD_DIR/Furball_Furball.bundle/VideoCreatorSkill" "$STAGE_APP/Contents/Resources/VideoCreatorSkill"
find "$STAGE_APP" -type f -name '.DS_Store' -delete
find "$STAGE_APP/Contents/Resources/CreatorSkill" -type d -name '__pycache__' -prune -exec rm -rf {} +
find "$STAGE_APP/Contents/Resources/CreatorSkill" -type f \( -name '*.pyc' -o -name '*.pyo' \) -delete
find "$STAGE_APP/Contents/Resources/VideoCreatorSkill" -type d -name '__pycache__' -prune -exec rm -rf {} +
find "$STAGE_APP/Contents/Resources/VideoCreatorSkill" -type f \( -name '*.pyc' -o -name '*.pyo' \) -delete

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
