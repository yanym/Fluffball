# Runtime smoke test / 运行时冒烟测试

Date / 日期：2026-08-17

## Image mode / 图片模式

```bash
FURBALL_FAST_BEHAVIOR=1 .build/debug/Furball2D \
  -videoAnimationsEnabled.furball-demo-dog false
```

- Ran for more than 73 seconds through accelerated stand, sit, lie, sleep, wake, and patrol cycles without a crash or runtime error.
- RSS sampled at about 119 MB after 33 seconds and 106 MB after 73 seconds; no sustained growth was observed.
- The atlas was decoded once and cells were reused by the runtime frame cache.
- After the final gaze-idle and autonomous-gesture changes, an additional 18-second accelerated run completed without an error.

- 加速运行超过 73 秒，覆盖站立、坐下、趴下、睡眠、起身与巡逻，未出现崩溃或运行时错误。
- 约 33 秒时 RSS 为 119 MB，约 73 秒时为 106 MB，未观察到持续增长。
- 图集只解码一次，单格图像由运行时帧缓存复用。
- 最终加入“视线回待机”和自动可爱动作后，又完成了一轮 18 秒加速运行，未出现错误。

## Video mode regression / 视频模式回归

```bash
.build/debug/Furball2D -videoAnimationsEnabled.furball-demo-dog true
```

The existing MP4 path launched and played without runtime errors. The image-atlas implementation does not replace or re-encode the existing video clips.

原有 MP4 路径可以正常启动播放；图片图集实现没有替换或重新编码现有视频素材。
