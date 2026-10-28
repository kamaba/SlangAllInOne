import Std;
import Core;
import SLangServer;

# ============================================================================
# ServerP2Test.sl -- SLangServer P2 验收（ServerTest 宿主）
# 设计契约：SERVER_DESIGN.md §8 P2 验收（§4.5 与 §4.7 示例全可运行）
#
#   T1  中间件管道：短路（401 不进 handler）/ onion 后置环顺序 /
#       userData 传值 / 404 请求同样过管道 / 插件 onInstall 立即注册 +
#       onStart/onStop 生命周期钩子
#   T2  内置插件：cors（OPTIONS 预检 204 短路 + 放行头）+ staticFiles
#       （文件直出 MIME / 未命中放行 404 / '..' 穿越 403）+ 路由共存
#   T3  流式三件套 + 超时豁免（handlerTimeoutMs=400）：
#       chunked（块编码往返 + handler 忘 close 引擎兜底）/ SSE（线格式）/
#       慢流总时长超 handlerTimeoutMs 仍完整（流式豁免）/ chunked 完成
#       后同连接 keep-alive 继续
#   T4  sendFile（大文件 160KB Content-Length + 内容对照 / 404）+
#       file() 附件头 + 通配路由 {path*}（多段/单段/空）+ wsEvents 事件糖
#       （onOpen/onMessage/onClose）
#
# 端口：19421-19424（避开 P1 19401-08 / P1.5 19411-13 / NetTest 19371-74）。
# 编写约定同 ServerP1Test/P15Test：原始 HTTP 客户端（P2RawClient 含
# chunked/Content-Length 双模式解析）+ 手搓 WS 客户端（P2WsClient）。
# 注意：SL bool.toString() 输出 "True/False"；闭包字面量须先赋变量再传参；
# 顶级 class 体内 static 方法存在 Front File 层误判（FileMetaClassClassStatic
# 把 static 成员行当类声明头）——测试全程零 static 成员，跨协程观测经
# userData / 响应头 / 文件系统回传。

# 测试插件（extends 跨模块非模板类——AttributeTest extends Core.Attribute 先例）。
# 观测机制（零 static）：onInstall 立即性 = 注册标记路由；生命周期钩子 =
# 写文件（stop 后测试侧读回断言）；mw3 trace = req.userData 拼接。
class MyP2Plugin extends SLang.ServerPlugin
{
    override public void onInstall()
    {
        # 标记路由：use() 时立即注册（onInstall 立即性观测）
        function hMark = function( SLang.Request req, SLang.Response res )
        {
            res.text( "installed" )
        }
        SLang.HttpServerCore.onGet( "/installed-mark", hMark )
        function mw = function( SLang.Request req, SLang.Response res, SLang.Next nx )
        {
            req.userData = ( req.userData as string ) + "mw3-pre|"
            nx.go()
            req.userData = ( req.userData as string ) + "mw3-post|"
            res.header( "X-Trace", req.userData as string )
        }
        SLang.HttpServerCore.use( mw )
    }

    override public void onStart()
    {
        File.writeAllText( "p2_hooks.txt", "start" )
    }

    override public void onStop()
    {
        File.appendText( "p2_hooks.txt", "|stop" )
    }
}

