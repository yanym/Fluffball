#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
REPORT_PATH="$(mktemp /tmp/furball-behavior-qa.XXXXXX.json)"
LOG_PATH="$(mktemp /tmp/furball-behavior-qa.XXXXXX.log)"
PREFS_DIR="$(mktemp -d /tmp/furball-behavior-qa-prefs.XXXXXX)"
APP_PID=""
QA_APPEARANCE="${FURBALL_BEHAVIOR_QA_APPEARANCE:-realistic-2d}"

cleanup() {
  if [[ -n "$APP_PID" ]] && kill -0 "$APP_PID" 2>/dev/null; then
    kill "$APP_PID" 2>/dev/null || true
  fi
  rm -f "$REPORT_PATH" "$LOG_PATH"
  if [[ "$PREFS_DIR" == /tmp/furball-behavior-qa-prefs.* && -d "$PREFS_DIR" ]]; then
    rm -rf "$PREFS_DIR"
  fi
}
trap cleanup EXIT

cd "$PROJECT_DIR"
swift build >/dev/null
BIN_PATH="$(swift build --show-bin-path)/Furball"

env \
  CFFIXED_USER_HOME="$PREFS_DIR" \
  FURBALL_APPEARANCE="$QA_APPEARANCE" \
  FURBALL_BEHAVIOR_QA_REPORT="$REPORT_PATH" \
  FURBALL_BEHAVIOR_QA_EXIT=1 \
  FURBALL_DESKTOP_INTERACTION_DRY_RUN=1 \
  "$BIN_PATH" >"$LOG_PATH" 2>&1 &
APP_PID=$!

for _ in {1..100}; do
  if [[ -s "$REPORT_PATH" ]]; then
    break
  fi
  if ! kill -0 "$APP_PID" 2>/dev/null; then
    break
  fi
  sleep 0.25
done

if [[ ! -s "$REPORT_PATH" ]]; then
  print -u2 "Behavior QA did not produce a report."
  sed -n '1,120p' "$LOG_PATH" >&2
  exit 1
fi

sed -n '1,160p' "$REPORT_PATH"
if ! grep -Eq '"pass"[[:space:]]*:[[:space:]]*true' "$REPORT_PATH"; then
  print -u2 "Behavior QA failed."
  exit 1
fi

print "Behavior QA passed ($QA_APPEARANCE): the pet reached the treat, consumed it, stopped moving, and remained visible."
