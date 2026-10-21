import Std;
import Core;

namespace SLang
{
    # ============================================================================
    # SLang/Server/Router.sl — 路由器（P1）
    # 设计契约：SERVER_DESIGN.md §4.2 / §6.2
    #
    # 匹配规则：pattern 按 '/' 拆段；{name} 段匹配任意非空单段并捕获；
    #   优先级 = 精确段 > 参数段（静态段多者优先，同数先注册者优先）；
    #   HEAD 视同 GET；method "ANY" 接受全部动词；
    #   判定序：路径命中但动词不符 → 405（+Allow）；全无匹配 → 404；
    #   冲突检测：start() 时对 (method, pattern) 去重（ServerError.DuplicateRoute）。
    # WS 路由共用同一套 {param} 语法（§4.6 s.pathParam）。
    # 形态：Router/RouteInfo 均为静态/模块内构造（跨模块多实例化隔离不可靠，
    # [2026-10-17] 复盘 ①）；RouteGroup 由 SLang.Server.group() 模块内构造
    # （HttpResponse 同款安全模式），实例方法只做前缀拼接转发。
    # ============================================================================

    # 路由记录（模块内构造；字段公开可读写——文档元数据 P3 扩展位）
    public class RouteInfo
    {
        # "GET"/"POST"... 或 "ANY"（全动词）/ "WS"（WebSocket 升级路由）
        public string method = ""
        # 原始 pattern（如 "/api/user/{id}"）
        public string pattern = ""
        # 处理器（HTTP 双参 Function(req,res)；WS 单参 Function(session)）
        public Function handler = null
        # ── 文档元数据（P3 OpenApi 消费；字段直写）──
        public string summary = ""
        public string tags = ""
        public string desc = ""

        # ── 文档元数据（P3，结构化；经链式方法登记，§4.8）──
        # path/query 参数表（kind="param"）
        public List<RouteParam> docParams = null
        # form 字段表（kind="form"）+ multipart 文件字段表（kind="file"）
        public List<RouteParam> docForms = null
        # requestBody JSON 样例（BaseJson.fromData 序列化文本；空串 = 无）
        public string docBodyText = ""
        # requestBody 样例类名（components.schemas 键；空串 = 内联不登记）
        public string docBodyClass = ""
        # 响应样例表（状态码 → 样例文本 + 类名 + mediaType）
        public List<RouteResp> docResponses = null
        # 认证要求（"bearerAuth" / "apiKeyAuth"；空串 = 无；§4.11）
        public string security = ""
        # 文档路由（importOpenApi 登记；命中 501；被真实注册覆盖时自动让位）
        public bool isDocOnly = false
        # 内置路由（/docs、/openapi.json；冲突检测豁免 + 不进 openapi.json）
        public bool isBuiltin = false

        # ── 匹配预编译（模块内部）──
        List<string> _segs = null
        List<string> _paramNames = null
        # 参数段在 _segs 中的下标（extractParams 对位用：第 k 个参数名取
        # 路径 _paramSegIdx[k] 段，勿按参数序号直取路径段——/a/{x}/{y} 中
        # 参数 0 在路径段 1）
        List<Int32> _paramSegIdx = null
        Int32 _staticCount = 0
        bool _hasParams = false
        # 通配段（P2，§4.2：{path*} 尾段匹配剩余全部段；仅识别最后一段）
        string _wildcardName = ""
        Int32 _wildcardIdx = -1

        # ── 文档元数据链式登记（§4.8：返回自身可链式）──

        # path/query 参数：type = "integer"/"string"/"boolean"...
        public RouteInfo param( string name, string type, string desc, bool required )
        {
            if this.docParams == null
            {
                this.docParams = new()
            }
            RouteParam p = RouteParam()
            p.name = name
            p.type = type
            p.desc = desc
            p.required = required
            this.docParams.add( p )
            ret this
        }

        # JSON body 样例（样例实例 → 探针法 schema；§6.10）
        public RouteInfo requestBody( object sample )
        {
            BaseJson j = BaseJson.fromData( sample )
            this.docBodyText = j.toJson()
            this.docBodyClass = Docs._typeNameOf( sample )
            ret this
        }

