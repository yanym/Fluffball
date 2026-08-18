#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
KEYFRAME_DIR="$PROJECT_DIR/Assets/ImageTurnMVP/normalized"
OUTPUT_DIR="$PROJECT_DIR/Sources/Furball2D/Assets/Clips/left-profile"
OUTPUT_PATH="$OUTPUT_DIR/look-around-images.mov"
FACING_OUTPUT_DIR="$PROJECT_DIR/Sources/Furball2D/Assets/Clips/image-views"
TARGET_FPS=120

# 图片视角来自多次独立生成，曝光和白平衡差异比几何差异更容易在短淡化中被看见。
# 以 left-profile 为参考，分别用黑毛、棕毛和白毛统计值建立单调 PCHIP 曲线。
image_curve_points() {
  local source_black="$1"
  local source_tan="$2"
  local source_white="$3"
  local target_black="$4"
  local target_tan="$5"
  local target_white="$6"
  awk \
    -v x1="$source_black" -v x2="$source_tan" -v x3="$source_white" \
    -v y1="$target_black" -v y2="$target_tan" -v y3="$target_white" \
    'BEGIN {
      printf "0/0 %.6f/%.6f %.6f/%.6f %.6f/%.6f 1/1", \
        x1/255, y1/255, x2/255, y2/255, x3/255, y3/255
    }'
}

image_color_filter() {
  local keyframe_name="$1"
  local -a anchors
  case "$keyframe_name" in
    left-profile) print -r -- "null"; return ;;
    front-near-center-left) anchors=(39.3 157.1 229.4 29.1 116.9 214.2 26.4 83.7 204.6) ;;
    front-near-center-right) anchors=(39.1 151.4 229.9 30.5 112.9 216.7 28.0 84.4 208.7) ;;
    front-near-profile-left) anchors=(34.4 128.9 219.7 26.6 87.7 202.4 28.4 74.0 203.2) ;;
    front-near-profile-right) anchors=(30.7 146.8 231.7 23.5 107.6 219.7 21.3 70.9 211.5) ;;
    front-three-quarter-left) anchors=(34.2 143.5 221.4 25.5 104.1 206.7 23.1 72.5 195.8) ;;
    front-three-quarter-right) anchors=(32.7 139.5 224.0 25.9 104.5 210.7 23.1 69.5 199.5) ;;
    front) anchors=(42.1 147.3 222.9 33.1 113.0 208.0 30.7 87.9 198.3) ;;
    right-profile) anchors=(29.7 144.1 229.0 22.1 102.1 215.3 20.5 74.4 208.8) ;;
    *) print -r -- "null"; return ;;
  esac

  # 目标锚点略低于直接统计均值，用于抵消曲线处理后高亮/棕毛像素重新分组造成的
  # 亮度回升。输出复测会落在 left-profile 的可见范围内，而不是只让输入均值相等。
  local red green blue
  red="$(image_curve_points "${anchors[1]}" "${anchors[2]}" "${anchors[3]}" 25 82 175)"
  green="$(image_curve_points "${anchors[4]}" "${anchors[5]}" "${anchors[6]}" 22 55 158)"
  blue="$(image_curve_points "${anchors[7]}" "${anchors[8]}" "${anchors[9]}" 23 50 161)"
  print -r -- "curves=interp=pchip:r='$red':g='$green':b='$blue'"
}

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
  color_grade="$(image_color_filter "$keyframe_name")"
  ffmpeg -y -v warning \
    -loop 1 -framerate "$TARGET_FPS" -t 1.00 -i "$KEYFRAME_DIR/$keyframe_name.png" \
    -vf "format=rgba,$color_grade,scale=1280:720:flags=lanczos+accurate_rnd,format=bgra" -an \
    -c:v hevc_videotoolbox -alpha_quality 0.95 -q:v 75 -tag:v hvc1 \
    "$FACING_OUTPUT_DIR/$keyframe_name.mov"
done

grade_left="$(image_color_filter left-profile)"
grade_near_profile_left="$(image_color_filter front-near-profile-left)"
grade_three_quarter_left="$(image_color_filter front-three-quarter-left)"
grade_near_center_left="$(image_color_filter front-near-center-left)"
grade_front="$(image_color_filter front)"
grade_near_center_right="$(image_color_filter front-near-center-right)"
grade_three_quarter_right="$(image_color_filter front-three-quarter-right)"
grade_near_profile_right="$(image_color_filter front-near-profile-right)"
grade_right="$(image_color_filter right-profile)"

