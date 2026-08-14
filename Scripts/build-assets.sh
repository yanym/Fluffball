#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
SOURCE_DIR="$PROJECT_DIR/Assets/SourceVideos/left-profile"
OUTPUT_DIR="$PROJECT_DIR/Sources/Furball2D/Assets/Clips/left-profile"

if ! command -v ffmpeg >/dev/null 2>&1 || ! command -v ffprobe >/dev/null 2>&1; then
  print -u2 "需要先安装 FFmpeg（brew install ffmpeg）。"
  exit 1
fi

mkdir -p "$OUTPUT_DIR"

# 素材统一在抠像完成后以 Lanczos 缩放至 960×540。比旧版 640×360 多 2.25 倍像素，
# 并收紧 chromakey 的 softness，避免毛发边缘被过度侵蚀。
SOURCE_CLEANUP="delogo=x=1122:y=538:w=96:h=96"
FINISH_FILTERS="chromakey=0x3f985b:0.075:0.025,despill=green:mix=0.30:expand=0.05,unsharp=5:5:0.25:3:3:0,scale=960:540:flags=lanczos+accurate_rnd,format=bgra"

segment_last_frame_index() {
  local source_path="$1"
  local duration="$2"
  local frame_rate
  frame_rate="$(ffprobe -v error -select_streams v:0 -show_entries stream=avg_frame_rate -of default=nw=1:nk=1 "$source_path")"
  awk -v seconds="$duration" -v rate="$frame_rate" 'BEGIN {
    split(rate, parts, "/")
    fps = parts[1] / parts[2]
    frameCount = int(seconds * fps + 0.999999)
    print frameCount - 1
  }'
}

compile_clip() {
  local source_name="$1"
  local output_name="$2"
  local start_time="$3"
  local duration="$4"
  local source_path="$SOURCE_DIR/$source_name"
  local output_path="$OUTPUT_DIR/$output_name.mov"

  if [[ ! -f "$source_path" ]]; then
    print -u2 "缺少素材：$source_path"
    exit 1
  fi

  print "编译 $source_name [$start_time + $duration] → $output_name.mov"
  ffmpeg -y -v warning -ss "$start_time" -t "$duration" -i "$source_path" \
    -vf "$SOURCE_CLEANUP,$FINISH_FILTERS" \
    -an -c:v hevc_videotoolbox -alpha_quality 0.84 -q:v 62 -tag:v hvc1 \
    "$output_path"
}

compile_pingpong_idle() {
  local source_name="$1"
  local output_name="$2"
  local start_time="$3"
  local duration="$4"
  local source_path="$SOURCE_DIR/$source_name"
  local output_path="$OUTPUT_DIR/$output_name.mov"
  local last_frame_index

  if [[ ! -f "$source_path" ]]; then
    print -u2 "缺少素材：$source_path"
    exit 1
  fi
  last_frame_index="$(segment_last_frame_index "$source_path" "$duration")"

  # 普通 AI 视频的首尾不是同一姿态，直接 AVQueuePlayer 循环会每隔几秒轻跳一次。
  # 待机动作幅度很小，使用首尾去重的正放/倒放能保留动作且保证位置连续。
  print "编译无跳点待机循环 $source_name → $output_name.mov"
  ffmpeg -y -v warning -ss "$start_time" -t "$duration" -i "$source_path" \
    -filter_complex "[0:v]$SOURCE_CLEANUP,$FINISH_FILTERS,split=2[forward][backward];[forward]setpts=PTS-STARTPTS[f];[backward]reverse,trim=start_frame=1:end_frame=$last_frame_index,setpts=PTS-STARTPTS[r];[f][r]concat=n=2:v=1:a=0,fps=24[out]" \
    -map "[out]" -an -c:v hevc_videotoolbox -alpha_quality 0.84 -q:v 62 -tag:v hvc1 \
    "$output_path"
}

compile_sleep_loop() {
  local source_path="$SOURCE_DIR/sleep-idle.mp4"
  local output_path="$OUTPUT_DIR/sleep-idle.mov"
  local last_frame_index

  if [[ ! -f "$source_path" ]]; then
    print -u2 "缺少素材：$source_path"
    exit 1
  fi
  last_frame_index="$(segment_last_frame_index "$source_path" "0.55")"

  print "编译低动作睡眠呼吸循环 → sleep-idle.mov"
  # 只取 0.55 秒最稳定的呼吸动作，并放慢 2.5 倍；倒放段去掉首尾重复帧。
  # 这样每轮约 2.5 秒，身体有轻微起伏，但不会反复甩尾或调整睡姿。
  ffmpeg -y -v warning -ss "0.50" -t "0.55" -i "$source_path" \
    -filter_complex "[0:v]$SOURCE_CLEANUP,$FINISH_FILTERS,split=2[forward][backward];[forward]setpts=2.5*(PTS-STARTPTS)[f];[backward]reverse,trim=start_frame=1:end_frame=$last_frame_index,setpts=2.5*(PTS-STARTPTS)[r];[f][r]concat=n=2:v=1:a=0,fps=24[out]" \
    -map "[out]" -an -c:v hevc_videotoolbox -alpha_quality 0.84 -q:v 62 -tag:v hvc1 \
    "$output_path"
}

