#!/usr/bin/env python3
"""Portable structural validator for Furball Pet Pack v2 image-only packages."""

from __future__ import annotations

import json
import re
import struct
import sys
from pathlib import Path

REQUIRED = {
    "stand.idle", "stand.look.images", "stand.to.sit", "sit.idle", "sit.to.lie",
    "lie.idle", "lie.to.sleep", "sleep.idle", "sleep.to.stand",
    "walk.start", "walk.loop", "walk.stop", "slow-run.start", "slow-run.loop",
    "slow-run.stop", "fast-run.start", "fast-run.loop", "fast-run.stop",
}
FACING = {
    "stand.facing.left-profile", "stand.facing.front-near-profile-left",
    "stand.facing.front-three-quarter-left", "stand.facing.front-near-center-left",
    "stand.facing.front", "stand.facing.front-near-center-right",
    "stand.facing.front-three-quarter-right", "stand.facing.front-near-profile-right",
    "stand.facing.right-profile",
}
PUBLISHED_ACTIONS = {
    "gesture.wave", "gesture.jump", "gesture.failed", "gesture.waiting",
    "gesture.working", "gesture.review", "gesture.play-bow",
    "gesture.head-tilt", "gesture.sniff", "gesture.high-five",
    "gesture.stretch", "gesture.sneeze", "gesture.paw-tap",
    "gesture.happy-dance", "gesture.yawn", "gesture.drowsy",
    "gesture.tail-chase",
}
IMAGE_STATE_MODEL = "furball-image-state-v1"
STANDARD_ROWS = {
    "idle": (0, 6), "running-right": (1, 8), "running-left": (2, 8),
    "waving": (3, 4), "jumping": (4, 5), "failed": (5, 8),
    "waiting": (6, 6), "working": (7, 6), "review": (8, 6),
}
POSTURE_BINDINGS = {
    "stand.idle": ("idle", None, True, None),
    "stand.to.sit": ("waiting", [0], False, None),
    "sit.idle": ("waiting", None, True, None),
    "sit.to.lie": ("failed", [1, 2, 3], False, None),
    "lie.idle": ("failed", [2, 3, 2], True, None),
    "lie.to.sleep": ("failed", [2, 3, 4, 5], False, None),
    "sleep.idle": ("failed", [5], True, "sleep"),
    "sleep.to.stand": ("failed", [5, 4, 3, 2, 1, 0], False, None),
}
SUPPORTED_MOTIONS = {
    "none", "idle", "sleep", "transition", "look", "gesture",
    "walk", "slow-run", "fast-run", "settle",
}
GESTURE_DURATION_RANGES = {
    "gesture.wave": (2.2, 3.0), "gesture.jump": (1.2, 1.8),
    "gesture.failed": (1.8, 2.7), "gesture.waiting": (2.4, 3.6),
    "gesture.working": (2.4, 3.6), "gesture.review": (2.4, 3.6),
    "gesture.play-bow": (2.0, 3.0), "gesture.head-tilt": (1.8, 2.8),
    "gesture.sniff": (2.4, 3.6), "gesture.high-five": (1.8, 2.8),
    "gesture.stretch": (2.3, 3.5), "gesture.sneeze": (0.55, 1.2),
    "gesture.paw-tap": (1.2, 2.0), "gesture.happy-dance": (2.1, 3.2),
    "gesture.yawn": (3.0, 4.8), "gesture.drowsy": (2.8, 4.2),
    "gesture.tail-chase": (2.0, 3.2),
}


def fail(message: str) -> None:
    raise SystemExit(f"ERROR: {message}")


def safe_file(root: Path, relative: str) -> Path:
    if not relative or relative.startswith(("/", "\\")) or "\\" in relative:
        fail(f"unsafe path: {relative!r}")
    candidate = (root / relative).resolve()
    try:
        candidate.relative_to(root.resolve())
    except ValueError:
        fail(f"path escapes package: {relative}")
    if not candidate.is_file() or candidate.is_symlink():
        fail(f"missing file or symlink: {relative}")
    return candidate


def webp_dimensions(path: Path) -> tuple[int, int, bool]:
    data = path.read_bytes()[:64]
    if len(data) < 30 or data[:4] != b"RIFF" or data[8:12] != b"WEBP":
        fail(f"not a WebP: {path.name}")
    kind = data[12:16]
    if kind == b"VP8X":
        flags = data[20]
        width = 1 + int.from_bytes(data[24:27], "little")
        height = 1 + int.from_bytes(data[27:30], "little")
        return width, height, bool(flags & 0x10)
    if kind == b"VP8L" and data[20] == 0x2F:
        packed = int.from_bytes(data[21:25], "little")
        width = 1 + (packed & 0x3FFF)
        height = 1 + ((packed >> 14) & 0x3FFF)
        alpha_used = bool((packed >> 28) & 1)
        return width, height, alpha_used
    fail(f"WebP must be lossless VP8L or extended VP8X with alpha: {path.name}")


