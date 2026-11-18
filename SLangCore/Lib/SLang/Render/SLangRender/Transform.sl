import Std;
import Math;
# 变换组件（统一版，2026-11-17 合并）：
#   - Render 原语义保留：Quaternion 全 3D 旋转（rotate/lookAt/rotateAxis 等）
#     + parentNode 父链（Renderer 等组件消费不变；组件式 Camera/Light 已随
#       SRP 草稿链移除，实体相机/光源归引擎层）；
#   - 引擎 API 面并入（SimGameEngine P0~P7 原自有 Transform 删除，统一复用
#     本类）：setPosition/setRotationZ/setScale/rotateZ/localMatrix/worldMatrix/
#     worldRotationZ/worldScale/localPosition 别名 + Z 轴精确路径；
#   - Z 轴精确性：rotation 为纯 Z 旋转（x=y=0）时 localMatrix/worldRotationZ
#     走 euler-Z 直算（与引擎逐位一致——Quaternion 三角函数 roundtrip 有
#     末位漂移，引擎测试断言逐位相等）；非纯 Z 走 Quaternion 路径。
#   - worldToLocalMatrix 升级为 TRS 解析逆（沿父链 L⁻¹·P⁻¹，含缩放；原
#     inverseRigid 不含缩放，非均匀缩放父链下失真——引擎侧实证）。
# 层级约定：parentNode 由宿主维护（引擎 GameObject 创建/改挂/销毁时同步）；
# 直接裸写 rotation 字段不回填 localRotationZ（Z 判定以 rotation 本身为准，
# localRotationZ 漂移只影响 Z 快捷 API——宿主应走 setRotationZ/rotateZ）。
public class Transform extends Component
{
    # 相对父节点的平移（引擎 API 名 localPosition 以 get 属性别名，下方）
    public Float32_3 position = Float32_3.zero()
    # 相对父节点的 Z 轴旋转（弧度；与 rotation 的纯 Z 分量保持同步）
    public Float32 localRotationZ = 0.0f
    # 相对父节点的缩放
    public Float32_3 localScale = Float32_3.one()
    # 全 3D 旋转（真源；纯 Z 时由 Z 轴 API 同步回填）
    public Quaternion rotation = Quaternion.identity()

    public Transform parentNode = null

    # ── 引擎 API 别名（读形态 t.localPosition，SimPhysicsTest 等）──
    public get Float32_3 localPosition()
    {
        ret this.position.clone()
    }

    # ── 方向（局部前向经旋转到世界空间；引擎侧 forward() 括号形态兼容）──
    # 说明：Quaternion 的运算符重载返回 Object，此处用带静态类型的 rotate() 避免转型
    public get Float32_3 forward()
    {
        ret this.rotation.rotate( Float32_3.forward() )
    }

    public get Float32_3 back()
    {
        ret this.rotation.rotate( Float32_3.back() )
    }

    public get Float32_3 right()
    {
        ret this.rotation.rotate( Float32_3.right() )
    }

    public get Float32_3 left()
    {
        ret this.rotation.rotate( Float32_3.left() )
    }

    public get Float32_3 up()
    {
        ret this.rotation.rotate( Float32_3.up() )
    }

    public get Float32_3 down()
    {
        ret this.rotation.rotate( Float32_3.down() )
    }

    # ── Z 纯旋转判定与欧拉 Z 提取（先定义后使用——编译器顺序要求）──
    bool isZOnlyRotation()
    {
        Float32 xy = this.rotation.x * this.rotation.x + this.rotation.y * this.rotation.y
        ret xy < 0.000001f
    }

    # Quaternion -> 欧拉 Z（ZYX 约定；纯 Z 旋转下精确还原）
    Float32 extractRotZ()
    {
        Float32 sy = 2.0f * ( this.rotation.z * this.rotation.w + this.rotation.x * this.rotation.y )
        Float32 cy = 1.0f - 2.0f * ( this.rotation.x * this.rotation.x + this.rotation.y * this.rotation.y )
        ret Mathf.atan2( sy, cy )
    }

    # Z 轴旋转角有效值（纯 Z 用字段精确值；非纯 Z 从 Quaternion 提取）
    Float32 effectiveRotZ()
    {
        if this.isZOnlyRotation()
        {
            ret this.localRotationZ
        }
        ret this.extractRotZ()
    }

    # ── 引擎 Z 轴 TRS 快捷写 API ─────────────────────────
    public void setPosition( Float32_3 p )
    {
        this.position = p.clone()
    }

