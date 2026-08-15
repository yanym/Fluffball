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

# 移动素材来自另一批生成视频，原始白毛和棕毛明显偏暖、偏亮。以下曲线用
# stand-idle 的黑毛、棕毛和白毛统计值作为三个锚点，在抠像后统一色温与明度。
# 每种移动源片使用一条固定曲线，保证 start / loop / stop 内部不会发生色漂。
color_curve_points() {
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

motion_color_filter() {
  local source_name="$1"
  local -a anchors
  case "$source_name" in
    stand-to-walk-to-stand.mp4)
      anchors=(32.2 142.3 207.6 24.7 103.7 180.4 23.1 91.0 177.2)
      ;;
    stand-to-slow-run-to-stand.mp4)
      anchors=(31.1 137.8 209.2 23.6 99.6 182.8 21.9 86.7 180.2)
      ;;
    stand-to-fast-run-to-stand.mp4)
      anchors=(28.8 137.1 211.1 22.2 94.8 184.6 20.9 79.8 182.0)
      ;;
    *)
      print -r -- "null"
      return
      ;;
  esac

  local red green blue
  red="$(color_curve_points "${anchors[1]}" "${anchors[2]}" "${anchors[3]}" 30 112 181)"
  green="$(color_curve_points "${anchors[4]}" "${anchors[5]}" "${anchors[6]}" 26 78 164)"
  blue="$(color_curve_points "${anchors[7]}" "${anchors[8]}" "${anchors[9]}" 27 67 166)"
  print -r -- "curves=interp=pchip:r='$red':g='$green':b='$blue'"
}

# 在透明的 1600×900 工作画布上做等比缩放和位移，再裁回 1280×720。
# 这样既支持缩小，也支持放大，不会因为 pad 目标小于动态输入而失败。
# q / dx / dy 在片段首尾之间使用 smoothstep，避免校正本身造成速度突变。
stabilize_filter() {
  local base_width="$1"
  local base_height="$2"
  local frame_count="$3"
  local q0="$4"
  local q1="$5"
  local dx0="$6"
  local dx1="$7"
  local dy0="$8"
  local dy1="$9"
  local last_frame=$((frame_count - 1))
  local progress="(n/$last_frame)"
  local eased="($progress*$progress*(3-2*$progress))"
  local q="($q0+($q1-$q0)*$eased)"
  # pad 不暴露帧号 n；它收到的 iw 已经是逐帧 scale 后的宽度，因此可由
  # iw/base_width 反推出同一个 eased 进度，保证缩放和位移严格同步。
  local inferred_eased="((iw/$base_width-$q0)/($q1-$q0))"
  local dx="($dx0+($dx1-$dx0)*$inferred_eased)"
  local dy="($dy0+($dy1-$dy0)*$inferred_eased)"

  print -r -- "scale=w='$base_width*$q':h='$base_height*$q':eval=frame,pad=1600:900:x='160+(1280-iw)/2+$dx':y='90+(720-ih)/2+$dy':eval=frame:color=black@0,crop=1280:720:160:90"
}

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

compile_stabilized_clip() {
  local source_name="$1"
  local output_name="$2"
  local start_time="$3"
  local duration="$4"
  local frame_count="$5"
  local q0="$6"
  local q1="$7"
  local dx0="$8"
  local dx1="$9"
  local dy0="${10}"
  local dy1="${11}"
  local source_path="$SOURCE_DIR/$source_name"
  local output_path="$OUTPUT_DIR/$output_name.mov"
  local normalize
  local color_grade

  if [[ ! -f "$source_path" ]]; then
    print -u2 "缺少素材：$source_path"
    exit 1
  fi

  normalize="$(stabilize_filter 1280 720 "$frame_count" "$q0" "$q1" "$dx0" "$dx1" "$dy0" "$dy1")"
  print "编译端口稳定动作 $source_name [$start_time + $duration] → $output_name.mov"
  ffmpeg -y -v warning -ss "$start_time" -t "$duration" -i "$source_path" \
    -vf "$SOURCE_CLEANUP,chromakey=0x3f985b:0.075:0.025,despill=green:mix=0.30:expand=0.05,unsharp=5:5:0.25:3:3:0,format=rgba,$normalize,scale=960:540:flags=lanczos+accurate_rnd,fps=24,format=bgra" \
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
  local frame_count="$6"
  local q0="$7"
  local q1="$8"
  local dx0="$9"
  local dx1="${10}"
  local dy0="${11}"
  local dy1="${12}"
  local source_path="$SOURCE_DIR/$source_name"
  local output_path="$OUTPUT_DIR/$output_name.mov"
  local normalize

  if [[ ! -f "$source_path" ]]; then
    print -u2 "缺少移动素材：$source_path"
    exit 1
  fi

  # 移动原片的站立端口比 stand-idle 大约 8%，脚底低约 18 px，且三个
  # 原片在跑动期间各有不同程度的横向/纵向漂移。每一段都使用独立的
  # 首末 q/dx/dy 校正；循环段的两端被归一到同一高度、中心和脚底基线。
  # 走路/跑步是方向性动作，循环段只取相同落脚相位，绝不使用倒放。
  normalize="$(stabilize_filter 1190 670 "$frame_count" "$q0" "$q1" "$dx0" "$dx1" "$dy0" "$dy1")"
  color_grade="$(motion_color_filter "$source_name")"
  local motion_filters="$SOURCE_CLEANUP,chromakey=$key_color:0.078:0.025,despill=green:mix=0.32:expand=0.05,format=rgba,$color_grade,unsharp=5:5:0.25:3:3:0,$normalize,scale=960:540:flags=lanczos+accurate_rnd,fps=24,format=bgra"

  print "编译移动动作 $source_name [$start_time + $duration] → $output_name.mov"
  ffmpeg -y -v warning -ss "$start_time" -t "$duration" -i "$source_path" \
    -vf "$motion_filters" \
    -an -c:v hevc_videotoolbox -alpha_quality 0.84 -q:v 62 -tag:v hvc1 \
    "$output_path"
}

