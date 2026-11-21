# SimGameEngine · 14 Volume 效果处理

> 状态：**v1.4 已落盘（2026-11-20，Motion Blur 动态模糊）**：RHI vtable 加 `motion_blur` 槽（GL/GLES 独立 FS_MB 程序沿速度方向对称快门采样；D3D11/VK NULL——无速度图）；管线阶段 10.6（TAA 后、阶段 11 FXAA/调色前）消费 motion 速度图输出到 rt_mb，post 从 rt_mb 读；导出 `slr_pipeline_set_motion_blur(p,on,scale,samples)` + `SLR_STAT_MOTION_BLUR=22`，自动开 motion；速度≈0 的像素快速路径直出原色（静止零模糊）；RenderTest Phase MB 专项 PASS，全套件 EXIT=0。设计要点：独立 vtable 槽而非改 post_process 签名（规避历史四后端签名漂移坑）。
> 状态：**v1.3 已落盘（2026-11-20，TAA 时域抗锯齿）**：渲染库新增 `slr_pipeline_set_taa`（开关 + 当前帧权重 blend）与 `slr_pipeline_taa` 阶段导出；RHI vtable 加 `taa_resolve`（GL/GLES 运行期 GLSL/ESSL、D3D11 运行期 HLSL 三纹理全屏 pass，VK NULL）；管线加 history ping-pong 双 RT + 阶段 10.5（MSAA resolve 后、后处理前）：速度图重投影上帧历史 → 3×3 邻域 clamp 防鬼影 → `mix(hist, cur, blend)`；自动开启 motion（无速度图后端拒绝启用）；RenderSystem `setTaa(on, blend)` 门面；RenderTest 新增 Phase TAA（开关统计 / 静止收敛 / 速度重投影 / MSAA+TAA 组合 / 关闭零回归）全绿。
> 状态：**v1.2 已落盘（2026-11-20，AA + MotionVectors）**：渲染库新增 `slr_pipeline_set_aa` / `slr_pipeline_set_motion` / `slr_pipeline_output_motion_texture` 三导出（FXAA + MSAA + 速度 RT 回读）；后处理参数块 13→16 float（尾部 fxaaOn/fxaaSpanMax）；FS_POST 内嵌 FXAA（GL/GLES ESSL + D3D11 HLSL 运行期消费）；SLR_PROG_MOTION 速度 pass（上帧 MVP 经 PerDrawPrev UBO 绑定点 2）；管线 `SlrPipeline` 加 aa/motion RT 组 + 阶段 9 尾速度 pass + 阶段 11 MSAA resolve；引擎 RenderSystem 三个门面（`setAa` / `setMotionVectors` / `readMotionVectors`）；RenderTest 新 Phase AA + Phase MV 双绿（FXAA 748 px 边缘变化 / MSAA 4x 384 px / 速度 +x=153 -x=102 静止=127、恢复全关逐位一致）。
> 状态：**v1.1 已落盘（2026-11-18，Unity Color Adjustments 风扩参）**：后处理参数从三参扩到 **11 项可下发**（brightness/contrast/saturation/hueShift/colorFilter RGB/vignette/vignetteSmooth/grain/tonemap Reinhard）——C 渲染库新增 `slr_pipeline_set_post_params`（13 float 参数块）+ GL/GLES 着色器全量消费（VK/D3D11 v1 着色器只解 enable/brightness/saturation/vignette，其余静默忽略待 SPIR-V/DXBC 重产 M5）；引擎侧 VolumeProfile/VolumeStack/VolumeSystem 块布局 11→24 float、`RenderSystem.applyPost` 改参数块下发 + `volumeSystem` 字段自动集成（sync 每帧按相机 compute+apply，Unity VolumeManager 同款）；SceneImporter 支持 `Volume` 场景组件；**中性暗角语义修正为 0**（v1 的 1.0 起点是误语义——无配置 = 无暗角）。Bloom/DOF/Fog 仍存参数不下发（HDR 链路 M5）；Tonemapping 仅 Reinhard LDR 近似（ACES 需 HDR）。
> 使用者文档：`md/lib/SimGameEngine/post-processing.md`（只写用法/规则/坑）。
> 前置阅读：`13-天空盒与环境.md`、`05-合批与RenderObject提交.md`、`06-相机光照与探针.md`。
> 依据：`../Render/doc/07-Implemented-Features.md` §3（P2 Feature 机制未开始）、`../Render/doc/11-Pass-System.md`、`../Render/doc/13-Usage-Guide.md`。

