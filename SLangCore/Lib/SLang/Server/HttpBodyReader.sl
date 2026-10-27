import Std;
import Core;

namespace SLang
{
    # ============================================================================
    # SLang/Server/StreamIo.sl 增补 — HttpBodyReader（P5，§6.6 请求侧流式）
    #
    # 生命周期：streamBody=true 的路由命中时，引擎把连接 + 预读缓冲移交
    #   handler（Request._bindStream 绑定）；req.bodyStream() 构造本读取器。
    #   read( dst ) 语义：填充 dst 可写区（最多 min(need, dst.writableBytes)），
    #   返回本次读到的字节数；0 = body 结束（Content-Length 读满 / chunked
    #   终止块）；EOF 截断抛 HttpError.Protocol（对端中断）。
    #   累计字节超 maxStreamBodyBytes（引擎绑定传入）→ 抛 ServerError
    #   .InvalidConfig？不——走 413 语义：抛 StreamBodyError.LimitExceeded，
    #   handler 可捕获后 res.jsonFail(413,...)；未捕获由引擎 500 兜底。
    #   readAll() = 循环聚合便捷形态（小体量场景；大文件用 read+FileStream）。
    #   读取器用毕调 done()：报告是否消费完整（引擎决定 keep-alive 续用
    #   还是 drain 收尾）；不调也可（引擎查 _done 标志）。
    # ============================================================================

    public enum StreamBodyError extends Error
    {
        # 累计读取超 maxStreamBodyBytes（413 语义）
        LimitExceeded = { code = 1 }
    }

    public class HttpBodyReader
    {
        # 连接 + 预读缓冲（引擎移交；读路径与 _HttpParser 同款）
        Net.NetStream _conn = null
        ByteBuffer _buf = null
        # Content-Length 模式：剩余字节数（-1 = chunked / 0 = 结束）
        Int64 _remain = 0
        # chunked 模式标志
        bool _chunked = false
        # chunked 当前块剩余（0 = 待读块头）
        Int32 _chunkRemain = 0
        # chunked 已见终止块
        bool _chunkEnd = false
        # 累计已读 + 上限（超限抛 LimitExceeded）
        Int64 _total = 0
        Int64 _maxBytes = 0
        # 消费完整（CL 读满 / chunked 终止块已消化）
        bool _done = false

        # 引擎构造（Request._bindStream → req.bodyStream()；用户勿直接 new）
        _init_( Net.NetStream conn, ByteBuffer buf, Int64 contentLength, bool chunked, Int64 maxBytes )
        {
            this._conn = conn
            this._buf = buf
            this._chunked = chunked
            this._maxBytes = maxBytes
            if chunked
            {
                this._remain = -1
                this._chunkRemain = 0
                this._chunkEnd = false
            }
            else
            {
                this._remain = contentLength
                this._chunkRemain = 0
                this._chunkEnd = false
                if contentLength <= 0
                {
                    this._done = true
                }
            }
            this._total = 0
        }

        # 是否已消费完整（引擎 keep-alive 判定用）
        public get bool isDone()
        {
            ret this._done
        }

        # 读一段 body 入 dst 可写区：返回本次字节数（0 = 结束）；
        # EOF 截断抛 Net.HttpError.Protocol；超限抛 StreamBodyError.LimitExceeded
        public Int32 read( ByteBuffer dst ) throws
        {
            if this._done
            {
                ret 0
            }
            if this._chunked
            {
                ret this._readChunked( dst )
            }
            ret this._readCl( dst )
        }

        # 聚合全量（便捷形态；超大 body 请用 read 循环 + FileStream 落盘）
        public ByteBuffer readAll() throws
        {
            ByteBuffer outBuf = ByteBuffer()
            ByteBuffer chunk = ByteBuffer( 65536 )
            while true
            {
                Int32 n = this.read( chunk )
                if n <= 0
                {
                    break
                }
                ByteBuffer view = chunk.slice( 0, n )
                outBuf.writeBytes( view )
                chunk.clear()
            }
            chunk.release()
            ret outBuf
        }

