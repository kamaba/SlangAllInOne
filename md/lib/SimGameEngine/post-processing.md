# SimGameEngine · 后处理与 Volume（使用者文档）

> 读者 = 写 SL 代码、想给自己的场景调画面效果的人。只写规则、示例、
> 方法签名与已知坑；引擎内部实现见 `doc/14-Volume效果处理.md`。

## 1. 一句话总览

后处理 = 画面渲染完成后的一次全屏调色（亮度/对比度/饱和度/色相/滤片/暗角/颗粒/Reinhard 色调映射）。参考 Unity URP 的 Volume 方式：

```
VolumeProfile（效果配置，可共享）
        ↓ 挂在
Volume（场景组件：全局 或 局部范围 + 权重 + 优先级）
        ↓ 每帧每相机
VolumeSystem.compute → VolumeStack（混合后的最终参数）
        ↓
RenderSystem.applyPost → 渲染管线后处理阶段
```

多个 Volume 同时生效时：按「全局优先 → priority 小者先 → 离相机近者先」排序，**已配置字段**按权重插值，**未配置字段保持不变**（不是清零）。

## 2. 场景组件形态（推荐，Unity 同款）

scene.json 节点上挂 `Volume` 组件；键缺省 = 该项不修改：

```json
{
  "id": 202, "parent": 0, "name": "CinematicVolume", "tag": "Volume",
  "components": [
    { "type": "Volume", "isGlobal": true, "priority": 0, "weight": 1.0,
      "contrast": 1.25, "saturation": 1.3,
      "vignette": 0.55, "vignetteSmooth": 0.9,
      "grain": 0.06, "tonemap": 1 }
  ]
}
```

| 键 | 中性值 | 说明 |
|---|---|---|
| isGlobal | true | false 时需 influenceBounds（局部范围） |
| priority | 0 | 值大者覆盖优先 |
| weight | 1.0 | 有效权重 [0,1]，0 = 不参与 |
| blendDistance | 0 | 局部 Volume 范围外过渡距离（0 = 硬切） |
| brightness | 1.0 | 曝光（乘法） |
| contrast | 1.0 | 对比度（<1 变灰，>1 变硬） |
| saturation | 1.0 | 饱和度（0 = 黑白） |
| hueShift | 0 | 色相偏移（角度制） |
| filterR/G/B | 1.0 | 颜色滤片（乘法 tint，暖色如 1.1/1.0/0.85） |
| vignette | 0 | 暗角强度（0 = 无暗角） |
| vignetteSmooth | 1.0 | 暗角柔度（1 = 标准柔和，越小越收硬） |
| grain | 0 | 胶片颗粒强度（建议 0~0.15，随帧自动变化） |
| tonemap | 0 | 0 = 关 / 1 = Reinhard |

## 3. 代码形态

### 3.1 打开后处理（一次性）

```sl
# Unity VolumeManager 同款：sync 每帧按相机位置自动计算并下发，
# 场景里有 Volume 组件才生效
rs.volumeSystem = VolumeSystem()
```

手动驱动（多相机各自算栈）：

```sl
VolumeSystem vs = VolumeSystem()
VolumeStack st = vs.compute( scene, camPos )   # 每相机一次、renderFrame 前
rs.applyPost( st )
```

### 3.2 代码态创建 Volume

```sl
VolumeProfile prof = VolumeProfile()
prof.setContrast( 1.2f )
prof.setSaturation( 1.25f )
prof.setVignette( 0.45f )
prof.setVignetteSmooth( 0.9f )
prof.setColorFilter( 1.05f, 1.0f, 0.9f )   # 暖色滤片
prof.setGrain( 0.05f )
prof.setTonemap( 1 )

GameObject go = scene.createObject( "GlobalVolume" )
Volume vol = go.addComponent( Volume() )
vol.isGlobal = true
vol.profile = prof
```

淡入淡出：逐帧调 `vol.weight`（0→1 渐入）。

### 3.3 局部 Volume（房间/区域效果）

