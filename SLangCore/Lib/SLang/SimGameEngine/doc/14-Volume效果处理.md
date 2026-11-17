# SimGameEngine · 14 Volume 效果处理

> 状态：**Volume 参数栈 v1 已落盘（2026-11-17，引擎层）**：`VolumeProfile`/`Volume`/`VolumeStack` + `system/VolumeSystem.compute` + `RenderSystem.applyPost`；**混合数学核心在 C**（`sl_sim_engine_lib.sle_volume_blend`：排序 + 掩码 lerp，SL 侧只组块/解块——复用专项约定「重计算下沉 FFI」）；Bloom/Tonemap/DOF/Fog 存参数不下发（需 Render HDR 链路，M5）。
> 前置阅读：`13-天空盒与环境.md`、`05-合批与RenderObject提交.md`、`06-相机光照与探针.md`。
> 依据：`../Render/doc/07-Implemented-Features.md` §3（P2 Feature 机制未开始）、`../Render/doc/11-Pass-System.md`、`../Render/doc/13-Usage-Guide.md`。

---

## 0. v1 落盘形态（2026-11-17）

| 能力 | 状态 | 落点 |
|---|---|---|
| VolumeProfile 资源 | ✅ | `VolumeProfile.sl`：post 三参 + `hasXxx` 掩码（**缺省=不修改**）+ Bloom/Tonemap/DOF/Fog 存参数不下发（`unsupportedCount()` 统计） |
| Volume 组件 | ✅ | `Volume.sl`：profile/isGlobal/priority（值大者覆盖优先）/weight/blendDistance/influenceBounds + `weightAt(camPos)`（范围内满权重、外扩段线性衰减、范围外 0；straight-line 方法） |
| C 混合核心 | ✅ | `sle_volume_blend(inPtr, count, outPtr)`：稳定插入排序（全局优先 → priority 升序 → 距离升序）+ 掩码字段 `lerp(cur, v, weight)`，自中性 (1,1,1) 起；块布局 11 float/Volume（sle_engine.c 头注释）；绑定失败 SL 兜底线性混合（VolumeSystem 检测 <0 降级） |
| VolumeStack + System | ✅ | `VolumeStack.sl`（三参 + contributing + hasEffect）+ `system/VolumeSystem.compute(scene, camPos)`（显式栈收集 + 平行数组 + Memory 组块 → C → 解块；诊断 lastCollected/lastCulled） |
| 下发 Render | ✅ | `RenderSystem.applyPost(st)` → `pipe.setPostEffect(enable, b, s, v)`（contributing=0 → 关闭后处理） |
| 多相机隔离 | ✅（用法级） | 每相机各自 `compute` 一份栈（§4 参数栈按相机隔离） |
| Bloom/Tonemap/DOF/Fog | ❌ 存参数不下发 | 需 Render HDR 中间缓冲（M5）；`unsupportedCount` 防误判 |

用法：

```sl
VolumeSystem vs = VolumeSystem()
VolumeStack st = vs.compute( scene, camPos )   # 每相机一次
rs.applyPost( st )                             # renderFrame 之前写完（§4 帧序）
```

---

---

## 1. 现状边界（重要）

| 能力 | 状态 | 证据 |
|---|---|---|
| 后处理阶段 | ✅ 已落盘：13 阶段第 11 步 `postProcess` | Render/doc/09 §1 |
| 亮度 / 饱和度 / 暗角 | ✅ 已落盘：`cmd.postProcess(enabled, brightness, saturation, vignette)`、`PostProcessPass` | Render/doc/10、11 |
| 开关与统计 | ✅ 已落盘：`postEnabled`、`STAT_POST_ENABLED=6` | Render/doc/09 §3 |
| Volume 参数栈 / RenderFeature / 注入点 | ❌ **未开始**（P2） | Render/doc/07 §3 |
| Bloom / Tonemap / FXAA / HDR 中间缓冲 | ❌ 规划中（M5） | Render/doc/05 |
| 多效果串联 / DOF / 局部雾 | ❌ 规划中 | Render/doc/03 |

**所以：现在能调的是「亮度/饱和度/暗角」三个全局数；Volume 作为「按空间范围分层混合的效果配置」尚未实现。** 本文定义目标契约，供 Render 打通 P2 后接入。

## 2. Volume 模型【设计稿】

对齐 Unity URP 的三层结构：

```
VolumeProfile（资源，可共享）
 ├─ Bloom { intensity, threshold, scatter }
 ├─ ColorAdjustments { postExposure, contrast, colorFilter, saturation }
 ├─ Vignette { intensity, smoothness }
 ├─ Tonemapping { mode = ACES / Neutral }
 ├─ DepthOfField { focusDistance, aperture }
 └─ Fog { color, density, start, end }

Volume（组件，挂 GameObject）
 ├─ profile: VolumeProfile
 ├─ isGlobal: bool
 ├─ priority: int
 ├─ weight: Float32 [0,1]
 └─ influenceBounds: Bounds（非全局时有效，第 03 章已落盘类型）
```

### 2.1 拟定接口

```sl
public class Volume extends Behaviour
{
    public VolumeProfile profile
    public bool   isGlobal = false
    public int    priority = 0
    public Float32 weight = 1.0f
    public Bounds  influenceBounds

    public void apply( VolumeStack stack, Float32 cameraWeight )
}
```

