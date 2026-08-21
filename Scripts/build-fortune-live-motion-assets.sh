#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
SOURCE_DIR="$PROJECT_DIR/Assets/Pets/Fortune/UserProvided/SourceVideos/right-profile"
PET_DIR="$PROJECT_DIR/Sources/Furball2D/Assets/Pets/Fortune"
OUTPUT_DIR="$PET_DIR/Clips/right-profile"
VIEW_DIR="$PET_DIR/Clips/image-views"
ATLAS_PATH="$PET_DIR/Sprites/Fortune/realistic/spritesheet.webp"
REQUESTED_OUTPUTS=("$@")

if ! command -v ffmpeg >/dev/null 2>&1 || ! command -v ffprobe >/dev/null 2>&1; then
  print -u2 "FFmpeg is required (brew install ffmpeg)."
  exit 1
fi

mkdir -p "$OUTPUT_DIR" "$VIEW_DIR"

TARGET_WIDTH=1280
TARGET_HEIGHT=720
TARGET_FPS=120
WORK_WIDTH=1600
WORK_HEIGHT=900
TARGET_CENTER_X=640
TARGET_GROUND_Y=682
ENCODE_OPTIONS=(-an -c:v hevc_videotoolbox -alpha_quality 0.98 -q:v 82 -tag:v hvc1)
INTERMEDIATE_OPTIONS=(-an -c:v prores_ks -profile:v 4 -pix_fmt yuva444p10le)
STABILIZER_BINARY="$(mktemp -u /tmp/furball-alpha-stabilizer.XXXXXX)"
WORK_DIR="$(mktemp -d /tmp/furball-fortune-live-motion.XXXXXX)"
trap 'rm -rf "$WORK_DIR"; rm -f "$STABILIZER_BINARY"' EXIT
swiftc -O -framework AVFoundation -framework CoreVideo \
  "$SCRIPT_DIR/measure-alpha-stabilization.swift" -o "$STABILIZER_BINARY"