```sl
vol.isGlobal = false
vol.blendDistance = 2.0f          # 范围外过渡距离，自动按距离衰减
Bounds b = Bounds()
b.min = Float32_3( 0.0f - 4.0f, 0.0f, 0.0f - 4.0f )
b.max = Float32_3( 4.0f, 3.0f, 4.0f )
vol.influenceBounds = b
```

## 4. 可用方法与签名

| 类型 | 方法 | 说明 |
|---|---|---|
| VolumeProfile | `setBrightness(f) / setContrast(f) / setSaturation(f) / setHueShift(f) / setVignette(f) / setVignetteSmooth(f) / setGrain(f)` | 掩码置位 + 赋值 |
| VolumeProfile | `setColorFilter(r, g, b)` | 颜色滤片 |
| VolumeProfile | `setTonemap(mode)` | 0 关 / 1 Reinhard（枚举不插值，高优先级覆盖） |
| VolumeProfile | `setPost(b, s, v)` | 一次配齐基础三参（兼容入口） |
| VolumeProfile | `unsupportedCount()` | 配置了但不生效的效果数（Bloom/DOF/Fog） |
| Volume | 字段 `profile / isGlobal / priority / weight / blendDistance / influenceBounds`；`weightAt(camPos)` | 组件属性 / 诊断 |
| VolumeSystem | `compute(scene, camPos)` → VolumeStack；字段 `lastCollected / lastCulled` | 每相机每帧一次 / 诊断 |
| VolumeStack | 11 个效果字段 + `contributing`（=0 即后处理关闭） | 混合结果 |
| RenderSystem | 字段 `volumeSystem`；`applyPost(stack)` → bool | 自动集成 / 手动下发 |
| RenderSystem | `setAa(msaa, fxaaOn, fxaaSpan)` → Int32 | 抗锯齿：返回实际生效采样数（0 = 单采样） |
| RenderSystem | `setMotionVectors(on)` → bool；`readMotionVectors(dstPtr)` → bool | 速度 RT 开关 / 回读 RGBA8 块（w×h×4） |
| RenderSystem | `setTaa(on, blend)` → bool | TAA 时域抗锯齿开关（on=1 自动开 motion） |
| RenderSystem | `setMotionBlur(on, scale, samples)` → bool | 动态模糊开关（on=1 自动开 motion） |

## 5. 已知坑与注意事项

1. **后端差异**：GL / GLES 全部 11 项生效；D3D11 / Vulkan 固化着色器目前只吃 brightness / saturation / vignette + 开关，其余静默忽略（待 SPIR-V/DXBC 重产）。跨后端验收画面时只比这三个参数。
2. **后处理作用于一切画面内容**：天空渐变、2D 精灵都会被一起调色；只想改某物体时调它自己的颜色，别开后处理。
3. **缺省语义是「不修改」**：只配了暗角的 Volume 不会把亮度清掉；未配置字段继承上层混合值。
4. **tonemap 是枚举**：切换会跳变，不做插值；需要过渡用 weight 淡入。
5. **多相机各自 compute**：把栈算成全局单例会让两台相机后处理串台。
6. **Bloom / DOF / 雾**：配置了不生效（`unsupportedCount` 会计数），需要渲染库 HDR 中间缓冲（M5）；别误判成参数写错。
7. **grain 随帧自动变化**（种子 = 管线帧计数），同一帧内固定；录屏对帧断言时把 grain 留 0。
8. **FXAA 独立于后处理开关**：`setAa(0, 1, 8)` 只开 FXAA 时不需要打开 Volume / `applyPost`；颜色链保持中性。
9. **MSAA 采样数会被钳制 / 回退**：传 0 或 1 = 关；传 2/4/8 之外的数按 4 处理；返回 0 表示当前后端或显卡不支持（自动回到单采样，画面照常渲染）。分辨率改变会在下一帧自动重建多采样目标。
10. **FXAA 与 MSAA 可叠加**：两者同时打开时先 MSAA resolve 再 FXAA；只开 FXAA 时零额外 RT 开销。
11. **速度 RT 是「逐帧位移」**：RG 通道 = NDC 位移×0.5+0.5（0.5 = 静止），仅保留本帧绘制物体，关闭后回读返回 false。首帧没有上帧位置，速度记为 0。
12. **后端支持差异**：FXAA 四种后端均可；MSAA 在 GL / GLES / D3D11 生效、Vulkan 回退单采样；运动矢量只在 GL / GLES 生效（Vulkan / D3D11 开关无效果）。跨后端比画面时不要在这些项上做逐像素断言。
13. **TAA 只在 GL / GLES 生效**（依赖运动矢量；Vulkan / D3D11 无速度图，开关返回 false）。打开 TAA 会自动打开运动矢量；关闭 TAA 不会自动关闭运动矢量，需单独 `setMotionVectors(0)`。
14. **TAA 的 blend 是「当前帧权重」**：默认 0.1（90% 历史，最稳但镜头转动有拖影）；快速镜头用 0.3~0.5。频繁切换开关会丢弃历史重新累积。
15. **TAA 输出是累积帧**：静止场景平坦区与无 TAA 逐位一致，几何边缘 1px 过渡带有少量舍入噪声（正常）；需要严格逐像素画面（截图比对）时关掉 TAA。
16. **动态模糊沿速度方向"拖影"**：`scale` 是速度倍率（默认 1.0，钳 0..4），值越大拖影越长；`samples` 是采样数（默认 8，钳 4..16），越大越平滑但越慢。
17. **动态模糊只在 GL / GLES 生效**（依赖运动矢量，与 TAA 同）；静止物体像素所有采样点重合，输出原色（零模糊），只有真正运动的物体/边缘被拖影。
18. **动态模糊与 TAA 可同时开**：处理顺序为 TAA → 动态模糊 → FXAA/调色；只想要运动模糊时无需开 TAA，模糊开关会自己打开速度图。

