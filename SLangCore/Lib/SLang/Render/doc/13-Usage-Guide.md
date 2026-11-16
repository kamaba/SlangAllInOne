# 13 — SLangRender 完整使用指南

> 所有示例均取自 RenderTest（13 阶段端到端验证）中实际运行过的写法。
> 功能边界见 `07-Implemented-Features.md`；各子系统细节见 08~12 号文档。

## 0. 工程接入

1. 模块已在 spm 渠道注册为 `SLangRender`（version 1.0.0）+ `SLangQT`（0.1.0）；
   测试工程 jsonc 的 `references` 段声明：
   ```json
   { "type": "module", "name": "SLangQT", "channel": "official", "version": "0.1.0" },
   { "type": "module", "name": "SLangRender", "channel": "official", "version": "1.0.0" }
   ```
2. 源码 `import SLangRender;`（QT 显示另需 `import SLangQT;`）；
3. 引擎层 Math 的 `Float32_4x4 / Color` 由 `import Math;` 提供。

## 1. 初始化与后端

```sl
import SLangRender;

public static bool init()
{
    if !SLang.Render.initialize()
    {
        Console.println( "render init failed: " + SLang.Render.errorString() )
        ret false
    }
    # 可选切换后端（须在创建管线前）："gl"/"d3d11"/"vk"/"gles"
    # SLang.Render.initializeBackend( "vk" )
    ret true
}
```

## 2. 场景 A：对象渲染（最常用路径）

```sl
Int32 w = 256
Int32 h = 256
Int64 pixels = Memory.alloc( w * h * 4 )               # 回读缓冲 RGBA8

SLang.RenderPipeline pipe = SLang.RenderPipeline.create( w, h )

# 画一个色相循环三角 + 一个透明 quad
SLang.RenderObject tri = pipe.addObject( pipe.MESH_TRIANGLE )
tri.setAnimated( pipe.ANIM_HUE_CYCLE, 0.05f )          # layer0 不透明
SLang.RenderObject quad = pipe.addObject( pipe.MESH_QUAD )
quad.layer = 1                                          # queue>=2500 走透明段

pipe.renderFrame( 0.0f, pixels )                        # 完整 13 阶段
# ... label.setPixmapRgba( pixels, w, h ) 或 Memory.readU32 抽样
pipe.destroy()
Memory.free( pixels )
```

要点：

- `renderFrame(t,pixels)` 每帧调用；`t` 秒驱动动画；
- `pipe.runStages(t, pixels)` 与其等价，但按 13 阶段逐步驱动（调试用）；
- 帧统计：`pipe.stat( pipe.STAT_DRAW_CALLS )` 等（见 `09` §3）。

## 3. 场景 B：QT 窗口上屏

```sl
import SLangQT;

SLang.QApplication app = SLang.QApplication()
SLang.QLabel label = SLang.QLabel( "SLangRender demo", 296, 372 )
label.show()
SLang.QTimer timer = SLang.QTimer( 16 )      # ~60fps 帧循环
timer.onTick = onTick                        # 回调里 renderFrame + setPixmapRgba
app.exec()
```

```sl
public static void onTick()
{
    if _pipe.runStages( _t, _pixels )
    {
        _label.setPixmapRgba( _pixels, _w, _h )   # RGBA8 块直接上屏
    }
    _t = _t + 0.033f
}
```

注意：`initializeBackend` 切换后端后，管线/纹理句柄失效，需全量重建场景
（见 `08` §5）。

## 4. 场景 C：多相机合成

```sl
SLang.RenderCamera cam1 = SLang.RenderCamera()   # 默认相机已有（depth 0）
cam1.depth = 10                                  # depth 升序逐台渲染
cam1.cullingMask = ( 1 << 2 )                    # 只画 layer2
cam1.viewportX = 128; cam1.viewportY = 0
cam1.viewportW = 128; cam1.viewportH = 256       # 右半屏
cam1.clearColor = Color( 0.0f, 0.2f, 0.0f, 1.0f )
cam1.clearFlags = SLang.RenderPipeline.CLEAR_COLOR | SLang.RenderPipeline.CLEAR_DEPTH
```

后渲染相机覆盖先渲染相机；`cam1.enabled = false` 后其区域回到下层相机画面。

## 5. 场景 D：贴图（程序纹理 / 图片文件）

```sl
# 程序纹理：RGBA8 内存块 → 纹理
Int64 texPtr = Memory.alloc( 64 * 64 * 4 )
# ... Memory.writeU32 填充像素 ...
RenderTexture tex = RenderTexture.createRgba( texPtr, 64, 64 )
tex.handle            # 命令流 setTexture / 材质路由用
tex.destroy()
Memory.free( texPtr )

# 图片文件：WIC 解码（png/jpg）
RenderTexture img = RenderTexture.loadFile( "test_image.png" )
```

## 6. 场景 E：命令流直连（CommandBuffer）

适合明确掌控绘制序的路径（等价 13 阶段中的核心绘制段）：

