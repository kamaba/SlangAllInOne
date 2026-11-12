import Std;
import Math;
# 相机组件：视场角 / 近远裁剪面 / 宽高比 + 视图 / 投影矩阵。
# 数学类型使用 Math 库的 Float32 系列：位置 -> Float32_3，矩阵 -> Float32_4x4。

# 射线（屏幕拾取用；Mesh.sl 明确不引入 Ray，这里就近定义）
public class Ray
{
    public Float32_3 origin = Float32_3.zero()
    public Float32_3 direction = Float32_3.forward()

    public void _init_()
    {
        this.origin = Float32_3.zero()
        this.direction = Float32_3.forward()
    }

    public void _init_( Float32_3 _origin, Float32_3 _direction )
    {
        this.origin = _origin.clone()
        this.direction = _direction.normalize()
    }

    # 射线上 t 处的点
    public Float32_3 getPoint( Float32 t )
    {
        ret this.origin._add_( this.direction.scale( t ) ) as Float32_3
    }

    override string toString()
    {
        ret "Ray(origin=" + this.origin.toString() + ", dir=" + this.direction.toString() + ")"
    }
}

public class Camera extends Component
{
    # 透视 / 正交
    public bool isOrthographic = false

    # 视场角（角度制）
    public Float32 fieldOfView = 60.0f
    public Float32 orthographicSize = 5.0f

    public Float32 nearClipPlane = 0.1f
    public Float32 farClipPlane = 1000.0f
    public Float32 aspect = 1.0f

    # 背景清屏色
    public Color background = Color.black()

    # 深度排序（值小先渲染）
    public Int32 depth = 0

    # ── 视图矩阵 ─────────────────────────────────────────
    # Transform 提供世界变换；若未挂 Transform 则用本地 identity
    public get Float32_4x4 worldToCameraMatrix()
    {
        Transform t = this.getTransform()
        if t == null
        {
            ret Float32_4x4.identity()
        }
        Float32_4x4 world = t.localToWorldMatrix()
        ret MatrixUtil.inverseRigid( world )
    }

    # 相机本地 -> 世界（供世界坐标推算用）
    public get Float32_4x4 cameraToWorldMatrix()
    {
        Transform t = this.getTransform()
        if t == null
        {
            ret Float32_4x4.identity()
        }
        ret t.localToWorldMatrix()
    }

    # ── 投影矩阵 ─────────────────────────────────────────
    public get Float32_4x4 projectionMatrix()
    {
        if this.isOrthographic
        {
            Float32 halfH = this.orthographicSize
            Float32 halfW = halfH * this.aspect
            ret Float32_4x4.ortho( 0.0f - halfW, halfW, 0.0f - halfH, halfH,
                this.nearClipPlane, this.farClipPlane )
        }
        ret Float32_4x4.perspective( Mathf.radians( this.fieldOfView ),
            this.aspect, this.nearClipPlane, this.farClipPlane )
    }

    # 视图 * 投影（提交绘制时直接传给 Renderer）
    public get Float32_4x4 viewProjectionMatrix()
    {
        ret this.projectionMatrix().multiply( this.worldToCameraMatrix() )
    }

    # ── 屏幕空间 ─────────────────────────────────────────
    # 世界坐标 -> 归一化设备坐标（-1..1）；超出裁剪体返回 null
    # 说明：Float32_4x4.transformPoint 不做透视除（返回的是 w=1 展开），这里手工
    # 计算四分量 clip 再除 w。
    public Float32_3 worldToViewportPoint( Float32_3 worldPoint )
    {
        Float32_4x4 vp = this.viewProjectionMatrix()
        Float32 cx = vp.getValue( 0, 0 ) * worldPoint.x + vp.getValue( 0, 1 ) * worldPoint.y + vp.getValue( 0, 2 ) * worldPoint.z + vp.getValue( 0, 3 )
        Float32 cy = vp.getValue( 1, 0 ) * worldPoint.x + vp.getValue( 1, 1 ) * worldPoint.y + vp.getValue( 1, 2 ) * worldPoint.z + vp.getValue( 1, 3 )
        Float32 cw = vp.getValue( 3, 0 ) * worldPoint.x + vp.getValue( 3, 1 ) * worldPoint.y + vp.getValue( 3, 2 ) * worldPoint.z + vp.getValue( 3, 3 )
        if cw <= 0.0f
        {
            ret null
        }
        ret Float32_3( cx / cw, cy / cw, 0.0f )
    }

    # 由屏幕像素坐标反投影到世界射线（屏幕原点左上）
    public Ray screenPointToRay( Float32 x, Float32 y, Float32 screenWidth, Float32 screenHeight )
    {
        Float32 ndcX = ( x / screenWidth ) * 2.0f - 1.0f
        Float32 ndcY = 1.0f - ( y / screenHeight ) * 2.0f

        Transform t = this.getTransform()
        Float32_3 origin = Float32_3.zero()
        Float32_3 forwardDir = Float32_3.forward()
        if t != null
        {
            origin = t.worldPosition()
            forwardDir = t.forward()
        }

        Float32_3 target = origin._add_( forwardDir ) as Float32_3
        Float32_3 rightVec = this.up().cross( forwardDir ).normalize()
        Float32_3 upDir = forwardDir.cross( rightVec ).normalize()

        # 由视场角推出近平面上射线方向（表达式不支持跨行续行，逐段落变量）
        Float32 tanFov = Mathf.tan( Mathf.radians( this.fieldOfView ) * 0.5f )
        Float32_3 dir = forwardDir._add_( rightVec.scale( ndcX * tanFov * this.aspect ) ) as Float32_3
        dir = dir._add_( upDir.scale( ndcY * tanFov ) ) as Float32_3
        ret Ray( origin, dir.normalize() )
    }

    # ── 辅助 ─────────────────────────────────────────────
    public Float32_3 up()
    {
        Transform t = this.getTransform()
        if t == null
        {
            ret Float32_3.up()
        }
        ret t.up()
    }

    public Float32_3 position()
    {
        Transform t = this.getTransform()
        if t == null
        {
            ret Float32_3.zero()
        }
        ret t.worldPosition()
    }

    Transform getTransform()
    {
        Component c = this.getComponent<Transform>()
        if c is Transform t
        {
            ret t
        }
        ret null
    }

    # 裁剪参数修正
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

    override string toString()
    {
        ret String.toFormat( "Camera(fov={0}, aspect={1}, ortho={2})",
            this.fieldOfView.toString(), this.aspect.toString(), this.isOrthographic.toString() )
    }
}
