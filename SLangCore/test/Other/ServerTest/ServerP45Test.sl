import Std;
import Core;

# ============================================================================
# ServerP45Test.sl -- P4.5 直接 await 糖验收（ServerTest 宿主，纯协程用例）
# 设计契约：SERVER_DESIGN.md §8 P4.5 / §7.5 糖规则
#
#   T1 直等形态（糖核心）：await 后跟「返回非 Task 的调用」一步直等——
#       T1a 静态 1 参 / T1b 静态 0 参 / T1c 静态 3 参（__awaitSpawn0..3 全档）
#       T1d 实例方法直等（receiver 链 -> NewMethodRef 实例引用 -> this 绑定）
#       T1e 目标体内 delay（spawn 协程真挂起，awaitTask 取回）
#       T1f void 返回目标直等（副作用断言）
#   T2 三条回归红线（§8 P4.5 验收）：
#       T2a 返回 Task 的调用透传不回归（makeSlowTask 与 httpGetAsync 同类型
#           学通道：调用形态 + Task 返回 -> awaitTask 换绑，spawn 不包）
#       T2b 显式 spawn 并发聚合不回归（waitAll2 + 逐个 await 取值）
#       T2c Task 变量基础形态不回归（t = spawn ...; await t as T）
#   T3 边界：
#       T3a 保守路径：函数值变量调用不进糖（返回 Task 的函数变量调用
#           依旧正确透传）
#       T3b 混用：同一协程体内直等/透传/变量三形态交错
#
# 机制（§7.5 实录形态）：parse 层把 await <调用形态> 发射为换绑标记
# Coroutine.__awaitCall( <调用原样> )；MetaCore 按实参返回类型换绑——
# Task -> awaitTask 透传；非 Task -> __awaitSpawnN(方法引用, 实参...)
# （方法引用 + spawnClosureN + awaitTask，实参在 await 点立即求值）。
# 测试体跑在协程内（awaitTask 语义要求）；root 用 waitTimeout 轮询收尾。
# ============================================================================

class P45Box
{
    Int32 mul = 10

    _init_()
    {
        this.mul = 10
    }

    # 实例方法：直等时 receiver 进方法引用闭包，this 正常绑定
    public Int32 fetchInst( Int32 v )
    {
        ret this.mul * v
    }
}

