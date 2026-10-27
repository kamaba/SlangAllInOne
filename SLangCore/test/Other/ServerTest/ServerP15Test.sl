import Std;
import Core;
import SLangServer;

# ============================================================================
# ServerP15Test.sl -- SLangServer P1.5 上传验收（ServerTest 宿主）
# 设计契约：SERVER_DESIGN.md §8 P1.5 验收（§4.4 文件上传全部示例可运行）
#
#   T1  multipart 混合（文件 + 普通字段）：bodyFormat 判定 / form 族并入
#       （form/formInt/formBool/formKeys）/ file() 元数据（filename/
#       contentType/size/ext）/ bytes() 二进制内容往返（hex 对照，含
#       NUL + 高位字节 + 内嵌 CRLF 的内容不截断）
#   T2  多文件同字段：files(field).length / fileCount / file() 首个命中 /
#       跨字段（photos×2 + cover×1）计数
#       （⚠ 检索侧 List<SLang.UploadedFile> 类型变量在 Front 闭包内
#        模板实例化 NRE——typealias/点分类型均触发；链式 .length 访问
#        正常，逐元素访问暂以字段区分替代，Front 修复后补强）
#   T3  路径穿越攻击：filename "../../evil.txt" / "..\..\evil2.txt" →
#       剥离为 basename；空 filename → "upload_0"
#   T4  落盘：saveAs 完整路径 / saveInto 目录 + 重名自动改名
#       dup.txt → dup(1).txt（两字段同名文件先后 saveInto），内容读回对照
#   T5  单文件超限：maxFileBytes=16，32 字节文件 → 413（协议层断连）
#   T6  multipart 总量超限：maxUploadBytes=96，~180 字节 body → 413（CL 检查）
#   T7  boundary 缺失：Content-Type 无 boundary 参数 → 400
#
# 端口：19411（默认配置）/ 19412（maxFileBytes=16）/ 19413（maxUploadBytes=96）
#（避开 ServerP1Test 19401-19408 与 NetTest 19371-19374）。
# 编写约定同 ServerP1Test.sl：原始 HTTP 客户端 + 手搓 multipart 构造
#（HttpClient body 为纯 string 不支持二进制，multipart 必须原始 TCP 手搓）。
# ============================================================================

