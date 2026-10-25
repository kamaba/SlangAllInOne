import Std;
import Core;
import SLangServer;

# ============================================================================
# ServerP4Test.sl -- SLangServer P4 验收（ServerTest 宿主）
# 设计契约：SERVER_DESIGN.md §8 P4 验收 / §4.10 控制器语法 / §7 P4 方案
#
#   T1  attribute 路由端到端：usePreloadRoutes() 条数 == 控制器方法数（6）
#       + @OnRoute 类前缀拼接（@OnPost("/user") -> POST /p4admin/user）
#       + @Route 双参小写 verb 由 C 侧大写化（"delete" -> DELETE）+ pathParam
#       + 每请求一实例（LATE 实例闭包：实例字段 hits 两次请求均 == 1）
#       + 无前缀 @OnGet/@OnAny 直挂（@OnAny 双动词命中 + req.method 回显）
#       + 与动态注册共存（闭包注册与 attribute 注册统一生效）
#       + 404 未知路径 / 405 + Allow（attribute 入表动词精确性）
#   T2  异步与超时（cfg.handlerTimeoutMs=200）：协程内 delay(150) 正常应答
#       / delay(400) 超时 -> cancel + 504 + 优雅断连（LATE 闭包协程可取消）
#   T3  usePreloadRoutes 重复接线 -> start() fail-fast（DuplicateRoute）
#
# 端口：19441-19443（P1=19401-08 / P1.5=19411-13 / P2=19421-24 / P3=19431-35）。
# 编写约定同 ServerP1Test.sl（check/sfFind/sfReadResp/respBodyDone/rawReq
# 助手同款实现）。
#
# 机制回顾（§4.10 / §7）：控制器类 + 方法在装配期（Preload）经 C VM
# vm_route_attribute.c 收集——方法级条目入路由表、类级 @OnRoute 记前缀
# join 出 "verb|path|class|method" 行；usePreloadRoutes() 拉取入 Router，
# handler 为 LATE 实例闭包（每请求实例化全新控制器，this + req/res 两参）。
# ============================================================================

# ── 控制器 1：类级 @OnRoute("/p4admin") 前缀（Spring RequestMapping 形态）──

@OnRoute( "/p4admin" )
class P4AdminController
{
    Int32 hits = 0

    _init_()
    {
        this.hits = 0
    }

    # -> POST /p4admin/user（类前缀 + 方法 path 拼接）
    # 实例字段 hits：每请求一实例（LATE 闭包每请求新实例）-> 恒 hits=1
    @OnPost( "/user" )
    public void saveUser( SLang.Request req, SLang.Response res )
    {
        this.hits = this.hits + 1
        res.text( "hits=" + this.hits.toString() + ",body=" + req.bodyText() )
    }

    # -> DELETE /p4admin/user/{id}（双参 @Route：args[0]=path / args[1]=verb，
    # 小写 "delete" 由 C 侧 s_toupper_dup 大写化）
    @Route( "/user/{id}", "delete" )
    public void delUser( SLang.Request req, SLang.Response res )
    {
        res.text( "del:" + req.pathParam( "id" ) )
    }
}

# ── 控制器 2：无类前缀直挂 ──

class P4PlainController
{
    _init_()
    {
    }

    # -> GET /p4plain
    @OnGet( "/p4plain" )
    public void plainGet( SLang.Request req, SLang.Response res )
    {
        res.text( "plain-ok" )
    }

    # -> ANY /p4any（全动词；req.method 回显命中动词）
    @OnAny( "/p4any" )
    public void anyEcho( SLang.Request req, SLang.Response res )
    {
        res.text( "any:" + req.method )
    }
}

# ── 控制器 3：异步 / 超时（T2 配 handlerTimeoutMs=200）──

class P4AsyncController
{
    _init_()
    {
    }

    # -> GET /p4async（协程内 delay 合法，G12：await/yield/delay；150ms < 200ms）
    @OnGet( "/p4async" )
    public void asyncOk( SLang.Request req, SLang.Response res )
    {
        Coroutine.delay( 150 )
        res.text( "async-ok" )
    }

    # -> GET /p4slow（400ms > 200ms：协程 cancel + 504 + 优雅断连）
    @OnGet( "/p4slow" )
    public void slow( SLang.Request req, SLang.Response res )
    {
        Coroutine.delay( 400 )
        res.text( "slow-done" )
    }
}

