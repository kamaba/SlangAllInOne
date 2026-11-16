# 引擎侧变换组件：TRS（平移 / Z 轴旋转 / 缩放）+ 父子层级累乘。
#
# 与 Render 模块 Transform 的分工（doc/03 §2.2）：
#   - 本类是场景树节点的正式变换（GameObject 强制持有），只有 local 状态 +
#     world 读侧累乘；Render 侧 Transform 是渲染数据类，引擎不消费它。
#   - 旋转仅支持 Z 轴（localRotationZ，弧度）：复杂旋转由调用方烘焙进
#     合并顶点（doc/05 权衡），引擎变换保持 TRS 分解、不保留剪切。
#
# 脏标记约定（doc/03 §2.2）：
#   - 写 local 值只标脏（_localDirty），local 矩阵在读侧首次重算；
#   - world 矩阵读侧沿父链递归累乘（每层 local 有缓存），永远拿到当前值，
#     无「读到上一帧 world」的陈旧问题；Scene.updateTransforms() 作为
#     显式一致性入口保留（预热整条链）。
import Std;
import Math;
public class Transform extends Component
{
    # 相对父节点的平移
    public Float32_3 localPosition = Float32_3.zero()
    # 相对父节点的 Z 轴旋转（弧度）
    public Float32 localRotationZ = 0.0f
    # 相对父节点的缩放
    public Float32_3 localScale = Float32_3.one()

    # 宿主节点（GameObject 创建时回填，等价于继承的 parent）
    public GameObject gameObject = null

    bool _localDirty = true
    Float32_4x4 _localMatrix = MatrixUtil.identity()

    # ── 构造 ─────────────────────────────────────────────
    public void _init_()
    {
        this.parent = null
        this.components = List<Component>(4)
        this.name = "Transform"
        this.localPosition = Float32_3.zero()
        this.localRotationZ = 0.0f
        this.localScale = Float32_3.one()
        this.gameObject = null
        this._localDirty = true
        this._localMatrix = MatrixUtil.identity()
    }

    # ── 写入（只标脏，不立即重算）────────────────────────
    public void setPosition( Float32_3 p )
    {
        this.localPosition = p.clone()
        this._localDirty = true
    }

    public void setRotationZ( Float32 radians )
    {
        this.localRotationZ = radians
        this._localDirty = true
    }

    public void setScale( Float32_3 s )
    {
        this.localScale = s.clone()
        this._localDirty = true
    }

    public void setScale( Float32 uniform )
    {
        this.localScale = Float32_3( uniform, uniform, uniform )
        this._localDirty = true
    }

    # 按父空间（local）增量平移
    public void translate( Float32_3 delta )
    {
        this.localPosition = this.localPosition._add_( delta ) as Float32_3
        this._localDirty = true
    }

    # 叠加 Z 轴旋转（弧度）
    public void rotateZ( Float32 radians )
    {
        this.localRotationZ = this.localRotationZ + radians
        this._localDirty = true
    }

    # ── 矩阵 ─────────────────────────────────────────────
    # 本地 TRS 矩阵（脏标记缓存：同帧多次写入只算一次）
    public Float32_4x4 localMatrix()
    {
        if this._localDirty
        {
            this._localMatrix = MatrixUtil.trs( this.localPosition,
                Float32_3( 0.0f, 0.0f, this.localRotationZ ), this.localScale )
            this._localDirty = false
        }
        ret this._localMatrix
    }

    # 本地 -> 世界：父链 world ∘ local（读侧累乘，永远最新）
    public Float32_4x4 worldMatrix()
    {
        Float32_4x4 lm = this.localMatrix()
        if this.gameObject == null
        {
            ret lm
        }
        GameObject pgo = this.gameObject.getParent()
        if pgo == null
        {
            ret lm
        }
        Transform pt = pgo.transform
        if pt == null
        {
            ret lm
        }
        Float32_4x4 pw = pt.worldMatrix()
        ret pw.multiply( lm )
    }

    # 世界 -> 本地（TRS 解析逆沿父链递归：(P·L)⁻¹ = L⁻¹·P⁻¹；
    # 不用 MatrixUtil.inverseRigid——它不含缩放，非均匀缩放下失真）
    public Float32_4x4 worldToLocalMatrix()
    {
        Float32_4x4 invLocal = this.localInverseMatrix()
        if this.gameObject == null
        {
            ret invLocal
        }
        GameObject pgo = this.gameObject.getParent()
        if pgo == null || pgo.transform == null
        {
            ret invLocal
        }
        Float32_4x4 invParent = pgo.transform.worldToLocalMatrix()
        ret invLocal.multiply( invParent )
    }

    # 本地 TRS 的解析逆：(T·R·S)⁻¹ = S⁻¹·R⁻¹·T⁻¹
    Float32_4x4 localInverseMatrix()
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
        Float32_3 p = this.localPosition
        Float32_4x4 sinv = Float32_4x4.scale( Float32_3( 1.0f / sx, 1.0f / sy, 1.0f / sz ) )
        Float32_4x4 rinv = MatrixUtil.trs( Float32_3.zero(),
            Float32_3( 0.0f, 0.0f, 0.0f - this.localRotationZ ), Float32_3.one() )
        Float32_4x4 tinv = MatrixUtil.trs( Float32_3( 0.0f - p.x, 0.0f - p.y, 0.0f - p.z ),
            Float32_3.zero(), Float32_3.one() )
        Float32_4x4 a = sinv.multiply( rinv )
        ret a.multiply( tinv )
    }

    # ── 世界状态（读侧即时）──────────────────────────────
    public Float32_3 worldPosition()
    {
        Float32_4x4 wm = this.worldMatrix()
        ret wm.transformPoint( Float32_3.zero() )
    }

    # Z 轴旋转角沿父链累加（TRS 约定，无剪切）
    public Float32 worldRotationZ()
    {
        Float32 sum = this.localRotationZ
        if this.gameObject == null
        {
            ret sum
        }
        GameObject pgo = this.gameObject.getParent()
        if pgo == null || pgo.transform == null
        {
            ret sum
        }
        sum = sum + pgo.transform.worldRotationZ()
        ret sum
    }

    # 缩放沿父链逐分量累乘（TRS 约定）
    public Float32_3 worldScale()
    {
        Float32_3 s = this.localScale.clone()
        if this.gameObject == null
        {
            ret s
        }
        GameObject pgo = this.gameObject.getParent()
        if pgo == null || pgo.transform == null
        {
            ret s
        }
        Float32_3 ps = pgo.transform.worldScale()
        s.x = s.x * ps.x
        s.y = s.y * ps.y
        s.z = s.z * ps.z
        ret s
    }

    # ── 空间变换 ─────────────────────────────────────────
    # 世界点 -> 世界矩阵下的点变换
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

    # 世界点 -> 本地点
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

    # ── 方向快捷 ─────────────────────────────────────────
    public Float32_3 forward()
    {
        ret this.transformDirection( Float32_3.forward() )
    }

    public Float32_3 right()
    {
        ret this.transformDirection( Float32_3.right() )
    }

    public Float32_3 up()
    {
        ret this.transformDirection( Float32_3.up() )
    }

    override string toString()
    {
        ret String.toFormat( "Transform(pos={0}, rotZ={1}, scale={2})",
            this.localPosition.toString(),
            this.localRotationZ.toString(),
            this.localScale.toString() )
    }
}