should_build() {
  local candidate="$1"
  (( ${#REQUESTED_OUTPUTS[@]} == 0 )) && return 0
  local requested
  for requested in "${REQUESTED_OUTPUTS[@]}"; do
    [[ "$requested" == "$candidate" ]] && return 0
  done
  return 1
}

motion_interpolation_filter() {
  local duration="$1"
  print -r -- "tpad=stop_mode=clone:stop_duration=0.10,minterpolate=fps=$TARGET_FPS:mi_mode=mci:mc_mode=aobmc:me_mode=bidir:vsbmc=1,trim=duration=$duration,setpts=PTS-STARTPTS"
}

# Normalize a source segment on a larger transparent canvas. q, source center, and ground
# measurements interpolate with smoothstep so entry and exit ports reach the same runtime
# center and baseline without introducing a velocity discontinuity.
normalize_filter() {
  local duration="$1"
  local q0="$2"
  local q1="$3"
  local cx0="$4"
  local cx1="$5"
  local gy0="$6"
  local gy1="$7"
  local progress="min(1,max(0,t/$duration))"
  local eased="($progress*$progress*(3-2*$progress))"
  local q="($q0+($q1-$q0)*$eased)"
  local inferred="min(1,max(0,(iw/$TARGET_WIDTH-$q0)/($q1-$q0)))"
  local source_cx="($cx0+($cx1-$cx0)*$inferred)"
  local source_gy="($gy0+($gy1-$gy0)*$inferred)"
  local dx="($TARGET_CENTER_X-($TARGET_CENTER_X+($source_cx-$TARGET_CENTER_X)*(iw/$TARGET_WIDTH)))"
  local dy="($TARGET_GROUND_Y-($TARGET_HEIGHT/2+($source_gy-$TARGET_HEIGHT/2)*(ih/$TARGET_HEIGHT)))"

  print -r -- "scale=w='$TARGET_WIDTH*$q':h='$TARGET_HEIGHT*$q':eval=frame,pad=$WORK_WIDTH:$WORK_HEIGHT:x='160+($TARGET_WIDTH-iw)/2+$dx':y='90+($TARGET_HEIGHT-ih)/2+$dy':eval=frame:color=black@0,crop=$TARGET_WIDTH:$TARGET_HEIGHT:160:90"
}

segment_filters() {
  local source_name="$1"
  local duration="$2"
  local key_color="$3"
  local q0="$4"
  local q1="$5"
  local cx0="$6"
  local cx1="$7"
  local gy0="$8"
  local gy1="$9"
  local pre_key="null"
  local source_grade="null"
  local alpha_boost="1.04"
  local key_similarity="0.070"
  local key_softness="0.025"
  local common_grade="curves=all='0/0 0.09/0.16 0.25/0.37 0.50/0.63 0.75/0.86 1/1',eq=saturation=1.14"
  local interpolate
  local normalize

  # Gemini inserted a small duplicate dog in the upper-left of stand-to-sit. Mask only that
  # source strip in place. Cropping shifted the real subject 260 px and caused the old clip's
  # severe lateral jump.
  if [[ "$source_name" == "stand-to-sit.mp4" ]]; then
    pre_key="drawbox=x=0:y=0:w=260:h=720:color=0x${key_color}:t=fill"
  fi

  # A single monotonic display curve gives every generation batch the same lively reference.
  # Alpha correction is fixed per source (never per frame), so opacity cannot breathe inside
  # a clip. Walk and lie need stronger alpha restoration after their noisier magenta keys.
  case "$source_name" in
    stand-to-walk-to-stand.mp4)
      key_similarity="0.045"
      key_softness="0.018"
      alpha_boost="1.55"
      ;;
    lie-to-sleep.mp4)
      key_similarity="0.045"
      key_softness="0.018"
      alpha_boost="1.35"
      ;;
    sleep-idle.mp4)
      alpha_boost="1.12"
      ;;
    stand-to-fast-run-to-stand.mp4)
      key_similarity="0.045"
      key_softness="0.018"
      alpha_boost="1.30"
      ;;
    stand-to-slow-run-to-stand.mp4)
      key_similarity="0.045"
      key_softness="0.018"
      alpha_boost="1.30"
      ;;
  esac

  interpolate="$(motion_interpolation_filter "$duration")"
  normalize="$(normalize_filter "$duration" "$q0" "$q1" "$cx0" "$cx1" "$gy0" "$gy1")"
  print -r -- "$pre_key,$interpolate,chromakey=0x${key_color}:$key_similarity:$key_softness,format=rgba,huesaturation=colors=m:saturation=-0.72:strength=70:lightness=1,$source_grade,$common_grade,lut=a='min(255,val*$alpha_boost)',unsharp=5:5:0.22:3:3:0,$normalize,format=bgra"
}

stabilize_and_encode() {
  local intermediate="$1"
  local output="$2"
  local loop_flag="${3:-}"
  local commands="$WORK_DIR/$(basename "$output" .mov)-stabilize.txt"
  if [[ "$loop_flag" == "loop" ]]; then
    "$STABILIZER_BINARY" "$intermediate" "$commands" --loop
  else
    "$STABILIZER_BINARY" "$intermediate" "$commands"
  fi
  ffmpeg -y -v warning -i "$intermediate" \
    -vf "sendcmd=f='$commands',pad=2000:1200:360:240:color=black@0,crop@stabilize=1280:720:360:240,format=bgra" \
    "${ENCODE_OPTIONS[@]}" "$output"
}

compile_segment() {
  local source_name="$1"
  local output_name="$2"
  local start_time="$3"
  local duration="$4"
  local key_color="$5"
  local q0="$6"
  local q1="$7"
  local cx0="$8"
  local cx1="$9"
  local gy0="${10}"
  local gy1="${11}"
  local source_path="$SOURCE_DIR/$source_name"
  local output_path="$OUTPUT_DIR/$output_name.mov"
  local intermediate="$WORK_DIR/$output_name-prores.mov"
  local filters

  should_build "$output_name" || return 0

  [[ -f "$source_path" ]] || { print -u2 "Missing source: $source_path"; exit 1; }
  filters="$(segment_filters "$source_name" "$duration" "$key_color" "$q0" "$q1" "$cx0" "$cx1" "$gy0" "$gy1")"
  print "Building Fortune $output_name [$start_time + $duration]"
  ffmpeg -y -v warning -ss "$start_time" -t "$duration" -i "$source_path" \
    -vf "$filters" "${INTERMEDIATE_OPTIONS[@]}" "$intermediate"
  if [[ "$output_name" == *-loop ]]; then
    stabilize_and_encode "$intermediate" "$output_path" loop
  else
    stabilize_and_encode "$intermediate" "$output_path"
  fi
}

