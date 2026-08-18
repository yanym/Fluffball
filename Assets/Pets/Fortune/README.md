# Fortune source workspace

Fortune is the second bundled pet profile: a tricolor Pembroke Welsh Corgi with a black saddle, warm tan head and haunches, a narrow asymmetric white forehead blaze, white muzzle/chest/legs, large upright ears, dark eyes, and a naturally very short tail.

- `UserProvided/ReferencePhotos/` contains the six immutable identity photos supplied by the user. Their filenames describe the visible view or posture.
- `Generated/SpritePet/run/` contains the grounded `$hatch-pet` generation record, canonical identity image, native-HD action grids, and QA data.
- `Generated/SpritePets/HD-QA/realistic-atlas.png` is the complete 11-row visual review sheet.

The corresponding image-only runtime Pet Pack lives at `Sources/Furball2D/Assets/Pets/Fortune/`. It deliberately declares `videoMode=false`; Fortune-specific Live Motion can be added later without changing the profile ID.
