import SimGameEngine;
import Std;
import Math;

# ============================================================================
# SimEngineTest — SimGameEngine P0/P1 冒烟验证
# ----------------------------------------------------------------------------
# 覆盖：场景树 / Transform TRS / 组件去重 / 生命周期 / 激活传播 / 延迟销毁 /
#       查找 / 无头帧循环（fixedUpdate 累加器、paused、timeScale、shutdown）
# 写法约束（本工程实证，已登记 doc/10 §6）：
#   - 跨模块「成员.方法」链式调用返回 Object（a.b().c() 坑）：一律拆单步
#     局部变量（Transform t = go.transform 后再 t.method()）
#   - && 只写双操作数（三连链报「布尔参与加减运算」），复杂条件拆 bool 局部变量
#   - 浮点比较内联容差写法（静态辅助方法在值位置调用解析不稳）
# ============================================================================

public class SimEngineTest
{
    static Int32 _pass = 0
    static Int32 _fail = 0

    static void check( bool cond, string msg )
    {
        if cond
        {
            _pass = _pass + 1
        }
        else
        {
            _fail = _fail + 1
            Console.println( "[FAIL] " + msg )
        }
    }

    # 浮点近似：|a-b| < 0.0001（内联容差写法）
    static bool near( Float32 a, Float32 b )
    {
        Float32 d = a - b
        if d < 0.0f
        {
            d = 0.0f - d
        }
        ret d < 0.0001f
    }

    # ── 测试用 Behaviour：计数探针 ──────────────────────
    public class Probe extends Behaviour
    {
        public Int32 awakeCount = 0
        public Int32 startCount = 0
        public Int32 updateCount = 0
        public Int32 lateCount = 0
        public Int32 fixedCount = 0
        public Int32 enableCount = 0
        public Int32 disableCount = 0
        public Int32 disposeCount = 0

        override void awake()
        {
            this.awakeCount = this.awakeCount + 1
        }
        override void start()
        {
            this.startCount = this.startCount + 1
        }
        override void update()
        {
            this.updateCount = this.updateCount + 1
        }
        override void lateUpdate()
        {
            this.lateCount = this.lateCount + 1
        }
        override void fixedUpdate()
        {
            this.fixedCount = this.fixedCount + 1
        }
        override void onEnable()
        {
            this.enableCount = this.enableCount + 1
        }
        override void onDisable()
        {
            this.disableCount = this.disableCount + 1
        }
        override void dispose()
        {
            this.disposeCount = this.disposeCount + 1
        }
    }

    # ── A. 场景树 ───────────────────────────────────────
    static void testTree()
    {
        Scene scene = Scene( "T1" )
        GameObject a = scene.createObject( "A" )
        GameObject b = scene.createObject( "B", a )
        GameObject c = scene.createObject( "C", b )
        check( scene.rootCount == 1, "A1 rootCount==1" )
        GameObject bParent = b.getParent()
        GameObject cParent = c.getParent()
        bool okParent = ( bParent == a ) && ( cParent == b )
        check( okParent, "A2 parent link" )
        bool okCount = ( a.childCount == 1 ) && ( b.childCount == 1 )
        check( okCount, "A3 childCount" )
        GameObject aChild = a.getChild( 0 )
        check( aChild == b, "A4 getChild" )
        GameObject fa = scene.find( "A" )
        GameObject fb = scene.find( "A/B" )
        bool okFind = ( fa == a ) && ( fb == b )
        check( okFind, "A5 scene membership" )

        # 环检测：把祖先挂到子孙下必须失败
        bool ok1 = a.setParent( c )
        check( ok1 == false, "A6 cycle rejected (ancestor->descendant)" )
        bool ok2 = a.setParent( a )
        check( ok2 == false, "A7 cycle rejected (self)" )

        # setParent(null) 移回根（挂回场景根列表）
        bool ok3 = b.setParent( null )
        bool ok4 = ( scene.rootCount == 2 ) && ( a.childCount == 0 )
        check( ok3 && ok4, "A8 reparent to root" )
        # 挂回 A
        b.setParent( a )
        bool ok5 = ( scene.rootCount == 1 ) && ( a.childCount == 1 )
        check( ok5, "A9 reparent under A" )

        # 独立节点（无场景；等价 GameObject.create("Solo")，
        # 跨模块静态工厂经 IR 解析错位，测试侧走构造器形态）
        GameObject solo = GameObject()
        solo.name = "Solo"
        GameObject soloParent = solo.getParent()
        bool soloActive = solo.getActiveInHierarchy()
        bool okSolo = ( soloParent == null ) && soloActive
        check( okSolo, "A10 standalone node" )
        solo.setParent( c )
        GameObject soloParent2 = solo.getParent()
        check( soloParent2 == c, "A11 standalone adopted into scene tree" )
        scene.destroy( solo )
        scene.processDestroys()
        check( c.childCount == 0, "A12 standalone destroyed" )
    }

