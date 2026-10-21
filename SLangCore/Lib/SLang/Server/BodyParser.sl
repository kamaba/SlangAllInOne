import Std;
import Core;

namespace SLang
{
    # ============================================================================
    # SLang/Server/BodyParser.sl — 请求体格式判定与解码（P1 → P1.5）
    # 设计契约：SERVER_DESIGN.md §4.4 / §6.4
    #
    # 范围（P1）：EBodyFormat 判定（json/form/multipart/text/binary/none）+
    #   urlencoded form 解码（_UrlCodec：percent-decode + '+'→空格）。
    # 范围（P1.5）：multipart/form-data 全量解析（RFC 7578）——boundary 提取 /
    #   part 头 / 普通字段并入 form 表（值不解码，直传语义）/ 文件 part →
    #   UploadedFile（内容独立 ByteBuffer，filename 路径穿越安全剥离）。
    # ============================================================================

    # 请求体格式（extends Int32，枚举字段先例：HttpMethod / WsOpCode）
    public enum EBodyFormat extends Int32
    {
        # 无 body（GET/HEAD/长度 0）
        None = 0
        # application/json（含 +json 后缀）
        Json = 1
        # application/x-www-form-urlencoded
        Form = 2
        # multipart/form-data（P1.5 全量解析；P1 仅判定）
        Multipart = 3
        # text/*
        Text = 4
        # 其余（application/octet-stream 等）
        Binary = 5
    }

    # ============================================================================
    # _UrlCodec — 内部 URL 解码工具（percent-decode + '+'→空格；UTF-8 组装）。
    # Uri 无现成解码（SERVER_DESIGN.md §2.3），本类为查询参数与 form 共用解码器。
    # 非法 %HH 序列原样保留（RFC 宽容语义）。
    # ============================================================================
    class _UrlCodec
    {
        static string decode( string s )
        {
            if s == null
            {
                ret ""
            }
            Int32 len = SystemStringLength( s )
            if len == 0
            {
                ret ""
            }
            ByteBuffer b = ByteBuffer( len )
            Int32 i = 0
            while i < len
            {
                Int32 c = SystemStringCharCodeAt( s, i )
                if c == 43
                {
                    # '+' → 空格（form / query 通用约定）
                    b.writeU8( 32 )
                    i = i + 1
                }
                elif c == 37 && i + 2 < len
                {
                    # %HH：需 s[i+1]、s[i+2] 在界内；两位十六进制合法才解码，
                    # 否则原样保留（RFC 宽容语义）
                    Int32 h = _UrlCodec._hexVal( SystemStringCharCodeAt( s, i + 1 ) )
                    Int32 l = _UrlCodec._hexVal( SystemStringCharCodeAt( s, i + 2 ) )
                    if h >= 0 && l >= 0
                    {
                        UInt8 v = SystemConvertUInt8( h * 16 + l )
                        b.writeU8( v )
                        i = i + 3
                    }
                    else
                    {
                        b.writeU8( SystemConvertUInt8( c ) )
                        i = i + 1
                    }
                }
                else
                {
                    b.writeU8( SystemConvertUInt8( c ) )
                    i = i + 1
                }
            }
            string decoded = b.toString()
            b.release()
            ret decoded
        }

        # 十六进制字符 → 0..15；非法返回 -1
        static Int32 _hexVal( Int32 c )
        {
            if c >= 48 && c <= 57
            {
                ret c - 48
            }
            if c >= 65 && c <= 70
            {
                ret c - 55
            }
            if c >= 97 && c <= 102
            {
                ret c - 87
            }
            ret 0 - 1
        }
    }

    # ============================================================================
    # _MultipartBody — multipart 解析结果（内部）。
    # errorCode：0 = OK / 400 = boundary 缺失或格式坏 / 413 = 单文件超 maxFileBytes
    #（协议层语义由引擎按 errorCode 应答 + 优雅断连，SERVER_DESIGN.md §6.11）
    # ============================================================================
    class _MultipartBody
    {
        Int32 _errorCode = 0
        Map<string,string> _fields = null
        List<UploadedFile> _files = null

        override _init_()
        {
            this._errorCode = 0
            this._fields = new()
            this._files = new()
        }
    }

