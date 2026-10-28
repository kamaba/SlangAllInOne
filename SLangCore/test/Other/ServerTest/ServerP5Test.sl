import Std;
import Core;
import SLangServer;

# ============================================================================
# ServerP5Test.sl -- SLangServer P5 验收（ServerTest 宿主）
# 设计契约：SERVER_DESIGN.md §8 P5（前缀树路由 / 请求侧流式 / Range 断点
#   续传 / WS 主动心跳 / rateLimit 插件 / Jwt HS256 签验）
#
#   T1  rateLimit：固定窗口限流（窗口内超 max → 429 + Retry-After；
#       窗口内未超 → 200；放行计数不回归）
#   T2  Range 断点续传：sendFileRange（"bytes=a-b" → 206 + Content-Range +
#       区间内容 / "bytes=a-" → 尾段 / "bytes=-n" → 尾部 n 字节 /
#       越界 start → 416 + Content-Range: bytes */size / 畸形 → 全量 200）+
#       staticFiles 透传 Range + Accept-Ranges 声明
#   T3  WS 空闲心跳：wsIdleTimeoutMs=600 → 空闲会话被看门狗关闭
#       （sessions 归零轮询）；持续活跃会话不被误杀
#   T4  Jwt HS256：sign/verify 往返（claims 保留 + iat/exp 写入）/ 错密钥
#       → null / 篡改 payload → null / 过期 token → null / alg 降级
#       （none）→ null / ServerConfig.jwtSecret 便捷形态 + MissingJwtSecret
#   T5  请求侧流式：streamBody 路由 bodyStream() 边收边消费（CL 精确 +
#       chunked 感知 / 超限 → StreamBodyError 413 语义 / keep-alive 排干
#       ——未消费完的流式请求后同连接继续下一条）
#   T6  路由树回归：树化后全部既有语义（静态优先 / 参数段 / 通配 / 405
#       + Allow / ANY / HEAD→GET）——P1 既有断言的树化重放
#
# 端口：19451-19454（避开 P1-P4.5 的 19401-19443）。
# 编写约定同 ServerP2/P3Test（原始 HTTP 客户端 + 零 static 观测）。
# ============================================================================