        # ── Content-Length 模式 ──
        Int32 _readCl( ByteBuffer dst ) throws
        {
            Int32 want = dst.writableBytes
            if want <= 0
            {
                ret 0
            }
            Int64 canTake = this._remain
            if canTake > want
            {
                canTake = want
            }
            if canTake <= 0
            {
                this._done = true
                ret 0
            }
            Int32 got = this._pull( dst, canTake.toInt32() )
            if got <= 0
            {
                # EOF 截断（对端中断）
                throw Net.HttpError.Protocol
            }
            this._remain = this._remain - got
            this._total = this._total + got
            if this._total > this._maxBytes
            {
                throw StreamBodyError.LimitExceeded
            }
            if this._remain <= 0
            {
                this._done = true
            }
            ret got
        }

        # ── chunked 模式 ──
        Int32 _readChunked( ByteBuffer dst ) throws
        {
            while true
            {
                # 当前块有剩余：直读
                if this._chunkRemain > 0
                {
                    Int32 want = dst.writableBytes
                    if want <= 0
                    {
                        ret 0
                    }
                    Int32 take = this._chunkRemain
                    if take > want
                    {
                        take = want
                    }
                    Int32 got = this._pull( dst, take )
                    if got <= 0
                    {
                        throw Net.HttpError.Protocol
                    }
                    this._chunkRemain = this._chunkRemain - got
                    this._total = this._total + got
                    if this._total > this._maxBytes
                    {
                        throw StreamBodyError.LimitExceeded
                    }
                    if this._chunkRemain == 0
                    {
                        # 块尾 CRLF
                        ByteBuffer crlf = ByteBuffer()
                        Int32 ec = HttpServerCore._readBytesChecked( this._conn, this._buf, crlf, 2 )
                        crlf.release()
                        if ec != 0
                        {
                            throw Net.HttpError.Protocol
                        }
                    }
                    ret got
                }
                # 待读块头 / 终止块
                if this._chunkEnd
                {
                    this._done = true
                    ret 0
                }
                string line = HttpServerCore._readLine( this._conn, this._buf )
                if line == null
                {
                    throw Net.HttpError.Protocol
                }
                Int32 size = HttpServerCore._chunkSize( HttpServerCore._stripEol( line ) )
                if size < 0
                {
                    throw Net.HttpError.Protocol
                }
                if size == 0
                {
                    # 终止块：消化 trailer 至空行
                    while true
                    {
                        string t = HttpServerCore._readLine( this._conn, this._buf )
                        if t == null
                        {
                            throw Net.HttpError.Protocol
                        }
                        if SystemStringLength( HttpServerCore._stripEol( t ) ) == 0
                        {
                            break
                        }
                    }
                    this._chunkEnd = true
                    this._done = true
                    ret 0
                }
                # 块头预检上限（防单块声明超限仍进入读路径）
                if this._total + size > this._maxBytes
                {
                    throw StreamBodyError.LimitExceeded
                }
                this._chunkRemain = size
            }
            ret 0
        }

        # 底层拉取：先消费 _buf 预读，不足再从连接读（_readBytesChecked 同款；
        # 但 dst 只填 take 字节且返回实际值——EOF 返回 0 由调用方判协议错误）
        Int32 _pull( ByteBuffer dst, Int32 take ) throws
        {
            Int32 need = take
            while need > 0
            {
                if this._buf.readableBytes > 0
                {
                    Int32 avail = this._buf.readableBytes
                    if avail > need
                    {
                        avail = need
                    }
                    this._buf.readBytes( dst, avail )
                    need = need - avail
                }
                else
                {
                    if this._buf.writableBytes < 4096
                    {
                        this._buf.discardReadBytes()
                        this._buf.ensureWritable( 4096 )
                    }
                    Int32 n = this._conn.read( this._buf )
                    if n == 0
                    {
                        break
                    }
                }
            }
            ret take - need
        }
    }
}
