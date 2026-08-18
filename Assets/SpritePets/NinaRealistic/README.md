# Nina 写实 2D 图集 / Nina Realistic 2D Atlas

[中文](#中文) · [English](#english)

## 中文

这里保存 Nina「写实 2D」外观的可追溯生成、逐帧拆分与 QA 资料。运行时只加载精简副本：

```text
Sources/Furball2D/Assets/Sprites/Nina/realistic/spritesheet.webp
```

- `package/spritesheet.webp`：可独立归档的最终无损透明图集。
- `run/references/`：本次生成使用的 Nina 身份参考图。
- `run/prompts/`：基础角色、动作行和方向修复提示词。
- `run/frames/`：从候选动作行确定性拆出的逐帧素材。
- `run/final/`：旧版候选与 1536×2288、8×11 的 v2 兼容图集；当前 2× 运行时成品由 `Scripts/build-hd-sprite-assets.py` 输出到应用素材目录。
- `run/qa/`：接触表、循环预览、方向语义与连续性报告。

该目录是制作记录，不会整体打进 App。替换运行时图集前，应重新运行仓库验证器并在 60%、100%、140% 三种显示尺寸下检查。

## English

This directory preserves the traceable generation, frame extraction, and QA material for Nina's **Realistic 2D** appearance. The app only loads the compact runtime copy:

```text
Sources/Furball2D/Assets/Sprites/Nina/realistic/spritesheet.webp
```

- `package/spritesheet.webp` is the archival lossless transparent atlas.
- `run/references/` contains the Nina identity references used for generation.
- `run/prompts/` records the base, animation-row, and direction-repair prompts.
- `run/frames/` contains deterministically extracted animation frames.
- `run/final/` contains legacy candidate and accepted 1536×2288, 8×11 compatibility atlases. `Scripts/build-hd-sprite-assets.py` writes the current 2× runtime atlas into the app asset directory.
- `run/qa/` contains contact sheets, loop previews, direction semantics, and continuity reports.

The complete working tree is not bundled into the app. Before replacing the runtime atlas, rerun the repository validators and inspect the pet at 60%, 100%, and 140% display sizes.