compile_pingpong() {
  local source_name="$1"
  local output_name="$2"
  local start_time="$3"
  local duration="$4"
  local key_color="$5"
  local q0="$6"
  local q1="$7"
  local cx0="$8"
  local cx1="$9"
  local gy0="${10}"
  local gy1="${11}"
  local source_path="$SOURCE_DIR/$source_name"
  local output_path="$OUTPUT_DIR/$output_name.mov"
  local intermediate="$WORK_DIR/$output_name-prores.mov"
  local filters
  local frame_count

  should_build "$output_name" || return 0

  [[ -f "$source_path" ]] || { print -u2 "Missing source: $source_path"; exit 1; }
  filters="$(segment_filters "$source_name" "$duration" "$key_color" "$q0" "$q1" "$cx0" "$cx1" "$gy0" "$gy1")"
  frame_count="$(awk -v d="$duration" -v fps="$TARGET_FPS" 'BEGIN { print int(d * fps + 0.5) }')"
  print "Building Fortune seamless idle $output_name [$start_time + $duration]"
  ffmpeg -y -v warning -ss "$start_time" -t "$duration" -i "$source_path" \
    -filter_complex "[0:v]$filters,split=2[forward][backward];[forward]setpts=PTS-STARTPTS[f];[backward]reverse,trim=start_frame=1:end_frame=$((frame_count - 1)),setpts=PTS-STARTPTS[r];[f][r]concat=n=2:v=1:a=0,fps=${TARGET_FPS}[out]" \
    -map "[out]" "${INTERMEDIATE_OPTIONS[@]}" "$intermediate"
  stabilize_and_encode "$intermediate" "$output_path" loop
}

