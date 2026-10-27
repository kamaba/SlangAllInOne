import Std;
import Core;
import SLangServer;

# ============================================================================
# ServerBench.sl -- SLangServer BenchMark 压测矩阵（ServerTest 宿主）
# 设计契约：SERVER_DESIGN.md §25（P8 落地实录）——量化 P7 流式解析相对
#   内存形态的收益（树化收益与流式内存峰值量化，§10 风险 #17 闭环）。
#
#   M1 上传解析矩阵（端口 19481，单 app 双路由对称落盘保公平）：
#     模式 stream : POST /bench/stream（streamBody=true）→ multipartStream
#                  逐 part 迭代，文件 part saveAs("bench_stream.bin")
#     模式 memory : POST /bench/memory（默认路由，引擎 4a 预解析）→
#                  req.form("note") + req.file("blob").saveAs("bench_mem.bin")
#     尺寸档      : 64KB / 512KB / 2MB / 8MB（净荷 "0123456789" 循环）
#     方法        : 每档预热 1 次（不计时，兼正确性验证）→ Memory.collect()
#                  稳定环境 → 计时 3 次取最小；计时窗 = connect → 全量发送
#                  → 读完整响应；窗内分配 = totalAllocated 差值（delta<0
#                  视为回绕丢弃样本）；请求体深拷贝在计时窗外（send 会推
#                  进 readerIndex，不可复用同一 buffer）。
#     指标        : min ms / MB/s（1 位小数，×10 整数算法）/ alloc 字节
#
#   M2 连接矩阵（端口 19482，GET /probe 微响应）：
#     keepalive : 同一连接 100× 请求（HTTP/1.1 默认保活）
#     close     : 100× 每请求新连接 + Connection: close
#     方法      : 预热 10 次；指标 = 总 ms → req/s 与 µs/req
#
#   M3 控制器实例矩阵（端口 19483，P9 §26 量化 @InstanceAttr bind-once 收益）：
#     singleton : @InstanceAttr 控制器 GET /b3s/ping（首请求 bind-once，后续
#                 复用单实例——零实例化开销）
#     fresh     : 每请求一实例控制器 GET /b3f/ping（默认语义 §4.10，每
#                 请求 vm_late_instance_instantiate：对象头 + 4 字段 +
#                 _init_ 子 VM 执行）
#     控制器形态：4 字段（2 string / 2 Int32）+ _init_ 全字段赋值，模拟
#     真实控制器；keepalive 同连接 200× 微响应，预热 10 次（singleton
#     bind-once 完成 / fresh 达稳态）。
#     指标       : 总 ms / req/s / 窗内 alloc 差值（200 次累计，均值
#                 B/req）；alloc 是实例化开销最稳的量化（时间受 IO 噪声
#                 掩没，alloc 差值确定性成立）。
#
# 端口：19481（M1）、19482（M2）、19483（M3）——避开 P0-P7/P9 端口段。
# 输出前缀 [ServerBench] 独立于回归统计口径（不进入 213 计数）。
# 编写约定同 ServerP7Test（手搓 raw 客户端；助手按复制式惯例自带）。
# ============================================================================

# ── M3 控制器 A：单例（@InstanceAttr bind-once，后续请求零实例化）──

@InstanceAttr
@OnRoute( "/b3s" )
class BenchSingletonController
{
    string name = ""
    Int32 level = 0
    Int32 quota = 0
    string tag = ""

    _init_()
    {
        this.name = "svc"
        this.level = 1
        this.quota = 100
        this.tag = "singleton"
    }

    @OnGet( "/ping" )
    public void ping( SLang.Request req, SLang.Response res )
    {
        res.text( "s-ok " + this.name )
    }
}

# ── M3 控制器 B：每请求一实例对照（默认语义 §4.10）──

@OnRoute( "/b3f" )
class BenchFreshController
{
    string name = ""
    Int32 level = 0
    Int32 quota = 0
    string tag = ""

