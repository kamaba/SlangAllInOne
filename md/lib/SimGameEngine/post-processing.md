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

## 5. 已知坑与注意事项

1. **后端差异**：GL / GLES 全部 11 项生效；D3D11 / Vulkan 固化着色器目前只吃 brightness / saturation / vignette + 开关，其余静默忽略（待 SPIR-V/DXBC 重产）。跨后端验收画面时只比这三个参数。
2. **后处理作用于一切画面内容**：天空渐变、2D 精灵都会被一起调色；只想改某物体时调它自己的颜色，别开后处理。
3. **缺省语义是「不修改」**：只配了暗角的 Volume 不会把亮度清掉；未配置字段继承上层混合值。
4. **tonemap 是枚举**：切换会跳变，不做插值；需要过渡用 weight 淡入。
5. **多相机各自 compute**：把栈算成全局单例会让两台相机后处理串台。
6. **Bloom / DOF / 雾**：配置了不生效（`unsupportedCount` 会计数），需要渲染库 HDR 中间缓冲（M5）；别误判成参数写错。
7. **grain 随帧自动变化**（种子 = 管线帧计数），同一帧内固定；录屏对帧断言时把 grain 留 0。