compile_pingpong_idle "stand-idle.mp4" "stand-idle" "0.20" "9.40"
compile_clip "stand-to-sit.mp4" "stand-to-sit" "0.00" "3.20"
compile_pingpong_idle "sit-to-lie.mp4" "sit-idle" "0.00" "3.30"
compile_stabilized_clip "sit-to-lie.mp4" "sit-to-lie" "3.10" "6.50" 156 \
  "0.982533" "1.134557" "-0.153" "28.150" "4.186" "-42.084"
compile_pingpong_idle "lie-to-sleep.mp4" "lie-idle" "0.00" "3.90"
compile_stabilized_clip "lie-to-sleep.mp4" "lie-to-sleep" "3.70" "5.90" 142 \
  "0.997312" "1.055000" "2.420" "7.700" "0.871" "-22.040"
compile_sleep_loop
compile_sleep_to_stand

# 新移动素材均包含“站立 → 移动 → 站立”。每段拆成起步、相位闭合循环、停步：
# walk loop:    frame 99  → 128（约 1.208 s）
# slow-run loop: frame 98  → 129（约 1.292 s）
# fast-run loop: frame 66  → 80 （约 0.583 s）
compile_motion_segment "stand-to-walk-to-stand.mp4" "walk-start" "0.000000" "4.125000" "0x549a44" 99 \
  "0.929752" "0.934504" "-12.060" "8.919" "0.749" "25.332"
compile_motion_segment "stand-to-walk-to-stand.mp4" "walk-loop" "4.125000" "1.208333" "0x549a44" 29 \
  "0.930000" "0.934504" "8.637" "8.296" "26.707" "26.578"
compile_motion_segment "stand-to-walk-to-stand.mp4" "walk-stop" "5.333333" "3.166667" "0x549a44" 76 \
  "0.927764" "1.032110" "9.920" "-5.845" "28.626" "5.162"

compile_motion_segment "stand-to-slow-run-to-stand.mp4" "slow-run-start" "0.000000" "4.083333" "0x509b3e" 98 \
  "0.925926" "0.942602" "-12.514" "25.974" "0.790" "27.886"
compile_motion_segment "stand-to-slow-run-to-stand.mp4" "slow-run-loop" "4.083333" "1.291667" "0x509b3e" 31 \
  "0.930000" "0.942602" "24.013" "-4.818" "31.667" "32.913"
compile_motion_segment "stand-to-slow-run-to-stand.mp4" "slow-run-stop" "5.375000" "3.125000" "0x509b3e" 75 \
  "0.937520" "0.961538" "-6.642" "-9.703" "34.411" "5.538"

compile_motion_segment "stand-to-fast-run-to-stand.mp4" "fast-run-start" "0.000000" "2.750000" "0x539648" 66 \
  "0.929752" "0.861281" "-11.936" "-4.421" "0.749" "55.728"
compile_motion_segment "stand-to-fast-run-to-stand.mp4" "fast-run-loop" "2.750000" "0.583333" "0x539648" 14 \
  "0.930000" "0.889771" "-7.111" "-13.671" "42.827" "52.040"
compile_motion_segment "stand-to-fast-run-to-stand.mp4" "fast-run-stop" "3.333333" "5.166667" "0x539648" 124 \
  "0.945081" "1.022727" "-12.716" "2.779" "35.963" "-9.788"

"$SCRIPT_DIR/build-image-turn-mvp.sh"

print "透明素材已写入：$OUTPUT_DIR"