    # ============================================================================
    # BodyParser — 格式判定与 form / multipart 解码（静态工具）
    # ============================================================================
    public class BodyParser
    {
        # Content-Type → EBodyFormat（忽略大小写；参数段 ';' 后剥离后比较）。
        # 无 body（len == 0）且无 Content-Type → None
        static EBodyFormat detect( string contentType, Int32 bodyLen )
        {
            Int32 ctLen = SystemStringLength( contentType )
            if ctLen == 0
            {
                if bodyLen == 0
                {
                    ret EBodyFormat.None
                }
                ret EBodyFormat.Binary
            }
            string mime = BodyParser._mimeOf( contentType )
            Int32 mLen = SystemStringLength( mime )
            if mLen == 0
            {
                ret EBodyFormat.Binary
            }

            if BodyParser._endsWithFold( mime, "json" )
            {
                ret EBodyFormat.Json
            }
            if Net.Uri.eqFold( mime, "application/x-www-form-urlencoded" )
            {
                ret EBodyFormat.Form
            }
            if Net.Uri.eqFold( mime, "multipart/form-data" )
            {
                ret EBodyFormat.Multipart
            }
            if BodyParser._startsWithFold( mime, "text/" )
            {
                ret EBodyFormat.Text
            }
            ret EBodyFormat.Binary
        }

        # multipart/form-data 判定（引擎 body 上限选择用：multipart →
        # maxUploadBytes，其余 maxBodyBytes，SERVER_DESIGN.md §6.4）
        static bool isMultipart( string contentType )
        {
            if contentType == null
            {
                ret false
            }
            string mime = BodyParser._mimeOf( contentType )
            ret Net.Uri.eqFold( mime, "multipart/form-data" )
        }

        # 剥离 Content-Type 参数段（"; boundary=..."）取裸 mime
        static string _mimeOf( string contentType )
        {
            Int32 ctLen = SystemStringLength( contentType )
            Int32 cut = ctLen
            for Int32 i = 0, i < ctLen, i = i + 1
            {
                if SystemStringCharCodeAt( contentType, i ) == 59
                {
                    cut = i
                    break
                }
            }
            ret SystemStringRange( contentType, 0, cut )
        }

        # urlencoded form 解码："a=1&b=hello+world&c=%E4%BD%A0" → Map；
        # 键重复后者覆盖前者（m[k]=v put 语义，Map._getItem_ 头注记）；
        # 无 '=' 的段跳过；值解码经 _UrlCodec（percent + '+'→空格）
        static Map<string,string> parseForm( string text )
        {
            Map<string,string> m = new()
            Int32 len = SystemStringLength( text )
            if len == 0
            {
                ret m
            }
            Int32 segStart = 0
            Int32 i = 0
            # 尾部哨兵：按 '&' 逐段切；最后一段在循环外处理
            while i <= len
            {
                if i == len || SystemStringCharCodeAt( text, i ) == 38
                {
                    Int32 segLen = i - segStart
                    if segLen > 0
                    {
                        string seg = SystemStringRange( text, segStart, i )
                        Int32 eq = -1
                        Int32 sl = SystemStringLength( seg )
                        for Int32 k = 0, k < sl, k = k + 1
                        {
                            if SystemStringCharCodeAt( seg, k ) == 61
                            {
                                eq = k
                                break
                            }
                        }
                        if eq > 0
                        {
                            string key = _UrlCodec.decode( SystemStringRange( seg, 0, eq ) )
                            string val = _UrlCodec.decode( SystemStringRange( seg, eq + 1, sl ) )
                            m[key] = val
                        }
                    }
                    segStart = i + 1
                }
                i = i + 1
            }
            ret m
        }

        # ── 文本辅助（大小写折叠前缀/后缀）──

        static bool _startsWithFold( string s, string prefix )
        {
            Int32 sl = SystemStringLength( s )
            Int32 pl = SystemStringLength( prefix )
            if pl == 0
            {
                ret true
            }
            if sl < pl
            {
                ret false
            }
            for Int32 i = 0, i < pl, i = i + 1
            {
                if Net.Uri.fold( SystemStringCharCodeAt( s, i ) ) != Net.Uri.fold( SystemStringCharCodeAt( prefix, i ) )
                {
                    ret false
                }
            }
            ret true
        }