compile_sleep_to_stand() {
  local source_path="$SOURCE_DIR/sleep-to-stand.mp4"
  local output_path="$OUTPUT_DIR/sleep-to-stand.mov"

  if [[ ! -f "$source_path" ]]; then
    print -u2 "缺少素材：$source_path"
    exit 1
  fi

  # 原片在起身过程中逐渐推近，末帧主体约大 6%。这里使用 smoothstep 渐变缩回，
  # 同时以脚底为锚点补偿横纵位置，使末帧和 stand-idle 的大小、落脚点一致。
  local normalize="scale=w='iw*(1-0.057*(3*(n/110)^2-2*(n/110)^3))':h='ih*(1-0.057*(3*(n/110)^2-2*(n/110)^3))':eval=frame,pad=1280:720:x='(ow-iw)/2+25*((1280-iw)/(1280*0.057))':y='oh-ih-12*((720-ih)/(720*0.057))':eval=frame:color=0x3f985b"

  print "编译并校正睡醒起身尺寸 → sleep-to-stand.mov"
  ffmpeg -y -v warning -ss "0.00" -t "4.60" -i "$source_path" \
    -vf "$SOURCE_CLEANUP,$normalize,$FINISH_FILTERS" \
    -an -c:v hevc_videotoolbox -alpha_quality 0.84 -q:v 62 -tag:v hvc1 \
    "$output_path"
}

compile_motion_segment() {
  local source_name="$1"
  local output_name="$2"
  local start_time="$3"
  local duration="$4"
  local key_color="$5"
  local source_path="$SOURCE_DIR/$source_name"
  local output_path="$OUTPUT_DIR/$output_name.mov"

  if [[ ! -f "$source_path" ]]; then
    print -u2 "缺少移动素材：$source_path"
    exit 1
  fi

  # 三段新移动素材的主体比现有 stand-idle 高约 7%。先按各自绿幕颜色抠像，
  # 再以透明画布中心缩至 93%，可让脚底基线和站立端口回到当前动作链附近。
  # 走路/跑步是方向性动作，循环段只取相同落脚相位，绝不使用倒放。
  local motion_filters="$SOURCE_CLEANUP,chromakey=$key_color:0.078:0.025,despill=green:mix=0.32:expand=0.05,unsharp=5:5:0.25:3:3:0,format=rgba,scale=1190:670:flags=lanczos+accurate_rnd,pad=1280:720:45:25:color=black@0,scale=960:540:flags=lanczos+accurate_rnd,fps=24,format=bgra"

  print "编译移动动作 $source_name [$start_time + $duration] → $output_name.mov"
  ffmpeg -y -v warning -ss "$start_time" -t "$duration" -i "$source_path" \
    -vf "$motion_filters" \
    -an -c:v hevc_videotoolbox -alpha_quality 0.84 -q:v 62 -tag:v hvc1 \
    "$output_path"
}

compile_pingpong_idle "stand-idle.mp4" "stand-idle" "0.20" "9.40"
compile_clip "stand-to-sit.mp4" "stand-to-sit" "0.00" "3.20"
compile_pingpong_idle "sit-to-lie.mp4" "sit-idle" "0.00" "3.30"
compile_clip "sit-to-lie.mp4" "sit-to-lie" "3.10" "6.50"
compile_pingpong_idle "lie-to-sleep.mp4" "lie-idle" "0.00" "3.90"
compile_clip "lie-to-sleep.mp4" "lie-to-sleep" "3.70" "5.90"
compile_sleep_loop
compile_sleep_to_stand

# 新移动素材均包含“站立 → 移动 → 站立”。每段拆成起步、相位闭合循环、停步：
# walk loop:    frame 99  → 128（约 1.208 s）
# slow-run loop: frame 98  → 129（约 1.292 s）
# fast-run loop: frame 66  → 80 （约 0.583 s）
compile_motion_segment "stand-to-walk-to-stand.mp4" "walk-start" "0.000000" "4.125000" "0x549a44"
compile_motion_segment "stand-to-walk-to-stand.mp4" "walk-loop" "4.125000" "1.208333" "0x549a44"
compile_motion_segment "stand-to-walk-to-stand.mp4" "walk-stop" "5.333333" "3.166667" "0x549a44"

compile_motion_segment "stand-to-slow-run-to-stand.mp4" "slow-run-start" "0.000000" "4.083333" "0x509b3e"
compile_motion_segment "stand-to-slow-run-to-stand.mp4" "slow-run-loop" "4.083333" "1.291667" "0x509b3e"
compile_motion_segment "stand-to-slow-run-to-stand.mp4" "slow-run-stop" "5.375000" "3.125000" "0x509b3e"

compile_motion_segment "stand-to-fast-run-to-stand.mp4" "fast-run-start" "0.000000" "2.750000" "0x539648"
compile_motion_segment "stand-to-fast-run-to-stand.mp4" "fast-run-loop" "2.750000" "0.583333" "0x539648"
compile_motion_segment "stand-to-fast-run-to-stand.mp4" "fast-run-stop" "3.333333" "5.166667" "0x539648"

print "透明素材已写入：$OUTPUT_DIR"
