import Std;
import Core;
import SLangServer;

# ============================================================================
# ServerP9Test.sl -- SLangServer P9 验收（ServerTest 宿主）
# 设计契约：SERVER_DESIGN.md §8 P9 验收 / §26 单例控制器 / §4.10 默认每请求一实例
#
#   T1  @InstanceAttr bind-once 端到端（服务端 spawn 派发路径）：
#       preload count >= 10（P4 六条 + P9 四条全量并入）
#       + 单例控制器两请求实例字段连续递增（hits=1 -> hits=2 = 同实例
#         状态共享，首次派发 bind-once 后续复用）
#       + POST reset 改写单例字段再验证（仍同实例）
#       + 合成静态字段直接访问（P9CounterController.instance 装配期已
#         构造，类型即宿主类——instance.hits 免转型）
#       + 自定义实例名（@InstanceAttr("inst") → P9NamedController.inst）
#       + 对照无 @InstanceAttr 控制器恒 hits=1（默认每请求一实例保持）
#   T2  异步单例（cfg.handlerTimeoutMs=500）：协程 delay(120) 应答内
#       单例状态跨请求保持（spawn 路径 bind-once 与异步语义共存）
#
# 端口：19491-19492（P1=19401-08 / P1.5=19411-13 / P2=19421-24 / P3=19431-35 /
#       P4=19441-43 / P5=19451-54 / P6=19461-62 / P7=19471-72 / Bench=19481-82）。
#
# 机制回顾（§26 形态 3）：@InstanceAttr（Std）/ @On* 家族全部经 Preload
# SL 触发通道（vm_runtime_attribute_preload_enter_sl）在装配期实例化并调
# 各自 _enter_：@InstanceAttr 构造单例实例（hostClassNew）写入 Front 编译期
# 合成的静态字段（缺省名 instance / 自定义名）；@OnGet 等经
# SystemAttributeGetInstanceField 取该实例绑 hostMethodRefOf（绑定实例
# method-ref，全程复用）或 hostMethodRef()（LATE 闭包，每请求一实例）
# 注册路由。单例作用域 = 宿主类静态字段（进程级），同类全部方法共享同一实例。
# ============================================================================

# ── 控制器 1：单例计数器（类级双 attribute 叠加：@InstanceAttr + @OnRoute）──

@InstanceAttr
@OnRoute( "/p9s" )
class P9CounterController
{
    Int32 hits = 0

    _init_()
    {
        this.hits = 0
    }

    # -> GET /p9s/counter（单例：hits 跨请求连续递增）
    @OnGet( "/counter" )
    public void counter( SLang.Request req, SLang.Response res )
    {
        this.hits = this.hits + 1
        res.text( "s hits=" + this.hits.toString() )
    }

    # -> POST /p9s/reset（单例字段可被改写：reset 后 counter 从 1 重计）
    @OnPost( "/reset" )
    public void reset( SLang.Request req, SLang.Response res )
    {
        this.hits = 0
        res.text( "s reset ok" )
    }

    # -> GET /p9s/slow（协程内 delay：T2 验证异步下 bind-once 仍生效）
    @OnGet( "/slow" )
    public void slow( SLang.Request req, SLang.Response res )
    {
        Coroutine.delay( 120 )
        this.hits = this.hits + 1
        res.text( "s slow=" + this.hits.toString() )
    }
}

# ── 控制器 2：每请求一实例对照（无 @InstanceAttr，默认语义 §4.10）──

@OnRoute( "/p9f" )
class P9FreshController
{
    Int32 hits = 0

    _init_()
    {
        this.hits = 0
    }

    # -> GET /p9f/fresh（每请求新实例 -> 恒 hits=1）
    @OnGet( "/fresh" )
    public void fresh( SLang.Request req, SLang.Response res )
    {
        this.hits = this.hits + 1
        res.text( "f hits=" + this.hits.toString() )
    }
}

# ── 控制器 3：自定义实例名（@InstanceAttr("inst") → P9NamedController.inst；
#    无路由纯装配验证：合成静态字段名/写入/类型均为 InstanceAttr 契约。
#    注意：hostClassNew = NewObject 同款构造链（字段初始化器；用户 _init_
#    与 LATE 每请求一实例路径同语义不跑），故状态经字段初始化器赋初值）──