        static bool _endsWithFold( string s, string suffix )
        {
            Int32 sl = SystemStringLength( s )
            Int32 fl = SystemStringLength( suffix )
            if fl == 0
            {
                ret true
            }
            if sl < fl
            {
                ret false
            }
            Int32 off = sl - fl
            for Int32 i = 0, i < fl, i = i + 1
            {
                if Net.Uri.fold( SystemStringCharCodeAt( s, off + i ) ) != Net.Uri.fold( SystemStringCharCodeAt( suffix, i ) )
                {
                    ret false
                }
            }
            ret true
        }

        # ====================================================================
        # multipart/form-data 解析（RFC 7578，SERVER_DESIGN.md §6.4）
        #
        # 报文形态：
        #   --B\r\n part 头(至空行) \r\n 内容 \r\n--B\r\n ... \r\n--B-- [epilogue]
        # 内容区以 "\r\n--B" 定界（内容不含结尾 CRLF，boundary 不得出现在内容中）；
        # v1 全量驻留内存（总量受引擎 maxUploadBytes 上限约束，流式为 P5）。
        # 对 body 只经 slice 视图消费（不推进源 readerIndex，body 三视图不受影响）。
        # ====================================================================

        # 解析入口。errorCode：0 = OK / 400 = boundary 缺失或格式坏 /
        # 413 = 单文件超 maxFileBytes（内容不驻留，直接中止）
        static _MultipartBody parseMultipart( string contentType, ByteBuffer body, Int32 maxFileBytes )
        {
            _MultipartBody result = _MultipartBody()
            string boundary = BodyParser._extractBoundary( contentType )
            if SystemStringLength( boundary ) == 0
            {
                # boundary 参数缺失（§6.4 第 1 步）
                result._errorCode = 400
                ret result
            }
            if body == null
            {
                ret result
            }
            if body.readableBytes == 0
            {
                ret result
            }
            ByteBuffer work = body.slice()
            string want = "--" + boundary

            # ---- 首分隔符定位（容忍 preamble 行；空表单 "--B--" 直接收工）----
            bool opened = false
            while opened == false
            {
                string line = work.readLine()
                if line == null
                {
                    result._errorCode = 400
                    work.release()
                    ret result
                }
                line = HttpServerCore._stripEol( line )
                if line == want
                {
                    opened = true
                }
                elif line == want + "--"
                {
                    work.release()
                    ret result
                }
            }

            ByteBuffer pat = ByteBuffer.fromString( "\r\n--" + boundary )
            Int32 patLen = pat.readableBytes
            ByteBuffer closeMark = ByteBuffer.fromString( "--" )

            Int32 err = 0
            bool finished = false
            while err == 0 && finished == false
            {
                # ---- part 头（到空行；只关心 Content-Disposition / Content-Type）----
                string disp = null
                string partCt = "application/octet-stream"
                bool headDone = false
                while err == 0 && headDone == false
                {
                    string line = work.readLine()
                    if line == null
                    {
                        err = 400
                    }
                    else
                    {
                        line = HttpServerCore._stripEol( line )
                        Int32 ll = SystemStringLength( line )
                        if ll == 0
                        {
                            headDone = true
                        }
                        else
                        {
                            Int32 ci = -1
                            for Int32 k = 0, k < ll, k = k + 1
                            {
                                if SystemStringCharCodeAt( line, k ) == 58
                                {
                                    ci = k
                                    break
                                }
                            }
                            if ci > 0
                            {
                                Int32 vs = ci + 1
                                while vs < ll && SystemStringCharCodeAt( line, vs ) == 32
                                {
                                    vs = vs + 1
                                }
                                string hname = SystemStringRange( line, 0, ci )
                                string hval = SystemStringRange( line, vs, ll )
                                if Net.Uri.eqFold( hname, "Content-Disposition" )
                                {
                                    disp = hval
                                }
                                elif Net.Uri.eqFold( hname, "Content-Type" )
                                {
                                    partCt = hval
                                }
                            }
                            # 无冒号头行忽略（宽容）
                        }
                    }
                }
                if err != 0
                {
                    break
                }

                # ---- 内容区：到 "\r\n--B" 止 ----
                Int32 idx = work.indexOf( pat )
                if idx < 0
                {
                    # 无收尾分隔符（截断报文）
                    err = 400
                    break
                }
                Int32 contentLen = idx
                string fieldName = ""
                string fileName = null
                if disp != null
                {
                    string dv = disp
                    string nm = BodyParser._dispParam( dv, "name" )
                    if nm != null
                    {
                        fieldName = nm
                    }
                    fileName = BodyParser._dispParam( dv, "filename" )
                }

                if fileName != null && contentLen > maxFileBytes
                {
                    # 单文件超限（§6.4 第 5 步）：不驻留内容直接中止
                    err = 413
                    break
                }

                ByteBuffer content = ByteBuffer( contentLen )
                if contentLen > 0
                {
                    work.readBytes( content, contentLen )
                }
                work.skipBytes( patLen )
                if SystemStringLength( fieldName ) == 0
                {
                    # 无 name 的 part：内容丢弃（宽容）
                    content.release()
                }
                elif fileName != null
                {
                    Int32 seq = result._files.length
                    string safe = BodyParser._safeFilename( fileName, seq )
                    result._files.add( UploadedFile( fieldName, safe, partCt, content ) )
                }
                else
                {
                    # 普通字段：值不解码（multipart 直传语义，§6.4 第 4 步）
                    result._fields[fieldName] = content.toString()
                    content.release()
                }

                # ---- 分隔符后续："--" = 收尾；否则应为一行 CRLF → 下一 part ----
                if work.startsWith( closeMark )
                {
                    finished = true
                }
                else
                {
                    string tail = work.readLine()
                    if tail == null
                    {
                        err = 400
                    }
                    # tail 应为空行（"--B" 后的 \r\n）；非空容忍跳过
                }
            }

            pat.release()
            closeMark.release()
            work.release()
            result._errorCode = err
            ret result
        }

