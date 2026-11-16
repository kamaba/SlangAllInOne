# 09 — 13 阶段渲染管线（已实现）

> 对应实现：`Pipeline.sl`（SL 门面，薄绑定）+ `sl_render_lib.c`（全部管线逻辑）。
> 一帧渲染 = 13 个显式阶段；`renderFrame(t,pixels)` 与 `runStages(t,pixels)` 等价
> （后者由 SL 侧逐阶段驱动，Phase A2 验证两者输出一致）。

## 1. 阶段表

| # | 阶段 | 常量 | 内容 |
|---|---|---|---|
| 1 | beginFrame | `STAGE_BEGIN_FRAME` | 绑定场景 FBO、清屏、帧计数 |
| 2 | prepareMaterials | `STAGE_PREPARE_MATERIALS` | 着色器/采样器就绪 |
| 3 | earlyUpdate | `STAGE_EARLY_UPDATE` | 对象动画推进（如色相循环） |
| 4 | cullLayers | `STAGE_CULL_LAYERS` | cullingMask 分层 + 视域剔除 |
| 5 | assembleLayerData | `STAGE_ASSEMBLE_LAYER_DATA` | 排序绘制列表 + MVP + 分块 |
| 6 | uploadRenderData | `STAGE_UPLOAD_RENDER_DATA` | PerDraw UBO 上传 |
| 7 | renderShaderChunks | `STAGE_RENDER_SHADER_CHUNKS` | 不透明段按 shader 合批 |
| 8 | updateCoreTime | `STAGE_UPDATE_CORE_TIME` | 帧间隔推进 |
| 9 | renderShaderSegments | `STAGE_RENDER_SHADER_SEGMENTS` | 透明段后→前混合 |
| 10 | assembleRenderedLayers | `STAGE_ASSEMBLE_RENDERED_LAYERS` | 图层位掩码/状态复位 |
| 11 | postProcess | `STAGE_POST_PROCESS` | 亮度/饱和度/暗角全屏 pass |
| 12 | integrateLayers | `STAGE_INTEGRATE_LAYERS` | 合成最终 renderTexture |
| 13 | outputRenderTexture | `STAGE_OUTPUT_RENDER_TEXTURE` | RGBA8 回读 |

## 2. RenderPipeline 门面

```sl
SLang.RenderPipeline pipe = SLang.RenderPipeline.create( 256, 256 )
SLang.RenderObject obj  = pipe.addObject( pipe.MESH_TRIANGLE )   # 内建网格槽
Int32 stat = pipe.stat( pipe.STAT_DRAW_CALLS )                   # 帧统计
pipe.uploadMesh( 0, vertPtr, vertCount )                         # 动态网格槽 0..3
pipe.renderFrame( t, pixels )      # pixels = Memory.alloc(w*h*4)
pipe.runStages( t, pixels )        # 逐阶段驱动（调试/教学用）
pipe.destroy()
```

对象常量：`MESH_TRIANGLE=0 / MESH_QUAD=1 / MESH_CUSTOM=4(+slot 4..7)`；
动画：`ANIM_NONE=0 / ANIM_HUE_CYCLE=1`（`obj.setAnimated(id, speed)`）。

## 3. 统计项（pipe.stat(id)）

`STAT_FRAME=0 / STAT_VISIBLE=1 / STAT_CULLED=2 / STAT_DRAW_CALLS=3 /
STAT_OPAQUE_DRAWS=4 / STAT_TRANSPARENT_DRAWS=5 / STAT_POST_ENABLED=6 /
STAT_LAST_STAGE=7 / STAT_OBJECT_COUNT=8 / STAT_CHUNK_COUNT=9 /
STAT_LAYERS_MASK=10 / STAT_UPLOAD_COUNT=11 / STAT_TIME_MS=12 / STAT_DT_MS=13 /
STAT_TEXTURE_COUNT=14 / STAT_PROGRAM_SWITCHES=15 / STAT_CAMERA_COUNT=16`

## 4. 对象与相机

- **RenderObject**：`layer`（分层剔除掩码）、`meshKind`、`setAnimated`、
  颜色/队列字段；`queue >= 2500` 走透明段。
- **RenderCamera**（Phase A3）：多相机按 `depth` 升序逐台渲染；
  相机可设 `viewport` 子矩形 + 独立清屏色 + `cullingMask`（仅画指定 layer），
  相机覆盖关系 = 后渲染者覆盖先渲染者。
- **clearFlags**：`CLEAR_COLOR=1 / CLEAR_DEPTH=2`（可按位或）。

## 5. 固化 shader（gen 槽 8..17，Phase G）

5 效果 × flat/tex 变体：Lambert / Phong / Blinn-Phong / NormalMap / Toon。
效果参数经对象材质路由下发；验收覆盖：退化等价（uSpec=0）、
Blinn/Phong 高光手算值、Toon 阶梯值、NormalMap 零扰动等价、
VK 后端固化一致性复检。

## 6. 灯光（Camera\Light.sl，Phase L）

```sl
Light lamp = Light()
lamp.type   = 2              # 0 平行光 / 1 点光 / 2 聚光
lamp.posX = 0.0f; lamp.posY = 0.8f
lamp.intensity = 1.6f
lamp.spotAngle = 30.0f
lamp.castShadow = true; lamp.shadowStrength = 1.0f
lamp.applyTo( pipe, 0 )      # 写入光照槽 0..N（每帧可重写）
```

点光衰减 `attenuation(dist)`、聚光锥角 `spotAttenuation(point)` 由 SL 数学实现，
`applyTo` 下发到 C 侧光照槽，阴影/高光实时跟随。
