import Std;
import Core;

namespace SLang
{
    # ============================================================================
    # SLang/Server/Request.sl — 请求上下文（读侧 API，P1 全表 → P1.5 增补）
    # 设计契约：SERVER_DESIGN.md §6.3 / §4.4
    #
    # P1 全表：方法/路径/原始查询/请求头/body 三视图（text/json/bytes/<T>）/
    #   bodyFormat 分流/form 族（urlencoded）/路径参数族（路由 {param} 提取）/
    #   查询参数族（percent + '+'→空格解码）/对端地址/传值槽（userData）/
    #   身份槽（auth，P3 auth 插件写入）。
    # 实例由引擎构造（构造入参即全部字段，无公开无参构造语义）；
    # bodyBytes() 返回 slice 视图（不推进源索引），勿跨请求持有。
    # P1.5 增补：文件族（file/files/fileCount）+ multipart 普通字段并入
    #   form 族（引擎构造期经 _ensureMultipart 即时解析，§6.5；单文件超限
    #   → 413、boundary 缺失 → 400 由引擎协议层应答）。
    # ============================================================================
    public class Request
    {
        string _method = ""
        string _path = ""
        string _rawQuery = ""
        Net.HttpHeaders _headers = null
        # body 缓冲（无 body 为 null；归属本请求，响应写出后引擎统一回收）
        ByteBuffer _body = null
        string _ip = ""
        Int32 _port = 0
        # 路由 {param} 提取结果（无参数路由为空 Map）
        Map<string,string> _pathParams = null
        # 查询参数惰性解析缓存
        Map<string,string> _queryParsed = null
        # form 字段惰性解析缓存（urlencoded；multipart 经 _mpFields 并入）
        Map<string,string> _formParsed = null
        bool _formDone = false
        # multipart 解析结果（惰性一次；引擎派发前即时触发，§6.5）
        Map<string,string> _mpFields = null
        List<UploadedFile> _mpFiles = null
        bool _mpDone = false
        # 0 = OK / 400 = boundary 缺失或格式坏 / 413 = 单文件超限
        Int32 _mpCode = 0
        # ── 请求侧流式（P5，§6.6）──
        # streamBody=true 路由：引擎在头区空行后停止预读，连接 + 预读
        # 缓冲经 _bindStream 移交本请求；bodyStream() 据此构造读取器
        Net.NetStream _streamConn = null
        ByteBuffer _streamBuf = null
        Int64 _streamCl = 0
        bool _streamChunked = false
        # ── 流式读取器缓存（P7，§6.6）──
        # bodyStream() 首取定形缓存单实例：后续调用（含引擎 keep-alive
        # 收尾 drainer）返回同一实例，_remain 与 handler 消费进度接力
        # （修复 P5 期每次新造实例按完整 CL 起算的多吃错位）；multipart
        # 解析器（multipartStream）同样缓存，引擎收尾据此以 multipart
        # 语义排干剩余结构（_win 预读窗口残留由此闭环）
        HttpBodyReader _streamReader = null
        MultipartReader _mpReader = null

        # ── 传值槽（中间件 → 处理器；引擎不触碰）──
        # 自由传值槽（任意语义）
        public object userData = null
        # 约定身份槽（auth 插件校验通过后写入身份、handler 只读使用；
        # 多为 SLang.JwtClaims；与 userData 分工见 §4.11，P3 auth 落地）
        public object auth = null

        # 引擎内部构造（用户勿直接 new）
        _init_( string method, string path, string rawQuery, Net.HttpHeaders headers, ByteBuffer body, string ip, Int32 port, Map<string,string> pathParams )
        {
            this._method = method
            this._path = path
            this._rawQuery = rawQuery
            this._headers = headers
            this._body = body
            this._ip = ip
            this._port = port
            this._pathParams = pathParams
            this._mpFields = new()
            this._mpFiles = new()
            this._mpDone = false
            this._mpCode = 0
            this._streamConn = null
            this._streamBuf = null
            this._streamCl = 0
            this._streamChunked = false
            this._streamReader = null
            this._mpReader = null
        }

        # 引擎绑定（streamBody 路由派发前；用户勿调）——连接 + 预读
        # 缓冲 + body 元信息移交（§6.6）
        void _bindStream( Net.NetStream conn, ByteBuffer buf, Int64 contentLength, bool chunked )
        {
            this._streamConn = conn
            this._streamBuf = buf
            this._streamCl = contentLength
            this._streamChunked = chunked
        }

        # 是否流式 body 路由（引擎收尾判定 + handler 侧能力探测）
        public get bool isStreamBody()
        {
            ret this._streamConn != null
        }

