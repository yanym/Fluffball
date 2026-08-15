#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_VIEWS="$ROOT_DIR/Assets/ImageTurnMVP/normalized"
SOURCE_POSES="$ROOT_DIR/Assets/SourceImagesForAIVideo/generation-ready"
OUTPUT_ROOT="$ROOT_DIR/Sources/Furball2D/Assets/Images"

command -v ffmpeg >/dev/null 2>&1 || {
  echo "错误：需要 ffmpeg 才能构建图片模式素材。" >&2
  exit 1
}

mkdir -p \
  "$OUTPUT_ROOT/stand" \
  "$OUTPUT_ROOT/sit" \
  "$OUTPUT_ROOT/lie" \
  "$OUTPUT_ROOT/sleep"

stand_views=(
  left-profile
  front-near-profile-left
  front-three-quarter-left
  front-near-center-left
  front
  front-near-center-right
  front-three-quarter-right
  front-near-profile-right
  right-profile
)

for view in "${stand_views[@]}"; do
  source="$SOURCE_VIEWS/$view.png"
  destination="$OUTPUT_ROOT/stand/$view.png"
  [[ -f "$source" ]] || {
    echo "错误：缺少站姿图片 $source" >&2
    exit 1
  }
  cp "$source" "$destination"
done

key_pose() {
  local pose="$1"
  local view="$2"
  local source="$SOURCE_POSES/$pose/$view.png"
  local destination="$OUTPUT_ROOT/$pose/$view.png"
  [[ -f "$source" ]] || {
    echo "错误：缺少姿态图片 $source" >&2
    exit 1
  }

  # These identity-reference PNGs use the same flat green (RGB 0,177,64).
  # Fit the complete 4:3 source into the standard 16:9 canvas so generated
  # feet remain on the same y=540 baseline without runtime keying or cropping.
  ffmpeg -y -hide_banner -loglevel error \
    -i "$source" \
    -vf "format=rgba,colorkey=0x00b140:0.10:0.03,despill=green:mix=0.18:expand=0.03,scale=720:540:flags=lanczos+accurate_rnd,pad=960:540:120:0:color=black@0,format=rgba" \
    -frames:v 1 \
    "$destination"
}

for view in left-profile front right-profile; do
  key_pose sit "$view"
  key_pose lie "$view"
done

for view in left-profile right-profile; do
  key_pose sleep "$view"
done

echo "图片模式素材已构建：$OUTPUT_ROOT"