        # form 字段（urlencoded requestBody schema；§4.8）
        public RouteInfo formField( string name, string desc )
        {
            if this.docForms == null
            {
                this.docForms = new()
            }
            RouteParam p = RouteParam()
            p.name = name
            p.kind = "form"
            p.desc = desc
            this.docForms.add( p )
            ret this
        }

        # multipart 文件字段（requestBody multipart/form-data；§4.8）
        public RouteInfo uploadField( string name, string desc, string mime )
        {
            if this.docForms == null
            {
                this.docForms = new()
            }
            RouteParam p = RouteParam()
            p.name = name
            p.kind = "file"
            p.desc = desc
            p.mime = mime
            this.docForms.add( p )
            ret this
        }

        # 响应样例（状态码 + 样例实例；mediaType 缺省 application/json，
        # text/event-stream 等流式响应显式传）
        public RouteInfo response( Int32 status, object sample )
        {
            ret this.responseAs( status, sample, "application/json" )
        }

        public RouteInfo responseAs( Int32 status, object sample, string mediaType )
        {
            if this.docResponses == null
            {
                this.docResponses = new()
            }
            RouteResp rr = RouteResp()
            rr.status = status
            rr.mediaType = mediaType
            if sample != null
            {
                BaseJson j = BaseJson.fromData( sample )
                rr.sampleText = j.toJson()
                rr.sampleClass = Docs._typeNameOf( sample )
            }
            this.docResponses.add( rr )
            ret this
        }

        # 认证要求（"bearerAuth" / "apiKeyAuth"；§4.11 / §6.10）
        public RouteInfo security( string scheme )
        {
            this.security = scheme
            ret this
        }
    }

    # 文档参数/字段记录（P3；RouteInfo 结构化元数据）
    public class RouteParam
    {
        public string name = ""
        # "integer" / "string" / "boolean" ...（param 专用）
        public string type = ""
        public string desc = ""
        public bool required = false
        # "param"（path/query）/ "form"（urlencoded 字段）/ "file"（multipart 文件）
        public string kind = "param"
        # file 专用：接受类型（如 "image/*"）
        public string mime = ""

        _init_()
        {
            this.name = ""
            this.type = ""
            this.desc = ""
            this.required = false
            this.kind = "param"
            this.mime = ""
        }
    }

    # 文档响应记录（P3；状态码 + 样例文本 + 类名 + mediaType）
    public class RouteResp
    {
        public Int32 status = 200
        public string sampleText = ""
        public string sampleClass = ""
        public string mediaType = "application/json"

        _init_()
        {
            this.status = 200
            this.sampleText = ""
            this.sampleClass = ""
            this.mediaType = "application/json"
        }
    }

    public class Router
    {
        # HTTP 路由表（线性扫描；v1 规模假设 < 200 条，前缀树为 P5 优化项）
        static List<RouteInfo> _routes = null
        # WS 升级路由表
        static List<RouteInfo> _wsRoutes = null
        # 引擎构造期标志（未 configure 时表未建）
        static bool _ready = false

        # ── 初始化 / 清理（HttpServerCore.configure/reset 调用）──

        static void _ensure()
        {
            if _routes == null
            {
                _routes = new()
            }
            if _wsRoutes == null
            {
                _wsRoutes = new()
            }
            _ready = true
        }

        # 清空全部路由（HTTP + WS；stop 后重新配置用）
        public static void clear()
        {
            _routes = new()
            _wsRoutes = new()
        }

        # ── 注册 ──

        # HTTP 路由注册（method 大小写不敏感；"ANY" 全动词）；返回 RouteInfo
        #（文档元数据可链式后写：r = Router.add(...); r.summary = "..."）
        # P3：同 (method, pattern) 已存在**文档路由**（importOpenApi 501 登记）
        # 时自动让位——新真实路由继承其文档元数据后顶替（§4.8 覆盖工作流）
        public static RouteInfo add( string method, string pattern, Function handler )
        {
            Router._ensure()
            RouteInfo shadow = Router.findExact( method, pattern )
            if shadow != null && shadow.isDocOnly
            {
                Router._remove( shadow )
            }
            RouteInfo r = Router._build( method, pattern, handler )
            if shadow != null && shadow.isDocOnly
            {
                r.summary = shadow.summary
                r.tags = shadow.tags
                r.desc = shadow.desc
                r.docParams = shadow.docParams
                r.docForms = shadow.docForms
                r.security = shadow.security
            }
            _routes.add( r )
            ret r
        }

