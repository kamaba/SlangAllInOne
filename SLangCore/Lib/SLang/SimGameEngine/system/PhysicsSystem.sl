import Core;
import Std;
import Math;
import SLangRender;

# ============================================================================
# PhysicsSystem — 轻量物理（P4，doc/12 §3/§4）：半隐式欧拉 + 顺序冲量求解
# ----------------------------------------------------------------------------
# 用法：app.physicsSystem = PhysicsSystem()（可与 app.collisionSystem =
# CollisionSystem() 同时启用——物理步内部驱动碰撞检测；只挂碰撞不挂物理时
# Application 保持原纯碰撞步）。
# 每个固定步流程（doc/12 §3）：
#   1) 重力 + 外力 + 阻力 → velocity（半隐式欧拉：先速度后位置）
#   2) 位置积分 pos += v*dt（写 Transform local，标脏）
#   3) CollisionSystem.step（用积分后的位置做宽/窄相 + Enter/Stay/Exit，
#      并留存本步实体接触对供求解消费）
#   4) 接触求解：位置修正（slop/percent，一次）→ 法向冲量 + 切向摩擦
#      （velocityIterations 轮顺序冲量）
#   5) 休眠管理：线速度持续低于阈值 sleepTimeThreshold 秒入睡；被外力/
#      碰撞唤醒
# v0.1 边界：刚体建议挂根节点（写 Transform local，父级缩放不支持）；
# 接触形状随 CollisionSystem 仅 box/sphere；CCD 未做（doc/12 §6 远期）。
# 已知坑规避：向量运算全用局部变量承接（不链式）；`&&` 双操作数；下标/字段
# 先落局部变量再返回；负数用 0.0f - x 形态。
# ============================================================================

public class PhysicsSystem
{
    # ── 全局参数 ────────────────────────────────────────
    public Float32_3 gravity = Float32_3( 0.0f, 0.0f - 9.81f, 0.0f )
    # 位置修正（doc/12 §4.1）：允许穿透量与修正百分比（过高会抖动）
    public Float32 slop = 0.01f
    public Float32 correctionPercent = 0.8f
    # 顺序冲量迭代轮数（doc/12 §4.2：4~8，堆叠稳定性随轮数提升）
    public Int32 velocityIterations = 4
    # 休眠（doc/12 §4.4）
    public Float32 sleepLinearThreshold = 0.05f
    public Float32 sleepTimeThreshold = 0.5f

    # 诊断（上步值）
    public Int32 bodyCount = 0
    public Int32 contactCountLast = 0

    # 平行数组（收集上下文一次读全）
    List<Rigidbody> _bodies = List<Rigidbody>( 16 )
    # CCD 用：积分前位置快照（与 _bodies 平行，capturePrevPositions 回填）
    List<Float32_3> _prevPos = List<Float32_3>( 16 )

    # ── 主入口：每个固定步一次（内部驱动碰撞检测）────────
    public void step( Scene scene, Float32 fixedDt, CollisionSystem collisionSys )
    {
        if scene == null
        {
            ret
        }
        this.gatherBodies( scene )
        this.bodyCount = this._bodies.length
        this.integrateVelocities( fixedDt )
        this.capturePrevPositions()
        this.integratePositions( fixedDt )
        if collisionSys != null
        {
            # 宽相 AABB 要用积分后的位置：先刷新变换再检测
            scene.updateTransforms()
            collisionSys.step( scene )
            # 选择性 CCD（doc/12 §6 方案二）：离散检测可能漏检穿墙对，
            # 扫掠补检并把高速刚体钳回命中面外
            this.ccdClip( collisionSys )
            this.solveContacts( collisionSys )
        }
        # 休眠判定放最后（冲量把接触刚体的重力抵消之后）——放在积分前会因
        # 每步先加的重力恒超阈值而永不入睡
        this.updateSleep( fixedDt )
    }

    # ── CCD 位置快照（积分前调用，与 _bodies 平行）──────
    void capturePrevPositions()
    {
        this._prevPos.clear()
        Int32 i = 0
        Int32 n = this._bodies.length
        while i < n
        {
            Rigidbody rb = this._bodies[i]
            GameObject go = rb.owner
            if go != null
            {
                Transform t = go.transform
                this._prevPos.add( t.localPosition )
            }
            else
            {
                this._prevPos.add( Float32_3.zero() )
            }
            i = i + 1
        }
    }