## 3. 参数栈与混合

每帧、每台相机各自算一次最终参数：

```
1. 收集：所有激活 Volume 组件（根节点禁用则跳过，第 02 章激活传播）
2. 过滤：
     global → 生效
     local  → 相机位置 ∈ influenceBounds（Bounds.contains 已落盘）
3. 排序：isGlobal 优先，再按 priority 升序，最后按到相机距离
4. 混合：对每个效果字段按 weight 从低到高覆盖 / lerp
     未配置的字段保留上层值（不是全部重置）
5. 输出：PostSettings → cmd.postProcess(...) / 扩展后的效果链
```

### 3.1 混合规则

| 字段类型 | 混合方式 |
|---|---|
| 标量（intensity / density） | 线性插值 `lerp(a, b, weight)` |
| 颜色 | 各分量 lerp |
| 枚举（Tonemapping mode） | 高优先级**覆盖**，不插值 |
| 布尔（enabled） | 高优先级覆盖 |

**覆盖默认值为「不修改」**，不是 0：一个只配了 Vignette 的 Volume 不应该把 Bloom 清掉。实现上用「字段是否有设置」掩码区分。

### 3.2 局部 Volume 的边界过渡

硬切（进范围立刻生效）会突兀；建议加 `blendDistance`：在 `influenceBounds` 外扩一段距离内按距离衰减 weight，进入内部为满权重。`Bounds.expand(Float32)` 已落盘，可直接用于外扩计算。

## 4. 与相机、帧序的关系

```
固定步长 → update → lateUpdate（相机就位）
   ↓
第 9 步之前：按每相机的 cullMask / 位置收集 Volume → 算 PostSettings
   ↓
第 9 步：pipe.setCamera(...) / Light.applyTo(...)
   ↓
第 10 步：13 阶段管线 → 第 11 步 postProcess 消费 PostSettings
   ↓
帧尾：恢复默认栈，下一帧重新计算
```

- 多相机（第 06 章 `depth` 排序）各自有独立 PostSettings，避免后处理串台；
- Volume 的 layer 过滤与相机的 `cullMask` 共用一套 layer 定义，但**含义不同**：cullMask 决定「画哪些物体」，Volume layer 决定「这台相机吃哪些 Volume」；
- Volume 参数必须在 `renderFrame` 之前写完；阶段中途改会导致前后半帧不一致。

## 5. 与已落盘后处理的对接

当前 `postProcess` 只接受 4 个参数：

```sl
cmd.postProcess( enabled, brightness, saturation, vignette )
```

VolumeStack 落地后的过渡策略：

| Volume 效果 | 当前能否落地 |
|---|---|
| ColorAdjustments.saturation | ✅ 映射到 `saturation` |
| Vignette.intensity | ✅ 映射到 `vignette` |
| 整体曝光 | ⚠ 近似映射到 `brightness` |
| Bloom / Tonemap / DOF / Fog | ❌ 需 Render 扩展 PostProcessPass 与 HDR 中间缓冲，暂只存参数不下发 |

未支持的效果**静默忽略并给出统计计数**，不要假装生效；否则调画面时会误判为参数写错。

## 6. 示例

```sl
import Std;
import Math;

# 设计稿：全局轻微调色
VolumeProfile profile = VolumeProfile()
profile.colorAdjustments.saturation = 1.15f
profile.colorAdjustments.contrast = 1.05f
profile.vignette.intensity = 0.35f

GameObject postGo = GameObject.create( "Global Volume" )
Volume vol = postGo.addComponent<Volume>()
vol.isGlobal = true
vol.priority = 0
vol.profile = profile

# 设计稿：房间内的暖色局部 Volume
GameObject roomGo = GameObject.create( "Room Volume" )
Volume room = roomGo.addComponent<Volume>()
room.isGlobal = false
room.influenceBounds = Bounds.fromCenterSize(
    Float32_3( 0.0f, 1.5f, 0.0f ), Float32_3( 8.0f, 3.0f, 8.0f ) )
room.priority = 10
room.weight = 0.7f
```

> 当前可运行的是 Render 的 `cmd.postProcess(...)` / `PostProcessPass`（见 Render/doc/13 §Pass 用法）；上面 Volume 类尚未落盘。

## 7. 已知坑与注意

1. **~~Volume 参数栈未落盘~~ → v1 已落盘（2026-11-17）**：post 三参全链路可用（C 混合核心 + applyPost 下发）；Bloom/Tonemap/DOF/Fog 仍存参数不下发（Render HDR 链路 M5）。
2. **不要把所有效果都塞一个全局 Volume**：按「全局基调 + 局部覆盖」分层，调试时逐层开关更容易定位。
3. **字段缺省语义是「不修改」**：实现时若误写成默认值 0，低优先级 Volume 的配置会被高优先级 Volume 意外清零。
4. **枚举不插值**：Tonemapping 模式切换会跳变，需要过渡时应做交叉淡入而非对枚举插值。
5. **多相机各自算栈**：把 Volume 参数算成全局单例会导致两个相机的后处理互相串扰。
6. **后处理作用于天空盒**：第 13 章天空盒是场景内容，会一起被调色；只想改天空时调天空自身参数。
7. **HDR 链路未就绪**：Bloom / ACES Tonemap 需要 HDR 中间缓冲（Render M5）；在 LDR 回读缓冲上硬做会丢失高光信息。
