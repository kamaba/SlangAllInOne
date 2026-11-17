import Core;
import Std;
import Math;

# ============================================================================
# CollisionSystem — 碰撞检测与触发器事件（P3，doc/11 §3/§4）
# ----------------------------------------------------------------------------
# 用法：app.collisionSystem = CollisionSystem() 启用；Application 的每个
# fixedUpdate 步末自动调用 step(activeScene)（Enter/Stay/Exit 必须在固定
# 步长判定——doc/11 §4.3）。
# 流程：显式栈遍历收集 Collider（键一次读全平行数组，doc/10 §6 规避家族）
# → 宽相（AABB + 碰撞矩阵，两套掩码与渲染 cullMask 独立）→ 窄相（kind
# 分派：box/box 最小穿透轴、sphere/sphere 中心距、box/sphere closestPoint）
# → 与持续接触表比对发 Enter/Stay/Exit（经 SystemSimEngineCallHook1/2
# 按名派发到最派生 override）。
# P3 简化：① 事件只投给宿主的 Collider 组件自身（多 Behaviour 广播随 P5）；
# ② O(n²) 宽相（空间网格远期）；③ MeshCollider 退化为盒（远期 GJK）。
# ============================================================================

public class CollisionSystem
{
    public Int32 broadphaseChecks = 0
    public Int32 narrowphaseHits = 0

    # 碰撞矩阵：Array<Int32>（List 下标写跨模块失效——P2 实证，doc/10 §6；
    # Array 索引走 SystemArray* 系统调用路径可靠）
    Array<Int32> _matrix = Array<Int32>( 32 )
    bool _matrixReady = false
    # 平行数组（收集上下文一次读全，step 内只消费标量/引用）
    List<Behaviour> _colRef = List<Behaviour>( 16 )
    List<GameObject> _colOwner = List<GameObject>( 16 )
    List<Bounds> _colBounds = List<Bounds>( 16 )
    List<Float32_3> _colCenter = List<Float32_3>( 16 )
    List<Float32> _colRadius = List<Float32>( 16 )
    List<Int32> _colKind = List<Int32>( 16 )
    List<bool> _colTrigger = List<bool>( 16 )
    List<ContactPair> _pairs = List<ContactPair>( 8 )
    # 本步实体接触留存（P4：PhysicsSystem.solveContacts 消费；触发器对不入）
    List<Behaviour> _lastA = List<Behaviour>( 8 )
    List<Behaviour> _lastB = List<Behaviour>( 8 )
    List<ContactInfo> _lastInfo = List<ContactInfo>( 8 )
    # 触发器开关（debug 用）：disableTriggerEvents 时不派发 onTrigger*
    public bool disableTriggerEvents = false

    # ── 碰撞矩阵（与渲染 cullMask 两套独立掩码，doc/11 §3.3）────
    # 第 layer 位为 1 表示该 layer 与 layer 碰撞；默认全 1（互碰）
    void ensureMatrix()
    {
        if this._matrixReady
        {
            ret
        }
        Int32 i = 0
        while i < 32
        {
            this._matrix[i] = 0x7FFFFFFF
            i = i + 1
        }
        this._matrixReady = true
    }

    public void setLayerMask( Int32 layer, Int32 mask )
    {
        this.ensureMatrix()
        this._matrix[layer] = mask
    }

    public Int32 getLayerMask( Int32 layer )
    {
        this.ensureMatrix()
        # 坑（doc/10 §6）：ret 表达式内成员下标解析失败——先落局部变量
        Int32 v = this._matrix[layer]
        ret v
    }

    bool canCollide( Int32 layerA, Int32 layerB )
    {
        # 对称判定（doc/11 §3.3：矩阵第 i 位 = 该 layer 与 layer i 碰撞；
        # setLayerMask(1, 0) 表示 layer1 与任何层都不碰）
        this.ensureMatrix()
        Int32 ma = this._matrix[layerA]
        Int32 mb = 1 << layerB
        Int32 h1 = ma & mb
        Int32 mb2 = this._matrix[layerB]
        Int32 ma2 = 1 << layerA
        Int32 h2 = mb2 & ma2
        bool s1 = h1 > 0
        bool s2 = h2 > 0
        # AND 语义：双方矩阵都允许才碰撞（setLayerMask(1,0) 即可阻断）
        ret s1 && s2
    }