    # ── B. Transform ────────────────────────────────────
    static void testTransform()
    {
        Scene scene = Scene( "T2" )
        GameObject root = scene.createObject( "Root" )
        GameObject child = scene.createObject( "Child", root )

        Transform rt = root.transform
        rt.setPosition( Float32_3( 10.0f, 20.0f, 30.0f ) )
        rt.setRotationZ( 0.0f )
        Float32_3 wp = rt.worldPosition()
        bool okB1 = ( wp.x == 10.0f ) && ( wp.y == 20.0f )
        check( okB1, "B1 root world pos" )

        # 子节点 local (1,2,3)，父无旋转 -> world = 父 + local
        Transform ct = child.transform
        ct.setPosition( Float32_3( 1.0f, 2.0f, 3.0f ) )
        Float32_3 cw = ct.worldPosition()
        bool okB2 = ( cw.x == 11.0f ) && ( cw.y == 22.0f )
        bool okB2z = cw.z == 33.0f
        check( okB2 && okB2z, "B2 child world pos accumulate" )

        # 父 Z 旋转 90 度：子 local (1,0,0) -> world 偏移 (0,1,0)
        rt.setRotationZ( 1.5707963f )
        ct.setPosition( Float32_3( 1.0f, 0.0f, 0.0f ) )
        Float32_3 cw2 = ct.worldPosition()
        bool okX = near( cw2.x, 10.0f )
        bool okY = near( cw2.y, 21.0f )
        check( okX && okY, "B3 parent rotZ rotates child offset" )

        # 缩放累乘：父 scale 2，子 local (1,2,3)（无旋转）
        rt.setRotationZ( 0.0f )
        rt.setScale( 2.0f )
        ct.setPosition( Float32_3( 1.0f, 2.0f, 3.0f ) )
        Float32_3 cw3 = ct.worldPosition()
        bool okB4x = near( cw3.x, 12.0f )
        bool okB4y = near( cw3.y, 24.0f )
        check( okB4x && okB4y, "B4 parent scale multiplies child offset" )
        Float32_3 ws = ct.worldScale()
        bool okB5 = near( ws.x, 2.0f ) && near( ws.y, 2.0f )
        check( okB5, "B5 worldScale chain" )

        # worldRotationZ 累加
        rt.setRotationZ( 0.5f )
        ct.rotateZ( 0.25f )
        Float32 wrz = ct.worldRotationZ()
        bool okB6 = near( wrz, 0.75f )
        check( okB6, "B6 worldRotationZ sum" )

        # translate 标脏后读侧拿到新值
        ct.translate( Float32_3( 1.0f, 0.0f, 0.0f ) )
        Float32_3 lp = ct.localPosition
        Float32 lpx = lp.x
        bool okB7 = near( lpx, 2.0f )
        check( okB7, "B7 translate local" )

        # transformPoint / inverseTransformPoint 往返
        Float32_3 p = ct.transformPoint( Float32_3( 1.0f, 1.0f, 1.0f ) )
        Float32_3 back = ct.inverseTransformPoint( p )
        bool okB8 = near( back.x, 1.0f ) && near( back.y, 1.0f )
        check( okB8, "B8 point roundtrip" )
    }