    _init_()
    {
        this.name = "svc"
        this.level = 1
        this.quota = 100
        this.tag = "fresh"
    }

    @OnGet( "/ping" )
    public void ping( SLang.Request req, SLang.Response res )
    {
        res.text( "f-ok " + this.name )
    }
}

ServerBench
{
    # ── m1Run 出参（无元组，经静态字段回传）──
    static Int64 gMinMs = 0L
    static Int32 gMinAlloc = 0
    static bool gAllocValid = false
    static bool gAllOk = true

    static check( string name, bool cond )
    {
        if cond
        {
            Console.println( "[ServerBench] " + name + " : OK" )
        }
        else
        {
            Console.println( "[ServerBench] " + name + " : FAIL" )
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

    static void fun()
    {
        Console.println( "[ServerBench] begin" )
        ServerBench.gAllOk = true
        ServerBench.m1Upload()
        ServerBench.m2Conn()
        ServerBench.m3Instance()
        Console.println( "[ServerBench] all done" )
    }

    # ── M1 上传解析矩阵（端口 19481）──

    static void m1Upload()
    {
        Console.println( "[ServerBench] M1 begin (port 19481)" )
        Console.println( "[ServerBench] M1 matrix : {stream,memory} x {64KB,512KB,2MB,8MB} ; min-of-3 ; ms / MB/s / alloc" )
        SLang.HttpServer app = SLang.HttpServer( 19481 )
        app.reset()

        # stream 路由：multipartStream 逐 part，文件落盘
        function hStream = function( SLang.Request req, SLang.Response res )
        {
            SLang.MultipartReader m = req.multipartStream()
            Int32 sv = 0
            while true
            {
                SLang.MultipartPart p = m.nextPart()
                if p == null
                {
                    break
                }
                if p.isFile
                {
                    if p.saveAs( "bench_stream.bin" )
                    {
                        sv = 1
                    }
                }
                else
                {
                    ByteBuffer vb = p.readAll()
                    vb.release()
                }
            }
            res.text( "sv=" + sv.toString() )
        }
        SLang.RouteInfo rStream = app.onPost( "/bench/stream", hStream )
        rStream.streamBody = true

        # memory 路由：引擎 4a 预解析（form/file 内存形态）
        function hMem = function( SLang.Request req, SLang.Response res )
        {
            string u = req.form( "note" )
            SLang.UploadedFile f = req.file( "blob" )
            Int32 sv = 0
            Int64 sz = 0
            if f != null
            {
                sz = f.size
                if f.saveAs( "bench_mem.bin" )
                {
                    sv = 1
                }
            }
            res.text( "u=" + u + "|sz=" + sz.toString() + "|sv=" + sv.toString() )
        }
        app.onPost( "/bench/memory", hMem )

        app.start( 19481 )
        File.delete( "bench_stream.bin" )
        File.delete( "bench_mem.bin" )

        for Int32 si = 0, si < 4, si = si + 1
        {
            Int32 size = 65536
            if si == 1
            {
                size = 524288
            }
            elif si == 2
            {
                size = 2097152
            }
            elif si == 3
            {
                size = 8388608
            }
            string lbl = ServerBench.sizeLabel( size )
            ServerBench.m1Run( 19481, size, true )
            Int64 sMs = ServerBench.gMinMs
            Int32 sAlloc = ServerBench.gMinAlloc
            bool sAllocOk = ServerBench.gAllocValid
            ServerBench.m1Run( 19481, size, false )
            Int64 mMs = ServerBench.gMinMs
            Int32 mAlloc = ServerBench.gMinAlloc
            bool mAllocOk = ServerBench.gAllocValid

            # 对比行（memory/stream 倍率，1 位小数）
            string tRatio = "n/a"
            if sMs > 0
            {
                Int64 tr10 = mMs * 10 / sMs
                tRatio = ( tr10 / 10 ).toString() + "." + ( tr10 % 10 ).toString() + "x"
            }
            string ar = "n/a"
            if sAllocOk && mAllocOk && sAlloc > 0 && mAlloc >= 0
            {
                Int64 ar10 = mAlloc * 10L / sAlloc
                ar = ( ar10 / 10 ).toString() + "." + ( ar10 % 10 ).toString() + "x"
            }
            Console.println( "[ServerBench] M1 " + lbl + " ratio mem/stream : time=" + tRatio + " alloc=" + ar )
        }

        File.delete( "bench_stream.bin" )
        File.delete( "bench_mem.bin" )
        ServerBench.check( "M1 timed runs all ok", ServerBench.gAllOk )
        app.stop()
    }

    # 单档单模式：构造 → 预热（兼正确性）→ 计时 3 次取最小；结果经静态字段回传
    static void m1Run( Int32 port, Int32 size, bool streamMode ) throws
    {
        string mode = "stream"
        string path = "/bench/stream"
        string saveName = "bench_stream.bin"
        if streamMode == false
        {
            mode = "memory"
            path = "/bench/memory"
            saveName = "bench_mem.bin"
        }
        string lbl = ServerBench.sizeLabel( size )

        # 净荷：size 字节 "0123456789" 循环（10240 字符块填充，10 次倍增构造）
        string blk = "0123456789"
        for Int32 i = 0, i < 10, i = i + 1
        {
            blk = blk + blk
        }
        ByteBuffer fdata = ByteBuffer( size )
        Int32 written = 0
        while written + 10240 <= size
        {
            fdata.writeString( blk )
            written = written + 10240
        }
        if written < size
        {
            fdata.writeString( SystemStringRange( blk, 0, size - written ) )
        }

        # 请求 = 头 + multipart body 拼进同一 buffer（单次全量 write）
        ByteBuffer body = ByteBuffer()
        ServerBench.mpField( body, "BNC", "note", "bench" )
        ServerBench.mpFile( body, "BNC", "blob", "b.bin", "application/octet-stream", fdata )
        ServerBench.mpFinish( body, "BNC" )
        fdata.release()
        Int32 blen = body.readableBytes
        string head = "POST " + path + " HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Type: multipart/form-data; boundary=BNC\r\nContent-Length: " + blen.toString() + "\r\nConnection: close\r\n\r\n"
        ByteBuffer reqBuf = ByteBuffer()
        reqBuf.writeString( head )
        reqBuf.writeBytes( body )
        body.release()

        # 预热 1 次（不计时；兼正确性验证——两模式对称落盘同尺寸文件）
        File.delete( saveName )
        ByteBuffer w1 = reqBuf.copy()
        BenchRawClient cw = BenchRawClient.connect( port )
        cw.sendBuf( w1 )
        BenchResp rw = cw.readResp()
        cw.close()
        w1.release()

        bool respOk = rw._ok && ServerBench.sfFind( rw._body, "sv=1" ) >= 0
        if streamMode == false
        {
            respOk = rw._ok && ServerBench.sfFind( rw._body, "u=bench" ) >= 0
                && ServerBench.sfFind( rw._body, "sz=" + size.toString() ) >= 0
                && ServerBench.sfFind( rw._body, "sv=1" ) >= 0
        }
        Int64 saved = File.getSize( saveName )
        bool sizeOk = saved == size
        string all = File.readAllText( saveName )
        bool winOk = ServerBench.dataWindowOk( all, 0, 16 )
            && ServerBench.dataWindowOk( all, size / 2, 16 )
            && ServerBench.dataWindowOk( all, size - 16, 16 )
        ServerBench.check( "M1 " + mode + " " + lbl + " respond+save ok", respOk && sizeOk && winOk )

        # 计时 3 次取最小（深拷贝在计时窗外；窗 = connect→全量发送→读完整响应）
        Memory.collect()
        Int64 bestMs = 0
        bool haveMs = false
        Int32 bestAlloc = -1
        for Int32 k = 0, k < 3, k = k + 1
        {
            ByteBuffer cp = reqBuf.copy()
            Int32 a0 = Memory.totalAllocated()
            Int64 t0 = OS.Timer.clock()
            BenchRawClient c = BenchRawClient.connect( port )
            c.sendBuf( cp )
            BenchResp r = c.readResp()
            Int64 t1 = OS.Timer.clock()
            Int32 a1 = Memory.totalAllocated()
            c.close()
            cp.release()
            if r._ok == false
            {
                ServerBench.gAllOk = false
            }
            else
            {
                Int64 ms = t1 - t0
                Int32 alloc = a1 - a0
                if haveMs == false || ms < bestMs
                {
                    bestMs = ms
                    haveMs = true
                }
                if alloc >= 0
                {
                    if bestAlloc < 0 || alloc < bestAlloc
                    {
                        bestAlloc = alloc
                    }
                }
            }
        }
        reqBuf.release()

        ServerBench.gMinMs = bestMs
        ServerBench.gMinAlloc = bestAlloc
        if bestAlloc >= 0
        {
            ServerBench.gAllocValid = true
        }
        else
        {
            ServerBench.gAllocValid = false
        }

        string allocTxt = "wrap"
        if ServerBench.gAllocValid
        {
            allocTxt = "+" + bestAlloc.toString()
        }
        Console.println( "[ServerBench] M1 " + mode + " " + lbl + " : min=" + bestMs.toString() + "ms "
            + ServerBench.fmtMbps( size, bestMs ) + "MB/s alloc=" + allocTxt )
    }

    # ── M2 连接矩阵（端口 19482）──

    static void m2Conn()
    {
        Console.println( "[ServerBench] M2 begin (port 19482)" )
        Console.println( "[ServerBench] M2 matrix : {keepalive,close} x 100 req ; total ms / req-per-s / us-per-req" )
        SLang.HttpServer app = SLang.HttpServer( 19482 )
        app.reset()

        function hProbe = function( SLang.Request req, SLang.Response res )
        {
            res.text( "probe-ok" )
        }
        app.onGet( "/probe", hProbe )

        app.start( 19482 )

        Int32 n = 100
        string kaReq = "GET /probe HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n"
        string clReq = "GET /probe HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n"

        # 预热 10 次（同连接）
        BenchRawClient cw = BenchRawClient.connect( 19482 )
        for Int32 i = 0, i < 10, i = i + 1
        {
            cw.send( kaReq )
            BenchResp rw = cw.readResp()
            if rw._ok == false
            {
                break
            }
        }
        cw.close()

        # keepalive：同连接 n 次
        Int32 kaOk = 0
        Int64 t0 = OS.Timer.clock()
        BenchRawClient c = BenchRawClient.connect( 19482 )
        for Int32 i = 0, i < n, i = i + 1
        {
            c.send( kaReq )
            BenchResp r = c.readResp()
            if r._ok && ServerBench.sfFind( r._body, "probe-ok" ) >= 0
            {
                kaOk = kaOk + 1
            }
        }
        Int64 kaMs = OS.Timer.clock() - t0
        c.close()

        # close：每请求新连接
        Int32 clOk = 0
        Int64 t1 = OS.Timer.clock()
        for Int32 i = 0, i < n, i = i + 1
        {
            BenchRawClient c2 = BenchRawClient.connect( 19482 )
            c2.send( clReq )
            BenchResp r2 = c2.readResp()
            if r2._ok && ServerBench.sfFind( r2._body, "probe-ok" ) >= 0
            {
                clOk = clOk + 1
            }
            c2.close()
        }
        Int64 clMs = OS.Timer.clock() - t1

        ServerBench.check( "M2 200 responses ok", kaOk == n && clOk == n )
        Console.println( "[ServerBench] M2 keepalive " + n.toString() + "req : total=" + kaMs.toString() + "ms "
            + ServerBench.fmtRps( n, kaMs ) + "req/s " + ServerBench.fmtUspr( kaMs, n ) + "us/req" )
        Console.println( "[ServerBench] M2 close    " + n.toString() + "req : total=" + clMs.toString() + "ms "
            + ServerBench.fmtRps( n, clMs ) + "req/s " + ServerBench.fmtUspr( clMs, n ) + "us/req" )
        app.stop()
    }

    # ── M3 控制器实例矩阵（端口 19483；P9 §26 量化 @InstanceAttr 收益）──

    static void m3Instance()
    {
        Console.println( "[ServerBench] M3 begin (port 19483)" )
        Console.println( "[ServerBench] M3 matrix : {singleton,fresh} x 200 req keepalive ; total ms / req-per-s / alloc" )
        SLang.HttpServer app = SLang.HttpServer( 19483 )
        app.reset()
        app.usePreloadRoutes()
        app.start( 19483 )

        Int32 n = 200
        string sReq = "GET /b3s/ping HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n"
        string fReq = "GET /b3f/ping HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n"

        # 预热各 10 次（singleton bind-once 完成；fresh 达稳态）
        BenchRawClient pw = BenchRawClient.connect( 19483 )
        for Int32 i = 0, i < 10, i = i + 1
        {
            pw.send( sReq )
            BenchResp pr = pw.readResp()
            pw.send( fReq )
            BenchResp pr2 = pw.readResp()
            if pr._ok == false || pr2._ok == false
            {
                break
            }
        }
        pw.close()

        # singleton 轮：keepalive 同连接 n 次；窗内 alloc 差值
        Memory.collect()
        Int32 sOk = 0
        Int32 a0 = Memory.totalAllocated()
        Int64 t0 = OS.Timer.clock()
        BenchRawClient cs = BenchRawClient.connect( 19483 )
        for Int32 i = 0, i < n, i = i + 1
        {
            cs.send( sReq )
            BenchResp r = cs.readResp()
            if r._ok && ServerBench.sfFind( r._body, "s-ok" ) >= 0
            {
                sOk = sOk + 1
            }
        }
        Int64 sMs = OS.Timer.clock() - t0
        Int32 sAlloc = Memory.totalAllocated() - a0
        cs.close()

        # fresh 轮：每请求 vm_late_instance_instantiate（4 字段 + _init_）
        Memory.collect()
        Int32 fOk = 0
        Int32 b0 = Memory.totalAllocated()
        Int64 t1 = OS.Timer.clock()
        BenchRawClient cf = BenchRawClient.connect( 19483 )
        for Int32 i = 0, i < n, i = i + 1
        {
            cf.send( fReq )
            BenchResp r2 = cf.readResp()
            if r2._ok && ServerBench.sfFind( r2._body, "f-ok" ) >= 0
            {
                fOk = fOk + 1
            }
        }
        Int64 fMs = OS.Timer.clock() - t1
        Int32 fAlloc = Memory.totalAllocated() - b0
        cf.close()

        ServerBench.check( "M3 400 responses ok", sOk == n && fOk == n )
        Console.println( "[ServerBench] M3 singleton " + n.toString() + "req : total=" + sMs.toString() + "ms "
            + ServerBench.fmtRps( n, sMs ) + "req/s alloc=+" + sAlloc.toString()
            + " (avg " + ( sAlloc / n ).toString() + "B/req)" )
        Console.println( "[ServerBench] M3 fresh     " + n.toString() + "req : total=" + fMs.toString() + "ms "
            + ServerBench.fmtRps( n, fMs ) + "req/s alloc=+" + fAlloc.toString()
            + " (avg " + ( fAlloc / n ).toString() + "B/req)" )
        if sAlloc > 0 && fAlloc >= 0
        {
            Int64 ar10 = fAlloc * 10L / sAlloc
            Console.println( "[ServerBench] M3 alloc ratio fresh/singleton : " + ( ar10 / 10 ).toString()
                + "." + ( ar10 % 10 ).toString() + "x" )
        }
        app.stop()
    }

    # ── 格式化与校验助手 ──

    static string sizeLabel( Int32 size )
    {
        if size == 65536
        {
            ret "64KB"
        }
        if size == 524288
        {
            ret "512KB"
        }
        if size == 2097152
        {
            ret "2MB"
        }
        ret "8MB"
    }

    # MB/s 定点 1 位小数（×10 整数算法；ms<1 按 1 防除零）
    static string fmtMbps( Int32 sizeBytes, Int64 ms )
    {
        Int64 dms = ms
        if dms < 1
        {
            dms = 1
        }
        Int64 v10 = sizeBytes * 10000L / ( dms * 1048576L )
        ret ( v10 / 10 ).toString() + "." + ( v10 % 10 ).toString()
    }

    # req/s（整数；ms<1 按 1 防除零）
    static string fmtRps( Int32 n, Int64 ms )
    {
        Int64 dms = ms
        if dms < 1
        {
            dms = 1
        }
        Int64 rps = n * 1000L / dms
        ret rps.toString()
    }

    # µs/req（整数）
    static string fmtUspr( Int64 ms, Int32 n )
    {
        Int64 uspr = ms * 1000 / n
        ret uspr.toString()
    }

    # 校验 all[from, from+len) 为 "0123456789" 循环对齐窗口（任意偏移）
    static bool dataWindowOk( string all, Int32 from, Int32 len )
    {
        Int32 alen = SystemStringLength( all )
        if from < 0 || len <= 0 || from + len > alen
        {
            ret false
        }
        for Int32 j = 0, j < len, j = j + 1
        {
            Int32 expect = ( from + j ) % 10
            if SystemStringCharCodeAt( all, from + j ) != 48 + expect
            {
                ret false
            }
        }
        ret true
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
    static Int32 bnHex( string s )
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

    # ── multipart 构造助手（P7 复制）──

    static void mpField( ByteBuffer body, string boundary, string name, string value )
    {
        body.writeString( "--" + boundary + "\r\n" )
        body.writeString( "Content-Disposition: form-data; name=\"" + name + "\"\r\n\r\n" )
        body.writeString( value )
        body.writeString( "\r\n" )
    }

    static void mpFile( ByteBuffer body, string boundary, string field, string filename, string ctype, ByteBuffer content )
    {
        body.writeString( "--" + boundary + "\r\n" )
        body.writeString( "Content-Disposition: form-data; name=\"" + field + "\"; filename=\"" + filename + "\"\r\n" )
        if SystemStringLength( ctype ) > 0
        {
            body.writeString( "Content-Type: " + ctype + "\r\n" )
        }
        body.writeString( "\r\n" )
        body.writeBytes( content )
        body.writeString( "\r\n" )
    }

    static void mpFinish( ByteBuffer body, string boundary )
    {
        body.writeString( "--" + boundary + "--\r\n" )
    }
}

# ============================================================================
# BenchResp / BenchRawClient -- 原始 HTTP 基准客户端（ServerP7Test 同款
# + sendBuf：全量写出 ByteBuffer，send 推进 readerIndex 后由调用方 release）
# ============================================================================
class BenchResp
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

class BenchRawClient
{
    Net.TcpStream c = null
    string rtext = ""

    _init_()
    {
        this.c = null
        this.rtext = ""
    }

    static BenchRawClient connect( Int32 port ) throws
    {
        BenchRawClient rc = BenchRawClient()
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

    void sendBuf( ByteBuffer b ) throws
    {
        this.c.write( b )
    }

    string readLine() throws
    {
        Int32 pos = ServerBench.sfFind( this.rtext, "\n" )
        while pos < 0
        {
            ByteBuffer b = ByteBuffer( 1024 )
            Int32 n = this.c.read( b )
            if n == 0
            {
                ret null
            }
            this.rtext = this.rtext + b.readString( n )
            pos = ServerBench.sfFind( this.rtext, "\n" )
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

    BenchResp readResp() throws
    {
        BenchResp r = BenchResp()
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
        if ServerBench.sfFind( head, "Transfer-Encoding: chunked" ) >= 0
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
                    Int32 sz = ServerBench.bnHex( sizeLine )
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
        Int32 cl = ServerBench.headInt( head, "Content-Length: " )
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