ServerP2Test
{
    static void check( string name, bool cond )
    {
        if cond
        {
            Console.println( "[ServerP2Test] " + name + " : OK" )
        }
        else
        {
            Console.println( "[ServerP2Test] " + name + " : FAIL" )
        }
    }

    # ── 通用助手（ServerP1Test 同款）──

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

    # 十六进制串 → Int32（chunk size 行解析；非法返回 -1）
    static Int32 p2Hex( string s )
    {
        Int32 len = SystemStringLength( s )
        if len == 0
        {
            ret -1
        }
        Int32 v = 0
        for Int32 i = 0, i < len, i = i + 1
        {
            Int32 c = SystemStringCharCodeAt( s, i )
            Int32 d = -1
            if c >= 48 && c <= 57
            {
                d = c - 48
            }
            elif c >= 97 && c <= 102
            {
                d = c - 87
            }
            elif c >= 65 && c <= 70
            {
                d = c - 55
            }

            if d < 0
            {
                ret -1
            }
            v = v * 16 + d
        }
        ret v
    }

    # 条件轮询（异步回调时序；每轮 50ms）
    static bool waitCond( Function cond, Int32 loops )
    {
        for Int32 i = 0, i < loops, i = i + 1
        {
            bool b = cond()
            if b
            {
                ret true
            }
            Coroutine.delay( 50 )
        }
        ret false
    }

    # ── T1 中间件管道 ──
    # 观测载体（零 static）：trace 全程存 req.userData（中间件↔handler 传值
    # 同槽演示）；后置环的完整 trace 写 X-Trace 响应头（header 表不受终端
    # 锁约束、引擎写出读最新值）；生命周期钩子写文件（stop 后读回）。
    static void t1Pipeline()
    {
        Console.println( "[ServerP2Test] T1 begin (port 19421)" )
        File.delete( "p2_hooks.txt" )
        SLang.HttpServer app = SLang.HttpServer( 19421 )
        app.reset()

        # 外环中间件：短路 + trace 起始 + 后置环
        function mw1 = function( SLang.Request req, SLang.Response res, SLang.Next nx )
        {
            req.userData = "mw1-pre|"
            if req.path == "/block"
            {
                res.header( "X-Trace", "mw1-pre|" )
                res.jsonFail( 401, "unauthorized", 401 )
                ret
            }
            nx.go()
            req.userData = ( req.userData as string ) + "mw1-post|"
            res.header( "X-Trace", req.userData as string )
        }
        app.use( mw1 )

        # 中间环：前置 + 后置
        function mw2 = function( SLang.Request req, SLang.Response res, SLang.Next nx )
        {
            req.userData = ( req.userData as string ) + "mw2-pre|"
            nx.go()
            req.userData = ( req.userData as string ) + "mw2-post|"
            res.header( "X-Trace", req.userData as string )
        }
        app.use( mw2 )

        # 插件（onInstall 立即注册 /installed-mark 标记路由 + mw3 +
        # onStart/onStop 文件钩子；子类实参经局部赋型上行——HttpTest 先例）
        SLang.ServerPlugin myPlugin = MyP2Plugin()
        app.use( myPlugin )

        function hOk = function( SLang.Request req, SLang.Response res )
        {
            # 进 handler 前的 pre 环序（H 段由 mw3-post 前的 userData 快照体现
            # 不进 body——body 在此定格；完整序看 X-Trace 头）
            res.text( "uid=" + ( req.userData as string ) )
        }
        app.onGet( "/ok", hOk )
        function hBlock = function( SLang.Request req, SLang.Response res )
        {
            res.text( "BLOCK-REACHED" )
        }
        app.onGet( "/block", hBlock )
        app.start()

        # T1a 短路：401 + X-Trace 仅 mw1-pre（未进 mw2/mw3/handler）
        string r1 = ServerP2Test.rawReq( 19421, "GET /block HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n" )
        ServerP2Test.check( "T1a middleware short-circuit 401",
            sfFind( r1, "401" ) >= 0 && sfFind( r1, "\"code\":401" ) >= 0
            && sfFind( r1, "X-Trace: mw1-pre|" ) >= 0
            && sfFind( r1, "BLOCK-REACHED" ) < 0 )

        # T1b onion 后置环顺序 + userData 传值（body = pre 段；
        # X-Trace 头 = 完整 onion 序）
        string r2 = ServerP2Test.rawReq( 19421, "GET /ok HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n" )
        ServerP2Test.check( "T1b onion order + userData",
            sfFind( r2, "uid=mw1-pre|mw2-pre|mw3-pre|" ) >= 0
            && sfFind( r2, "X-Trace: mw1-pre|mw2-pre|mw3-pre|mw3-post|mw2-post|mw1-post|" ) >= 0 )

        # T1c 404 请求同样过管道（尾环应答 + 后置环回程 → X-Trace 完整无 H）
        string r3 = ServerP2Test.rawReq( 19421, "GET /no-such HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n" )
        ServerP2Test.check( "T1c 404 goes through pipeline",
            sfFind( r3, "404" ) >= 0
            && sfFind( r3, "X-Trace: mw1-pre|mw2-pre|mw3-pre|mw3-post|mw2-post|mw1-post|" ) >= 0 )

        # T1d onInstall 立即性：标记路由已生效
        string r4 = ServerP2Test.rawReq( 19421, "GET /installed-mark HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n" )
        ServerP2Test.check( "T1d onInstall immediate + onStart hook",
            sfFind( r4, "installed" ) >= 0 && File.readAllText( "p2_hooks.txt" ) == "start" )

        app.stop()
        ServerP2Test.check( "T1e onStop hook", File.readAllText( "p2_hooks.txt" ) == "start|stop" )
    }

    # ── T2 内置插件（cors + staticFiles）──

    static void t2CorsStatic()
    {
        Console.println( "[ServerP2Test] T2 begin (port 19422)" )
        # 静态目录准备（框架不自动建目录——测试自建 + 写样例文件）
        if IO.Directory.exists( "p2_static" ) == false
        {
            IO.Directory.createDirectory( "p2_static" )
        }
        File.writeAllText( "p2_static/hello.txt", "static-hello" )
        File.writeAllText( "p2_static/page.html", "<h1>hi</h1>" )

        SLang.HttpServer app = SLang.HttpServer( 19422 )
        app.reset()
        app.use( SLang.Plugins.cors() )
        app.use( SLang.Plugins.staticFiles( "p2_static" ) )
        function hApi = function( SLang.Request req, SLang.Response res )
        {
            res.text( "api-ok" )
        }
        app.onGet( "/api/data", hApi )
        app.start( 19422 )

        # T2a CORS 预检：未注册路径 OPTIONS → 204 + Allow-Origin
        string r1 = ServerP2Test.rawReq( 19422, "OPTIONS /no-such HTTP/1.1\r\nHost: 127.0.0.1\r\nOrigin: http://x.test\r\nConnection: close\r\n\r\n" )
        ServerP2Test.check( "T2a cors preflight 204",
            sfFind( r1, "204" ) >= 0 && sfFind( r1, "Access-Control-Allow-Origin: *" ) >= 0 )

        # T2b 静态直出：MIME 判定
        string r2 = ServerP2Test.rawReq( 19422, "GET /hello.txt HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n" )
        ServerP2Test.check( "T2b static txt + mime",
            sfFind( r2, "200" ) >= 0 && sfFind( r2, "text/plain" ) >= 0 && sfFind( r2, "static-hello" ) >= 0 )
        string r3 = ServerP2Test.rawReq( 19422, "GET /page.html HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n" )
        ServerP2Test.check( "T2b static html mime", sfFind( r3, "text/html" ) >= 0 && sfFind( r3, "<h1>hi</h1>" ) >= 0 )

        # T2c 未命中放行 → 404 尾环 + CORS 头仍带（中间件先于尾环）
        string r4 = ServerP2Test.rawReq( 19422, "GET /missing.txt HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n" )
        ServerP2Test.check( "T2c miss -> 404 with cors header",
            sfFind( r4, "404" ) >= 0 && sfFind( r4, "Access-Control-Allow-Origin: *" ) >= 0 )

        # T2d '..' 穿越段 → 403
        string r5 = ServerP2Test.rawReq( 19422, "GET /../secret.txt HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n" )
        ServerP2Test.check( "T2d traversal -> 403", sfFind( r5, "403" ) >= 0 )

        # T2e 路由与静态共存（非静态路径放行进 handler）
        string r6 = ServerP2Test.rawReq( 19422, "GET /api/data HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n" )
        ServerP2Test.check( "T2e route + static coexist",
            sfFind( r6, "api-ok" ) >= 0 && sfFind( r6, "Access-Control-Allow-Origin: *" ) >= 0 )

        app.stop()
    }

    # ── T3 流式三件套 + 超时豁免（handlerTimeoutMs=400）──

    static void t3Stream()
    {
        Console.println( "[ServerP2Test] T3 begin (port 19423, handlerTimeoutMs=400)" )
        SLang.HttpServer app = SLang.HttpServer( 19423 )
        SLang.ServerConfig cfg = app.config
        cfg.handlerTimeoutMs = 400
        app.reset()

        function hChunk = function( SLang.Request req, SLang.Response res )
        {
            SLang.StreamWriter w = res.stream()
            w.write( "part0" )
            Coroutine.delay( 60 )
            w.write( "part1" )
            Coroutine.delay( 60 )
            w.write( "part2" )
            w.close()
        }
        app.onGet( "/chunk", hChunk )

        function hNoClose = function( SLang.Request req, SLang.Response res )
        {
            SLang.StreamWriter w = res.stream()
            w.write( "nc-data" )
            # 刻意不调 close()——引擎兜底补终止块
        }
        app.onGet( "/noclose", hNoClose )

        function hSse = function( SLang.Request req, SLang.Response res )
        {
            SLang.SseWriter sse = res.sse()
            sse.sendEvent( "progress", "10" )
            sse.comment( "ka" )
            sse.send( "done" )
            sse.close()
        }
        app.onGet( "/sse", hSse )

        function hSlow = function( SLang.Request req, SLang.Response res )
        {
            SLang.StreamWriter w = res.stream()
            w.write( "s0" )
            Coroutine.delay( 200 )
            w.write( "s1" )
            Coroutine.delay( 200 )
            w.write( "s2" )
            Coroutine.delay( 200 )
            w.close()
        }
        app.onGet( "/slowstream", hSlow )

        function hPing = function( SLang.Request req, SLang.Response res )
        {
            res.text( "pong" )
        }
        app.onGet( "/ping", hPing )

        app.start( 19423 )

        # T3a chunked 往返：TE 头 + 块解码 + 终止 + 兜底（noclose 也收完）
        P2RawClient c1 = P2RawClient.connect( 19423 )
        c1.send( "GET /chunk HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n" )
        P2Resp r1 = c1.readResp()
        ServerP2Test.check( "T3a chunked decode + terminator",
            r1._ok && r1._chunked && r1._body == "part0part1part2" )

        # T3b handler 忘 close → 引擎兜底终止块（客户端完整收完）
        P2RawClient c2 = P2RawClient.connect( 19423 )
        c2.send( "GET /noclose HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n" )
        P2Resp r2 = c2.readResp()
        ServerP2Test.check( "T3b engine close fallback", r2._ok && r2._chunked && r2._body == "nc-data" )

        # T3c chunked 完成后同连接 keep-alive 继续
        c1.send( "GET /ping HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n" )
        P2Resp r3 = c1.readResp()
        ServerP2Test.check( "T3c keep-alive after chunked", r3._ok && r3._body == "pong" )
        c1.close()
        c2.close()

        # T3d SSE 线格式
        P2RawClient c4 = P2RawClient.connect( 19423 )
        c4.send( "GET /sse HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n" )
        P2Resp r4 = c4.readResp()
        ServerP2Test.check( "T3d sse wire format",
            r4._ok && r4._chunked
            && sfFind( r4._head, "Content-Type: text/event-stream" ) >= 0
            && sfFind( r4._body, "event: progress\r\ndata: 10\r\n\r\n" ) >= 0
            && sfFind( r4._body, ":ka" ) >= 0
            && sfFind( r4._body, "data: done\r\n\r\n" ) >= 0 )
        c4.close()

        # T3e 超时豁免：慢流总时长 600ms > handlerTimeoutMs 400ms 仍完整
        P2RawClient c5 = P2RawClient.connect( 19423 )
        c5.send( "GET /slowstream HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n" )
        P2Resp r5 = c5.readResp()
        ServerP2Test.check( "T3e streaming timeout exemption",
            r5._ok && r5._body == "s0s1s2" && sfFind( r5._head, "504" ) < 0 )
        c5.close()

        app.stop()
    }

    # ── T4 sendFile / file / 通配路由 / wsEvents ──

    static void t4FileWild()
    {
        Console.println( "[ServerP2Test] T4 begin (port 19424)" )
        # 160KB 大文件（ByteBuffer 构建，避免 O(n^2) 字符串拼接）
        ByteBuffer bb = ByteBuffer( 163840 )
        for Int32 i = 0, i < 16000, i = i + 1
        {
            bb.writeString( "0123456789" )
        }
        UInt8Array barr = bb.toArray()
        File.writeAllBytes( "p2_big.txt", barr )
        string expected = bb.toString()
        bb.release()

        SLang.HttpServer app = SLang.HttpServer( 19424 )
        app.reset()

        function hDl = function( SLang.Request req, SLang.Response res )
        {
            res.sendFile( "p2_big.txt" )
        }
        app.onGet( "/download", hDl )
        function hDl404 = function( SLang.Request req, SLang.Response res )
        {
            res.sendFile( "no-such-file.bin" )
        }
        app.onGet( "/dl404", hDl404 )
        function hAttach = function( SLang.Request req, SLang.Response res )
        {
            res.file( "p2_static/hello.txt", "greet.txt" )
        }
        app.onGet( "/attach", hAttach )

        # 通配路由 {path*}
        function hWild = function( SLang.Request req, SLang.Response res )
        {
            res.text( "p=" + req.pathParam( "path" ) )
        }
        app.onGet( "/files/{path*}", hWild )

        # wsEvents 事件糖（onOpen/onMessage/onClose；onClose 空实现——
        # 触发判据经 sessions()==0 轮询）
        # WS 注册经 WebSocketServer 实例（形态 A：同端口升级；2026-10-26
        # 自 SLang.Server.wsEvents 迁移）
        SLang.WebSocketServer ws = SLang.WebSocketServer()
        SLang.WsEventBuilder eb = ws.wsEvents( "/ws/evt" )
        function fOpen = function( SLang.WsSession s )
        {
            s.sendText( "opened" )
        }
        eb.onOpen( fOpen )
        function fMsg = function( SLang.WsSession s, Net.WsMessage m )
        {
            s.sendText( "echo:" + m.text() )
            m.release()
        }
        eb.onMessage( fMsg )
        function fClose = function( SLang.WsSession s )
        {
        }
        eb.onClose( fClose )

        app.start( 19424 )

        # T4a sendFile 大文件：Content-Length + 内容对照
        P2RawClient c1 = P2RawClient.connect( 19424 )
        c1.send( "GET /download HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n" )
        P2Resp r1 = c1.readResp()
        ServerP2Test.check( "T4a sendFile 160KB roundtrip",
            r1._ok && sfFind( r1._head, "Content-Length: 160000" ) >= 0
            && SystemStringLength( r1._body ) == 160000 && r1._body == expected )
        c1.close()

        # T4b sendFile 不存在 → 404
        string r2 = ServerP2Test.rawReq( 19424, "GET /dl404 HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n" )
        ServerP2Test.check( "T4b sendFile missing -> 404", sfFind( r2, "404" ) >= 0 )

        # T4c file() 附件头
        string r3 = ServerP2Test.rawReq( 19424, "GET /attach HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n" )
        ServerP2Test.check( "T4c file() content-disposition",
            sfFind( r3, "attachment; filename=\"greet.txt\"" ) >= 0 && sfFind( r3, "static-hello" ) >= 0 )

        # T4d 通配路由：多段 / 单段 / 空
        string r4 = ServerP2Test.rawReq( 19424, "GET /files/a/b/c.txt HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n" )
        string r5 = ServerP2Test.rawReq( 19424, "GET /files/only.txt HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n" )
        string r6 = ServerP2Test.rawReq( 19424, "GET /files HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n" )
        ServerP2Test.check( "T4d wildcard multi/single/empty",
            sfFind( r4, "p=a/b/c.txt" ) >= 0 && sfFind( r5, "p=only.txt" ) >= 0 && sfFind( r6, "p=" ) >= 0 )

        # T4e wsEvents：onOpen 推送（opened 消息）+ onMessage echo +
        # onClose 触发（观测零 static：close 生效判据 = 会话注销，
        # sessions()==0 轮询，T6i 同款判据）
        P2WsClient w = P2WsClient.connect( 19424, "/ws/evt" )
        bool okHandshake = sfFind( w.head, "101" ) >= 0
        string openMsg = w.readText()
        w.sendText( "hi" )
        string echoMsg = w.readText()
        w.close()
        function condClosed = function()
        {
            ret SLang.HttpServerCore.sessions( "/ws/evt" ).length == 0
        }
        bool closedOk = ServerP2Test.waitCond( condClosed, 20 )
        ServerP2Test.check( "T4e wsEvents open/msg/close",
            okHandshake && openMsg == "opened"
            && echoMsg == "echo:hi" && closedOk )

        app.stop()
    }

    # 单连接单请求（纯文本；简单断言用）
    static string rawReq( Int32 port, string reqText ) throws
    {
        P2RawClient c = P2RawClient.connect( port )
        c.send( reqText )
        P2Resp r = c.readResp()
        c.close()
        ret r._head + "\n" + r._body
    }

    # 尽力清理
    static void cleanup()
    {
        File.delete( "p2_static/hello.txt" )
        File.delete( "p2_static/page.html" )
        IO.Directory.delete( "p2_static" )
        File.delete( "p2_big.txt" )
    }

    static fun()
    {
        ServerP2Test.t1Pipeline()
        ServerP2Test.t2CorsStatic()
        ServerP2Test.t3Stream()
        ServerP2Test.t4FileWild()
        ServerP2Test.cleanup()
        Console.println( "[ServerP2Test] all done" )
    }
}

