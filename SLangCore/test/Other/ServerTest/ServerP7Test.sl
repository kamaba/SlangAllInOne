import Std;
import Core;
import SLangServer;

# ============================================================================
# ServerP7Test.sl -- SLangServer P7 验收（ServerTest 宿主）
# 设计契约：SERVER_DESIGN.md §6.6 P7（multipart 流式解析 MultipartReader——
#   streamBody 路由下 nextPart 逐 part 迭代 + read/readAll/saveAs 消费；
#   Request.multipartStream() 首取缓存单实例；引擎收尾 multipart 语义排干）
#
#   T1  基础迭代：multipartStream 缓存单实例（同请求两调同引用）/
#       字段+文件 part 解析（field/filename/contentType/isFile/readAll）/
#       parts 计数 + isDone 终态
#   T2  大文件落盘：300KB 文件 part → saveAs 边收边写 + 首/中/尾内容对照
#   T3  分帧鲁棒：首 boundary 确定性切断 5 段投递（段间 50ms）
#   T4  空表单：零 part（"--B--" 直接收工）/ preamble 行容忍
#   T5  混合场景：(a) 非流式路由 multipartStream 返 null + form 内存语义
#       (b) 非 multipart CT 流式路由返 null 回退裸读 (c) boundary 缺失
#       返 null + 引擎兜底排干（同连接 keep-alive 继续）
#   T6  非流式 multipart 不回归：引擎 4a 预解析 form/file 族
#   T7  半读收尾：(a) multipart 文件 part 半读（引擎 _drainTail 闭环）
#       (b) 裸流半读（drainer _remain 接力）——同连接 keep-alive 继续
#
# 端口：19471（T1-T4）、19472（T5-T7）——避开 P0-P6 端口段。
# 编写约定同 ServerP5Test（手搓 raw 客户端；助手按复制式惯例自带）。
# ============================================================================

