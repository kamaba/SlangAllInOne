import Core;
import Std;
import Math;
import SLangRender;

# ============================================================================
# Rigidbody — 刚体组件（P4，doc/12 §2）
# ----------------------------------------------------------------------------
# 三种状态（doc/12 §2 表）：
#   Dynamic   —— 受重力/力/碰撞求解（默认）
#   Kinematic —— isKinematic=true：脚本 movePosition / 直接写 velocity 驱动，
#                不受重力与力，不被推动（求解中 invMass=0）
#   Static    —— 不挂 Rigidbody 只有 Collider 的节点：碰撞背景
# 用法（坑规避，doc/10 §6）：
#   Rigidbody rb = Rigidbody()
#   go.addComponent( rb )          # 调用方构造 + 引擎去重挂载（禁 addComponent<T>()）
#   rb.mass = 1.0f
# 注意：
#   - 力/冲量要在 fixedUpdate 之外的时机施加也可以（累加到下一个物理步生效）
#   - 勿在 update() 直接改带 Rigidbody 节点的 Transform（会被物理写回覆盖）
#   - sleeping 时积分与求解跳过；addForce/addImpulse/movePosition 自动唤醒
# ============================================================================

public class Rigidbody extends Behaviour
{
    # ── 物性参数 ────────────────────────────────────────
    public Float32 mass = 1.0f
    public Float32 drag = 0.0f              # 线性阻力（速度指数衰减系数）
    public Float32 angularDrag = 0.05f
    public bool useGravity = true
    public bool isKinematic = false
    public Float32 restitution = 0.0f       # 恢复系数（[0,1]，>1 会持续增能）
    public Float32 friction = 0.6f

    # ── CCD（doc/12 §6 方案二：选择性扫掠）──────────────
    # 高速小物体开启（步内位移会超过碰撞体尺寸时）；慢速物体无需。
    # ccdMotionThreshold：步内位移超过此值才扫掠；ccdRadius：钳位余量
    # （≈碰撞体半径，中心停在命中面外扩该值处）。
    public bool ccdEnabled = false
    public Float32 ccdMotionThreshold = 0.5f
    public Float32 ccdRadius = 0.5f

    # ── 状态 ────────────────────────────────────────────
    public Float32_3 velocity = Float32_3.zero()
    public Float32_3 angularVelocity = Float32_3.zero()
    public bool sleeping = false            # 休眠（PhysicsSystem 维护）

    Float32 _sleepTimer = 0.0f
    Float32_3 _forceSum = Float32_3.zero()

    # ── 施加 ────────────────────────────────────────────
    # 持续力：累积到本固定步积分时生效，随后清零（每步重复施加才持续）
    public void addForce( Float32_3 force )
    {
        this.wakeUp()
        this._forceSum = this._forceSum + force
    }

    # 冲量：立即改速度（velocity += impulse / mass）
    public void addImpulse( Float32_3 impulse )
    {
        this.wakeUp()
        if this.isKinematic
        {
            ret
        }
        Float32 m = this.mass
        if m <= 0.0f
        {
            ret
        }
        this.velocity = this.velocity + impulse.scale( 1.0f / m )
    }

    # kinematic 脚本驱动：瞬移到目标位置（dynamic 瞬移请同时清 velocity）
    public void movePosition( Float32_3 target )
    {
        this.wakeUp()
        GameObject go = this.owner
        if go == null
        {
            ret
        }
        Transform t = go.transform
        t.setPosition( target )
    }

    # 唤醒（外力 / 碰撞 / 脚本显式）
    public void wakeUp()
    {
        this.sleeping = false
        this._sleepTimer = 0.0f
    }

    # ── 引擎内部（PhysicsSystem 专用；业务方勿调）────────
    public void physClearForce()
    {
        this._forceSum = Float32_3.zero()
    }

    public Float32_3 physForceSum()
    {
        ret this._forceSum
    }

    public Float32 physSleepTimerAdd( Float32 dt )
    {
        this._sleepTimer = this._sleepTimer + dt
        ret this._sleepTimer
    }

    public void physSleepTimerReset()
    {
        this._sleepTimer = 0.0f
    }
}
