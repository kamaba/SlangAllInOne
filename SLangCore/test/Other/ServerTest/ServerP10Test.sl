import Std;
import Core;
import SLangServer;

# ============================================================================
# ServerP10Test.sl -- SLangServer P10 验收（ServerTest 宿主）
# 补齐 SERVER_DESIGN.md P3 裁剪三项（setCookie / formAll / 路由级中间件）：
#
#   T1  res.setCookie 简单形态：Set-Cookie 头行出现 + 值正确；
#       同名两次调用 = 两条独立头行（Set-Cookie 多行重复语义）
#   T2  res.setCookie 属性形态：Path/Max-Age/Secure/HttpOnly/SameSite 属性
#       逐项断言 + SameSite=None 自动补 Secure
#   T3  cookie 读写往返：Response 设置 → 原始客户端带 Cookie 头回发 →
#       req.cookie 读回；hasCookie / cookieKeys；无 cookie 头空语义
#   T4  req.formAll：urlencoded 同名多值（a=1&a=2&a=3）按出现序取全；
#       form(name) 首值语义不变；无该字段空表
#   T5  路由级中间件（params 尾参形态）：全局 → 路由级1 → 路由级2 →
#       handler 执行序（req.userData 传值链）；短路（不调 nx.go()）；
#       无路由级中间件的路由不受影响
#   T6  RouteInfo.use 链式登记 + RouteGroup.onGet 尾参形态（同 T5 语义）
#
# 端口：19501-19502（P3=19431-19436、P9=19491-19492 之后顺延）。
# 编写约定同 ServerP3Test.sl（原始 HTTP 客户端助手同款实现）。
# ============================================================================