ServerP7Test
{
    static check( string name, bool cond )
    {
        if cond
        {
            Console.println( "[ServerP7Test] " + name + " : OK" )
        }
        else
        {
            Console.println( "[ServerP7Test] " + name + " : FAIL" )
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
        Console.println( "[ServerP7Test] begin" )
        ServerP7Test.t1Basic()
        ServerP7Test.t2SaveAs()
        ServerP7Test.t3ChunkedWire()
        ServerP7Test.t4Empty()
        ServerP7Test.t5Mixed()
        ServerP7Test.t6NonStream()
        ServerP7Test.t7HalfRead()
        Console.println( "[ServerP7Test] all done" )
    }

    # ── T1 基础迭代（端口 19471）──

    static void t1Basic()
    {
        Console.println( "[ServerP7Test] T1 begin (port 19471)" )
        SLang.HttpServer app = SLang.HttpServer( 19471 )
        app.reset()

        # 缓存单实例 + 字段/文件 part 解析 + isDone 终态
        function hUp = function( SLang.Request req, SLang.Response res )
        {
            SLang.MultipartReader m1 = req.multipartStream()
            SLang.MultipartReader m2 = req.multipartStream()
            Int32 cached = 0
            if m1 != null
            {
                if m2 != null
                {
                    if m1 == m2
                    {
                        cached = 1
                    }
                }
            }
            Int32 parts = 0
            string u = ""
            string fn = ""
            string pct = ""
            Int32 sz = 0
            Int32 fc = 0
            while true
            {
                SLang.MultipartPart p = m1.nextPart()
                if p == null
                {
                    break
                }
                parts = parts + 1
                if p.isFile
                {
                    ByteBuffer fb = p.readAll()
                    if fb.toString() == "ABCDEFGHIJKL"
                    {
                        fc = 1
                    }
                    sz = fb.readableBytes
                    fb.release()
                    fn = p.filename
                    pct = p.contentType
                }
                else
                {
                    ByteBuffer vb = p.readAll()
                    u = vb.toString()
                    vb.release()
                }
            }
            Int32 done = 0
            if m1.isDone
            {
                done = 1
            }
            res.text( "parts=" + parts.toString() + "|u=" + u + "|fn=" + fn
                + "|ct=" + pct + "|sz=" + sz.toString() + "|fc=" + fc.toString()
                + "|cached=" + cached.toString() + "|done=" + done.toString() )
        }
        SLang.RouteInfo rUp = app.onPost( "/up", hUp )
        rUp.streamBody = true

        app.start( 19471 )

        # 字段 username=alice + 文件 avatar（12 字节）
        ByteBuffer body = ByteBuffer()
        ServerP7Test.mpField( body, "P7A", "username", "alice" )
        ByteBuffer fdata = ByteBuffer.fromString( "ABCDEFGHIJKL" )
        ServerP7Test.mpFile( body, "P7A", "avatar", "a.bin", "application/octet-stream", fdata )
        ServerP7Test.mpFinish( body, "P7A" )
        fdata.release()
        Int32 blen = body.readableBytes
        string bodyStr = body.toString()
        body.release()
        string r1 = ServerP7Test.p7Req( 19471, "POST /up HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Type: multipart/form-data; boundary=P7A\r\nContent-Length: " + blen.toString() + "\r\nConnection: close\r\n\r\n" + bodyStr )
        ServerP7Test.check( "T1a multipartStream cached single instance",
            sfFind( r1, "cached=1" ) >= 0 )
        ServerP7Test.check( "T1b field+file parsed",
            sfFind( r1, "u=alice" ) >= 0 && sfFind( r1, "fn=a.bin" ) >= 0
            && sfFind( r1, "ct=application/octet-stream" ) >= 0
            && sfFind( r1, "sz=12" ) >= 0 && sfFind( r1, "fc=1" ) >= 0 )
        ServerP7Test.check( "T1c parts=2 + isDone",
            sfFind( r1, "parts=2" ) >= 0 && sfFind( r1, "done=1" ) >= 0 )

        app.stop()
    }

    # ── T2 大文件落盘（端口 19471）──

    static void t2SaveAs()
    {
        Console.println( "[ServerP7Test] T2 begin (port 19471)" )
        File.delete( "p7_stream_big.bin" )
        SLang.HttpServer app = SLang.HttpServer( 19471 )
        app.reset()

        function hSave = function( SLang.Request req, SLang.Response res )
        {
            SLang.MultipartReader m = req.multipartStream()
            Int32 ok = 0
            while true
            {
                SLang.MultipartPart p = m.nextPart()
                if p == null
                {
                    break
                }

                if p.isFile
                {
                    if p.saveAs( "p7_stream_big.bin" )
                    {
                        ok = 1
                    }
                }
                else
                {
                    ByteBuffer vb = p.readAll()
                    vb.release()
                }
            }
            res.text( "ok=" + ok.toString() )
        }
        SLang.RouteInfo rSave = app.onPost( "/save", hSave )
        rSave.streamBody = true

        app.start( 19471 )

        # 307200 字节（30720 × "0123456789"）
        ByteBuffer fdata = ByteBuffer( 307200 )
        for Int32 i = 0, i < 30720, i = i + 1
        {
            fdata.writeString( "0123456789" )
        }
        ByteBuffer body = ByteBuffer()
        ServerP7Test.mpField( body, "P7B", "note", "big" )
        ServerP7Test.mpFile( body, "P7B", "blob", "big.bin", "application/octet-stream", fdata )
        ServerP7Test.mpFinish( body, "P7B" )
        fdata.release()
        Int32 blen = body.readableBytes
        string bodyStr = body.toString()
        body.release()
        string r1 = ServerP7Test.p7Req( 19471, "POST /save HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Type: multipart/form-data; boundary=P7B\r\nContent-Length: " + blen.toString() + "\r\nConnection: close\r\n\r\n" + bodyStr )

        bool respOk = sfFind( r1, "ok=1" ) >= 0
        Int64 savedSize = File.getSize( "p7_stream_big.bin" )
        string all = File.readAllText( "p7_stream_big.bin" )
        bool sizeOk = savedSize == 307200 && SystemStringLength( all ) == 307200
        bool headOk = SystemStringRange( all, 0, 10 ) == "0123456789"
        bool midOk = SystemStringRange( all, 153590, 153600 ) == "0123456789"
        bool tailOk = SystemStringRange( all, 307190, 307200 ) == "0123456789"
        ServerP7Test.check( "T2a saveAs 300KB responded ok", respOk )
        ServerP7Test.check( "T2b saved file size+head/mid/tail",
            sizeOk && headOk && midOk && tailOk )
        File.delete( "p7_stream_big.bin" )

        app.stop()
    }

    # ── T3 分帧鲁棒（端口 19471；首 boundary 跨 TCP 段切断）──

    static void t3ChunkedWire()
    {
        Console.println( "[ServerP7Test] T3 begin (port 19471)" )
        SLang.HttpServer app = SLang.HttpServer( 19471 )
        app.reset()

        function hCross = function( SLang.Request req, SLang.Response res )
        {
            SLang.MultipartReader m = req.multipartStream()
            Int32 parts = 0
            string u = ""
            Int32 sz = 0
            while true
            {
                SLang.MultipartPart p = m.nextPart()
                if p == null
                {
                    break
                }
                parts = parts + 1
                if p.isFile
                {
                    ByteBuffer fb = p.readAll()
                    sz = fb.readableBytes
                    fb.release()
                }
                else
                {
                    ByteBuffer vb = p.readAll()
                    u = vb.toString()
                    vb.release()
                }
            }
            Int32 done = 0
            if m.isDone
            {
                done = 1
            }
            res.text( "parts=" + parts.toString() + "|u=" + u
                + "|sz=" + sz.toString() + "|done=" + done.toString() )
        }
        SLang.RouteInfo rCross = app.onPost( "/cross", hCross )
        rCross.streamBody = true

        app.start( 19471 )

        # 300 字节文件 + 字段；整个请求文本按确定性切点分 5 段投递
        ByteBuffer fdata = ByteBuffer( 300 )
        for Int32 i = 0, i < 30, i = i + 1
        {
            fdata.writeString( "0123456789" )
        }
        ByteBuffer body = ByteBuffer()
        ServerP7Test.mpField( body, "P7XB", "who", "cross-chunk" )
        ServerP7Test.mpFile( body, "P7XB", "data", "c.bin", "application/octet-stream", fdata )
        ServerP7Test.mpFinish( body, "P7XB" )
        fdata.release()
        Int32 blen = body.readableBytes
        string bodyStr = body.toString()
        body.release()
        string head = "POST /cross HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Type: multipart/form-data; boundary=P7XB\r\nContent-Length: " + blen.toString() + "\r\n\r\n"
        string reqText = head + bodyStr
        Int32 total = SystemStringLength( reqText )
        # 切点落在首个 "\r\n--P7XB" 边界内部（+5 → "--P7X" 与 "B" 分离）
        Int32 bpos = ServerP7Test.sfFind( reqText, "\r\n--P7XB" )
        Int32 cut = bpos + 5
        P7RawClient c = P7RawClient.connect( 19471 )
        c.send( SystemStringRange( reqText, 0, cut ) )
        Coroutine.delay( 50 )
        Int32 p1 = cut + 80
        if p1 > total
        {
            p1 = total
        }
        c.send( SystemStringRange( reqText, cut, p1 ) )
        Coroutine.delay( 50 )
        Int32 p2 = p1 + 80
        if p2 > total
        {
            p2 = total
        }
        c.send( SystemStringRange( reqText, p1, p2 ) )
        Coroutine.delay( 50 )
        Int32 p3 = p2 + 80
        if p3 > total
        {
            p3 = total
        }
        c.send( SystemStringRange( reqText, p2, p3 ) )
        Coroutine.delay( 50 )
        if p3 < total
        {
            c.send( SystemStringRange( reqText, p3, total ) )
        }
        P7Resp r1 = c.readResp()
        bool crossOk = r1._ok && sfFind( r1._body, "u=cross-chunk" ) >= 0
        ServerP7Test.check( "T3a boundary split across wire, field intact", crossOk )
        ServerP7Test.check( "T3b file 300 bytes + done",
            sfFind( r1._body, "sz=300" ) >= 0 && sfFind( r1._body, "done=1" ) >= 0 )
        c.close()

        app.stop()
    }

    # ── T4 空表单（端口 19471）──

    static void t4Empty()
    {
        Console.println( "[ServerP7Test] T4 begin (port 19471)" )
        SLang.HttpServer app = SLang.HttpServer( 19471 )
        app.reset()

        function hEmpty = function( SLang.Request req, SLang.Response res )
        {
            SLang.MultipartReader m = req.multipartStream()
            Int32 parts = 0
            while true
            {
                SLang.MultipartPart p = m.nextPart()
                if p == null
                {
                    break
                }
                parts = parts + 1
            }
            Int32 done = 0
            if m.isDone
            {
                done = 1
            }
            res.text( "parts=" + parts.toString() + "|done=" + done.toString() )
        }
        SLang.RouteInfo rEmpty = app.onPost( "/empty", hEmpty )
        rEmpty.streamBody = true

        app.start( 19471 )

        # body1：零 part（"--P7E--" 直接收工）
        string b1 = "--P7E--\r\n"
        string r1 = ServerP7Test.p7Req( 19471, "POST /empty HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Type: multipart/form-data; boundary=P7E\r\nContent-Length: 9\r\nConnection: close\r\n\r\n" + b1 )
        ServerP7Test.check( "T4a zero parts close mark",
            sfFind( r1, "parts=0" ) >= 0 && sfFind( r1, "done=1" ) >= 0 )

        # body2：preamble 容忍（垃圾行先于首分隔符）
        string b2 = "preamble junk\r\n--P7E--\r\n"
        string r2 = ServerP7Test.p7Req( 19471, "POST /empty HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Type: multipart/form-data; boundary=P7E\r\nContent-Length: 24\r\nConnection: close\r\n\r\n" + b2 )
        ServerP7Test.check( "T4b preamble tolerated",
            sfFind( r2, "parts=0" ) >= 0 && sfFind( r2, "done=1" ) >= 0 )

        app.stop()
    }

    # ── T5 混合场景（端口 19472）──

    static void t5Mixed()
    {
        Console.println( "[ServerP7Test] T5 begin (port 19472)" )
        SLang.HttpServer app = SLang.HttpServer( 19472 )
        app.reset()

        # (a) 非流式路由：multipartStream 返 null（内存语义不回归）
        function hPlain = function( SLang.Request req, SLang.Response res )
        {
            SLang.MultipartReader m = req.multipartStream()
            string mp = "notnull"
            if m == null
            {
                mp = "null"
            }
            res.text( "mp=" + mp + "|u=" + req.form( "username" ) )
        }
        app.onPost( "/plain", hPlain )

        # (b) 非 multipart CT 流式路由：multipartStream 返 null，回退裸读
        function hRaw = function( SLang.Request req, SLang.Response res )
        {
            SLang.MultipartReader m = req.multipartStream()
            string mp = "notnull"
            if m == null
            {
                mp = "null"
            }
            SLang.HttpBodyReader rd = req.bodyStream()
            Int32 total = 0
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
            res.text( "mp=" + mp + "|raw=" + total.toString() )
        }
        SLang.RouteInfo rRaw = app.onPost( "/rawnonmp", hRaw )
        rRaw.streamBody = true

        # (c) boundary 缺失：multipartStream 返 null；引擎兜底排干
        function hNb = function( SLang.Request req, SLang.Response res )
        {
            SLang.MultipartReader m = req.multipartStream()
            string mp = "notnull"
            if m == null
            {
                mp = "null"
            }
            res.text( "mp=" + mp )
        }
        SLang.RouteInfo rNb = app.onPost( "/nobound", hNb )
        rNb.streamBody = true

        # probe：keep-alive 健康探针
        function hProbe = function( SLang.Request req, SLang.Response res )
        {
            res.text( "probe-ok" )
        }
        app.onGet( "/probe", hProbe )

        app.start( 19472 )

        # (a) 非流式路由 + 合法 multipart
        ByteBuffer bodyA = ByteBuffer()
        ServerP7Test.mpField( bodyA, "P7D", "username", "dave" )
        ServerP7Test.mpFinish( bodyA, "P7D" )
        Int32 alen = bodyA.readableBytes
        string aStr = bodyA.toString()
        bodyA.release()
        string r1 = ServerP7Test.p7Req( 19472, "POST /plain HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Type: multipart/form-data; boundary=P7D\r\nContent-Length: " + alen.toString() + "\r\nConnection: close\r\n\r\n" + aStr )
        ServerP7Test.check( "T5a non-stream route mp=null + form works",
            sfFind( r1, "mp=null" ) >= 0 && sfFind( r1, "u=dave" ) >= 0 )

        # (b) 非 multipart CT 流式路由回退裸读（200 字节）
        ByteBuffer raw = ByteBuffer( 200 )
        for Int32 i = 0, i < 20, i = i + 1
        {
            raw.writeString( "0123456789" )
        }
        string rawStr = raw.toString()
        raw.release()
        string r2 = ServerP7Test.p7Req( 19472, "POST /rawnonmp HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Type: application/octet-stream\r\nContent-Length: 200\r\nConnection: close\r\n\r\n" + rawStr )
        ServerP7Test.check( "T5b non-multipart CT falls back raw",
            sfFind( r2, "mp=null" ) >= 0 && sfFind( r2, "raw=200" ) >= 0 )

        # (c) boundary 缺失 + 同连接第二请求（引擎兜底排干后 keep-alive）
        P7RawClient c = P7RawClient.connect( 19472 )
        c.send( "POST /nobound HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Type: multipart/form-data\r\nContent-Length: 25\r\n\r\nno-boundary-junk-body-!!!" )
        P7Resp r3 = c.readResp()
        bool nbOk = r3._ok && sfFind( r3._body, "mp=null" ) >= 0
        c.send( "GET /probe HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n" )
        P7Resp r4 = c.readResp()
        bool probeOk = r4._ok && sfFind( r4._body, "probe-ok" ) >= 0
        ServerP7Test.check( "T5c missing boundary -> null, keep-alive survives",
            nbOk && probeOk )
        c.close()

        app.stop()
    }

    # ── T6 非流式 multipart 不回归（端口 19472）──

    static void t6NonStream()
    {
        Console.println( "[ServerP7Test] T6 begin (port 19472)" )
        SLang.HttpServer app = SLang.HttpServer( 19472 )
        app.reset()

        function hMem = function( SLang.Request req, SLang.Response res )
        {
            string u = req.form( "username" )
            SLang.UploadedFile f = req.file( "note" )
            Int32 sz = 0
            if f != null
            {
                sz = f.size
            }
            res.text( "mem:u=" + u + "|sz=" + sz.toString() )
        }
        app.onPost( "/mem", hMem )

        app.start( 19472 )

        ByteBuffer note = ByteBuffer.fromString( "carl-data" )
        ByteBuffer body = ByteBuffer()
        ServerP7Test.mpField( body, "P7M", "username", "carl" )
        ServerP7Test.mpFile( body, "P7M", "note", "note.txt", "text/plain", note )
        ServerP7Test.mpFinish( body, "P7M" )
        note.release()
        Int32 blen = body.readableBytes
        string bodyStr = body.toString()
        body.release()
        string r1 = ServerP7Test.p7Req( 19472, "POST /mem HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Type: multipart/form-data; boundary=P7M\r\nContent-Length: " + blen.toString() + "\r\nConnection: close\r\n\r\n" + bodyStr )
        ServerP7Test.check( "T6 non-stream form/file memory semantics",
            sfFind( r1, "mem:u=carl" ) >= 0 && sfFind( r1, "sz=9" ) >= 0 )

        app.stop()
    }

    # ── T7 半读收尾（端口 19472）──

    static void t7HalfRead()
    {
        Console.println( "[ServerP7Test] T7 begin (port 19472)" )
        SLang.HttpServer app = SLang.HttpServer( 19472 )
        app.reset()

        # (a) multipart 半读：字段全读 + 文件仅读 100 字节即返
        #    （引擎 _drainTail 以 multipart 语义闭环剩余结构）
        function hHalf = function( SLang.Request req, SLang.Response res )
        {
            SLang.MultipartReader m = req.multipartStream()
            string u = ""
            Int32 got = -1
            while true
            {
                SLang.MultipartPart p = m.nextPart()
                if p == null
                {
                    break
                }

                if p.isFile
                {
                    ByteBuffer piece = ByteBuffer( 100 )
                    Int32 n = p.read( piece )
                    got = n
                    piece.release()
                    break
                }
                else
                {
                    ByteBuffer vb = p.readAll()
                    u = vb.toString()
                    vb.release()
                }
            }
            res.text( "half:u=" + u + "|got=" + got.toString() )
        }
        SLang.RouteInfo rHalf = app.onPost( "/half", hHalf )
        rHalf.streamBody = true

        # (b) 裸流半读：octet-stream CL=300 仅读 100（drainer _remain 接力）
        function hRawHalf = function( SLang.Request req, SLang.Response res )
        {
            SLang.HttpBodyReader rd = req.bodyStream()
            ByteBuffer piece = ByteBuffer( 100 )
            Int32 n = rd.read( piece )
            piece.release()
            res.text( "rawhalf:" + n.toString() )
        }
        SLang.RouteInfo rRawHalf = app.onPost( "/rawhalf", hRawHalf )
        rRawHalf.streamBody = true

        function hProbe = function( SLang.Request req, SLang.Response res )
        {
            res.text( "probe-ok" )
        }
        app.onGet( "/probe", hProbe )

        app.start( 19472 )

        # (a) 5000 字节文件 + 字段；同连接 probe
        ByteBuffer fdata = ByteBuffer( 5000 )
        for Int32 i = 0, i < 500, i = i + 1
        {
            fdata.writeString( "0123456789" )
        }
        ByteBuffer body = ByteBuffer()
        ServerP7Test.mpField( body, "P7H", "username", "partial" )
        ServerP7Test.mpFile( body, "P7H", "blob", "h.bin", "application/octet-stream", fdata )
        ServerP7Test.mpFinish( body, "P7H" )
        fdata.release()
        Int32 blen = body.readableBytes
        string bodyStr = body.toString()
        body.release()
        P7RawClient c = P7RawClient.connect( 19472 )
        c.send( "POST /half HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Type: multipart/form-data; boundary=P7H\r\nContent-Length: " + blen.toString() + "\r\n\r\n" + bodyStr )
        P7Resp r1 = c.readResp()
        bool halfOk = r1._ok && sfFind( r1._body, "half:u=partial" ) >= 0 && sfFind( r1._body, "got=100" ) >= 0
        c.send( "GET /probe HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n" )
        P7Resp r2 = c.readResp()
        bool probeA = r2._ok && sfFind( r2._body, "probe-ok" ) >= 0
        ServerP7Test.check( "T7a multipart half-read drained, keep-alive survives",
            halfOk && probeA )

        # (b) 裸流半读；同连接 probe
        ByteBuffer raw = ByteBuffer( 300 )
        for Int32 i = 0, i < 30, i = i + 1
        {
            raw.writeString( "0123456789" )
        }
        string rawStr = raw.toString()
        raw.release()
        P7RawClient c2 = P7RawClient.connect( 19472 )
        c2.send( "POST /rawhalf HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Type: application/octet-stream\r\nContent-Length: 300\r\n\r\n" + rawStr )
        P7Resp r3 = c2.readResp()
        bool rawHalfOk = r3._ok && sfFind( r3._body, "rawhalf:100" ) >= 0
        c2.send( "GET /probe HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n" )
        P7Resp r4 = c2.readResp()
        bool probeB = r4._ok && sfFind( r4._body, "probe-ok" ) >= 0
        ServerP7Test.check( "T7b raw half-read drained, keep-alive survives",
            rawHalfOk && probeB )
        c.close()
        c2.close()

        app.stop()
    }

    # ── raw 请求助手（P5 复制）──

    static string p7Req( Int32 port, string reqText ) throws
    {
        P7RawClient c = P7RawClient.connect( port )
        c.send( reqText )
        P7Resp r = c.readResp()
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
    static Int32 p7Hex( string s )
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

    # ── multipart 构造助手（P15 复制）──

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
# P7Resp / P7RawClient -- 原始 HTTP 测试客户端（ServerP5Test 同款）
# ============================================================================
class P7Resp
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

class P7RawClient
{
    Net.TcpStream c = null
    string rtext = ""

    _init_()
    {
        this.c = null
        this.rtext = ""
    }

    static P7RawClient connect( Int32 port ) throws
    {
        P7RawClient rc = P7RawClient()
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
        Int32 pos = ServerP7Test.sfFind( this.rtext, "\n" )
        while pos < 0
        {
            ByteBuffer b = ByteBuffer( 1024 )
            Int32 n = this.c.read( b )
            if n == 0
            {
                ret null
            }
            this.rtext = this.rtext + b.readString( n )
            pos = ServerP7Test.sfFind( this.rtext, "\n" )
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

    P7Resp readResp() throws
    {
        P7Resp r = P7Resp()
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
        if ServerP7Test.sfFind( head, "Transfer-Encoding: chunked" ) >= 0
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
                    Int32 sz = ServerP7Test.p7Hex( sizeLine )
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
        Int32 cl = ServerP7Test.headInt( head, "Content-Length: " )
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
