#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
SOURCE_DIR="$PROJECT_DIR/Assets/Pets/Nina/UserProvided/SourceVideos/left-profile"
OUTPUT_DIR="$PROJECT_DIR/Sources/Furball2D/Assets/Pets/Nina/Clips/left-profile"

if ! command -v ffmpeg >/dev/null 2>&1 || ! command -v ffprobe >/dev/null 2>&1; then
  print -u2 "FFmpeg is required (brew install ffmpeg)."
  exit 1
fi

mkdir -p "$OUTPUT_DIR"

# Continuous animation exports at 1280×720 and 120 fps to match window movement on ProMotion.
# The original AI footage is 24 fps. Motion interpolation must run before keying while the
# background is stable and silhouettes are complete, preventing optical-flow holes in fur alpha.
# A 0.10-second cloned tail supplies future frames for bidirectional flow and is trimmed afterward.
TARGET_WIDTH=1280
TARGET_HEIGHT=720
TARGET_FPS=120
SOURCE_CLEANUP="delogo=x=1122:y=538:w=96:h=96"
FINISH_FILTERS="chromakey=0x3f985b:0.075:0.025,despill=green:mix=0.30:expand=0.05,unsharp=5:5:0.25:3:3:0,scale=${TARGET_WIDTH}:${TARGET_HEIGHT}:flags=lanczos+accurate_rnd,format=bgra"
ENCODE_OPTIONS=(-an -c:v hevc_videotoolbox -alpha_quality 0.98 -q:v 82 -tag:v hvc1)

motion_interpolation_filter() {
  local duration="$1"
  print -r -- "tpad=stop_mode=clone:stop_duration=0.10,minterpolate=fps=$TARGET_FPS:mi_mode=mci:mc_mode=aobmc:me_mode=bidir:vsbmc=1,trim=duration=$duration,setpts=PTS-STARTPTS"
}

# Locomotion footage came from a warmer, brighter generation batch. These curves use stand-idle
# black, tan, and white fur statistics as anchors after keying. One fixed curve per source keeps
# start, loop, and stop color-stable.
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

# Apply uniform scale and translation on a transparent 1600×900 work canvas, then crop to
# 1280×720. This supports enlargement and reduction without pad failures. Interpolate q, dx,
# and dy with smoothstep so correction does not introduce a velocity discontinuity.
stabilize_filter() {
  local base_width="$1"
  local base_height="$2"
  local timeline_duration="$3"
  local q0="$4"
  local q1="$5"
  local dx0="$6"
  local dx1="$7"
  local dy0="$8"
  local dy1="$9"
  local progress="min(1,max(0,t/$timeline_duration))"
  local eased="($progress*$progress*(3-2*$progress))"
  local q="($q0+($q1-$q0)*$eased)"
  # pad does not expose frame n. Its iw already reflects per-frame scaling, so iw/base_width
  # reconstructs the eased progress and keeps scale and translation synchronized.
  local inferred_eased="((iw/$base_width-$q0)/($q1-$q0))"
  local dx="($dx0+($dx1-$dx0)*$inferred_eased)"
  local dy="($dy0+($dy1-$dy0)*$inferred_eased)"

  print -r -- "scale=w='$base_width*$q':h='$base_height*$q':eval=frame,pad=1600:900:x='160+(1280-iw)/2+$dx':y='90+(720-ih)/2+$dy':eval=frame:color=black@0,crop=1280:720:160:90"
}

segment_last_frame_index() {
  local source_path="$1"
  local duration="$2"
  local frame_rate
  frame_rate="$TARGET_FPS/1"
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
  local interpolate

  if [[ ! -f "$source_path" ]]; then
    print -u2 "Missing asset: $source_path"
    exit 1
  fi

  interpolate="$(motion_interpolation_filter "$duration")"
  print "Building 120 fps HD action $source_name [$start_time + $duration] → $output_name.mov"
  ffmpeg -y -v warning -ss "$start_time" -t "$duration" -i "$source_path" \
    -vf "$SOURCE_CLEANUP,$interpolate,$FINISH_FILTERS" \
    "${ENCODE_OPTIONS[@]}" \
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
  local interpolate

  if [[ ! -f "$source_path" ]]; then
    print -u2 "Missing asset: $source_path"
    exit 1
  fi

  normalize="$(stabilize_filter 1280 720 "$duration" "$q0" "$q1" "$dx0" "$dx1" "$dy0" "$dy1")"
  interpolate="$(motion_interpolation_filter "$duration")"
  print "Building port-stabilized action $source_name [$start_time + $duration] → $output_name.mov"
  ffmpeg -y -v warning -ss "$start_time" -t "$duration" -i "$source_path" \
    -vf "$SOURCE_CLEANUP,$interpolate,chromakey=0x3f985b:0.075:0.025,despill=green:mix=0.30:expand=0.05,unsharp=5:5:0.25:3:3:0,format=rgba,$normalize,scale=${TARGET_WIDTH}:${TARGET_HEIGHT}:flags=lanczos+accurate_rnd,format=bgra" \
    "${ENCODE_OPTIONS[@]}" \
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
  local interpolate

  if [[ ! -f "$source_path" ]]; then
    print -u2 "Missing asset: $source_path"
    exit 1
  fi
  last_frame_index="$(segment_last_frame_index "$source_path" "$duration")"
  interpolate="$(motion_interpolation_filter "$duration")"

  # Typical AI clips do not share the same first and last pose. Low-motion idle can use a
  # de-duplicated forward/reverse loop to preserve motion without a periodic jump.
  print "Building seamless idle loop $source_name → $output_name.mov"
  ffmpeg -y -v warning -ss "$start_time" -t "$duration" -i "$source_path" \
    -filter_complex "[0:v]$SOURCE_CLEANUP,$interpolate,$FINISH_FILTERS,split=2[forward][backward];[forward]setpts=PTS-STARTPTS[f];[backward]reverse,trim=start_frame=1:end_frame=$last_frame_index,setpts=PTS-STARTPTS[r];[f][r]concat=n=2:v=1:a=0,fps=${TARGET_FPS}[out]" \
    -map "[out]" "${ENCODE_OPTIONS[@]}" \
    "$output_path"
}