        # 精确 (method, pattern) 查找（docs 挂载冲突检测 / importOpenApi
        # 合并判定用；不参与匹配优先级；method 相互或任一为 "ANY" 即命中）
        public static RouteInfo findExact( string method, string pattern )
        {
            Int32 n = _routes.length
            for Int32 i = 0, i < n, i = i + 1
            {
                RouteInfo r = _routes[i]
                if Net.Uri.eqFold( r.pattern, pattern )
                {
                    if Net.Uri.eqFold( r.method, method )
                    {
                        ret r
                    }

                    if Net.Uri.eqFold( r.method, "ANY" ) || Net.Uri.eqFold( method, "ANY" )
                    {
                        ret r
                    }
                }
            }
            ret null
        }

        # 移除一条路由（内部；importOpenApi 覆盖让位用）
        static void _remove( RouteInfo r )
        {
            Int32 n = _routes.length
            for Int32 i = 0, i < n, i = i + 1
            {
                if _routes[i] == r
                {
                    _routes.removeRange( i, 1 )
                    ret
                }
            }
        }

        # WS 升级路由注册（pattern 同一套 {param} 语法）
        public static RouteInfo addWs( string pattern, Function handler )
        {
            Router._ensure()
            RouteInfo r = Router._build( "WS", pattern, handler )
            _wsRoutes.add( r )
            ret r
        }

        # 注册项预编译：段拆分 + 参数名提取 + 静态段计数 + 通配段识别
        static RouteInfo _build( string method, string pattern, Function handler )
        {
            RouteInfo r = RouteInfo()
            r.method = method
            r.pattern = pattern
            r.handler = handler
            r._segs = new()
            r._paramNames = new()
            r._paramSegIdx = new()
            r._staticCount = 0
            r._hasParams = false
            r._wildcardName = ""
            r._wildcardIdx = -1
            Router._splitSegments( pattern, r._segs )
            Int32 n = r._segs.length
            for Int32 i = 0, i < n, i = i + 1
            {
                string seg = r._segs[i]
                Int32 sl = SystemStringLength( seg )
                # 通配段 {name*}：仅最后一段识别（匹配剩余全部段，P2 §4.2）
                if i == n - 1 && sl > 3 && SystemStringCharCodeAt( seg, 0 ) == 123 && SystemStringCharCodeAt( seg, sl - 1 ) == 125 && SystemStringCharCodeAt( seg, sl - 2 ) == 42
                {
                    r._wildcardName = SystemStringRange( seg, 1, sl - 2 )
                    r._wildcardIdx = i
                    r._hasParams = true
                }
                elif sl > 2 && SystemStringCharCodeAt( seg, 0 ) == 123 && SystemStringCharCodeAt( seg, sl - 1 ) == 125
                {
                    # {name} 参数段
                    r._paramNames.add( SystemStringRange( seg, 1, sl - 1 ) )
                    r._paramSegIdx.add( i )
                    r._hasParams = true
                }
                else
                {
                    r._staticCount = r._staticCount + 1
                }
            }
            ret r
        }

        # ── 匹配 ──

        # HTTP 匹配（HEAD 视同 GET；ANY 全动词）；命中者中按静态段多者优先
        # （§4.2 精确段 > 参数段；同数先注册者优先）；无命中返回 null
        # （404/405 区分由 findBest：路径有注册但动词不符 → findBest 非空 → 405）
        public static RouteInfo match( string method, string path )
        {
            string lookup = method
            if Net.Uri.eqFold( method, "HEAD" )
            {
                lookup = "GET"
            }
            RouteInfo best = null
            Int32 bestStatic = 0 - 1
            Int32 n = _routes.length
            for Int32 i = 0, i < n, i = i + 1
            {
                RouteInfo r = _routes[i]
                if Net.Uri.eqFold( r.method, lookup ) || Net.Uri.eqFold( r.method, "ANY" )
                {
                    if Router._matchPattern( r, path )
                    {
                        if r._staticCount > bestStatic
                        {
                            best = r
                            bestStatic = r._staticCount
                        }
                    }
                }
            }
            ret best
        }