ServerP45Test
{
    static bool g_voidTouched = false

    static check( string name, bool cond )
    {
        if cond
        {
            Console.println( "[ServerP45Test] " + name + " : OK" )
        }
        else
        {
            Console.println( "[ServerP45Test] " + name + " : FAIL" )
        }
    }

    # ── 直等目标方法（返回非 Task）──

    static Int32 fetchInc( Int32 v )
    {
        Coroutine.delay( 30 )
        ret v + 1
    }

    static string fetchZero()
    {
        ret "zero"
    }

    static Int32 fetchSum3( Int32 a, Int32 b, Int32 c )
    {
        ret a + b + c
    }

    static void touchVoid()
    {
        ServerP45Test.g_voidTouched = true
    }

    static Int32 fetchSlow()
    {
        Coroutine.delay( 120 )
        ret 99
    }

    # ── 透传通道（返回 Task 的调用，与 httpGetAsync 同类型学形态）──

    static Task makeSlowTask( Int32 v )
    {
        # ret spawn function() 为无 parse 先例形态（Node 层不认 ret 后匿名闭包）：
        # 具名闭包 + spawnClosure0 直传（tmp 捕获参数 v，实参立即求值语义）
        function tmp = function()
        {
            Coroutine.delay( 60 )
            ret v
        }
        ret Coroutine.spawnClosure0( tmp )
    }

    # ── T1 直等形态 ──

    static void t1Direct()
    {
        Console.println( "[ServerP45Test] T1 begin" )

        # T1a 静态 1 参：await fetchInc( 41 ) -> spawn + awaitTask -> 42
        Int32 r1 = await ServerP45Test.fetchInc( 41 ) as Int32
        ServerP45Test.check( "T1a static 1-arg direct await", r1 == 42 )

        # T1b 静态 0 参（__awaitSpawn0 档）
        string r0 = await ServerP45Test.fetchZero() as string
        ServerP45Test.check( "T1b static 0-arg direct await", r0 == "zero" )

        # T1c 静态 3 参（__awaitSpawn3 档）
        Int32 r3 = await ServerP45Test.fetchSum3( 1, 2, 3 ) as Int32
        ServerP45Test.check( "T1c static 3-arg direct await", r3 == 6 )

        # T1d 实例方法直等：receiver 链 -> 实例方法引用 -> this 绑定
        P45Box box = P45Box()
        Int32 ri = await box.fetchInst( 5 ) as Int32
        ServerP45Test.check( "T1d instance method direct await", ri == 50 )

        # T1e 目标体内 delay：spawn 协程真挂起，awaitTask 完成后取回
        Int32 rs = await ServerP45Test.fetchSlow() as Int32
        ServerP45Test.check( "T1e delayed target direct await", rs == 99 )

        # T1f void 返回目标（await 语句形态无接收；副作用断言）
        ServerP45Test.g_voidTouched = false
        await ServerP45Test.touchVoid()
        ServerP45Test.check( "T1f void target direct await", ServerP45Test.g_voidTouched )
    }

    # ── T2 三条回归红线 ──

    static void t2Redlines()
    {
        Console.println( "[ServerP45Test] T2 begin" )

        # T2a 返回 Task 的调用透传：makeSlowTask( 7 ) 返回 Task ->
        #     awaitTask( makeSlowTask( 7 ) ) 直传（不包 spawn）
        Int32 rt = await ServerP45Test.makeSlowTask( 7 ) as Int32
        ServerP45Test.check( "T2a Task-returning call passthrough", rt == 7 )

        # T2b 显式 spawn 并发聚合：两任务显式发起 -> waitAll2 -> 逐个 await 取值
        Task t1 = spawn function()
        {
            Coroutine.delay( 40 )
            ret 10
        }
        Task t2 = spawn function()
        {
            Coroutine.delay( 40 )
            ret 20
        }
        Coroutine.waitAll2( t1, t2 )
        Int32 ra = await t1 as Int32
        Int32 rb = await t2 as Int32
        ServerP45Test.check( "T2b explicit spawn waitAll2", ra + rb == 30 )

        # T2c Task 变量基础形态
        Task tc = spawn function()
        {
            ret 9
        }
        Int32 rc = await tc as Int32
        ServerP45Test.check( "T2c Task variable basic form", rc == 9 )
    }

    # ── T3 边界 ──

    static void t3Edges()
    {
        Console.println( "[ServerP45Test] T3 begin" )

        # T3a 函数值变量调用不进糖（parse 层 IsLocalScopeDefineName 分流 ->
        #     保守 awaitTask）。注意：awaitTask 形参严格 Task 匹配，函数值调用的
        #     静态签名类型（FunctionSignature，方法引用特性产物）不兼容 Task 形参
        #     ——「await 函数值调用」形态在旧语法下同样不合法（类型系统既有局限，
        #     非 P4.5 回归），此处用中间 Task 变量承载保守两步形态。
        #     函数值来源 = 方法引用（makeSlowTask 非模板、无重载，可作引用），
        #     避免闭包嵌套（框架版闭包体不支持再定义闭包）
        function mkt = ServerP45Test.makeSlowTask
        Task t3a = mkt( 4 )
        Int32 rv = await t3a as Int32
        ServerP45Test.check( "T3a function-value call conservative path", rv == 4 )

        # T3b 三形态混用同一协程体
        Int32 m1 = await ServerP45Test.fetchInc( 1 ) as Int32
        Int32 m2 = await ServerP45Test.makeSlowTask( 5 ) as Int32
        Task m3 = spawn function()
        {
            ret 2
        }
        Int32 m4 = await m3 as Int32
        P45Box b = P45Box()
        Int32 m5 = await b.fetchInst( 3 ) as Int32
        ServerP45Test.check( "T3b mixed forms in one coroutine", m1 == 2 && m2 == 5 && m4 == 2 && m5 == 30 )
    }

    static void fun()
    {
        # 测试体跑在协程内（awaitTask 挂起语义）；root 用 waitTimeout 轮询收尾
        Task t = spawn function()
        {
            ServerP45Test.t1Direct()
            ServerP45Test.t2Redlines()
            ServerP45Test.t3Edges()
        }
        while Coroutine.waitTimeout( t, 100 ) == false
        {
            yield
        }
        Console.println( "[ServerP45Test] all done" )
    }
}
