import SimGameEngine;
import SLangRender;
import Std;
import SLangRender;
import Math;
import SLangRender;

# ============================================================================
# SimCollisionTest — SimGameEngine P3 碰撞检测冒烟验证
# ----------------------------------------------------------------------------
# 覆盖：box/box Enter→Stay→Exit 生命周期、触发器事件（onTrigger* 而非
# onCollision*）、box/box 最小穿透轴深度、球/球、球/盒混合对、碰撞矩阵
# 过滤、Application 固定步集成（tick 内自动 step）。
# 探针（HitBox/HitSphere extends 具体碰撞体）override 计数——事件经
# SystemSimEngineCallHook1/2 按名派发到最派生 override（doc/10 §6）。
# ============================================================================

public class HitBox extends BoxCollider
{
    public Int32 enterCount = 0
    public Int32 stayCount = 0
    public Int32 exitCount = 0
    public Int32 trigEnter = 0
    public Int32 trigStay = 0
    public Int32 trigExit = 0
    public Float32 lastPen = 0.0f

    public override void onCollisionEnter( Behaviour other, ContactInfo info )
    {
        this.enterCount = this.enterCount + 1
        this.lastPen = info.penetration
    }

    public override void onCollisionStay( Behaviour other, ContactInfo info )
    {
        this.stayCount = this.stayCount + 1
    }

    public override void onCollisionExit( Behaviour other )
    {
        this.exitCount = this.exitCount + 1
    }

    public override void onTriggerEnter( Behaviour other )
    {
        this.trigEnter = this.trigEnter + 1
    }

    public override void onTriggerStay( Behaviour other )
    {
        this.trigStay = this.trigStay + 1
    }

    public override void onTriggerExit( Behaviour other )
    {
        this.trigExit = this.trigExit + 1
    }
}

public class HitSphere extends SphereCollider
{
    public Int32 enterCount = 0
    public Int32 exitCount = 0
    public Int32 trigEnter = 0

    public override void onCollisionEnter( Behaviour other, ContactInfo info )
    {
        this.enterCount = this.enterCount + 1
    }

    public override void onCollisionExit( Behaviour other )
    {
        this.exitCount = this.exitCount + 1
    }

    public override void onTriggerEnter( Behaviour other )
    {
        this.trigEnter = this.trigEnter + 1
    }
}

public class HitCapsule extends CapsuleCollider
{
    public Int32 enterCount = 0
    public Int32 exitCount = 0
    public Int32 trigEnter = 0
    public Float32 lastPen = 0.0f
    public Float32 lastNx = 0.0f
    public Float32 lastNy = 0.0f

    public override void onCollisionEnter( Behaviour other, ContactInfo info )
    {
        this.enterCount = this.enterCount + 1
        this.lastPen = info.penetration
        this.lastNx = info.normal.x
        this.lastNy = info.normal.y
    }

    public override void onCollisionExit( Behaviour other )
    {
        this.exitCount = this.exitCount + 1
    }

    public override void onTriggerEnter( Behaviour other )
    {
        this.trigEnter = this.trigEnter + 1
    }
}