    # ── 收集 ────────────────────────────────────────────
    # 显式栈先序遍历（不用递归——递归方法内跨模块字段读失效，doc/10 §6）
    void gather( Scene scene )
    {
        this._colRef.clear()
        this._colOwner.clear()
        this._colBounds.clear()
        this._colCenter.clear()
        this._colRadius.clear()
        this._colKind.clear()
        this._colTrigger.clear()
        this._lastA.clear()
        this._lastB.clear()
        this._lastInfo.clear()
        if scene == null
        {
            ret
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
            bool active = cur.getActiveInHierarchy()
            if active
            {
                if cur.pendingDestroy == false
                {
                    BoxCollider bc = cur.getComponent<BoxCollider>()
                    SphereCollider sc = cur.getComponent<SphereCollider>()
                    CapsuleCollider cc = cur.getComponent<CapsuleCollider>()
                    MeshCollider mc = cur.getComponent<MeshCollider>()
                    if bc != null
                    {
                        bc.refreshWorldBounds()
                        this._colRef.add( bc )
                        this._colOwner.add( cur )
                        this._colBounds.add( bc.worldBounds )
                        this._colCenter.add( Float32_3.zero() )
                        this._colRadius.add( 0.0f )
                        this._colKind.add( 0 )
                        this._colTrigger.add( bc.isTrigger )
                    }
                    elif sc != null
                    {
                        sc.refreshWorldBounds()
                        this._colRef.add( sc )
                        this._colOwner.add( cur )
                        this._colBounds.add( sc.worldBounds )
                        this._colCenter.add( sc.worldCenter )
                        this._colRadius.add( sc.worldRadius )
                        this._colKind.add( 1 )
                        this._colTrigger.add( sc.isTrigger )
                    }
                    elif cc != null
                    {
                        cc.refreshWorldBounds()
                        this._colRef.add( cc )
                        this._colOwner.add( cur )
                        this._colBounds.add( cc.worldBounds )
                        this._colCenter.add( Float32_3.zero() )
                        this._colRadius.add( 0.0f )
                        this._colKind.add( 2 )
                        this._colTrigger.add( cc.isTrigger )
                    }
                    elif mc != null
                    {
                        # MeshCollider（v0.1 退化盒）：走 kind=0 盒窄相——
                        # MeshCollider extends BoxCollider，窄相 as 转换兼容
                        mc.refreshWorldBounds()
                        this._colRef.add( mc )
                        this._colOwner.add( cur )
                        this._colBounds.add( mc.worldBounds )
                        this._colCenter.add( Float32_3.zero() )
                        this._colRadius.add( 0.0f )
                        this._colKind.add( 0 )
                        this._colTrigger.add( mc.isTrigger )
                    }
                }
                # 子节点逆序入栈（弹出即原序）；未激活子树不入栈
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
    }

    # ── 主入口：每个固定步调用一次 ──────────────────────
    public Int32 step( Scene scene )
    {
        this.broadphaseChecks = 0
        this.narrowphaseHits = 0
        this.ensureMatrix()
        this.gather( scene )
        Int32 count = this._colRef.length
        # 本步接触对（平行数组）：colA/colB 引用 + trigger + 触发标志
        List<Behaviour> nowA = List<Behaviour>( 8 )
        List<Behaviour> nowB = List<Behaviour>( 8 )
        List<bool> nowTrigger = List<bool>( 8 )
        List<ContactInfo> nowInfo = List<ContactInfo>( 8 )
        Int32 i = 0
        while i < count
        {
            Int32 j = i + 1
            while j < count
            {
                # 坑（doc/10 §6）：`this._colOwner[i].layer` 链式返回 Object
                # ——下标结果先落局部变量（第33轮 list[idx] 坑同源）
                GameObject oa = this._colOwner[i]
                Int32 la = oa.layer
                GameObject ob = this._colOwner[j]
                Int32 lb = ob.layer
                bool allowed = this.canCollide( la, lb )
                if allowed
                {
                    Bounds ba = this._colBounds[i]
                    Bounds bb = this._colBounds[j]
                    this.broadphaseChecks = this.broadphaseChecks + 1
                    if ba.intersects( bb )
                    {
                        # 窄相（kind 分派：0=box 1=sphere 2=capsule；3×3 全矩阵）
                        ContactInfo info = ContactInfo()
                        bool touching = false
                        Int32 ka = this._colKind[i]
                        Int32 kb = this._colKind[j]
                        Behaviour ca = this._colRef[i]
                        Behaviour cb = this._colRef[j]
                        if ka == 0
                        {
                            BoxCollider ba2 = ca as BoxCollider
                            if kb == 0
                            {
                                BoxCollider bb2 = cb as BoxCollider
                                touching = ba2.computeBoxContact( bb2, info )
                                if touching
                                {
                                    # GJK/MTV 精化（v1，doc/11）：双方均为 MeshCollider
                                    # 且登记了凸点集 → C 侧 GJK 布尔复核 + MTV 法线/深度
                                    # 覆写 ContactInfo（false 撤销包围盒误报对）
                                    MeshCollider ma2 = ca as MeshCollider
                                    MeshCollider mb2 = cb as MeshCollider
                                    if ma2 != null
                                    {
                                        if mb2 != null
                                        {
                                            Int32 va = ma2.meshVertCount()
                                            Int32 vb2 = mb2.meshVertCount()
                                            if va > 0
                                            {
                                                if vb2 > 0
                                                {
                                                    bool fine = ma2.meshContact( mb2, info )
                                                    if !fine
                                                    {
                                                        touching = false
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            elif kb == 1
                            {
                                # box vs sphere：盒侧法线从球指向盒 = B→A ✓
                                Float32_3 sc2 = this._colCenter[j]
                                Float32 sr = this._colRadius[j]
                                touching = ba2.computeSphereContact( sc2, sr, info )
                            }
                            else
                            {
                                # box vs capsule：委托胶囊侧。坑（P3 补全实证）：
                                # 配对约定 n=B→A，方法约定 n=other→self——胶囊在
                                # B 侧被委托时返回 A→B，须取反（胶囊在 A 侧的
                                # 三个分支才直接可用）
                                CapsuleCollider cb2 = cb as CapsuleCollider
                                touching = cb2.computeBoxContact( ba2, info )
                                if touching
                                {
                                    info.normal = info.normal._mul_( 0.0f - 1.0f ) as Float32_3
                                }
                            }
                        }
                        elif ka == 1
                        {
                            SphereCollider sa = ca as SphereCollider
                            if kb == 1
                            {
                                SphereCollider sb = cb as SphereCollider
                                touching = sa.computeSphereContact( sb, info )
                            }
                            elif kb == 0
                            {
                                # sphere vs box：委托球侧（内部法线取反 = B→A ✓）
                                BoxCollider bb3 = cb as BoxCollider
                                touching = sa.computeBoxContact( bb3, info )
                            }
                            else
                            {
                                # sphere vs capsule：委托胶囊侧（B 侧，取反同上）
                                CapsuleCollider cb3 = cb as CapsuleCollider
                                touching = cb3.computeSphereContact( sa, info )
                                if touching
                                {
                                    info.normal = info.normal._mul_( 0.0f - 1.0f ) as Float32_3
                                }
                            }
                        }
                        else
                        {
                            CapsuleCollider ca2 = ca as CapsuleCollider
                            if kb == 0
                            {
                                # capsule vs box（n 从盒指向胶囊 = B→A ✓）
                                BoxCollider bb4 = cb as BoxCollider
                                touching = ca2.computeBoxContact( bb4, info )
                            }
                            elif kb == 1
                            {
                                # capsule vs sphere（n 从球指向胶囊 = B→A ✓）
                                SphereCollider sb2 = cb as SphereCollider
                                touching = ca2.computeSphereContact( sb2, info )
                            }
                            else
                            {
                                CapsuleCollider cb4 = cb as CapsuleCollider
                                touching = ca2.computeCapsuleContact( cb4, info )
                            }
                        }
                        if touching
                        {
                            this.narrowphaseHits = this.narrowphaseHits + 1
                            nowA.add( ca )
                            nowB.add( cb )
                            bool trig = this._colTrigger[i]
                            bool trig2 = this._colTrigger[j]
                            if trig || trig2
                            {
                                trig = true
                            }
                            nowTrigger.add( trig )
                            nowInfo.add( info )
                            # 实体接触留存（触发器对不入——无求解意义）
                            if trig == false
                            {
                                this._lastA.add( ca )
                                this._lastB.add( cb )
                                this._lastInfo.add( info )
                            }
                        }
                    }
                }
                j = j + 1
            }
            i = i + 1
        }
        # ── 配对表比对 + 事件派发 ───────────────────────────
        Int32 events = 0
        # 1) 旧配对消失 → Exit
        Int32 p = 0
        Int32 pn = this._pairs.length
        while p < pn
        {
            ContactPair pair = this._pairs[p]
            if pair.wasTouching
            {
                bool still = this.pairInNow( nowA, nowB, pair.colA, pair.colB )
                if !still
                {
                    pair.wasTouching = false
                    if pair.triggerPair
                    {
                        if !this.disableTriggerEvents
                        {
                            SystemSimEngineCallHook1( pair.colA, "onTriggerExit", pair.colB )
                            SystemSimEngineCallHook1( pair.colB, "onTriggerExit", pair.colA )
                        }
                    }
                    else
                    {
                        SystemSimEngineCallHook1( pair.colA, "onCollisionExit", pair.colB )
                        SystemSimEngineCallHook1( pair.colB, "onCollisionExit", pair.colA )
                    }
                    events = events + 2
                }
            }
            p = p + 1
        }
        # 2) 本步接触 → Enter（新）或 Stay（持续）
        Int32 q = 0
        Int32 qn = nowA.length
        while q < qn
        {
            Behaviour qa = nowA[q]
            Behaviour qb = nowB[q]
            bool trig = nowTrigger[q]
            ContactInfo info = nowInfo[q]
            bool known = this.pairInNow( this.pairColAList(), this.pairColBList(), qa, qb )
            if known
            {
                # Stay
                if trig
                {
                    if !this.disableTriggerEvents
                    {
                        SystemSimEngineCallHook1( qa, "onTriggerStay", qb )
                        SystemSimEngineCallHook1( qb, "onTriggerStay", qa )
                    }
                }
                else
                {
                    SystemSimEngineCallHook2( qa, "onCollisionStay", qb, info )
                    SystemSimEngineCallHook2( qb, "onCollisionStay", qa, info )
                }
                events = events + 2
                this.markPairTouching( qa, qb )
            }
            else
            {
                # Enter + 新建配对
                ContactPair np = ContactPair()
                np.colA = qa
                np.colB = qb
                np.wasTouching = true
                np.triggerPair = trig
                this._pairs.add( np )
                if trig
                {
                    if !this.disableTriggerEvents
                    {
                        SystemSimEngineCallHook1( qa, "onTriggerEnter", qb )
                        SystemSimEngineCallHook1( qb, "onTriggerEnter", qa )
                    }
                }
                else
                {
                    SystemSimEngineCallHook2( qa, "onCollisionEnter", qb, info )
                    SystemSimEngineCallHook2( qb, "onCollisionEnter", qa, info )
                }
                events = events + 2
            }
            q = q + 1
        }
        # 3) 清理已离开的旧配对
        this.prunePairs()
        ret events
    }

    # ── CCD 扫掠查询（PhysicsSystem.ccdClip 消费）────────
    # from→to 线段对本步收集的碰撞体 AABB 求最近命中距离；
    # 排除 exclude（自身节点）；未命中返回 -1（doc/03 §6.1 语义）。
    # 须在 step() 之后调用（_colBounds 为本步刷新值）。
    public Float32 sweepDistance( GameObject exclude, Float32_3 from, Float32_3 to )
    {
        Float32 best = 0.0f - 1.0f
        Ray r = Ray.fromTo( from, to )
        Int32 i = 0
        Int32 n = this._colBounds.length
        while i < n
        {
            GameObject ow = this._colOwner[i]
            bool isSelf = ow == exclude
            if isSelf == false
            {
                Bounds b = this._colBounds[i]
                Float32 d = b.intersectRayDistance( r )
                if d >= 0.0f
                {
                    bool better = best < 0.0f
                    if better == false
                    {
                        better = d < best
                    }
                    if better
                    {
                        best = d
                    }
                }
            }
            i = i + 1
        }
        ret best
    }

    # ── 本步实体接触读取（P4 PhysicsSystem 消费；步外读为上一步值）──
    public Int32 contactCount()
    {
        ret this._lastA.length
    }

    public Behaviour contactA( Int32 i )
    {
        Behaviour b = this._lastA[i]
        ret b
    }

    public Behaviour contactB( Int32 i )
    {
        Behaviour b = this._lastB[i]
        ret b
    }

    public ContactInfo contactInfo( Int32 i )
    {
        ContactInfo c = this._lastInfo[i]
        ret c
    }

    # nowA/nowB 中是否存在 (a,b) 对（引用比较，双向同键）
    bool pairInNow( List<Behaviour> listA, List<Behaviour> listB, Behaviour a, Behaviour b )
    {
        Int32 i = 0
        Int32 n = listA.length
        while i < n
        {
            Behaviour la = listA[i]
            Behaviour lb = listB[i]
            bool fwd = ( la == a ) && ( lb == b )
            bool rev = ( la == b ) && ( lb == a )
            if fwd || rev
            {
                ret true
            }
            i = i + 1
        }
        ret false
    }

    # 持续接触表的两个平行视图（避免暴露 _pairs 内部列表）
    List<Behaviour> pairColAList()
    {
        List<Behaviour> outList = List<Behaviour>( 0 )
        Int32 i = 0
        Int32 n = this._pairs.length
        while i < n
        {
            ContactPair p = this._pairs[i]
            if p.wasTouching
            {
                outList.add( p.colA )
            }
            else
            {
                outList.add( null )
            }
            i = i + 1
        }
        ret outList
    }

    List<Behaviour> pairColBList()
    {
        List<Behaviour> outList = List<Behaviour>( 0 )
        Int32 i = 0
        Int32 n = this._pairs.length
        while i < n
        {
            ContactPair p = this._pairs[i]
            if p.wasTouching
            {
                outList.add( p.colB )
            }
            else
            {
                outList.add( null )
            }
            i = i + 1
        }
        ret outList
    }

    void markPairTouching( Behaviour a, Behaviour b )
    {
        Int32 i = 0
        Int32 n = this._pairs.length
        while i < n
        {
            ContactPair p = this._pairs[i]
            bool fwd = ( p.colA == a ) && ( p.colB == b )
            bool rev = ( p.colA == b ) && ( p.colB == a )
            if fwd || rev
            {
                p.wasTouching = true
                ret
            }
            i = i + 1
        }
    }

    # 移除本步未接触的旧配对（Exit 已发）
    void prunePairs()
    {
        List<ContactPair> keep = List<ContactPair>( 8 )
        Int32 i = 0
        Int32 n = this._pairs.length
        while i < n
        {
            ContactPair p = this._pairs[i]
            if p.wasTouching
            {
                keep.add( p )
            }
            i = i + 1
        }
        this._pairs = keep
    }
}
