#!/usr/bin/env python3
"""Rebuild Nina's cursor-facing standing keyframes from the approved HD sources.

The former runtime keyframes were first reduced to 960x540 and later enlarged to
1280x720 video. This script keys and aligns the original 1440x1080 references
directly onto the final 1280x720 canvas, preserving fur and eye detail.
"""

from __future__ import annotations

import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter


PROJECT = Path(__file__).resolve().parents[1]
SOURCE = PROJECT / "Assets/Pets/Nina/Generated/AIReferenceImages/generation-ready/stand"
OUTPUT = PROJECT / "Assets/Pets/Nina/Generated/ImageTurn/normalized"
QA_PATH = PROJECT / "Assets/Pets/Nina/Generated/ImageTurn/qa/standing-keyframes.json"

CANVAS_SIZE = (1280, 720)
TARGET_HEIGHT = 600
TARGET_CENTER_X = 667
TARGET_GROUND_Y = 672

SOURCES = {
    "left-profile": "left-profile.png",
    "front-near-profile-left": "front-near-profile-left-imagegen.png",
    "front-three-quarter-left": "front-three-quarter-left-imagegen.png",
    "front-near-center-left": "front-near-center-left-imagegen.png",
    "front": "front-neutral-imagegen.png",
    "front-near-center-right": "front-near-center-right-imagegen.png",
    "front-three-quarter-right": "front-three-quarter-right-imagegen.png",
    "front-near-profile-right": "front-near-profile-right-imagegen.png",
    "right-profile": "right-profile-neutral-imagegen.png",
}


def background_color(rgb: np.ndarray) -> np.ndarray:
    strip = 24
    corners = np.concatenate(
        (
            rgb[:strip, :strip].reshape(-1, 3),
            rgb[:strip, -strip:].reshape(-1, 3),
            rgb[-strip:, :strip].reshape(-1, 3),
            rgb[-strip:, -strip:].reshape(-1, 3),
        )
    )
    return np.median(corners, axis=0)


def key_green_screen(image: Image.Image) -> Image.Image:
    rgb = np.asarray(image.convert("RGB"), dtype=np.float32)
    bg = background_color(rgb)

    # Green dominance works across both the vivid image-generation green and
    # Nina's darker approved left-profile source without erasing white fur.
    excess = rgb[..., 1] - np.maximum(rgb[..., 0], rgb[..., 2])
    background_excess = float(bg[1] - max(bg[0], bg[2]))
    full_foreground_at = max(12.0, background_excess * 0.22)
    denominator = max(1.0, background_excess - full_foreground_at)
    alpha = np.clip((background_excess - excess) / denominator, 0.0, 1.0)

    # Suppress tiny compression deviations in the flat background while
    # retaining a narrow antialiased fur boundary.
    alpha = np.where(alpha < 0.075, 0.0, alpha)
    alpha = np.where(alpha > 0.94, 1.0, alpha)

    # Remove residual green without unmixing low-alpha pixels. Aggressive
    # colour reconstruction amplifies tiny JPEG/PNG edge deviations into red
    # or yellow outlines; a monotonic despill preserves the photographed fur.
    foreground = rgb.copy()
    spill = np.maximum(excess, 0.0)
    blue_spill_ratio = max(0.0, float(bg[2] - bg[0])) / max(1.0, background_excess)
    foreground[..., 2] = np.maximum(0.0, foreground[..., 2] - spill * blue_spill_ratio)
    foreground[..., 1] = np.minimum(
        foreground[..., 1], np.maximum(foreground[..., 0], foreground[..., 2])
    )
    foreground[alpha == 0] = 0

    rgba = np.dstack((foreground, alpha[..., None] * 255)).astype(np.uint8)
    return Image.fromarray(rgba, "RGBA")


def align_to_runtime_canvas(keyed: Image.Image) -> tuple[Image.Image, dict[str, int | float]]:
    data = np.asarray(keyed)
    ys, xs = np.where(data[..., 3] > 10)
    if len(xs) == 0:
        raise RuntimeError("green-screen key produced an empty subject")

    left, top, right, bottom = xs.min(), ys.min(), xs.max() + 1, ys.max() + 1
    cropped = keyed.crop((left, top, right, bottom))
    scale = TARGET_HEIGHT / cropped.height
    target_width = round(cropped.width * scale)
    if target_width > 1180:
        scale = 1180 / cropped.width
        target_width = 1180
    target_height = round(cropped.height * scale)

    resized = cropped.resize((target_width, target_height), Image.Resampling.LANCZOS)
    # Apply restrained detail recovery at final resolution; alpha is left alone.
    red, green, blue, alpha = resized.split()
    sharp_rgb = Image.merge("RGB", (red, green, blue)).filter(
        ImageFilter.UnsharpMask(radius=1.15, percent=105, threshold=2)
    )
    resized = Image.merge("RGBA", (*sharp_rgb.split(), alpha))

    canvas = Image.new("RGBA", CANVAS_SIZE, (0, 0, 0, 0))
    x = round(TARGET_CENTER_X - target_width / 2)
    y = TARGET_GROUND_Y - target_height
    canvas.alpha_composite(resized, (x, y))

    final_alpha = np.asarray(canvas)[..., 3]
    final_ys, final_xs = np.where(final_alpha > 10)
    bounds = {
        "xMin": int(final_xs.min()),
        "yMin": int(final_ys.min()),
        "xMax": int(final_xs.max() + 1),
        "yMax": int(final_ys.max() + 1),
        "width": int(final_xs.max() + 1 - final_xs.min()),
        "height": int(final_ys.max() + 1 - final_ys.min()),
        "centerX": round(float((final_xs.min() + final_xs.max() + 1) / 2), 2),
        "groundY": int(final_ys.max() + 1),
    }
    return canvas, bounds


def detail_score(image: Image.Image) -> float:
    rgba = np.asarray(image, dtype=np.float32)
    gray = rgba[..., :3].mean(axis=2)
    alpha = rgba[..., 3] > 220
    horizontal = np.abs(gray[:, 1:] - gray[:, :-1])
    vertical = np.abs(gray[1:, :] - gray[:-1, :])
    hmask = alpha[:, 1:] & alpha[:, :-1]
    vmask = alpha[1:, :] & alpha[:-1, :]
    values = np.concatenate((horizontal[hmask], vertical[vmask]))
    return round(float(np.mean(values)) if values.size else 0.0, 3)


def main() -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    QA_PATH.parent.mkdir(parents=True, exist_ok=True)
    report = {
        "canvas": {"width": CANVAS_SIZE[0], "height": CANVAS_SIZE[1]},
        "target": {
            "subjectHeight": TARGET_HEIGHT,
            "centerX": TARGET_CENTER_X,
            "groundY": TARGET_GROUND_Y,
        },
        "keyframes": {},
    }

    for name, filename in SOURCES.items():
        source_path = SOURCE / filename
        if not source_path.is_file():
            raise FileNotFoundError(source_path)
        source_image = Image.open(source_path)
        aligned, bounds = align_to_runtime_canvas(key_green_screen(source_image))
        destination = OUTPUT / f"{name}.png"
        aligned.save(destination, optimize=True)
        report["keyframes"][name] = {
            "source": str(source_path.relative_to(PROJECT)),
            "output": str(destination.relative_to(PROJECT)),
            "bounds": bounds,
            "detailScore": detail_score(aligned),
        }
        print(f"{name}: {bounds['width']}x{bounds['height']} at ({bounds['centerX']}, {bounds['groundY']})")

    QA_PATH.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote QA report: {QA_PATH}")


if __name__ == "__main__":
    main()
