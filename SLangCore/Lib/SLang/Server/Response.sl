import Std;
import Core;

namespace SLang
{
    # ============================================================================
    # SLang/Server/Response.sl — 响应输出（写侧 API，P1 全表 → P2 流式增补）
    # 设计契约：SERVER_DESIGN.md §4.3 / §4.5 / §6.3 / §6.6
    #
    # 语义：普通终端方法把响应暂存到本对象，handler 协程结束后由引擎统一
    #   编码写出（恒精确 Content-Length）；终端方法第二次调用抛
    #   ServerError.AlreadyResponded（开发期防重复写出）。
    # 链式：status / header / contentType 返回 this（须在终端方法之前调用）。
    # 注意：Content-Type / Content-Length / Connection 三头由引擎管理，
    #   自定义 Content-Type 走 contentType(mime)，经 header() 设置会被跳过。
    # P2 增补（流式，§4.5 / §6.6）：
    #   - stream() / sse()：流式终端——调用即发出状态行+头并锁定响应，返回
    #     写出器（chunked 块编码 / SSE 线格式）；handler 退出未 close() 时
    #     引擎兜底补终止块；HTTP/1.0 降级 close-delimited（连接收尾断连）；
    #   - sendFile( path )：普通终端（内部流式实现：64KB 分块直写，
    #     Content-Length = 文件大小，非 chunked，对用户透明）；
    #   - file( path, downloadName )：sendFile + Content-Disposition 附件头。
    # 直写通道：引擎派发前经 _bind 绑定连接（_conn/_keepAlive/_http10）。
    # ============================================================================
    public class Response
    {
        Int32 _status = 200
        string _contentType = "text/plain; charset=utf-8"
        Net.HttpHeaders _headers = null
        ByteBuffer _body = null
        bool _responded = false
        # ── Set-Cookie 表（P10 补齐 P3 裁剪项，§4.3 / §6.3）──
        # 已序列化的 Set-Cookie 值（"name=value[; attrs]"，逐条独立成头行——
        # Set-Cookie 是 HTTP 唯一必须多行重复的头，不走 HttpHeaders 覆盖语义）
        List<string> _cookies = null
        # ── 流式状态（引擎绑定；P2）──
        # 直写通道（stream/sse/sendFile 用；引擎 _bind 绑定）
        Net.TcpStream _conn = null
        bool _keepAlive = true
        bool _http10 = false
        # chunked 流式开启（stream/sse）：头已直发，引擎不再走缓冲写出
        bool _streaming = false
        StreamWriter _streamWriter = null
        # sendFile 直写完成（Content-Length 精确，keep-alive 可继续）
        bool _direct = false

        override _init_()
        {
            this._headers = Net.HttpHeaders()
            this._cookies = null
            this._conn = null
            this._keepAlive = true
            this._http10 = false
            this._streaming = false
            this._streamWriter = null
            this._direct = false
        }

        # 引擎绑定（派发前；用户勿调）——流式直写通道 + 连接语义
        void _bind( Net.TcpStream client, bool keepAlive, bool http10 )
        {
            this._conn = client
            this._keepAlive = keepAlive
            this._http10 = http10
        }

        # 是否已有终端写出（handler 忘记响应时引擎兜底 500）
        public get bool isResponded()
        {
            ret this._responded
        }

        # 是否处于流式输出（stream/sse 已开启——头已直发；引擎超时豁免与
        # 写出路径判定用，§6.1 / §6.6）
        public get bool isStreaming()
        {
            ret this._streaming
        }

        # ── 链式（终端方法之前调用）──

        # 置状态码
        public Response status( Int32 code )
        {
            this._status = code
            ret this
        }

        # 追加响应头（覆盖同名，大小写不敏感）
        public Response header( string name, string value )
        {
            this._headers.setHeader( name, value )
            ret this
        }

        # 覆盖 Content-Type
        public Response contentType( string mime )
        {
            this._contentType = mime
            ret this
        }