    # ── C. 组件容器 ─────────────────────────────────────
    static void testComponents()
    {
        Scene scene = Scene( "T3" )
        GameObject go = scene.createObject( "GO" )

        Probe p1 = Probe()
        go.addComponent( p1 )
        check( p1 != null, "C1 attach component" )
        Probe p2 = Probe()
        go.addComponent( p2 )
        Probe got1 = go.getComponent<Probe>()
        check( got1 == p1, "C2 same-type attach dedup (first kept)" )
        check( p2.owner == null, "C3 rejected duplicate not owned" )
        check( p1.owner == go, "C4 owner backfilled" )
        Transform gotT = go.getComponent<Transform>()
        Transform goT = go.transform
        check( gotT == goT, "C5 getComponent<Transform>" )

        # awake 在挂载时立即调用
        check( p1.awakeCount == 1, "C6 awake on mount" )

        # Transform 不可移除
        bool removedT = go.removeComponent<Transform>()
        bool okC7 = ( removedT == false ) && ( goT != null )
        check( okC7, "C7 Transform protected" )

        # 移除 Behaviour：onDisable + dispose
        p1.setEnabled( true )
        bool removed = go.removeComponent<Probe>()
        bool okC8 = ( removed == true ) && ( p1.disposeCount == 1 )
        bool okC8b = p1.disableCount == 1
        check( okC8 && okC8b, "C8 removeComponent disposes" )
        Probe gone = go.getComponent<Probe>()
        check( gone == null, "C9 gone after remove" )
    }

    # ── D/E. 生命周期 + 激活传播 ────────────────────────
    static void testLifecycleAndActivation()
    {
        Application app = Application()
        app.init()
        app.fixedDt = 0.01f
        Scene scene = app.activeScene

        GameObject parent = scene.createObject( "P" )
        GameObject child = scene.createObject( "Child", parent )
        Probe pp = Probe()
        parent.addComponent( pp )
        Probe pc = Probe()
        child.addComponent( pc )

        # 挂载即 awake；激活态挂载即 onEnable
        bool okD1 = ( pp.awakeCount == 1 ) && ( pc.awakeCount == 1 )
        check( okD1, "D1 awake on mount" )
        bool okD2 = ( pp.enableCount == 1 ) && ( pc.enableCount == 1 )
        check( okD2, "D2 onEnable on mount (active)" )

        # 一帧：start 一次 + update 一次 + lateUpdate 一次；fixedDt=0.01, dt=0.05 -> 5 步
        app.tick( 0.05f )
        bool okD3 = ( pp.startCount == 1 ) && ( pc.startCount == 1 )
        check( okD3, "D3 start once" )
        bool okD4 = ( pp.updateCount == 1 ) && ( pc.updateCount == 1 )
        check( okD4, "D4 update per tick" )
        check( pp.lateCount == 1, "D5 lateUpdate per tick" )
        check( pp.fixedCount == 5, "D6 fixedUpdate 5 steps (0.05/0.01)" )

        # 禁用父节点：整棵子树跳过更新，子节点 activeSelf 保持
        parent.setActive( false )
        bool parentActive = parent.getActiveInHierarchy()
        bool childActive = child.getActiveInHierarchy()
        bool okE1 = ( parentActive == false ) && ( childActive == false )
        check( okE1, "E1 inactive propagates" )
        check( child.activeSelf == true, "E2 child activeSelf preserved" )
        bool okE3 = ( pp.disableCount == 1 ) && ( pc.disableCount == 1 )
        check( okE3, "E3 onDisable both" )
        app.tick( 0.05f )
        bool okE4 = ( pp.updateCount == 1 ) && ( pc.updateCount == 1 )
        check( okE4, "E4 subtree skipped" )

        # 组件级开关独立生效
        parent.setActive( true )
        bool okE5 = ( pp.enableCount == 2 ) && ( pc.enableCount == 2 )
        check( okE5, "E5 re-enable subtree" )
        # 组件级开关：走 C VM 系统调用（用户侧 pc.setEnabled 经基类虚表
        # 派发在跨模块派生实例上不可靠，见 doc/10 §6 缺陷登记）
        SystemSimEngineSetEnabled( pc, false )
        app.tick( 0.02f )
        bool okE6 = ( pc.updateCount == 1 ) && ( pp.updateCount == 2 )
        check( okE6, "E6 component isEnabled gate" )

        # paused：dt=0，update 不推进（fixedUpdate 也不推进）
        app.paused = true
        app.tick( 0.05f )
        bool okD7 = ( pp.updateCount == 2 ) && ( pp.fixedCount == 7 )
        check( okD7, "D7 paused freezes logic" )
        app.paused = false

        # timeScale=0.5：dt 减半 -> 0.025 -> 2 步（累计 7+2=9）
        app.timeScale = 0.5f
        app.tick( 0.05f )
        check( pp.fixedCount == 9, "D8 timeScale halves steps (2)" )
        app.timeScale = 1.0f

        app.shutdown()
        bool okD9 = ( pp.disposeCount == 1 ) && ( pc.disposeCount == 1 )
        check( okD9, "D9 shutdown disposes" )
        check( app.activeScene == null, "D10 shutdown clears scene" )
    }