        # Content-Type 参数提取 boundary（忽略大小写；值可带引号；
        # 未找到/空值返回空串 → 调用方按 400 处理）
        static string _extractBoundary( string contentType )
        {
            if contentType == null
            {
                ret ""
            }
            Int32 pos = BodyParser._findFold( contentType, "boundary=" )
            if pos < 0
            {
                ret ""
            }
            Int32 ctLen = SystemStringLength( contentType )
            Int32 vs = pos + 9
            Int32 ve = ctLen
            for Int32 k = vs, k < ctLen, k = k + 1
            {
                if SystemStringCharCodeAt( contentType, k ) == 59
                {
                    ve = k
                    break
                }
            }
            # 去首尾空白
            while vs < ve && ( SystemStringCharCodeAt( contentType, vs ) == 32 || SystemStringCharCodeAt( contentType, vs ) == 9 )
            {
                vs = vs + 1
            }
            while ve > vs && ( SystemStringCharCodeAt( contentType, ve - 1 ) == 32 || SystemStringCharCodeAt( contentType, ve - 1 ) == 9 )
            {
                ve = ve - 1
            }
            # 剥引号（boundary="..."）
            if ve - vs >= 2 && SystemStringCharCodeAt( contentType, vs ) == 34 && SystemStringCharCodeAt( contentType, ve - 1 ) == 34
            {
                vs = vs + 1
                ve = ve - 1
            }
            if ve <= vs
            {
                ret ""
            }
            ret SystemStringRange( contentType, vs, ve )
        }