        # 流式 body 读取器（streamBody 路由专用；非流式路由返回 null）。
        # P7：首取定形缓存单实例——同请求多次调用/引擎收尾复用同一实例
        # （消费进度接力；maxBytes 形态在实例已存在时忽略其上限）。
        # 上限 = cfg.maxBodyBytes（multipart 场景放宽为 maxUploadBytes）
        public HttpBodyReader bodyStream()
        {
            if this._streamConn == null
            {
                ret null
            }
            if this._streamReader != null
            {
                ret this._streamReader
            }
            Int64 limit = 10485760
            ServerConfig cfg = HttpServerCore._cfg
            if cfg != null
            {
                limit = cfg.maxBodyBytes
                string ct = this.contentType()
                if ct != null && BodyParser.isMultipart( ct )
                {
                    limit = cfg.maxUploadBytes
                }
            }
            this._streamReader = HttpBodyReader( this._streamConn, this._streamBuf, this._streamCl, this._streamChunked, limit )
            ret this._streamReader
        }

        # 流式 body 读取器（显式上限形态；调用方自管限额场景）。
        # 首取定形：实例已存在（含无参形态先取）则忽略本次上限
        public HttpBodyReader bodyStream( Int64 maxBytes )
        {
            if this._streamConn == null
            {
                ret null
            }
            if this._streamReader != null
            {
                ret this._streamReader
            }
            this._streamReader = HttpBodyReader( this._streamConn, this._streamBuf, this._streamCl, this._streamChunked, maxBytes )
            ret this._streamReader
        }

        # multipart 流式解析器（P7，§6.6；streamBody 路由专用）。
        # Content-Type 非 multipart / boundary 缺失 → 返回 null（调用方
        # 可回退 bodyStream 裸读）。底层经 bodyStream() 缓存实例（multipart
        # 场景上限已放宽为 maxUploadBytes）；两种消费路径互斥——同一请求
        # 勿混用 multipartStream 与 bodyStream 裸读（字节归属交错）。
        # 解析器一次构造缓存（构造失败不缓存，可重试）；引擎 keep-alive
        # 收尾复用缓存实例以 multipart 语义排干剩余结构
        public MultipartReader multipartStream()
        {
            if this._streamConn == null
            {
                ret null
            }
            if this._mpReader != null
            {
                ret this._mpReader
            }
            string ct = this.contentType()
            if ct == null
            {
                ret null
            }
            if BodyParser.isMultipart( ct ) == false
            {
                ret null
            }
            HttpBodyReader r = this.bodyStream()
            if r == null
            {
                ret null
            }
            MultipartReader m = MultipartReader.of( r, ct )
            if m == null
            {
                ret null
            }
            this._mpReader = m
            ret m
        }

        # ── 请求行 ──

        # 请求方法（原始大写，如 "GET" / "POST"）
        public get string method()
        {
            ret this._method
        }

        # 路径（不含 query）
        public get string path()
        {
            ret this._path
        }

        # 原始 query 串（可为空串）
        public get string rawQuery()
        {
            ret this._rawQuery
        }

        # 对端地址 / 端口
        public get string ip()
        {
            ret this._ip
        }

        public get Int32 port()
        {
            ret this._port
        }

        # ── 请求头 ──

        # 原始头集合（大小写不敏感取值经 header(name)）
        public get Net.HttpHeaders headers()
        {
            ret this._headers
        }

        # 取请求头（大小写不敏感；不存在返回 null）
        public string header( string name )
        {
            ret this._headers.getHeader( name )
        }

        # 原始 Content-Type（含参数，如 boundary；无则空串）
        public get string contentType()
        {
            string v = this._headers.getHeader( "Content-Type" )
            if v == null
            {
                ret ""
            }
            ret v
        }

        # 请求声明长度（Content-Length；无头或格式非法为 0）
        public get Int64 contentLength()
        {
            string v = this._headers.getHeader( "Content-Length" )
            if v == null
            {
                ret 0
            }
            Int64 n = HttpServerCore._parseDec64( v )
            if n < 0
            {
                ret 0
            }
            ret n
        }

        # Upgrade 头探测（Upgrade: websocket 升级请求为 true）
        public get bool isUpgrade()
        {
            string v = this._headers.getHeader( "Upgrade" )
            if v == null
            {
                ret false
            }
            ret HttpServerCore._containsFold( v, "websocket" )
        }

        # ── body 三视图 ──

        # body 文本（UTF-8；无 body 空串；可重复调用，不消耗索引）
        public string bodyText()
        {
            if this._body == null
            {
                ret ""
            }
            ret this._body.toString()
        }

        # body 二进制视图（slice 视图；无 body 返回 null）
        public ByteBuffer bodyBytes()
        {
            if this._body == null
            {
                ret null
            }
            ret this._body.slice()
        }