compile_sleep_loop() {
  local source_path="$SOURCE_DIR/sleep-idle.mp4"
  local output_path="$OUTPUT_DIR/sleep-idle.mov"
  local last_frame_index
  local interpolate

  if [[ ! -f "$source_path" ]]; then
    print -u2 "Missing asset: $source_path"
    exit 1
  fi
  last_frame_index="$(segment_last_frame_index "$source_path" "0.55")"
  interpolate="$(motion_interpolation_filter "0.55")"

  print "Building low-motion sleep breathing loop → sleep-idle.mov"
  # Keep the calmest 0.55 seconds, slow it 2.5×, and remove repeated endpoints from reverse.
  # Each cycle retains subtle breathing without repeated tail sweeps or posture changes.
  ffmpeg -y -v warning -ss "0.50" -t "0.55" -i "$source_path" \
    -filter_complex "[0:v]$SOURCE_CLEANUP,$interpolate,$FINISH_FILTERS,split=2[forward][backward];[forward]setpts=2.5*(PTS-STARTPTS)[f];[backward]reverse,trim=start_frame=1:end_frame=$last_frame_index,setpts=2.5*(PTS-STARTPTS)[r];[f][r]concat=n=2:v=1:a=0,fps=${TARGET_FPS}[out]" \
    -map "[out]" "${ENCODE_OPTIONS[@]}" \
    "$output_path"
}

compile_sleep_to_stand() {
  local source_path="$SOURCE_DIR/sleep-to-stand.mp4"
  local output_path="$OUTPUT_DIR/sleep-to-stand.mov"
  local interpolate

  if [[ ! -f "$source_path" ]]; then
    print -u2 "Missing asset: $source_path"
    exit 1
  fi

  # The source pushes in during waking and ends about 6% larger. Smoothstep scale correction
  # plus foot-anchored translation matches the final frame to stand-idle size and placement.
  local normalize="scale=w='iw*(1-0.057*(3*min(1,t/4.60)^2-2*min(1,t/4.60)^3))':h='ih*(1-0.057*(3*min(1,t/4.60)^2-2*min(1,t/4.60)^3))':eval=frame,pad=1280:720:x='(ow-iw)/2+25*((1280-iw)/(1280*0.057))':y='oh-ih-12*((720-ih)/(720*0.057))':eval=frame:color=0x3f985b"
  interpolate="$(motion_interpolation_filter "4.60")"

  print "Building and normalizing wake-up scale → sleep-to-stand.mov"
  ffmpeg -y -v warning -ss "0.00" -t "4.60" -i "$source_path" \
    -vf "$SOURCE_CLEANUP,$interpolate,$normalize,$FINISH_FILTERS" \
    "${ENCODE_OPTIONS[@]}" \
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
  local repetitions="${13:-1}"
  local source_path="$SOURCE_DIR/$source_name"
  local output_path="$OUTPUT_DIR/$output_name.mov"
  local normalize
  local interpolate
  local color_grade
  local loop_filter=""

  if [[ ! -f "$source_path" ]]; then
    print -u2 "Missing locomotion source: $source_path"
    exit 1
  fi

  # Locomotion standing ports are roughly 8% larger and 18 px lower than stand-idle, with
  # source-specific drift. Give each segment independent endpoint q/dx/dy correction and
  # normalize loop ends to one height, center, and foot baseline. Never reverse locomotion;
  # trim loops to matching contact phases.
  normalize="$(stabilize_filter 1190 670 "$duration" "$q0" "$q1" "$dx0" "$dx1" "$dy0" "$dy1")"
  color_grade="$(motion_color_filter "$source_name")"
  interpolate="$(motion_interpolation_filter "$duration")"
  if (( repetitions > 1 )); then
    local interpolated_frame_count
    interpolated_frame_count="$(awk -v seconds="$duration" -v fps="$TARGET_FPS" 'BEGIN { print int(seconds * fps + 0.5) }')"
    loop_filter=",loop=loop=$((repetitions - 1)):size=${interpolated_frame_count}:start=0,setpts=N/${TARGET_FPS}/TB"
  fi
  local motion_filters="$SOURCE_CLEANUP,$interpolate,chromakey=$key_color:0.078:0.025,despill=green:mix=0.32:expand=0.05,format=rgba,$color_grade,unsharp=5:5:0.25:3:3:0,$normalize,scale=${TARGET_WIDTH}:${TARGET_HEIGHT}:flags=lanczos+accurate_rnd,format=bgra$loop_filter"

  print "Building locomotion $source_name [$start_time + $duration] → $output_name.mov"
  ffmpeg -y -v warning -ss "$start_time" -t "$duration" -i "$source_path" \
    -vf "$motion_filters" \
    "${ENCODE_OPTIONS[@]}" \
    "$output_path"
}

