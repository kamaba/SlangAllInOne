import Std;
import Core;

namespace SLang
{
    # ============================================================================
    # SLang/Server/StreamIo.sl — 流式写出器与 MIME 表（P2）
    # 设计契约：SERVER_DESIGN.md §4.5 / §6.6 / 附录 B
    #
    # StreamWriter：chunked 流式写出（RFC 9112 §7.1：<hex 长度>\r\n<数据>\r\n
    #   每 write 一块；close() → 0\r\n\r\n 终止块）；HTTP/1.0 降级
    #   close-delimited（裸写不编码块，连接收尾断连，§6.6）；
    #   状态机 Streaming → Closed（Closed 后再写抛 AlreadyResponded）。
    # SseWriter：text/event-stream 线格式（§6.6：event:/data:/注释行）。
    # 背压：底层 TcpStream.write 挂起语义（发送缓冲满协程让出）；
    #   慢客户端超时由 cfg.writeTimeoutMs 守护（引擎连接级 setWriteTimeout）。
    # _Mime：内置 MIME 表（附录 B；扩展名小写化匹配）。
    # ============================================================================

    # ============================================================================
    # _Mime — MIME 类型表（静态工具；staticFiles / res.file / sendFile 共用）
    # ============================================================================
    class _Mime
    {
        # 按路径扩展名取 MIME（扩展名小写化；无扩展/未命中 octet-stream）
        static string of( string path )
        {
            if path == null
            {
                ret "application/octet-stream"
            }
            Int32 len = SystemStringLength( path )
            Int32 dot = -1
            for Int32 i = len - 1, i >= 0, i = i - 1
            {
                if SystemStringCharCodeAt( path, i ) == 46
                {
                    dot = i
                    break
                }
            }
            if dot < 0 || dot == len - 1
            {
                ret "application/octet-stream"
            }
            # String 无 toLowerCase（标准库现状）——逐字节折叠 'A'-'Z'
            ByteBuffer b = ByteBuffer( 8 )
            for Int32 i = dot + 1, i < len, i = i + 1
            {
                Int32 c = SystemStringCharCodeAt( path, i )
                if c >= 65 && c <= 90
                {
                    c = c + 32
                }
                b.writeU8( SystemConvertUInt8( c ) )
            }
            string ext = b.toString()
            b.release()
            ret _Mime.ofExt( ext )
        }

        # 按小写扩展名取 MIME（SERVER_DESIGN.md 附录 B）
        static string ofExt( string ext )
        {
            if ext == "html" || ext == "htm"
            {
                ret "text/html; charset=utf-8"
            }

            if ext == "js"
            {
                ret "application/javascript"
            }

            if ext == "css"
            {
                ret "text/css"
            }

            if ext == "json"
            {
                ret "application/json"
            }

            if ext == "xml"
            {
                ret "text/xml"
            }

            if ext == "txt"
            {
                ret "text/plain; charset=utf-8"
            }

            if ext == "png"
            {
                ret "image/png"
            }

            if ext == "jpg" || ext == "jpeg"
            {
                ret "image/jpeg"
            }

            if ext == "gif"
            {
                ret "image/gif"
            }

            if ext == "webp"
            {
                ret "image/webp"
            }

            if ext == "svg"
            {
                ret "image/svg+xml"
            }

            if ext == "ico"
            {
                ret "image/x-icon"
            }

            if ext == "mp3"
            {
                ret "audio/mpeg"
            }

            if ext == "wav"
            {
                ret "audio/wav"
            }

            if ext == "mp4"
            {
                ret "video/mp4"
            }

            if ext == "webm"
            {
                ret "video/webm"
            }

            if ext == "pdf"
            {
                ret "application/pdf"
            }

            if ext == "zip"
            {
                ret "application/zip"
            }

            if ext == "gz"
            {
                ret "application/gzip"
            }

            if ext == "wasm"
            {
                ret "application/wasm"
            }

            if ext == "woff"
            {
                ret "font/woff"
            }

            if ext == "woff2"
            {
                ret "font/woff2"
            }

            ret "application/octet-stream"
        }
    }