---

## 0. v1 落盘形态（2026-11-17）

| 能力 | 状态 | 落点 |
|---|---|---|
| VolumeProfile 资源 | ✅ v1.1 | `VolumeProfile.sl`：11 项可下发字段 + `hasXxx` 掩码（**缺省=不修改**）+ Bloom/DOF/Fog 存参数不下发（`unsupportedCount()` 统计） |
| Volume 组件 | ✅ | `Volume.sl`：profile/isGlobal/priority（值大者覆盖优先）/weight/blendDistance/influenceBounds + `weightAt(camPos)`（范围内满权重、外扩段线性衰减、范围外 0；straight-line 方法）；**SceneImporter 支持 `Volume` 场景组件** |
| C 混合核心 | ✅ v1.1 | `sle_volume_blend(inPtr, count, outPtr)`：稳定插入排序（全局优先 → priority 升序 → 距离升序）+ 掩码字段 `lerp(cur, v, weight)`、tonemap 枚举覆盖不插值；块布局 **24 float/Volume**、输出 11 float（sle_engine.c 头注释）；中性暗角 = 0 |
| VolumeStack + System | ✅ v1.1 | `VolumeStack.sl`（11 字段 + contributing + hasEffect）+ `system/VolumeSystem.compute(scene, camPos)`（显式栈收集 + 平行数组 + Memory 组块 → C → 解块；诊断 lastCollected/lastCulled） |
| 下发 Render | ✅ v1.1 | `RenderSystem.applyPost(st)` → 13 float 参数块 → `pipe.setPostParams(ptr)`（contributing=0 → 关闭后处理；grainSeed = 管线帧计数）；**`RenderSystem.volumeSystem` 非空时 sync 自动 compute+apply（Unity VolumeManager 同款）** |
| 多相机隔离 | ✅（用法级） | 每相机各自 `compute` 一份栈（§4 参数栈按相机隔离） |
| Tonemapping | ✅（LDR 近似） | mode 1 = Reinhard `c/(1+c)`（LDR 缓冲近似；ACES 需 HDR M5） |
| Bloom/DOF/Fog | ❌ 存参数不下发 | 需 Render HDR 中间缓冲（M5）；`unsupportedCount` 防误判 |
| 渲染库着色器 | ✅ v1.1 | `slr_pipeline_set_post_params`（13 float 块）+ GL/GLES FS_POST 全量消费（中性值 = 旧三参行为逐位一致）；VK/D3D11 只解四参（SPIR-V/DXBC 重产 M5） |

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

---

## 8. v1.2 实现记录（2026-11-20，AA + MotionVectors）

### 8.1 C 渲染库改动