# 这不是 AI 视频生成：只把 9 张透明 PNG 按角度排序，并用 0.07 秒短淡化
# 组成一次往返转身。首尾都使用 stand-idle 的左侧面端口，因此运行时可以平稳接回待机。
ffmpeg -y -v warning \
  -loop 1 -framerate "$TARGET_FPS" -t 0.36 -i "$KEYFRAME_DIR/left-profile.png" \
  -loop 1 -framerate "$TARGET_FPS" -t 0.20 -i "$KEYFRAME_DIR/front-near-profile-left.png" \
  -loop 1 -framerate "$TARGET_FPS" -t 0.20 -i "$KEYFRAME_DIR/front-three-quarter-left.png" \
  -loop 1 -framerate "$TARGET_FPS" -t 0.20 -i "$KEYFRAME_DIR/front-near-center-left.png" \
  -loop 1 -framerate "$TARGET_FPS" -t 0.55 -i "$KEYFRAME_DIR/front.png" \
  -loop 1 -framerate "$TARGET_FPS" -t 0.20 -i "$KEYFRAME_DIR/front-near-center-right.png" \
  -loop 1 -framerate "$TARGET_FPS" -t 0.20 -i "$KEYFRAME_DIR/front-three-quarter-right.png" \
  -loop 1 -framerate "$TARGET_FPS" -t 0.20 -i "$KEYFRAME_DIR/front-near-profile-right.png" \
  -loop 1 -framerate "$TARGET_FPS" -t 0.45 -i "$KEYFRAME_DIR/right-profile.png" \
  -loop 1 -framerate "$TARGET_FPS" -t 0.20 -i "$KEYFRAME_DIR/front-near-profile-right.png" \
  -loop 1 -framerate "$TARGET_FPS" -t 0.20 -i "$KEYFRAME_DIR/front-three-quarter-right.png" \
  -loop 1 -framerate "$TARGET_FPS" -t 0.20 -i "$KEYFRAME_DIR/front-near-center-right.png" \
  -loop 1 -framerate "$TARGET_FPS" -t 0.50 -i "$KEYFRAME_DIR/front.png" \
  -loop 1 -framerate "$TARGET_FPS" -t 0.20 -i "$KEYFRAME_DIR/front-near-center-left.png" \
  -loop 1 -framerate "$TARGET_FPS" -t 0.20 -i "$KEYFRAME_DIR/front-three-quarter-left.png" \
  -loop 1 -framerate "$TARGET_FPS" -t 0.20 -i "$KEYFRAME_DIR/front-near-profile-left.png" \
  -loop 1 -framerate "$TARGET_FPS" -t 0.36 -i "$KEYFRAME_DIR/left-profile.png" \
  -filter_complex "\
    [0:v]format=rgba,$grade_left,setpts=PTS-STARTPTS[k0];\
    [1:v]format=rgba,$grade_near_profile_left,setpts=PTS-STARTPTS[k1];\
    [2:v]format=rgba,$grade_three_quarter_left,setpts=PTS-STARTPTS[k2];\
    [3:v]format=rgba,$grade_near_center_left,setpts=PTS-STARTPTS[k3];\
    [4:v]format=rgba,$grade_front,setpts=PTS-STARTPTS[k4];\
    [5:v]format=rgba,$grade_near_center_right,setpts=PTS-STARTPTS[k5];\
    [6:v]format=rgba,$grade_three_quarter_right,setpts=PTS-STARTPTS[k6];\
    [7:v]format=rgba,$grade_near_profile_right,setpts=PTS-STARTPTS[k7];\
    [8:v]format=rgba,$grade_right,setpts=PTS-STARTPTS[k8];\
    [9:v]format=rgba,$grade_near_profile_right,setpts=PTS-STARTPTS[k9];\
    [10:v]format=rgba,$grade_three_quarter_right,setpts=PTS-STARTPTS[k10];\
    [11:v]format=rgba,$grade_near_center_right,setpts=PTS-STARTPTS[k11];\
    [12:v]format=rgba,$grade_front,setpts=PTS-STARTPTS[k12];\
    [13:v]format=rgba,$grade_near_center_left,setpts=PTS-STARTPTS[k13];\
    [14:v]format=rgba,$grade_three_quarter_left,setpts=PTS-STARTPTS[k14];\
    [15:v]format=rgba,$grade_near_profile_left,setpts=PTS-STARTPTS[k15];\
    [16:v]format=rgba,$grade_left,setpts=PTS-STARTPTS[k16];\
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
    fps=$TARGET_FPS,scale=1280:720:flags=lanczos+accurate_rnd,format=bgra[out]" \
  -map "[out]" -an \
  -c:v hevc_videotoolbox -alpha_quality 0.95 -q:v 75 -tag:v hvc1 \
  "$OUTPUT_PATH"

print "图片转身 MVP 已写入：$OUTPUT_PATH"
print "鼠标朝向图片循环已写入：$FACING_OUTPUT_DIR"