# ============================================================================
# P2Resp -- 响应解析结果（head = 头文本；body = 解码后 body；chunked 标志）
# ============================================================================
class P2Resp
{
    bool _ok = false
    bool _chunked = false
    string _head = ""
    string _body = ""

    _init_()
    {
        this._ok = false
        this._chunked = false
        this._head = ""
        this._body = ""
    }
}

# ============================================================================
# P2RawClient -- 原始 HTTP 测试客户端：行/定长读取 + chunked 解码
#（支持 keep-alive 复用：readResp 可在同连接多次调用）
# ============================================================================
class P2RawClient
{
    Net.TcpStream c = null
    string rtext = ""

    _init_()
    {
        this.c = null
        this.rtext = ""
    }

    static P2RawClient connect( Int32 port ) throws
    {
        P2RawClient rc = P2RawClient()
        rc.c = Net.Tcp.connect( "127.0.0.1", port )
        rc.rtext = ""
        ret rc
    }

    void send( string text ) throws
    {
        ByteBuffer b = ByteBuffer.fromString( text )
        this.c.write( b )
        b.release()
    }

    # 读一行（不含行尾；EOF 无行返回 null）
    string readLine() throws
    {
        Int32 pos = ServerP2Test.sfFind( this.rtext, "\n" )
        while pos < 0
        {
            ByteBuffer b = ByteBuffer( 1024 )
            Int32 n = this.c.read( b )
            if n == 0
            {
                ret null
            }
            this.rtext = this.rtext + b.readString( n )
            pos = ServerP2Test.sfFind( this.rtext, "\n" )
        }
        Int32 cut = pos
        if cut > 0 && SystemStringCharCodeAt( this.rtext, cut - 1 ) == 13
        {
            cut = cut - 1
        }
        string line = SystemStringRange( this.rtext, 0, cut )
        this.rtext = SystemStringRange( this.rtext, pos + 1, SystemStringLength( this.rtext ) )
        ret line
    }