        # Content-Disposition 参数取值：按 ';' 分段找 key（忽略大小写），
        # 值去空白 + 剥引号；未找到返回 null。
        # 形态：form-data; name="field"; filename="a.txt"
        static string _dispParam( string value, string wantKey )
        {
            Int32 vlen = SystemStringLength( value )
            Int32 i = 0
            while i < vlen
            {
                Int32 segEnd = vlen
                for Int32 k = i, k < vlen, k = k + 1
                {
                    if SystemStringCharCodeAt( value, k ) == 59
                    {
                        segEnd = k
                        break
                    }
                }
                Int32 eq = -1
                for Int32 k = i, k < segEnd, k = k + 1
                {
                    if SystemStringCharCodeAt( value, k ) == 61
                    {
                        eq = k
                        break
                    }
                }
                if eq >= 0
                {
                    # 键 [i, eq) 去空白
                    Int32 ks = i
                    Int32 ke = eq
                    while ks < ke && ( SystemStringCharCodeAt( value, ks ) == 32 || SystemStringCharCodeAt( value, ks ) == 9 )
                    {
                        ks = ks + 1
                    }
                    while ke > ks && ( SystemStringCharCodeAt( value, ke - 1 ) == 32 || SystemStringCharCodeAt( value, ke - 1 ) == 9 )
                    {
                        ke = ke - 1
                    }
                    if ke > ks
                    {
                        string key = SystemStringRange( value, ks, ke )
                        if Net.Uri.eqFold( key, wantKey )
                        {
                            # 值 [eq+1, segEnd) 去空白 + 剥引号
                            Int32 vs = eq + 1
                            Int32 ve = segEnd
                            while vs < ve && ( SystemStringCharCodeAt( value, vs ) == 32 || SystemStringCharCodeAt( value, vs ) == 9 )
                            {
                                vs = vs + 1
                            }
                            while ve > vs && ( SystemStringCharCodeAt( value, ve - 1 ) == 32 || SystemStringCharCodeAt( value, ve - 1 ) == 9 )
                            {
                                ve = ve - 1
                            }
                            if ve - vs >= 2 && SystemStringCharCodeAt( value, vs ) == 34 && SystemStringCharCodeAt( value, ve - 1 ) == 34
                            {
                                vs = vs + 1
                                ve = ve - 1
                            }
                            if ve <= vs
                            {
                                ret ""
                            }
                            ret SystemStringRange( value, vs, ve )
                        }
                    }
                }
                if segEnd >= vlen
                {
                    break
                }
                i = segEnd + 1
            }
            ret null
        }

        # 文件名安全化：按 '/' 与 '\\' 剥离路径段（防 ../ 穿越，只留
        # basename，§6.4 第 6 步）；空名生成 "upload_<序号>"
        static string _safeFilename( string raw, Int32 seq )
        {
            if raw == null
            {
                ret "upload_" + seq.toString()
            }
            Int32 len = SystemStringLength( raw )
            Int32 cut = 0
            for Int32 i = 0, i < len, i = i + 1
            {
                Int32 c = SystemStringCharCodeAt( raw, i )
                if c == 47 || c == 92
                {
                    cut = i + 1
                }
            }
            string name = SystemStringRange( raw, cut, len )
            Int32 nl = SystemStringLength( name )
            Int32 s = 0
            Int32 e = nl
            while s < e && ( SystemStringCharCodeAt( name, s ) == 32 || SystemStringCharCodeAt( name, s ) == 9 )
            {
                s = s + 1
            }
            while e > s && ( SystemStringCharCodeAt( name, e - 1 ) == 32 || SystemStringCharCodeAt( name, e - 1 ) == 9 )
            {
                e = e - 1
            }
            if e <= s
            {
                ret "upload_" + seq.toString()
            }
            ret SystemStringRange( name, s, e )
        }

        # 忽略大小写查找子串（返回首匹配下标；未找到 -1；空 sub 返回 0）
        static Int32 _findFold( string s, string sub )
        {
            Int32 sl = SystemStringLength( s )
            Int32 fl = SystemStringLength( sub )
            if fl == 0
            {
                ret 0
            }
            if fl > sl
            {
                ret -1
            }
            Int32 last = sl - fl
            for Int32 i = 0, i <= last, i = i + 1
            {
                bool match = true
                for Int32 j = 0, j < fl, j = j + 1
                {
                    Int32 a = Net.Uri.fold( SystemStringCharCodeAt( s, i + j ) )
                    Int32 b = Net.Uri.fold( SystemStringCharCodeAt( sub, j ) )
                    if a != b
                    {
                        match = false
                        break
                    }
                }
                if match
                {
                    ret i
                }
            }
            ret -1
        }
    }
}
