#!/usr/bin/env python3
"""Render Realistic 2D bindings with Furball's runtime timing/alignment model."""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path

import numpy as np
from PIL import Image


ALPHA_THRESHOLD = 18


def smootherstep(value: float) -> float:
    x = max(0.0, min(1.0, value))
    return x * x * x * (x * (x * 6 - 15) + 10)


def alpha_box(image: Image.Image) -> tuple[int, int, int, int] | None:
    alpha = np.asarray(image.getchannel("A"))
    ys, xs = np.where(alpha >= ALPHA_THRESHOLD)
    if len(xs) == 0:
        return None
    return int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1


def aligned_incoming(outgoing: Image.Image, incoming: Image.Image, progress: float) -> Image.Image:
    outgoing_box = alpha_box(outgoing)
    incoming_box = alpha_box(incoming)
    if outgoing_box is None or incoming_box is None or progress >= 0.999:
        return incoming

    ax0, ay0, ax1, ay1 = outgoing_box
    bx0, by0, bx1, by1 = incoming_box
    incoming_height = max(1, by1 - by0)
    initial_scale = max(0.88, min(1.12, (ay1 - ay0) / incoming_height))
    scale = initial_scale + (1.0 - initial_scale) * progress
    source_center_x = (bx0 + bx1) * 0.5
    source_ground_y = by1
    target_center_x = ((ax0 + ax1) * 0.5) + (source_center_x - (ax0 + ax1) * 0.5) * progress
    target_ground_y = ay1 + (source_ground_y - ay1) * progress

    width = max(1, round(incoming.width * scale))
    height = max(1, round(incoming.height * scale))
    resized = incoming.resize((width, height), Image.Resampling.LANCZOS)
    scaled_source_center_x = source_center_x * scale
    scaled_source_ground_y = source_ground_y * scale
    x = round(target_center_x - scaled_source_center_x)
    y = round(target_ground_y - scaled_source_ground_y)
    result = Image.new("RGBA", incoming.size, (0, 0, 0, 0))
    result.alpha_composite(resized, (x, y))
    return result


def premultiplied_mix(a: Image.Image, b: Image.Image, weight: float) -> Image.Image:
    if weight <= 0:
        return a
    if weight >= 1:
        return b
    aa = np.asarray(a, dtype=np.float32) / 255.0
    bb = np.asarray(b, dtype=np.float32) / 255.0
    alpha_a = aa[..., 3:4]
    alpha_b = bb[..., 3:4]
    premul_a = aa[..., :3] * alpha_a
    premul_b = bb[..., :3] * alpha_b
    alpha = alpha_a * (1 - weight) + alpha_b * weight
    premul = premul_a * (1 - weight) + premul_b * weight
    rgb = np.divide(premul, alpha, out=np.zeros_like(premul), where=alpha > 1e-6)
    rgba = np.concatenate((rgb, alpha), axis=2)
    return Image.fromarray(np.clip(rgba * 255 + 0.5, 0, 255).astype(np.uint8), "RGBA")


def composite_for_review(image: Image.Image, scale: float = 0.5) -> Image.Image:
    size = (max(1, round(image.width * scale)), max(1, round(image.height * scale)))
    sprite = image.resize(size, Image.Resampling.LANCZOS)
    background = Image.new("RGBA", size, (43, 45, 51, 255))
    background.alpha_composite(sprite)
    return background.convert("RGB")


def binding_frames(
    atlas: Image.Image,
    descriptor: dict,
    binding: dict,
) -> tuple[list[Image.Image], list[float], float]:
    animations = {item["id"]: item for item in descriptor["animations"]}
    animation = animations[binding["animation"]]
    indices = binding.get("frameIndices", list(range(animation["frameCount"])))
    scale = float(binding.get("frameDurationScale", 1.0))
    durations = [float(animation["frameDurations"][index]) * scale for index in indices]
    layout = descriptor["layout"]
    frames = []
    for index in indices:
        x0 = index * layout["cellWidth"]
        y0 = animation["rowIndex"] * layout["cellHeight"]
        frames.append(atlas.crop((x0, y0, x0 + layout["cellWidth"], y0 + layout["cellHeight"])))
    blend = float(binding.get("frameBlendFraction", animation.get("frameBlendFraction", 0.0)))
    return frames, durations, blend