        # 路径最优命中（忽略动词；405 判定与 Allow 头生成用）：
        # 静态段多者优先、同数先注册者优先
        public static RouteInfo findBest( string path )
        {
            RouteInfo best = null
            Int32 bestStatic = 0 - 1
            Int32 n = _routes.length
            for Int32 i = 0, i < n, i = i + 1
            {
                RouteInfo r = _routes[i]
                if Router._matchPattern( r, path )
                {
                    if r._staticCount > bestStatic
                    {
                        best = r
                        bestStatic = r._staticCount
                    }
                }
            }
            ret best
        }

        # 该路径已注册的全部动词（405 Allow 头用；逗号分隔；ANY 展开全表）
        public static string allowMethods( string path )
        {
            string allow = ""
            Int32 n = _routes.length
            for Int32 i = 0, i < n, i = i + 1
            {
                RouteInfo r = _routes[i]
                if Router._matchPattern( r, path )
                {
                    if Net.Uri.eqFold( r.method, "ANY" )
                    {
                        ret "GET, POST, PUT, DELETE, PATCH, HEAD, OPTIONS"
                    }
                    if SystemStringLength( allow ) > 0
                    {
                        allow = allow + ", "
                    }
                    allow = allow + r.method
                }
            }
            ret allow
        }

        # WS 路由匹配（仅路径；无命中返回 null → 引擎 400）
        public static RouteInfo findWs( string path )
        {
            Int32 n = _wsRoutes.length
            for Int32 i = 0, i < n, i = i + 1
            {
                RouteInfo r = _wsRoutes[i]
                if Router._matchPattern( r, path )
                {
                    ret r
                }
            }
            ret null
        }

        # 提取路径参数（route 命中 path 后调用；无参数路由返回空 Map；
        # 通配段 {name*} → 剩余段以 '/' 连接，可为空串）
        public static Map<string,string> extractParams( RouteInfo route, string path )
        {
            Map<string,string> m = new()
            if route == null || route._hasParams == false
            {
                ret m
            }
            List<string> segs = new()
            Router._splitSegments( path, segs )
            Int32 pn = route._paramNames.length
            Int32 sn = segs.length
            for Int32 i = 0, i < pn, i = i + 1
            {
                string name = route._paramNames[i]
                Int32 segIdx = route._paramSegIdx[i]
                string sv = ""
                if segIdx < sn
                {
                    sv = segs[segIdx]
                }
                if segIdx < sn
                {
                    m[name] = sv
                }
            }
            if route._wildcardIdx >= 0
            {
                # 通配段：剩余段 '/' 连接（0 段 = 空串）
                string joined = ""
                for Int32 i = route._wildcardIdx, i < sn, i = i + 1
                {
                    if SystemStringLength( joined ) > 0
                    {
                        joined = joined + "/"
                    }
                    joined = joined + segs[i]
                }
                m[route._wildcardName] = joined
            }
            ret m
        }

        # 冲突检测（start() 调用）：同 method+pattern 重复注册返回首个重复
        # 的 pattern 描述（调用方抛 ServerError.DuplicateRoute）；无重复返回 null
        public static string checkDuplicate()
        {
            Int32 n = _routes.length
            for Int32 i = 0, i < n, i = i + 1
            {
                RouteInfo a = _routes[i]
                for Int32 k = i + 1, k < n, k = k + 1
                {
                    RouteInfo b = _routes[k]
                    if Net.Uri.eqFold( a.method, b.method ) && a.pattern == b.pattern
                    {
                        ret a.method + " " + a.pattern
                    }
                }
            }
            Int32 wn = _wsRoutes.length
            for Int32 i = 0, i < wn, i = i + 1
            {
                RouteInfo a = _wsRoutes[i]
                for Int32 k = i + 1, k < wn, k = k + 1
                {
                    RouteInfo b = _wsRoutes[k]
                    if a.pattern == b.pattern
                    {
                        ret "WS " + a.pattern
                    }
                }
            }
            ret null
        }

        # ── 内部：段拆分与模式匹配 ──

        # pattern/path 按 '/' 拆段（空串/仅 '/' → 空表；不产生空段）
        static void _splitSegments( string path, List<string> outSegs )
        {
            Int32 len = SystemStringLength( path )
            Int32 start = -1
            for Int32 i = 0, i <= len, i = i + 1
            {
                if i == len || SystemStringCharCodeAt( path, i ) == 47
                {
                    if start >= 0 && i > start
                    {
                        outSegs.add( SystemStringRange( path, start, i ) )
                    }
                    start = -1
                }
                elif start < 0
                {
                    start = i
                }
            }
        }

