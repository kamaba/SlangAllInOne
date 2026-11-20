import Core;
import Std;
import Math;
import SLangRender;

# ============================================================================
# Camera — 相机实体（Unity Camera 形态：extends GameObject + CameraData 组件）
# ----------------------------------------------------------------------------
# 本节点继承 GameObject（自带 Transform / layer / 层级 / 场景归属），在构造期
# 挂一个 CameraData 组件承载全部相机参数（投影 / 裁剪 / 清屏 / 排序）。
# 矩阵能力分两层：
#   - 不依赖节点变换的（projectionMatrix / clampClipping / orthographicHalfWidth）
#     在 CameraData 上，Camera 提供同名转发；
#   - 依赖世界变换的（view / 坐标转换 / TRS）在本类，经 this.transform 取矩阵。
#
# 遵循 doc/10 §6：跨模块调用一律把中间结果落局部变量，禁止 a.b().c() 链式；
# 静态字段作实参先落局部变量；SLang 子类构造不自动调父类 _init_，故本类
# _init_ 手工复制 GameObject 节点字段初始化（_children/_scene 已开放 public）。
#
# 本轮只建结构 + 矩阵方法，不接入 RenderSystem 消费链路（by design）。
# ============================================================================
public class Camera extends GameObject
{
    public CameraData cameraData = null

    public void _init_()
    {
        # ── 复制 GameObject._init_（父类构造不自动触发）──
        this.parent = null
        this.components = List<Component>( 8 )
        this.name = "Camera"
        this.tag = "Untagged"
        this.transform = Transform()
        this.transform.parent = this
        this.components.add( this.transform )
        this.activeSelf = true
        this.layer = 0
        this.pendingDestroy = false
        this.nodeId = 0
        this._children = List<GameObject>( 8 )
        this._scene = null
        # ── 绑定 CameraData 组件 ──
        CameraData cd = CameraData()
        this.addComponent( cd )
        this.cameraData = cd
    }

    public void _init_( string _name )
    {
        this._init_()
        this.name = _name
    }

    # ── 工厂 ─────────────────────────────────────────────
    public static Camera create( string name )
    {
        Camera c = Camera()
        c.name = name
        ret c
    }

    # ── 数据组件访问 ─────────────────────────────────────
    public CameraData getData()
    {
        ret this.cameraData
    }

    # ── 投影 / 裁剪参数转发 ───────────────────────────────
    public void setOrthographic( bool on )
    {
        this.cameraData.setOrthographic( on )
    }

    public void setFieldOfView( Float32 fov )
    {
        this.cameraData.setFieldOfView( fov )
    }

    public void setOrthographicSize( Float32 size )
    {
        this.cameraData.setOrthographicSize( size )
    }

    public void setClipPlanes( Float32 nearPlane, Float32 farPlane )
    {
        this.cameraData.setClipPlanes( nearPlane, farPlane )
    }

    public void setAspect( Float32 value )
    {
        this.cameraData.setAspect( value )
    }

    public void setPixelRect( Int32 pixelWidth, Int32 pixelHeight )
    {
        this.cameraData.setPixelRect( pixelWidth, pixelHeight )
    }

    public void setCullingMask( Int32 mask )
    {
        this.cameraData.setCullingMask( mask )
    }

    public void setDepth( Int32 value )
    {
        this.cameraData.setDepth( value )
    }

    public void setClearFlags( Int32 flags )
    {
        this.cameraData.setClearFlags( flags )
    }

    public void setBackgroundColor( Float32 r, Float32 g, Float32 b )
    {
        this.cameraData.setBackgroundColor( r, g, b )
    }

    # ═══════════════════════════════════════════════════════
    # 一、投影 / 视图矩阵
    # ═══════════════════════════════════════════════════════

    # 投影矩阵（委托数据组件）
    public Float32_4x4 projectionMatrix()
    {
        ret this.cameraData.projectionMatrix()
    }

    # 相机本地 -> 世界（= 节点世界变换）
    public Float32_4x4 cameraToWorldMatrix()
    {
        ret this.transform.worldMatrix()
    }

    # 世界 -> 相机（刚体逆变换）
    public Float32_4x4 worldToCameraMatrix()
    {
        Float32_4x4 world = this.transform.worldMatrix()
        ret MatrixUtil.inverseRigid( world )
    }

    # 视图 * 投影（先视图后投影）
    public Float32_4x4 viewProjectionMatrix()
    {
        Float32_4x4 proj = this.cameraData.projectionMatrix()
        Float32_4x4 view = this.worldToCameraMatrix()
        ret proj.multiply( view )
    }

    # ═══════════════════════════════════════════════════════
    # 二、TRS 变换
    # ═══════════════════════════════════════════════════════

    # 本地点 -> 世界点
    public Float32_3 transformPoint( Float32_3 localPoint )
    {
        Float32_4x4 wm = this.transform.worldMatrix()
        ret wm.transformPoint( localPoint )
    }

    # 本地方向 -> 世界方向
    public Float32_3 transformDirection( Float32_3 localDir )
    {
        Float32_4x4 wm = this.transform.worldMatrix()
        ret wm.transformDirection( localDir )
    }

