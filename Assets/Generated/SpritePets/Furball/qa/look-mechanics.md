# Furball look mechanics

Furball is a grounded, soft-bodied Australian shepherd with a separate head and neck, physical brown eyeballs, folded triangular ears, a heavy white chest ruff, four planted paws, and a long fluffy tail. The look loop must feel like one attentive dog tracking a target around the screen, not a turntable rotation.

## Stable anchor

- Keep all four paws, lower torso, apparent body scale, chest center, and ground baseline registered across all 16 cells.
- Keep the tail attached and broadly stable; only the tip may lag by a very small amount.
- Never rotate, skew, or affine-tilt the whole sprite.

## Motion chain

1. Brown eyeballs and eyelids lead the gaze while remaining inside the original eye apertures.
2. The muzzle and head pitch/yaw after the eyes. Preserve the white blaze width, nose size, skull proportions, and black mask.
3. The neck and upper chest follow subtly without sliding the lower body.
4. Folded ears, cheek fur, and chest ruff follow through a fraction later. Ears may lift or compress slightly but must remain the same folded ears.
5. The tail tip may counter-lag very slightly; it never teleports or changes length.

## Cardinal pose families

- `000 up`: broadly frontal face; pupils and nose aim toward the top edge; muzzle pitches upward; upper eyelids open slightly; ears buoy upward; lower body remains planted.
- `090 screen-right`: nose tip and both pupils move clearly to the screen-right side of the head center; the dog's left cheek and ruff become slightly more visible while the far cheek is modestly occluded; screen-right ear follows the turn.
- `180 down`: broadly frontal face; pupils aim down; muzzle tucks toward the white chest; upper eyelids lower slightly; ears soften downward; paws and body remain unchanged.
- `270 screen-left`: exact semantic opposite of `090`; nose tip and pupils move clearly to screen-left; the dog's right cheek and ruff become slightly more visible; screen-left ear follows.

## Intermediate motion budget

- Each 22.5-degree step advances eyes, muzzle, head, ear follow-through, and visible cheek area by roughly one equal visual increment.
- `022.5–067.5` interpolate up to screen-right, `112.5–157.5` interpolate screen-right to down, `202.5–247.5` interpolate down to screen-left, and `292.5–337.5` interpolate screen-left back to up.
- No adjacent step may introduce a new expression, open mouth, body scale change, paw move, ear replacement, tail flip, or re-centering jump.
- All directions remain warm, curious, closed-mouth, and identity-preserving; neutral/front belongs to idle and is not one of the 16 directions.
