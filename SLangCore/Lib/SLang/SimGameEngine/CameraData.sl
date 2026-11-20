import Core;
import Std;
import Math;
import SLangRender;

# ============================================================================
# CameraData — 相机数据组件（Unity Camera 形态，doc/06 §相机）
# ----------------------------------------------------------------------------
# 挂在 Camera（extends GameObject）节点上的数据组件，持有投影 / 裁剪 /
# 层级 / 清屏等相机参数。本类只放「不依赖节点 Transform」的纯计算：
#   投影矩阵、裁剪面修正、宽高比联动、视口坐标换算的矩阵准备；
# 依赖世界变换的矩阵（worldToCamera / cameraToWorld / viewProjection /
# worldToViewport / screenPointToRay）在 Camera 实体上实现（它持有 transform）。
#
# 命名贴合 Unity3D（R22）：isOrthographic / fieldOfView / orthographicSize /
# nearClipPlane / farClipPlane / aspect / cullingMask / depth / clearFlags /
# backgroundColor / projectionMatrix / clampClipping。
# ============================================================================
public class CameraData extends Behaviour
{
    public static Int32 CLEAR_NONE = 0
    public static Int32 CLEAR_SOLID_COLOR = 1
    public static Int32 CLEAR_DEPTH = 2
    public static Int32 CLEAR_ALL = 3

    # 投影模式：false = 透视，true = 正交
    public bool isOrthographic = false
    # 透视垂直视场角（角度制）
    public Float32 fieldOfView = 60.0f
    # 正交半高（Unity orthographicSize）
    public Float32 orthographicSize = 5.0f
    public Float32 nearClipPlane = 0.1f
    public Float32 farClipPlane = 1000.0f
    # 宽高比（宽 / 高）；setAspect 联动正交半宽
    public Float32 aspect = 1.0f
    # 渲染层掩码（与 GameObject.layer 位对应）
    public Int32 cullingMask = -1
    # 深度排序（越小越先渲染）
    public Int32 depth = 0
    public Int32 clearFlags = CLEAR_SOLID_COLOR
    public Float32_3 backgroundColor = Float32_3( 0.0f, 0.0f, 0.0f )

    # 诊断信息
    public string lastError = ""

    public void _init_()
    {
        this.isOrthographic = false
        this.fieldOfView = 60.0f
        this.orthographicSize = 5.0f
        this.nearClipPlane = 0.1f
        this.farClipPlane = 1000.0f
        this.aspect = 1.0f
        this.cullingMask = -1
        this.depth = 0
        this.clearFlags = CameraData.CLEAR_SOLID_COLOR
        this.backgroundColor = Float32_3( 0.0f, 0.0f, 0.0f )
        this.lastError = ""
    }

    # ── 参数 setter ──────────────────────────────────────
    public void setOrthographic( bool on )
    {
        this.isOrthographic = on
    }

    public void setFieldOfView( Float32 fov )
    {
        this.fieldOfView = fov
        this.clampClipping()
    }

    public void setOrthographicSize( Float32 size )
    {
        if size > 0.0f
        {
            this.orthographicSize = size
        }
    }

    public void setClipPlanes( Float32 nearPlane, Float32 farPlane )
    {
        this.nearClipPlane = nearPlane
        this.farClipPlane = farPlane
        this.clampClipping()
    }

    public void setAspect( Float32 value )
    {
        if value > 0.0f
        {
            this.aspect = value
        }
    }

    # 由像素尺寸设置宽高比（screenWidth / screenHeight）
    public void setPixelRect( Int32 pixelWidth, Int32 pixelHeight )
    {
        if pixelWidth <= 0 || pixelHeight <= 0
        {
            ret
        }
        Float32 w = pixelWidth as Float32
        Float32 h = pixelHeight as Float32
        this.aspect = w / h
    }

    public void setCullingMask( Int32 mask )
    {
        this.cullingMask = mask
    }

    public void setDepth( Int32 value )
    {
        this.depth = value
    }

    public void setClearFlags( Int32 flags )
    {
        this.clearFlags = flags
    }

    public void setBackgroundColor( Float32 r, Float32 g, Float32 b )
    {
        this.backgroundColor = Float32_3( r, g, b )
    }

    # ── 裁剪面修正 ───────────────────────────────────────
    # near 保底 0.01；far 至少比 near 大 1
    public void clampClipping()
    {
        if this.nearClipPlane <= 0.0f
        {
            this.nearClipPlane = 0.01f
        }
        if this.farClipPlane <= this.nearClipPlane
        {
            this.farClipPlane = this.nearClipPlane + 1.0f
        }
    }

    # ── 投影矩阵 ─────────────────────────────────────────
    public Float32_4x4 projectionMatrix()
    {
        this.clampClipping()
        if this.isOrthographic
        {
            Float32 halfH = this.orthographicSize
            Float32 halfW = halfH * this.aspect
            ret Float32_4x4.ortho( 0.0f - halfW, halfW, 0.0f - halfH, halfH,
                this.nearClipPlane, this.farClipPlane )
        }
        Float32 fovRad = Mathf.radians( this.fieldOfView )
        ret Float32_4x4.perspective( fovRad,
            this.aspect, this.nearClipPlane, this.farClipPlane )
    }

    # 正交半宽（orthographicSize * aspect），供 UI/2D 换算消费
    public Float32 orthographicHalfWidth()
    {
        ret this.orthographicSize * this.aspect
    }

    override string toString()
    {
        ret String.toFormat( "CameraData(fov={0}, aspect={1}, ortho={2})",
            this.fieldOfView.toString(), this.aspect.toString(),
            this.isOrthographic.toString() )
    }
}
