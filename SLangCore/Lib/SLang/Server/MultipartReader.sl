import Std;
import Core;

namespace SLang
{
    # ============================================================================
    # SLang/Server/MultipartReader.sl — multipart 流式解析（P7，§6.6）
    # 设计契约：SERVER_DESIGN.md §6.6（请求侧流式上传扩展）/ §6.4
    #   （multipart 语义——与全内存版 BodyParser.parseMultipart 对齐）
    #
    # 生命周期：streamBody=true 路由 + multipart/form-data Content-Type 时
    #   req.multipartStream() 构造本解析器（单请求缓存实例）。nextPart()
    #   迭代 part（MultipartPart）：read(dst) 流式读内容 / readAll() 聚合 /
    #   saveAs(path) 边收边落盘（FileStream，目录须已存在）。
    # 语义对齐（§6.4）：preamble 行容忍；part 头只认 Content-Disposition /
    #   Content-Type（默认 application/octet-stream），无冒号头行忽略（宽容）；
    #   无 name 的 part 内容丢弃（宽容）；filename 经 BodyParser._safeFilename
    #   安全化（路径剥离 + upload_<seq> 兜底）；字段值不解码（直传语义）。
    # 内存语义：内容经 _win 工作窗口（64KB 量级）+ _pat("\r\n--B") 原生
    #   indexOf 匹配；未命中时窗口尾悬挂保留 (patLen-1) 字节防 boundary 被
    #   TCP 分段切断（跨块正确）；part 内容不驻留内存（saveAs 边收边写）。
    # 收尾（P7 修正，引擎 6a 配合）：_win 预读字节已从底层 bodyStream 实例
    #   消费——handler 返回后引擎收尾先经 _drainTail() 以 multipart 语义排干
    #   剩余结构（防 _win 残留被底层 drainer 跳过而错吃下一请求字节），再由
    #   缓存的 bodyStream 实例排干 CL 余量（epilogue）；失败断连止损。
    # 错误：截断报文（boundary 未闭合 / body 尽而无完整行 / 行积压超限）抛
    #   Net.HttpError.Protocol；底层累计超限抛 StreamBodyError.LimitExceeded
    #   （multipart 场景上限 = cfg.maxUploadBytes，见 Request.multipartStream）。
    # 已知限制：用户 dst 可写区极小（如百字节）读大 part 时每轮全窗重扫
    #   （O(n²) 最坏），正常 64KB 分块循环无影响；saveAs 在句柄过期后调用
    #   写出空文件（read 恒 0）——句柄随 nextPart 推进即过期，勿跨迭代持有。
    # ============================================================================

    # ── 单个 part 句柄（MultipartReader.nextPart 产出；用户勿直接 new）──
    public class MultipartPart
    {
        # 归属解析器（read 经它消费内容区）
        MultipartReader _owner = null
        # 表单字段名
        string _field = ""
        # 文件名（null = 普通字段；已剥离路径）
        string _filename = null
        # part 声明的 Content-Type
        string _contentType = ""

        _init_( MultipartReader owner, string field, string filename, string contentType )
        {
            this._owner = owner
            this._field = field
            this._filename = filename
            this._contentType = contentType
        }

        # ── 元数据 ──

        public get string field()
        {
            ret this._field
        }

        public get string filename()
        {
            ret this._filename
        }

        public get string contentType()
        {
            ret this._contentType
        }

        # 是否文件 part（有 filename 声明）
        public get bool isFile()
        {
            ret this._filename != null
        }

        # 读一段内容入 dst 可写区：返回本次字节数（0 = 本 part 结束）；
        # 句柄过期（nextPart 已推进）恒 0。截断抛 Protocol；底层超限抛
        # StreamBodyError.LimitExceeded
        public Int32 read( ByteBuffer dst ) throws
        {
            if this._owner == null
            {
                ret 0
            }
            if this._owner._cur != this
            {
                ret 0
            }
            ret this._owner._readContent( dst )
        }

        # 聚合本 part 全量（小体量场景；大文件用 read 循环 / saveAs）
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

        # 边收边落盘（FileStream 流式写；目录须已存在；失败返回 false）
        public bool saveAs( string path )
        {
            ByteBuffer chunk = null
            FileStream fs = null
            bool ok = true
            label saveBlock
            {
                fs = FileStream( path, FileMode.Create )
                chunk = ByteBuffer( 65536 )
                while true
                {
                    Int32 n = this.read( chunk )
                    if n <= 0
                    {
                        break
                    }
                    ByteBuffer view = chunk.slice( 0, n )
                    fs.write( view )
                    chunk.clear()
                }
                fs.flush()
            }
            catch
            {
                ok = false
            }
            if chunk != null
            {
                chunk.release()
            }
            if fs != null
            {
                label closeBlock
                {
                    fs.close()
                }
                catch
                {
                    ok = false
                }
            }
            ret ok
        }
    }