    # ── 选择性 CCD（doc/12 §6 方案二）───────────────────
    # 对 ccdEnabled 且步内位移超阈值的刚体做射线扫掠（本步刷新的碰撞体
    # AABB），命中则钳到命中面外 ccdRadius 处，并清速度的法向分量（沿
    # 本步位移方向）、保留切向。v0.1 边界：离散检测基于钳位前位置，高速
    # 穿透步的 Enter/Exit 事件可能错拍（下一固定步恢复）。
    void ccdClip( CollisionSystem cs )
    {
        Int32 i = 0
        Int32 n = this._bodies.length
        while i < n
        {
            Rigidbody rb = this._bodies[i]
            bool eligible = rb.ccdEnabled && rb.sleeping == false
            if eligible
            {
                if rb.isKinematic == false
                {
                    GameObject go = rb.owner
                    if go != null
                    {
                        Transform t = go.transform
                        Float32_3 now = t.localPosition
                        Float32_3 prev = this._prevPos[i]
                        Float32 dx = now.x - prev.x
                        Float32 dy = now.y - prev.y
                        Float32 dz = now.z - prev.z
                        Float32 dist = Float32_3( dx, dy, dz ).length()
                        if dist > rb.ccdMotionThreshold
                        {
                            Float32 hit = cs.sweepDistance( go, prev, now )
                            if hit >= 0.0f
                            {
                                Float32 stop = hit - rb.ccdRadius
                                if stop < 0.0f
                                {
                                    stop = 0.0f
                                }
                                Float32 inv = 0.0f
                                if dist > 0.000001f
                                {
                                    inv = 1.0f / dist
                                }
                                Float32_3 dir = Float32_3( dx * inv, dy * inv, dz * inv )
                                t.setPosition( Float32_3( prev.x + dir.x * stop,
                                    prev.y + dir.y * stop, prev.z + dir.z * stop ) )
                                # 清法向速度分量（沿位移方向），保留切向
                                Float32 vn = rb.velocity.x * dir.x + rb.velocity.y * dir.y + rb.velocity.z * dir.z
                                if vn > 0.0f
                                {
                                    rb.velocity = Float32_3( rb.velocity.x - dir.x * vn,
                                        rb.velocity.y - dir.y * vn, rb.velocity.z - dir.z * vn )
                                }
                            }
                        }
                    }
                }
            }
            i = i + 1
        }
    }

    # ── 休眠判定（速度阈值持续 sleepTimeThreshold 秒入睡）─
    void updateSleep( Float32 dt )
    {
        if dt <= 0.0f
        {
            ret
        }
        Int32 i = 0
        Int32 n = this._bodies.length
        while i < n
        {
            Rigidbody rb = this._bodies[i]
            if rb.sleeping == false && rb.isKinematic == false
            {
                Float32 sp2 = rb.velocity.lengthSquared()
                Float32 thr = this.sleepLinearThreshold
                if sp2 < thr * thr
                {
                    Float32 t = rb.physSleepTimerAdd( dt )
                    if t >= this.sleepTimeThreshold
                    {
                        rb.sleeping = true
                        rb.velocity = Float32_3.zero()
                    }
                }
                else
                {
                    rb.physSleepTimerReset()
                }
            }
            i = i + 1
        }
    }

    # ── 收集（显式栈遍历，不用递归）─────────────────────
    void gatherBodies( Scene scene )
    {
        this._bodies.clear()
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
                Rigidbody rb = cur.getComponent<Rigidbody>()
                if rb != null
                {
                    this._bodies.add( rb )
                }
            }
            Int32 cn = cur.childCount
            Int32 ci = cn - 1
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