ServerP4Test
{
    static check( string name, bool cond )
    {
        if cond
        {
            Console.println( "[ServerP4Test] " + name + " : OK" )
        }
        else
        {
            Console.println( "[ServerP4Test] " + name + " : FAIL" )
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
                Int32 he = ServerP4Test.sfFind( text, "\r\n\r\n" )
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
                elif ServerP4Test.respBodyDone( text, headerEnd )
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
        Int32 pos = ServerP4Test.sfFind( text, pat )
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
        string r = ServerP4Test.sfReadResp( ns, false )
        c.close()
        ret r
    }

    # ── T1 attribute 路由端到端 ──

    static void t1Preload()
    {
        Console.println( "[ServerP4Test] T1 begin" )
        SLang.Server app = SLang.Server( 19441 )
        app.reset()

        # T1a 装配期路由表条数 == 控制器方法数（2+2+2=6 全量并入）
        Int32 n = app.usePreloadRoutes()
        ServerP4Test.check( "T1a preload count == 6", n == 6 )

        # 动态注册共存（闭包注册与 attribute 注册统一生效）
        function hDyn = function( SLang.Request req, SLang.Response res )
        {
            res.text( "dyn-ok" )
        }
        app.onGet( "/p4dyn", hDyn )
        app.start( 19441 )

        # T1b @OnRoute 类前缀拼接 + body 回显（POST /p4admin/user）
        Net.HttpResponse r1 = Net.HttpClient.httpPost( "http://127.0.0.1:19441/p4admin/user", "data1", "text/plain" )
        ServerP4Test.check( "T1b OnRoute prefix join", r1.statusCode == 200 && r1.body == "hits=1,body=data1" )

        # T1c 每请求一实例（LATE 闭包：第二次请求实例字段复位 -> 仍 hits=1）
        Net.HttpResponse r2 = Net.HttpClient.httpPost( "http://127.0.0.1:19441/p4admin/user", "data2", "text/plain" )
        ServerP4Test.check( "T1c per-request instance", r2.statusCode == 200 && r2.body == "hits=1,body=data2" )

        # T1d @Route 双参 + 小写 verb 大写化 + pathParam（DELETE /p4admin/user/77）
        string rd = ServerP4Test.rawReq( 19441, "DELETE /p4admin/user/77 HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n" )
        ServerP4Test.check( "T1d Route dual-arg DELETE", sfFind( rd, "200" ) >= 0 && sfFind( rd, "del:77" ) >= 0 )

        # T1e 无前缀 @OnGet 直挂
        Net.HttpResponse r3 = Net.HttpClient.httpGet( "http://127.0.0.1:19441/p4plain" )
        ServerP4Test.check( "T1e plain OnGet", r3.statusCode == 200 && r3.body == "plain-ok" )

        # T1f @OnAny 双动词命中（req.method 回显命中动词）
        string ra1 = ServerP4Test.rawReq( 19441, "POST /p4any HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Length: 0\r\n\r\n" )
        string ra2 = ServerP4Test.rawReq( 19441, "PUT /p4any HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Length: 0\r\n\r\n" )
        ServerP4Test.check( "T1f OnAny two verbs", sfFind( ra1, "any:POST" ) >= 0 && sfFind( ra2, "any:PUT" ) >= 0 )

        # T1g 动态注册共存
        Net.HttpResponse r4 = Net.HttpClient.httpGet( "http://127.0.0.1:19441/p4dyn" )
        ServerP4Test.check( "T1g dynamic coexists", r4.statusCode == 200 && r4.body == "dyn-ok" )

        # T1h 404（未注册路径）
        Net.HttpResponse r5 = Net.HttpClient.httpGet( "http://127.0.0.1:19441/p4none" )
        ServerP4Test.check( "T1h 404 unknown", r5.statusCode == 404 )

        # T1i 405 + Allow（/p4admin/user 仅注册 POST）
        Net.HttpResponse r6 = Net.HttpClient.httpGet( "http://127.0.0.1:19441/p4admin/user" )
        ServerP4Test.check( "T1i 405 + Allow", r6.statusCode == 405 && r6.headers.getHeader( "Allow" ) == "POST" )

        app.stop()
    }

    # ── T2 异步与超时（handlerTimeoutMs=200）──

    static void t2AsyncTimeout()
    {
        Console.println( "[ServerP4Test] T2 begin" )
        SLang.Server app = SLang.Server( 19442 )
        SLang.ServerConfig cfg = app.config
        cfg.handlerTimeoutMs = 200
        app.reset()
        app.usePreloadRoutes()
        app.start( 19442 )

        # T2a 协程内 delay 正常异步应答（150ms < 200ms）
        string ra = ServerP4Test.rawReq( 19442, "GET /p4async HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n" )
        ServerP4Test.check( "T2a async delay ok", sfFind( ra, "200" ) >= 0 && sfFind( ra, "async-ok" ) >= 0 )

        # T2b handler 超时 504（400ms > 200ms：协程 cancel + 504 + 优雅断连；
        # rawReq 客户端读满 504 短响应）
        string rs = ServerP4Test.rawReq( 19442, "GET /p4slow HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n" )
        ServerP4Test.check( "T2b timeout 504", sfFind( rs, "504" ) >= 0 && sfFind( rs, "slow-done" ) < 0 )

        app.stop()
    }

    # ── T3 重复接线 -> start fail-fast（DuplicateRoute）──

    static void t3Duplicate()
    {
        Console.println( "[ServerP4Test] T3 begin" )
        SLang.Server app = SLang.Server( 19443 )
        app.reset()

        # 两次拉取：C 表装配期快照不变，每次均并入 6 条（Router.add 不查重）
        app.usePreloadRoutes()
        Int32 n2 = app.usePreloadRoutes()
        ServerP4Test.check( "T3a second pull still 6", n2 == 6 )

        # start() fail-fast：同 verb+pattern 重复注册抛 DuplicateRoute 且不监听
        bool threw = false
        label startDup
        {
            app.start( 19443 )
        }
        catch
        {
            threw = true
        }
        ServerP4Test.check( "T3b duplicate fail-fast", threw && app.isRunning == false )
    }

    static fun()
    {
        ServerP4Test.t1Preload()
        ServerP4Test.t2AsyncTimeout()
        ServerP4Test.t3Duplicate()
        Console.println( "[ServerP4Test] all done" )
    }
}