        # ── Set-Cookie（P10 补齐 P3 裁剪项，SERVER_DESIGN.md §4.3 / §6.3）──
        # 非终端：暂存 cookie 行，随终端方法一并写出（三条头写出路径统一
        # 消费 _cookies：缓冲 / 流式头 / sendFile 头——见 _userHeadersText）。
        # 同名多次调用 = 多条独立 Set-Cookie 行（HTTP 语义：Set-Cookie 是
        # 唯一必须逐行重复、不可逗号合并的头）。

        # 简单形态：Set-Cookie: name=value
        public Response setCookie( string name, string value )
        {
            this._addCookie( name + "=" + value )
            ret this
        }

        # 属性形态：path 常用 "/"；maxAge 秒（<= 0 省略 Max-Age）；
        # secure / httpOnly 附加标记；sameSite = "Strict"/"Lax"/"None"
        #（空串省略）。sameSite=None 时按现代浏览器要求自动补 Secure。
        public Response setCookie( string name, string value, string path, Int32 maxAge, bool secure, bool httpOnly, string sameSite )
        {
            string line = name + "=" + value
            if path != null && SystemStringLength( path ) > 0
            {
                line = line + "; Path=" + path
            }

            if maxAge > 0
            {
                line = line + "; Max-Age=" + maxAge.toString()
            }

            if secure
            {
                line = line + "; Secure"
            }

            if httpOnly
            {
                line = line + "; HttpOnly"
            }

            if sameSite != null && SystemStringLength( sameSite ) > 0
            {
                line = line + "; SameSite=" + sameSite
                if Net.Uri.eqFold( sameSite, "None" ) && secure == false
                {
                    # SameSite=None 无 Secure 被现代浏览器拒收（RFC 6265bis）
                    line = line + "; Secure"
                }
            }
            this._addCookie( line )
            ret this
        }

        # 清空已暂存 cookie（改主意场景；幂等）
        public Response clearCookies()
        {
            this._cookies = null
            ret this
        }

        void _addCookie( string line )
        {
            if this._cookies == null
            {
                this._cookies = new()
            }
            this._cookies.add( line )
        }

        # ── 终端方法（二次调用抛 ServerError.AlreadyResponded）──

        # 文本响应（text/plain）
        public void text( string s )
        {
            this._terminal()
            this._contentType = "text/plain; charset=utf-8"
            this._body = ByteBuffer.fromString( s )
        }

        # HTML 响应（text/html）
        public void html( string s )
        {
            this._terminal()
            this._contentType = "text/html; charset=utf-8"
            this._body = ByteBuffer.fromString( s )
        }

        # 任意对象 → JSON（BaseJson.fromData；null → "null"）
        public void json( object obj )
        {
            this._terminal()
            this._contentType = "application/json; charset=utf-8"
            string text = "null"
            if obj != null
            {
                BaseJson j = BaseJson.fromData( obj )
                string s = j.toJson()
                if SystemStringLength( s ) > 0
                {
                    text = s
                }
            }
            this._body = ByteBuffer.fromString( text )
        }

        # 预构建 JSON 串直写（application/json；openapi.json 等内部使用）
        public void rawJson( string jsonText )
        {
            this._terminal()
            this._contentType = "application/json; charset=utf-8"
            this._body = ByteBuffer.fromString( jsonText )
        }

        # 统一成功封装 = json( ApiResult.ok( payload ) )
        #（输出 {"code":0,"message":"ok","data":...}；payload null → data:null）
        public void jsonOk( object payload )
        {
            this._terminal()
            this._contentType = "application/json; charset=utf-8"
            this._body = ByteBuffer.fromString( ApiResult.ok( payload ).toJson() )
        }

        # 统一失败封装（HTTP 仍 200：业务码与 HTTP 码分离）
        public void jsonFail( Int32 code, string message )
        {
            this._terminal()
            this._contentType = "application/json; charset=utf-8"
            this._body = ByteBuffer.fromString( ApiResult.fail( code, message ).toJson() )
        }