@InstanceAttr( "inst" )
class P9NamedController
{
    Int32 marks = 21

    public Int32 double()
    {
        this.marks = this.marks + this.marks
        ret this.marks
    }
}

ServerP9Test
{
    static check( string name, bool cond )
    {
        if cond
        {
            Console.println( "[ServerP9Test] " + name + " : OK" )
        }
        else
        {
            Console.println( "[ServerP9Test] " + name + " : FAIL" )
        }
    }

    # ── 通用助手（ServerP1Test 同款）──

    # 朴素子串查找（返回首匹配下标；未找到 -1；sub 空返回 0）
    static Int32 sfFind( string text, string sub )
    {
        Int32 tlen = SystemStringLength( text )
        Int32 slen = SystemStringLength( sub )
        if slen == 0
        {
            ret 0
        }
        if tlen < slen
        {
            ret -1
        }
        Int32 last = tlen - slen
        for Int32 i = 0, i <= last, i = i + 1
        {
            bool matched = true
            for Int32 j = 0, j < slen, j = j + 1
            {
                if SystemStringCharCodeAt( text, i + j ) != SystemStringCharCodeAt( sub, j )
                {
                    matched = false
                    break
                }
            }
            if matched
            {
                ret i
            }
        }
        ret -1
    }

    # 读满一条响应：头到空行 + Content-Length body
    static string sfReadResp( Net.NetStream s, bool headOnly ) throws
    {
        string text = ""
        Int32 headerEnd = -1
        Int32 bodyNeed = 0
        bool done = false
        while done == false
        {
            ByteBuffer b = ByteBuffer( 512 )
            Int32 n = s.read( b )
            if n == 0
            {
                ret text
            }
            text = text + b.readString( n )
            if headerEnd < 0
            {
                Int32 he = ServerP9Test.sfFind( text, "\r\n\r\n" )
                if he >= 0
                {
                    headerEnd = he + 4
                    # 本组用例 body 均为文本，长度即字节数，直接按串长判满
                    bodyNeed = 0
                }
            }
            if headerEnd >= 0
            {
                if headOnly
                {
                    done = true
                }
                elif ServerP9Test.respBodyDone( text, headerEnd )
                {
                    done = true
                }
            }
        }
        ret text
    }

    # Content-Length 判满（从头部文本提取；无 CL 视为 0）
    static bool respBodyDone( string text, Int32 headerEnd )
    {
        string pat = "\r\nContent-Length:"
        Int32 pos = ServerP9Test.sfFind( text, pat )
        if pos < 0 || pos > headerEnd
        {
            ret SystemStringLength( text ) >= headerEnd
        }
        Int32 i = pos + SystemStringLength( pat )
        Int32 tlen = SystemStringLength( text )
        while i < tlen && SystemStringCharCodeAt( text, i ) == 32
        {
            i = i + 1
        }
        Int32 v = 0
        bool any = false
        while i < tlen
        {
            Int32 ch = SystemStringCharCodeAt( text, i )
            if ch < 48 || ch > 57
            {
                break
            }
            v = v * 10 + ( ch - 48 )
            any = true
            i = i + 1
        }
        if any == false
        {
            ret SystemStringLength( text ) >= headerEnd
        }
        ret SystemStringLength( text ) >= headerEnd + v
    }

    # 单连接单请求（原始客户端）
    static string rawReq( Int32 port, string reqText ) throws
    {
        Net.TcpStream c = Net.Tcp.connect( "127.0.0.1", port )
        Net.NetStream ns = c
        c.write( ByteBuffer.fromString( reqText ) )
        string r = ServerP9Test.sfReadResp( ns, false )
        c.close()
        ret r
    }

    # ── T1 单例 bind-once 端到端（spawn 派发路径）──

    static void t1Singleton()
    {
        Console.println( "[ServerP9Test] T1 begin" )
        SLang.HttpServer app = SLang.HttpServer( 19491 )
        app.reset()

        # T1a 装配期路由表全量并入（P4 六条 + P9 四条）
        Int32 n = app.usePreloadRoutes()
        ServerP9Test.check( "T1a preload count >= 10", n >= 10 )

        app.start( 19491 )

        # T1b 首请求 bind-once 实例化（hits=1 与每请求一实例不可区分，
        # 与 T1c 联立方能证明单例）
        Net.HttpResponse r1 = Net.HttpClient.httpGet( "http://127.0.0.1:19491/p9s/counter" )
        ServerP9Test.check( "T1b singleton first hit", r1.statusCode == 200 && r1.body == "s hits=1" )

        # T1c 第二请求同实例状态共享（bind-once 生效的决定性证据）
        Net.HttpResponse r2 = Net.HttpClient.httpGet( "http://127.0.0.1:19491/p9s/counter" )
        ServerP9Test.check( "T1c singleton state shared (hits=2)", r2.statusCode == 200 && r2.body == "s hits=2" )

        # T1d POST 改写单例字段
        Net.HttpResponse r3 = Net.HttpClient.httpPost( "http://127.0.0.1:19491/p9s/reset", "", "text/plain" )
        ServerP9Test.check( "T1d singleton field mutated", r3.statusCode == 200 && r3.body == "s reset ok" )

        # T1e reset 后仍同实例重计（hits 回 1）
        Net.HttpResponse r4 = Net.HttpClient.httpGet( "http://127.0.0.1:19491/p9s/counter" )
        ServerP9Test.check( "T1e singleton recount after reset", r4.statusCode == 200 && r4.body == "s hits=1" )

        # T1f/T1g 对照：无 @InstanceAttr 恒 hits=1（默认每请求一实例保持）
        Net.HttpResponse r5 = Net.HttpClient.httpGet( "http://127.0.0.1:19491/p9f/fresh" )
        ServerP9Test.check( "T1f per-request baseline first", r5.statusCode == 200 && r5.body == "f hits=1" )
        Net.HttpResponse r6 = Net.HttpClient.httpGet( "http://127.0.0.1:19491/p9f/fresh" )
        ServerP9Test.check( "T1g per-request baseline kept", r6.statusCode == 200 && r6.body == "f hits=1" )

        # T1h 合成静态字段直接访问：装配期已构造（T1e 后 hits=1），类型即
        # 宿主类——instance.hits 免转型读字段
        ServerP9Test.check( "T1h direct field access (P9CounterController.instance)", P9CounterController.instance.hits == 1 )

        # T1i 自定义实例名 + 与路由派发同一实例（inst.double() 改字段后，
        # 路由侧 hits 不受影响——不同类；此处验证 inst 装配期非空 + 调用）
        ServerP9Test.check( "T1i custom field name (P9NamedController.inst)", P9NamedController.inst != null && P9NamedController.inst.double() == 42 )

        app.stop()
    }

    # ── T2 异步单例（handlerTimeoutMs=500，协程 delay 120ms）──

    static void t2AsyncSingleton()
    {
        Console.println( "[ServerP9Test] T2 begin" )
        SLang.HttpServer app = SLang.HttpServer( 19492 )
        SLang.ServerConfig cfg = app.config
        cfg.handlerTimeoutMs = 500
        app.reset()
        app.usePreloadRoutes()
        app.start( 19492 )

        # 单例为宿主类合成静态字段（进程级，§26）：T1 结束时 hits=1——先打
        # /reset 归零，再验证异步路径（协程 delay 内 bind method-ref
        # 派发 + 单例状态保持）
        Net.HttpResponse r0 = Net.HttpClient.httpPost( "http://127.0.0.1:19492/p9s/reset", "", "text/plain" )
        ServerP9Test.check( "T2 pre-reset", r0.statusCode == 200 && r0.body == "s reset ok" )

        # T2a 协程 delay 内应答（异步下单例 method-ref 派发正常）
        string ra = ServerP9Test.rawReq( 19492, "GET /p9s/slow HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n" )
        ServerP9Test.check( "T2a async singleton first", sfFind( ra, "200" ) >= 0 && sfFind( ra, "s slow=1" ) >= 0 )

        # T2b 第二次异步请求状态保持（协程派发路径单例复用）
        string rb = ServerP9Test.rawReq( 19492, "GET /p9s/slow HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n" )
        ServerP9Test.check( "T2b async singleton state kept (slow=2)", sfFind( rb, "200" ) >= 0 && sfFind( rb, "s slow=2" ) >= 0 )

        app.stop()
    }

    static fun()
    {
        ServerP9Test.t1Singleton()
        ServerP9Test.t2AsyncSingleton()
        Console.println( "[ServerP9Test] all done" )
    }
}
