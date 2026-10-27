import Std;
import Core;
import SLangServer;

# ============================================================================
# ServerP6Test.sl -- SLangServer P6 验收（ServerTest 宿主）
# 设计契约：SERVER_DESIGN.md §8 P6（app 级事件钩子 onStart/onStop/onError /
#   WS 会话标签 s.tag/untag/tagged/tags + 定向组播 broadcastTag /
#   broadcast binary( ByteBuffer ) 重载——形态 A + 形态 B）
#
#   T1  app 级事件钩子：onStart start 末尾恰一次 / onStop stop 收尾恰一次 /
#       onError 管道异常先交钩子（写响应自救覆盖 500 兜底 / 钩子不写响应
#       维持 500 兜底 / 正常路由不受影响 / 异常对象非 null）
#   T2  形态 A WS 标签：handler 闭包内 s.tag 打标（消息驱动，零捕获同套）/
#       tagged·tags 查询 / untag 撤标 / broadcastTag 文本+二进制定向送达
#       （未打标会话零到达）/ broadcast( path, ByteBuffer ) 全量二进制
#   T3  形态 B（独立端口）标签同套：onMessage 回调内打标 /
#       broadcastTag 文本+二进制定向 / broadcast( ByteBuffer ) 全量二进制
#
# 端口：19461（HTTP 形态 A）、19462（WS 形态 B）——避开 P1-P5 端口段。
# 编写约定同 ServerP5Test（手搓 WS 客户端 + 静态字段观测——钩子零捕获，
# 观测值经静态字段回传）。
# ============================================================================