def sequence_sample(
    frames: list[Image.Image],
    durations: list[float],
    blend_fraction: float,
    elapsed: float,
) -> Image.Image:
    if len(frames) == 1:
        return frames[0]
    timeline = min(max(0.0, sum(durations) - 1e-6), elapsed)
    frame_start = 0.0
    index = len(frames) - 1
    for candidate, duration in enumerate(durations):
        if timeline < frame_start + duration:
            index = candidate
            break
        frame_start += duration
    next_index = min(len(frames) - 1, index + 1)
    if next_index == index or blend_fraction <= 0:
        return frames[index]
    local = (timeline - frame_start) / max(durations[index], 1e-6)
    blend_start = 1.0 - blend_fraction
    weight = smootherstep((local - blend_start) / max(blend_fraction, 1e-6))
    incoming = aligned_incoming(frames[index], frames[next_index], weight)
    return premultiplied_mix(frames[index], incoming, weight)


def render_binding(
    atlas: Image.Image,
    descriptor: dict,
    binding: dict,
    output: Path,
    fps: int,
) -> dict:
    frames, durations, blend = binding_frames(atlas, descriptor, binding)
    idle_binding = next(item for item in descriptor["bindings"] if item["id"] == "stand.idle")
    idle_frames, _, _ = binding_frames(atlas, descriptor, idle_binding)
    idle = idle_frames[0]
    lead, transition, tail = 0.28, 0.22, 0.32
    action_duration = sum(durations)
    total = lead + transition + action_duration + transition + tail
    rendered: list[Image.Image] = []
    for sample_index in range(max(2, math.ceil(total * fps))):
        now = sample_index / fps
        if now < lead:
            frame = idle
        elif now < lead + transition:
            weight = smootherstep((now - lead) / transition)
            incoming = aligned_incoming(idle, frames[0], weight)
            frame = premultiplied_mix(idle, incoming, weight)
        elif now < lead + transition + action_duration:
            frame = sequence_sample(frames, durations, blend, now - lead - transition)
        elif now < lead + 2 * transition + action_duration:
            outgoing = frames[-1]
            weight = smootherstep((now - lead - transition - action_duration) / transition)
            incoming = aligned_incoming(outgoing, idle, weight)
            frame = premultiplied_mix(outgoing, incoming, weight)
        else:
            frame = idle
        rendered.append(composite_for_review(frame))

    output.parent.mkdir(parents=True, exist_ok=True)
    frame_ms = max(10, round(1000 / fps))
    rendered[0].save(
        output,
        "WEBP",
        save_all=True,
        append_images=rendered[1:],
        duration=frame_ms,
        loop=0,
        quality=92,
        method=5,
    )
    sample_count = min(12, len(rendered))
    sample_indices = [
        round(index * (len(rendered) - 1) / max(1, sample_count - 1))
        for index in range(sample_count)
    ]
    columns = 6
    rows = math.ceil(sample_count / columns)
    sheet = Image.new("RGB", (rendered[0].width * columns, rendered[0].height * rows), (28, 30, 35))
    for position, frame_index in enumerate(sample_indices):
        x = (position % columns) * rendered[0].width
        y = (position // columns) * rendered[0].height
        sheet.paste(rendered[frame_index], (x, y))
    contact_path = output.with_suffix(".contact.png")
    sheet.save(contact_path)
    return {
        "id": binding["id"],
        "duration": round(action_duration, 3),
        "keyframes": len(frames),
        "runtimeSamplesAt60Hz": max(1, round(action_duration * 60)),
        "frameBlendFraction": blend,
        "preview": str(output),
        "contactSheet": str(contact_path),
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("manifest", type=Path)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--fps", type=int, default=30)
    parser.add_argument("--include", action="append", default=[])
    args = parser.parse_args()

    manifest = json.loads(args.manifest.read_text("utf-8"))
    descriptor = manifest["spriteAtlas"]
    atlas_path = args.manifest.parent / descriptor["file"]
    atlas = Image.open(atlas_path).convert("RGBA")
    selected = set(args.include)
    bindings = [
        item for item in descriptor["bindings"]
        if item["id"].startswith("gesture.") and (not selected or item["id"] in selected)
    ]
    reports = []
    pet_id = manifest["pet"]["id"]
    for binding in bindings:
        name = binding["id"].replace("gesture.", "")
        reports.append(render_binding(
            atlas,
            descriptor,
            binding,
            args.output_dir / f"{pet_id}-{name}.webp",
            max(12, min(60, args.fps)),
        ))
    report_path = args.output_dir / f"{pet_id}-motion-report.json"
    report_path.write_text(json.dumps({"pet": pet_id, "actions": reports}, indent=2) + "\n", "utf-8")
    print(report_path)


if __name__ == "__main__":
    main()