    public void setRotationZ( Float32 radians )
    {
        this.localRotationZ = radians
        Float32_3 eulerZ = Float32_3( 0.0f, 0.0f, radians )
        this.rotation = Quaternion.euler( eulerZ )
    }

    public void setScale( Float32_3 s )
    {
        this.localScale = s.clone()
    }

    public void setScale( Float32 uniform )
    {
        this.localScale = Float32_3( uniform, uniform, uniform )
    }

    # 叠加 Z 轴旋转（弧度；与 rotate(Float32_3) 欧拉叠加互补）
    public void rotateZ( Float32 radians )
    {
        this.setRotationZ( this.localRotationZ + radians )
    }

    # ── 矩阵 ─────────────────────────────────────────────
    # 本地 TRS 矩阵（引擎面）：纯 Z 旋转走 euler 直算（逐位精确），
    # 其余走 Quaternion 路径
    public Float32_4x4 localMatrix()
    {
        if this.isZOnlyRotation()
        {
            Float32_3 eulerZ = Float32_3( 0.0f, 0.0f, this.localRotationZ )
            ret MatrixUtil.trs( this.position, eulerZ, this.localScale )
        }
        ret MatrixUtil.trs( this.position, this.rotation, this.localScale )
    }

    # 本地 -> 世界（含父级链；Quaternion 路径，Renderer 消费不变）
    public get Float32_4x4 localToWorldMatrix()
    {
        Float32_4x4 local1 = MatrixUtil.trs( this.position, this.rotation, this.localScale )
        if this.parentNode != null
        {
            ret this.parentNode.localToWorldMatrix().multiply( local1 )
        }
        ret local1
    }

    # 本地 -> 世界（引擎面：父链 world ∘ local，localMatrix 同源）
    public Float32_4x4 worldMatrix()
    {
        Float32_4x4 lm = this.localMatrix()
        if this.parentNode == null
        {
            ret lm
        }
        Float32_4x4 pw = this.parentNode.worldMatrix()
        ret pw.multiply( lm )
    }

    # 本地 TRS 的解析逆：(T·R·S)⁻¹ = S⁻¹·R⁻¹·T⁻¹（纯 Z 精确）；
    # 非纯 Z 回退 inverseRigid（不含缩放——全 3D + 非均匀缩放组合不支持）
    Float32_4x4 localInverseMatrix()
    {
        if this.isZOnlyRotation()
        {
            Float32 sx = this.localScale.x
            Float32 sy = this.localScale.y
            Float32 sz = this.localScale.z
            if sx < 0.000001f && sx > -0.000001f
            {
                sx = 0.000001f
            }
            if sy < 0.000001f && sy > -0.000001f
            {
                sy = 0.000001f
            }
            if sz < 0.000001f && sz > -0.000001f
            {
                sz = 0.000001f
            }
            Float32_3 p = this.position
            Float32_4x4 sinv = Float32_4x4.scale( Float32_3( 1.0f / sx, 1.0f / sy, 1.0f / sz ) )
            Float32_4x4 rinv = MatrixUtil.trs( Float32_3.zero(),
                Float32_3( 0.0f, 0.0f, 0.0f - this.localRotationZ ), Float32_3.one() )
            Float32_4x4 tinv = MatrixUtil.trs( Float32_3( 0.0f - p.x, 0.0f - p.y, 0.0f - p.z ),
                Float32_3.zero(), Float32_3.one() )
            Float32_4x4 a = sinv.multiply( rinv )
            ret a.multiply( tinv )
        }
        ret MatrixUtil.inverseRigid( MatrixUtil.trs( this.position, this.rotation, this.localScale ) )
    }

    # 世界 -> 本地（TRS 解析逆沿父链：(P·L)⁻¹ = L⁻¹·P⁻¹，含缩放）
    public Float32_4x4 worldToLocalMatrix()
    {
        Float32_4x4 invLocal = this.localInverseMatrix()
        if this.parentNode == null
        {
            ret invLocal
        }
        Float32_4x4 invParent = this.parentNode.worldToLocalMatrix()
        ret invLocal.multiply( invParent )
    }

    # ── 世界坐标 ─────────────────────────────────────────
    public get Float32_3 worldPosition()
    {
        Float32_4x4 wm = this.worldMatrix()
        ret wm.transformPoint( Float32_3.zero() )
    }

    public void setWorldPosition( Float32_3 p )
    {
        if this.parentNode == null
        {
            this.position = p.clone()
            ret
        }
        this.position = this.parentNode.inverseTransformPoint( p )
    }