ServerP15Test
{
    static check( string name, bool cond )
    {
        if cond
        {
            Console.println( "[ServerP15Test] " + name + " : OK" )
        }
        else
        {
            Console.println( "[ServerP15Test] " + name + " : FAIL" )
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
                Int32 he = ServerP15Test.sfFind( text, "\r\n\r\n" )
                if he >= 0
                {
                    headerEnd = he + 4
                }
            }
            if headerEnd >= 0
            {
                if headOnly
                {
                    done = true
                }
                elif ServerP15Test.respBodyDone( text, headerEnd )
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
        Int32 pos = ServerP15Test.sfFind( text, pat )
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

    # 单连接单请求（纯文本请求；boundary 缺失 400 用）
    static string rawReq( Int32 port, string reqText ) throws
    {
        Net.TcpStream c = Net.Tcp.connect( "127.0.0.1", port )
        Net.NetStream ns = c
        c.write( ByteBuffer.fromString( reqText ) )
        string r = ServerP15Test.sfReadResp( ns, false )
        c.close()
        ret r
    }

    # ── multipart 构造助手（RFC 7578 形态）──

    # 普通字段 part
    static void mpField( ByteBuffer body, string boundary, string name, string value )
    {
        body.writeString( "--" + boundary + "\r\n" )
        body.writeString( "Content-Disposition: form-data; name=\"" + name + "\"\r\n\r\n" )
        body.writeString( value )
        body.writeString( "\r\n" )
    }

    # 文件 part（content 字节直入；ctype 空 = 省略 Content-Type 头）
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

    # 收尾分隔符
    static void mpFinish( ByteBuffer body, string boundary )
    {
        body.writeString( "--" + boundary + "--\r\n" )
    }

    # 发送 multipart POST 并读回完整响应（Connection: close）
    static string mpPost( Int32 port, string path, string boundary, ByteBuffer body ) throws
    {
        Int32 blen = body.readableBytes
        string head = "POST " + path + " HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Type: multipart/form-data; boundary=" + boundary + "\r\nContent-Length: " + blen.toString() + "\r\nConnection: close\r\n\r\n"
        ByteBuffer req = ByteBuffer.fromString( head )
        req.writeBytes( body )
        Net.TcpStream c = Net.Tcp.connect( "127.0.0.1", port )
        Net.NetStream ns = c
        c.write( req )
        req.release()
        string r = ServerP15Test.sfReadResp( ns, false )
        c.close()
        ret r
    }

    # ── T1-T4 + T7：默认配置服务（19411）──

    static void t1Main()
    {
        Console.println( "[ServerP15Test] T1-T4/T7 begin (port 19411)" )
        # 落盘目录准备（显式优于隐式：框架不自动建目录，测试自建）
        if IO.Directory.exists( "p15_up" ) == false
        {
            IO.Directory.createDirectory( "p15_up" )
        }
        # 清残留（上次运行可能遗留）
        File.delete( "p15_up/saveAs.txt" )
        File.delete( "p15_up/dup.txt" )
        File.delete( "p15_up/dup(1).txt" )

        SLang.HttpServer app = SLang.HttpServer( 19411 )
        app.reset()

        # /up：混合字段 + 文件（T1）
        function hUp = function( SLang.Request req, SLang.Response res )
        {
            string fmt = "unk"
            if req.bodyFormat == SLang.EBodyFormat.Multipart
            {
                fmt = "mp"
            }
            string u = req.form( "username" )
            string fpart = "f0"
            if req.formBool( "flag", false )
            {
                fpart = "f1"
            }
            SLang.UploadedFile f = req.file( "avatar" )
            if f == null
            {
                res.text( fmt + "|u=" + u + "|" + fpart + "|nofile" )
                ret
            }
            ByteBuffer b = f.bytes()
            string hex = b.toHex()
            res.text( fmt + "|u=" + u + "|" + fpart + "|ai=" + req.formInt( "age", -1 ).toString()
                + "|kn=" + req.formKeys().length.toString()
                + "|fn=" + f.filename + "|ct=" + f.contentType + "|sz=" + f.size.toString()
                + "|ext=" + f.ext() + "|hex=" + hex )
        }
        app.onPost( "/up", hUp )

        # /trav：路径穿越（T3）
        function hTrav = function( SLang.Request req, SLang.Response res )
        {
            SLang.UploadedFile f1 = req.file( "evil1" )
            SLang.UploadedFile f2 = req.file( "evil2" )
            SLang.UploadedFile f3 = req.file( "evil3" )
            string n1 = "null1"
            if f1 != null
            {
                n1 = f1.filename
            }
            string n2 = "null2"
            if f2 != null
            {
                n2 = f2.filename
            }
            string n3 = "null3"
            if f3 != null
            {
                n3 = f3.filename
            }
            Int32 cnt = req.fileCount
            res.text( "n1=" + n1 + "|n2=" + n2 + "|n3=" + n3 + "|cnt=" + cnt.toString() )
        }
        app.onPost( "/trav", hTrav )

        # /multi：多文件同字段（T2；链式 .length——List<SLang.UploadedFile>
        # 类型变量在闭包内模板实例化 NRE，见文件头注记）
        function hMulti = function( SLang.Request req, SLang.Response res )
        {
            Int32 pn = req.files( "photos" ).length
            SLang.UploadedFile first = req.file( "photos" )
            SLang.UploadedFile cov = req.file( "cover" )
            Int32 cnt = req.fileCount
            string cf = "null"
            if first != null
            {
                cf = first.filename
            }
            string cc = "null"
            if cov != null
            {
                cc = cov.filename
            }
            res.text( "pn=" + pn.toString() + "|cnt=" + cnt.toString()
                + "|first=" + cf + "|cover=" + cc )
        }
        app.onPost( "/multi", hMulti )

        # /save：saveAs / saveInto + 重名自动改名（T4；两字段同名文件——
        # 第二个 saveInto 应自动改名 dup(1).txt）
        function hSave = function( SLang.Request req, SLang.Response res )
        {
            SLang.UploadedFile solo = req.file( "solo" )
            bool ok1 = false
            if solo != null
            {
                ok1 = solo.saveAs( "p15_up/saveAs.txt" )
            }
            SLang.UploadedFile d1 = req.file( "dupA" )
            SLang.UploadedFile d2 = req.file( "dupB" )
            bool ok2 = false
            bool ok3 = false
            if d1 != null
            {
                ok2 = d1.saveInto( "p15_up" )
            }
            if d2 != null
            {
                ok3 = d2.saveInto( "p15_up" )
            }
            res.text( "ok1=" + ok1.toString() + "|ok2=" + ok2.toString() + "|ok3=" + ok3.toString() )
        }
        app.onPost( "/save", hSave )

        app.start( 19411 )

        # ---- T1 混合（文件 + 普通字段 + form 族 + 内容往返）----
        string bnd = "P15BOUNDARY"
        ByteBuffer body1 = ByteBuffer( 256 )
        ServerP15Test.mpField( body1, bnd, "username", "tom lee" )
        ByteBuffer content = ByteBuffer( 16 )
        content.writeU8( SystemConvertUInt8( 0 ) )
        content.writeU8( SystemConvertUInt8( 1 ) )
        content.writeString( "hi\r\nthere" )
        content.writeU8( SystemConvertUInt8( 251 ) )
        string expectedHex = content.toHex()
        ServerP15Test.mpFile( body1, bnd, "avatar", "photo.png", "image/png", content )
        ServerP15Test.mpField( body1, bnd, "age", "30" )
        ServerP15Test.mpField( body1, bnd, "flag", "on" )
        ServerP15Test.mpFinish( body1, bnd )
        string r1 = ServerP15Test.mpPost( 19411, "/up", bnd, body1 )
        body1.release()
        content.release()
        ServerP15Test.check( "T1 mixed meta + form family",
            sfFind( r1, "mp|u=tom lee" ) >= 0 && sfFind( r1, "|f1|" ) >= 0
            && sfFind( r1, "ai=30" ) >= 0 && sfFind( r1, "kn=3" ) >= 0
            && sfFind( r1, "fn=photo.png" ) >= 0 && sfFind( r1, "ct=image/png" ) >= 0
            && sfFind( r1, "sz=12" ) >= 0 && sfFind( r1, "ext=png" ) >= 0 )
        ServerP15Test.check( "T1 binary content hex roundtrip",
            sfFind( r1, "|hex=" + expectedHex ) >= 0 )

        # ---- T2 多文件同字段 ----
        ByteBuffer body2 = ByteBuffer( 256 )
        ByteBuffer ca = ByteBuffer( 8 )
        ca.writeString( "AAA" )
        ByteBuffer cb = ByteBuffer( 8 )
        cb.writeString( "BBBBB" )
        ByteBuffer cc = ByteBuffer( 8 )
        cc.writeString( "CCCC" )
        ServerP15Test.mpFile( body2, bnd, "photos", "a.png", "image/png", ca )
        ServerP15Test.mpFile( body2, bnd, "photos", "b.png", "image/png", cb )
        ServerP15Test.mpFile( body2, bnd, "cover", "c.bin", "application/octet-stream", cc )
        ServerP15Test.mpFinish( body2, bnd )
        string r2 = ServerP15Test.mpPost( 19411, "/multi", bnd, body2 )
        body2.release()
        ca.release()
        cb.release()
        cc.release()
        ServerP15Test.check( "T2 multi-file same field",
            sfFind( r2, "pn=2" ) >= 0 && sfFind( r2, "cnt=3" ) >= 0
            && sfFind( r2, "first=a.png" ) >= 0 && sfFind( r2, "cover=c.bin" ) >= 0 )

        # ---- T3 路径穿越 + 空名 ----
        ByteBuffer body3 = ByteBuffer( 256 )
        ByteBuffer e1 = ByteBuffer( 8 )
        e1.writeString( "E1" )
        ByteBuffer e2 = ByteBuffer( 8 )
        e2.writeString( "E2" )
        ByteBuffer e3 = ByteBuffer( 8 )
        e3.writeString( "E3" )
        ServerP15Test.mpFile( body3, bnd, "evil1", "../../evil.txt", "text/plain", e1 )
        ServerP15Test.mpFile( body3, bnd, "evil2", "..\\..\\evil2.txt", "text/plain", e2 )
        ServerP15Test.mpFile( body3, bnd, "evil3", "", "text/plain", e3 )
        ServerP15Test.mpFinish( body3, bnd )
        string r3 = ServerP15Test.mpPost( 19411, "/trav", bnd, body3 )
        body3.release()
        e1.release()
        e2.release()
        e3.release()
        ServerP15Test.check( "T3 traversal stripped + empty name",
            sfFind( r3, "n1=evil.txt" ) >= 0 && sfFind( r3, "n2=evil2.txt" ) >= 0
            && sfFind( r3, "n3=upload_2" ) >= 0 && sfFind( r3, "cnt=3" ) >= 0 )

        # ---- T4 落盘（saveAs / saveInto + 重名自动改名）----
        # dupA/dupB 两字段同 filename "dup.txt"：第一个 saveInto 落 dup.txt，
        # 第二个自动改名 dup(1).txt
        ByteBuffer body4 = ByteBuffer( 256 )
        ByteBuffer s1 = ByteBuffer( 8 )
        s1.writeString( "EEE" )
        ByteBuffer d1b = ByteBuffer( 8 )
        d1b.writeString( "CCC" )
        ByteBuffer d2b = ByteBuffer( 8 )
        d2b.writeString( "DDD" )
        ServerP15Test.mpFile( body4, bnd, "solo", "solo.txt", "text/plain", s1 )
        ServerP15Test.mpFile( body4, bnd, "dupA", "dup.txt", "text/plain", d1b )
        ServerP15Test.mpFile( body4, bnd, "dupB", "dup.txt", "text/plain", d2b )
        ServerP15Test.mpFinish( body4, bnd )
        string r4 = ServerP15Test.mpPost( 19411, "/save", bnd, body4 )
        body4.release()
        s1.release()
        d1b.release()
        d2b.release()
        # 注意：SL bool.toString() 输出 "True/False"（C# 风格大写开头）
        bool saveRespOk = sfFind( r4, "ok1=True" ) >= 0 && sfFind( r4, "ok2=True" ) >= 0 && sfFind( r4, "ok3=True" ) >= 0
        string tSaveAs = File.readAllText( "p15_up/saveAs.txt" )
        string tDup = File.readAllText( "p15_up/dup.txt" )
        string tDup1 = File.readAllText( "p15_up/dup(1).txt" )
        ServerP15Test.check( "T4 saveAs/saveInto + auto rename",
            saveRespOk && tSaveAs == "EEE" && tDup == "CCC" && tDup1 == "DDD" )

        # ---- T7 boundary 缺失 → 400 ----
        string r7 = ServerP15Test.rawReq( 19411, "POST /up HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Type: multipart/form-data\r\nContent-Length: 5\r\nConnection: close\r\n\r\nhello" )
        ServerP15Test.check( "T7 missing boundary -> 400", sfFind( r7, "400" ) >= 0 )

        app.stop()
    }

    # ── T5 单文件超限（19412，maxFileBytes=16）──

    static void t5FileLimit()
    {
        Console.println( "[ServerP15Test] T5 begin (port 19412)" )
        SLang.HttpServer app = SLang.HttpServer( 19412 )
        SLang.ServerConfig cfg = app.config
        cfg.maxFileBytes = 16
        app.reset()
        function hUp = function( SLang.Request req, SLang.Response res )
        {
            res.text( "should-not-reach" )
        }
        app.onPost( "/up", hUp )
        app.start( 19412 )

        string bnd = "P15B12"
        ByteBuffer body = ByteBuffer( 256 )
        ByteBuffer big = ByteBuffer( 32 )
        for Int32 i = 0, i < 32, i = i + 1
        {
            big.writeU8( SystemConvertUInt8( 65 + ( i & 15 ) ) )
        }
        ServerP15Test.mpField( body, bnd, "note", "x" )
        ServerP15Test.mpFile( body, bnd, "big", "big.bin", "application/octet-stream", big )
        ServerP15Test.mpFinish( body, bnd )
        string r = ServerP15Test.mpPost( 19412, "/up", bnd, body )
        body.release()
        big.release()
        ServerP15Test.check( "T5 single file over maxFileBytes -> 413",
            sfFind( r, "413" ) >= 0 && sfFind( r, "should-not-reach" ) < 0 )

        app.stop()
    }

    # ── T6 multipart 总量超限（19413，maxUploadBytes=96）──

    static void t6TotalLimit()
    {
        Console.println( "[ServerP15Test] T6 begin (port 19413)" )
        SLang.HttpServer app = SLang.HttpServer( 19413 )
        SLang.ServerConfig cfg = app.config
        cfg.maxUploadBytes = 96
        app.reset()
        function hUp = function( SLang.Request req, SLang.Response res )
        {
            res.text( "should-not-reach" )
        }
        app.onPost( "/up", hUp )
        app.start( 19413 )

        # 三字段 body ~180 字节 > 96（Content-Length 检查即拦截）
        string bnd = "P15B13"
        ByteBuffer body = ByteBuffer( 256 )
        ServerP15Test.mpField( body, bnd, "a", "1" )
        ServerP15Test.mpField( body, bnd, "b", "2" )
        ServerP15Test.mpField( body, bnd, "c", "3" )
        ServerP15Test.mpFinish( body, bnd )
        Int32 bodyLen = body.readableBytes
        string r = ServerP15Test.mpPost( 19413, "/up", bnd, body )
        body.release()
        ServerP15Test.check( "T6 multipart body over maxUploadBytes -> 413",
            bodyLen > 96 && sfFind( r, "413" ) >= 0 && sfFind( r, "should-not-reach" ) < 0 )

        app.stop()
    }

    # 尽力清理（残留不影响下次运行：开场会重删）
    static void cleanup()
    {
        File.delete( "p15_up/saveAs.txt" )
        File.delete( "p15_up/dup.txt" )
        File.delete( "p15_up/dup(1).txt" )
        IO.Directory.delete( "p15_up" )
    }

    static fun()
    {
        ServerP15Test.t1Main()
        ServerP15Test.t5FileLimit()
        ServerP15Test.t6TotalLimit()
        ServerP15Test.cleanup()
        Console.println( "[ServerP15Test] all done" )
    }
}
