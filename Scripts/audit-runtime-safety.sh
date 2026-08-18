#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
SOURCE_DIR="$PROJECT_DIR/Sources/Furball2D"

forbidden='NSAppleScript|osascript|CreateDesktop|desktop position|trashItem\(|removeItem\(|moveItem\(|replaceItemAt\(|copyItem\(|setAttributes\(|setResourceValue\('
if rg -n "$forbidden" "$SOURCE_DIR" -g '*.swift'; then
  print -u2 "Runtime safety audit failed: a user-file or Finder mutation API is reachable from app sources."
  exit 1
fi

if ! rg -q 'permitsUserFileMutations = false' "$SOURCE_DIR/RuntimeSafetyPolicy.swift"; then
  print -u2 "Runtime safety audit failed: the read-only product policy is missing."
  exit 1
fi

if ! rg -q 'reply\(toOpenOrPrint: \.failure\)' "$SOURCE_DIR/main.swift"; then
  print -u2 "Runtime safety audit failed: opening files must be rejected by the app."
  exit 1
fi

if rg -n 'Data\([^)]*contentsOf:.*\)\.write|FileHandle\(forWriting|createFile\(' "$SOURCE_DIR" -g '*.swift'; then
  print -u2 "Runtime safety audit failed: an unapproved general-purpose write path exists."
  exit 1
fi

print "Runtime safety audit passed: no Finder mutation or user-file create/move/copy/delete path exists."