    # 读 n 字节（文本安全：测试数据无内嵌 NUL）
    string readN( Int32 n ) throws
    {
        while SystemStringLength( this.rtext ) < n
        {
            ByteBuffer b = ByteBuffer( 8192 )
            Int32 got = this.c.read( b )
            if got == 0
            {
                break
            }
            this.rtext = this.rtext + b.readString( got )
        }
        Int32 have = SystemStringLength( this.rtext )
        Int32 take = n
        if have < take
        {
            take = have
        }
        string part = SystemStringRange( this.rtext, 0, take )
        this.rtext = SystemStringRange( this.rtext, take, have )
        ret part
    }

    # 读完整响应：头到空行 + body（Transfer-Encoding: chunked → 逐块解码；
    # Content-Length → 定长；两者皆无 → EOF 截止）
    P2Resp readResp() throws
    {
        P2Resp r = P2Resp()
        # ---- 头区 ----
        string head = ""
        bool headDone = false
        while headDone == false
        {
            string line = this.readLine()
            if line == null
            {
                ret r
            }

            if SystemStringLength( line ) == 0
            {
                headDone = true
            }
            else
            {
                head = head + line + "\n"
            }
        }
        r._head = head
        r._ok = true
        # ---- body ----
        if ServerP2Test.sfFind( head, "Transfer-Encoding: chunked" ) >= 0
        {
            r._chunked = true
            string body = ""
            bool bodyDone = false
            while bodyDone == false
            {
                string sizeLine = this.readLine()
                if sizeLine == null
                {
                    bodyDone = true
                }
                else
                {
                    Int32 size = ServerP2Test.p2Hex( sizeLine )
                    if size <= 0
                    {
                        # 0 终止块（或非法行防御）：消费 trailer 空行后收工
                        string trailer = this.readLine()
                        bodyDone = true
                    }
                    else
                    {
                        body = body + this.readN( size )
                        # 块尾 CRLF
                        this.readLine()
                    }
                }
            }
            r._body = body
        }
        else
        {
            # Content-Length 定长（无 CL 头按 0）
            Int32 need = 0
            Int32 pos = ServerP2Test.sfFind( head, "Content-Length:" )
            if pos >= 0
            {
                Int32 i = pos + 16
                Int32 hlen = SystemStringLength( head )
                while i < hlen && SystemStringCharCodeAt( head, i ) == 32
                {
                    i = i + 1
                }
                Int32 v = 0
                while i < hlen
                {
                    Int32 ch = SystemStringCharCodeAt( head, i )
                    if ch < 48 || ch > 57
                    {
                        break
                    }
                    v = v * 10 + ( ch - 48 )
                    i = i + 1
                }
                need = v
            }

            if need > 0
            {
                r._body = this.readN( need )
            }
        }
        ret r
    }

