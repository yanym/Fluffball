#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
SOURCE_DIR="$PROJECT_DIR/Sources/Furball2D"

finder_forbidden='NSAppleScript|osascript|CreateDesktop|desktop position|trashItem\(|setAttributes\(|setResourceValue\('
if rg -n "$finder_forbidden" "$SOURCE_DIR" -g '*.swift'; then
  print -u2 "Runtime safety audit failed: a Finder, Desktop, Trash, or metadata mutation path is reachable."
  exit 1
fi

# General runtime code remains read-only. The only mutation implementation is
# the explicit Pet Pack import/creator manager, which is separately constrained
# to Furball's own managed library and user-selected export destinations.
managed_mutation='removeItem\(|moveItem\(|replaceItemAt\(|copyItem\(|createDirectory\(|FileHandle\(forWriting|createFile\('
if rg -n "$managed_mutation" "$SOURCE_DIR" -g '*.swift' -g '!PetPackLibraryManager.swift' -g '!VisualQACapture.swift'; then
  print -u2 "Runtime safety audit failed: file mutation escaped the Pet Pack manager."
  exit 1
fi

if ! rg -q 'requireManagedPetLibraryURL\(target\)' "$SOURCE_DIR/PetPackLibraryManager.swift" \
  || ! rg -q 'requireManagedPetLibraryURL\(staging\)' "$SOURCE_DIR/PetPackLibraryManager.swift"; then
  print -u2 "Runtime safety audit failed: Pet Pack installation lacks managed-library path guards."
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

if rg -n 'Data\([^)]*contentsOf:.*\)\.write|FileHandle\(forWriting|createFile\(' "$SOURCE_DIR" -g '*.swift' -g '!PetPackLibraryManager.swift'; then
  print -u2 "Runtime safety audit failed: an unapproved general-purpose write path exists."
  exit 1
fi

print "Runtime safety audit passed: no Finder/Desktop mutation exists; Pet Pack writes stay in guarded import/creator paths."
