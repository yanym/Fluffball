#!/usr/bin/env python3
"""Rebuild Nina's neutral 2D idle row from the native identity master.

The previous generated row was visually soft at its first frame. This script
uses the 1205x1305 canonical identity image directly, creates six restrained
breathing poses, and writes an exact 4x2 HD source grid. No legacy cell is
upscaled and the feet remain locked to one ground baseline.
"""

from __future__ import annotations

from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter


GRID_W = 512
GRID_H = 512
KEY = (255, 0, 238, 255)


def keyed_subject(path: Path) -> Image.Image:
    image = Image.open(path).convert("RGB")
    rgb = np.asarray(image, dtype=np.float32)
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    dominance = np.minimum(r, b) - g
    brightness = (r + b) * 0.5
    alpha = np.clip((55.0 - dominance) / 31.0, 0.0, 1.0)
    alpha = np.where(brightness < 68, 1.0, alpha)
    spill = np.maximum(0.0, np.minimum(r, b) - g)
    edge = alpha < 0.995
    rgb[..., 0] = np.where(edge, r - spill, r)
    rgb[..., 2] = np.where(edge, b - spill, b)
    rgba = np.dstack((np.clip(rgb, 0, 255), alpha[..., None] * 255)).astype(np.uint8)
    subject = Image.fromarray(rgba, "RGBA")
    box = subject.getchannel("A").getbbox()
    if box is None:
        raise ValueError("canonical identity image has no visible subject")
    return subject.crop(box)


def main() -> None:
    root = Path(__file__).resolve().parents[1]
    master = root / "Assets/Pets/Nina/Generated/SpritePets/NinaRealistic/run/references/canonical-base.png"
    output = root / "Assets/Pets/Nina/Generated/SpritePets/NinaRealistic/run/generated-hd/idle-grid-4x2.png"
    subject = keyed_subject(master)
    base_scale = min(450 / subject.width, 478 / subject.height)
    breath = [0.998, 1.000, 1.003, 1.005, 1.002, 0.999]
    grid = Image.new("RGBA", (GRID_W * 4, GRID_H * 2), KEY)
    for index, scale_y in enumerate(breath):
        width = round(subject.width * base_scale * (2 - scale_y))
        height = round(subject.height * base_scale * scale_y)
        frame = subject.resize((width, height), Image.Resampling.LANCZOS)
        # A very restrained native-resolution unsharp pass recovers fur detail
        # lost during the one required downsample from the identity master.
        frame = frame.filter(ImageFilter.UnsharpMask(radius=0.65, percent=42, threshold=3))
        cell = Image.new("RGBA", (GRID_W, GRID_H), KEY)
        x = round((GRID_W - width) / 2)
        y = GRID_H - 12 - height
        cell.alpha_composite(frame, (x, y))
        row, column = divmod(index, 4)
        grid.alpha_composite(cell, (column * GRID_W, row * GRID_H))
    output.parent.mkdir(parents=True, exist_ok=True)
    grid.convert("RGB").save(output, quality=100)
    print(output)


if __name__ == "__main__":
    main()
