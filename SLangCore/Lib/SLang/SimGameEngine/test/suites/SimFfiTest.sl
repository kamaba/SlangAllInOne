import SimGameEngine;
import Math;
import Std;

# ============================================================================
# SimFfiTest — C99 原生库（sl_sim_engine_lib）绑定与功能冒烟
# ----------------------------------------------------------------------------
# 覆盖：FFI 绑定生效（计数/注册/注销）、时钟单调性、定时器流逝、
# GameObject 接线（createObject 注册 nodeId / find 走 C 哈希 / destroy 注销 /
# 重名拒绝）、活跃标志同步。
# 绑定失败兜底征兆：libNodeCount 恒 0 且注册不生效——本测试会 FAIL。
# ============================================================================

public class SimFfiTest
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

    # ── 1. 时钟单调 + 间隔（等待循环带迭代上限——绑定失败兜底 0 时防死循环）──
    static void testClock()
    {
        Int64 t0 = EngineClock.nowUs()
        Int64 t1 = EngineClock.nowUs()
        check( t1 >= t0, "F1a clock monotonic" )
        check( t0 > 0, "F1b ffi bound (nowUs > 0; 0 = fallback)" )
        # busy 等待 ~2ms（迭代上限防死循环）
        Int64 deadline = EngineClock.nowUs() + 2000
        Int32 spins = 0
        while EngineClock.nowUs() < deadline
        {
            spins = spins + 1
            if spins > 5000000
            {
                break
            }
        }
        Int64 t2 = EngineClock.nowUs()
        check( t2 - t0 >= 2000, "F1c clock advances >= 2ms" )
        # mark：帧间隔采样
        EngineClock.mark()
        Int64 deadline2 = EngineClock.nowUs() + 1500
        spins = 0
        while EngineClock.nowUs() < deadline2
        {
            spins = spins + 1
            if spins > 5000000
            {
                break
            }
        }
        Int64 d = EngineClock.mark()
        check( d >= 1500, "F1d mark delta >= 1.5ms" )
    }

    # ── 2. 定时器 ───────────────────────────────────────
    static void testTimer()
    {
        Timer tm = Timer.create()
        check( tm.valid(), "F2a timer handle allocated" )
        tm.start()
        Int64 deadline = EngineClock.nowUs() + 3000
        Int32 spins = 0
        while EngineClock.nowUs() < deadline
        {
            spins = spins + 1
            if spins > 5000000
            {
                break
            }
        }
        Int64 el = tm.elapsedMs()
        check( el >= 2, "F2b elapsed >= 3ms (ms granularity)" )
        tm.reset()
        Int64 el0 = tm.elapsedMs()
        check( el0 < 2, "F2c reset clears accumulation" )
        tm.destroy()
        check( tm.valid() == false, "F2d destroy releases handle" )
    }

    # ── 3. 节点注册表直连 ───────────────────────────────
    static void testRegistryDirect()
    {
        Int32 before = NodeRegistry.count()
        Int64 id = NodeRegistry.registerNode( "FfiProbe", "probe", 3 )
        check( id > 0, "F3a register returns id" )
        Int32 after = NodeRegistry.count()
        check( after == before + 1, "F3b count increments" )
        Int64 hit = NodeRegistry.findByName( "FfiProbe" )
        check( hit == id, "F3c hash find by name O(1)" )
        check( NodeRegistry.isActive( id ) == true, "F3d default active" )
        bool lay = NodeRegistry.setLayer( id, 5 )
        check( lay == true, "F3e setLayer" )
        string nm = NodeRegistry.nameOf( id )
        check( nm == "FfiProbe", "F3f nameOf roundtrip" )
        check( NodeRegistry.unregister( id ) == true, "F3g unregister" )
        check( NodeRegistry.findByName( "FfiProbe" ) == 0, "F3h gone after unregister" )
    }

    # ── 4. GameObject 接线（createObject/destroy/重名）──
    static void testGameObjectIntegration()
    {
        Scene scene = Scene( "F4" )
        GameObject a = scene.createObject( "NodeA" )
        check( a.nodeId > 0, "F4a createObject registers node" )
        GameObject b = scene.createObject( "NodeB" )
        check( b.nodeId > 0 && b.nodeId != a.nodeId, "F4b distinct ids" )
        # find 走 C 哈希分支（裸名单段）
        GameObject hit = scene.find( "NodeA" )
        check( hit == a, "F4c find via C registry hash" )
        # 重名注册拒绝（第二个 nodeId == 0，场景仍持有对象）
        GameObject dup = scene.createObject( "NodeA" )
        check( dup.nodeId == 0, "F4d duplicate name rejected by registry" )
        # destroy 注销
        a.destroy()
        scene.processDestroys()
        check( a.nodeId == 0, "F4e destroy unregisters" )
        check( NodeRegistry.findByName( "NodeA" ) == 0, "F4f registry find gone" )
        # 活跃标志同步
        check( NodeRegistry.isActive( b.nodeId ) == true, "F4g active default" )
        b.setActive( false )
        check( NodeRegistry.isActive( b.nodeId ) == false, "F4h setActive syncs registry" )
    }

    public static void run()
    {
        Console.println( "=== SimFfiTest (sl_sim_engine_lib FFI smoke) ===" )
        testClock()
        testTimer()
        testRegistryDirect()
        testGameObjectIntegration()
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