        # 三参重载：同时改 HTTP 状态码
        public void jsonFail( Int32 code, string message, Int32 httpStatus )
        {
            this._terminal()
            this._status = httpStatus
            this._contentType = "application/json; charset=utf-8"
            this._body = ByteBuffer.fromString( ApiResult.fail( code, message ).toJson() )
        }

        # 二进制响应（application/octet-stream；缓冲归属本响应，写出后引擎回收）
        public void bytes( ByteBuffer buf )
        {
            this._terminal()
            this._contentType = "application/octet-stream"
            this._body = buf
        }

        # 重定向（302 + Location；空 body）
        public void redirect( string url )
        {
            this._terminal()
            this._status = 302
            this._contentType = "text/plain; charset=utf-8"
            this._headers.setHeader( "Location", url )
            this._body = null
        }

        # ── 流式终端（P2，§4.5 / §6.6）──

        # chunked 流式响应：即刻发出状态行 + 头（Transfer-Encoding: chunked），
        # 返回写出器（write/writeBytes/flush/close）；HTTP/1.0 降级
        # close-delimited（裸写，连接收尾断连）。头部设置（status/contentType/
        # header 链式）须在本调用之前完成
        public StreamWriter stream() throws
        {
            this._terminal()
            this._streaming = true
            this._writeStreamHead()
            this._streamWriter = StreamWriter( this._conn, this._http10 == false )
            ret this._streamWriter
        }

        # SSE 流式响应（text/event-stream + Cache-Control: no-cache 自动置）
        public SseWriter sse() throws
        {
            this._terminal()
            this._streaming = true
            this._contentType = "text/event-stream; charset=utf-8"
            this._headers.setHeader( "Cache-Control", "no-cache" )
            this._writeStreamHead()
            this._streamWriter = StreamWriter( this._conn, this._http10 == false )
            ret SseWriter( this._streamWriter )
        }

        # 流式文件下载（大文件 64KB 分块读发不整载内存；Content-Length =
        # 文件大小，非 chunked；MIME 按扩展名）。文件不存在 → 404 终端
        public void sendFile( string path ) throws
        {
            this.sendFileRange( path, null )
        }

        # 流式文件下载 + Range 断点续传（P5，§4.5）：
        #   rangeSpec = 请求 Range 头原值（如 "bytes=100-199" / "bytes=100-" /
        #   "bytes=-100"）；null / 畸形 / 多 range → 忽略按全量 200（RFC 9110
        #   允许服务器忽略 Range；v1 只取首个 range，多 range 不做合成分块）；
        #   start 越界（>= 文件大小）→ 416 + Content-Range: bytes */size。
        #   有效 → 206 + Content-Range: bytes s-e/size + Content-Length = 区间长。
        public void sendFileRange( string path, string rangeSpec ) throws
        {
            if path == null || File.exists( path ) == false
            {
                this.status( 404 ).text( "not found" )
                ret
            }
            this._terminal()
            this._direct = true
            Int64 fsize = File.getSize( path )
            Int64 start = 0
            Int64 len = fsize
            bool isRange = false
            if rangeSpec != null && SystemStringLength( rangeSpec ) > 6
            {
                if HttpServerCore._startsWithFold( SystemStringRange( rangeSpec, 0, 6 ), "bytes=" )
                {
                    Int32 rc = Response._parseRange( SystemStringRange( rangeSpec, 6, SystemStringLength( rangeSpec ) ), fsize )
                    if rc == 1
                    {
                        # 416：区间不可满足（start >= size）
                        this._status = 416
                        this._contentType = "text/plain; charset=utf-8"
                        this._headers.setHeader( "Content-Range", "bytes */" + fsize.toString() )
                        this._writeRangeHead( fsize, 0, 0 )
                        ret
                    }

                    if rc == 0
                    {
                        # 有效区间
                        start = Response._rangeStart
                        len = Response._rangeEnd - start + 1
                        isRange = true
                    }
                    # rc == -1：畸形 → 忽略（全量 200）
                }
            }
            this._contentType = _Mime.of( path )
            if isRange
            {
                this._status = 206
                this._headers.setHeader( "Content-Range", "bytes " + start.toString() + "-" + ( start + len - 1 ).toString() + "/" + fsize.toString() )
                this._writeRangeHead( fsize, start, len )
            }
            else
            {
                this._writeRangeHead( fsize, start, len )
            }
            # 64KB 分块读发（FileStream.read 满 writable 区；clear 复用）
            FileStream fs = File.openRead( path )
            if start > 0
            {
                fs.seek( start, SeekOrigin.Begin )
            }
            Int64 remain = len
            ByteBuffer chunk = ByteBuffer( 65536 )
            while remain > 0
            {
                Int32 n = fs.read( chunk )
                if n <= 0
                {
                    break
                }
                Int32 take = n
                if remain - n < 0
                {
                    take = remain.toInt32()
                }
                # clear 后 readerIndex=0：新数据落在 [0, n)，截取 [0, take)
                ByteBuffer view = chunk.slice( 0, take )
                this._conn.write( view )
                view.release()
                chunk.clear()
                remain = remain - take
            }
            chunk.release()
            fs.close()
        }

