# Nina realistic 2D look mechanics

- The standing paws, lower torso, ground baseline, apparent body scale, coat markings, and camera remain fixed across all 16 directions.
- `000` means Nina looks toward the top of the screen: pupils and nose lift above the head center, with a small upward neck extension.
- `090` means screen-right and `270` means screen-left. Nose tip and both pupils must visibly cross to the corresponding side of the head center; these are viewer/screen coordinates.
- `180` means down toward the desktop: pupils lead downward, muzzle follows, and the head lowers slightly without turning into the sleeping/sniffing pose.
- The motion hierarchy is eyes first, then muzzle/head/neck, with folded ears, cheek fur, white ruff, shoulders, and fluffy tail responding by a smaller delayed amount.
- Nina's naturally folded ears must never become upright pointed ears. The blaze, copper eyebrows/cheeks, white chest, and left/right coat asymmetry stay attached to the same anatomy.
- Intermediate directions advance clockwise by exactly 22.5 degrees. Adjacent poses must change gradually; no whole-sprite rotation, body replacement, face replacement, eye enlargement, clipping, or moving baseline.
- Neutral/no-vector gaze is not part of these two rows and returns to the normal animated idle row.