ServerP6Test
{
    static check( string name, bool cond )
    {
        if cond
        {
            Console.println( "[ServerP6Test] " + name + " : OK" )
        }
        else
        {
            Console.println( "[ServerP6Test] " + name + " : FAIL" )
        }
    }

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

    # ── 钩子观测静态（钩子闭包零捕获——观测值经静态字段回传）──
    static Int32 _evtStart = 0
    static Int32 _evtStop = 0
    static Int32 _errCount = 0
    static string _errPath = ""
    static bool _errHasObj = false
    # ── 会话观测静态（handler 回调闭包内回传；ServerP15Test L15 同款
    #    规避：List<SLang.WsSession> 点分类型作泛型参数 Front 模板实例化
    #    NRE——按消息驱动登记：谁发 "tag:vip" 谁入 _sessVip（连接序不可
    #    依赖——协程调度序无契约）；sessions().length 链式访问正常）──
    static SLang.WsSession _sessVip = null

    # 异常源（handler 闭包无 throws 声明不能直接 throw——经本 throws
    # 静态方法调用传播，§6.1 handler 协程异常 -> awaitTask 重抛 -> 500 兜底）
    static void blowUp() throws
    {
        throw SLang.ServerError.AlreadyResponded
    }

    static void fun()
    {
        Console.println( "[ServerP6Test] begin" )
        ServerP6Test.t1Hooks()
        ServerP6Test.t2WsTags()
        ServerP6Test.t3StandaloneTags()
        Console.println( "[ServerP6Test] all done" )
    }

    # ── T1 app 级事件钩子（onStart/onStop/onError；端口 19461）──

    static void t1Hooks()
    {
        Console.println( "[ServerP6Test] T1 begin (port 19461)" )
        ServerP6Test._evtStart = 0
        ServerP6Test._evtStop = 0
        ServerP6Test._errCount = 0
        ServerP6Test._errPath = ""
        ServerP6Test._errHasObj = false
        SLang.HttpServer app = SLang.HttpServer( 19461 )
        app.reset()
        app.onGet( "/boom", function( SLang.Request req, SLang.Response res )
        {
            ServerP6Test.blowUp()    # 异常传播（未写响应）-> onError 钩子
        } )
        app.onGet( "/ok", function( SLang.Request req, SLang.Response res )
        {
            res.text( "fine" )
        } )
        # 钩子注册（字段赋值形态，§4.9；赋值右侧不支持直接闭包字面量——
        # 先存变量再赋值；钩子零捕获——写观测静态）
        function hOnStart = function()
        {
            ServerP6Test._evtStart = ServerP6Test._evtStart + 1
        }
        app.onStart = hOnStart
        function hOnStop = function()
        {
            ServerP6Test._evtStop = ServerP6Test._evtStop + 1
        }
        app.onStop = hOnStop
        function hOnErr = function( SLang.Request req, SLang.Response res, Error e )
        {
            ServerP6Test._errCount = ServerP6Test._errCount + 1
            ServerP6Test._errPath = req.path
            if e != null
            {
                ServerP6Test._errHasObj = true
            }
            res.status( 599 ).text( "hooked" )
        }
        app.onError = hOnErr
        app.start( 19461 )
        ServerP6Test.check( "T1a onStart fired once", ServerP6Test._evtStart == 1 )

        # T1b/T1c 异常路径：钩子接住并写响应 -> 599 覆盖 500 兜底
        Net.HttpResponse r1 = Net.HttpClient.httpGet( "http://127.0.0.1:19461/boom" )
        ServerP6Test.check( "T1b onError hook responds 599",
            r1.statusCode == 599 && r1.body == "hooked" )
        ServerP6Test.check( "T1c onError saw path + error object",
            ServerP6Test._errCount == 1 && ServerP6Test._errPath == "/boom"
            && ServerP6Test._errHasObj )

        # T1d 正常路由不受钩子影响
        Net.HttpResponse r2 = Net.HttpClient.httpGet( "http://127.0.0.1:19461/ok" )
        ServerP6Test.check( "T1d normal route unaffected",
            r2.statusCode == 200 && r2.body == "fine" )

        # T1e/T1f 钩子只记录不写响应 -> 既有 500 兜底路径不变
        function hOnErr2 = function( SLang.Request req, SLang.Response res, Error e )
        {
            ServerP6Test._errCount = ServerP6Test._errCount + 1
        }
        app.onError = hOnErr2
        Net.HttpResponse r3 = Net.HttpClient.httpGet( "http://127.0.0.1:19461/boom" )
        ServerP6Test.check( "T1e silent hook -> 500 fallback", r3.statusCode == 500 )
        ServerP6Test.check( "T1f hook invoked for both", ServerP6Test._errCount == 2 )

        app.stop()
        ServerP6Test.check( "T1g onStop fired once", ServerP6Test._evtStop == 1 )
    }

    # ── T2 形态 A WS 会话标签 + 定向/二进制组播（端口 19461）──

    static void t2WsTags()
    {
        Console.println( "[ServerP6Test] T2 begin (port 19461)" )
        ServerP6Test._sessVip = null
        SLang.HttpServer app = SLang.HttpServer( 19461 )
        app.reset()
        SLang.WebSocketServer ws = SLang.WebSocketServer()
        # handler 闭包内 s.tag 打标（消息驱动，零捕获同套）：
        # "tag:vip" -> 打 vip 标签并登记观测静态 _sessVip（无回显）；
        # 其余消息 echo
        function hWs = function( SLang.WsSession s )
        {
            while true
            {
                Net.WsMessage m = s.receive()
                if m == null
                {
                    break
                }

                if m.text == "tag:vip"
                {
                    ServerP6Test._sessVip = s
                    s.tag( "vip" )
                }
                else
                {
                    s.sendText( "echo:" + m.text )
                }
                m.release()
            }
        }
        ws.websocket( "/ws/room", hWs )
        app.start( 19461 )

        P6WsClient a = P6WsClient.connect( 19461, "/ws/room" )
        P6WsClient b = P6WsClient.connect( 19461, "/ws/room" )
        Coroutine.delay( 100 )
        # 链式 .length（P15 同款规避——List<SLang.WsSession> 点分泛型
        # 局部变量 NRE，逐元素访问一律经静态槽回传）
        ServerP6Test.check( "T2a two sessions online",
            SLang.HttpServerCore.sessions( "/ws/room" ).length == 2 )

        # a 发打标驱动消息；b 保持静默（零驱动即零标签，且避免 b 缓冲
        # 残留 echo 帧干扰 T2e 的零到达首帧探测）
        a.sendText( "tag:vip" )
        Coroutine.delay( 100 )

        # T2b tagged 查询：发 "tag:vip" 的会话（即 a）已打标
        bool taggedOk = false
        if ServerP6Test._sessVip != null
        {
            taggedOk = ServerP6Test._sessVip.tagged( "vip" )
        }

        ServerP6Test.check( "T2b tagging session reports tagged", taggedOk )

        # T2c tags 快照
        List<string> tg = ServerP6Test._sessVip.tags
        ServerP6Test.check( "T2c tags snapshot",
            tg.length == 1 && tg[0] == "vip" )

        # T2d/T2e broadcastTag 文本定向：sent==1 证恰一命中且只达 a；
        # b 探测自 echo 证明零到达（b 此前零收帧，首帧必是 echo:probe——
        # 若 go-vip 泄漏则首帧为 go-vip）
        Int32 sent1 = ws.broadcastTag( "/ws/room", "vip", "go-vip" )
        string gotA = a.readText()
        ServerP6Test.check( "T2d broadcastTag text tagged only",
            sent1 == 1 && gotA == "go-vip" )
        b.sendText( "probe" )
        string gotB = b.readText()
        ServerP6Test.check( "T2e untagged session not reached", gotB == "echo:probe" )

        # T2f broadcastTag 二进制定向
        ByteBuffer bin1 = ServerP6Test.binOf( 0x41, 0x42, 0x43, 0x44 )
        Int32 sent2 = ws.broadcastTag( "/ws/room", "vip", bin1 )
        string binA = a.readBinary()
        ServerP6Test.check( "T2f broadcastTag binary tagged only",
            sent2 == 1 && binA == "ABCD" )

        # T2g broadcast( path, ByteBuffer ) 全量二进制：a、b 都达
        ByteBuffer bin2 = ServerP6Test.binOf( 0x57, 0x58, 0x59, 0x5A )
        Int32 sent3 = ws.broadcast( "/ws/room", bin2 )
        string binA2 = a.readBinary()
        string binB2 = b.readBinary()
        ServerP6Test.check( "T2g broadcast binary all sessions",
            sent3 == 2 && binA2 == "WXYZ" && binB2 == "WXYZ" )

        # T2i untag 撤标后定向零送达
        ServerP6Test._sessVip.untag( "vip" )
        Int32 sent4 = ws.broadcastTag( "/ws/room", "vip", "late" )
        ServerP6Test.check( "T2i untag stops broadcastTag",
            sent4 == 0 && ServerP6Test._sessVip.tagged( "vip" ) == false )

        a.close()
        b.close()
        app.stop()
    }

    # ── T3 形态 B（独立端口 19462）标签 + 定向/二进制组播 ──

    static void t3StandaloneTags()
    {
        Console.println( "[ServerP6Test] T3 begin (port 19462)" )
        SLang.WebSocketServer wss = SLang.WebSocketServer( 19462 )
        wss.onMessage( function( SLang.WsSession s, Net.WsMessage m )
        {
            if m.text == "vip"
            {
                s.tag( "vip" )
            }
            m.release()
        } )
        wss.start( 19462 )
        P6WsClient xa = P6WsClient.connect( 19462, "/" )
        P6WsClient xb = P6WsClient.connect( 19462, "/" )
        Coroutine.delay( 100 )
        xa.sendText( "vip" )
        xb.sendText( "plain" )
        Coroutine.delay( 100 )

        # T3a broadcastTag 文本定向：xa 收 go；xb 下一帧只应是 to-all（零泄漏）
        Int32 s1 = wss.broadcastTag( "vip", "go" )
        string ga = xa.readText()
        ServerP6Test.check( "T3a broadcastTag text -> 1", s1 == 1 && ga == "go" )
        Int32 s2 = wss.broadcast( "to-all" )
        string gb = xb.readText()
        ServerP6Test.check( "T3b untagged leak-free + broadcast all -> 2",
            s2 == 2 && gb == "to-all" )
        string ga2 = xa.readText()
        ServerP6Test.check( "T3b tagged session also got to-all", ga2 == "to-all" )

        # T3c broadcastTag 二进制定向
        ByteBuffer bin1 = ServerP6Test.binOf( 0x41, 0x42, 0x43, 0x44 )
        Int32 s3 = wss.broadcastTag( "vip", bin1 )
        string ba = xa.readBinary()
        ServerP6Test.check( "T3c broadcastTag binary -> 1",
            s3 == 1 && ba == "ABCD" )

        # T3d broadcast( ByteBuffer ) 全量二进制
        ByteBuffer bin2 = ServerP6Test.binOf( 0x57, 0x58, 0x59, 0x5A )
        Int32 s4 = wss.broadcast( bin2 )
        string ba2 = xa.readBinary()
        string bb2 = xb.readBinary()
        ServerP6Test.check( "T3d broadcast binary all -> 2",
            s4 == 2 && ba2 == "WXYZ" && bb2 == "WXYZ" )

        xa.close()
        xb.close()
        wss.stop()
    }

    # 四字节小载荷构造（readBinary 断言用 "ABCD"/"WXYZ" 对照）
    static ByteBuffer binOf( Int32 b0, Int32 b1, Int32 b2, Int32 b3 )
    {
        ByteBuffer b = ByteBuffer( 4 )
        b.writeU8( SystemConvertUInt8( b0 ) )
        b.writeU8( SystemConvertUInt8( b1 ) )
        b.writeU8( SystemConvertUInt8( b2 ) )
        b.writeU8( SystemConvertUInt8( b3 ) )
        ret b
    }
}