| 项 | 落点 | 说明 |
|---|---|---|
| FFI 导出 | `slr_pipeline_set_aa(p, msaa, fxaaOn, fxaaSpan)` / `slr_pipeline_set_motion(p, on)` / `slr_pipeline_output_motion_texture(p, dst)` | `vm_sl_render.h` 声明表登记（漏登记 = FFI 静默 false）；setAa 返回实际生效采样数 |
| 参数块 | `set_post_params` 13→16 float（尾部 `[13]fxaaOn [14]fxaaSpanMax`） | 命令回放 `sl_cmd.c` POST_PROCESS 按 16 组块；旧 13 索引不变 |
| 程序槽 | `SLR_PROG_MOTION=8`（插在 PHONG_TEX 与 GEN_BASE 之间），GEN_BASE 8→9 | 四后端 make_shared 同步；SL 侧 `PROG_MOTION=8 / PROG_GEN_BASE=9` 同步 |
| FXAA | FS_POST 内嵌函数（GL/GLES ESSL + D3D11 HLSL 运行期编译） | luma 边缘检测 + 方向 clamp + 5 点混合；**独立于 color-adjustments enable**（enabled=0 走中性色链 + FXAA，enabled=0 且 FXAA=0 仍走 BLIT 逐位旧行为）；VK 冻结 SPIR-V 不消费 |
| MSAA | `target_create_ms` / `target_resolve` vtable 加槽（GL/GLES/D3D11 实现，VK NULL） | GL 多采样纹理 + blit；GLES ES3.0 无 multitexture → 多采样 RB + blit（destroy 按 samples 分流删 RB）；D3D11 TEXTURE2MS RTV + ResolveSubresource；rt_scene 重建走 make_targets，阶段 11 先 resolve 再后处理 |
| MotionVectors | `upload_perdraw_prev` vtable 加槽（GL/GLES 实现，D3D11/VK NULL） | PerDrawPrev UBO 绑定点 2（4KB mat4×64）；`SlrPerDraw` 加 prev 矩阵 + obj_prev_valid，每帧阶段 10 快照；阶段 9 尾以 `PROG_MOTION` 重绘所有绘制项输出 top-down RGBA8 速度图（RG = NDC 位移×0.5+0.5）；无上帧位置记 0 |
| 统计 | `STAT_MV_ENABLED=18 / STAT_MSAA_SAMPLES=19 / STAT_FXAA=20` | 调用方可读实际生效状态（后端回退可见） |

### 8.2 引擎与测试

- `RenderSystem` 三门面：`setAa(Int32,Int32,Float32)` / `setMotionVectors(Int32)` / `readMotionVectors(Int64)`；跨模块只传标量/Int64 句柄（避免命名空间冲突与复杂参数绑定）。
- RenderTest 新增 `RenderTestPhasesF.sl`（priority 11）挂 `runAa` / `runMotion` 两相位，main 汇总 PASS。
- 回归结果：Phase AA 748 FXAA 边缘变化像素 / 384 MSAA 4x 变化像素 / 恢复全关逐位一致；Phase MV 静止 (127,127)、+x (153,127)、-x 102、关闭后回读 false。

### 8.3 本次排查记录（存量问题，非本次引入）

- 全套件中 GL 主流程 `SHADOW2`（S_in=255 而非 213）与 `CSM` 稳定 FAIL，但 D3D11 / GLES 后端同断言 PASS。二分实验（禁 MOTION program / PerDrawPrev UBO / FXAA 段、跳过后端切换纯 GL 直跑）均无法消除。
- **决定性对照：用本次改动前的 Release dll（2026-11-19）跑同一 slb，GL shadow 同样 S_in=255 FAIL** → 判定为 11-19 前后既有的 GL 后端 shadow map 存量回归，与本次 AA/MV 改动无关。未在本轮修复，登记待专项。
- 坑：vtable 加槽后必须 `/t:Rebuild` 全后端；spm 自愈会用 zip 覆盖已安装 dll，slb + dll + zip 必须同批重打（四处 zip + 两个已安装目录 + 7 个 dll 槽位）。
- 坑：MSVC 对 GLES 的 `GL_READ_FRAMEBUFFER` 宏未定义（自定义宏表需补 ES3.0 常量）；D3D11 `D3D11_TEX2DMS_RTV` 无 `FirstSlice` 成员。

---

## 9. v1.3 实现记录（2026-11-20，TAA 时域抗锯齿）

### 9.1 算法与数据流

```
阶段 9  几何 + motion pass（速度图 RG = NDC 位移*0.5+0.5）
阶段 10 上帧变换快照
阶段 10.5 TAA：
   src = MSAA resolve 后颜色（若 MSAA 开）
   decodedVel = velocity.rg * 2 - 1
   prevUv = uv - decodedVel * 0.5           （NDC→UV 半幅）
   histClamped = clamp(history[prevUv], min(3×3 cur), max(3×3 cur))
   out = mix(histClamped, cur, blend)        （blend = 当前帧权重，默认 0.1）
   history ping-pong：写 hist[1-idx]，读 hist[idx]，交换；reset=1 首帧直出 cur
阶段 11 后处理（FXAA / Color Adjustments）消费 TAA 输出
```

