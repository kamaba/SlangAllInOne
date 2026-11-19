import Core;
import Std;
import Math;
import SLangRender;

# ============================================================================
# UICanvas — UI 管理节点组件（Unity Canvas 形态，doc/08 §8）
# ----------------------------------------------------------------------------
# 挂到 GameObject 上即成为「一个 UI 画布管理节点」。两种渲染模式：
#   MODE_SCREEN_OVERLAY (0) —— 系统叠加层（Unity Screen Space - Overlay）。
#       引擎自动挂专用 UI 相机（layer 31 独占、depth 靠后、只清深度），
#       UI 网格由 FairyUIRenderer 提交后天然盖在 3D 画面之上，无需相机赋值。
#   MODE_CAMERA (1) —— 相机赋值层（Unity Screen Space - Camera / Camera Stack
#       Overlay）。必须给本节点赋值 targetCamera；引擎层按 sortingOrder 把
#       该相机编排进相机栈，霓制掩码收敛到 uiLayer，清屏标志由 clearFlags
#       控制（默认位 2 = 只清深度 → 上一个相机的颜色输出被保留，从而实现
#       「相机处理完成后再做图层叠加」）。
#   MODE_WORLD (2) —— 世界空间层（Unity World Space 轻量版）。同样要相机赋值，
#       但 extents 按 referenceWidth/Height / scaleFactor 换算成世界单位，
#       UI 节点按普通 Transform 摆放在世界坐标系中。
#
# 本类只存数据与 setter；模式落地由 system/UICanvasSystem.configure 统一完成
# （避免在 Behaviour 子类里做跨模块相机操作与循环字段读，doc/10 §6）。
# 注意：常量是 static 字段，作实参时先落局部变量（不能直传 static 字段）。
# ============================================================================
public class UICanvas extends Behaviour
{
    public static Int32 MODE_SCREEN_OVERLAY = 0
    public static Int32 MODE_CAMERA = 1
    public static Int32 MODE_WORLD = 2

    public static Int32 FLAGS_NONE = 0
    public static Int32 FLAGS_COLOR = 1
    public static Int32 FLAGS_DEPTH = 2
    public static Int32 FLAGS_ALL = 3

    # 渲染模式（0 系统叠加 / 1 相机赋值 / 2 世界空间）
    public Int32 renderMode = 0
    # 相机模式的目标相机（跨模块门面，单字段持有合法；RenderSystem._uiCam 同款）
    public SLang.RenderCamera camera = null
    # 本画布独占的渲染层（默认 31，与系统叠加相机配套）
    public Int32 uiLayer = 31
    # 相机栈排序号（越小越先画；引擎层映射为相机 depth = 20 + sortingOrder）
    public Int32 sortingOrder = 0
    # 世界空间相机的平面距离（仅模式 2 消费）
    public Float32 planeDistance = 5.0f
    # 设计分辨率 / 缩放（模式 1/2 的视域换算）
    public Float32 referenceWidth = 1280.0f
    public Float32 referenceHeight = 720.0f
    public Float32 scaleFactor = 1.0f
    # 图层叠加的清屏标志（默认只清深度 = 保留前一相机颜色输出）
    public Int32 clearFlags = 2
    # 像素完美（缩放取整开关，供宿主布局侧消费）
    public bool pixelPerfect = false
    # 诊断信息
    public string lastError = ""

    public void _init_()
    {
        this.renderMode = 0
        this.camera = null
        this.uiLayer = 31
        this.sortingOrder = 0
        this.planeDistance = 5.0f
        this.referenceWidth = 1280.0f
        this.referenceHeight = 720.0f
        this.scaleFactor = 1.0f
        this.clearFlags = 2
        this.pixelPerfect = false
        this.lastError = ""
    }

    public void setRenderMode( Int32 mode )
    {
        if mode < 0 || mode > 2
        {
            this.lastError = "invalid render mode"
            ret
        }
        this.renderMode = mode
        this.lastError = ""
    }

    public void setCamera( SLang.RenderCamera cam )
    {
        this.camera = cam
    }

    public void setLayer( Int32 layer )
    {
        if layer < 0 || layer > 31
        {
            this.lastError = "invalid ui layer"
            ret
        }
        this.uiLayer = layer
        this.lastError = ""
    }

    public void setSortingOrder( Int32 order )
    {
        this.sortingOrder = order
    }

    public void setPlaneDistance( Float32 distance )
    {
        if distance <= 0.0f
        {
            this.lastError = "invalid plane distance"
            ret
        }
        this.planeDistance = distance
        this.lastError = ""
    }

    public void setReferenceSize( Float32 width, Float32 height )
    {
        if width <= 0.0f || height <= 0.0f
        {
            this.lastError = "invalid reference size"
            ret
        }
        this.referenceWidth = width
        this.referenceHeight = height
        this.lastError = ""
    }

    public void setScaleFactor( Float32 scale )
    {
        if scale <= 0.0f
        {
            this.lastError = "invalid scale factor"
            ret
        }
        this.scaleFactor = scale
        this.lastError = ""
    }

    public void setClearFlags( Int32 flags )
    {
        if flags < 0 || flags > 3
        {
            this.lastError = "invalid clear flags"
            ret
        }
        this.clearFlags = flags
        this.lastError = ""
    }

    public void setPixelPerfect( bool value )
    {
        this.pixelPerfect = value
    }

    public Int32 getRenderMode()
    {
        ret this.renderMode
    }

    public Int32 getLayer()
    {
        ret this.uiLayer
    }

    public bool hasCamera()
    {
        if this.camera == null
        {
            ret false
        }
        ret this.camera.isValid
    }

    override string toString()
    {
        ret String.toFormat( "UICanvas(mode={0}, layer={1}, order={2}, camera={3})",
            this.renderMode.toString(), this.uiLayer.toString(),
            this.sortingOrder.toString(), this.hasCamera().toString() )
    }
}
