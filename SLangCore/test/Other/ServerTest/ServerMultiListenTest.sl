import Std;
import Core;
import SLangServer;

# ============================================================================
# ServerMultiListenTest.sl -- 多监听器验收（v1.1：HttpServer.listen 扩展端口）
#
#   M1  双端口静态挂载（start 前登记，start 统一 bind）：
#       tag 分配 / 全局路由两端口共享 / listener 路由仅本端口可见
#       / listener 同名路由覆盖全局（本端口视图优先）/ req.localPort
#       / 405 + Allow 在监听器视图下生成
#   M2  running 中动态挂载第三端口（listen() 立即 bind，全局路由
#       对新端口立即可见）
#
# 端口：M=19521-19523（与既有组不冲突；ServerTest.sp 宿主选择器接入）。
# ============================================================================

ServerMultiListenTest
{
    static check( string name, bool cond )
    {
        if cond
        {
            Console.println( "[ServerMultiListenTest] " + name + " : OK" )
        }
        else
        {
            Console.println( "[ServerMultiListenTest] " + name + " : FAIL" )
        }
    }

    # ── M1 双端口静态挂载 ──

    static m1Scopes()
    {
        Console.println( "[ServerMultiListenTest] M1 begin (ports 19521/19522)" )
        SLang.HttpServer app = SLang.HttpServer( 19521 )
        app.reset()

        # 全局路由（app.on* 直注 = scope 0：全部端口共享）
        function hTime = function( SLang.Request req, SLang.Response res )
        {
            res.text( "time:global" )
        }
        app.onGet( "/api/time", hTime )

        # 全局同名路由（扩展端口将被 listener 同名路由覆盖——视图优先演示）
        function hWhoG = function( SLang.Request req, SLang.Response res )
        {
            res.text( "who:global" )
        }
        app.onGet( "/api/who", hWhoG )

        # 扩展监听器 19522（start 前登记入缓冲，start 统一 bind）
        SLang.ServerListener adm = app.listen( 19522 )
        ServerMultiListenTest.check( "M0 listener tag/port", adm.tag() == 2 && adm.port() == 19522 )

        # listener 路由（仅 19522 可见）
        function hPanel = function( SLang.Request req, SLang.Response res )
        {
            res.text( "panel:admin" )
        }
        adm.onGet( "/admin/panel", hPanel )

        # req.localPort（请求进入的监听端口）
        function hPort = function( SLang.Request req, SLang.Response res )
        {
            Int32 lp = req.localPort
            res.text( "port:" + lp.toString() )
        }
        adm.onGet( "/admin/port", hPort )

        # listener 同名覆盖全局（19522 的 /api/who 视图优先）
        function hWhoA = function( SLang.Request req, SLang.Response res )
        {
            res.text( "who:admin" )
        }
        adm.onGet( "/api/who", hWhoA )

        app.start()

        # M1a 全局路由主端口可达
        Net.HttpResponse r1 = Net.HttpClient.httpGet( "http://127.0.0.1:19521/api/time" )
        ServerMultiListenTest.check( "M1a global route on main port", r1.statusCode == 200 && r1.body == "time:global" )

        # M1b 全局路由扩展端口可达（scope 0 全端口共享）
        Net.HttpResponse r2 = Net.HttpClient.httpGet( "http://127.0.0.1:19522/api/time" )
        ServerMultiListenTest.check( "M1b global route on extra port", r2.statusCode == 200 && r2.body == "time:global" )

        # M1c listener 路由主端口不可见（404）
        Net.HttpResponse r3 = Net.HttpClient.httpGet( "http://127.0.0.1:19521/admin/panel" )
        ServerMultiListenTest.check( "M1c listener route hidden on main port", r3.statusCode == 404 )

        # M1d listener 路由本端口可达
        Net.HttpResponse r4 = Net.HttpClient.httpGet( "http://127.0.0.1:19522/admin/panel" )
        ServerMultiListenTest.check( "M1d listener route on own port", r4.statusCode == 200 && r4.body == "panel:admin" )

        # M1e req.localPort
        Net.HttpResponse r5 = Net.HttpClient.httpGet( "http://127.0.0.1:19522/admin/port" )
        ServerMultiListenTest.check( "M1e req.localPort", r5.statusCode == 200 && r5.body == "port:19522" )

        # M1f listener 同名路由覆盖全局（本端口视图优先；主端口仍全局）
        Net.HttpResponse r6 = Net.HttpClient.httpGet( "http://127.0.0.1:19522/api/who" )
        Net.HttpResponse r7 = Net.HttpClient.httpGet( "http://127.0.0.1:19521/api/who" )
        ServerMultiListenTest.check( "M1f listener view overrides global", r6.body == "who:admin" && r7.body == "who:global" )

        # M1g 405 + Allow（listener 视图下 pathHit 命中本端口路由）
        Net.HttpResponse r8 = Net.HttpClient.httpPost( "http://127.0.0.1:19522/admin/panel", "", "text/plain" )
        ServerMultiListenTest.check( "M1g 405 + Allow in listener view", r8.statusCode == 405 && r8.headers.getHeader( "Allow" ) == "GET" )

        app.stop()
    }

    # ── M2 running 中动态挂载 ──

    static m2Dynamic()
    {
        Console.println( "[ServerMultiListenTest] M2 begin (port 19521 + dynamic 19523)" )
        SLang.HttpServer app = SLang.HttpServer( 19521 )
        app.reset()

        function hTime = function( SLang.Request req, SLang.Response res )
        {
            res.text( "time:global" )
        }
        app.onGet( "/api/time", hTime )

        app.start()

        # M2a 运行中 listen：立即 bind
        SLang.ServerListener dyn = app.listen( 19523 )
        ServerMultiListenTest.check( "M2a dynamic listen tag", dyn.tag() == 2 && dyn.port() == 19523 )

        # M2b 新端口立即可服务（全局路由对动态监听器可见）
        Net.HttpResponse r1 = Net.HttpClient.httpGet( "http://127.0.0.1:19523/api/time" )
        ServerMultiListenTest.check( "M2b global route on dynamic port", r1.statusCode == 200 && r1.body == "time:global" )

        # M2c 动态端口专属路由即时注册即时可用
        function hPing = function( SLang.Request req, SLang.Response res )
        {
            res.text( "ping:dyn" )
        }
        dyn.onGet( "/dyn/ping", hPing )
        Net.HttpResponse r2 = Net.HttpClient.httpGet( "http://127.0.0.1:19523/dyn/ping" )
        Net.HttpResponse r3 = Net.HttpClient.httpGet( "http://127.0.0.1:19521/dyn/ping" )
        ServerMultiListenTest.check( "M2c dynamic route scoped", r2.statusCode == 200 && r2.body == "ping:dyn" && r3.statusCode == 404 )

        # M2d stop 一次关全部监听器（19521/19523 均断）
        app.stop()
        bool closed = false
        label probe
        {
            Net.TcpStream p = Net.Tcp.connect( "127.0.0.1", 19523 )
            p.close()
        }
        catch
        {
            closed = true
        }
        ServerMultiListenTest.check( "M2d stop closes all listeners", closed )
    }

    static fun()
    {
        ServerMultiListenTest.m1Scopes()
        ServerMultiListenTest.m2Dynamic()
    }
}
