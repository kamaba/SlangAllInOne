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
            if path == null || File.exists( path ) == false
            {
                this.status( 404 ).text( "not found" )
                ret
            }
            this._terminal()
            this._direct = true
            Int64 fsize = File.getSize( path )
            this._contentType = _Mime.of( path )
            this._writeFileHead( fsize )
            # 64KB 分块读发（FileStream.read 满 writable 区；clear 复用）
            FileStream fs = File.openRead( path )
            ByteBuffer chunk = ByteBuffer( 65536 )
            while true
            {
                Int32 n = fs.read( chunk )
                if n <= 0
                {
                    break
                }
                ByteBuffer view = chunk.slice()
                this._conn.write( view )
                chunk.clear()
            }
            chunk.release()
            fs.close()
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

        # sendFile 响应头直发（Content-Length 精确；keep-alive 可继续）
        void _writeFileHead( Int64 fsize ) throws
        {
            string head = "HTTP/1.1 " + this._status.toString() + " " + HttpServerCore._reason( this._status ) + "\r\n"
            head = head + "Content-Type: " + this._contentType + "\r\n"
            head = head + "Content-Length: " + fsize.toString() + "\r\n"
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

        # 用户附加头文本（引擎管理头跳过：Content-Type/Length/Connection/
        # Transfer-Encoding；跨类静态调用的实参先拷局部——HttpHeaders 纪律）
        string _userHeadersText()
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