    # ── multipart 流式解析器（req.multipartStream() 构造；用户勿直接 new）──
    public class MultipartReader
    {
        # 底层 body 读取器（req.bodyStream() 缓存实例；CL/chunked 解码 + 限额）
        HttpBodyReader _r = null
        # 内容区定界模式 "\r\n--<boundary>"（原生 indexOf 匹配）
        ByteBuffer _pat = null
        Int32 _patLen = 0
        # 首分隔符行 "--<boundary>"（行模式比对）
        string _dashB = ""
        # 收尾标记 "--"（boundary 行后续判定）
        ByteBuffer _dashClose = null
        # 工作窗口（预读 + 匹配；容量 68KB = 64KB 积压上限 + 4KB fill 余量）
        ByteBuffer _win = null
        # 行模式积压上限（无换行积压超此值视为坏流）
        Int32 _winMax = 65536
        # 状态机：0 = 首分隔符前 / 1 = part 头区 / 2 = 内容区 /
        #   3 = boundary 已消化（待判收尾或空行）/ 4 = 结束
        Int32 _state = 0
        # 当前 part 句柄（readAll/read 过期判定锚点）
        MultipartPart _cur = null
        # 文件序号（安全名兜底 upload_<seq>）
        Int32 _seq = 0

        _init_( HttpBodyReader reader, string boundary )
        {
            this._r = reader
            this._pat = ByteBuffer.fromString( "\r\n--" + boundary )
            this._patLen = this._pat.readableBytes
            this._dashB = "--" + boundary
            this._dashClose = ByteBuffer.fromString( "--" )
            this._win = ByteBuffer( 69632 )
            this._state = 0
            this._cur = null
            this._seq = 0
        }

        # 工厂：从 Content-Type 提取 boundary 构造（boundary 缺失返回 null）
        static MultipartReader of( HttpBodyReader reader, string contentType )
        {
            string b = BodyParser._extractBoundary( contentType )
            if SystemStringLength( b ) == 0
            {
                ret null
            }
            ret MultipartReader( reader, b )
        }

        # multipart 结构是否已完整消费（含收尾 "--B--"）
        public get bool isDone()
        {
            ret this._state == 4
        }