        # 段数一致 + 逐段匹配（{param} 匹配任意非空单段；字面段精确相等；
        # {name*} 通配尾段：pn >= rn-1 即命中——通配段吸收剩余全部段，可为空）
        static bool _matchPattern( RouteInfo route, string path )
        {
            if route == null
            {
                ret false
            }
            List<string> segs = new()
            Router._splitSegments( path, segs )
            Int32 rn = route._segs.length
            Int32 pn = segs.length
            if route._wildcardIdx >= 0
            {
                # 通配路由：前 rn-1 段逐一匹配，剩余全归通配段（≥0 段）
                if pn < rn - 1
                {
                    ret false
                }
                for Int32 i = 0, i < rn - 1, i = i + 1
                {
                    # 静态调用实参先提取局部变量（复合表达式传参匹配
                    # NotFound——HttpHeaders 头注记纪律）
                    string want = route._segs[i]
                    string got = segs[i]
                    if Router._segMatch( want, got ) == false
                    {
                        ret false
                    }
                }
                ret true
            }
            if rn != pn
            {
                ret false
            }
            for Int32 i = 0, i < rn, i = i + 1
            {
                string want = route._segs[i]
                string got = segs[i]
                if Router._segMatch( want, got ) == false
                {
                    ret false
                }
            }
            ret true
        }

        # 单段匹配：{param} 非空即命中；字面段精确相等
        static bool _segMatch( string want, string got )
        {
            Int32 wl = SystemStringLength( want )
            if wl > 2 && SystemStringCharCodeAt( want, 0 ) == 123 && SystemStringCharCodeAt( want, wl - 1 ) == 125
            {
                ret SystemStringLength( got ) > 0
            }
            ret want == got
        }
    }

    # ============================================================================
    # RouteGroup — 前缀分组（Spring @RequestMapping 形态；§4.2）
    # 由 SLang.Server.group() 构造（模块内 new，HttpResponse 安全模式）；
    # 实例方法只做前缀拼接后转发 Router.add。
    # ============================================================================
    public class RouteGroup
    {
        string _prefix = ""

        _init_( string prefix )
        {
            # 规范化：确保前缀以 '/' 起始、不以 '/' 结尾（拼接免二次处理）
            string p = prefix
            if p == null
            {
                p = ""
            }
            if SystemStringLength( p ) == 0
            {
                p = "/"
            }
            if SystemStringCharCodeAt( p, 0 ) != 47
            {
                p = "/" + p
            }
            Int32 plen = SystemStringLength( p )
            if plen > 1 && SystemStringCharCodeAt( p, plen - 1 ) == 47
            {
                p = SystemStringRange( p, 0, plen - 1 )
            }
            this._prefix = p
        }

        # 前缀 + 子路径（子路径不以 '/' 起始时自动补；"/" 子路径 = 裸前缀）
        string _join( string path )
        {
            if path == null || SystemStringLength( path ) == 0 || path == "/"
            {
                ret this._prefix
            }
            if SystemStringCharCodeAt( path, 0 ) == 47
            {
                ret this._prefix + path
            }
            ret this._prefix + "/" + path
        }

        public RouteInfo onGet( string path, Function handler )
        {
            ret Router.add( "GET", this._join( path ), handler )
        }

        public RouteInfo onPost( string path, Function handler )
        {
            ret Router.add( "POST", this._join( path ), handler )
        }

        public RouteInfo onPut( string path, Function handler )
        {
            ret Router.add( "PUT", this._join( path ), handler )
        }

        public RouteInfo onDelete( string path, Function handler )
        {
            ret Router.add( "DELETE", this._join( path ), handler )
        }

        public RouteInfo onPatch( string path, Function handler )
        {
            ret Router.add( "PATCH", this._join( path ), handler )
        }

        public RouteInfo onAny( string path, Function handler )
        {
            ret Router.add( "ANY", this._join( path ), handler )
        }

        # 原始形式（动态注册 / 方法变量）
        public RouteInfo on( string method, string path, Function handler )
        {
            ret Router.add( method, this._join( path ), handler )
        }

        # WS 升级路由（组内前缀）
        public RouteInfo websocket( string path, Function handler )
        {
            ret Router.addWs( this._join( path ), handler )
        }
    }
}
