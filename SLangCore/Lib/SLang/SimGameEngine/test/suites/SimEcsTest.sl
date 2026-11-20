import SimGameEngine;
import SLangRender;
import Std;
import Math;

# ============================================================================
# SimEcsTest — ECS 模式（doc/20）冒烟验证
# ----------------------------------------------------------------------------
# 覆盖：GameObject 只挂 Data（渲染数据拔离/逻辑集中/普通 Behaviour 拒绝）、
# 世界数据仓、集中逻辑调度与顺序、激活/禁用资格、自动分层合并键、
# Application 帧序接线、RenderSystem 统一提交。
# ============================================================================

public class SpeedData extends EcsData
{
    public Float32 speed = 1.0f
}

public class TraceLogic extends EcsLogic
{
    public static List<Int32> trace = List<Int32>( 0 )
    public Int32 updateCalls = 0
    public Int32 fixedCalls = 0

    override void update()
    {
        this.updateCalls = this.updateCalls + 1
        TraceLogic.trace.add( this.order )
    }

    override void fixedUpdate()
    {
        this.fixedCalls = this.fixedCalls + 1
    }
}

public class RejectedLogic extends Behaviour
{
    public Int32 calls = 0
}

public class SimEcsTest
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

    static MaterialData newMat( string name )
    {
        MaterialData m = MaterialData()
        m.name = name
        ret m
    }

    static GameObject makeEcs( Scene scene, string name, EcsWorld world, MaterialData mat, bool vertexData, Float32 red )
    {
        GameObject go = scene.createObject( name )
        world.register( go )
        MeshRef mr = MeshRef()
        mr.meshKind = 1
        if vertexData
        {
            mr.useQuad( 1.0f )
        }
        go.addComponent( mr )
        MaterialRef md = MaterialRef()
        md.material = mat
        if red > 0.0f
        {
            md.instanceColorOverride = true
            md.instanceColor = Float32_3( red, 0.0f, 0.0f )
        }
        go.addComponent( md )
        ret go
    }

    # ── 1. 注册 + 渲染数据拔离 ──────────────────────────
    static void testRegister()
    {
        Scene scene = Scene( "E1" )
        GameObject go = scene.createObject( "pull" )
        MeshRef mr = MeshRef()
        mr.meshKind = 1
        go.addComponent( mr )
        MaterialRef md = MaterialRef()
        md.material = newMat( "m" )
        go.addComponent( md )
        check( go.componentCount() == 3, "E1a before register has transform+mesh+mat" )
        EcsWorld world = EcsWorld()
        check( world.register( go ), "E1b register ok" )
        check( world.entityCount() == 1, "E1c entityCount 1" )
        check( go.useEcs && go.ecsWorld == world, "E1d node flagged ecs" )
        check( go.componentCount() == 1, "E1e render data pulled out of node" )
        check( world.meshOf( go ) != null, "E1f world owns mesh" )
        check( world.materialOf( go ) != null, "E1g world owns material" )
        check( world.register( go ) && world.entityCount() == 1, "E1h duplicate register is no-op" )
    }

    # ── 2. ECS 模式下 addComponent 路由 ──────────────────
    static void testRouting()
    {
        Scene scene = Scene( "E2" )
        EcsWorld world = EcsWorld()
        EcsWorld.active = world
        GameObject go = scene.createObject( "route" )
        world.register( go )
        MeshRef mr = MeshRef()
        go.addComponent( mr )
        MaterialRef md = MaterialRef()
        md.material = newMat( "m2" )
        go.addComponent( md )
        SpeedData sd = SpeedData()
        sd.kind = "speed"
        sd.speed = 2.5f
        go.addComponent( sd )
        RejectedLogic bad = RejectedLogic()
        go.addComponent( bad )
        check( go.componentCount() == 1, "E2a node still only transform" )
        check( world.meshOf( go ) != null, "E2b mesh routed to world" )
        check( world.materialOf( go ) != null, "E2c material routed to world" )
        check( world.dataOf( go, "speed" ) != null, "E2d data routed to world" )
        check( go.lastEcsReject.length > 0, "E2e plain Behaviour rejected" )
        EcsWorld.active = null
    }

    # ── 3. 世界数据仓（按实体 + 标签）────────────────────
    static void testDataStore()
    {
        Scene scene = Scene( "E3" )
        EcsWorld world = EcsWorld()
        GameObject go = scene.createObject( "data" )
        world.register( go )
        SpeedData a = SpeedData()
        a.kind = "speed"
        a.speed = 2.0f
        world.addData( go, a )
        SpeedData b = SpeedData()
        b.kind = "speed"
        b.speed = 9.0f
        world.addData( go, b )
        SpeedData c = SpeedData()
        c.kind = "alt"
        c.speed = 3.0f
        world.addData( go, c )
        check( world.dataCount( go ) == 2, "E3a same kind replaces" )
        EcsData got = world.dataOf( go, "speed" )
        SpeedData speedGot = got as SpeedData
        check( speedGot != null && speedGot.speed == 9.0f, "E3b latest value visible" )
        check( speedGot.entity == go, "E3c data back-reference" )
    }

    # ── 4. 集中逻辑调度与顺序 ────────────────────────────
    static void testLogic()
    {
        Scene scene = Scene( "E4" )
        EcsWorld world = EcsWorld()
        TraceLogic.trace.clear()
        Int32 t = 0
        while t < 3
        {
            GameObject go = scene.createObject( "logic" + t.toString() )
            world.register( go )
            TraceLogic logic = TraceLogic()
            logic.order = 3 - t
            world.addLogic( logic, go )
            t = t + 1
        }
        check( world.logic.logicCount() == 3, "E4a three logics registered" )
        Int32 before = TraceLogic.trace.length
        world.updateLogic( 0.016f )
        check( TraceLogic.trace.length - before == 3, "E4b all logics updated once" )
        Int32 idx0 = before
        Int32 idx1 = idx0 + 1
        Int32 idx2 = idx1 + 1
        Int32 order0 = TraceLogic.trace[idx0]
        Int32 order1 = TraceLogic.trace[idx1]
        Int32 order2 = TraceLogic.trace[idx2]
        check( order0 == 1 && order1 == 2 && order2 == 3, "E4c stable order by order field" )
        check( world.logic.updateCount == 3, "E4d system counter" )
        world.lateLogic( 0.016f )
        check( world.logic.lateUpdateCount == 3, "E4e late pass" )
        world.fixedLogic()
        check( world.logic.fixedUpdateCount == 3, "E4f fixed pass" )
    }

    # ── 5. 逻辑资格（禁用/非激活/待销毁）────────────────
    static void testLogicGate()
    {
        Scene scene = Scene( "E5" )
        EcsWorld world = EcsWorld()
        GameObject go = scene.createObject( "gate" )
        world.register( go )
        TraceLogic logic = TraceLogic()
        world.addLogic( logic, go )
        world.updateLogic( 0.016f )
        check( logic.updateCalls == 1, "E5a initial run" )
        logic.setEnabled( false )
        world.updateLogic( 0.016f )
        check( logic.updateCalls == 1, "E5b disabled logic skipped" )
        logic.setEnabled( true )
        go.setActive( false )
        world.updateLogic( 0.016f )
        check( logic.updateCalls == 1, "E5c inactive owner skipped" )
        go.setActive( true )
        world.updateLogic( 0.016f )
        check( logic.updateCalls == 2, "E5d re-activated" )
        world.logic.remove( logic )
        world.updateLogic( 0.016f )
        check( logic.updateCalls == 2 && world.logic.logicCount() == 0, "E5e removed logic not run" )
    }

    # ── 6. 自动分层 + 合并 ───────────────────────────────
    static void testLayers()
    {
        Scene scene = Scene( "E6" )
        EcsWorld world = EcsWorld()
        MaterialData mat = newMat( "shared" )
        Int32 i = 0
        while i < 4
        {
            makeEcs( scene, "m" + i.toString(), world, mat, true, 0.0f )
            i = i + 1
        }
        check( world.buildLayers() == 1, "E6a four same-key entities merge to one layer" )
        EcsLayer layer = world.layerAt( 0 )
        check( layer != null, "E6b layer is EcsLayer" )
        check( layer.merged && layer.mergedCount == 3, "E6c merged count" )
        check( layer.memberCount() == 4, "E6d member count" )
        check( layer.ecsSource == world, "E6e layer keeps render source" )
        List<Float32_3> verts = List<Float32_3>( 0 )
        layer.bakeVerticesInto( verts )
        check( verts.length == 24, "E6f baked vertices from world mesh store" )
        check( world.lastMergedCount == 3, "E6g world merged counter" )
    }

    # ── 7. 分层键拆批 ────────────────────────────────────
    static void testLayerSplit()
    {
        Scene s1 = Scene( "E7a" )
        EcsWorld w1 = EcsWorld()
        MaterialData mat = newMat( "m" )
        makeEcs( s1, "a", w1, mat, true, 0.0f )
        makeEcs( s1, "b", w1, mat, true, 1.0f )
        w1.buildLayers()
        check( w1.layerCount() == 2, "E7a instance color splits layer" )

        Scene s2 = Scene( "E7b" )
        EcsWorld w2 = EcsWorld()
        makeEcs( s2, "a", w2, mat, true, 0.0f )
        GameObject other = makeEcs( s2, "b", w2, mat, true, 0.0f )
        other.layer = 1
        w2.buildLayers()
        check( w2.layerCount() == 2, "E7b layer bit splits layer" )

        Scene s3 = Scene( "E7c" )
        EcsWorld w3 = EcsWorld()
        makeEcs( s3, "a", w3, mat, true, 0.0f )
        GameObject single = makeEcs( s3, "b", w3, mat, false, 0.0f )
        w3.buildLayers()
        EcsLayer bakedLayer = w3.layerAt( 0 )
        EcsLayer sl = w3.layerAt( 1 )
        check( w3.layerCount() == 2 && !bakedLayer.singleObject && sl.singleObject,
            "E7c built-in mesh takes direct path" )
    }

    # ── 8. cullMask + 注销/清空 ──────────────────────────
    static void testLifecycle()
    {
        Scene scene = Scene( "E8" )
        EcsWorld world = EcsWorld()
        MaterialData mat = newMat( "m" )
        GameObject go = makeEcs( scene, "a", world, mat, true, 0.0f )
        go.layer = 1
        world.cullMask = 1
        check( world.buildLayers() == 0, "E8a cullMask excludes layer 1" )
        world.cullMask = 0x7FFFFFFF
        check( world.buildLayers() == 1, "E8b visible again" )
        check( world.unregister( go ), "E8c unregister ok" )
        check( world.entityCount() == 0, "E8d entity removed" )
        check( go.componentCount() == 3, "E8e render data returned to node" )
        EcsWorld.active = world
        GameObject g2 = scene.createObject( "b" )
        world.register( g2 )
        world.clear()
        check( world.entityCount() == 0 && EcsWorld.active == null, "E8f clear detaches world" )
    }

    # ── 9. Application 帧序接线 ──────────────────────────
    static void testApplication()
    {
        Application app = Application()
        app.init()
        EcsWorld world = EcsWorld()
        world.attach( app )
        Scene scene = app.activeScene
        MaterialData mat = newMat( "m" )
        GameObject go = makeEcs( scene, "app", world, mat, true, 0.0f )
        TraceLogic logic = TraceLogic()
        logic.order = 1
        world.addLogic( logic, go )
        app.tick( 0.016f )
        check( app.ecsWorld == world, "E9a world attached to application" )
        check( logic.updateCalls == 1, "E9b central logic runs in tick" )
        check( world.layerCount() == 1, "E9c layers rebuilt after transform refresh" )
        world.detach()
    }

    # ── 10. 渲染层统一提交（GPU 可用时）──────────────────
    static void testRenderSubmit()
    {
        Scene scene = Scene( "E10" )
        EcsWorld world = EcsWorld()
        MaterialData mat = newMat( "m" )
        makeEcs( scene, "a", world, mat, true, 0.0f )
        makeEcs( scene, "b", world, mat, true, 0.0f )
        world.buildLayers()
        RenderSystem rs = RenderSystem()
        if !rs.init( 64, 64 )
        {
            Console.println( "[SKIP] E10 GL pipeline unavailable" )
            ret
        }
        rs.ecsSource = world
        Int32 n = rs.sync( scene )
        check( n > 0, "E10a ECS layers submitted through RenderSystem" )
        check( rs.lastSubmitted == n, "E10b lastSubmitted mirrors ECS submit" )
        rs.shutdown()
    }

    public static Int32 passCount()
    {
        ret _pass
    }

    public static Int32 failCount()
    {
        ret _fail
    }

    public static void run()
    {
        testRegister()
        testRouting()
        testDataStore()
        testLogic()
        testLogicGate()
        testLayers()
        testLayerSplit()
        testLifecycle()
        testApplication()
        testRenderSubmit()
        Console.println( "SimEcsTest PASS=" + _pass.toString() + " FAIL=" + _fail.toString() )
    }
}