def atlas_contract(root: Path, atlas: dict, semantic: set[str], files: set[str]) -> None:
    if atlas.get("spriteVersionNumber") != 2:
        fail("spriteVersionNumber must be 2")
    if atlas.get("stateModel") != IMAGE_STATE_MODEL:
        fail(f"spriteAtlas.stateModel must be {IMAGE_STATE_MODEL}")
    layout = atlas.get("layout", {})
    scale = atlas.get("assetScale", 2)
    expected = {"columns": 8, "rows": 11, "cellWidth": 192 * scale, "cellHeight": 208 * scale}
    if scale != 2 or layout != expected:
        fail("creator output must use assetScale 2: 8x11 with native 384x416 cells")
    file = atlas.get("file")
    if not isinstance(file, str):
        fail("spriteAtlas.file is required")
    files.add(file)
    animations = {a.get("id"): a for a in atlas.get("animations", [])}
    if len(animations) < 9:
        fail("all nine standard animation rows are required")
    for animation_id, (row, frames) in STANDARD_ROWS.items():
        animation = animations.get(animation_id, {})
        if animation.get("rowIndex") != row or animation.get("frameCount") != frames:
            fail(f"{animation_id} does not match the shared 2D state row contract")
        durations = animation.get("frameDurations", [])
        if len(durations) != frames or not all(isinstance(v, (int, float)) and v > 0 for v in durations):
            fail(f"{animation_id} must declare one positive duration per frame")
        if animation.get("motion", "none") not in SUPPORTED_MOTIONS:
            fail(f"{animation_id} declares an unsupported motion")
        blend = animation.get("frameBlendFraction", 0)
        if not isinstance(blend, (int, float)) or not 0 <= blend <= 0.82:
            fail(f"{animation_id} frameBlendFraction must be in 0...0.82")
    binding_list = atlas.get("bindings", [])
    binding_map = {binding.get("id"): binding for binding in binding_list}
    for binding in binding_list:
        if binding.get("animation") not in animations:
            fail(f"binding {binding.get('id')} references a missing animation")
        if binding.get("motion", animations[binding["animation"]].get("motion", "none")) not in SUPPORTED_MOTIONS:
            fail(f"binding {binding.get('id')} declares an unsupported motion")
        blend = binding.get("frameBlendFraction", animations[binding["animation"]].get("frameBlendFraction", 0))
        if not isinstance(blend, (int, float)) or not 0 <= blend <= 0.82:
            fail(f"binding {binding.get('id')} frameBlendFraction must be in 0...0.82")
        semantic.add(binding.get("id", ""))
    for binding_id, (animation, frames, loops, motion) in POSTURE_BINDINGS.items():
        binding = binding_map.get(binding_id, {})
        if (binding.get("animation"), binding.get("frameIndices"), binding.get("loop"), binding.get("motion")) != (animation, frames, loops, motion):
            fail(f"{binding_id} does not match {IMAGE_STATE_MODEL}")
    for tier in ("walk", "slow-run", "fast-run"):
        start_indices = binding_map.get(f"{tier}.start", {}).get("frameIndices", [])
        loop_indices = binding_map.get(f"{tier}.loop", {}).get("frameIndices", [])
        if len(start_indices) < 4:
            fail(f"{tier}.start must contain at least four ordered authored poses")
        if len(loop_indices) != 8 or len(set(loop_indices)) != 8:
            fail(f"{tier}.loop must publish all eight distinct gait poses in cyclic order")
        if loop_indices[0] != (start_indices[-1] + 1) % 8:
            fail(f"{tier}.loop must continue from the pose after {tier}.start")
    directions = atlas.get("lookDirections", [])
    degrees = {float(d.get("degrees")) for d in directions if "degrees" in d}
    if degrees != {i * 22.5 for i in range(16)}:
        fail("lookDirections must contain 0..337.5 in 22.5-degree steps")
    semantic.update(FACING)
    actions = {a.get("id") for a in atlas.get("actions", [])}
    bindings = {b.get("id") for b in atlas.get("bindings", [])}
    if not actions.issubset(bindings):
        fail("every published action must have a binding")
    if not PUBLISHED_ACTIONS.issubset(actions):
        fail("missing action registry IDs: " + ", ".join(sorted(PUBLISHED_ACTIONS - actions)))
    for binding_id, (minimum, maximum) in GESTURE_DURATION_RANGES.items():
        binding = binding_map.get(binding_id, {})
        animation = animations.get(binding.get("animation"), {})
        indices = binding.get("frameIndices", list(range(animation.get("frameCount", 0))))
        durations = animation.get("frameDurations", [])
        try:
            duration = sum(durations[index] for index in indices) * float(binding.get("frameDurationScale", 1))
        except (IndexError, TypeError, ValueError):
            fail(f"{binding_id} has invalid frame timing")
        if not minimum <= duration <= maximum:
            fail(f"{binding_id} duration {duration:.3f}s must be in {minimum}...{maximum}s")
    for binding_id in ("gesture.jump", "gesture.play-bow", "gesture.stretch", "gesture.happy-dance"):
        binding = binding_map.get(binding_id, {})
        indices = binding.get("frameIndices", [])
        if binding.get("animation") != "jumping" or not indices or indices[0] != 4 or indices[-1] != 4:
            fail(f"{binding_id} must enter and exit through jumping row stand frame 4")