```sl
CommandBuffer cmd = CommandBuffer()
cmd.begin()
cmd.setRenderTargets( pipe.TARGET_SCENE, 0, 0, 256, 256, 3, Color( 0.06f, 0.06f, 0.10f, 1.0f ) )
cmd.setTexture( 0, tex.handle )
cmd.setPerDraw( 0, triMvp, Color( 1.0f, 0.0f, 0.0f, 1.0f ) )     # 列主序 MVP
cmd.drawItem( pipe.PROG_PFLAT, 0, pipe.MESH_TRIANGLE, 0, 0, 2000, 0.0f )
cmd.drawItem( pipe.PROG_PTEX,  1, pipe.MESH_QUAD,     0, 1, 3000, 0.5f )
cmd.postProcess( 0, 1.0f, 1.0f, 1.0f )
cmd.blitFinal()
cmd.readback( pixels )
cmd.end()

pipe.executeCommandBuffer( cmd )    # 单流整包提交
```

规则：

- 透明分界 `queue >= 2500`；段内排序自动完成（`sortDrawItems`，见 `10` §4）；
- **一帧内所有 setTexture/setPerDraw/drawItem 必须在同一条流**（C 侧每流
  重置状态）；`cb.clear()` 后可复用录制。

## 7. 场景 F：Pass 序列（P1，推荐结构化路径）

```sl
ScriptableRenderContext ctx = ScriptableRenderContext()
ctx.pipeline = pipe

# 可视集快照（P0 数据层）
CullingData cull = CullingData()
cull.addItem( pipe.PROG_PFLAT, 0, pipe.MESH_TRIANGLE, 0, 0, 2000, 0.0f )   # 不透明
cull.addItem( pipe.PROG_PTEX,  1, pipe.MESH_QUAD,     0, 1, 3000, 0.5f )   # 透明

OpaquePass opaque = OpaquePass()
opaque.culling = cull
opaque.viewportWidth = 256; opaque.viewportHeight = 256
opaque.clearTargetColor = true; opaque.clearTargetDepth = true
opaque.clearColor = Color( 0.06f, 0.06f, 0.10f, 1.0f )

TransparentPass transp = TransparentPass()
transp.culling = cull

PostProcessPass post = PostProcessPass()      # postEnabled=false 时不录命令
BlitPass blit = BlitPass()
blit.blitReadbackPtr = pixels                 # 最终回读到 pixels

ctx.addPass( opaque )
ctx.addPass( transp )
ctx.addPass( post )
ctx.addPass( blit )

# 帧级共享状态（贴图槽 / PerDraw 槽）预录进同一流
CommandBuffer setup = CommandBuffer()
setup.begin()
setup.setTexture( 0, tex.handle )
setup.setPerDraw( 0, triMvp, Color( 1.0f, 0.0f, 0.0f, 1.0f ) )
setup.setPerDraw( 1, texMvp, Color( 1.0f, 1.0f, 1.0f, 0.85f ) )
setup.end()
ctx.beginPassRecording( setup )

ctx.submitPasses()                            # 单流整包提交
```

自定义 Pass：继承 `RenderPass`，无参 `_init_()` 手动设 `passType` 等字段，
复用基类 `execute` 派发（见 `11` §3）。

## 8. 场景 G：动态网格（CPU 变换 + uploadMesh）

```sl
Int64 verts = Memory.alloc( 4096 * 16 )   # 每顶点 16B：x,y,u,v（Float32*4）
# ... writeF32 填 NDC 顶点（透视除法后）...
pipe.uploadMesh( 0, verts, vertCount )    # 槽 0..3，每帧可整块重传

SLang.RenderObject obj = pipe.addObject( pipe.MESH_CUSTOM + 0 )   # meshKind=4
```

网格数学库辅助：`Mesh.triangle / quad / cube(size)`（顶点 + 面表 + 法线），
配合 `Float32_4x4.rotationX/Y(t)` / `transformPoint` 做模型变换。

## 9. 灯光

```sl
Light lamp = Light()
lamp.type = 2                      # 0 平行光 / 1 点光 / 2 聚光
lamp.posX = 0.0f; lamp.posY = 0.8f
lamp.intensity = 1.6f
lamp.spotAngle = 30.0f
lamp.castShadow = true
lamp.applyTo( pipe, 0 )            # 槽位 0..N，每帧重写即可
```

配合固化 shader 效果槽（Lambert/Phong/Blinn-Phong/NormalMap/Toon），
高光/阴影实时跟随灯（见 `09` §5-6）。

## 10. 资源管理 checklist

- `pipe.destroy()` 释放管线（含渲染目标）；纹理 `tex.destroy()`；
- `Memory.free` 释放自分配缓冲（pixels / texPtr / verts）；
- 切后端 = 全部句柄失效后重建；
- 资源余量经 `RenderEnvironment.query()` 监控（见 `12` §3）。

## 11. 排障速查

| 症状 | 排查点 |
|---|---|
| init 返回 false | `errorString()`；vk/gles 需运行库（见 `08` §1） |
| 画面全黑 | clearFlags/clearColor；TARGET 槽位；透明队列是否 ≥2500 |
| 透明物叠序不对 | z 值方向（透明段 z 降序后→前）；同流提交契约 |
| drawItem 无效果 | PerDraw 槽与 drawItem slot 一致；贴图槽 setTexture |
| 统计全 0 | 命令流是否整包提交成功（`executeCommandBuffer` 门槛，见 `10` §5） |
| QT 无窗口 | Phase B 仅最后阶段出现 30 秒小窗（296×372），查任务栏/副屏 |
| 模块加载失败 | spm md5 不一致触发重装；确认 `modules\SLangRender\` 三文件 + spm.json 完整 |
