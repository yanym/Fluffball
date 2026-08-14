#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
KEYFRAME_DIR="$PROJECT_DIR/Assets/ImageTurnMVP/normalized"
OUTPUT_DIR="$PROJECT_DIR/Sources/Furball2D/Assets/Clips/left-profile"
OUTPUT_PATH="$OUTPUT_DIR/look-around-images.mov"
FACING_OUTPUT_DIR="$PROJECT_DIR/Sources/Furball2D/Assets/Clips/image-views"

if ! command -v ffmpeg >/dev/null 2>&1; then
  print -u2 "需要先安装 FFmpeg（brew install ffmpeg）。"
  exit 1
fi

typeset -a required_keyframes=(
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
for keyframe_name in "${required_keyframes[@]}"; do
  if [[ ! -f "$KEYFRAME_DIR/$keyframe_name.png" ]]; then
    print -u2 "缺少图片关键帧：$KEYFRAME_DIR/$keyframe_name.png"
    exit 1
  fi
done

mkdir -p "$OUTPUT_DIR" "$FACING_OUTPUT_DIR"

# 每个角度也导出为一段 1 秒无缝静止循环，供运行时按鼠标位置逐级切换。
# 使用 HEVC with Alpha 是为了复用现有 AVFoundation + Metal 双通道渲染器。
for keyframe_name in "${required_keyframes[@]}"; do
  ffmpeg -y -v warning \
    -loop 1 -framerate 24 -t 1.00 -i "$KEYFRAME_DIR/$keyframe_name.png" \
    -vf "format=bgra" -an \
    -c:v hevc_videotoolbox -alpha_quality 0.84 -q:v 62 -tag:v hvc1 \
    "$FACING_OUTPUT_DIR/$keyframe_name.mov"
done

# 这不是 AI 视频生成：只把 9 张透明 PNG 按角度排序，并用 0.07 秒短淡化
# 组成一次往返转身。首尾都使用 stand-idle 的左侧面端口，因此运行时可以平稳接回待机。
ffmpeg -y -v warning \
  -loop 1 -framerate 24 -t 0.36 -i "$KEYFRAME_DIR/left-profile.png" \
  -loop 1 -framerate 24 -t 0.20 -i "$KEYFRAME_DIR/front-near-profile-left.png" \
  -loop 1 -framerate 24 -t 0.20 -i "$KEYFRAME_DIR/front-three-quarter-left.png" \
  -loop 1 -framerate 24 -t 0.20 -i "$KEYFRAME_DIR/front-near-center-left.png" \
  -loop 1 -framerate 24 -t 0.55 -i "$KEYFRAME_DIR/front.png" \
  -loop 1 -framerate 24 -t 0.20 -i "$KEYFRAME_DIR/front-near-center-right.png" \
  -loop 1 -framerate 24 -t 0.20 -i "$KEYFRAME_DIR/front-three-quarter-right.png" \
  -loop 1 -framerate 24 -t 0.20 -i "$KEYFRAME_DIR/front-near-profile-right.png" \
  -loop 1 -framerate 24 -t 0.45 -i "$KEYFRAME_DIR/right-profile.png" \
  -loop 1 -framerate 24 -t 0.20 -i "$KEYFRAME_DIR/front-near-profile-right.png" \
  -loop 1 -framerate 24 -t 0.20 -i "$KEYFRAME_DIR/front-three-quarter-right.png" \
  -loop 1 -framerate 24 -t 0.20 -i "$KEYFRAME_DIR/front-near-center-right.png" \
  -loop 1 -framerate 24 -t 0.50 -i "$KEYFRAME_DIR/front.png" \
  -loop 1 -framerate 24 -t 0.20 -i "$KEYFRAME_DIR/front-near-center-left.png" \
  -loop 1 -framerate 24 -t 0.20 -i "$KEYFRAME_DIR/front-three-quarter-left.png" \
  -loop 1 -framerate 24 -t 0.20 -i "$KEYFRAME_DIR/front-near-profile-left.png" \
  -loop 1 -framerate 24 -t 0.36 -i "$KEYFRAME_DIR/left-profile.png" \
  -filter_complex "\
    [0:v]format=rgba,setpts=PTS-STARTPTS[k0];\
    [1:v]format=rgba,setpts=PTS-STARTPTS[k1];\
    [2:v]format=rgba,setpts=PTS-STARTPTS[k2];\
    [3:v]format=rgba,setpts=PTS-STARTPTS[k3];\
    [4:v]format=rgba,setpts=PTS-STARTPTS[k4];\
    [5:v]format=rgba,setpts=PTS-STARTPTS[k5];\
    [6:v]format=rgba,setpts=PTS-STARTPTS[k6];\
    [7:v]format=rgba,setpts=PTS-STARTPTS[k7];\
    [8:v]format=rgba,setpts=PTS-STARTPTS[k8];\
    [9:v]format=rgba,setpts=PTS-STARTPTS[k9];\
    [10:v]format=rgba,setpts=PTS-STARTPTS[k10];\
    [11:v]format=rgba,setpts=PTS-STARTPTS[k11];\
    [12:v]format=rgba,setpts=PTS-STARTPTS[k12];\
    [13:v]format=rgba,setpts=PTS-STARTPTS[k13];\
    [14:v]format=rgba,setpts=PTS-STARTPTS[k14];\
    [15:v]format=rgba,setpts=PTS-STARTPTS[k15];\
    [16:v]format=rgba,setpts=PTS-STARTPTS[k16];\
    [k0][k1]xfade=transition=fade:duration=0.07:offset=0.29[x1];\
    [x1][k2]xfade=transition=fade:duration=0.07:offset=0.42[x2];\
    [x2][k3]xfade=transition=fade:duration=0.07:offset=0.55[x3];\
    [x3][k4]xfade=transition=fade:duration=0.07:offset=0.68[x4];\
    [x4][k5]xfade=transition=fade:duration=0.07:offset=1.16[x5];\
    [x5][k6]xfade=transition=fade:duration=0.07:offset=1.29[x6];\
    [x6][k7]xfade=transition=fade:duration=0.07:offset=1.42[x7];\
    [x7][k8]xfade=transition=fade:duration=0.07:offset=1.55[x8];\
    [x8][k9]xfade=transition=fade:duration=0.07:offset=1.93[x9];\
    [x9][k10]xfade=transition=fade:duration=0.07:offset=2.06[x10];\
    [x10][k11]xfade=transition=fade:duration=0.07:offset=2.19[x11];\
    [x11][k12]xfade=transition=fade:duration=0.07:offset=2.32[x12];\
    [x12][k13]xfade=transition=fade:duration=0.07:offset=2.75[x13];\
    [x13][k14]xfade=transition=fade:duration=0.07:offset=2.88[x14];\
    [x14][k15]xfade=transition=fade:duration=0.07:offset=3.01[x15];\
    [x15][k16]xfade=transition=fade:duration=0.07:offset=3.14,\
    fps=24,format=bgra[out]" \
  -map "[out]" -an \
  -c:v hevc_videotoolbox -alpha_quality 0.84 -q:v 62 -tag:v hvc1 \
  "$OUTPUT_PATH"

print "图片转身 MVP 已写入：$OUTPUT_PATH"
print "鼠标朝向图片循环已写入：$FACING_OUTPUT_DIR"