    void close()
    {
        if this.c != null
        {
            this.c.close()
        }
    }
}

# ============================================================================
# P2WsClient -- 手搓 WS 测试客户端（ServerP1Test P1WsClient 同款实现）：
# 升级握手 + 掩码文本帧发送 + 服务端文本帧读取
# ============================================================================
class P2WsClient
{
    Net.TcpStream c = null
    ByteBuffer rbuf = null
    string head = ""

    _init_()
    {
        this.c = null
        this.rbuf = null
        this.head = ""
    }

    static P2WsClient connect( Int32 port, string path ) throws
    {
        P2WsClient w = P2WsClient()
        w.c = Net.Tcp.connect( "127.0.0.1", port )
        Int64 keyId = SystemRandomFill( 16 )
        ByteBuffer kb = ByteBuffer.fromHandle( keyId )
        string key = Base64.encodeToString( kb )
        kb.release()
        string reqText = "GET " + path + " HTTP/1.1\r\nHost: 127.0.0.1\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: " + key + "\r\nSec-WebSocket-Version: 13\r\n\r\n"
        w.rbuf = ByteBuffer()
        ByteBuffer rb = ByteBuffer.fromString( reqText )
        w.c.write( rb )
        rb.release()
        string resp = ""
        while ServerP2Test.sfFind( resp, "\r\n\r\n" ) < 0
        {
            ByteBuffer b = ByteBuffer( 256 )
            Int32 n = w.c.read( b )
            if n == 0
            {
                break
            }
            w.rbuf.writeBytes( b, n )
            resp = w.rbuf.toString()
        }
        w.head = resp
        Int32 hdrEnd = ServerP2Test.sfFind( resp, "\r\n\r\n" )
        if hdrEnd >= 0
        {
            w.rbuf.skipBytes( hdrEnd + 4 )
        }
        ret w
    }

