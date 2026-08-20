#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
QA_DIR="$(mktemp -d /tmp/furball-live-motion-qa.XXXXXX)"
REPORT_PATH="$QA_DIR/report.json"
LOG_PATH="$QA_DIR/run.log"
PREFS_DIR="$QA_DIR/preferences"
APP_PID=""

mkdir -p "$PREFS_DIR"

cleanup() {
  if [[ -n "$APP_PID" ]] && kill -0 "$APP_PID" 2>/dev/null; then
    kill "$APP_PID" 2>/dev/null || true
  fi
  if [[ "$QA_DIR" == /tmp/furball-live-motion-qa.* && -d "$QA_DIR" ]]; then
    rm -rf "$QA_DIR"
  fi
}
trap cleanup EXIT

cd "$PROJECT_DIR"
swift build -j 1 >/dev/null
BIN_PATH="$(swift build --show-bin-path)/Furball"

env \
  CFFIXED_USER_HOME="$PREFS_DIR" \
  FURBALL_APPEARANCE=continuous-video \
  FURBALL_LIVE_MOTION_QA_REPORT="$REPORT_PATH" \
  FURBALL_LIVE_MOTION_QA_EXIT=1 \
  "$BIN_PATH" >"$LOG_PATH" 2>&1 &
APP_PID=$!

for _ in {1..60}; do
  if [[ -s "$REPORT_PATH" ]]; then
    break
  fi
  if ! kill -0 "$APP_PID" 2>/dev/null; then
    break
  fi
  sleep 0.25
done

if [[ ! -s "$REPORT_PATH" ]]; then
  print -u2 "Live Motion QA did not produce a report."
  sed -n '1,160p' "$LOG_PATH" >&2
  exit 1
fi

sed -n '1,180p' "$REPORT_PATH"
if ! grep -Eq '"pass"[[:space:]]*:[[:space:]]*true' "$REPORT_PATH"; then
  print -u2 "Live Motion QA failed."
  exit 1
fi

print "Live Motion QA passed: Nina reached fast run and sustained smooth decoded motion while crossing the desktop."
