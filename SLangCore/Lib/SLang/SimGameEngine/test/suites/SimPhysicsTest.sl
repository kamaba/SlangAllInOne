import SimGameEngine;
import SLangRender;
import Math;
import SLangRender;
import Std;
import SLangRender;

# ============================================================================
# SimPhysicsTest — P4 轻量物理冒烟（doc/12）
# ----------------------------------------------------------------------------
# 覆盖：重力自由落体与落地静止（验收标准"小球落地稳定"）、弹跳衰减、
# 帧率一致性（不同 tick 粒度同固定步长结果一致——验收标准之二）、
# kinematic 不受力、addImpulse/addForce、drag 衰减、休眠与唤醒、
# 水平撞墙停止、Static 不受影响、高恢复系数反弹。
# ============================================================================
public class SimPhysicsTest
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

    # ── 场景搭建────────────────────────────────────
    # 地面盒：顶面 y=0（center.y=-h/2）；Static（只有 Collider）
    static GameObject makeGround( Scene scene )
    {
        GameObject ground = scene.createObject( "Ground" )
        ground.layer = 0
        BoxCollider bc = BoxCollider()
        bc.size = Float32_3( 40.0f, 0.2f, 40.0f )
        ground.addComponent( bc )
        Transform t = ground.transform
        t.setPosition( Float32_3( 0.0f, 0.0f - 0.1f, 0.0f ) )
        ret ground
    }

    # 小球：SphereCollider 半径 r + Rigidbody
    static GameObject makeBall( Scene scene, string name, Float32 x, Float32 y, Float32 r )
    {
        GameObject ball = scene.createObject( name )
        ball.layer = 0
        SphereCollider sc = SphereCollider()
        sc.radius = r
        ball.addComponent( sc )
        Rigidbody rb = Rigidbody()
        ball.addComponent( rb )
        Transform t = ball.transform
        t.setPosition( Float32_3( x, y, 0.0f ) )
        ret ball
    }

    static Rigidbody bodyOf( GameObject go )
    {
        ret go.getComponent<Rigidbody>()
    }

    # 建一套独立物理环境（每用例互不共享状态）
    static Application makeWorld()
    {
        Application app = Application()
        app.init()
        app.fixedDt = 0.0166667f
        app.physicsSystem = PhysicsSystem()
        app.collisionSystem = CollisionSystem()
        ret app
    }

    # ── P1 重力落地静止（验收：小球落地稳定）────────────
    static void testFallAndRest()
    {
        Application app = makeWorld()
        makeGround( app.activeScene )
        GameObject ball = makeBall( app.activeScene, "Ball", 0.0f, 5.0f, 0.5f )
        Int32 i = 0
        while i < 300
        {
            app.tick( 0.0166667f )
            i = i + 1
        }
        Transform t = ball.transform
        Float32_3 p = t.localPosition
        Rigidbody rb = bodyOf( ball )
        check( p.y > 0.44f && p.y < 0.56f, "PH1a ball rests at r=0.5 (y=" + p.y.toString() + ")" )
        check( rb.velocity.length() < 0.2f, "PH1b velocity ~0 at rest" )
        check( rb.sleeping, "PH1c body falls asleep at rest" )
        app.shutdown()
    }

    # ── P2 弹跳衰减（restitution=0.5：有反弹且逐次衰减）─
    static void testBounceDecay()
    {
        Application app = makeWorld()
        makeGround( app.activeScene )
        GameObject ball = makeBall( app.activeScene, "Bouncer", 0.0f, 3.0f, 0.5f )
        Rigidbody rb = bodyOf( ball )
        rb.restitution = 0.5f
        Float32 peak = 0.0f
        bool bounced = false
        bool firstContact = false
        Int32 i = 0
        while i < 300
        {
            app.tick( 0.0166667f )
            Transform t = ball.transform
            Float32_3 p = t.localPosition
            if p.y > peak
            {
                peak = p.y
            }
            if firstContact == false && p.y < 0.6f
            {
                firstContact = true
                peak = 0.0f
            }
            if firstContact && peak > 0.9f
            {
                bounced = true
            }
            i = i + 1
        }
        check( firstContact, "PH2a ball reached ground" )
        check( bounced, "PH2b restitution 0.5 produces visible bounce" )
        check( peak < 2.2f, "PH2c bounce peak decays (peak=" + peak.toString() + ")" )
        Transform tf = ball.transform
        Float32_3 pf = tf.localPosition
        check( pf.y > 0.44f && pf.y < 0.56f, "PH2d finally at rest on ground" )
        app.shutdown()
    }

    # ── P3 帧率一致性（验收：不同帧率结果一致）──────────
    # 同一固定步长，三种 tick 粒度：每 tick 1/2/4 个固定步，终态位置一致
    static void testFrameRateIndependence()
    {
        Application appA = makeWorld()
        makeGround( appA.activeScene )
        GameObject ballA = makeBall( appA.activeScene, "Ball", 0.0f, 5.0f, 0.5f )
        Int32 i = 0
        while i < 120
        {
            appA.tick( 0.0166667f )
            i = i + 1
        }
        Application appB = makeWorld()
        makeGround( appB.activeScene )
        GameObject ballB = makeBall( appB.activeScene, "Ball", 0.0f, 5.0f, 0.5f )
        i = 0
        while i < 60
        {
            appB.tick( 1.0f / 30.0f )
            i = i + 1
        }
        Application appC = makeWorld()
        makeGround( appC.activeScene )
        GameObject ballC = makeBall( appC.activeScene, "Ball", 0.0f, 5.0f, 0.5f )
        i = 0
        while i < 15
        {
            appC.tick( 1.0f / 15.0f )
            i = i + 1
        }
        Transform ta = ballA.transform
        Float32_3 pa = ta.localPosition
        Transform tb = ballB.transform
        Float32_3 pb = tb.localPosition
        Transform tc = ballC.transform
        Float32_3 pc = tc.localPosition
        Float32 dAB = pa.y - pb.y
        Float32 dAC = pa.y - pc.y
        if dAB < 0.0f
        {
            dAB = 0.0f - dAB
        }
        if dAC < 0.0f
        {
            dAC = 0.0f - dAC
        }
        check( dAB < 0.01f, "PH3a 1-step vs 2-step tick same y (d=" + dAB.toString() + ")" )
        check( dAC < 0.01f, "PH3b 1-step vs 4-step tick same y (d=" + dAC.toString() + ")" )
        appA.shutdown()
        appB.shutdown()
        appC.shutdown()
    }

    # ── P4 kinematic：不受重力、不休眠 ───────────────────
    static void testKinematic()
    {
        Application app = makeWorld()
        makeGround( app.activeScene )
        GameObject ball = makeBall( app.activeScene, "Ball", 3.0f, 5.0f, 0.5f )
        Rigidbody rb = bodyOf( ball )
        rb.isKinematic = true
        Int32 i = 0
        while i < 120
        {
            app.tick( 0.0166667f )
            i = i + 1
        }
        Transform t = ball.transform
        Float32_3 p = t.localPosition
        check( p.y > 4.99f, "PH4a kinematic ignores gravity (y=" + p.y.toString() + ")" )
        check( rb.velocity.length() < 0.001f, "PH4b kinematic velocity untouched" )
        check( rb.sleeping == false, "PH4c kinematic never sleeps" )
        app.shutdown()
    }

    # ── P5 addImpulse / P6 addForce（真空弹道）──────────
    static void testImpulseAndForce()
    {
        # 冲量：mass=2、impulse=(0,10,0) → v=(0,5,0)；1s 后 y ≈ 0.095
        Application app = makeWorld()
        GameObject ball = makeBall( app.activeScene, "Ball", 0.0f, 0.0f, 0.5f )
        Rigidbody rb = bodyOf( ball )
        rb.mass = 2.0f
        rb.addImpulse( Float32_3( 0.0f, 10.0f, 0.0f ) )
        check( rb.velocity.y > 4.9f && rb.velocity.y < 5.1f, "PH5a impulse -> v=i/m" )
        Int32 i = 0
        while i < 60
        {
            app.tick( 0.0166667f )
            i = i + 1
        }
        Transform t = ball.transform
        Float32_3 p = t.localPosition
        check( p.y > 0.0f - 0.3f && p.y < 0.4f, "PH5b ballistic y≈0.095 after 1s (y=" + p.y.toString() + ")" )
        app.shutdown()
        # 持续力：useGravity=false、force=(0,20,0)、mass=2 → a=10；1s 后 v≈10
        Application app2 = makeWorld()
        GameObject ball2 = makeBall( app2.activeScene, "Ball", 0.0f, 0.0f, 0.5f )
        Rigidbody rb2 = bodyOf( ball2 )
        rb2.mass = 2.0f
        rb2.useGravity = false
        Int32 k = 0
        while k < 60
        {
            rb2.addForce( Float32_3( 0.0f, 20.0f, 0.0f ) )
            app2.tick( 0.0166667f )
            k = k + 1
        }
        check( rb2.velocity.y > 9.0f && rb2.velocity.y < 11.0f, "PH6a force accumulates a=10/s (v=" + rb2.velocity.y.toString() + ")" )
        app2.shutdown()
    }

    # ── P7 drag 衰减（同高落下，高阻力下落更慢）─────────
    static void testDrag()
    {
        Application app = makeWorld()
        GameObject lo = makeBall( app.activeScene, "NoDrag", 0.0f, 50.0f, 0.5f )
        GameObject hi = makeBall( app.activeScene, "HiDrag", 5.0f, 50.0f, 0.5f )
        Rigidbody rb2 = bodyOf( hi )
        rb2.drag = 3.0f
        Int32 i = 0
        while i < 90
        {
            app.tick( 0.0166667f )
            i = i + 1
        }
        Rigidbody rb1 = bodyOf( lo )
        Transform t1 = lo.transform
        Float32_3 p1 = t1.localPosition
        Transform t2 = hi.transform
        Float32_3 p2 = t2.localPosition
        # 弹道精确值：50 - ½·9.81·1.5² ≈ 38.96（1.5s 只落 11m——顺带验积分精度）
        check( p1.y > 38.0f && p1.y < 40.0f, "PH7a free-fall matches ½gt² (y=" + p1.y.toString() + ")" )
        check( p2.y > p1.y + 1.0f, "PH7b drag slows fall (hi=" + p2.y.toString() + " lo=" + p1.y.toString() + ")" )
        check( rb2.velocity.y > rb1.velocity.y, "PH7c drag bounds terminal velocity" )
        app.shutdown()
    }

    # ── P8 休眠与唤醒 ───────────────────────────────────
    static void testSleepWake()
    {
        Application app = makeWorld()
        makeGround( app.activeScene )
        GameObject ball = makeBall( app.activeScene, "Ball", 0.0f, 0.55f, 0.5f )
        Rigidbody rb = bodyOf( ball )
        Int32 i = 0
        while i < 120
        {
            app.tick( 0.0166667f )
            i = i + 1
        }
        check( rb.sleeping, "PH8a asleep after resting 2s" )
        rb.addImpulse( Float32_3( 0.0f, 4.0f, 0.0f ) )
        check( rb.sleeping == false, "PH8b impulse wakes body" )
        check( rb.velocity.y > 1.5f, "PH8c wake preserves impulse velocity" )
        app.shutdown()
    }

    # ── P9 水平撞墙停止（法向冲量清 vx）─────────────────
    static void testWallStop()
    {
        Application app = makeWorld()
        GameObject wall = app.activeScene.createObject( "Wall" )
        wall.layer = 0
        BoxCollider wc = BoxCollider()
        wc.size = Float32_3( 0.2f, 8.0f, 8.0f )
        wall.addComponent( wc )
        Transform wt = wall.transform
        wt.setPosition( Float32_3( 0.0f, 0.0f, 0.0f ) )
        GameObject ball = makeBall( app.activeScene, "Ball", 0.0f - 4.0f, 0.5f, 0.5f )
        Rigidbody rb = bodyOf( ball )
        rb.velocity = Float32_3( 5.0f, 0.0f, 0.0f )
        Int32 i = 0
        while i < 120
        {
            app.tick( 0.0166667f )
            i = i + 1
        }
        Transform t = ball.transform
        Float32_3 p = t.localPosition
        check( p.x < 0.65f, "PH9a ball stopped before wall (x=" + p.x.toString() + ")" )
        check( rb.velocity.x < 0.3f, "PH9b vx canceled by normal impulse (vx=" + rb.velocity.x.toString() + ")" )
        app.shutdown()
    }

    # ── P10 Static 不受影响 + 高恢复系数反弹 ─────────────
    static void testStaticAndRestitutionMax()
    {
        Application app = makeWorld()
        GameObject ground = makeGround( app.activeScene )
        GameObject ball = makeBall( app.activeScene, "Ball", 0.0f, 2.0f, 0.5f )
        Rigidbody rb = bodyOf( ball )
        rb.restitution = 0.9f
        Int32 i = 0
        while i < 60
        {
            app.tick( 0.0166667f )
            i = i + 1
        }
        Transform tg = ground.transform
        Float32_3 pg = tg.localPosition
        Float32 gyOff = pg.y + 0.1f
        if gyOff < 0.0f
        {
            gyOff = 0.0f - gyOff
        }
        check( gyOff < 0.001f, "PH10a static ground unmoved (y=" + pg.y.toString() + ")" )
        Transform tb = ball.transform
        Float32_3 pb = tb.localPosition
        check( pb.y > 0.7f, "PH10b restitution 0.9 bounces high (y=" + pb.y.toString() + ")" )
        app.shutdown()
    }

    # ── PH11~PH14 CCD（doc/12 §6 方案二：选择性扫掠）────
    # 竖直薄墙世界：墙 AABB x∈[9.95,10.05]（厚 0.1 < 高速球步内位移 0.833）
    static Application makeTunnelWorld()
    {
        Application app = Application()
        app.init()
        app.fixedDt = 0.0166667f
        app.physicsSystem = PhysicsSystem()
        app.collisionSystem = CollisionSystem()
        GameObject wall = app.activeScene.createObject( "Wall" )
        wall.layer = 0
        BoxCollider wc = BoxCollider()
        wc.size = Float32_3( 0.1f, 4.0f, 4.0f )
        wall.addComponent( wc )
        Transform tw = wall.transform
        tw.setPosition( Float32_3( 10.0f, 0.0f, 0.0f ) )
        ret app
    }

    static GameObject makeBullet( Application app, Float32 r, bool ccd )
    {
        GameObject ball = app.activeScene.createObject( "Bullet" )
        ball.layer = 0
        SphereCollider sc = SphereCollider()
        sc.radius = r
        ball.addComponent( sc )
        Rigidbody rb = Rigidbody()
        rb.ccdEnabled = ccd
        rb.ccdRadius = r
        ball.addComponent( rb )
        Transform t = ball.transform
        t.setPosition( Float32_3( 0.0f, 0.0f, 0.0f ) )
        rb.velocity = Float32_3( 50.0f, 0.0f, 0.0f )
        ret ball
    }

    static void testCcdTunnel()
    {
        # 无 CCD 对照：离散检测必穿（步内位移 0.833 > 墙厚 0.1 + 球径 0.5）
        Application app1 = makeTunnelWorld()
        GameObject b1 = makeBullet( app1, 0.25f, false )
        Int32 i = 0
        while i < 60
        {
            app1.tick( 0.0166667f )
            i = i + 1
        }
        Transform t1 = b1.transform
        Float32_3 p1 = t1.localPosition
        check( p1.x > 12.0f, "PH11a no-CCD bullet tunnels through thin wall (x=" + p1.x.toString() + ")" )
        app1.shutdown()

        # 有 CCD：钳在墙前（球面贴墙 x≈9.95 → 中心 ≈9.7），法向速度清零
        Application app2 = makeTunnelWorld()
        GameObject b2 = makeBullet( app2, 0.25f, true )
        Int32 j = 0
        while j < 60
        {
            app2.tick( 0.0166667f )
            j = j + 1
        }
        Transform t2 = b2.transform
        Float32_3 p2 = t2.localPosition
        check( p2.x > 9.3f && p2.x < 9.95f, "PH12a CCD bullet stopped before wall (x=" + p2.x.toString() + ")" )
        Rigidbody rb2 = bodyOf( b2 )
        check( rb2.velocity.x < 0.01f && rb2.velocity.x > 0.0f - 0.01f, "PH12b CCD clears normal velocity" )
        app2.shutdown()
    }

    static void testCcdSlowUnaffected()
    {
        # CCD 开启的慢速球不受影响：正常落地静止入睡
        Application app = makeWorld()
        makeGround( app.activeScene )
        GameObject ball = makeBall( app.activeScene, "Ball", 0.0f, 5.0f, 0.5f )
        Rigidbody rb = bodyOf( ball )
        rb.ccdEnabled = true
        Int32 i = 0
        while i < 300
        {
            app.tick( 0.0166667f )
            i = i + 1
        }
        Transform t = ball.transform
        Float32_3 p = t.localPosition
        check( p.y > 0.4f && p.y < 0.8f, "PH13a slow CCD ball rests normally (y=" + p.y.toString() + ")" )
        check( rb.sleeping, "PH13b slow CCD ball sleeps" )
    }

    static void testCcdTangentKept()
    {
        # 斜向高速：CCD 清法向（x）分量、保留切向（y）
        Application app = makeTunnelWorld()
        GameObject ball = app.activeScene.createObject( "Bullet" )
        ball.layer = 0
        SphereCollider sc = SphereCollider()
        sc.radius = 0.25f
        ball.addComponent( sc )
        Rigidbody rb = Rigidbody()
        rb.ccdEnabled = true
        rb.ccdRadius = 0.25f
        ball.addComponent( rb )
        Transform t = ball.transform
        t.setPosition( Float32_3( 0.0f, 2.0f, 0.0f ) )
        rb.velocity = Float32_3( 30.0f, 0.0f - 5.0f, 0.0f )
        Int32 i = 0
        while i < 60
        {
            app.tick( 0.0166667f )
            i = i + 1
        }
        Transform t2 = ball.transform
        Float32_3 p = t2.localPosition
        check( p.x < 9.95f, "PH14a angled bullet stopped before wall (x=" + p.x.toString() + ")" )
        check( rb.velocity.x < 0.01f && rb.velocity.x > 0.0f - 0.01f, "PH14b normal (x) component cleared" )
        check( rb.velocity.y < 0.0f - 3.0f, "PH14c tangent (y) component kept (vy=" + rb.velocity.y.toString() + ")" )
    }

    public static void run()
    {
        Console.println( "=== SimPhysicsTest (SimGameEngine P4 physics smoke) ===" )
        testFallAndRest()
        testBounceDecay()
        testFrameRateIndependence()
        testKinematic()
        testImpulseAndForce()
        testDrag()
        testSleepWake()
        testWallStop()
        testStaticAndRestitutionMax()
        testCcdTunnel()
        testCcdSlowUnaffected()
        testCcdTangentKept()
        Console.println( "PASS=" + _pass.toString() + " FAIL=" + _fail.toString() )
    }

    # 计数读取（Test.sl 统一入口汇总用；不单独 exit，失败由入口统一判）
    public static Int32 passCount()
    {
        ret _pass
    }

    public static Int32 failCount()
    {
        ret _fail
    }
}