# ============================================================================
# P6Util -- 精确读助手（P5Util 同款）
# ============================================================================
class P6Util
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

# ============================================================================
# P6WsClient -- 手搓 WS 客户端（ServerP5Test P5WsClient 同款 + readBinary）
# ============================================================================
class P6WsClient
{
    Net.TcpStream c = null
    string head = ""

    _init_()
    {
        this.c = null
        this.head = ""
    }

    static P6WsClient connect( Int32 port, string path ) throws
    {
        P6WsClient w = P6WsClient()
        w.c = Net.Tcp.connect( "127.0.0.1", port )
        # 最小握手（key 任意 16 字节 b64；服务端不校验来源）
        string req = "GET " + path + " HTTP/1.1\r\nHost: 127.0.0.1\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n\r\n"
        ByteBuffer b = ByteBuffer.fromString( req )
        w.c.write( b )
        b.release()
        # 读握手响应头（到空行）
        string acc = ""
        while ServerP6Test.sfFind( acc, "\r\n\r\n" ) < 0
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

    # 读一条帧（服务端帧无掩码；简单解析，控制帧跳过）。
    # opcode == 1 -> 文本；opcode == 2 -> 二进制（toString 对照用）
    string readFrame( Int32 wantOp ) throws
    {
        while true
        {
            ByteBuffer h = ByteBuffer( 2 )
            P6Util.readExactInto( this.c, h, 2 )
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
                P6Util.readExactInto( this.c, ext, 2 )
                UInt16 e = ext.readU16Be()
                len = e
                ext.release()
            }
            elif len == 127
            {
                ByteBuffer ext = ByteBuffer( 8 )
                P6Util.readExactInto( this.c, ext, 8 )
                ext.release()
                len = 0
            }

            if len > 0
            {
                ByteBuffer pl = ByteBuffer( len )
                P6Util.readExactInto( this.c, pl, len )
                if opcode == wantOp
                {
                    string s = pl.toString()
                    pl.release()
                    ret s
                }
                pl.release()
            }
            # 其他帧（含控制帧 / 非目标类型）：继续
        }
        ret ""
    }

    string readText() throws
    {
        ret this.readFrame( 1 )
    }

    string readBinary() throws
    {
        ret this.readFrame( 2 )
    }

    void close()
    {
        label one
        {
            if this.c != null
            {
                this.c.close()
            }
        }
        catch { }
        this.c = null
    }
}