ServerP10Test
{
    static check( string name, bool cond )
    {
        if cond
        {
            Console.println( "[ServerP10Test] " + name + " : OK" )
        }
        else
        {
            Console.println( "[ServerP10Test] " + name + " : FAIL" )
        }
    }

    # 调试：失败时打印实际响应（提交前保留——P10 排障产物，遵循最小改动）
    static void dump( string tag, string text )
    {
        Console.println( "[ServerP10Test] DUMP " + tag + " >>> " + text )
    }

    # ── 通用助手（ServerP3Test 同款）──

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

    # 头行计数（Set-Cookie 多行断言用：出现次数）
    static Int32 sfCount( string text, string sub )
    {
        Int32 tlen = SystemStringLength( text )
        Int32 slen = SystemStringLength( sub )
        if slen == 0 || tlen < slen
        {
            ret 0
        }
        Int32 cnt = 0
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
                cnt = cnt + 1
            }
        }
        ret cnt
    }

    static string rawReq( Int32 port, string reqText ) throws
    {
        P10RawClient c = P10RawClient.connect( port )
        c.send( reqText )
        P10Resp r = c.readResp()
        c.close()
        ret r._head + "\n" + r._body
    }

    # 十六进制串 → Int32（chunk size 行解析；非法返回 -1）
    static Int32 p10Hex( string s )
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

    # 头区提取整数头（如 Content-Length；未找到 -1）
    static Int32 p10HeadInt( string head, string name )
    {
        Int32 pos = ServerP10Test.sfFind( head, name )
        if pos < 0
        {
            ret -1
        }

        Int32 len = SystemStringLength( head )
        Int32 v = 0
        bool any = false
        for Int32 i = pos + SystemStringLength( name ), i < len, i = i + 1
        {
            Int32 c = SystemStringCharCodeAt( head, i )
            if c < 48 || c > 57
            {
                break
            }
            v = v * 10 + ( c - 48 )
            any = true
        }

        if any == false
        {
            ret -1
        }
        ret v
    }

    # ── T1 setCookie 简单形态 + 同名多行 ──

    static void t1SetCookieSimple()
    {
        Console.println( "[ServerP10Test] T1 begin (port 19501)" )
        SLang.HttpServer app = SLang.HttpServer( 19501 )
        app.reset()

        function hCookie = function( SLang.Request req, SLang.Response res )
        {
            res.setCookie( "sid", "abc123" )
            res.setCookie( "sid", "xyz789" )
            res.setCookie( "theme", "dark" )
            res.text( "ok" )
        }
        app.onGet( "/cookie", hCookie )
        app.start( 19501 )

        string r = ServerP10Test.rawReq( 19501, "GET /cookie HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n" )
        ServerP10Test.check( "T1a Set-Cookie 头行出现 + 值正确",
            ServerP10Test.sfFind( r, "Set-Cookie: theme=dark" ) >= 0
            && ServerP10Test.sfFind( r, "Set-Cookie: sid=abc123" ) >= 0 )
        ServerP10Test.check( "T1b 同名两次 = 两条独立头行（多行重复语义）",
            ServerP10Test.sfCount( r, "Set-Cookie: sid=" ) == 2 )
        ServerP10Test.check( "T1c 头行总数 = 3（sid×2 + theme×1）",
            ServerP10Test.sfCount( r, "Set-Cookie: " ) == 3 )

        app.stop()
    }

    # ── T2 setCookie 属性形态 ──

    static void t2SetCookieAttrs()
    {
        Console.println( "[ServerP10Test] T2 begin (port 19501)" )
        SLang.HttpServer app = SLang.HttpServer( 19501 )
        app.reset()

        function hAttr = function( SLang.Request req, SLang.Response res )
        {
            # 属性形态：Path / Max-Age / Secure / HttpOnly / SameSite
            res.setCookie( "tok", "v1", "/", 3600, true, true, "Strict" )
            # SameSite=None 且 secure=false：自动补 Secure
            res.setCookie( "cs", "v2", "", 0, false, false, "None" )
            res.text( "ok" )
        }
        app.onGet( "/attr", hAttr )
        app.start( 19501 )

        string r = ServerP10Test.rawReq( 19501, "GET /attr HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n" )
        ServerP10Test.check( "T2a 属性逐项（Path/Max-Age/Secure/HttpOnly/SameSite=Strict）",
            ServerP10Test.sfFind( r, "Set-Cookie: tok=v1; Path=/; Max-Age=3600; Secure; HttpOnly; SameSite=Strict" ) >= 0 )
        ServerP10Test.check( "T2b SameSite=None 自动补 Secure",
            ServerP10Test.sfFind( r, "Set-Cookie: cs=v2; SameSite=None; Secure" ) >= 0 )

        app.stop()
    }

    # ── T3 cookie 读写往返 ──

    static void t3CookieRoundtrip()
    {
        Console.println( "[ServerP10Test] T3 begin (port 19501)" )
        SLang.HttpServer app = SLang.HttpServer( 19501 )
        app.reset()

        function hEcho = function( SLang.Request req, SLang.Response res )
        {
            string sid = req.cookie( "sid" )
            List<string> keys = req.cookieKeys()
            Int32 kn = keys.length
            string all = "keys=" + kn.toString()
            if sid != null
            {
                all = all + ";sid=" + sid
            }
            else
            {
                all = all + ";nosid"
            }

            if req.hasCookie( "theme" )
            {
                all = all + ";theme=" + req.cookie( "theme" )
            }
            else
            {
                all = all + ";notheme"
            }
            res.text( all )
        }
        app.onGet( "/echo", hEcho )
        app.start( 19501 )

        # 带 Cookie 头回发
        string r1 = ServerP10Test.rawReq( 19501, "GET /echo HTTP/1.1\r\nHost: 127.0.0.1\r\nCookie: sid=round1; theme=light\r\nConnection: close\r\n\r\n" )
        ServerP10Test.check( "T3a cookie 读回 + hasCookie + cookieKeys",
            ServerP10Test.sfFind( r1, "sid=round1" ) >= 0
            && ServerP10Test.sfFind( r1, "theme=light" ) >= 0
            && ServerP10Test.sfFind( r1, "keys=2" ) >= 0 )

        # 无 Cookie 头
        string r2 = ServerP10Test.rawReq( 19501, "GET /echo HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n" )
        ServerP10Test.check( "T3b 无 cookie 头：cookie() null 化 + 空键表 + hasCookie false",
            ServerP10Test.sfFind( r2, "keys=0" ) >= 0
            && ServerP10Test.sfFind( r2, "nosid" ) >= 0
            && ServerP10Test.sfFind( r2, "notheme" ) >= 0 )

        # 多条 Cookie 头 + 空白容忍
        string r3 = ServerP10Test.rawReq( 19501, "GET /echo HTTP/1.1\r\nHost: 127.0.0.1\r\nCookie: a=1\r\nCookie: sid= round2 \r\nConnection: close\r\n\r\n" )
        ServerP10Test.check( "T3c 多条 Cookie 头 + 值两端空白剥离",
            ServerP10Test.sfFind( r3, "sid=round2" ) >= 0
            && ServerP10Test.sfFind( r3, "keys=2" ) >= 0 )

        app.stop()
    }

    # ── T4 formAll 同名多值 ──

    static void t4FormAll()
    {
        Console.println( "[ServerP10Test] T4 begin (port 19501)" )
        SLang.HttpServer app = SLang.HttpServer( 19501 )
        app.reset()

        function hForm = function( SLang.Request req, SLang.Response res )
        {
            List<string> vals = req.formAll( "tag" )
            Int32 n = vals.length
            string outText = "n=" + n.toString()
            for Int32 i = 0, i < n, i = i + 1
            {
                outText = outText + ";" + vals[i]
            }
            # form() 首值语义（v1 不变；先拆局部——续链混方法调用 Front 坑）
            string first = req.form( "tag" )
            outText = outText + ";first=" + first
            # 无字段空表
            List<string> none = req.formAll( "nosuch" )
            Int32 noneN = none.length
            outText = outText + ";none=" + noneN.toString()
            res.text( outText )
        }
        app.onPost( "/form", hForm )
        app.start( 19501 )

        string body = "tag=a&tag=b&tag=c&other=1"
        # 字符串续链混方法调用触发 Front 解析坑（mkJwt 注记同款）——先拆局部
        Int32 bodyLen = SystemStringLength( body )
        string bodyLenText = bodyLen.toString()
        string reqText = "POST /form HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Type: application/x-www-form-urlencoded\r\nContent-Length: " + bodyLenText + "\r\nConnection: close\r\n\r\n" + body
        string r = ServerP10Test.rawReq( 19501, reqText )
        ServerP10Test.dump( "T4", r )
        ServerP10Test.check( "T4a 同名多值按出现序取全（a,b,c）",
            ServerP10Test.sfFind( r, "n=3;a;b;c" ) >= 0 )
        ServerP10Test.check( "T4b form() 覆盖语义不变（重复键末值 first=c，§6.4）",
            ServerP10Test.sfFind( r, "first=c" ) >= 0 )
        ServerP10Test.check( "T4c 无字段返回空表（none=0）",
            ServerP10Test.sfFind( r, "none=0" ) >= 0 )

        app.stop()
    }

    # ── T5 路由级中间件（params 尾参形态）──

    static void t5RouteMiddleware()
    {
        Console.println( "[ServerP10Test] T5 begin (port 19501)" )
        SLang.HttpServer app = SLang.HttpServer( 19501 )
        app.reset()

        # 全局中间件：链头打标
        function mwGlobal = function( SLang.Request req, SLang.Response res, SLang.Next nx )
        {
            req.userData = "G"
            nx.go()
        }
        app.use( mwGlobal )

        # 路由级 1：追加（userData 是 object 槽——经 string 局部转回，
        # object 直 + 触发 Front 算术路径报错）
        function mwRoute1 = function( SLang.Request req, SLang.Response res, SLang.Next nx )
        {
            string cur = req.userData as string
            req.userData = cur + ">R1"
            nx.go()
        }
        # 路由级 2：再追加
        function mwRoute2 = function( SLang.Request req, SLang.Response res, SLang.Next nx )
        {
            string cur2 = req.userData as string
            req.userData = cur2 + ">R2"
            nx.go()
        }

        function hChain = function( SLang.Request req, SLang.Response res )
        {
            string chain = req.userData as string
            res.text( "chain=" + chain )
        }
        # params 尾参形态：fn, mw1, mw2
        app.onGet( "/chain", hChain, mwRoute1, mwRoute2 )

        # 短路路由：路由级中间件不调 nx.go() → handler 不执行
        function mwBlock = function( SLang.Request req, SLang.Response res, SLang.Next nx )
        {
            res.status( 403 ).text( "blocked" )
        }
        function hSecret = function( SLang.Request req, SLang.Response res )
        {
            res.text( "secret" )
        }
        app.onGet( "/secret", hSecret, mwBlock )

        # 无路由级中间件的路由：全局照常、handler 直达
        function hPlain = function( SLang.Request req, SLang.Response res )
        {
            string plain = req.userData as string
            res.text( "plain=" + plain )
        }
        app.onGet( "/plain", hPlain )

        app.start( 19501 )

        string r1 = ServerP10Test.rawReq( 19501, "GET /chain HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n" )
        ServerP10Test.dump( "T5-chain", r1 )
        ServerP10Test.check( "T5a 执行序：全局 → 路由级1 → 路由级2 → handler",
            ServerP10Test.sfFind( r1, "chain=G>R1>R2" ) >= 0 )

        string r2 = ServerP10Test.rawReq( 19501, "GET /secret HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n" )
        ServerP10Test.dump( "T5-secret", r2 )
        ServerP10Test.check( "T5b 路由级中间件短路（403，handler 不执行）",
            ServerP10Test.sfFind( r2, "403" ) >= 0
            && ServerP10Test.sfFind( r2, "blocked" ) >= 0
            && ServerP10Test.sfFind( r2, "secret" ) < 0 )

        string r3 = ServerP10Test.rawReq( 19501, "GET /plain HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n" )
        ServerP10Test.check( "T5c 无路由级中间件路由不受影响（全局仍执行）",
            ServerP10Test.sfFind( r3, "plain=G" ) >= 0 )

        app.stop()
    }

    # ── T6 RouteInfo.use 链式 + RouteGroup 尾参形态 ──

    static void t6ChainAndGroup()
    {
        Console.println( "[ServerP10Test] T6 begin (port 19502)" )
        SLang.HttpServer app = SLang.HttpServer( 19502 )
        app.reset()

        # RouteInfo.use 链式登记
        function mwA = function( SLang.Request req, SLang.Response res, SLang.Next nx )
        {
            req.userData = "A"
            nx.go()
        }
        function mwB = function( SLang.Request req, SLang.Response res, SLang.Next nx )
        {
            string curB = req.userData as string
            req.userData = curB + "B"
            nx.go()
        }
        function hUse = function( SLang.Request req, SLang.Response res )
        {
            string useChain = req.userData as string
            res.text( "use=" + useChain )
        }
        SLang.RouteInfo r1 = app.onGet( "/usechain", hUse )
        r1.use( mwA ).use( mwB )

        # RouteGroup 尾参形态
        function mwGroup = function( SLang.Request req, SLang.Response res, SLang.Next nx )
        {
            req.userData = "GRP"
            nx.go()
        }
        function hGroup = function( SLang.Request req, SLang.Response res )
        {
            string grp = req.userData as string
            res.text( "group=" + grp )
        }
        SLang.RouteGroup g = app.group( "/api" )
        g.onGet( "/items", hGroup, mwGroup )

        app.start( 19502 )

        string r1s = ServerP10Test.rawReq( 19502, "GET /usechain HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n" )
        ServerP10Test.check( "T6a RouteInfo.use 链式登记（A→B→handler）",
            ServerP10Test.sfFind( r1s, "use=AB" ) >= 0 )

        string r2 = ServerP10Test.rawReq( 19502, "GET /api/items HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n" )
        ServerP10Test.dump( "T6-group", r2 )
        ServerP10Test.check( "T6b RouteGroup.onGet 尾参形态（前缀拼接 + mw 执行）",
            ServerP10Test.sfFind( r2, "group=GRP" ) >= 0 )

        app.stop()
    }

    static fun()
    {
        label t1
        {
            ServerP10Test.t1SetCookieSimple()
        }
        catch
        {
            Console.println( "[ServerP10Test] T1 异常" )
        }
        label t2
        {
            ServerP10Test.t2SetCookieAttrs()
        }
        catch
        {
            Console.println( "[ServerP10Test] T2 异常" )
        }
        label t3
        {
            ServerP10Test.t3CookieRoundtrip()
        }
        catch
        {
            Console.println( "[ServerP10Test] T3 异常" )
        }
        label t4
        {
            ServerP10Test.t4FormAll()
        }
        catch
        {
            Console.println( "[ServerP10Test] T4 异常" )
        }
        label t5
        {
            ServerP10Test.t5RouteMiddleware()
        }
        catch
        {
            Console.println( "[ServerP10Test] T5 异常" )
        }
        label t6
        {
            ServerP10Test.t6ChainAndGroup()
        }
        catch
        {
            Console.println( "[ServerP10Test] T6 异常" )
        }
        Console.println( "[ServerP10Test] all done" )
    }
}