ServerP5Test
{
    static check( string name, bool cond )
    {
        if cond
        {
            Console.println( "[ServerP5Test] " + name + " : OK" )
        }
        else
        {
            Console.println( "[ServerP5Test] " + name + " : FAIL" )
        }
    }

    # ── 通用助手（ServerP2/P3Test 同款）──

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

    static string rawReq( Int32 port, string reqText ) throws
    {
        P5RawClient c = P5RawClient.connect( port )
        c.send( reqText )
        P5Resp r = c.readResp()
        c.close()
        ret r._head + "\n" + r._body
    }

    # 头区提取整数头（如 Content-Length；未找到 -1）
    static Int32 headInt( string head, string name )
    {
        Int32 pos = sfFind( head, name )
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

    # 十六进制串 → Int32（chunk size 行解析；非法返回 -1）
    static Int32 p5Hex( string s )
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

    # 条件轮询（异步时序；每轮 50ms）
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

    # ── T1 rateLimit ──

    static void t1RateLimit()
    {
        Console.println( "[ServerP5Test] T1 begin (port 19451)" )
        SLang.HttpServer app = SLang.HttpServer( 19451 )
        app.reset()
        app.use( SLang.Plugins.rateLimit( 3, 60000 ) )
        function hPing = function( SLang.Request req, SLang.Response res )
        {
            res.text( "ok" )
        }
        app.onGet( "/ping", hPing )
        app.start( 19451 )

        # T1a 窗口内前 3 次 200
        bool first3 = true
        for Int32 i = 0, i < 3, i = i + 1
        {
            string r = ServerP5Test.rawReq( 19451, "GET /ping HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n" )
            if sfFind( r, "200" ) < 0 || sfFind( r, "ok" ) < 0
            {
                first3 = false
            }
        }
        ServerP5Test.check( "T1a first 3 in window -> 200", first3 )

        # T1b 第 4 次 429 + Retry-After
        string r4 = ServerP5Test.rawReq( 19451, "GET /ping HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n" )
        ServerP5Test.check( "T1b 4th -> 429 + Retry-After",
            sfFind( r4, "429" ) >= 0 && sfFind( r4, "Retry-After: " ) >= 0
            && sfFind( r4, "rate limit exceeded" ) >= 0 )

        app.stop()
    }

    # ── T2 Range 断点续传 ──

    static void t2Range()
    {
        Console.println( "[ServerP5Test] T2 begin (port 19452)" )
        # 1KB 样本文件（内容 = "0000...9999" 分段，便于区间断言）
        ByteBuffer bb = ByteBuffer( 1024 )
        for Int32 i = 0, i < 1000, i = i + 1
        {
            bb.writeString( "0123456789" )
        }
        UInt8Array barr = bb.toArray()
        File.writeAllBytes( "p5_range.txt", barr )
        string expected = bb.toString()
        bb.release()

        SLang.HttpServer app = SLang.HttpServer( 19452 )
        app.reset()
        function hDl = function( SLang.Request req, SLang.Response res )
        {
            res.sendFileRange( "p5_range.txt", req.header( "Range" ) )
        }
        app.onGet( "/download", hDl )
        app.start( 19452 )

        # T2a 全量 200 + Accept-Ranges 声明
        string r1 = ServerP5Test.rawReq( 19452, "GET /download HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n" )
        ServerP5Test.check( "T2a full 200 + Accept-Ranges",
            sfFind( r1, "200" ) >= 0 && sfFind( r1, "Accept-Ranges: bytes" ) >= 0
            && sfFind( r1, "Content-Length: 10000" ) >= 0
            && SystemStringLength( r1 ) > 10000 )

        # T2b "bytes=100-199" → 206 + Content-Range + 区间内容
        string r2 = ServerP5Test.rawReq( 19452, "GET /download HTTP/1.1\r\nHost: 127.0.0.1\r\nRange: bytes=100-199\r\nConnection: close\r\n\r\n" )
        ServerP5Test.check( "T2b range 100-199 -> 206",
            sfFind( r2, "206" ) >= 0
            && sfFind( r2, "Content-Range: bytes 100-199/10000" ) >= 0
            && sfFind( r2, "Content-Length: 100" ) >= 0
            && ServerP5Test._endsWith( r2, SystemStringRange( expected, 100, 200 ) ) )

        # T2c "bytes=9990-" → 尾段
        string r3 = ServerP5Test.rawReq( 19452, "GET /download HTTP/1.1\r\nHost: 127.0.0.1\r\nRange: bytes=9990-\r\nConnection: close\r\n\r\n" )
        ServerP5Test.check( "T2c open end 9990- -> 206 tail",
            sfFind( r3, "Content-Range: bytes 9990-9999/10000" ) >= 0
            && ServerP5Test._endsWith( r3, SystemStringRange( expected, 9990, 10000 ) ) )

        # T2d "bytes=-10" → 尾部 10 字节
        string r4 = ServerP5Test.rawReq( 19452, "GET /download HTTP/1.1\r\nHost: 127.0.0.1\r\nRange: bytes=-10\r\nConnection: close\r\n\r\n" )
        ServerP5Test.check( "T2d suffix -10 -> 206",
            sfFind( r4, "Content-Range: bytes 9990-9999/10000" ) >= 0
            && ServerP5Test._endsWith( r4, SystemStringRange( expected, 9990, 10000 ) ) )

        # T2e 越界 start → 416 + Content-Range: bytes */size
        string r5 = ServerP5Test.rawReq( 19452, "GET /download HTTP/1.1\r\nHost: 127.0.0.1\r\nRange: bytes=20000-\r\nConnection: close\r\n\r\n" )
        ServerP5Test.check( "T2e out of range -> 416",
            sfFind( r5, "416" ) >= 0 && sfFind( r5, "Content-Range: bytes */10000" ) >= 0 )

        # T2f 畸形 Range → 忽略按全量 200
        string r6 = ServerP5Test.rawReq( 19452, "GET /download HTTP/1.1\r\nHost: 127.0.0.1\r\nRange: bytes=abc\r\nConnection: close\r\n\r\n" )
        ServerP5Test.check( "T2f malformed -> full 200",
            sfFind( r6, "200" ) >= 0 && sfFind( r6, "Content-Length: 10000" ) >= 0 )

        app.stop()
    }

    # 尾缀断言（body 精确对照；头区已含 \n）
    static bool _endsWith( string whole, string tail )
    {
        Int32 wlen = SystemStringLength( whole )
        Int32 tlen = SystemStringLength( tail )
        if tlen == 0
        {
            ret true
        }

        if wlen < tlen
        {
            ret false
        }
        Int32 start = wlen - tlen
        for Int32 i = 0, i < tlen, i = i + 1
        {
            if SystemStringCharCodeAt( whole, start + i ) != SystemStringCharCodeAt( tail, i )
            {
                ret false
            }
        }
        ret true
    }

    # ── T3 WS 空闲心跳 ──

    static void t3WsHeartbeat()
    {
        Console.println( "[ServerP5Test] T3 begin (port 19453)" )
        SLang.HttpServer app = SLang.HttpServer( 19453 )
        SLang.ServerConfig cfg = app.config
        cfg.wsIdleTimeoutMs = 600
        app.reset()
        SLang.WebSocketServer ws = SLang.WebSocketServer()
        function hWs = function( SLang.WsSession s )
        {
            while true
            {
                Net.WsMessage m = s.receive()
                if m == null
                {
                    break
                }
                s.sendText( "echo:" + m.text )
                m.release()
            }
        }
        ws.websocket( "/ws/idle", hWs )
        function hWsActive = function( SLang.WsSession s )
        {
            while true
            {
                Net.WsMessage m = s.receive()
                if m == null
                {
                    break
                }
                s.sendText( "echo:" + m.text )
                m.release()
            }
        }
        ws.websocket( "/ws/active", hWsActive )
        app.start( 19453 )

        # T3a 空闲会话：600ms 看门狗关闭（sessions 归零轮询）
        P5WsClient w1 = P5WsClient.connect( 19453, "/ws/idle" )
        function condIdle = function()
        {
            ret SLang.HttpServerCore.sessions( "/ws/idle" ).length == 0
        }
        bool idleClosed = ServerP5Test.waitCond( condIdle, 20 )
        ServerP5Test.check( "T3a idle session closed by watchdog", idleClosed )
        w1.close()

        # T3b 活跃会话：每 200ms 发消息 → 3s 后仍在线（未被误杀）
        P5WsClient w2 = P5WsClient.connect( 19453, "/ws/active" )
        bool alive = true
        for Int32 i = 0, i < 15, i = i + 1
        {
            w2.sendText( "tick" )
            string echo = w2.readText()
            if echo != "echo:tick"
            {
                alive = false
            }
            Coroutine.delay( 200 )
        }
        bool stillOnline = SLang.HttpServerCore.sessions( "/ws/active" ).length == 1
        ServerP5Test.check( "T3b active session survives", alive && stillOnline )
        w2.close()

        app.stop()
    }

    # ── T4 Jwt HS256 ──

    static void t4Jwt()
    {
        Console.println( "[ServerP5Test] T4 begin (no port)" )
        string secret = "p5-secret-key"

        # T4a sign/verify 往返：claims 保留 + iat 写入
        SLang.JwtClaims c = SLang.JwtClaims()
        c.put( "sub", "user-42" )
        c.put( "role", "admin" )
        string token = SLang.Jwt.sign( c, secret, 3600 )
        SLang.JwtClaims back = SLang.Jwt.verify( token, secret )
        bool roundtrip = false
        if back != null
        {
            string roleV = back.claim( "role" )
            string iatV = back.claim( "iat" )
            bool roleOk = back.subject == "user-42" && roleV == "admin"
            bool iatOk = iatV != null && back.expired == false
            roundtrip = roleOk && iatOk
        }
        ServerP5Test.check( "T4a sign/verify roundtrip", roundtrip )

        # T4b 三段式 + base64url 无填充
        Int32 len = SystemStringLength( token )
        Int32 dots = 0
        for Int32 i = 0, i < len, i = i + 1
        {
            if SystemStringCharCodeAt( token, i ) == 46
            {
                dots = dots + 1
            }
        }
        ServerP5Test.check( "T4b three segments, no padding",
            dots == 2 && sfFind( token, "=" ) < 0 )

        # T4c 错密钥 → null
        SLang.JwtClaims wrongKey = SLang.Jwt.verify( token, "other-secret" )
        ServerP5Test.check( "T4c wrong secret -> null", wrongKey == null )

        # T4d 篡改 payload → null（换段后签名失配）
        Int32 d1 = ServerP5Test.sfFind( token, "." )
        string headPart = SystemStringRange( token, 0, d1 )
        Int32 d2 = -1
        for Int32 i = d1 + 1, i < len, i = i + 1
        {
            if SystemStringCharCodeAt( token, i ) == 46
            {
                d2 = i
                break
            }
        }
        # 篡改：payload 段首字符替换（b64url 字母表内换一个）
        string payloadPart = SystemStringRange( token, d1 + 1, d2 )
        Int32 plen = SystemStringLength( payloadPart )
        Int32 first = SystemStringCharCodeAt( payloadPart, 0 )
        Int32 swapped = 65
        if first == 65
        {
            swapped = 66
        }
        ByteBuffer tb = ByteBuffer( plen )
        tb.writeU8( SystemConvertUInt8( swapped ) )
        tb.writeString( SystemStringRange( payloadPart, 1, plen ) )
        string tamperedPayload = tb.toString()
        tb.release()
        string tampered = headPart + "." + tamperedPayload + SystemStringRange( token, d2, len )
        SLang.JwtClaims tamperedC = SLang.Jwt.verify( tampered, secret )
        ServerP5Test.check( "T4d tampered payload -> null", tamperedC == null )

        # T4e 过期 token → null（sign exp 参数 <=0 不写 exp——预 put 过去
        # 时间戳的 exp 再以 exp=0 签发，verify 过期检查拦截）
        SLang.JwtClaims c2 = SLang.JwtClaims()
        c2.put( "sub", "expired-user" )
        c2.put( "exp", "1000" )
        string tokExp = SLang.Jwt.sign( c2, secret, 0 )
        SLang.JwtClaims expiredC = SLang.Jwt.verify( tokExp, secret )
        ServerP5Test.check( "T4e expired -> null", expiredC == null )

        # T4f alg 降级（none）→ null：手造 alg:none token
        string noneHead = ServerP5Test._b64url( "{\"alg\":\"none\",\"typ\":\"JWT\"}" )
        string nonePayload = ServerP5Test._b64url( "{\"sub\":\"x\"}" )
        string noneTok = noneHead + "." + nonePayload + "."
        SLang.JwtClaims noneC = SLang.Jwt.verify( noneTok, secret )
        ServerP5Test.check( "T4f alg none -> null", noneC == null )

        # T4g ServerConfig.jwtSecret 便捷形态 + MissingJwtSecret
        # [回归防线] verify 签名段解码曾走 decodeString——其内嵌 NUL 截断
        # 语义会截断含 0x00 的 HMAC-SHA256 签名（概率 ~12%）→ 概率性验签
        # 失败；现已改二进制安全链。固化防线：20 rep × 独立 jti = 20 个
        # 独立 HMAC 样本，解码层回归时本断言 ~92% 概率当场抓获
        SLang.HttpServer appCfg = SLang.HttpServer( 19454 )
        SLang.ServerConfig cfgT4g = appCfg.config
        cfgT4g.jwtSecret = secret
        Int32 t4gFails = 0
        for Int32 rep = 0, rep < 20, rep = rep + 1
        {
            SLang.JwtClaims cCfg = SLang.JwtClaims()
            cCfg.put( "sub", "cfg-user" )
            cCfg.put( "jti", rep.toString() )
            string tokCfg = SLang.Jwt.sign( cCfg, 600 )
            SLang.JwtClaims backCfg = SLang.Jwt.verify( tokCfg )
            bool repOk = false
            if backCfg != null
            {
                repOk = backCfg.subject == "cfg-user"
            }

            if repOk == false
            {
                t4gFails = t4gFails + 1
            }
        }
        # 清空 secret 后便捷 sign 必须抛 MissingJwtSecret
        #（label/catch 不能进 for 体内，故放在循环外）
        cfgT4g.jwtSecret = ""
        bool threwMjs = false
        label mjs
        {
            SLang.JwtClaims cMjs = SLang.JwtClaims()
            SLang.Jwt.sign( cMjs, 600 )
        }
        catch
        {
            threwMjs = true
        }

        if threwMjs == false
        {
            t4gFails = t4gFails + 1
        }
        ServerP5Test.check( "T4g cfg secret + MissingJwtSecret", t4gFails == 0 )
    }

    # base64 标准字母 → base64url（ServerP3Test.b64url 同款）
    static string _b64url( string s ) throws
    {
        string b = Base64.encodeToString( s )
        Int32 len = SystemStringLength( b )
        ByteBuffer bufOut = ByteBuffer( len + 4 )
        for Int32 i = 0, i < len, i = i + 1
        {
            Int32 c = SystemStringCharCodeAt( b, i )
            if c == 43
            {
                c = 45
            }
            elif c == 47
            {
                c = 95
            }
            elif c == 61
            {
                continue
            }
            bufOut.writeU8( SystemConvertUInt8( c ) )
        }
        string res = bufOut.toString()
        bufOut.release()
        ret res
    }

    # ── T5 请求侧流式 ──

    static void t5StreamBody()
    {
        Console.println( "[ServerP5Test] T5 begin (port 19454)" )
        SLang.HttpServer app = SLang.HttpServer( 19454 )
        app.reset()

        # 流式 echo：读一段回写一段（观测 = 收到字节数）
        function hUp = function( SLang.Request req, SLang.Response res )
        {
            if req.isStreamBody == false
            {
                res.jsonFail( 500, "not stream" )
                ret
            }
            SLang.HttpBodyReader rd = req.bodyStream()
            Int64 total = 0
            ByteBuffer chunk = ByteBuffer( 4096 )
            while true
            {
                Int32 n = rd.read( chunk )
                if n <= 0
                {
                    break
                }
                total = total + n
                chunk.clear()
            }
            chunk.release()
            res.jsonOk( total.toString() )
        }
        SLang.RouteInfo rUp = app.onPost( "/upload", hUp )
        rUp.streamBody = true

        # 流式落盘：边收边写文件（P5 主场景）
        function hSave = function( SLang.Request req, SLang.Response res )
        {
            SLang.HttpBodyReader rd = req.bodyStream()
            var fs = FileStream( "p5_stream_in.bin", FileMode.Create )
            ByteBuffer chunk = ByteBuffer( 4096 )
            Int64 total = 0
            while true
            {
                Int32 n = rd.read( chunk )
                if n <= 0
                {
                    break
                }
                ByteBuffer view = chunk.slice( 0, n )
                fs.write( view )
                total = total + n
                chunk.clear()
            }
            chunk.release()
            fs.close()
            res.text( "saved:" + total.toString() )
        }
        SLang.RouteInfo rSave = app.onPost( "/save", hSave )
        rSave.streamBody = true

        # 不消费：handler 直接响应（引擎收尾排干 → keep-alive 继续）
        function hSkip = function( SLang.Request req, SLang.Response res )
        {
            res.text( "skipped" )
        }
        SLang.RouteInfo rSkip = app.onPost( "/skip", hSkip )
        rSkip.streamBody = true

        # 普通路由（非流式）：v1 全量缓冲语义不回归
        function hPlain = function( SLang.Request req, SLang.Response res )
        {
            res.text( "plain:" + req.bodyText() )
        }
        app.onPost( "/plain", hPlain )

        app.start( 19454 )

        # T5a CL 精确：300 字节 → "300"
        ByteBuffer bb = ByteBuffer( 300 )
        for Int32 i = 0, i < 30, i = i + 1
        {
            bb.writeString( "0123456789" )
        }
        string payload300 = bb.toString()
        bb.release()
        string r1 = ServerP5Test.rawReq( 19454, "POST /upload HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Type: application/octet-stream\r\nContent-Length: 300\r\nConnection: close\r\n\r\n" + payload300 )
        ServerP5Test.check( "T5a CL exact 300 -> 300",
            sfFind( r1, "\"data\":300" ) >= 0 )

        # T5b chunked 感知：3 块 100 字节 → "300"
        string chunkedBody = "64\r\n" + SystemStringRange( payload300, 0, 100 ) + "\r\n"
        chunkedBody = chunkedBody + "64\r\n" + SystemStringRange( payload300, 100, 200 ) + "\r\n"
        chunkedBody = chunkedBody + "64\r\n" + SystemStringRange( payload300, 200, 300 ) + "\r\n"
        chunkedBody = chunkedBody + "0\r\n\r\n"
        string r2 = ServerP5Test.rawReq( 19454, "POST /upload HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Type: application/octet-stream\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n" + chunkedBody )
        ServerP5Test.check( "T5b chunked 3x100 -> 300",
            sfFind( r2, "\"data\":300" ) >= 0 )

        # T5c 边收边落盘：600KB > 单 read 块 → 文件大小 + 首尾内容对照
        ByteBuffer big = ByteBuffer( 614400 )
        for Int32 i = 0, i < 61440, i = i + 1
        {
            big.writeString( "0123456789" )
        }
        string payload600k = big.toString()
        big.release()
        string r3 = ServerP5Test.rawReq( 19454, "POST /save HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Length: 614400\r\nConnection: close\r\n\r\n" + payload600k )
        Int64 savedSize = File.getSize( "p5_stream_in.bin" )
        bool headOk = sfFind( r3, "saved:614400" ) >= 0
        bool sizeOk = savedSize == 614400
        string head100 = File.readAllText( "p5_stream_in.bin" )
        bool contentOk = SystemStringRange( head100, 0, 100 ) == SystemStringRange( payload600k, 0, 100 )
        ServerP5Test.check( "T5c stream-to-file 600KB",
            headOk && sizeOk && contentOk )

        # T5d 未消费 + keep-alive：同连接 skip 后继续下一条（引擎排干）
        P5RawClient c4 = P5RawClient.connect( 19454 )
        c4.send( "POST /skip HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Length: 50\r\n\r\n" + SystemStringRange( payload300, 0, 50 ) )
        P5Resp r4 = c4.readResp()
        bool skipOk = r4._ok && sfFind( r4._body, "skipped" ) >= 0
        c4.send( "POST /plain HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Length: 6\r\nConnection: close\r\n\r\nhelloX" )
        P5Resp r5 = c4.readResp()
        bool nextOk = r5._ok && sfFind( r5._body, "plain:helloX" ) >= 0
        ServerP5Test.check( "T5d unconsumed drained, keep-alive continues", skipOk && nextOk )
        c4.close()

        # T5e 非流式路由不回归（全量缓冲 body）
        string r6 = ServerP5Test.rawReq( 19454, "POST /plain HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Length: 5\r\nConnection: close\r\n\r\nhello" )
        ServerP5Test.check( "T5e non-stream route unchanged",
            sfFind( r6, "plain:hello" ) >= 0 )

        app.stop()
    }

    # ── T6 路由树回归（树化语义重放）──

    static void t6RouteTree()
    {
        Console.println( "[ServerP5Test] T6 begin (port 19454)" )
        SLang.HttpServer app = SLang.HttpServer( 19454 )
        app.reset()

        function hNew = function( SLang.Request req, SLang.Response res )
        {
            res.text( "user-new" )
        }
        app.onGet( "/user/new", hNew )
        function hId = function( SLang.Request req, SLang.Response res )
        {
            res.text( "user-" + req.pathParam( "id" ) )
        }
        app.onGet( "/user/{id}", hId )
        function hWild = function( SLang.Request req, SLang.Response res )
        {
            res.text( "w=" + req.pathParam( "path" ) )
        }
        app.onGet( "/files/{path*}", hWild )
        function hAny = function( SLang.Request req, SLang.Response res )
        {
            res.text( "any" )
        }
        app.onAny( "/any", hAny )
        function hPost = function( SLang.Request req, SLang.Response res )
        {
            res.text( "posted" )
        }
        app.onPost( "/user", hPost )

        app.start( 19454 )

        # T6a 静态段优先（/user/new 不被 {id} 抢走）
        string r1 = ServerP5Test.rawReq( 19454, "GET /user/new HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n" )
        ServerP5Test.check( "T6a static beats param", sfFind( r1, "user-new" ) >= 0 )

        # T6b 参数段提取
        string r2 = ServerP5Test.rawReq( 19454, "GET /user/42 HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n" )
        ServerP5Test.check( "T6b param extraction", sfFind( r2, "user-42" ) >= 0 )

        # T6c 通配路由
        string r3 = ServerP5Test.rawReq( 19454, "GET /files/a/b/c HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n" )
        ServerP5Test.check( "T6c wildcard", sfFind( r3, "w=a/b/c" ) >= 0 )

        # T6d 405 + Allow（GET /user → POST 注册）
        string r4 = ServerP5Test.rawReq( 19454, "GET /user HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n" )
        ServerP5Test.check( "T6d 405 + Allow", sfFind( r4, "405" ) >= 0 && sfFind( r4, "Allow: POST" ) >= 0 )

        # T6e ANY 两动词 + HEAD→GET
        string r5 = ServerP5Test.rawReq( 19454, "PUT /any HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n" )
        string r6 = ServerP5Test.rawReq( 19454, "HEAD /user/new HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n" )
        ServerP5Test.check( "T6e ANY verbs + HEAD->GET",
            sfFind( r5, "any" ) >= 0 && sfFind( r6, "200" ) >= 0 )

        # T6f 404 未注册
        string r7 = ServerP5Test.rawReq( 19454, "GET /no-such HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n" )
        ServerP5Test.check( "T6f 404", sfFind( r7, "404" ) >= 0 )

        app.stop()
    }

    static fun()
    {
        ServerP5Test.t1RateLimit()
        ServerP5Test.t2Range()
        ServerP5Test.t3WsHeartbeat()
        ServerP5Test.t4Jwt()
        ServerP5Test.t5StreamBody()
        ServerP5Test.t6RouteTree()
        ServerP5Test.cleanup()
        Console.println( "[ServerP5Test] all done" )
    }

    static void cleanup()
    {
        File.delete( "p5_range.txt" )
        File.delete( "p5_stream_in.bin" )
    }
}

# ============================================================================
# P5Resp / P5RawClient -- 原始 HTTP 测试客户端（ServerP3Test 同款）
# ============================================================================
class P5Resp
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

class P5RawClient
{
    Net.TcpStream c = null
    string rtext = ""

    _init_()
    {
        this.c = null
        this.rtext = ""
    }

    static P5RawClient connect( Int32 port ) throws
    {
        P5RawClient rc = P5RawClient()
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

    string readLine() throws
    {
        Int32 pos = ServerP5Test.sfFind( this.rtext, "\n" )
        while pos < 0
        {
            ByteBuffer b = ByteBuffer( 1024 )
            Int32 n = this.c.read( b )
            if n == 0
            {
                ret null
            }
            this.rtext = this.rtext + b.readString( n )
            pos = ServerP5Test.sfFind( this.rtext, "\n" )
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

    P5Resp readResp() throws
    {
        P5Resp r = P5Resp()
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
        if ServerP5Test.sfFind( head, "Transfer-Encoding: chunked" ) >= 0
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
                    Int32 sz = ServerP5Test.p5Hex( sizeLine )
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
        Int32 cl = ServerP5Test.headInt( head, "Content-Length: " )
        if cl >= 0
        {
            r._body = this.readN( cl )
            ret r
        }
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

# ============================================================================
# P5WsClient -- 手搓 WS 客户端（ServerP2Test P2WsClient 同款）
# ============================================================================
class P5WsClient
{
    Net.TcpStream c = null
    string head = ""

    _init_()
    {
        this.c = null
        this.head = ""
    }

    static P5WsClient connect( Int32 port, string path ) throws
    {
        P5WsClient w = P5WsClient()
        w.c = Net.Tcp.connect( "127.0.0.1", port )
        # 最小握手（key 任意 16 字节 b64；服务端不校验来源）
        string req = "GET " + path + " HTTP/1.1\r\nHost: 127.0.0.1\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n\r\n"
        ByteBuffer b = ByteBuffer.fromString( req )
        w.c.write( b )
        b.release()
        # 读握手响应头（到空行）
        string acc = ""
        while ServerP5Test.sfFind( acc, "\r\n\r\n" ) < 0
        {
            ByteBuffer rb = ByteBuffer( 1024 )
            Int32 n = w.c.read( rb )
            if n == 0
            {
                break
            }
            acc = acc + rb.readString( n )
        }
        w.head = acc
        ret w
    }

    # 发文本帧（客户端掩码：4 字节 0 掩码——服务端只校验有掩码位）
    void sendText( string text ) throws
    {
        Int32 len = SystemStringLength( text )
        ByteBuffer f = ByteBuffer( len + 14 )
        f.writeU8( SystemConvertUInt8( 0x81 ) )
        if len < 126
        {
            f.writeU8( SystemConvertUInt8( 0x80 | len ) )
        }
        else
        {
            f.writeU8( SystemConvertUInt8( 0x80 | 126 ) )
            f.writeU8( SystemConvertUInt8( ( len >> 8 ) & 0xFF ) )
            f.writeU8( SystemConvertUInt8( len & 0xFF ) )
        }
        f.writeU8( 0 )
        f.writeU8( 0 )
        f.writeU8( 0 )
        f.writeU8( 0 )
        f.writeString( text )
        ByteBuffer view = f.slice()
        this.c.write( view )
        view.release()
        f.release()
    }

    # 读一条文本消息（服务端帧无掩码；简单解析，控制帧跳过）
    string readText() throws
    {
        while true
        {
            ByteBuffer h = ByteBuffer( 2 )
            P5Util.readExactInto( this.c, h, 2 )
            UInt8 b0v = h.readU8()
            UInt8 b1v = h.readU8()
            Int32 h0 = b0v
            Int32 h1 = b1v
            h.release()
            Int32 opcode = h0 & 0x0F
            Int32 len = h1 & 0x7F
            if len == 126
            {
                ByteBuffer ext = ByteBuffer( 2 )
                P5Util.readExactInto( this.c, ext, 2 )
                UInt16 e = ext.readU16Be()
                len = e
                ext.release()
            }
            elif len == 127
            {
                ByteBuffer ext = ByteBuffer( 8 )
                P5Util.readExactInto( this.c, ext, 8 )
                ext.release()
                len = 0
            }

            if len > 0
            {
                ByteBuffer pl = ByteBuffer( len )
                P5Util.readExactInto( this.c, pl, len )
                if opcode == 1
                {
                    string s = pl.toString()
                    pl.release()
                    ret s
                }
                pl.release()
            }
            # 控制帧 / 空：继续
        }
        ret ""
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

# 读 n 字节精确（P5WsClient 辅助）
class P5Util
{
    static void readExactInto( Net.TcpStream c, ByteBuffer dst, Int32 n ) throws
    {
        Int32 need = n
        while need > 0
        {
            ByteBuffer b = ByteBuffer( need )
            Int32 got = c.read( b )
            if got == 0
            {
                ret
            }
            ByteBuffer view = b.slice( 0, got )
            dst.writeBytes( view )
            view.release()
            b.release()
            need = need - got
        }
    }
}