    # ── 速度积分（半隐式欧拉第一步）─────────────────────
    void integrateVelocities( Float32 dt )
    {
        if dt <= 0.0f
        {
            ret
        }
        Int32 i = 0
        Int32 n = this._bodies.length
        while i < n
        {
            Rigidbody rb = this._bodies[i]
            if rb.sleeping == false
            {
                if rb.isKinematic == false
                {
                    if rb.useGravity
                    {
                        rb.velocity = rb.velocity + this.gravity.scale( dt )
                    }
                    Float32_3 f = rb.physForceSum()
                    Float32 m = rb.mass
                    if m > 0.0f
                    {
                        rb.velocity = rb.velocity + f.scale( dt / m )
                    }
                    Float32 d = rb.drag
                    if d > 0.0f
                    {
                        rb.velocity = rb.velocity.scale( 1.0f / ( 1.0f + d * dt ) )
                    }
                    rb.physClearForce()
                }
            }
            i = i + 1
        }
    }

    # ── 位置积分（写 Transform local 并标脏）────────────
    void integratePositions( Float32 dt )
    {
        if dt <= 0.0f
        {
            ret
        }
        Int32 i = 0
        Int32 n = this._bodies.length
        while i < n
        {
            Rigidbody rb = this._bodies[i]
            if rb.sleeping == false
            {
                GameObject go = rb.owner
                if go != null
                {
                    Transform t = go.transform
                    Float32_3 p = t.localPosition
                    p = p + rb.velocity.scale( dt )
                    t.setPosition( p )
                }
            }
            i = i + 1
        }
    }

    # ── 接触求解（doc/12 §4：位置修正 + 法向冲量 + 摩擦）─
    void solveContacts( CollisionSystem cs )
    {
        Int32 n = cs.contactCount()
        this.contactCountLast = n
        if n <= 0
        {
            ret
        }
        # 平行数组：接触对两侧刚体（null = static / 无刚体）
        List<Rigidbody> bA = List<Rigidbody>( 8 )
        List<Rigidbody> bB = List<Rigidbody>( 8 )
        List<ContactInfo> infos = List<ContactInfo>( 8 )
        Int32 i = 0
        while i < n
        {
            Behaviour ca = cs.contactA( i )
            Behaviour cb = cs.contactB( i )
            ContactInfo info = cs.contactInfo( i )
            Rigidbody ra = null
            Rigidbody rb2 = null
            if ca != null
            {
                GameObject oa = ca.owner
                if oa != null
                {
                    ra = oa.getComponent<Rigidbody>()
                }
            }
            if cb != null
            {
                GameObject ob = cb.owner
                if ob != null
                {
                    rb2 = ob.getComponent<Rigidbody>()
                }
            }
            # 碰撞唤醒：相对速度显著时唤醒入睡侧（静止叠放不互相吵醒）
            if ra != null && rb2 != null
            {
                bool anySleep = ra.sleeping || rb2.sleeping
                if anySleep
                {
                    Float32_3 rel = rb2.velocity - ra.velocity
                    Float32 thr4 = this.sleepLinearThreshold * 4.0f
                    if rel.length() > thr4
                    {
                        ra.wakeUp()
                        rb2.wakeUp()
                    }
                }
            }
            bA.add( ra )
            bB.add( rb2 )
            infos.add( info )
            i = i + 1
        }
        # 1) 位置修正（一次；percent 比例 + slop 余量，doc/12 §4.1）
        i = 0
        while i < n
        {
            Rigidbody ra = bA[i]
            Rigidbody rb2 = bB[i]
            Float32 invA = invMassOf( ra )
            Float32 invB = invMassOf( rb2 )
            Float32 total = invA + invB
            if total > 0.0f
            {
                ContactInfo info = infos[i]
                Float32 pen = info.penetration
                Float32 over = pen - this.slop
                if over > 0.0f
                {
                    # info.normal 约定 B→A（doc/11 §2）：A 沿 +normal 退出
                    Float32_3 corr = info.normal.scale( over * this.correctionPercent / total )
                    applyPositionDelta( ra, corr.scale( invA ) )
                    applyPositionDelta( rb2, corr.scale( 0.0f - invB ) )
                }
            }
            i = i + 1
        }
        # 2) 法向冲量 + 切向摩擦（velocityIterations 轮，doc/12 §4.2/§4.3）
        Int32 iter = 0
        Int32 iters = this.velocityIterations
        while iter < iters
        {
            i = 0
            while i < n
            {
                Rigidbody ra = bA[i]
                Rigidbody rb2 = bB[i]
                Float32 invA = invMassOf( ra )
                Float32 invB = invMassOf( rb2 )
                Float32 total = invA + invB
                if total > 0.0f
                {
                    ContactInfo info = infos[i]
                    Float32_3 normal = info.normal
                    Float32_3 va = velOf( ra )
                    Float32_3 vb = velOf( rb2 )
                    Float32_3 relV = vb - va
                    Float32 vn = relV.dot( normal )
                    # ⚠ normal 是 B→A 约定（doc/11 §2）——与 doc/12 伪码的
                    # A→B（Unity 风格）相反：接近 = vn > 0，分离 = vn < 0。
                    # 只对接近求解；vn < 0（分离中）跳过。
                    if vn > 0.0f
                    {
                        # 恢复系数取两侧较大者（Unity 同款）
                        Float32 rest = restitutionOf( ra )
                        Float32 rest2 = restitutionOf( rb2 )
                        if rest2 > rest
                        {
                            rest = rest2
                        }
                        # 本约定下 vn>0 → j<0：B 获 +normal·j 即被弹回
                        Float32 j = ( 0.0f - 1.0f - rest ) * vn / total
                        # 法向冲量：A 沿 -normal·j，B 沿 +normal·j
                        applyImpulseRaw( ra, normal.scale( ( 0.0f - j ) * invA ) )
                        applyImpulseRaw( rb2, normal.scale( j * invB ) )
                        # 摩擦（切向）：用冲量后的相对速度
                        Float32_3 relV2 = velOf( rb2 ) - velOf( ra )
                        Float32 vn2 = relV2.dot( normal )
                        Float32_3 tangent = relV2 - normal.scale( vn2 )
                        Float32 tLen = tangent.length()
                        if tLen > 0.0001f
                        {
                            tangent = tangent.scale( 1.0f / tLen )
                            Float32 jt = ( 0.0f - relV2.dot( tangent ) ) / total
                            Float32 frA = frictionOf( ra )
                            Float32 frB = frictionOf( rb2 )
                            Float32 fr = frA * frB
                            # clamp 到 ±|j|*fr（库仑锥；j<0 故取 0-j）
                            Float32 maxF = ( 0.0f - j ) * fr
                            if jt > maxF
                            {
                                jt = maxF
                            }
                            if jt < 0.0f - maxF
                            {
                                jt = 0.0f - maxF
                            }
                            applyImpulseRaw( ra, tangent.scale( ( 0.0f - jt ) * invA ) )
                            applyImpulseRaw( rb2, tangent.scale( jt * invB ) )
                        }
                    }
                }
                i = i + 1
            }
            iter = iter + 1
        }
    }