        # body 作 JSON 树解析；空 body / 解析失败返回 null
        public BaseJson bodyJson()
        {
            string text = this.bodyText()
            if SystemStringLength( text ) == 0
            {
                ret null
            }
            BaseJson j = BaseJson.parse( text )
            if j.isEmpty
            {
                ret null
            }
            ret j
        }

        # body JSON → DTO（BaseJson.toData<T> 直通；失败/空 body 返回 null，不抛）
        public T body<T>()
        {
            BaseJson j = BaseJson.parse( this.bodyText() )
            ret j.toData<T>()
        }

        # body 格式判定（Content-Type 分流，§4.4 表）
        public get EBodyFormat bodyFormat()
        {
            Int32 bodyLen = 0
            if this._body != null
            {
                bodyLen = this._body.readableBytes
            }
            ret BodyParser.detect( this.contentType(), bodyLen )
        }

        # ── form 表单（urlencoded + multipart 普通字段；§4.4）──
        # multipart 字段值不解码（直传语义，§6.4）；格式坏/超限时 form 族
        # 返回空（协议层已由引擎以 400/413 应答，正常流程到不了 handler）。

        # form 字段值（urlencoded 已解码；multipart 直传）；不存在返回 null
        public string form( string name )
        {
            if this._ensureForm() == false
            {
                ret null
            }
            if this._formParsed.containsKey( name ) == false
            {
                ret null
            }
            ret this._formParsed[name]
        }

        # form 字段 Int32 化；不存在/坏格式用 defVal
        public Int32 formInt( string name, Int32 defVal )
        {
            string v = this.form( name )
            if v == null
            {
                ret defVal
            }
            Int64 n = HttpServerCore._parseDec64( v )
            if n < 0
            {
                ret defVal
            }
            ret n.toInt32()
        }

        # form 字段布尔化（1/true/on 为真，其余假）；不存在用 defVal
        public bool formBool( string name, bool defVal )
        {
            string v = this.form( name )
            if v == null
            {
                ret defVal
            }
            if v == "1" || v == "true" || v == "on"
            {
                ret true
            }
            ret false
        }

        public bool hasForm( string name )
        {
            if this._ensureForm() == false
            {
                ret false
            }
            ret this._formParsed.containsKey( name )
        }

        # 全部字段名（无 form 为空表）。
        # 注意：struct 登记类的泛型返回方法体内，局部/形参 List 的 .add 链
        # 解析失败（Front Meta 层，「节点[add] 没有在类[Core.List<Core.String>]」；
        # 内部类不受影响）——拷贝循环收进内部类 _SrvUtil（queryKeys 同款）
        public List<string> formKeys()
        {
            List<string> outList = new()
            if this._ensureForm()
            {
                _SrvUtil.copyKeys( this._formParsed, outList )
            }
            ret outList
        }

        # 惰性解析 form（urlencoded 直解；multipart 普通字段并入，§4.4）
        bool _ensureForm()
        {
            if this._formDone
            {
                ret this._formParsed != null
            }
            this._formDone = true
            EBodyFormat fmt = this.bodyFormat
            if fmt == EBodyFormat.Form
            {
                this._formParsed = BodyParser.parseForm( this.bodyText() )
                ret true
            }
            if fmt == EBodyFormat.Multipart
            {
                # multipart 普通字段同 form API（§4.4 分流表）
                this._ensureMultipart()
                if this._mpCode == 0 && this._mpFields != null
                {
                    this._formParsed = this._mpFields
                    ret true
                }
            }
            ret false
        }

        # ── 文件上传（multipart/form-data；§4.4 / §6.5）──

        # 该字段首个文件；无返回 null
        public UploadedFile file( string field )
        {
            if this._ensureMultipart() != 0
            {
                ret null
            }
            Int32 n = this._mpFiles.length
            for Int32 i = 0, i < n, i = i + 1
            {
                UploadedFile f = this._mpFiles[i]
                if f._field == field
                {
                    ret f
                }
            }
            ret null
        }

        # 该字段全部文件（多文件同字段）；无返回空表
        public List<UploadedFile> files( string field )
        {
            List<UploadedFile> outList = new()
            if this._ensureMultipart() != 0
            {
                ret outList
            }
            Int32 n = this._mpFiles.length
            for Int32 i = 0, i < n, i = i + 1
            {
                UploadedFile f = this._mpFiles[i]
                if f._field == field
                {
                    outList.add( f )
                }
            }
            ret outList
        }

        # 本请求文件总数
        public get Int32 fileCount()
        {
            if this._ensureMultipart() != 0
            {
                ret 0
            }
            ret this._mpFiles.length
        }

