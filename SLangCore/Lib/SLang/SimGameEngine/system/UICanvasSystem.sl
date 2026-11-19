import Core;
import Std;
import Math;
import SLangRender;

# ============================================================================
# UICanvasSystem — UI 图层编排 / 引擎层叠加（doc/08 §8）
# ----------------------------------------------------------------------------
# 职责（Unity Canvas + Camera Stack 的引擎层对应物）：
#   1. collect(scene) —— 显式栈遍历场景，收集激活节点上的 UICanvas，按
#      (renderMode, sortingOrder, 树序) 稳定排序得到绘制次序。
#   2. configure(rs) —— 把每个画布的语义落到渲染管线相机：
#      · MODE_SCREEN_OVERLAY：复用 RenderSystem 的系统 UI 相机（layer 31、
#        depth=10、clearFlags=2 只清深度），画布自身 layer 强制 31；
#      · MODE_CAMERA：用画布赋值的相机，cullMask=1<<uiLayer，
#        depth=20+sortingOrder，clearFlags 由画布控制（默认 2 不清颜色 =
#        上一个相机的颜色保留 → 相机处理后做图层叠加）；
#      · MODE_WORLD：同上但 extents 按 reference/s 换算成世界单位。
#   3. composite(rs, dstPtr, layerPtr, w, h, alpha, mode) —— 引擎层叠加：
#      把一张相机输出 RGBA8 图层按 alpha / 混合模式合成到目标帧缓冲。
#      计算核心在 C（sle_layer_composite），SL 只做参数组块与句柄传递。
#
# 设计约束（doc/10 §6）：跨模块对象字段只整块读写；下标先落局部 Int32；
# 常量先落局部再传参；Behaviour 子类的循环字段读移到 static/system 承载。
# ============================================================================
public class UICanvasSystem
{
    public static Int32 BLEND_ALPHA = 0
    public static Int32 BLEND_ADD = 1
    public static Int32 BLEND_MULTIPLY = 2

    # 收集结果（平行数组，避免跨模块 UI 对象的字段链下标问题）
    List<UICanvas> _canvases = List<UICanvas>( 16 )
    List<Int32> _modes = List<Int32>( 16 )
    List<Int32> _orders = List<Int32>( 16 )
    List<Int32> _layers = List<Int32>( 16 )

    public Int32 canvasCount = 0
    public Int32 overlayCount = 0
    public Int32 cameraCount = 0
    public Int32 worldCount = 0
    public Int32 lastCompositePixels = 0
    public string lastError = ""

    # 上一次 configure 是否真的用到系统 UI 相机（诊断）
    public bool systemCameraUsed = false

    # 系统 UI 相机的 depth / layer / clearFlags（与 RenderSystem.ensureUiCamera 对齐）
    Int32 _systemDepth = 10
    Int32 _systemLayer = 31
    Int32 _systemClearFlags = 2
    Int32 _depthBase = 20

    # ── 场景收集 ────────────────────────────────────────
    public Int32 collect( Scene scene )
    {
        this._canvases.clear()
        this._modes.clear()
        this._orders.clear()
        this._layers.clear()
        this.canvasCount = 0
        this.overlayCount = 0
        this.cameraCount = 0
        this.worldCount = 0
        this.systemCameraUsed = false
        if scene == null
        {
            ret 0
        }
        List<GameObject> stack = List<GameObject>( 16 )
        Int32 ri = scene.rootCount() - 1
        while ri > 0 - 1
        {
            GameObject r = scene.getRoot( ri )
            if r != null
            {
                stack.add( r )
            }
            ri = ri - 1
        }
        while stack.length > 0
        {
            Int32 lastIdx = stack.length - 1
            GameObject cur = stack[lastIdx]
            stack.removeAt( lastIdx )
            if cur.getActiveInHierarchy() && cur.pendingDestroy == false
            {
                UICanvas cv = cur.getComponent<UICanvas>()
                if cv != null
                {
                    Int32 mode = cv.renderMode
                    if mode < 0 || mode > 2
                    {
                        mode = 0
                    }
                    this._canvases.add( cv )
                    this._modes.add( mode )
                    this._orders.add( cv.sortingOrder )
                    this._layers.add( cv.uiLayer )
                    if mode == 0
                    {
                        this.overlayCount = this.overlayCount + 1
                    }
                    elif mode == 1
                    {
                        this.cameraCount = this.cameraCount + 1
                    }
                    else
                    {
                        this.worldCount = this.worldCount + 1
                    }
                }
                Int32 ci = cur.childCount - 1
                while ci > 0 - 1
                {
                    GameObject ch = cur.getChild( ci )
                    if ch != null
                    {
                        stack.add( ch )
                    }
                    ci = ci - 1
                }
            }
        }
        this.canvasCount = this._canvases.length
        if this.canvasCount > 1
        {
            this.sort()
        }
        ret this.canvasCount
    }

