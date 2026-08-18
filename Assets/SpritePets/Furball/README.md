# Furball Codex v2 图片宠物 / Furball Codex v2 Image Pet

[中文](#中文) · [English](#english)

## 中文

这里保存 Furball 图片动画图集的可追溯生成与 QA 资料。目录按用途划分：

- `source/canonical-base.png`：锁定身份、毛色和比例的角色母图。
- `source/rows/`：最终采用的各动作与方向生成行，方便以后局部重做。
- `package/`：独立的成品图集和布局清单。
- `qa/`：接触表、方向预览、循环 GIF 和确定性检查报告。

应用实际加载的运行时副本位于：

```text
Sources/Furball2D/Assets/Sprites/Nina/cute/spritesheet.webp
```

成品遵循 Codex `spriteVersionNumber: 2`：1536×2288、8 列×11 行、每格 192×208、透明无损 WebP。

- 0：idle，6 帧。
- 1：running-right，8 帧。
- 2：running-left，8 帧；为保留真实左右花纹而独立生成，没有镜像第 1 行。
- 3–8：waving、jumping、failed、waiting、working、review。
- 9–10：从 0° 起每 22.5° 一个的 16 个视线方向；0° 上、90° 屏幕右、180° 下、270° 屏幕左。

`qa/contact-sheet.png` 是完整接触表，`qa/look-directions.png` 是方向语义表，`qa/look-continuity.json` 是相邻方向连续性数据，`qa/validation.json` 与 `qa/chroma-despill.json` 是结构、Alpha 和蓝幕边缘的确定性验收结果。

运行时不按行名写死行为。`Sources/Furball2D/Assets/manifest.json` 通过 `spriteAtlas.animations` 声明时间，通过 `bindings` 映射 27 个标准动作，通过 `lookDirections` 声明方向，通过 `actions` 发布双语可爱动作。制作另一只狗或猫时可替换图集与清单，不要在 Swift 中增加宠物专属路径。

## English

This directory preserves traceable generation and QA material for the Furball image-animation atlas. It is organized by purpose:

- `source/canonical-base.png` locks identity, coat color, and proportions.
- `source/rows/` keeps the accepted generated action and direction strips for targeted regeneration.
- `package/` contains the standalone atlas and layout metadata.
- `qa/` contains contact sheets, direction previews, loop GIFs, and deterministic reports.

The copy loaded by the app at runtime is:

```text
Sources/Furball2D/Assets/Sprites/Nina/cute/spritesheet.webp
```

It follows the Codex `spriteVersionNumber: 2` contract: a transparent lossless WebP at 1536×2288, 8 columns × 11 rows, and 192×208 cells.

- Row 0: six-frame idle.
- Row 1: eight-frame running-right.
- Row 2: eight-frame running-left, generated independently to preserve real asymmetric markings rather than mirroring row 1.
- Rows 3–8: waving, jumping, failed, waiting, working, and review.
- Rows 9–10: 16 gaze directions at 22.5° intervals from 0°. Zero is up, 90° screen-right, 180° down, and 270° screen-left.

`qa/contact-sheet.png` is the full contact sheet, `qa/look-directions.png` is the labeled semantic sheet, `qa/look-continuity.json` contains adjacent-direction metrics, and `qa/validation.json` plus `qa/chroma-despill.json` are the deterministic structure, alpha, and blue-edge reports.

Runtime behavior is not hardcoded by row name. `Sources/Furball2D/Assets/manifest.json` declares timing in `spriteAtlas.animations`, maps all 27 standard semantics through `bindings`, defines gaze through `lookDirections`, and publishes localized gestures through `actions`. A new dog or cat should replace the atlas and manifest metadata without adding pet-specific Swift paths.