    # ============================================================================
    # StreamWriter — chunked 流式写出器（模块内构造：Response.stream()）
    # 头部由 Response.stream() 先行发出（状态行 + Transfer-Encoding: chunked
    # + 用户头）；本类只管块编码与终止块
    # ============================================================================
    public class StreamWriter
    {
        # 直写通道（引擎绑定的连接）
        Net.TcpStream _conn = null
        # false = HTTP/1.0 close-delimited（裸写，不编码块，§6.6）
        bool _chunked = true
        bool _closed = false

        _init_( Net.TcpStream conn, bool chunked )
        {
            this._conn = conn
            this._chunked = chunked
            this._closed = false
        }

        # 是否已关闭（引擎兜底判定用）
        public get bool isClosed()
        {
            ret this._closed
        }

        # 写一块文本（UTF-8）；空串 no-op（避免 0 长块语义冲突）
        public void write( string text ) throws
        {
            if this._closed
            {
                throw ServerError.AlreadyResponded
            }

            if text == null || SystemStringLength( text ) == 0
            {
                ret
            }
            ByteBuffer b = ByteBuffer.fromString( text )
            this._writeChunk( b )
            b.release()
        }

        # 写一块二进制（视图写出，不推进源索引）；空 no-op
        public void writeBytes( ByteBuffer payload ) throws
        {
            if this._closed
            {
                throw ServerError.AlreadyResponded
            }

            if payload == null || payload.readableBytes == 0
            {
                ret
            }
            this._writeChunk( payload )
        }

        # 空操作——写路径即时下发无用户态缓冲（NetStream.flush 同款语义，
        # 保留 API 习惯，§4.5）
        public void flush()
        {
        }

        # 关闭：0 长终止块（HTTP/1.0 降级 = 无操作）；幂等
        public void close() throws
        {
            if this._closed
            {
                ret
            }
            this._closed = true
            if this._chunked
            {
                ByteBuffer t = ByteBuffer.fromString( "0\r\n\r\n" )
                this._conn.write( t )
                t.release()
            }
        }

        # 块编码写出：<hex>\r\n<数据>\r\n（chunked）/ 裸写（close-delimited）
        void _writeChunk( ByteBuffer payload ) throws
        {
            Int32 len = payload.readableBytes
            if this._chunked
            {
                # Int32.toHexString：小写无前缀（chunk size 行，RFC 允许任意位数）
                ByteBuffer h = ByteBuffer.fromString( len.toHexString() + "\r\n" )
                this._conn.write( h )
                h.release()
                ByteBuffer view = payload.slice()
                this._conn.write( view )
                ByteBuffer t = ByteBuffer.fromString( "\r\n" )
                this._conn.write( t )
                t.release()
            }
            else
            {
                ByteBuffer view = payload.slice()
                this._conn.write( view )
            }
        }

        # 引擎兜底收尾（handler 退出未调 close() 时补终止块；幂等；尽力）
        void _ensureClosed()
        {
            label c
            {
                this.close()
            }
            catch { }
        }
    }

    # ============================================================================
    # SseWriter — Server-Sent Events 写出器（模块内构造：Response.sse()；
    # 线格式 §6.6，CRLF 行界）
    # ============================================================================
    public class SseWriter
    {
        StreamWriter _w = null

        _init_( StreamWriter w )
        {
            this._w = w
        }

        # 默认事件：data: <payload>\r\n\r\n（data 是关键字，参数名用 payload）
        public void send( string payload ) throws
        {
            this._w.write( "data: " + payload + "\r\n\r\n" )
        }

        # 具名事件：event: <event>\r\ndata: <payload>\r\n\r\n
        public void sendEvent( string event, string payload ) throws
        {
            this._w.write( "event: " + event + "\r\ndata: " + payload + "\r\n\r\n" )
        }

        # 心跳注释行：: <text>\r\n\r\n（防中间层掐空闲连接）
        public void comment( string text ) throws
        {
            this._w.write( ":" + text + "\r\n\r\n" )
        }

        # 关闭（透传底层 chunked 终止块）
        public void close() throws
        {
            this._w.close()
        }
    }
}