    void sendText( string text ) throws
    {
        Int32 m0 = 1
        Int32 m1 = 2
        Int32 m2 = 3
        Int32 m3 = 4
        Int32 plen = SystemStringLength( text )
        ByteBuffer frame = ByteBuffer( plen + 16 )
        frame.writeU8( SystemConvertUInt8( 0x81 ) )
        frame.writeU8( SystemConvertUInt8( 0x80 | plen ) )
        frame.writeU8( SystemConvertUInt8( m0 ) )
        frame.writeU8( SystemConvertUInt8( m1 ) )
        frame.writeU8( SystemConvertUInt8( m2 ) )
        frame.writeU8( SystemConvertUInt8( m3 ) )
        for Int32 i = 0, i < plen, i = i + 1
        {
            Int32 ch = SystemStringCharCodeAt( text, i )
            Int32 mod = i & 3
            Int32 mk = m0
            if mod == 1
            {
                mk = m1
            }
            elif mod == 2
            {
                mk = m2
            }
            elif mod == 3
            {
                mk = m3
            }
            frame.writeU8( SystemConvertUInt8( ch ^ mk ) )
        }
        this.c.write( frame )
        frame.release()
    }

    # 读一条服务端文本帧（EOF/Close/空载荷帧返回 null）
    string readText() throws
    {
        bool skip = true
        while skip
        {
            while this.rbuf.readableBytes < 2
            {
                ByteBuffer rb1 = this.rbuf
                Int32 n = this.c.read( rb1 )
                if n == 0
                {
                    ret null
                }
            }
            UInt8 b0 = this.rbuf.readU8()
            Int32 h0 = b0
            UInt8 b1 = this.rbuf.readU8()
            Int32 h1 = b1
            Int32 opcode = h0 & 0x0F
            Int32 flen = h1 & 0x7F
            if opcode == 8
            {
                ret null
            }

            if flen > 0
            {
                skip = false
                while this.rbuf.readableBytes < flen
                {
                    ByteBuffer rb2 = this.rbuf
                    Int32 n2 = this.c.read( rb2 )
                    if n2 == 0
                    {
                        ret null
                    }
                }
                ret this.rbuf.readString( flen )
            }
            # 空载荷帧（Ping/Pong）：继续读下一条
        }
        ret null
    }

    void close()
    {
        if this.c != null
        {
            this.c.close()
        }
    }
}