## 6. 抗锯齿与运动矢量（v1.2）

```SLang
# 抗锯齿：4x MSAA + FXAA（返回值 = 实际生效采样数）
Int32 used = rs.setAa( 4, 1, 8.0f )
Console.println( "msaa=" + used.toString() )

# 仅 FXAA（不调色、不加 RT 开销）
rs.setAa( 0, 1, 8.0f )

# 运动矢量：逐帧回读速度图（像素 RG 通道 = 位移*0.5+0.5）
rs.setMotionVectors( 1 )
rs.frame( time, dstPtr )         # 渲染一帧后速度 RT 就绪
Int64 buf = Memory.alloc( w * h * 4 )
if rs.readMotionVectors( buf )
{
    Int32 vx = Memory.readUInt8( buf, ( y * w + x ) * 4 )      # R 通道
    Int32 vy = Memory.readUInt8( buf, ( y * w + x ) * 4 + 1 )  # G 通道
}
rs.setMotionVectors( 0 )
Memory.free( buf )
```

运动矢量典型用途：帧间时序抗锯齿（TAA）重投影、运动模糊、光流可视化调试。回读缓冲是 top-down RGBA8 行序，宽高与渲染目标一致。

TAA 用法（时域平滑，自动使用上面那张速度图）：

```SLang
rs.setTaa( 1, 0.1f )             # 开 TAA，当前帧权重 0.1（平滑强）
# ... 每帧 rs.frame(...) 照常渲染，内部自动：
#     速度重投影历史帧 -> 3x3 邻域 clamp 防鬼影 -> mix(hist, cur, blend)
rs.setTaa( 0, 0.1f )             # 关 TAA（输出立即回到单帧画面）
```

可与 FXAA / MSAA 叠加（先 MSAA resolve → TAA → FXAA 调色）；只开 TAA 也有平滑效果，但配合 MSAA 4x 时边缘质量最佳。

动态模糊（利用同一张速度图，做运动拖影）：

```SLang
rs.setMotionBlur( 1, 1.0f, 8 )     # 开动态模糊：速度倍率 1.0，8 次采样
# ... 每帧 rs.frame(...) 照常渲染
rs.setMotionBlur( 0, 1.0f, 8 )     # 关
```

处理顺序：**MSAA resolve → TAA → 动态模糊 → FXAA/调色**。速度 0 的像素（静止物体、远景）输出原色，不会被糊；物体运动越快、scale 越大，拖影越长。常与 TAA 二选一或叠加使用（叠加时先 TAA 稳定边缘再做拖影）。