    # ── 静态工具（null 容错集中在此）────────────────────
    # 广义逆质量：null（Static）/ kinematic / mass<=0 → 0（不被推动）
    static Float32 invMassOf( Rigidbody rb )
    {
        if rb == null
        {
            ret 0.0f
        }
        if rb.isKinematic
        {
            ret 0.0f
        }
        Float32 m = rb.mass
        if m <= 0.0f
        {
            ret 0.0f
        }
        ret 1.0f / m
    }

    static Float32_3 velOf( Rigidbody rb )
    {
        if rb == null
        {
            ret Float32_3.zero()
        }
        ret rb.velocity
    }

    static Float32 restitutionOf( Rigidbody rb )
    {
        if rb == null
        {
            ret 0.0f
        }
        ret rb.restitution
    }

    static Float32 frictionOf( Rigidbody rb )
    {
        if rb == null
        {
            ret 0.5f
        }
        ret rb.friction
    }

    # 直接改速度（求解内部用；不唤醒——入睡体只在显著相对速度下被唤醒）
    static void applyImpulseRaw( Rigidbody rb, Float32_3 impulse )
    {
        if rb == null
        {
            ret
        }
        rb.velocity = rb.velocity + impulse
    }

    # 位置微调（求解内部用；Transform local 语义，见文件头边界说明）
    static void applyPositionDelta( Rigidbody rb, Float32_3 delta )
    {
        if rb == null
        {
            ret
        }
        GameObject go = rb.owner
        if go == null
        {
            ret
        }
        Transform t = go.transform
        Float32_3 p = t.localPosition
        p = p + delta
        t.setPosition( p )
    }
}