# ============================================================================
# P10Resp -- 响应解析结果（P3Resp 同款）
# ============================================================================
class P10Resp
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
# P10RawClient -- 原始 HTTP 测试客户端（P3RawClient 同款）
# ============================================================================
class P10RawClient
{
    Net.TcpStream c = null
    string rtext = ""

    _init_()
    {
        this.c = null
        this.rtext = ""
    }

    static P10RawClient connect( Int32 port ) throws
    {
        P10RawClient rc = P10RawClient()
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
        Int32 pos = ServerP10Test.sfFind( this.rtext, "\n" )
        while pos < 0
        {
            ByteBuffer b = ByteBuffer( 1024 )
            Int32 n = this.c.read( b )
            if n == 0
            {
                ret null
            }
            this.rtext = this.rtext + b.readString( n )
            pos = ServerP10Test.sfFind( this.rtext, "\n" )
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

    # 读完整响应（Content-Length 定长 / EOF 截止）
    P10Resp readResp() throws
    {
        P10Resp r = P10Resp()
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
        if ServerP10Test.sfFind( head, "Transfer-Encoding: chunked" ) >= 0
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
                    Int32 sz = ServerP10Test.p10Hex( sizeLine )
                    if sz == 0
                    {
                        this.readLine()
                        bodyDone = true
                    }
                    else
                    {
                        body = body + this.readN( sz )
                        this.readLine()
                    }
                }
            }
            r._body = body
            ret r
        }
        Int32 cl = ServerP10Test.p10HeadInt( head, "Content-Length: " )
        if cl >= 0
        {
            r._body = this.readN( cl )
            ret r
        }
        # 无长度 → EOF 截止
        string all = ""
        while true
        {
            string part = this.readN( 8192 )
            if SystemStringLength( part ) == 0
            {
                break
            }
            all = all + part
        }
        r._body = all
        ret r
    }

    void close()
    {
        if this.c != null
        {
            label cl
            {
                this.c.close()
            }
            catch { }
            this.c = null
        }
    }
}