        # 区间解析结果槽（_parseRange 输出；模块级静态——跨方法带出双值，
        # _SrvUtil 同款纪律，无并发共享语义：单 VM 协程非抢占 + 调用点立即消费）
        static Int64 _rangeStart = 0
        static Int64 _rangeEnd = 0

        # Range 值解析（"bytes=" 之后的部分）：
        #   返回 0 = 有效（_rangeStart/_rangeEnd 已置）
        #   返回 1 = 416（区间不可满足：start >= size）
        #   返回 -1 = 畸形忽略（按全量 200）
        # v1 只取首个 range（逗号分隔截断）；"a-b" 越界 end 钳到 size-1
        static Int32 _parseRange( string spec, Int64 fsize )
        {
            # 截首段（多 range 丢弃后续）
            Int32 len = SystemStringLength( spec )
            Int32 end = len
            for Int32 i = 0, i < len, i = i + 1
            {
                if SystemStringCharCodeAt( spec, i ) == 44
                {
                    end = i
                    break
                }
            }
            string one = SystemStringRange( spec, 0, end )
            Int32 ol = SystemStringLength( one )
            if ol == 0
            {
                ret -1
            }
            # 找 '-'
            Int32 dash = -1
            for Int32 i = 0, i < ol, i = i + 1
            {
                if SystemStringCharCodeAt( one, i ) == 45
                {
                    dash = i
                    break
                }
            }
            if dash < 0
            {
                ret -1
            }
            string s1 = SystemStringRange( one, 0, dash )
            string s2 = SystemStringRange( one, dash + 1, ol )
            Int32 l1 = SystemStringLength( s1 )
            Int32 l2 = SystemStringLength( s2 )
            if l1 == 0 && l2 == 0
            {
                ret -1
            }

            if l1 > 0
            {
                # "a-b" / "a-"
                Int64 a = HttpServerCore._parseDec64Full( s1 )
                if a < 0
                {
                    ret -1
                }

                if a >= fsize
                {
                    ret 1
                }
                Int64 b = fsize - 1
                if l2 > 0
                {
                    Int64 bv = HttpServerCore._parseDec64Full( s2 )
                    if bv < 0
                    {
                        ret -1
                    }

                    if bv < a
                    {
                        # start > end：畸形（RFC 9110 an unsatisfied... 按 416 处理）
                        ret 1
                    }

                    if bv < b
                    {
                        b = bv
                    }
                }
                Response._rangeStart = a
                Response._rangeEnd = b
                ret 0
            }
            # "-n" 尾部 n 字节
            Int64 n = HttpServerCore._parseDec64Full( s2 )
            if n <= 0
            {
                # suffix-length 0 / 非法：忽略
                ret -1
            }

            if n > fsize
            {
                n = fsize
            }
            Response._rangeStart = fsize - n
            Response._rangeEnd = fsize - 1
            ret 0
        }