        # 迭代下一个 part：返回句柄（元数据 + read/readAll/saveAs）；
        # null = 全部结束。自动排干未读完的当前 part；无 name 的 part
        # 内容丢弃不产出（宽容）。截断抛 Protocol；超限抛 LimitExceeded
        public MultipartPart nextPart() throws
        {
            if this._state == 4
            {
                ret null
            }
            if this._cur != null
            {
                this._drainContent()
                this._cur = null
            }
            while true
            {
                if this._state == 0
                {
                    # 首分隔符定位（容忍 preamble 行；"--B--" 空表单直接收工）
                    string line = this._ensureLine()
                    if line == this._dashB
                    {
                        this._state = 1
                    }
                    elif line == this._dashB + "--"
                    {
                        this._state = 4
                        ret null
                    }
                }
                elif this._state == 1
                {
                    # ---- part 头（到空行；只认 Content-Disposition / Content-Type）----
                    string disp = null
                    string partCt = "application/octet-stream"
                    bool headDone = false
                    while headDone == false
                    {
                        string hline = this._ensureLine()
                        Int32 hl = SystemStringLength( hline )
                        if hl == 0
                        {
                            headDone = true
                        }
                        else
                        {
                            Int32 ci = -1
                            for Int32 k = 0, k < hl, k = k + 1
                            {
                                if SystemStringCharCodeAt( hline, k ) == 58
                                {
                                    ci = k
                                    break
                                }
                            }
                            if ci > 0
                            {
                                Int32 vs = ci + 1
                                while vs < hl && SystemStringCharCodeAt( hline, vs ) == 32
                                {
                                    vs = vs + 1
                                }
                                string hname = SystemStringRange( hline, 0, ci )
                                string hval = SystemStringRange( hline, vs, hl )
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
                    # ---- name / filename 提取（§6.4）----
                    string fieldName = ""
                    string fileName = null
                    if disp != null
                    {
                        string nm = BodyParser._dispParam( disp, "name" )
                        if nm != null
                        {
                            fieldName = nm
                        }
                        fileName = BodyParser._dispParam( disp, "filename" )
                    }
                    this._state = 2
                    if SystemStringLength( fieldName ) == 0
                    {
                        # 无 name 的 part：内容丢弃（宽容）——排干后取下一 part
                        this._drainContent()
                    }
                    else
                    {
                        string safeName = null
                        if fileName != null
                        {
                            safeName = BodyParser._safeFilename( fileName, this._seq )
                        }
                        this._seq = this._seq + 1
                        MultipartPart p = MultipartPart( this, fieldName, safeName, partCt )
                        this._cur = p
                        ret p
                    }
                }
                elif this._state == 3
                {
                    # boundary 后续："--" = 收尾；否则应为一行 CRLF（空行，
                    # 非空容忍跳过）→ 下一 part 头
                    while this._win.readableBytes < 2
                    {
                        if this._fill() == 0
                        {
                            # body 尽而收尾未闭合（截断报文）
                            throw Net.HttpError.Protocol
                        }
                    }
                    if this._win.startsWith( this._dashClose )
                    {
                        this._state = 4
                        ret null
                    }
                    string tail = this._ensureLine()
                    this._state = 1
                }
                else
                {
                    # state==2 理论不可达（入口已排干）；防御收尾
                    this._state = 4
                    ret null
                }
            }
            ret null
        }

        # 内容区读取（状态 2 专用）：批量写当前 part 内容入 dst 可写区，
        # 返回本次字节数；0 = 本 part 结束（boundary 已消化、_state 推进 3）。
        # 跨块悬挂保留：未命中时窗口尾留 (patLen-1) 字节下轮 fill 后重扫。
        Int32 _readContent( ByteBuffer dst ) throws
        {
            if this._state != 2
            {
                ret 0
            }
            # readBytes 无 dst 可写守卫——调用方先钳制容量（写溢出防线）
            Int32 cap = dst.writableBytes
            if cap <= 0
            {
                ret 0
            }
            while true
            {
                Int32 have = this._win.readableBytes
                if have >= this._patLen
                {
                    Int32 idx = this._win.indexOf( this._pat )
                    if idx >= 0
                    {
                        if idx == 0
                        {
                            # 空内容 part：boundary 直接命中
                            this._win.skipBytes( this._patLen )
                            this._win.discardReadBytes()
                            this._state = 3
                            this._cur = null
                            ret 0
                        }
                        Int32 outN = idx
                        if outN > cap
                        {
                            outN = cap
                        }
                        # outN >= 1 保证（idx > 0 且 cap >= 1）；boundary
                        # 前内容超 dst 容量时本轮先吐 cap，_state 保持 2
                        # 下轮重扫（背压语义）
                        this._win.readBytes( dst, outN )
                        this._win.discardReadBytes()
                        ret outN
                    }
                    # 未命中：悬挂保留（尾 patLen-1 字节防 boundary 跨块切断）
                    Int32 safe = have - this._patLen + 1
                    Int32 outS = safe
                    if outS > cap
                    {
                        outS = cap
                    }
                    # outS >= 1 保证（have >= patLen 且 cap >= 1）
                    this._win.readBytes( dst, outS )
                    this._win.discardReadBytes()
                    ret outS
                }
                # 窗口不足一个模式长：拉取重试
                if this._fill() == 0
                {
                    # body 尽而 boundary 未闭合（截断报文）
                    throw Net.HttpError.Protocol
                }
            }
            ret 0
        }

        # 行模式取一行（剥 CRLF）：无完整行则拉取重试；积压超 _winMax
        # 视为坏流；body 尽而无完整行视为截断
        string _ensureLine() throws
        {
            while true
            {
                string line = this._win.readLine()
                if line != null
                {
                    ret HttpServerCore._stripEol( line )
                }
                if this._win.readableBytes > this._winMax
                {
                    throw Net.HttpError.Protocol
                }
                if this._fill() == 0
                {
                    throw Net.HttpError.Protocol
                }
            }
            ret ""
        }

        # 窗口拉取：底层读取器（CL/chunked 解码 + 限额）读入 _win 可写区；
        # 已读区满则先压缩腾位（防膨胀）
        Int32 _fill() throws
        {
            if this._win.writableBytes < 4096
            {
                this._win.discardReadBytes()
                this._win.ensureWritable( 4096 )
            }
            ret this._r.read( this._win )
        }

        # 排干当前内容区（状态 2 → 3）：nextPart 自动推进 / 无 name part
        # 丢弃 / 引擎收尾复用
        void _drainContent() throws
        {
            if this._state != 2
            {
                ret
            }
            ByteBuffer scratch = ByteBuffer( 65536 )
            while this._state == 2
            {
                Int32 n = this._readContent( scratch )
                scratch.clear()
                if n <= 0
                {
                    break
                }
            }
            scratch.release()
        }

        # 收尾排干（引擎 6a）：以 multipart 语义消费完剩余结构（丢弃式），
        # 直至收尾分隔符或异常。_win 预读残留由此闭环，防底层 drainer
        # 按 CL 余量排干时跳过 _win 数据错吃下一请求字节
        void _drainTail() throws
        {
            while true
            {
                MultipartPart p = this.nextPart()
                if p == null
                {
                    break
                }
            }
        }
    }
}