if [[ "${FURBALL_LOCOMOTION_LOOPS_ONLY:-0}" == "1" ]]; then
  compile_motion_segment "stand-to-walk-to-stand.mp4" "walk-loop" "4.125000" "1.208333" "0x549a44" 29 \
    "0.930000" "0.934504" "8.637" "8.296" "26.707" "26.578" 8
  compile_motion_segment "stand-to-slow-run-to-stand.mp4" "slow-run-loop" "4.083333" "1.291667" "0x509b3e" 31 \
    "0.930000" "0.942602" "24.013" "-4.818" "31.667" "32.913" 8
  compile_motion_segment "stand-to-fast-run-to-stand.mp4" "fast-run-loop" "2.750000" "0.583333" "0x539648" 14 \
    "0.930000" "0.889771" "-7.111" "-13.671" "42.827" "52.040" 16
  print "Rebuilt the three long, phase-closed locomotion loop items."
  exit 0
fi

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

# Every locomotion source contains stand → move → stand. Split each into start, phase-closed
# loop, and stop. Measured loops: walk frames 99–128 (~1.208 s), slow-run frames 98–129
# (~1.292 s), and fast-run frames 66–80 (~0.583 s).
compile_motion_segment "stand-to-walk-to-stand.mp4" "walk-start" "0.200000" "3.925000" "0x549a44" 94 \
  "0.929752" "0.934504" "-12.060" "8.919" "0.749" "25.332"
compile_motion_segment "stand-to-walk-to-stand.mp4" "walk-loop" "4.125000" "1.208333" "0x549a44" 29 \
  "0.930000" "0.934504" "8.637" "8.296" "26.707" "26.578" 8
compile_motion_segment "stand-to-walk-to-stand.mp4" "walk-stop" "5.333333" "3.166667" "0x549a44" 76 \
  "0.927764" "1.032110" "9.920" "-5.845" "28.626" "5.162"

compile_motion_segment "stand-to-slow-run-to-stand.mp4" "slow-run-start" "0.125000" "3.958333" "0x509b3e" 95 \
  "0.925926" "0.942602" "-12.514" "25.974" "0.790" "27.886"
compile_motion_segment "stand-to-slow-run-to-stand.mp4" "slow-run-loop" "4.083333" "1.291667" "0x509b3e" 31 \
  "0.930000" "0.942602" "24.013" "-4.818" "31.667" "32.913" 8
compile_motion_segment "stand-to-slow-run-to-stand.mp4" "slow-run-stop" "5.375000" "3.125000" "0x509b3e" 75 \
  "0.937520" "0.961538" "-6.642" "-9.703" "34.411" "5.538"

compile_motion_segment "stand-to-fast-run-to-stand.mp4" "fast-run-start" "0.250000" "2.500000" "0x539648" 60 \
  "0.929752" "0.861281" "-11.936" "-4.421" "0.749" "55.728"
compile_motion_segment "stand-to-fast-run-to-stand.mp4" "fast-run-loop" "2.750000" "0.583333" "0x539648" 14 \
  "0.930000" "0.889771" "-7.111" "-13.671" "42.827" "52.040" 16
compile_motion_segment "stand-to-fast-run-to-stand.mp4" "fast-run-stop" "3.333333" "5.166667" "0x539648" 124 \
  "0.945081" "1.022727" "-12.716" "2.779" "35.963" "-9.788"

"$SCRIPT_DIR/build-image-turn-mvp.sh"

print "Wrote transparent assets to: $OUTPUT_DIR"