    public get Quaternion worldRotation()
    {
        if this.parentNode == null
        {
            ret this.rotation.clone()
        }
        ret this.parentNode.worldRotation.multiply( this.rotation ).normalize()
    }

    # Z 轴旋转角沿父链累加（TRS 约定，无剪切；引擎面）
    public Float32 worldRotationZ()
    {
        Float32 sum = this.effectiveRotZ()
        if this.parentNode != null
        {
            sum = sum + this.parentNode.worldRotationZ()
        }
        ret sum
    }

    # 缩放沿父链逐分量累乘（TRS 约定；引擎面）
    public Float32_3 worldScale()
    {
        Float32_3 s = this.localScale.clone()
        if this.parentNode != null
        {
            Float32_3 ps = this.parentNode.worldScale()
            s.x = s.x * ps.x
            s.y = s.y * ps.y
            s.z = s.z * ps.z
        }
        ret s
    }

    # ── 移动 / 旋转（Quaternion 面，改旋转后回填 localRotationZ）──
    # 按父空间增量平移
    public void translate( Float32_3 delta )
    {
        this.position = this.position._add_( delta )
    }

    # 按自身局部方向平移（localDirection 为局部向量）
    public void translateLocal( Float32_3 localDirection )
    {
        Float32_3 worldDelta = this.rotation.rotate( localDirection )
        this.translate( worldDelta )
    }

    # 叠加欧拉角旋转（弧度）
    public void rotate( Float32_3 eulerRadians )
    {
        Quaternion delta = Quaternion.euler( eulerRadians )
        this.rotation = delta.multiply( this.rotation ).normalize()
        this.localRotationZ = this.extractRotZ()
    }

    # 绕世界轴旋转
    public void rotateAxis( Float32_3 axis, Float32 radians )
    {
        Quaternion delta = Quaternion.axisAngle( axis, radians )
        this.rotation = delta.multiply( this.rotation ).normalize()
        this.localRotationZ = this.extractRotZ()
    }

    # 绕某个世界点 + 轴旋转
    public void rotateAround( Float32_3 point, Float32_3 axis, Float32 radians )
    {
        Quaternion q = Quaternion.axisAngle( axis, radians )
        Float32_3 offset = this.position._sub_( point ) as Float32_3
        this.position = point._add_( q.rotate( offset ) ) as Float32_3
        this.rotation = q.multiply( this.rotation ).normalize()
        this.localRotationZ = this.extractRotZ()
    }

    # 朝向目标（+Z 对准）
    public void lookAt( Float32_3 target )
    {
        this.lookAt( target, Float32_3.up() )
    }

    public void lookAt( Float32_3 target, Float32_3 upHint )
    {
        Float32_3 dir = target._sub_( this.worldPosition() ) as Float32_3
        if dir.lengthSquared() <= 0.0f
        {
            ret
        }
        this.rotation = Quaternion.lookRotation( dir, upHint )
        this.localRotationZ = this.extractRotZ()
    }

    # ── 空间变换 ─────────────────────────────────────────
    public Float32_3 transformPoint( Float32_3 p )
    {
        Float32_4x4 wm = this.worldMatrix()
        ret wm.transformPoint( p )
    }

    public Float32_3 transformDirection( Float32_3 v )
    {
        Float32_4x4 wm = this.worldMatrix()
        ret wm.transformDirection( v )
    }

    public Float32_3 inverseTransformPoint( Float32_3 p )
    {
        Float32_4x4 inv = this.worldToLocalMatrix()
        ret inv.transformPoint( p )
    }

    public Float32_3 inverseTransformDirection( Float32_3 v )
    {
        Float32_4x4 inv = this.worldToLocalMatrix()
        ret inv.transformDirection( v )
    }

    # ── 其它 ─────────────────────────────────────────────
    public void setPositionAndRotation( Float32_3 p, Quaternion q )
    {
        this.position = p.clone()
        this.rotation = q.normalize()
        this.localRotationZ = this.extractRotZ()
    }

    public void reset()
    {
        this.position = Float32_3.zero()
        this.localScale = Float32_3.one()
        this.rotation = Quaternion.identity()
        this.localRotationZ = 0.0f
    }

    override string toString()
    {
        ret String.toFormat( "Transform(pos={0}, scale={1}, rot={2})",
            this.position.toString(), this.localScale.toString(), this.rotation.toString() )
    }
}
