#!/usr/bin/env python3
"""Rebuild Furball's 2× v2 atlases from the largest approved row sources."""

from __future__ import annotations

import argparse
from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image


CELL_W, CELL_H = 384, 416
COLS, ROWS = 8, 11
FRAME_COUNTS = [6, 8, 8, 4, 5, 8, 6, 6, 6, 8, 8]


def chroma_alpha(image: Image.Image, key: str) -> Image.Image:
    rgb = np.asarray(image.convert("RGB"), dtype=np.float32)
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    if key == "magenta":
        dominance = np.minimum(r, b) - g
        brightness = (r + b) * 0.5
    elif key == "green":
        dominance = g - np.maximum(r, b)
        brightness = g
    else:
        dominance = b - np.maximum(r, g)
        brightness = b
    # A soft dominance ramp preserves fine fur while removing the saturated key.
    alpha = np.clip((72.0 - dominance) / 34.0, 0.0, 1.0)
    alpha = np.where(brightness < 70.0, 1.0, alpha)
    # Remove key-color spill from semitransparent fur edges before preserving
    # straight alpha. This prevents blue/magenta/green halos on dark desktops.
    edge = alpha < 0.995
    corrected = rgb.copy()
    if key == "magenta":
        spill = np.maximum(0.0, np.minimum(r, b) - g)
        corrected[..., 0] = np.where(edge, r - spill, r)
        corrected[..., 2] = np.where(edge, b - spill, b)
    elif key == "green":
        spill = np.maximum(0.0, g - np.maximum(r, b))
        corrected[..., 1] = np.where(edge, g - spill, g)
    else:
        spill = np.maximum(0.0, b - np.maximum(r, g))
        corrected[..., 2] = np.where(edge, b - spill, b)
    rgba = np.dstack((np.clip(corrected, 0.0, 255.0), alpha[..., None] * 255.0)).astype(np.uint8)
    return Image.fromarray(rgba, "RGBA")


def load_keyed(path: Path, key: str) -> Image.Image:
    image = Image.open(path)
    if "A" in image.getbands():
        rgba = image.convert("RGBA")
        alpha = np.asarray(rgba.getchannel("A"))
        if np.any(alpha < 250):
            data = np.asarray(rgba).copy()
            data[data[..., 3] == 0, :3] = 0
            return Image.fromarray(data, "RGBA")
    return chroma_alpha(image.convert("RGB"), key)


def split_horizontal(path: Path, count: int, key: str) -> list[Image.Image]:
    keyed = load_keyed(path, key)
    alpha = np.asarray(keyed.getchannel("A"))
    column_ink = np.count_nonzero(alpha > 96, axis=0).astype(np.float32)
    column_ink = np.convolve(column_ink, np.ones(7, dtype=np.float32) / 7, mode="same")
    nominal = keyed.width / count
    boundaries = [0]
    for index in range(1, count):
        expected = index * nominal
        radius = nominal * 0.34
        low = max(boundaries[-1] + 8, round(expected - radius))
        high = min(keyed.width - 8, round(expected + radius))
        xs = np.arange(low, high)
        # Prefer the cleanest vertical valley but mildly penalize implausibly
        # large shifts, keeping animation order deterministic.
        score = column_ink[low:high] + np.abs(xs - expected) * 0.025
        boundaries.append(int(xs[int(np.argmin(score))]))
    boundaries.append(keyed.width)
    return [keyed.crop((boundaries[i], 0, boundaries[i + 1], keyed.height)) for i in range(count)]


def split_grid(path: Path, count: int, key: str) -> list[Image.Image]:
    image = load_keyed(path, key)
    frames = []
    for index in range(count):
        row, column = divmod(index, 4)
        x0 = round(image.width * column / 4)
        x1 = round(image.width * (column + 1) / 4)
        y0 = round(image.height * row / 2)
        y1 = round(image.height * (row + 1) / 2)
        frames.append(image.crop((x0, y0, x1, y1)))
    return frames


def alpha_bbox(frame: Image.Image) -> tuple[int, int, int, int]:
    alpha = np.asarray(frame.getchannel("A"))
    ys, xs = np.where(alpha > 24)
    if len(xs) == 0:
        return (0, 0, 1, 1)
    return (int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1)


