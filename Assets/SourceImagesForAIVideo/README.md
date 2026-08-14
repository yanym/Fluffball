# AI 视频生成参考图

这里保存的是 Furball 狗狗的身份、体型、毛色、姿态与视角参考图，供图生视频模型生成后续动作素材。它们不是应用运行时资源，也不会被打包进 `Furball2D.app`。

## 目录

```text
SourceImagesForAIVideo/
├── originals/          # 用户提供的原始参考图；画布尺寸和构图不完全一致
│   ├── stand/
│   ├── sit/
│   ├── lie/
│   └── sleep/
└── generation-ready/   # 推荐交给视频模型的标准化参考图
    ├── stand/
    ├── sit/
    ├── lie/
    └── sleep/
```

`generation-ready/` 目前统一为 1440×1080、绿色背景，并补齐了更完整的姿态与左右视角集合。生成新视频时优先使用这一层；`originals/` 用于核对狗狗真实身份细节和追溯来源，不应覆盖或删除。

部分 PNG 包含 C2PA Content Credentials，用于记录图片的生成与处理来源。仓库保留这些真实性元数据；检查未发现 GPS、相机设备或个人作者字段。

## 命名规则

目录名表示姿态，文件名表示镜头中看到的朝向：

- `front.png`：正面。
- `left-profile.png`：标准左侧面，狗头朝画面左侧。
- `right-profile.png`：标准右侧面，狗头朝画面右侧。
- `rear.png`：正后方。
- `front-three-quarter-left.png`：左前 3/4 视角。
- `front-three-quarter-right.png`：右前 3/4 视角。
- `rear-three-quarter-left.png`：左后 3/4 视角。
- `rear-three-quarter-right.png`：右后 3/4 视角。

新增文件继续使用：

```text
<collection>/<pose>/<view>.png
```

不要再使用 `std`、`1.png` 或 `stand_left_v2_final.png` 这类需要猜测含义的名称。

## 生成视频时怎样选图

1. 用 `generation-ready/stand/front.png` 作为脸型、眼睛、鼻子、耳位和胸口花纹的身份参考。
2. 再加入与目标动作一致的姿态和视角图。例如生成左侧面“坐下 → 趴下”，优先加入 `sit/left-profile.png` 和 `lie/left-profile.png`。
3. 需要核对尾巴长度、背部花纹或身体比例时，再补一张站立侧视或后视图；通常 2–4 张参考图足够。
4. 除非动作本身需要转身，同一段视频不要混用左侧面与右侧面参考，否则模型容易在中途翻转花纹或改变耳位。
5. 每段视频必须保持同一只狗、固定机位、固定画布、稳定主体尺度、稳定地面基线和纯绿色背景。
6. 生成结果仍需按根目录 [AGENTS.md](../../AGENTS.md) 的流程检查、切分、归一化、抠像和验收，不能直接覆盖运行时素材。

## 原文件名映射

旧的 `<pose>_<view>.png` 已整理为 `<collection>/<pose>/<view>.png`。例如：

| 旧路径 | 新路径 |
|---|---|
| `stand_front.png` | `originals/stand/front.png` |
| `stand_left.png` | `originals/stand/left-profile.png` |
| `stand_back_left.png` | `originals/stand/rear-three-quarter-left.png` |
| `sleep_right.png` | `originals/sleep/right-profile.png` |
| `std/sit_left.png` | `generation-ready/sit/left-profile.png` |
| `std/lie_right.png` | `generation-ready/lie/right-profile.png` |

完整集合共有 14 张 `originals` 和 16 张 `generation-ready` 图片。`generation-ready/lie/left-profile.png` 与 `right-profile.png` 在原始层没有同名对应图，因此作为独立的生成就绪参考保留。