build_image_view() {
  local name="$1"
  local row="$2"
  local column="$3"
  local x=$((column * 384))
  local y=$((row * 416))
  local output="$VIEW_DIR/$name.mov"
  (( ${#REQUESTED_OUTPUTS[@]} > 0 )) && return 0
  ffmpeg -y -v warning -loop 1 -framerate "$TARGET_FPS" -t 1.0 -i "$ATLAS_PATH" \
    -vf "crop=384:416:$x:$y,scale=772:836:flags=lanczos+accurate_rnd,format=rgba,pad=1280:1000:x=(ow-iw)/2:y=0:color=black@0,crop=1280:720:0:142,format=bgra" \
    -r "$TARGET_FPS" "${ENCODE_OPTIONS[@]}" "$output"
}

build_look_sequence() {
  local output="$OUTPUT_DIR/look-around-images.mov"
  (( ${#REQUESTED_OUTPUTS[@]} > 0 )) && return 0
  local cell_filter="scale=772:836:flags=lanczos+accurate_rnd,format=rgba,pad=1280:1000:x=(ow-iw)/2:y=0:color=black@0,crop=1280:720:0:142"
  # right profile → front → left profile, using the v2 atlas's clockwise direction rows.
  ffmpeg -y -v warning -loop 1 -framerate "$TARGET_FPS" -t 2.25 -i "$ATLAS_PATH" \
    -filter_complex "[0:v]split=9[s0][s1][s2][s3][s4][s5][s6][s7][s8];\
[s0]crop=384:416:1536:3744,$cell_filter,trim=duration=0.25,setpts=PTS-STARTPTS[v0];\
[s1]crop=384:416:1920:3744,$cell_filter,trim=duration=0.25,setpts=PTS-STARTPTS[v1];\
[s2]crop=384:416:2304:3744,$cell_filter,trim=duration=0.25,setpts=PTS-STARTPTS[v2];\
[s3]crop=384:416:2688:3744,$cell_filter,trim=duration=0.25,setpts=PTS-STARTPTS[v3];\
[s4]crop=384:416:0:4160,$cell_filter,trim=duration=0.25,setpts=PTS-STARTPTS[v4];\
[s5]crop=384:416:384:4160,$cell_filter,trim=duration=0.25,setpts=PTS-STARTPTS[v5];\
[s6]crop=384:416:768:4160,$cell_filter,trim=duration=0.25,setpts=PTS-STARTPTS[v6];\
[s7]crop=384:416:1152:4160,$cell_filter,trim=duration=0.25,setpts=PTS-STARTPTS[v7];\
[s8]crop=384:416:1536:4160,$cell_filter,trim=duration=0.25,setpts=PTS-STARTPTS[v8];\
[v0][v1][v2][v3][v4][v5][v6][v7][v8]concat=n=9:v=1:a=0,format=bgra[out]" \
    -map "[out]" -r "$TARGET_FPS" "${ENCODE_OPTIONS[@]}" "$output"
}

# Posture chain. Every transition enters and exits through independently measured ports.
compile_pingpong "stand-idle.mp4" "stand-idle" 0.40 8.80 bc5892 \
  1.000000 1.001000 643.5 639.0 682 682
compile_segment "stand-to-sit.mp4" "stand-to-sit" 0.20 3.20 b3568d \
  1.030000 1.010000 642.5 611.5 679 678
compile_pingpong "sit-to-lie.mp4" "sit-idle" 0.20 1.60 a14a88 \
  1.000000 1.001000 617.5 611.5 664 665
compile_segment "sit-to-lie.mp4" "sit-to-lie" 1.60 3.20 a14a88 \
  1.000000 1.080000 612.0 640.0 665 646
compile_pingpong "lie-to-sleep.mp4" "lie-idle" 0.20 2.00 943a61 \
  1.020000 1.021000 606.5 604.0 612 614
compile_segment "lie-to-sleep.mp4" "lie-to-sleep" 2.00 4.00 943a61 \
  1.020000 1.021000 604.0 628.0 614 612
compile_pingpong "sleep-idle.mp4" "sleep-idle" 0.50 6.70 a14a73 \
  0.972000 0.973000 639.0 640.5 632 633
compile_segment "sleep-to-stand.mp4" "sleep-to-stand" 0.20 6.50 a83794 \
  1.046000 1.022000 613.0 605.0 606 667

# Locomotion. Walk and slow-run use their authored start/loop/stop. The fast-run source's
# opening and closing direction changes are rejected; its clean right-facing middle supplies
# only the fast loop, while the compatible slow-run source provides physical acceleration and
# deceleration ports.
compile_segment "stand-to-walk-to-stand.mp4" "walk-start" 0.20 2.55 a04a6c \
  0.980000 0.981000 618.0 618.5 665 663
compile_segment "stand-to-walk-to-stand.mp4" "walk-loop" 2.750000 1.083333 a04a6c \
  0.980000 0.981000 618.5 627.5 663 664
compile_segment "stand-to-walk-to-stand.mp4" "walk-stop" 5.833333 1.666667 a04a6c \
  0.980000 0.981000 635.5 637.5 662 664

compile_segment "stand-to-slow-run-to-stand.mp4" "slow-run-start" 0.20 3.383333 ac4f7f \
  1.055000 1.056000 637.5 658.0 654 648
compile_segment "stand-to-slow-run-to-stand.mp4" "slow-run-loop" 3.583333 0.666667 ac4f7f \
  1.055000 1.056000 658.0 657.5 648 648
compile_segment "stand-to-slow-run-to-stand.mp4" "slow-run-stop" 5.541667 1.958333 ac4f7f \
  1.055000 1.056000 658.0 634.0 646 657

compile_segment "stand-to-slow-run-to-stand.mp4" "fast-run-start" 0.20 1.80 ac4f7f \
  1.055000 1.056000 637.5 655.0 654 649
compile_segment "stand-to-fast-run-to-stand.mp4" "fast-run-loop" 2.791667 0.541667 a44269 \
  1.020000 1.021000 730.0 727.0 637 636
compile_segment "stand-to-slow-run-to-stand.mp4" "fast-run-stop" 5.541667 1.958333 ac4f7f \
  1.055000 1.056000 658.0 634.0 646 657

build_image_view "right-profile" 9 4
build_image_view "front-near-profile-right" 9 5
build_image_view "front-three-quarter-right" 9 6
build_image_view "front-near-center-right" 9 7
build_image_view "front" 10 0
build_image_view "front-near-center-left" 10 1
build_image_view "front-three-quarter-left" 10 2
build_image_view "front-near-profile-left" 10 3
build_image_view "left-profile" 10 4
build_look_sequence

print "Wrote Fortune Live Motion assets to: $OUTPUT_DIR"