    # ── F. 延迟销毁 ─────────────────────────────────────
    static void testDeferredDestroy()
    {
        Application app = Application()
        app.init()
        Scene scene = app.activeScene
        GameObject go = scene.createObject( "Victim" )
        Probe p = Probe()
        go.addComponent( p )
        app.tick( 0.016f )
        Int32 updatesBefore = p.updateCount

        go.destroy()
        check( go.pendingDestroy == true, "F1 pendingDestroy marked" )
        check( p.disableCount == 1, "F2 onDisable immediate" )
        # 当帧仍可安全读节点
        check( go.name == "Victim", "F3 readable after destroy" )
        app.tick( 0.016f )
        check( p.updateCount == updatesBefore, "F4 destroyed node not updated" )
        check( p.disposeCount == 1, "F5 dispose at frame end" )
        check( scene.rootCount == 0, "F6 detached from scene" )
        app.shutdown()
    }

    # ── G. 查找 ─────────────────────────────────────────
    static void testFind()
    {
        Scene scene = Scene( "T7" )
        GameObject root = scene.createObject( "Root" )
        root.tag = "Player"
        root.layer = 3
        GameObject mid = scene.createObject( "Mid", root )
        GameObject leaf = scene.createObject( "Leaf", mid )
        leaf.tag = "Enemy"
        leaf.layer = 3

        GameObject g1 = scene.find( "Root" )
        check( g1 == root, "G1 scene.find root" )
        GameObject g2 = scene.find( "Root/Mid/Leaf" )
        check( g2 == leaf, "G2 scene.find path" )
        GameObject g3 = scene.find( "Root/Mid" )
        check( g3 == mid, "G3 scene.find partial" )
        GameObject g4a = scene.find( "Nope" )
        GameObject g4b = scene.find( "Root/Nope" )
        bool okG4 = ( g4a == null ) && ( g4b == null )
        check( okG4, "G4 find miss" )
        GameObject g5 = root.find( "Mid/Leaf" )
        check( g5 == leaf, "G5 relative find" )
        GameObject g6 = mid.find( "" )
        check( g6 == null, "G6 empty path null" )

        Array<GameObject> byTag = scene.findAllByTag( "Enemy" )
        Int32 tagCount = byTag.length
        check( tagCount == 1, "G7a findAllByTag count" )
        GameObject tagHit = byTag[0]
        check( tagHit == leaf, "G7b findAllByTag hit" )
        Array<GameObject> byLayer = scene.findAllByLayer( 3 )
        Int32 layerCount = byLayer.length
        check( layerCount == 2, "G8 findAllByLayer" )
    }

    public static void run()
    {
        Console.println( "=== SimEngineTest (SimGameEngine P0/P1 smoke) ===" )
        testTree()
        testTransform()
        testComponents()
        testLifecycleAndActivation()
        testDeferredDestroy()
        testFind()
        Console.println( "PASS=" + _pass.toString() + " FAIL=" + _fail.toString() )
        if _fail > 0
        {
            OS.Kernel.exit( 1 )
        }
    }
}
