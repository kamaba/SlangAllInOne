import Core;
import Std;
import Math;
import SLangRender;

# ============================================================================
# CameraRig2D — 2D 正交相机适配器（P7 2D 游戏类型支撑，doc/15 §9）
# ----------------------------------------------------------------------------
# 职责：把「窗口宽高比适配 + 目标跟随 + 地图边界钳制」收敛到一个可复用
# 控制器，按帧把结果写进 RenderSystem 的 cameraCenter / viewSize。
# 不是 Behaviour（不做生命周期钩子）：调用方每帧显式调 update(rs, dt)
#（或只调 applyViewSize(rs) 不跟随）。
#
# 宽高比适配三模式（fitMode）：
#   0 = MatchHeight  纵向视野恒定 = refSize（Unity orthographicSize 语义，
#       RenderSystem 既有约定），横向随窗口扩展/裁切——横版卷轴/俯视默认。
#   1 = MatchWidth   横向视野恒定 = refSize，纵向随窗口变化——竖屏/固定屏。
#   2 = PixelPerfect 像素完美：scale = floor(像素高 / refPixelHeight)（下限 1），
#       纵向世界跨度 = 像素高 / scale（1 世界单位 = 1 参考像素）——
#       像素风 tile 游戏防采样抖动。
#
# 跟随：target 节点位置 + followOffset；smoothTime > 0 时指数平滑
#（f = 1 - exp(-smoothTime*dt)，0 = 硬切）；useBounds 时把中心钳在
# [min+半视野, max-半视野]（地图小于视野时居中）。
# z 轴：写 cameraCenter 时 z 固定 0（2D 正交约定；3D 场景不要挂本 rig）。
# 坑规避：无循环/无常量表达式比较，straight-line 全可靠（doc/10 §6）。
# ============================================================================

public class CameraRig2D
{
    # 0 = MatchHeight / 1 = MatchWidth / 2 = PixelPerfect
    public Int32 fitMode = 0
    # MatchHeight：纵向半高；MatchWidth：横向半宽（世界单位）
    public Float32 refSize = 5.4f
    # PixelPerfect 参考纵向像素数（如 240/270）
    public Int32 refPixelHeight = 240
    # 跟随目标（null = 不跟随，只做适配）
    public GameObject target = null
    public Float32 followOffsetX = 0.0f
    public Float32 followOffsetY = 0.0f
    # 平滑时间常数（秒；0 = 硬切跟随）
    public Float32 smoothTime = 0.0f
    # 地图边界钳制（世界单位）
    public bool useBounds = false
    public Float32 boundMinX = 0.0f
    public Float32 boundMaxX = 0.0f
    public Float32 boundMinY = 0.0f
    public Float32 boundMaxY = 0.0f

    # 平滑状态（当前中心）
    Float32 _cx = 0.0f
    Float32 _cy = 0.0f
    bool _hasCenter = false
    # 最近一次算出的 viewSize（update/scaleFor 消费）
    Float32 _lastView = 10.0f

    # 按当前窗口像素尺寸计算并写回 rs.viewSize；返回该值。
    # 无管线也可用（配合 setPixelSize）。
    public Float32 applyViewSize( RenderSystem rs )
    {
        Int32 ph = rs.pixelHeight()
        Float32 vs = this.refSize
        if this.fitMode == 1
        {
            Float32 a = rs.aspectValue()
            vs = this.refSize / a
        }
        elif this.fitMode == 2
        {
            Int32 refPix = this.refPixelHeight
            if refPix < 1
            {
                refPix = 1
            }
            Int32 scale = 0
            if ph > 0
            {
                scale = ph / refPix
            }
            if scale < 1
            {
                scale = 1
            }
            Float32 span = ph.toFloat32() / scale.toFloat32()
            vs = span * 0.5f
        }
        this._lastView = vs
        rs.viewSize = vs
        ret vs
    }

    # 只读换算（不写 rs）：fitMode 在给定像素尺寸下的 viewSize
    public Float32 scaleFor( RenderSystem rs )
    {
        this.applyViewSize( rs )
        ret this._lastView
    }

    # 每帧更新：适配 + 跟随 + 钳制 + 平滑，结果写 rs.cameraCenter。
    # 首帧（或 snap() 后）硬切到目标，不做平滑。
    public void update( RenderSystem rs, Float32 dt )
    {
        this.applyViewSize( rs )
        Float32 tx = this._cx
        Float32 ty = this._cy
        GameObject tg = this.target
        if tg != null
        {
            Transform t = tg.transform
            Float32_3 wp = t.worldPosition()
            tx = wp.x + this.followOffsetX
            ty = wp.y + this.followOffsetY
        }
        Float32 vs = this._lastView
        Float32 a = rs.aspectValue()
        Float32 hw = vs * a
        if this.useBounds
        {
            Float32 bx = CameraRig2D.clampSpan( tx, this.boundMinX, this.boundMaxX, hw )
            Float32 by = CameraRig2D.clampSpan( ty, this.boundMinY, this.boundMaxY, vs )
            tx = bx
            ty = by
        }
        if this._hasCenter
        {
            if this.smoothTime > 0.0f
            {
                # 指数平滑：f = 1 - exp(-dt / smoothTime)（smoothTime 为时间常数 τ）
                Float32 k = dt / this.smoothTime
                Float32 e = Mathf.exp( 0.0f - k )
                Float32 f = 1.0f - e
                Float32 sx = this._cx + ( tx - this._cx ) * f
                Float32 sy = this._cy + ( ty - this._cy ) * f
                tx = sx
                ty = sy
            }
        }
        else
        {
            # 首帧硬切：不插值
        }
        this._cx = tx
        this._cy = ty
        this._hasCenter = true
        Float32_3 nc = Float32_3( tx, ty, 0.0f )
        rs.cameraCenter = nc
    }

    # 重置平滑状态（切目标 / 传送后调用，下一帧硬切）
    public void snap()
    {
        this._hasCenter = false
    }

    # 当前中心读取（诊断/脚本消费）
    public Float32 centerX()
    {
        ret this._cx
    }

    public Float32 centerY()
    {
        ret this._cy
    }

    # 视野半跨度钳制：地图跨度小于视野时居中，否则钳 [lo+half, hi-half]
    static Float32 clampSpan( Float32 v, Float32 lo, Float32 hi, Float32 halfSpan )
    {
        Float32 full = hi - lo
        Float32 need = halfSpan * 2.0f
        if full < need
        {
            ret ( lo + hi ) * 0.5f
        }
        Float32 mn = lo + halfSpan
        Float32 mx = hi - halfSpan
        ret Mathf.clamp( v, mn, mx )
    }
}