        # multipart 惰性解析（引擎在 handler 派发前即时触发——构造期语义
        # §6.5；重复调用返回缓存）。返回 0 = OK / 400 = boundary 缺失或
        # 格式坏 / 413 = 单文件超 maxFileBytes（引擎按协议层应答 + 断连）
        Int32 _ensureMultipart()
        {
            if this._mpDone
            {
                ret this._mpCode
            }
            this._mpDone = true
            this._mpCode = 0
            EBodyFormat fmt = this.bodyFormat
            if fmt != EBodyFormat.Multipart
            {
                ret 0
            }
            Int32 limit = HttpServerCore._uploadFileLimit()
            string ct = this.contentType()
            ByteBuffer bodyBuf = this._body
            _MultipartBody mp = BodyParser.parseMultipart( ct, bodyBuf, limit )
            this._mpCode = mp._errorCode
            if mp._fields != null
            {
                this._mpFields = mp._fields
            }
            if mp._files != null
            {
                this._mpFiles = mp._files
            }
            ret this._mpCode
        }

        # ── 路径参数（路由 {param} 提取；§4.2）──

        # 路径段参数；不存在返回 null
        public string pathParam( string name )
        {
            if this._pathParams == null
            {
                ret null
            }
            if this._pathParams.containsKey( name ) == false
            {
                ret null
            }
            ret this._pathParams[name]
        }

        # 路径参数 Int32 化；不存在/坏格式用 defVal（单参版 defVal=0）
        public Int32 pathInt( string name, Int32 defVal )
        {
            string v = this.pathParam( name )
            if v == null
            {
                ret defVal
            }
            Int64 n = HttpServerCore._parseDec64( v )
            if n < 0
            {
                ret defVal
            }
            ret n.toInt32()
        }

        public Int32 pathInt( string name )
        {
            ret this.pathInt( name, 0 )
        }

        # 路径参数 Int64 化；不存在/坏格式/溢出用 defVal
        public Int64 pathInt64( string name, Int64 defVal )
        {
            string v = this.pathParam( name )
            if v == null
            {
                ret defVal
            }
            Int64 n = HttpServerCore._parseDec64Full( v )
            if n < 0
            {
                ret defVal
            }
            ret n
        }

        # 路径参数 Float64 化；不存在/坏格式（非数字串）用 defVal
        public Float64 pathFloat( string name, Float64 defVal )
        {
            string v = this.pathParam( name )
            if v == null
            {
                ret defVal
            }
            if Request._isNumeric( v ) == false
            {
                ret defVal
            }
            ret SystemConvertFloat64( v )
        }

        # ── 查询参数（?a=1&b=x；percent + '+'→空格解码）──

        # 查询参数值；不存在返回 null
        public string query( string name )
        {
            if this._queryParsed == null
            {
                this._queryParsed = BodyParser.parseForm( this._rawQuery )
            }
            if this._queryParsed.containsKey( name ) == false
            {
                ret null
            }
            ret this._queryParsed[name]
        }

        # 查询参数 Int32 化；不存在/坏格式用 defVal
        public Int32 queryInt( string name, Int32 defVal )
        {
            string v = this.query( name )
            if v == null
            {
                ret defVal
            }
            Int64 n = HttpServerCore._parseDec64( v )
            if n < 0
            {
                ret defVal
            }
            ret n.toInt32()
        }

        # 查询参数布尔化（1/true/on 为真）；不存在用 defVal
        public bool queryBool( string name, bool defVal )
        {
            string v = this.query( name )
            if v == null
            {
                ret defVal
            }
            if v == "1" || v == "true" || v == "on"
            {
                ret true
            }
            ret false
        }

        public bool hasQuery( string name )
        {
            if this._queryParsed == null
            {
                this._queryParsed = BodyParser.parseForm( this._rawQuery )
            }
            ret this._queryParsed.containsKey( name )
        }

        # 全部查询参数名（无查询为空表；拷贝经 _SrvUtil——见 formKeys 注记）
        public List<string> queryKeys()
        {
            List<string> outList = new()
            if this._queryParsed == null
            {
                this._queryParsed = BodyParser.parseForm( this._rawQuery )
            }
            _SrvUtil.copyKeys( this._queryParsed, outList )
            ret outList
        }

        # 数字串校验（可选一元 '-' + 数字 + 至多一个 '.'；空串 false）
        static bool _isNumeric( string s )
        {
            Int32 len = SystemStringLength( s )
            if len == 0
            {
                ret false
            }
            Int32 start = 0
            if SystemStringCharCodeAt( s, 0 ) == 45
            {
                start = 1
                if len == 1
                {
                    ret false
                }
            }
            Int32 dotCount = 0
            for Int32 i = start, i < len, i = i + 1
            {
                Int32 c = SystemStringCharCodeAt( s, i )
                if c == 46
                {
                    dotCount = dotCount + 1
                    if dotCount > 1
                    {
                        ret false
                    }
                }
                elif c < 48 || c > 57
                {
                    ret false
                }
            }
            ret true
        }
    }
}
