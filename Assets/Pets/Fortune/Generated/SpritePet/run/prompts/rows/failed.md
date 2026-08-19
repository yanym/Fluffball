Create one horizontal animation strip for Codex pet `fortune`, state `failed`.

Use the attached canonical base for identity. Use the attached layout guide only for slot count, spacing, centering, and padding; do not draw the guide.

Output exactly 8 full-body frames in one left-to-right row on flat pure magenta #FF00FF. Treat the row as 8 invisible equal-width slots: one centered complete pose per slot, evenly spaced, with no overlap, clipping, empty slots, labels, or borders.

Identity: same pet in every frame: Preserve Fortune's exact corgi identity: compact long body, short legs, large upright ears, black saddle with tan edges, asymmetric narrow white blaze, white muzzle/chest/legs, dark eyes, and docked or naturally very short tail. Produce high-fidelity photorealistic 2D studio cutouts with crisp fur detail and stable proportions.. Preserve silhouette, face, proportions, markings, palette, material, style, and props.
Style: Pet-safe sprite: compact full-body mascot, readable in a 192x208 cell, clear silhouette, simple face, stable palette/materials, and crisp edges for chroma-key extraction. Style `auto`: Infer the most appropriate pet-safe style from the user request and reference images, then keep that exact style consistent across every row. User style notes: High-fidelity photorealistic 2D studio cutout, native Retina detail, clean fur contours, consistent neutral lighting, no props or clothing, no stylization that changes identity..
Animation continuity: keep apparent pet scale and baseline stable within the row unless the state itself intentionally changes vertical position, such as `jumping`. Move the pose within the slot instead of redrawing the pet larger or smaller frame to frame.

State action: One coherent posture chain: awake stand → lower body → genuinely horizontal lie → chin on front paws → half-closed eyes → closed-eye sleep.

State requirements:
- Frames 1–2 lower the body, frames 3–4 are fully lying and awake, frame 5 closes the eyes, and frames 6–8 remain fully lying and asleep with only tiny breathing changes.
- A standing or sitting corgi merely lowering its head is a generation failure for this row.
- Tears, small smoke puffs, or tiny stars are allowed only if attached to or overlapping the pet silhouette and kept inside the same frame slot.
- Do not draw red X marks, floating symbols, detached stars, separated smoke clouds, falling tear drops, dust, or other loose effects.

Clean extraction: crisp opaque edges, safe padding, no scenery, text, guide marks, checkerboard, shadows, glows, motion blur, speed lines, dust, detached effects, stray pixels, or chroma-key colors inside the pet.