def main() -> None:
    if len(sys.argv) != 2:
        fail("usage: validate_pet_pack.py <MyPet.furballpet>")
    root = Path(sys.argv[1]).expanduser().resolve()
    manifest_path = root / "manifest.json"
    if not root.is_dir() or not manifest_path.is_file():
        fail("select a .furballpet directory containing manifest.json")
    manifest = json.loads(manifest_path.read_text("utf-8"))
    if manifest.get("petPackVersion") != 2:
        fail("petPackVersion must be 2")
    pet = manifest.get("pet", {})
    if not re.fullmatch(r"[a-z0-9][a-z0-9-]{1,63}", pet.get("id", "")):
        fail("pet.id must be lowercase kebab-case")
    if pet.get("species") not in {"dog", "cat", "other"}:
        fail("pet.species must be dog, cat, or other")
    body_size = pet.get("bodySize", 60)
    if not isinstance(body_size, int) or not 1 <= body_size <= 100:
        fail("pet.bodySize must be an integer from 1 through 100")
    capabilities = manifest.get("capabilities", {})
    if capabilities.get("imageMode") is not True or capabilities.get("videoMode") is not False:
        fail("creator output must be imageMode=true and videoMode=false")

    clarity_path = root / "QA" / "clarity.json"
    if not clarity_path.is_file():
        fail("QA/clarity.json is required")
    clarity = json.loads(clarity_path.read_text("utf-8"))
    required_clarity = {
        "nativeCellWidth": 384,
        "nativeCellHeight": 416,
        "sourceRowsGeneratedNatively": True,
        "losslessAtlas": True,
        "reviewedAtNativeScale": True,
    }
    for key, expected in required_clarity.items():
        if clarity.get(key) != expected:
            fail(f"QA/clarity.json: {key} must be {expected!r}")
    if float(clarity.get("maximumRegistrationUpscale", 99)) > 1.25:
        fail("QA/clarity.json: maximumRegistrationUpscale must be <= 1.25")
    if clarity.get("rejectedArtifacts") != []:
        fail("QA/clarity.json: rejectedArtifacts must be an empty array after repair")

    semantic: set[str] = set()
    atlas_files: set[str] = set()
    atlas = manifest.get("spriteAtlas")
    if not isinstance(atlas, dict):
        fail("top-level spriteAtlas is required")
    atlas_contract(root, atlas, semantic, atlas_files)
    for appearance in manifest.get("appearances", []):
        if appearance.get("kind") != "sprite-atlas":
            fail("creator output appearances must be sprite-atlas")
        if isinstance(appearance.get("spriteAtlas"), dict):
            atlas_contract(root, appearance["spriteAtlas"], semantic, atlas_files)
        elif isinstance(appearance.get("atlasFile"), str):
            atlas_files.add(appearance["atlasFile"])
        else:
            fail(f"appearance {appearance.get('id')} has no atlas")
    if not REQUIRED.issubset(semantic):
        fail("missing semantic IDs: " + ", ".join(sorted(REQUIRED - semantic)))
    appearances = manifest.get("appearances", [])
    if len(appearances) != 1 or appearances[0].get("id") != "realistic-2d":
        fail("creator output must contain exactly one realistic-2d appearance")
    if sum(bool(a.get("isDefault")) for a in manifest["appearances"]) != 1:
        fail("exactly one appearance must be default")
    for relative in atlas_files:
        image = safe_file(root, relative)
        width, height, alpha = webp_dimensions(image)
        atlas_scale = atlas.get("assetScale", 2)
        expected_size = (1536 * atlas_scale, 2288 * atlas_scale)
        if (width, height) != expected_size or not alpha:
            fail(f"{relative}: expected {expected_size[0]}x{expected_size[1]} WebP with alpha")
    print(f"OK: {pet.get('name')} — {len(manifest['appearances'])} appearance(s), 27 semantic slots")


if __name__ == "__main__":
    main()
