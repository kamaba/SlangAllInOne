# SimGameEngine · UI 画布两模式与图层叠加（使用者文档）

> 读者 = 写 SL 代码、想给游戏加 UI 画布的人。只写规则、示例、方法签名与已知坑；
> 引擎内部实现见 `SimGameEngine/doc/08-UI节点与事件.md` §8。

## 1. 两种渲染模式

参考 Unity Canvas 的 `RenderMode`：

| 模式 | 常量 | 怎么用 | 要不要相机 |
|---|---|---|---|
| 系统叠加 | `UICanvas.MODE_SCREEN_OVERLAY`（0，默认） | 建一个节点挂 `UICanvas`，画面自动盖在最上层 | 不要 |
| 相机赋值 | `UICanvas.MODE_CAMERA`（1） | 在节点上指定一个相机，UI 由该相机渲染，按排序号盖在主画面之上 | 要 |
| 世界空间 | `UICanvas.MODE_WORLD`（2） | 同上，但 UI 按世界坐标摆放 | 要 |

模式 1 就是「相机处理完成后做图层叠加」：排在后面的相机不清掉前一个相机的颜色，
所以它的输出直接叠在主画面上（与 Unity Overlay Camera 一致）。

## 2. 最小用法

```sl
import SimGameEngine;
import SLangRender;

Systems sys = Systems()
sys.init( 1280, 720 )
Scene scene = app.activeScene

# 模式 0：系统叠加（HUD），不需要相机
GameObject hud = scene.createObject( "HUD" )
UICanvas hudCanvas = UICanvas()
hud.addComponent( hudCanvas )

# 模式 1：相机赋值面板
SLang.RenderCamera uiCam = sys.render.pipe().addCamera( 0 )
GameObject panel = scene.createObject( "PanelCanvas" )
UICanvas cv = UICanvas()
cv.setRenderMode( UICanvas.MODE_CAMERA )
cv.setCamera( uiCam )
cv.setLayer( 30 )
cv.setSortingOrder( 3 )
cv.setClearFlags( UICanvas.FLAGS_DEPTH )   # 只清深度 = 叠在主画面之上
panel.addComponent( cv )

# 每帧顺序（固定）：sync → setupCanvas → frame
sys.sync( scene, time )
sys.setupCanvas( scene )
sys.frame( time, dstPtr )
```

## 3. 可用方法与签名

### UICanvas（挂在管理节点上的组件）

| 签名 | 说明 |
|---|---|
| `void setRenderMode(Int32 mode)` | 0 系统叠加 / 1 相机赋值 / 2 世界空间；越界不改值 |
| `void setCamera(SLang.RenderCamera cam)` | 模式 1/2 指定相机 |
| `void setLayer(Int32 layer)` | 画布独占层 0..31；模式 0 会被引擎强制回 31 |
| `void setSortingOrder(Int32 order)` | 越小越先画；映射为相机深度 `20 + order` |
| `void setClearFlags(Int32 flags)` | 1 清颜色 / 2 清深度 / 3 都清；默认 2（保留底图） |
| `void setPlaneDistance(Float32 d)` | 世界空间的平面距离 |
| `void setReferenceSize(Float32 w, Float32 h)` | 设计分辨率（世界空间视域基准） |
| `void setScaleFactor(Float32 s)` | 缩放系数 |
| `void setPixelPerfect(bool v)` | 像素完美开关 |
| `Int32 getRenderMode()` / `Int32 getLayer()` | 读取 |
| `bool hasCamera()` | 相机是否已赋值且有效 |

### Systems / UICanvasSystem（宿主侧）

| 签名 | 说明 |
|---|---|
| `Int32 setupCanvas(Scene scene)` | 收集场景里的画布并落到相机；返回成功配置数，-1 = 渲染未就绪 |
| `bool frame(Float32 time, Int64 dstPtr)` | 出帧到 RGBA8 原生块 |
| `bool compositeLayer(Int64 dst, Int64 layer, Int32 w, Int32 h, Float32 alpha, Int32 mode)` | 把另一张相机输出图层合成到已出帧的图像 |

`UICanvasSystem` 的常量：`BLEND_ALPHA=0`（常规 alpha）、`BLEND_ADD=1`（加法）、
`BLEND_MULTIPLY=2`（正片叠底）；`UICanvas` 的清屏常量：`FLAGS_NONE=0`、`FLAGS_COLOR=1`、
`FLAGS_DEPTH=2`、`FLAGS_ALL=3`。

## 4. 独立图层叠加（相机输出回贴）

若需要把某个相机/离屏结果**当作一张图**贴回主画面，先各自出帧到两个 RGBA8 块，再合成：

```sl
Int64 mainBuf = Memory.alloc( 1280 * 720 * 4 )
Int64 layerBuf = Memory.alloc( 1280 * 720 * 4 )
sys.frame( time, mainBuf )                 # 主画面
otherSys.frame( time, layerBuf )           # 另一台相机/离屏管线的输出
sys.compositeLayer( mainBuf, layerBuf, 1280, 720, 1.0f, UICanvasSystem.BLEND_ALPHA )
# mainBuf 现在是合成后的最终图像，拿去上屏
Memory.free( mainBuf )
Memory.free( layerBuf )
```

`alpha` 取 0..1（0 = 完全不改主画面，1 = 按模式完全合成）；越界会被拒绝。

## 5. 使用技巧与已知坑

1. `setupCanvas` 必须放在 `sync` 之后、`frame` 之前——相机参数要在渲染前写定，否则本帧不生效。
2. 模式 1/2 忘了 `setCamera`：不会崩，该画布被跳过，原因写在画布的 `lastError` 里。
3. 多画布叠放：先按 `renderMode` 分组（系统叠加先画、相机层次之、世界空间最后），
   同组按 `sortingOrder` 升序；想让某面板在最上层就给它更大的 `sortingOrder`。
4. `clearFlags` 用默认值 2（只清深度）才能保留下层画面；设成 3 会把下面的内容清掉。
5. `compositeLayer` 的两块缓冲都必须是 top-down RGBA8、尺寸一致，否则合成失败。
6. 常量是静态字段，跨方法当参数传递时先存到局部变量，不要直接写在实参位置。