public class SimCollisionTest
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

    # 造「节点 + HitBox」，世界位置 (x,y,z)
    static HitBox placeBox( Scene scene, string name, Float32 x, Float32 y, Float32 z )
    {
        GameObject go = scene.createObject( name )
        go.layer = 0
        HitBox hb = HitBox()
        go.addComponent( hb )
        Transform t = go.transform
        t.setPosition( Float32_3( x, y, z ) )
        ret hb
    }

    static HitSphere placeSphere( Scene scene, string name, Float32 x, Float32 y, Float32 z, Float32 r )
    {
        GameObject go = scene.createObject( name )
        go.layer = 0
        HitSphere hs = HitSphere()
        hs.radius = r
        go.addComponent( hs )
        Transform t = go.transform
        t.setPosition( Float32_3( x, y, z ) )
        ret hs
    }

    # ── 1. box/box Enter → Stay → Exit ──────────────────
    static void testBoxLifecycle()
    {
        Scene scene = Scene( "C1" )
        HitBox a = placeBox( scene, "A", 0.0f, 0.0f, 0.0f )
        HitBox b = placeBox( scene, "B", 0.5f, 0.0f, 0.0f )
        CollisionSystem cs = CollisionSystem()
        cs.step( scene )
        Int32 ae = a.enterCount
        Int32 be = b.enterCount
        check( ae == 1, "C1a A onCollisionEnter once" )
        check( be == 1, "C1b B onCollisionEnter once" )
        Int32 as0 = a.stayCount
        check( as0 == 0, "C1c enter step has no stay" )
        # 第二步：仍重叠 → Stay
        cs.step( scene )
        Int32 as2 = a.stayCount
        Int32 ae2 = a.enterCount
        check( ae2 == 1, "C1d no duplicate enter" )
        check( as2 == 1, "C1e stay on second step" )
        # 分离 → Exit
        Transform tb = b.owner.transform
        tb.setPosition( Float32_3( 50.0f, 0.0f, 0.0f ) )
        cs.step( scene )
        Int32 ax = a.exitCount
        Int32 bx = b.exitCount
        check( ax == 1, "C1f A onCollisionExit" )
        check( bx == 1, "C1g B onCollisionExit" )
        # 再步：无新事件
        cs.step( scene )
        Int32 ax2 = a.exitCount
        check( ax2 == 1, "C1h exit fires once" )
    }

    # ── 2. 穿透深度（最小穿透轴）────────────────────────
    static void testPenetration()
    {
        Scene scene = Scene( "C2" )
        HitBox a = placeBox( scene, "A", 0.0f, 0.0f, 0.0f )
        HitBox b = placeBox( scene, "B", 0.5f, 0.0f, 0.0f )
        CollisionSystem cs = CollisionSystem()
        cs.step( scene )
        # 两单位盒中心距 0.5 → X 重叠 0.5、Y/Z 重叠 1.0 → 最小轴 pen = 0.5
        Float32 pen = a.lastPen
        bool ok = ( pen > 0.49f ) && ( pen < 0.51f )
        check( ok, "C2a min-axis penetration ~= 0.5" )
    }

    # ── 3. 触发器（onTrigger* 而非 onCollision*）────────
    static void testTriggerEvents()
    {
        Scene scene = Scene( "C3" )
        HitBox trigger = placeBox( scene, "T", 0.0f, 0.0f, 0.0f )
        trigger.isTrigger = true
        HitBox solid = placeBox( scene, "S", 0.5f, 0.0f, 0.0f )
        CollisionSystem cs = CollisionSystem()
        cs.step( scene )
        Int32 te = trigger.trigEnter
        Int32 se = solid.trigEnter
        Int32 ce = trigger.enterCount
        check( te == 1, "C3a trigger pair fires onTriggerEnter (T side)" )
        check( se == 1, "C3b trigger pair fires onTriggerEnter (S side)" )
        check( ce == 0, "C3c no onCollisionEnter for trigger pair" )
        Transform ts = solid.owner.transform
        ts.setPosition( Float32_3( 50.0f, 0.0f, 0.0f ) )
        cs.step( scene )
        Int32 tx = trigger.trigExit
        check( tx == 1, "C3d onTriggerExit on separation" )
    }

    # ── 4. 球/球 ────────────────────────────────────────
    static void testSphereSphere()
    {
        Scene scene = Scene( "C4" )
        HitSphere a = placeSphere( scene, "SA", 0.0f, 0.0f, 0.0f, 1.0f )
        HitSphere b = placeSphere( scene, "SB", 1.5f, 0.0f, 0.0f, 1.0f )
        CollisionSystem cs = CollisionSystem()
        cs.step( scene )
        Int32 ae = a.enterCount
        check( ae == 1, "C4a sphere/sphere overlap contact" )
        Transform tb = b.owner.transform
        tb.setPosition( Float32_3( 50.0f, 0.0f, 0.0f ) )
        cs.step( scene )
        Int32 ax = a.exitCount
        check( ax == 1, "C4b sphere/sphere exit" )
    }

    # ── 5. 球/盒混合对 ──────────────────────────────────
    static void testMixedPair()
    {
        Scene scene = Scene( "C5" )
        HitSphere s = placeSphere( scene, "S", 0.9f, 0.0f, 0.0f, 0.5f )
        HitBox b = placeBox( scene, "B", 0.0f, 0.0f, 0.0f )
        CollisionSystem cs = CollisionSystem()
        cs.step( scene )
        Int32 se = s.enterCount
        check( se == 1, "C5a sphere-box mixed pair contact" )
        Transform tb = b.owner.transform
        tb.setPosition( Float32_3( 50.0f, 0.0f, 0.0f ) )
        cs.step( scene )
        Int32 sx = s.exitCount
        check( sx == 1, "C5b mixed pair exit" )
    }

    # ── 6. 碰撞矩阵过滤 ─────────────────────────────────
    static void testCollisionMatrix()
    {
        Scene scene = Scene( "C6" )
        GameObject ga = scene.createObject( "A" )
        ga.layer = 0
        HitBox ha = HitBox()
        ga.addComponent( ha )
        GameObject gb = scene.createObject( "B" )
        gb.layer = 1
        HitBox hb = HitBox()
        gb.addComponent( hb )
        CollisionSystem cs = CollisionSystem()
        cs.setLayerMask( 1, 0 )
        cs.step( scene )
        Int32 ae = ha.enterCount
        check( ae == 0, "C6a matrix blocks layer0 vs layer1" )
        cs.setLayerMask( 1, 0x7FFFFFFF )
        cs.step( scene )
        Int32 ae2 = ha.enterCount
        check( ae2 == 1, "C6b matrix restored allows contact" )
    }

    # ── 7. Application 固定步集成 ───────────────────────
    static void testAppIntegration()
    {
        Application app = Application()
        app.init()
        app.fixedDt = 0.1f
        CollisionSystem cs = CollisionSystem()
        app.collisionSystem = cs
        Scene scene = app.activeScene
        HitBox a = placeBox( scene, "A", 0.0f, 0.0f, 0.0f )
        HitBox b = placeBox( scene, "B", 0.5f, 0.0f, 0.0f )
        app.tick( 0.1f )
        Int32 ae = a.enterCount
        check( ae == 1, "C7a app.tick drives collision step (enter)" )
        # paused：不推进
        app.paused = true
        app.tick( 0.1f )
        Int32 st0 = a.stayCount
        check( st0 == 0, "C7b paused freezes collision" )
        app.paused = false
        app.tick( 0.1f )
        Int32 as2 = a.stayCount
        check( as2 == 1, "C7c stay on second fixed step" )
        app.shutdown()
    }

    # ── 8. 不重叠无事件 ─────────────────────────────────
    static void testNoOverlap()
    {
        Scene scene = Scene( "C8" )
        HitBox a = placeBox( scene, "A", 0.0f, 0.0f, 0.0f )
        HitBox b = placeBox( scene, "B", 30.0f, 0.0f, 0.0f )
        CollisionSystem cs = CollisionSystem()
        cs.step( scene )
        Int32 ae = a.enterCount
        check( ae == 0, "C8a separated boxes no contact" )
    }

    # 造「节点 + HitCapsule」，世界位置 (x,y,z)，默认 r=0.5 / h=2.0
    static HitCapsule placeCapsule( Scene scene, string name, Float32 x, Float32 y, Float32 z )
    {
        GameObject go = scene.createObject( name )
        go.layer = 0
        HitCapsule hc = HitCapsule()
        go.addComponent( hc )
        Transform t = go.transform
        t.setPosition( Float32_3( x, y, z ) )
        ret hc
    }

    static bool near( Float32 a, Float32 b )
    {
        Float32 d = a - b
        if d < 0.0f
        {
            d = 0.0f - d
        }
        ret d < 0.001f
    }

    # ── 10. 胶囊：世界端点刷新 ──────────────────────────
    static void testCapsuleRefresh()
    {
        Scene scene = Scene( "C10" )
        HitCapsule c = placeCapsule( scene, "Cap", 0.0f, 3.0f, 0.0f )
        CollisionSystem cs = CollisionSystem()
        cs.step( scene )
        # halfSpan = 2.0/2 - 0.5 = 0.5 → A=(0,3.5,0) B=(0,2.5,0)
        check( near( c.worldA.y, 3.5f ) && near( c.worldB.y, 2.5f ), "CC1a world endpoints from center/height/radius" )
        check( near( c.worldA.x, 0.0f ) && near( c.worldB.z, 0.0f ), "CC1b endpoints x/z" )
        check( near( c.worldRadius, 0.5f ), "CC1c worldRadius = radius × scale" )
        # AABB 覆盖线段 ± 半径
        check( near( c.worldBounds.max.y, 4.0f ) && near( c.worldBounds.min.y, 2.0f ), "CC1d AABB covers caps" )
    }

    # ── 11. 胶囊/胶囊 ───────────────────────────────────
    static void testCapsuleCapsule()
    {
        Scene scene = Scene( "C11" )
        HitCapsule a = placeCapsule( scene, "A", 0.0f, 0.0f, 0.0f )
        HitCapsule b = placeCapsule( scene, "B", 1.2f, 0.0f, 0.0f )
        CollisionSystem cs = CollisionSystem()
        cs.step( scene )
        check( a.enterCount == 0, "CC2a parallel capsules gap 1.2 > 1.0 no contact" )
        Transform tb = b.owner.transform
        tb.setPosition( Float32_3( 0.8f, 0.0f, 0.0f ) )
        cs.step( scene )
        check( a.enterCount == 1, "CC2b capsules contact at gap 0.8" )
        check( near( a.lastPen, 0.2f ), "CC2c penetration = sum - dist = 0.2" )
        check( near( a.lastNx, 0.0f - 1.0f ), "CC2d normal B→A (-X)" )
        tb.setPosition( Float32_3( 50.0f, 0.0f, 0.0f ) )
        cs.step( scene )
        check( a.exitCount == 1, "CC2e capsule/capsule exit" )
    }

    # ── 12. 胶囊/球、胶囊/盒（系统级）──────────────────
    static void testCapsuleMixed()
    {
        # 场景隔离：球对在 x=0，盒对在 x=20（防 AABB 邻近误配对污染计数）
        Scene scene = Scene( "C12" )
        HitCapsule c = placeCapsule( scene, "Cap", 0.0f, 0.0f, 0.0f )
        HitSphere s = placeSphere( scene, "S", 0.9f, 0.0f, 0.0f, 0.5f )
        CollisionSystem cs = CollisionSystem()
        cs.step( scene )
        check( c.enterCount == 1, "CC3a capsule/sphere contact" )
        check( s.enterCount == 1, "CC3b both sides notified" )
        # 胶囊立在薄地板盒上：盒顶 y=0（box 缩 (4,0.2,4) 中心 -0.1）
        HitBox ground = placeBox( scene, "G", 20.0f, 0.0f - 0.1f, 0.0f )
        Transform tg = ground.owner.transform
        tg.setScale( Float32_3( 4.0f, 0.2f, 4.0f ) )
        HitCapsule cap2 = placeCapsule( scene, "Cap2", 20.0f, 0.55f, 0.0f )
        cs.step( scene )
        # worldB=(20,0.05,0)，距盒顶 0.05 < 0.5 → pen=0.45，法线 +Y（B→A ✓）
        check( cap2.enterCount == 1, "CC3c capsule resting on thin ground box" )
        check( near( cap2.lastPen, 0.45f ), "CC3d ground penetration 0.45" )
        # 配对 (A=地面, B=胶囊)：n=B→A=胶囊指向地面=-Y（物理把 B 沿 -n 推起）
        check( near( cap2.lastNy, 0.0f - 1.0f ), "CC3e ground normal -Y (B→A)" )
    }

    # ── 13. 胶囊触发器 + 碰撞矩阵 ──────────────────────
    static void testCapsuleTriggerMatrix()
    {
        Scene scene = Scene( "C13" )
        HitCapsule trigger = placeCapsule( scene, "T", 0.0f, 0.0f, 0.0f )
        trigger.isTrigger = true
        HitBox solid = placeBox( scene, "S", 0.5f, 0.0f, 0.0f )
        CollisionSystem cs = CollisionSystem()
        cs.step( scene )
        check( trigger.trigEnter == 1, "CC4a capsule trigger fires onTriggerEnter" )
        check( trigger.enterCount == 0, "CC4b no onCollisionEnter for trigger pair" )
        # 矩阵阻断（另一对）
        Scene s2 = Scene( "C13b" )
        HitCapsule a = placeCapsule( s2, "A", 0.0f, 0.0f, 0.0f )
        GameObject gb = s2.createObject( "B" )
        gb.layer = 1
        HitCapsule hb = HitCapsule()
        gb.addComponent( hb )
        CollisionSystem cs2 = CollisionSystem()
        cs2.setLayerMask( 1, 0 )
        cs2.step( s2 )
        check( a.enterCount == 0, "CC4c matrix blocks capsule pair" )
        cs2.setLayerMask( 1, 0x7FFFFFFF )
        cs2.step( s2 )
        check( a.enterCount == 1, "CC4d matrix restored allows capsule pair" )
    }

    # ── 14. 胶囊 + 物理：落地静止 ──────────────────────
    static void testCapsulePhysics()
    {
        Application app = Application()
        app.init()
        app.fixedDt = 1.0f / 60.0f
        app.physicsSystem = PhysicsSystem()
        app.collisionSystem = CollisionSystem()
        Scene scene = app.activeScene
        # 地面：顶面 y=0
        GameObject ground = scene.createObject( "Ground" )
        ground.layer = 0
        BoxCollider bc = BoxCollider()
        bc.size = Float32_3( 40.0f, 0.2f, 40.0f )
        ground.addComponent( bc )
        Transform tg = ground.transform
        tg.setPosition( Float32_3( 0.0f, 0.0f - 0.1f, 0.0f ) )
        # 胶囊刚体：r=0.5 h=2 → 静止时中心 y=1.0（worldB=0.5，底=-0+0）
        GameObject cap = scene.createObject( "Cap" )
        cap.layer = 0
        CapsuleCollider cc = CapsuleCollider()
        cc.radius = 0.5f
        cc.height = 2.0f
        cap.addComponent( cc )
        Rigidbody rb = Rigidbody()
        cap.addComponent( rb )
        Transform tc = cap.transform
        tc.setPosition( Float32_3( 0.0f, 5.0f, 0.0f ) )
        Int32 i = 0
        while i < 400
        {
            app.tick( 1.0f / 60.0f )
            i = i + 1
        }
        Float32_3 p = tc.localPosition
        check( p.y > 0.9f && p.y < 1.1f, "CC5a capsule rests at y≈1.0 on ground (y=" + p.y.toString() + ")" )
        check( rb.velocity.length() < 0.05f, "CC5b capsule velocity settled" )
        check( rb.sleeping, "CC5c capsule falls asleep" )
    }

    # ── 15. MeshCollider（v0.1 退化盒）─────────────────
    static void testMeshCollider()
    {
        # Mesh/Mesh 退化盒接触 + 分离退出
        Scene scene = Scene( "C15" )
        GameObject ga = scene.createObject( "A" )
        ga.layer = 0
        MeshCollider ma = MeshCollider()
        ma.size = Float32_3( 1.0f, 1.0f, 1.0f )
        ga.addComponent( ma )
        GameObject gb = scene.createObject( "B" )
        gb.layer = 0
        MeshCollider mb = MeshCollider()
        mb.size = Float32_3( 1.0f, 1.0f, 1.0f )
        gb.addComponent( mb )
        Transform tb = gb.transform
        tb.setPosition( Float32_3( 0.5f, 0.0f, 0.0f ) )
        CollisionSystem cs = CollisionSystem()
        cs.step( scene )
        check( cs.narrowphaseHits == 1, "CC6a mesh/mesh degraded-box contact" )
        tb.setPosition( Float32_3( 30.0f, 0.0f, 0.0f ) )
        cs.step( scene )
        check( cs.narrowphaseHits == 0, "CC6b mesh/mesh separation" )

        # Mesh/Box、Mesh/Sphere 混合对（几何隔离：Box-Sphere 对自身不相碰，
        # box(0.9,0,0) 与 sphere(0,0.95,0) 最近点距 0.602 > 0.5）
        Scene s2 = Scene( "C15b" )
        GameObject gm = s2.createObject( "M" )
        gm.layer = 0
        MeshCollider mm = MeshCollider()
        mm.size = Float32_3( 1.0f, 1.0f, 1.0f )
        gm.addComponent( mm )
        HitBox hb = placeBox( s2, "Box", 0.9f, 0.0f, 0.0f )
        HitSphere hs = placeSphere( s2, "Sph", 0.0f, 0.95f, 0.0f, 0.5f )
        CollisionSystem cs2 = CollisionSystem()
        cs2.step( s2 )
        check( cs2.narrowphaseHits == 2, "CC6g exactly mesh/box + mesh/sphere pairs" )
        check( hb.enterCount == 1, "CC6c mesh/box mixed pair (box side event)" )
        check( hs.enterCount == 1, "CC6d mesh/sphere mixed pair (sphere side event)" )

        # Mesh 触发器
        Scene s3 = Scene( "C15c" )
        GameObject gt = s3.createObject( "T" )
        gt.layer = 0
        MeshCollider mt = MeshCollider()
        mt.isTrigger = true
        gt.addComponent( mt )
        HitBox solid = placeBox( s3, "S", 0.5f, 0.0f, 0.0f )
        CollisionSystem cs3 = CollisionSystem()
        cs3.step( s3 )
        check( solid.trigEnter == 1, "CC6e mesh trigger fires onTriggerEnter" )
        check( solid.enterCount == 0, "CC6f mesh trigger no onCollisionEnter" )
    }

    # ── 9. 旋转节点 AABB 重算 ───────────────────────────
    static void testRotatedBounds()
    {
        Scene scene = Scene( "C9" )
        # 细长盒沿 X 放置并旋转 45°：AABB 对角扩展使 Z 轴也覆盖
        HitBox a = placeBox( scene, "A", 0.0f, 0.0f, 0.0f )
        Transform ta = a.owner.transform
        ta.setRotationZ( 0.7853982f )
        ta.setScale( 4.0f )
        # B 在 A 上方 z 方向附近：未旋转 AABB 时不会碰到 Z 范围，旋转后 AABB 扩大可碰到
        HitBox b = placeBox( scene, "B", 2.0f, 2.0f, 1.0f )
        CollisionSystem cs = CollisionSystem()
        cs.step( scene )
        Int32 ae = a.enterCount
        check( ae == 1, "C9 rotated AABB recomputed from transformed verts" )
    }

    public static void run()
    {
        Console.println( "=== SimCollisionTest (SimGameEngine P3 collision smoke) ===" )
        testBoxLifecycle()
        testPenetration()
        testTriggerEvents()
        testSphereSphere()
        testMixedPair()
        testCollisionMatrix()
        testAppIntegration()
        testNoOverlap()
        testRotatedBounds()
        testCapsuleRefresh()
        testCapsuleCapsule()
        testCapsuleMixed()
        testCapsuleTriggerMatrix()
        testCapsulePhysics()
        testMeshCollider()
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