邻域 clamp 是防鬼影关键：物体移动/消失时当前帧 3×3 邻域不含历史颜色，clamp 将其拉回当前色域——代价是剧烈颜色跳变无时域平滑（预期行为）。

### 9.2 后端与回退

| 后端 | taa_resolve | 说明 |
|---|---|---|
| GL / GLES | ✅ | 独立 FS_TAA 程序（VS_FULL 复用），sampler 单元 0=cur 1=vel 2=hist，uniform blend/reset/texel |
| D3D11 | 指针已实现但管线拒绝 | PS_TAA + b5 TaaParams + t0/t1/t2 SRV 已就绪；但 D3D11 无 `upload_perdraw_prev`（motion 不支持 → 无速度图），set_taa 返回 0。待 motion pass 专项后开放 |
| VK | NULL | SPIR-V 冻结无重投影 shader，set_taa 返回 0 |

### 9.3 验证结果与坑

- Phase TAA 全绿：开关统计（STAT_TAA=1 + motion 自动开）、静止 8 帧平坦区逐位一致（边缘 468/16384 像素 ±2 舍入噪声，来自额外纹理采样 + float mix）、移动帧速度 R=153 重投影输入就绪、MSAA 4x + TAA 组合、关闭零回归。
- 坑：`rt_taa_cur` 是 `rt_taa_hist[write_idx]` 的别名——`pipeline_release_targets` 若同时销毁二者会**双重释放**（setAa 重建目标的 MSAA+TAA 组合阶段崩溃），修复为只销毁 hist[0]/hist[1]。
- 坑：vtable 加槽必须 `/t:Rebuild` 全后端；spm 自愈 zip 与已安装目录的 slb/dll 必须同批重打（本轮 4 zip + 2 已安装目录 + 7 dll 槽位）。

---

## 10. v1.4 实现记录（2026-11-20，Motion Blur 动态模糊）

### 10.1 设计取舍

**不改 `post_process` vtable 签名**——历史上改该签名曾导致四后端 obj 增量混链崩溃（`doc/14` v1.1 坑①）。改为 vtable 尾部追加独立 `motion_blur(dst, src, vel, w, h, scale, samples)` 槽，管线放在阶段 10.6（TAA 后、阶段 11 前），输出 rt_mb 供 post 消费。逻辑上仍属后处理链第一环（FXAA/调色之前）。

### 10.2 算法

```
velocity = vel.rg*2-1（NDC 逐帧位移）
offset = velocity * 0.5 * scale          （NDC→UV 半幅 × 倍率）
快速路径：|velocity| ≈ 0 → 直出 src（静止像素零模糊，且无 16-tap 舍入噪声）
否则：for i in [0,samples): acc += src(uv + offset*(i/(samples-1) - 0.5))
out = acc / samples                       （对称快门， Samples 钳 4..16）
```

### 10.3 验证与边界

- Phase MB：开关/统计、静止中心与背景逐位一致（边缘 1px 过渡带 256 px 有邻色抹入——**运动模糊正常行为**，速度残差导致）、运动帧速度 R=150 + 模糊 diff=256、scale 0 对照、关闭零回归。全套件 EXIT=0；SimGameEngine 1009 PASS / 33 FAIL 存量不变。
- 后端：GL/GLES 实现；D3D11/VK 无速度图（无 `upload_perdraw_prev`），`set_motion_blur` 返回 0——与 TAA 同边界，待 D3D11 motion pass 专项后统一开放。
- 与 TAA 可叠加：`setTaa(1,...)` + `setMotionBlur(1,...)` → 先稳定边缘再拖影；二者都自动打开 motion 且共享同一张速度图。
