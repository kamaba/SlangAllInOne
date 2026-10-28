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
    # [2026-10-17] 复盘 ①）；RouteGroup 由 SLang.HttpServer.group() 模块内构造
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

        # ── 多监听器作用域（v1.1）──
        # 0 = 所有监听器可见（app.on* 直注默认语义不变）；N > 0 = 仅监听
        # 器 N 可见（ServerListener.on* 注册时打标——tag 由 HttpServerCore
        # .listen() 分配，主监听器 = 1）
        public Int32 scope = 0

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
        # 请求侧流式（P5，§6.6）：true = 引擎解析到头区空行即停、不预读
        # body，连接 + 预读残留移交 handler——handler 经 req.bodyStream()
        # 取 HttpBodyReader 边读边消费（超大上传不驻留内存）。
        # 消费不完即 handler 返回 → 引擎丢弃式收尾（drain）后按 keep-alive
        # 规则继续；WS 路由无 body 语义，恒 false
        public bool streamBody = false
        # ── 路由级中间件（P10 补齐 P3 裁剪项，§6.9）──
        # 该路由专属中间件（全局之后、handler 之前执行；注册序即执行序）。
        # RouteInfo.use 链式登记 / Router.add(method, path, handler, mws)
        # params 尾参形态批量传入
        List<Function> _mws = null

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
        # 注册序号（树化匹配的同静态段数平局裁决：先注册者优先）
        Int32 _seq = 0
        # 挂载节点反向引用（_remove 定位用；object 持有 + as 转型——
        # public 类字段类型为模块内部类 Front 解析不稳，_WsSessions 纪律）
        object _node = null

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

        # ── 路由级中间件（P10，§6.9）──

        # 链式登记一条路由级中间件（三参 Function(req,res,nx)）：
        # 全局管道之后、本路由 handler 之前执行；注册序即执行序
        public RouteInfo use( Function mw )
        {
            if this._mws == null
            {
                this._mws = new()
            }
            this._mws.add( mw )
            ret this
        }

        # 批量登记（app.onGet(path, fn, mw1, mw2) 尾参便捷形态的落地环）
        # 注意：形参必须用显式数组类型而非 params——SL 的 params 语义是把
        # "逐个多余实参"装箱成数组，没有 C# 式"尾实参为数组则透传"语义；
        # 若声明为 params，调用方把现成数组直传时会被再包一层导致元素遍历失败。
        public RouteInfo useAll( Function[] mws )
        {
            if mws == null
            {
                ret this
            }
            Int32 n = mws.length
            for Int32 i = 0, i < n, i = i + 1
            {
                Function one = mws[i]
                if one != null
                {
                    this.use( one )
                }
            }
            ret this
        }

        # 路由级中间件数（_Pipeline 执行序合并用）
        Int32 _mwCount()
        {
            if this._mws == null
            {
                ret 0
            }
            ret this._mws.length
        }

        # 取第 i 条（越界 null；调用方判空）
        Function _mwAt( Int32 i )
        {
            if this._mws == null
            {
                ret null
            }
            ret this._mws[i]
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

    # ============================================================================
    # _RouteNode — 段前缀树节点（P5 路由匹配优化，§6.2）
    # 树结构：静态边 Map<段,子节点> + 单一参数边（{x} 段共享）+ 通配表
    #   （{x*} 尾段路由挂在"前缀段节点"）；每节点四张路由表：
    #   _routes（HTTP 终止于此）/ _wsRoutes（WS）/ _wild（HTTP 通配）/
    #   _wsWild（WS 通配）。匹配 = DFS 沿段下降收集候选（每层最多静态+
    #   参数两条分支）+ 静态段计数择优（语义与 v1 线性扫描完全一致：
    #   静态段多者优先、同数先注册者优先、HEAD 视同 GET、ANY 全动词）。
    # 语言纪律：Map 值类型用 object + as _RouteNode 转型（自引用泛型
    #   Map<string,_RouteNode> Front 解析失败——_WsSessions 同款规避）。
    # ============================================================================
    class _RouteNode
    {
        # HTTP 路由（pattern 段链终止于此节点）
        List<RouteInfo> _routes = null
        # WS 升级路由
        List<RouteInfo> _wsRoutes = null
        # HTTP 通配路由（{x*}；挂在前缀段节点，吸收剩余全部段）
        List<RouteInfo> _wild = null
        # WS 通配路由
        List<RouteInfo> _wsWild = null
        # 静态边（段字面 → 子节点；object 持有 + as 转型）
        Map<string, object> _static = null
        # 参数边（{x} 段共享一条）
        _RouteNode _param = null

        _init_()
        {
            this._routes = null
            this._wsRoutes = null
            this._wild = null
            this._wsWild = null
            this._static = null
            this._param = null
        }
    }

    public class Router
    {
        # 段前缀树根（P5 树化：替代 v1 线性扫描表；路由数 < 200 的线性
        # 假设仍成立，树化是语义不变的查找优化）
        static _RouteNode _root = null
        # 引擎构造期标志（未 configure 时树未建）
        static bool _ready = false
        # 注册序号发生器（平局裁决：先注册者优先）
        static Int32 _nextSeq = 1

        # ── 初始化 / 清理（HttpServerCore.configure/reset 调用）──

        static void _ensure()
        {
            if _root == null
            {
                _root = _RouteNode()
            }
            _ready = true
        }

        # 清空全部路由（HTTP + WS；stop 后重新配置用）
        public static void clear()
        {
            _root = _RouteNode()
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
            r._seq = _nextSeq
            _nextSeq = _nextSeq + 1
            if shadow != null && shadow.isDocOnly
            {
                r.summary = shadow.summary
                r.tags = shadow.tags
                r.desc = shadow.desc
                r.docParams = shadow.docParams
                r.docForms = shadow.docForms
                r.security = shadow.security
            }
            Router._attach( r, false )
            ret r
        }

        # 路由级中间件形态（P10，§6.9）：Router.add( "GET", path, fn, mw1, mw2 )
        # —— mw 以 params 尾参批量登记（语义 = Router.add(...) 后逐条
        # RouteInfo.use；null 项跳过）。
        # ⚠ 仅适用于"逐个独立实参"传法：SL 的 params 是把多余实参装箱成数组，
        # 没有尾实参数组透传语义——若把现成数组作为第 4 实参传入，收到的
        # mws 会是"长度 1、元素为数组"的嵌套数组导致登记失效；库内门面
        # （HttpServer/RouteGroup on*）已全部改两步调用规避，直传数组请用
        # 三参 add + RouteInfo.useAll(数组)。
        public static RouteInfo add( string method, string pattern, Function handler, params Function[] mws )
        {
            RouteInfo r = Router.add( method, pattern, handler )
            r.useAll( mws )
            ret r
        }

        # 路由挂树（ws = WS 表 / HTTP 表；通配挂前缀节点 wild 表）
        static void _attach( RouteInfo r, bool ws )
        {
            List<string> segs = r._segs
            Int32 n = segs.length
            Int32 depth = n
            if r._wildcardIdx >= 0
            {
                # 通配路由：下降 n-1 段（前缀），挂 wild 表
                depth = n - 1
            }
            _RouteNode node = Router._descendBuild( segs, depth )
            r._node = node
            if r._wildcardIdx >= 0
            {
                # 通配表（HTTP / WS 分表）
                List<RouteInfo> wt = node._wild
                if ws
                {
                    wt = node._wsWild
                }

                if wt == null
                {
                    wt = new()

                    if ws
                    {
                        node._wsWild = wt
                    }
                    else
                    {
                        node._wild = wt
                    }
                }
                wt.add( r )
                ret
            }
            # 精确终止表
            List<RouteInfo> t = node._routes
            if ws
            {
                t = node._wsRoutes
            }

            if t == null
            {
                t = new()

                if ws
                {
                    node._wsRoutes = t
                }
                else
                {
                    node._routes = t
                }
            }
            t.add( r )
        }

        # 下降 depth 段（缺节点即建；静态段走 _static、{x} 走 _param）
        static _RouteNode _descendBuild( List<string> segs, Int32 depth )
        {
            _RouteNode node = _root
            for Int32 i = 0, i < depth, i = i + 1
            {
                string seg = segs[i]
                if Router._isParamSeg( seg )
                {
                    if node._param == null
                    {
                        node._param = _RouteNode()
                    }
                    node = node._param
                }
                else
                {
                    if node._static == null
                    {
                        node._static = new()
                    }

                    if node._static.containsKey( seg ) == false
                    {
                        _RouteNode child = _RouteNode()
                        node._static.add( seg, child )
                    }
                    object cur = node._static[seg]
                    node = cur as _RouteNode
                }
            }
            ret node
        }

        # 精确 (method, pattern) 查找（docs 挂载冲突检测 / importOpenApi
        # 合并判定用；不参与匹配优先级；method 相互或任一为 "ANY" 即命中）
        public static RouteInfo findExact( string method, string pattern )
        {
            if _root == null
            {
                ret null
            }
            RouteInfo r = Router._findInTree( pattern, false )
            if r == null
            {
                ret null
            }

            # method 兼容（原语义）
            if Net.Uri.eqFold( r.method, method )
            {
                ret r
            }

            if Net.Uri.eqFold( r.method, "ANY" ) || Net.Uri.eqFold( method, "ANY" )
            {
                ret r
            }
            ret null
        }

        # 在树中找 pattern 字面相等的 HTTP 路由（首个命中；表内序 = 注册序）
        static RouteInfo _findInTree( string pattern, bool ws )
        {
            List<string> segs = new()
            Router._splitSegments( pattern, segs )
            Int32 n = segs.length
            bool wild = false
            if n > 0
            {
                # 复合索引先拷局部再传参（HttpHeaders 头注记纪律）；
                # 下标禁用算术表达式（segs[n-1] 走 Front _getItem_ 探测
                # 路径报 21340——变量下标走 GetMetaVariableByName 快路，
                # 算术下标是 P5 踩中的 Front 已知坑，拆局部规避）
                Int32 last = n - 1
                string lastSeg = segs[last]
                wild = Router._isWildSeg( lastSeg )
            }
            Int32 depth = n
            if wild
            {
                depth = n - 1
            }
            # 下降现有节点（不建）
            _RouteNode node = _root
            for Int32 i = 0, i < depth, i = i + 1
            {
                string seg = segs[i]
                if Router._isParamSeg( seg )
                {
                    node = node._param
                }
                else
                {
                    if node._static == null
                    {
                        ret null
                    }
                    object cur = node._static[seg]
                    node = cur as _RouteNode
                }

                if node == null
                {
                    ret null
                }
            }
            List<RouteInfo> t = node._routes
            if ws
            {
                t = node._wsRoutes
            }

            if wild
            {
                t = node._wild

                if ws
                {
                    t = node._wsWild
                }
            }

            if t == null
            {
                ret null
            }
            Int32 tn = t.length
            for Int32 i = 0, i < tn, i = i + 1
            {
                # 索引先拷局部再链式取成员（Front 解析纪律）
                RouteInfo rr = t[i]
                if rr.pattern == pattern
                {
                    ret rr
                }
            }
            ret null
        }

        # {x} 参数段判定
        static bool _isParamSeg( string seg )
        {
            Int32 sl = SystemStringLength( seg )
            if sl > 2 && SystemStringCharCodeAt( seg, 0 ) == 123 && SystemStringCharCodeAt( seg, sl - 1 ) == 125
            {
                ret true
            }
            ret false
        }

        # {x*} 通配段判定
        static bool _isWildSeg( string seg )
        {
            Int32 sl = SystemStringLength( seg )
            if sl > 3 && SystemStringCharCodeAt( seg, 0 ) == 123 && SystemStringCharCodeAt( seg, sl - 1 ) == 125 && SystemStringCharCodeAt( seg, sl - 2 ) == 42
            {
                ret true
            }
            ret false
        }

        # 移除一条路由（内部；importOpenApi 覆盖让位用；经节点反向引用定位）
        static void _remove( RouteInfo r )
        {
            object nodeObj = r._node
            _RouteNode node = nodeObj as _RouteNode
            if node == null
            {
                ret
            }
            Int32 i = Router._removeFrom( node._routes, r )
            if i >= 0
            {
                node._routes.removeRange( i, 1 )
                ret
            }
            i = Router._removeFrom( node._wsRoutes, r )
            if i >= 0
            {
                node._wsRoutes.removeRange( i, 1 )
                ret
            }
            i = Router._removeFrom( node._wild, r )
            if i >= 0
            {
                node._wild.removeRange( i, 1 )
                ret
            }
            i = Router._removeFrom( node._wsWild, r )
            if i >= 0
            {
                node._wsWild.removeRange( i, 1 )
                ret
            }
        }

        # 表内定位（-1 未命中）
        static Int32 _removeFrom( List<RouteInfo> t, RouteInfo r )
        {
            if t == null
            {
                ret -1
            }
            Int32 n = t.length
            for Int32 i = 0, i < n, i = i + 1
            {
                RouteInfo cur = t[i]
                if cur == r
                {
                    ret i
                }
            }
            ret -1
        }

        # WS 升级路由注册（pattern 同一套 {param} 语法）
        public static RouteInfo addWs( string pattern, Function handler )
        {
            Router._ensure()
            RouteInfo r = Router._build( "WS", pattern, handler )
            r._seq = _nextSeq
            _nextSeq = _nextSeq + 1
            Router._attach( r, true )
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

        # 候选收集（DFS 沿段下降；每层静态边 + 参数边至多两条分支）：
        #   methodFilter = null 忽略动词（findBest/allowMethods）；否则按
        #   "动词相等或 ANY" 过滤（HEAD→GET 转换由调用方完成）。
        #   depth == 段数 → 收集本节点精确终止表；节点通配表无条件收集
        #   （吸收剩余 ≥ 0 段，§4.2 {path*} 语义）
        static void _collect( _RouteNode node, List<string> segs, Int32 depth, string methodFilter, bool wantWs, Int32 tag, List<RouteInfo> outCands )
        {
            if node == null
            {
                ret
            }
            List<RouteInfo> exact = node._routes
            if wantWs
            {
                exact = node._wsRoutes
            }

            if depth == segs.length && exact != null
            {
                Int32 n = exact.length
                for Int32 i = 0, i < n, i = i + 1
                {
                    RouteInfo r = exact[i]
                    if Router._methodOk( r, methodFilter ) && Router._scopeOk( r, tag )
                    {
                        outCands.add( r )
                    }
                }
            }
            # 通配表（挂在前缀节点；剩余段全归通配，0 段亦可）
            List<RouteInfo> wilds = node._wild
            if wantWs
            {
                wilds = node._wsWild
            }

            if wilds != null
            {
                Int32 wn = wilds.length
                for Int32 i = 0, i < wn, i = i + 1
                {
                    RouteInfo r = wilds[i]
                    if Router._methodOk( r, methodFilter ) && Router._scopeOk( r, tag )
                    {
                        outCands.add( r )
                    }
                }
            }

            # 下探（还有剩余段）
            if depth < segs.length
            {
                if node._static != null
                {
                    # 复合索引先拷局部再作 Map 键（HttpHeaders 头注记纪律）
                    string segHere = segs[depth]
                    object cur = node._static[segHere]
                    _RouteNode child = cur as _RouteNode
                    if child != null
                    {
                        Router._collect( child, segs, depth + 1, methodFilter, wantWs, tag, outCands )
                    }
                }

                if node._param != null
                {
                    Router._collect( node._param, segs, depth + 1, methodFilter, wantWs, tag, outCands )
                }
            }
        }

        # 监听器作用域过滤（多监听器 v1.1）：scope 0 = 全局可见；N > 0 仅 tag N
        static bool _scopeOk( RouteInfo r, Int32 tag )
        {
            if r.scope == 0
            {
                ret true
            }

            if r.scope == tag
            {
                ret true
            }
            ret false
        }

        # 动词过滤（methodFilter null = 全过）
        static bool _methodOk( RouteInfo r, string methodFilter )
        {
            if methodFilter == null
            {
                ret true
            }

            if Net.Uri.eqFold( r.method, methodFilter )
            {
                ret true
            }

            if Net.Uri.eqFold( r.method, "ANY" )
            {
                ret true
            }
            ret false
        }

        # 候选择优（静态段多者优先；同数先注册者优先——seq 升序）。
        # 多监听器 v1.1：同静态段数平局时，本监听器专属路由（scope==tag
        # 且非 0）优先于全局路由（scope 0）——listener 视图覆盖全局同名。
        static RouteInfo _pickBest( List<RouteInfo> cands, Int32 tag )
        {
            RouteInfo best = null
            Int32 n = cands.length
            for Int32 i = 0, i < n, i = i + 1
            {
                RouteInfo r = cands[i]
                if best == null
                {
                    best = r
                }
                elif r._staticCount > best._staticCount
                {
                    best = r
                }
                elif r._staticCount == best._staticCount
                {
                    bool rHit = false
                    bool bHit = false
                    if r.scope != 0 && r.scope == tag
                    {
                        rHit = true
                    }

                    if best.scope != 0 && best.scope == tag
                    {
                        bHit = true
                    }
                    bool take = false
                    if rHit && bHit == false
                    {
                        take = true
                    }
                    elif rHit == false && bHit == false && r._seq < best._seq
                    {
                        take = true
                    }
                    elif rHit && bHit && r._seq < best._seq
                    {
                        take = true
                    }

                    if take
                    {
                        best = r
                    }
                }
            }
            ret best
        }

        # HTTP 匹配（HEAD 视同 GET；ANY 全动词）；命中者中按静态段多者优先
        # （§4.2 精确段 > 参数段；同数先注册者优先）；无命中返回 null
        # （404/405 区分由 findBest：路径有注册但动词不符 → findBest 非空 → 405）
        public static RouteInfo match( string method, string path )
        {
            ret Router.match( method, path, 0 )
        }

        # 带 tag 形态（多监听器 v1.1；tag = 连接所在监听器，0 兼容旧语义
        # —— scope 0 全局路由全部可见）
        public static RouteInfo match( string method, string path, Int32 tag )
        {
            if _root == null
            {
                ret null
            }
            string lookup = method
            if Net.Uri.eqFold( method, "HEAD" )
            {
                lookup = "GET"
            }
            List<string> segs = new()
            Router._splitSegments( path, segs )
            List<RouteInfo> cands = new()
            Router._collect( _root, segs, 0, lookup, false, tag, cands )
            ret Router._pickBest( cands, tag )
        }

        # 路径最优命中（忽略动词；405 判定与 Allow 头生成用）：
        # 静态段多者优先、同数先注册者优先
        public static RouteInfo findBest( string path )
        {
            ret Router.findBest( path, 0 )
        }

        public static RouteInfo findBest( string path, Int32 tag )
        {
            if _root == null
            {
                ret null
            }
            List<string> segs = new()
            Router._splitSegments( path, segs )
            List<RouteInfo> cands = new()
            Router._collect( _root, segs, 0, null, false, tag, cands )
            ret Router._pickBest( cands, tag )
        }

        # 全部 HTTP 路由快照（Docs.openApiJson / importOpenApi 遍历用；
        # 树遍历收集 HTTP 精确表 + 通配表，注册序不定——消费方 Map 语义
        # 无顺序依赖）
        public static List<RouteInfo> allRoutes()
        {
            List<RouteInfo> outList = new()
            if _root != null
            {
                Router._gather( _root, outList )
            }
            ret outList
        }

        # 树遍历收集（HTTP 表：_routes + _wild；WS 表跳过）
        static void _gather( _RouteNode node, List<RouteInfo> outList )
        {
            if node._routes != null
            {
                Int32 n = node._routes.length
                for Int32 i = 0, i < n, i = i + 1
                {
                    RouteInfo r = node._routes[i]
                    outList.add( r )
                }
            }

            if node._wild != null
            {
                Int32 wn = node._wild.length
                for Int32 i = 0, i < wn, i = i + 1
                {
                    RouteInfo r = node._wild[i]
                    outList.add( r )
                }
            }

            if node._static != null
            {
                List<string> ks = node._static.keys
                Int32 kn = ks.length
                for Int32 i = 0, i < kn, i = i + 1
                {
                    string ck = ks[i]
                    object cur = node._static[ck]
                    _RouteNode child = cur as _RouteNode
                    Router._gather( child, outList )
                }
            }

            if node._param != null
            {
                Router._gather( node._param, outList )
            }
        }

        # 该路径已注册的全部动词（405 Allow 头用；逗号分隔；ANY 展开全表）
        public static string allowMethods( string path )
        {
            ret Router.allowMethods( path, 0 )
        }

        public static string allowMethods( string path, Int32 tag )
        {
            if _root == null
            {
                ret ""
            }
            List<string> segs = new()
            Router._splitSegments( path, segs )
            List<RouteInfo> cands = new()
            Router._collect( _root, segs, 0, null, false, tag, cands )
            string allow = ""
            Int32 n = cands.length
            for Int32 i = 0, i < n, i = i + 1
            {
                RouteInfo r = cands[i]
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
            ret allow
        }

        # WS 路由匹配（仅路径；静态段优先 + 先注册者优先；无命中返回
        # null → 引擎 400）
        public static RouteInfo findWs( string path )
        {
            ret Router.findWs( path, 0 )
        }

        public static RouteInfo findWs( string path, Int32 tag )
        {
            if _root == null
            {
                ret null
            }
            List<string> segs = new()
            Router._splitSegments( path, segs )
            List<RouteInfo> cands = new()
            Router._collect( _root, segs, 0, null, true, tag, cands )
            ret Router._pickBest( cands, tag )
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
        # 的 pattern 描述（调用方抛 ServerError.DuplicateRoute）；无重复返回 null。
        # 树化等价性：同 pattern 的路由段链确定 → 必挂同一节点 → 节点内
        # 双循环即全表按 (method, pattern) 分组的完整比较。
        # 多监听器 v1.1：同 (method, pattern) 但 scope 不同（全局 vs 各
        # 监听器专属）不算重复——不同端口的同名路径各自独立。
        public static string checkDuplicate()
        {
            if _root == null
            {
                ret null
            }
            ret Router._dupScan( _root )
        }

        # 节点递归扫描（节点四表内双循环 + 子树递归）
        static string _dupScan( _RouteNode node )
        {
            # HTTP 精确表：同 (method, pattern, scope)
            if node._routes != null
            {
                Int32 n = node._routes.length
                for Int32 i = 0, i < n, i = i + 1
                {
                    RouteInfo a = node._routes[i]
                    for Int32 k = i + 1, k < n, k = k + 1
                    {
                        RouteInfo b = node._routes[k]
                        if Net.Uri.eqFold( a.method, b.method ) && a.pattern == b.pattern && a.scope == b.scope
                        {
                            ret a.method + " " + a.pattern
                        }
                    }
                }
            }

            # WS 表：同 (pattern, scope)
            if node._wsRoutes != null
            {
                Int32 wn = node._wsRoutes.length
                for Int32 i = 0, i < wn, i = i + 1
                {
                    RouteInfo a = node._wsRoutes[i]
                    for Int32 k = i + 1, k < wn, k = k + 1
                    {
                        RouteInfo b = node._wsRoutes[k]
                        if a.pattern == b.pattern && a.scope == b.scope
                        {
                            ret "WS " + a.pattern
                        }
                    }
                }
            }

            # 通配表（同上两两比较）
            if node._wild != null
            {
                Int32 vn = node._wild.length
                for Int32 i = 0, i < vn, i = i + 1
                {
                    RouteInfo a = node._wild[i]
                    for Int32 k = i + 1, k < vn, k = k + 1
                    {
                        RouteInfo b = node._wild[k]
                        if Net.Uri.eqFold( a.method, b.method ) && a.pattern == b.pattern && a.scope == b.scope
                        {
                            ret a.method + " " + a.pattern
                        }
                    }
                }
            }

            if node._wsWild != null
            {
                Int32 xw = node._wsWild.length
                for Int32 i = 0, i < xw, i = i + 1
                {
                    RouteInfo a = node._wsWild[i]
                    for Int32 k = i + 1, k < xw, k = k + 1
                    {
                        RouteInfo b = node._wsWild[k]
                        if a.pattern == b.pattern && a.scope == b.scope
                        {
                            ret "WS " + a.pattern
                        }
                    }
                }
            }

            # 子树递归（静态边全部 + 参数边）
            if node._static != null
            {
                List<string> ks = node._static.keys
                Int32 kn = ks.length
                for Int32 i = 0, i < kn, i = i + 1
                {
                    # 复合索引先拷局部再作 Map 键（HttpHeaders 头注记纪律）
                    string ck = ks[i]
                    object cur = node._static[ck]
                    _RouteNode child = cur as _RouteNode
                    string d = Router._dupScan( child )
                    if d != null
                    {
                        ret d
                    }
                }
            }

            if node._param != null
            {
                string dp = Router._dupScan( node._param )
                if dp != null
                {
                    ret dp
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
    }

    # ============================================================================
    # RouteGroup — 前缀分组（Spring @RequestMapping 形态；§4.2）
    # 由 SLang.HttpServer.group() 构造（模块内 new，HttpResponse 安全模式）；
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

        # 路由级中间件形态（P10，§6.9）
        public RouteInfo onGet( string path, Function handler, params Function[] mws )
        {
            RouteInfo r = Router.add( "GET", this._join( path ), handler )
            ret r.useAll( mws )
        }

        public RouteInfo onPost( string path, Function handler )
        {
            ret Router.add( "POST", this._join( path ), handler )
        }

        public RouteInfo onPost( string path, Function handler, params Function[] mws )
        {
            RouteInfo r = Router.add( "POST", this._join( path ), handler )
            ret r.useAll( mws )
        }

        public RouteInfo onPut( string path, Function handler )
        {
            ret Router.add( "PUT", this._join( path ), handler )
        }

        public RouteInfo onPut( string path, Function handler, params Function[] mws )
        {
            RouteInfo r = Router.add( "PUT", this._join( path ), handler )
            ret r.useAll( mws )
        }

        public RouteInfo onDelete( string path, Function handler )
        {
            ret Router.add( "DELETE", this._join( path ), handler )
        }

        public RouteInfo onDelete( string path, Function handler, params Function[] mws )
        {
            RouteInfo r = Router.add( "DELETE", this._join( path ), handler )
            ret r.useAll( mws )
        }

        public RouteInfo onPatch( string path, Function handler )
        {
            ret Router.add( "PATCH", this._join( path ), handler )
        }

        public RouteInfo onPatch( string path, Function handler, params Function[] mws )
        {
            RouteInfo r = Router.add( "PATCH", this._join( path ), handler )
            ret r.useAll( mws )
        }

        public RouteInfo onAny( string path, Function handler )
        {
            ret Router.add( "ANY", this._join( path ), handler )
        }

        public RouteInfo onAny( string path, Function handler, params Function[] mws )
        {
            RouteInfo r = Router.add( "ANY", this._join( path ), handler )
            ret r.useAll( mws )
        }

        # 原始形式（动态注册 / 方法变量）
        public RouteInfo on( string method, string path, Function handler )
        {
            ret Router.add( method, this._join( path ), handler )
        }

        # 原始形式 + 路由级中间件（P10 params 尾参形态）
        public RouteInfo on( string method, string path, Function handler, params Function[] mws )
        {
            RouteInfo r = Router.add( method, this._join( path ), handler )
            ret r.useAll( mws )
        }

        # WS 升级路由（组内前缀）
        public RouteInfo websocket( string path, Function handler )
        {
            ret Router.addWs( this._join( path ), handler )
        }
    }
}
