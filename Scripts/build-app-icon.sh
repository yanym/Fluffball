#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
SOURCE_PATH="${1:-$PROJECT_DIR/Support/AppIcon.png}"
OUTPUT_PATH="${2:-$PROJECT_DIR/Support/AppIcon.icns}"
WORK_DIR=""

cleanup_work_dir() {
  if [[ -n "$WORK_DIR" && "$WORK_DIR" == /tmp/furball-app-icon.* && -d "$WORK_DIR" ]]; then
    rm -rf "$WORK_DIR"
  fi
}
trap cleanup_work_dir EXIT

if [[ ! -f "$SOURCE_PATH" ]]; then
  print -u2 "找不到应用图标源文件：$SOURCE_PATH"
  exit 1
fi

WORK_DIR="$(mktemp -d /tmp/furball-app-icon.XXXXXX)"
ICONSET_DIR="$WORK_DIR/AppIcon.iconset"
MASTER_PATH="$WORK_DIR/master.png"
mkdir -p "$ICONSET_DIR"

sips -s format png "$SOURCE_PATH" --out "$MASTER_PATH" >/dev/null
width="$(sips -g pixelWidth "$MASTER_PATH" | awk '/pixelWidth/ { print $2 }')"
height="$(sips -g pixelHeight "$MASTER_PATH" | awk '/pixelHeight/ { print $2 }')"
if [[ "$width" != "$height" ]]; then
  print -u2 "应用图标必须是正方形，当前尺寸为 ${width}×${height}"
  exit 1
fi

typeset -a icon_specs=(
  '16:icon_16x16.png'
  '32:icon_16x16@2x.png'
  '32:icon_32x32.png'
  '64:icon_32x32@2x.png'
  '128:icon_128x128.png'
  '256:icon_128x128@2x.png'
  '256:icon_256x256.png'
  '512:icon_256x256@2x.png'
  '512:icon_512x512.png'
  '1024:icon_512x512@2x.png'
)

for spec in "${icon_specs[@]}"; do
  size="${spec%%:*}"
  file_name="${spec#*:}"
  sips -z "$size" "$size" "$MASTER_PATH" --out "$ICONSET_DIR/$file_name" >/dev/null
done

mkdir -p "${OUTPUT_PATH:h}"
iconutil -c icns "$ICONSET_DIR" -o "$OUTPUT_PATH"
print "已生成应用图标：$OUTPUT_PATH"