def keep_primary_subject(frame: Image.Image) -> Image.Image:
    rgba = np.asarray(frame).copy()
    mask = rgba[..., 3] > 96
    visited = np.zeros(mask.shape, dtype=bool)
    largest: list[tuple[int, int]] = []
    height, width = mask.shape
    for seed_y, seed_x in np.argwhere(mask):
        y, x = int(seed_y), int(seed_x)
        if visited[y, x]:
            continue
        component: list[tuple[int, int]] = []
        queue = deque([(y, x)])
        visited[y, x] = True
        while queue:
            cy, cx = queue.popleft()
            component.append((cy, cx))
            for ny in range(max(0, cy - 1), min(height, cy + 2)):
                for nx in range(max(0, cx - 1), min(width, cx + 2)):
                    if mask[ny, nx] and not visited[ny, nx]:
                        visited[ny, nx] = True
                        queue.append((ny, nx))
        if len(component) > len(largest):
            largest = component
    primary = np.zeros(mask.shape, dtype=bool)
    for y, x in largest:
        primary[y, x] = True
    # Recover antialiased edge pixels around the hard primary component.
    for _ in range(3):
        expanded = primary.copy()
        expanded[1:, :] |= primary[:-1, :]
        expanded[:-1, :] |= primary[1:, :]
        expanded[:, 1:] |= primary[:, :-1]
        expanded[:, :-1] |= primary[:, 1:]
        primary = expanded
    rgba[..., 3] = np.where(primary, rgba[..., 3], 0)
    return Image.fromarray(rgba, "RGBA")


def normalize_row(frames: list[Image.Image]) -> list[Image.Image]:
    frames = [keep_primary_subject(frame) for frame in frames]
    boxes = [alpha_bbox(frame) for frame in frames]
    widths = [box[2] - box[0] for box in boxes]
    heights = [box[3] - box[1] for box in boxes]
    scale = min((CELL_W - 18) / max(widths), (CELL_H - 18) / max(heights))
    output: list[Image.Image] = []
    for frame, box in zip(frames, boxes):
        subject = frame.crop(box)
        size = (max(1, round(subject.width * scale)), max(1, round(subject.height * scale)))
        subject = subject.resize(size, Image.Resampling.LANCZOS)
        cell = Image.new("RGBA", (CELL_W, CELL_H), (0, 0, 0, 0))
        x = round((CELL_W - subject.width) / 2)
        y = CELL_H - 8 - subject.height
        cell.alpha_composite(subject, (x, y))
        output.append(cell)
    return output


def source_rows(root: Path, style: str) -> list[tuple[Path, bool, str]]:
    if style == "realistic":
        base = root / "Assets/SpritePets/NinaRealistic/run"
        decoded = base / "decoded"
        return [
            (base / "generated-hd/idle-grid-4x2.png", True, "magenta"),
            (base / "generated-hd/running-right-grid-4x2.png", True, "magenta"),
            (base / "generated-hd/running-left-grid-4x2.png", True, "magenta"),
            (decoded / "waving.png", False, "magenta"),
            (decoded / "jumping.png", False, "magenta"),
            (decoded / "failed.png", False, "magenta"),
            (decoded / "waiting.png", False, "magenta"),
            (decoded / "running.png", False, "magenta"),
            (decoded / "review.png", False, "magenta"),
            (base / "generated-hd/look-row-9-grid-4x2.png", True, "magenta"),
            (base / "generated-hd/look-row-10-grid-4x2.png", True, "green"),
        ]
    base = root / "Assets/SpritePets/Furball/source"
    rows = base / "rows"
    return [
        (base / "generated-hd/idle-grid-4x2.png", True, "blue"),
        (base / "generated-hd/running-right-grid-4x2.png", True, "blue"),
        (base / "generated-hd/running-left-grid-4x2.png", True, "blue"),
        (rows / "waving.png", False, "blue"),
        (rows / "jumping.png", False, "blue"),
        (rows / "failed.png", False, "blue"),
        (rows / "waiting.png", False, "blue"),
        (rows / "working.png", False, "blue"),
        (rows / "review.png", False, "blue"),
        (base / "generated-hd/look-row-9-grid-4x2.png", True, "blue"),
        (base / "generated-hd/look-row-10-grid-4x2.png", True, "blue"),
    ]


def build(root: Path, style: str) -> None:
    sources = source_rows(root, style)
    atlas = Image.new("RGBA", (COLS * CELL_W, ROWS * CELL_H), (0, 0, 0, 0))
    for row, ((source, is_grid, key), frame_count) in enumerate(zip(sources, FRAME_COUNTS)):
        if not source.is_file():
            raise FileNotFoundError(source)
        frames = split_grid(source, frame_count, key) if is_grid else split_horizontal(source, frame_count, key)
        for column, frame in enumerate(normalize_row(frames)):
            atlas.alpha_composite(frame, (column * CELL_W, row * CELL_H))

    output = root / f"Sources/Furball2D/Assets/Sprites/Nina/{style}/spritesheet.webp"
    output.parent.mkdir(parents=True, exist_ok=True)
    atlas.save(output, "WEBP", lossless=True, quality=100, method=6, exact=True)

    qa = root / f"Assets/SpritePets/HD-QA/{style}-atlas.png"
    qa.parent.mkdir(parents=True, exist_ok=True)
    atlas.resize((COLS * 192, ROWS * 208), Image.Resampling.LANCZOS).save(qa)
    print(f"{style}: {output} ({atlas.width}x{atlas.height})")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--style", choices=("cute", "realistic", "all"), default="all")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    styles = ("cute", "realistic") if args.style == "all" else (args.style,)
    for style in styles:
        build(root, style)


if __name__ == "__main__":
    main()