    # 稳定插入排序：mode 升序（overlay 先画），同模式按 sortingOrder 升序，
    # 同 order 保持收集序（后绘制 = 树序靠后 = 更上层）。
    void sort()
    {
        List<UICanvas> sc = List<UICanvas>( 0 )
        List<Int32> sm = List<Int32>( 0 )
        List<Int32> so = List<Int32>( 0 )
        List<Int32> sl = List<Int32>( 0 )
        Int32 i = 0
        Int32 n = this._canvases.length
        while i < n
        {
            UICanvas cvi = this._canvases[i]
            Int32 mi = this._modes[i]
            Int32 oi = this._orders[i]
            Int32 li = this._layers[i]
            Int32 pos = sc.length
            Int32 k = sc.length - 1
            while k > 0 - 1
            {
                Int32 ok = so[k]
                Int32 mk = sm[k]
                bool later = false
                if mk > mi
                {
                    later = true
                }
                elif mk == mi
                {
                    if ok > oi
                    {
                        later = true
                    }
                }
                if later
                {
                    pos = k
                    k = k - 1
                }
                else
                {
                    k = 0 - 1
                }
            }
            sc.insert( pos, cvi )
            sm.insert( pos, mi )
            so.insert( pos, oi )
            sl.insert( pos, li )
            i = i + 1
        }
        this._canvases = sc
        this._modes = sm
        this._orders = so
        this._layers = sl
    }

    public UICanvas canvasAt( Int32 index )
    {
        if index < 0 || index >= this._canvases.length
        {
            ret null
        }
        UICanvas c = this._canvases[index]
        ret c
    }

    public Int32 modeAt( Int32 index )
    {
        if index < 0 || index >= this._modes.length
        {
            ret 0 - 1
        }
        Int32 m = this._modes[index]
        ret m
    }

    public Int32 layerAt( Int32 index )
    {
        if index < 0 || index >= this._layers.length
        {
            ret 0 - 1
        }
        Int32 l = this._layers[index]
        ret l
    }

    # ── 相机编排（引擎层模式落地）────────────────────────
    # 返回本次成功配置的画布数。rs 未就绪返回 -1。
    public Int32 configure( RenderSystem rs )
    {
        this.lastError = ""
        if rs == null || rs.ready() == false
        {
            this.lastError = "render system not ready"
            ret 0 - 1
        }
        SLang.RenderPipeline pipe = rs.pipe()
        if pipe == null
        {
            this.lastError = "pipeline not ready"
            ret 0 - 1
        }
        Int32 configured = 0
        Int32 i = 0
        Int32 n = this._canvases.length
        while i < n
        {
            UICanvas cv = this._canvases[i]
            Int32 mode = this._modes[i]
            if cv != null
            {
                if mode == 0
                {
                    # 系统叠加：确保 UI 相机存在，层/深度/清屏由 RenderSystem 统一持有。
                    rs.ensureUiCamera()
                    cv.uiLayer = this._systemLayer
                    cv.clearFlags = this._systemClearFlags
                    this.systemCameraUsed = true
                    configured = configured + 1
                }
                elif mode == 1
                {
                    # 相机赋值：把该相机编排进相机栈（不清颜色 → 叠加在上一相机输出上）
                    if cv.camera != null && cv.camera.isValid
                    {
                        SLang.RenderCamera cam = cv.camera
                        Int32 mask = 1 << cv.uiLayer
                        cam.setCullMask( mask )
                        cam.setDepth( this._depthBase + cv.sortingOrder )
                        cam.setClearFlags( cv.clearFlags )
                        configured = configured + 1
                    }
                    else
                    {
                        cv.lastError = "camera mode requires a valid camera"
                    }
                }
                else
                {
                    # 世界空间：extents 按设计分辨率/缩放换算成世界单位
                    if cv.camera != null && cv.camera.isValid
                    {
                        SLang.RenderCamera cam = cv.camera
                        Int32 mask = 1 << cv.uiLayer
                        Float32 s = cv.scaleFactor
                        if s <= 0.0f
                        {
                            s = 1.0f
                        }
                        Float32 hw = cv.referenceWidth / ( 2.0f * s )
                        Float32 hh = cv.referenceHeight / ( 2.0f * s )
                        cam.setCullMask( mask )
                        cam.setDepth( this._depthBase + cv.sortingOrder )
                        cam.setClearFlags( cv.clearFlags )
                        cam.setExtents( 0.0f - hw, hw, 0.0f - hh, hh )
                        configured = configured + 1
                    }
                    else
                    {
                        cv.lastError = "world mode requires a valid camera"
                    }
                }
            }
            i = i + 1
        }
        ret configured
    }

    # ── 引擎层图层叠加 ──────────────────────────────────
    # dstPtr / layerPtr 均为 top-down RGBA8 缓冲（w*h*4）；pixelCount = w*h。
    # alpha=1 且 mode=BLEND_ALPHA 时 layer 完全覆盖 dst；mode=BLEND_ADD 加法；
    # mode=BLEND_MULTIPLY 正片叠底。计算在 C（sle_layer_composite）。
    public bool composite( Int64 dstPtr, Int64 layerPtr, Int32 w, Int32 h, Float32 alpha, Int32 mode )
    {
        this.lastError = ""
        if dstPtr == 0 || layerPtr == 0 || w <= 0 || h <= 0
        {
            this.lastError = "invalid composite buffers"
            ret false
        }
        if alpha < 0.0f || alpha > 1.0f
        {
            this.lastError = "invalid composite alpha"
            ret false
        }
        if mode < 0 || mode > 2
        {
            this.lastError = "invalid composite mode"
            ret false
        }
        Int32 pixels = w * h
        Int32 n = EngineFfi.libLayerComposite( dstPtr, layerPtr, pixels, alpha, mode )
        this.lastCompositePixels = n
        if n != pixels
        {
            this.lastError = "composite core rejected buffers"
            ret false
        }
        ret true
    }
}