        # 文件下载响应头直发（sendFile/sendFileRange 共用；Content-Length =
        # len（区间或全量），Accept-Ranges 声明支持断点续传；keep-alive 可继续）
        void _writeRangeHead( Int64 fsize, Int64 start, Int64 len ) throws
        {
            string head = "HTTP/1.1 " + this._status.toString() + " " + HttpServerCore._reason( this._status ) + "\r\n"
            head = head + "Content-Type: " + this._contentType + "\r\n"
            head = head + "Content-Length: " + len.toString() + "\r\n"
            head = head + "Accept-Ranges: bytes\r\n"
            if this._keepAlive && this._http10 == false
            {
                head = head + "Connection: keep-alive\r\n"
            }
            else
            {
                head = head + "Connection: close\r\n"
            }
            head = head + this._userHeadersText()
            head = head + "\r\n"
            ByteBuffer b = ByteBuffer.fromString( head )
            this._conn.write( b )
            b.release()
        }

        # 文件下载（sendFile + Content-Disposition 附件头）
        public void file( string path, string downloadName ) throws
        {
            this._headers.setHeader( "Content-Disposition", "attachment; filename=\"" + downloadName + "\"" )
            this.sendFile( path )
        }

        # 流式响应头直发（状态行 + chunked/Connection + 用户头；引擎管理头
        # 跳过；Transfer-Encoding 同引擎管理）
        void _writeStreamHead() throws
        {
            string head = "HTTP/1.1 " + this._status.toString() + " " + HttpServerCore._reason( this._status ) + "\r\n"
            head = head + "Content-Type: " + this._contentType + "\r\n"
            if this._http10
            {
                # HTTP/1.0 不支持 chunked → close-delimited（无长度声明，
                # 发完断连）
                head = head + "Connection: close\r\n"
            }
            else
            {
                head = head + "Transfer-Encoding: chunked\r\n"
                if this._keepAlive
                {
                    head = head + "Connection: keep-alive\r\n"
                }
                else
                {
                    head = head + "Connection: close\r\n"
                }
            }
            head = head + this._userHeadersText()
            head = head + "\r\n"
            ByteBuffer b = ByteBuffer.fromString( head )
            this._conn.write( b )
            b.release()
        }

        # 用户附加头文本（引擎管理头跳过：Content-Type/Length/Connection/
        # Transfer-Encoding；跨类静态调用的实参先拷局部——HttpHeaders 纪律）。
        # Set-Cookie 不经 HttpHeaders（多行重复语义）：逐条独立成行，P10
        public string _userHeadersText()
        {
            string outText = ""
            Net.HttpHeaders hs = this._headers
            Int32 n = hs.count
            for Int32 i = 0, i < n, i = i + 1
            {
                string hn = hs.nameAt( i )
                if Net.Uri.eqFold( hn, "Content-Type" ) || Net.Uri.eqFold( hn, "Content-Length" ) || Net.Uri.eqFold( hn, "Connection" ) || Net.Uri.eqFold( hn, "Transfer-Encoding" )
                {
                    continue
                }
                string hv = hs.valueAt( i )
                outText = outText + hn + ": " + hv + "\r\n"
            }
            List<string> cookies = this._cookies
            if cookies != null
            {
                Int32 cn = cookies.length
                for Int32 i = 0, i < cn, i = i + 1
                {
                    outText = outText + "Set-Cookie: " + cookies[i] + "\r\n"
                }
            }
            ret outText
        }

        # 终端守卫
        void _terminal() throws
        {
            if this._responded
            {
                throw ServerError.AlreadyResponded
            }
            this._responded = true
        }
    }
}