    # 世界点 -> 本地点
    public Float32_3 inverseTransformPoint( Float32_3 worldPoint )
    {
        Float32_4x4 inv = this.worldToCameraMatrix()
        ret inv.transformPoint( worldPoint )
    }

    # 世界方向 -> 本地方向
    public Float32_3 inverseTransformDirection( Float32_3 worldDir )
    {
        Float32_4x4 inv = this.worldToCameraMatrix()
        ret inv.transformDirection( worldDir )
    }

    # 世界 -> 相机局部（localToWorld 的逆，语义同 worldToCamera 变换点）
    public Float32_3 worldToLocal( Float32_3 worldPoint )
    {
        ret this.inverseTransformPoint( worldPoint )
    }

    # 相机局部 -> 世界
    public Float32_3 localToWorld( Float32_3 localPoint )
    {
        ret this.transformPoint( localPoint )
    }

    # ═══════════════════════════════════════════════════════
    # 三、坐标转换（视口 / 屏幕 / 射线）
    # ═══════════════════════════════════════════════════════

    # 世界点 -> 视口 NDC（-1..1）；w<=0 返回 null
    # transformPoint 按 w=1 算，齐次 w 由矩阵第 4 行与点相乘手工求得
    public Float32_3 worldToViewportPoint( Float32_3 worldPoint )
    {
        Float32_4x4 vp = this.viewProjectionMatrix()
        Float32 cw = vp.getValue( 3, 0 ) * worldPoint.x
            + vp.getValue( 3, 1 ) * worldPoint.y
            + vp.getValue( 3, 2 ) * worldPoint.z
            + vp.getValue( 3, 3 )
        if cw <= 0.0f
        {
            ret null
        }
        Float32_3 clip = vp.transformPoint( worldPoint )
        Float32 nx = clip.x / cw
        Float32 ny = clip.y / cw
        Float32 nz = clip.z / cw
        ret Float32_3( nx, ny, nz )
    }

    # 视口 NDC -> 世界点（逆 viewProjection 再除齐次）
    public Float32_3 viewportToWorldPoint( Float32_3 ndcPoint )
    {
        Float32_4x4 vp = this.viewProjectionMatrix()
        Float32_4x4 inv = MatrixUtil.inverseRigid( vp )
        ret inv.transformPoint( ndcPoint )
    }

    # 世界点 -> 屏幕像素（原点左上；y 翻转）
    public Float32_3 worldToScreenPoint( Float32_3 worldPoint,
        Int32 screenWidth, Int32 screenHeight )
    {
        if screenWidth <= 0 || screenHeight <= 0
        {
            ret null
        }
        Float32_3 ndc = this.worldToViewportPoint( worldPoint )
        if ndc == null
        {
            ret null
        }
        Float32 wf = screenWidth as Float32
        Float32 hf = screenHeight as Float32
        Float32 hw = wf * 0.5f
        Float32 hh = hf * 0.5f
        Float32 sx = ( ndc.x + 1.0f ) * hw
        Float32 sy = ( 1.0f - ndc.y ) * hh
        ret Float32_3( sx, sy, ndc.z )
    }

    # 屏幕像素 -> 世界射线（原点左上）
    public Ray screenPointToRay( Float32 x, Float32 y,
        Int32 screenWidth, Int32 screenHeight )
    {
        if screenWidth <= 0 || screenHeight <= 0
        {
            ret null
        }
        Float32 wf = screenWidth as Float32
        Float32 hf = screenHeight as Float32
        Float32 ndcX = ( x / wf ) * 2.0f - 1.0f
        Float32 ndcY = 1.0f - ( y / hf ) * 2.0f
        Float32_3 origin = this.transform.worldPosition()
        Float32_3 targetLocal = Float32_3( ndcX, ndcY, 1.0f )
        Float32_4x4 vp = this.viewProjectionMatrix()
        Float32_4x4 invVP = MatrixUtil.inverseRigid( vp )
        Float32_3 target = invVP.transformPoint( targetLocal )
        Float32_3 dir = target._sub_( origin ) as Float32_3
        ret Ray( origin, dir )
    }

    # ═══════════════════════════════════════════════════════
    # 四、辅助（方向 / 位置 / 裁剪面）
    # ═══════════════════════════════════════════════════════

    public Float32_3 position()
    {
        ret this.transform.worldPosition()
    }

    public Float32_3 up()
    {
        ret this.transform.up()
    }

    public Float32_3 forward()
    {
        ret this.transform.forward()
    }

    public void clampClipping()
    {
        this.cameraData.clampClipping()
    }

    public Float32 orthographicHalfWidth()
    {
        ret this.cameraData.orthographicHalfWidth()
    }

    public Float32 nearClipPlane()
    {
        ret this.cameraData.nearClipPlane
    }

    public Float32 farClipPlane()
    {
        ret this.cameraData.farClipPlane
    }

    override string toString()
    {
        ret String.toFormat( "Camera(fov={0}, aspect={1}, ortho={2})",
            this.cameraData.fieldOfView.toString(), this.cameraData.aspect.toString(),
            this.cameraData.isOrthographic.toString() )
    }
}
