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

typeset -a required_clips=(
  stand-idle stand-to-sit sit-idle sit-to-lie
  lie-idle lie-to-sleep sleep-idle sleep-to-stand
  walk-start walk-loop walk-stop
  slow-run-start slow-run-loop slow-run-stop
  fast-run-start fast-run-loop fast-run-stop
  look-around-images
)
assets_missing=false
for clip_name in "${required_clips[@]}"; do
  if [[ ! -f "$PROJECT_DIR/Sources/Furball2D/Assets/Clips/left-profile/$clip_name.mov" ]]; then
    assets_missing=true
    break
  fi
done
typeset -a required_image_views=(
  left-profile front-near-profile-left front-three-quarter-left
  front-near-center-left front front-near-center-right
  front-three-quarter-right front-near-profile-right right-profile
)
for view_name in "${required_image_views[@]}"; do
  if [[ ! -f "$PROJECT_DIR/Sources/Furball2D/Assets/Clips/image-views/$view_name.mov" ]]; then
    assets_missing=true
    break
  fi
done
if [[ "$assets_missing" == true ]]; then
  "$SCRIPT_DIR/build-assets.sh"
fi
if [[ ! -f "$PROJECT_DIR/Support/AppIcon.icns" ]]; then
  "$SCRIPT_DIR/build-app-icon.sh"
fi

# A Pet Pack is runtime data, not best-effort content. Reject incomplete or
# malformed packs before compiling/signing an application that cannot recover.
"$SCRIPT_DIR/validate-pet-pack.swift" "$PROJECT_DIR/Sources/Furball2D/Assets"

swift build -c release
BUILD_DIR="$(swift build -c release --show-bin-path)"
STAGE_DIR="$(mktemp -d /tmp/furball-package.XXXXXX)"
STAGE_APP="$STAGE_DIR/Furball2D.app"

mkdir -p "$STAGE_APP/Contents/MacOS" "$STAGE_APP/Contents/Resources"
cp "$BUILD_DIR/Furball2D" "$STAGE_APP/Contents/MacOS/Furball2D"
cp "$PROJECT_DIR/Support/Info.plist" "$STAGE_APP/Contents/Info.plist"
cp "$PROJECT_DIR/Support/AppIcon.icns" "$STAGE_APP/Contents/Resources/AppIcon.icns"
cp -R "$BUILD_DIR/Furball2D_Furball2D.bundle/Assets" "$STAGE_APP/Contents/Resources/Assets"
find "$STAGE_APP" -type f -name '.DS_Store' -delete

# Desktop 由 File Provider 管理，会主动给新 .app 写 FinderInfo。先在 /tmp 的干净
# 暂存区完成签名和严格校验，再制作不携带扩展属性的 ZIP，避免签名竞争。
xattr -cr "$STAGE_APP"
codesign --force --deep --sign - "$STAGE_APP"
codesign --verify --deep --strict "$STAGE_APP"

mkdir -p "$PROJECT_DIR/dist"
if [[ -e "$ARCHIVE_PATH" ]]; then
  rm -f "$ARCHIVE_PATH"
fi
ditto -c -k --keepParent --norsrc --noextattr "$STAGE_APP" "$ARCHIVE_PATH"

# 保留一个可直接双击运行的副本。即使 File Provider 随后添加展示元数据，也不会
# 影响本机运行；需要传输或复验签名时使用上面的 ZIP。
if [[ -d "$APP_DIR" ]]; then
  rm -rf "$APP_DIR"
fi
ditto --norsrc --noextattr "$STAGE_APP" "$APP_DIR"

print "已生成：$APP_DIR"
print "可传输包：$ARCHIVE_PATH"
