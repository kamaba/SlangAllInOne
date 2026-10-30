# Router.sl

> 源文件：`Router.sl`

## class `RouteInfo`

- **说明**：SLang/Server/Router.sl — 路由器（P1） 设计契约：SERVER_DESIGN.md §4.2 / §6.2 匹配规则：pattern 按 '/' 拆段；{name} 段匹配任意非空单段并捕获； 优先级 = 精确段 > 参数段（静态段多者优先，同数先注册者优先）； HEAD 视同 GET；method "ANY" 接受全部动词； 判定序：路径命中但动词不符 → 405（+Allow）；全无匹配 → 404； 冲突检测：start() 时对 (method, pattern) 去重（ServerError.DuplicateRoute）。 WS 路由共用同一套 {param} 语法（§4.6 s.pathParam）。 形态：Router/RouteInfo 均为静态/模块内构造（跨模块多实例化隔离不可靠， [2026-10-17] 复盘 ①）；RouteGroup 由 SLang.HttpServer.group() 模块内构造 （HttpResponse 同款安全模式），实例方法只做前缀拼接转发。 路由记录（模块内构造；字段公开可读写——文档元数据 P3 扩展位）

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `public string method = ""` | "GET"/"POST"... 或 "ANY"（全动词）/ "WS"（WebSocket 升级路由） |
| 字段 | `public string pattern = ""` | 原始 pattern（如 "/api/user/{id}"） |
| 字段 | `public Function handler = null` | 处理器（HTTP 双参 Function(req,res)；WS 单参 Function(session)） |
| 字段 | `public string summary = ""` | ── 文档元数据（P3 OpenApi 消费；字段直写）── |
| 字段 | `public string tags = ""` | 字段 string（类型见签名）。 |
| 字段 | `public string desc = ""` | 字段 string（类型见签名）。 |
| 字段 | `public Int32 scope = 0` | ── 多监听器作用域（v1.1）── 0 = 所有监听器可见（app.on* 直注默认语义不变）；N &gt; 0 = 仅监听 器 N 可见（ServerListener.on* 注册时打标——tag 由 HttpServerCore .listen() 分配，主监听器 = 1） |
| 字段 | `public List&lt;RouteParam&gt; docParams = null` | ── 文档元数据（P3，结构化；经链式方法登记，§4.8）── path/query 参数表（kind="param"） |
| 字段 | `public List&lt;RouteParam&gt; docForms = null` | form 字段表（kind="form"）+ multipart 文件字段表（kind="file"） |
| 字段 | `public string docBodyText = ""` | requestBody JSON 样例（BaseJson.fromData 序列化文本；空串 = 无） |
| 字段 | `public string docBodyClass = ""` | requestBody 样例类名（components.schemas 键；空串 = 内联不登记） |
| 字段 | `public List&lt;RouteResp&gt; docResponses = null` | 响应样例表（状态码 → 样例文本 + 类名 + mediaType） |
| 字段 | `public string security = ""` | 认证要求（"bearerAuth" / "apiKeyAuth"；空串 = 无；§4.11） |
| 字段 | `public bool isDocOnly = false` | 文档路由（importOpenApi 登记；命中 501；被真实注册覆盖时自动让位） |
| 字段 | `public bool isBuiltin = false` | 内置路由（/docs、/openapi.json；冲突检测豁免 + 不进 openapi.json） |
| 字段 | `public bool streamBody = false` | 请求侧流式（P5，§6.6）：true = 引擎解析到头区空行即停、不预读 body，连接 + 预读残留移交 handler——handler 经 req.bodyStream() 取 HttpBodyReader 边读边消费（超大上传不驻留内存）。 消费不完即 handler 返回 → 引擎丢弃式收尾（drain）后按 keep-alive 规则继续；WS 路由无 body 语义，恒 false |
| 字段 | `List&lt;Function&gt; _mws = null` | ── 路由级中间件（P10 补齐 P3 裁剪项，§6.9）── 该路由专属中间件（全局之后、handler 之前执行；注册序即执行序）。 RouteInfo.use 链式登记 / Router.add(method, path, handler, mws) params 尾参形态批量传入 |
| 字段 | `List&lt;string&gt; _segs = null` | ── 匹配预编译（模块内部）── |
| 字段 | `List&lt;string&gt; _paramNames = null` | 字段 _paramNames（类型见签名）。 |
| 字段 | `List&lt;Int32&gt; _paramSegIdx = null` | 参数段在 _segs 中的下标（extractParams 对位用：第 k 个参数名取 路径 _paramSegIdx[k] 段，勿按参数序号直取路径段——/a/{x}/{y} 中 参数 0 在路径段 1） |
| 字段 | `Int32 _staticCount = 0` | 字段 _staticCount（类型见签名）。 |
| 字段 | `bool _hasParams = false` | 字段 _hasParams（类型见签名）。 |
| 字段 | `string _wildcardName = ""` | 通配段（P2，§4.2：{path*} 尾段匹配剩余全部段；仅识别最后一段） |
| 字段 | `Int32 _wildcardIdx = -1` | 字段 _wildcardIdx（类型见签名）。 |
| 字段 | `Int32 _seq = 0` | 注册序号（树化匹配的同静态段数平局裁决：先注册者优先） |
| 字段 | `object _node = null` | 挂载节点反向引用（_remove 定位用；object 持有 + as 转型—— public 类字段类型为模块内部类 Front 解析不稳，_WsSessions 纪律） |
| 方法 | `RouteInfo param(string name, string type, string desc, bool required)` | ── 文档元数据链式登记（§4.8：返回自身可链式）── path/query 参数：type = "integer"/"string"/"boolean"... |
| 方法 | `RouteInfo requestBody(object sample)` | JSON body 样例（样例实例 → 探针法 schema；§6.10） |
| 方法 | `RouteInfo formField(string name, string desc)` | form 字段（urlencoded requestBody schema；§4.8） |
| 方法 | `RouteInfo uploadField(string name, string desc, string mime)` | multipart 文件字段（requestBody multipart/form-data；§4.8） |
| 方法 | `RouteInfo response(Int32 status, object sample)` | 响应样例（状态码 + 样例实例；mediaType 缺省 application/json， text/event-stream 等流式响应显式传） |
| 方法 | `RouteInfo responseAs(Int32 status, object sample, string mediaType)` | 执行 responseAs(status, sample, mediaType)，行为详见源实现。 |
| 方法 | `RouteInfo security(string scheme)` | 认证要求（"bearerAuth" / "apiKeyAuth"；§4.11 / §6.10） |
| 方法 | `RouteInfo use(Function mw)` | ── 路由级中间件（P10，§6.9）── 链式登记一条路由级中间件（三参 Function(req,res,nx)）： 全局管道之后、本路由 handler 之前执行；注册序即执行序 |
| 方法 | `RouteInfo useAll(Function[] mws)` | 批量登记（app.onGet(path, fn, mw1, mw2) 尾参便捷形态的落地环） 注意：形参必须用显式数组类型而非 params——SL 的 params 语义是把 "逐个多余实参"装箱成数组，没有 C# 式"尾实参为数组则透传"语义； 若声明为 params，调用方把现成数组直传时会被再包一层导致元素遍历失败。 |
| 方法 | `Int32 _mwCount()` | 路由级中间件数（_Pipeline 执行序合并用） |
| 方法 | `Function _mwAt(Int32 i)` | 取第 i 条（越界 null；调用方判空） |

## class `RouteParam`

- **说明**：文档参数/字段记录（P3；RouteInfo 结构化元数据）

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `public string name = ""` | 字段 string（类型见签名）。 |
| 字段 | `public string type = ""` | "integer" / "string" / "boolean" ...（param 专用） |
| 字段 | `public string desc = ""` | 字段 string（类型见签名）。 |
| 字段 | `public bool required = false` | 字段 bool（类型见签名）。 |
| 字段 | `public string kind = "param"` | "param"（path/query）/ "form"（urlencoded 字段）/ "file"（multipart 文件） |
| 字段 | `public string mime = ""` | file 专用：接受类型（如 "image/*"） |
| 构造 | `_init_()` | 构造方法，初始化本类型实例。 |

## class `RouteResp`

- **说明**：文档响应记录（P3；状态码 + 样例文本 + 类名 + mediaType）

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `public Int32 status = 200` | 字段 Int32（类型见签名）。 |
| 字段 | `public string sampleText = ""` | 字段 string（类型见签名）。 |
| 字段 | `public string sampleClass = ""` | 字段 string（类型见签名）。 |
| 字段 | `public string mediaType = "application/json"` | 字段 string（类型见签名）。 |
| 构造 | `_init_()` | 构造方法，初始化本类型实例。 |

## class `_RouteNode`

- **说明**：_RouteNode — 段前缀树节点（P5 路由匹配优化，§6.2） 树结构：静态边 Map<段,子节点> + 单一参数边（{x} 段共享）+ 通配表 （{x*} 尾段路由挂在"前缀段节点"）；每节点四张路由表： _routes（HTTP 终止于此）/ _wsRoutes（WS）/ _wild（HTTP 通配）/ _wsWild（WS 通配）。匹配 = DFS 沿段下降收集候选（每层最多静态+ 参数两条分支）+ 静态段计数择优（语义与 v1 线性扫描完全一致： 静态段多者优先、同数先注册者优先、HEAD 视同 GET、ANY 全动词）。 语言纪律：Map 值类型用 object + as _RouteNode 转型（自引用泛型 Map<string,_RouteNode> Front 解析失败——_WsSessions 同款规避）。

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `List&lt;RouteInfo&gt; _routes = null` | HTTP 路由（pattern 段链终止于此节点） |
| 字段 | `List&lt;RouteInfo&gt; _wsRoutes = null` | WS 升级路由 |
| 字段 | `List&lt;RouteInfo&gt; _wild = null` | HTTP 通配路由（{x*}；挂在前缀段节点，吸收剩余全部段） |
| 字段 | `List&lt;RouteInfo&gt; _wsWild = null` | WS 通配路由 |
| 字段 | `Map&lt;string, object&gt; _static = null` | 静态边（段字面 → 子节点；object 持有 + as 转型） |
| 字段 | `_RouteNode _param = null` | 参数边（{x} 段共享一条） |
| 构造 | `_init_()` | 构造方法，初始化本类型实例。 |

## class `Router`

- **说明**：SLang 标准库类型 Router（详见源文件）。

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `static _RouteNode _root = null` | 段前缀树根（P5 树化：替代 v1 线性扫描表；路由数 &lt; 200 的线性 假设仍成立，树化是语义不变的查找优化） |
| 字段 | `static bool _ready = false` | 引擎构造期标志（未 configure 时树未建） |
| 字段 | `static Int32 _nextSeq = 1` | 注册序号发生器（平局裁决：先注册者优先） |
| 方法 | `void _ensure()` | ── 初始化 / 清理（HttpServerCore.configure/reset 调用）── |
| 方法 | `void clear()` | 清空全部路由（HTTP + WS；stop 后重新配置用） |
| 方法 | `RouteInfo add(string method, string pattern, Function handler)` | ── 注册 ── HTTP 路由注册（method 大小写不敏感；"ANY" 全动词）；返回 RouteInfo （文档元数据可链式后写：r = Router.add(...); r.summary = "..."） P3：同 (method, pattern) 已存在**文档路由**（importOpenApi 501 登记） 时自动让位——新真实路由继承其文档元数据后顶替（§4.8 覆盖工作流） |
| 方法 | `RouteInfo add(string method, string pattern, Function handler, params Function[] mws)` | 路由级中间件形态（P10，§6.9）：Router.add( "GET", path, fn, mw1, mw2 ) —— mw 以 params 尾参批量登记（语义 = Router.add(...) 后逐条 RouteInfo.use；null 项跳过）。 ⚠ 仅适用于"逐个独立实参"传法：SL 的 params 是把多余实参装箱成数组， 没有尾实参数组透传语义——若把现成数组作为第 4 实参传入，收到的 mws 会是"长度 1、元素为数组"的嵌套数组导致登记失效；库内门面 （HttpServer/RouteGroup on*）已全部改两步调用规避，直传数组请用 三参 add + RouteInfo.useAll(数组)。 |
| 方法 | `void _attach(RouteInfo r, bool ws)` | 路由挂树（ws = WS 表 / HTTP 表；通配挂前缀节点 wild 表） |
| 方法 | `_RouteNode _descendBuild(List&lt;string&gt; segs, Int32 depth)` | 下降 depth 段（缺节点即建；静态段走 _static、{x} 走 _param） |
| 方法 | `RouteInfo findExact(string method, string pattern)` | 精确 (method, pattern) 查找（docs 挂载冲突检测 / importOpenApi 合并判定用；不参与匹配优先级；method 相互或任一为 "ANY" 即命中） |
| 方法 | `RouteInfo _findInTree(string pattern, bool ws)` | 在树中找 pattern 字面相等的 HTTP 路由（首个命中；表内序 = 注册序） |
| 方法 | `bool _isParamSeg(string seg)` | {x} 参数段判定 |
| 方法 | `bool _isWildSeg(string seg)` | {x*} 通配段判定 |
| 方法 | `void _remove(RouteInfo r)` | 移除一条路由（内部；importOpenApi 覆盖让位用；经节点反向引用定位） |
| 方法 | `Int32 _removeFrom(List&lt;RouteInfo&gt; t, RouteInfo r)` | 表内定位（-1 未命中） |
| 方法 | `RouteInfo addWs(string pattern, Function handler)` | WS 升级路由注册（pattern 同一套 {param} 语法） |
| 方法 | `RouteInfo _build(string method, string pattern, Function handler)` | 注册项预编译：段拆分 + 参数名提取 + 静态段计数 + 通配段识别 |
| 方法 | `void _collect(_RouteNode node, List&lt;string&gt; segs, Int32 depth, string methodFilter, bool wantWs, Int32 tag, List&lt;RouteInfo&gt; outCands)` | ── 匹配 ── 候选收集（DFS 沿段下降；每层静态边 + 参数边至多两条分支）： methodFilter = null 忽略动词（findBest/allowMethods）；否则按 "动词相等或 ANY" 过滤（HEAD→GET 转换由调用方完成）。 depth == 段数 → 收集本节点精确终止表；节点通配表无条件收集 （吸收剩余 ≥ 0 段，§4.2 {path*} 语义） |
| 方法 | `bool _scopeOk(RouteInfo r, Int32 tag)` | 监听器作用域过滤（多监听器 v1.1）：scope 0 = 全局可见；N &gt; 0 仅 tag N |
| 方法 | `bool _methodOk(RouteInfo r, string methodFilter)` | 动词过滤（methodFilter null = 全过） |
| 方法 | `RouteInfo _pickBest(List&lt;RouteInfo&gt; cands, Int32 tag)` | 候选择优（静态段多者优先；同数先注册者优先——seq 升序）。 多监听器 v1.1：同静态段数平局时，本监听器专属路由（scope==tag 且非 0）优先于全局路由（scope 0）——listener 视图覆盖全局同名。 |
| 方法 | `RouteInfo match(string method, string path)` | HTTP 匹配（HEAD 视同 GET；ANY 全动词）；命中者中按静态段多者优先 （§4.2 精确段 &gt; 参数段；同数先注册者优先）；无命中返回 null （404/405 区分由 findBest：路径有注册但动词不符 → findBest 非空 → 405） |
| 方法 | `RouteInfo match(string method, string path, Int32 tag)` | 带 tag 形态（多监听器 v1.1；tag = 连接所在监听器，0 兼容旧语义 —— scope 0 全局路由全部可见） |
| 方法 | `RouteInfo findBest(string path)` | 路径最优命中（忽略动词；405 判定与 Allow 头生成用）： 静态段多者优先、同数先注册者优先 |
| 方法 | `RouteInfo findBest(string path, Int32 tag)` | 执行 findBest(path, tag)，行为详见源实现。 |
| 方法 | `List&lt;RouteInfo&gt; allRoutes()` | 全部 HTTP 路由快照（Docs.openApiJson / importOpenApi 遍历用； 树遍历收集 HTTP 精确表 + 通配表，注册序不定——消费方 Map 语义 无顺序依赖） |
| 方法 | `void _gather(_RouteNode node, List&lt;RouteInfo&gt; outList)` | 树遍历收集（HTTP 表：_routes + _wild；WS 表跳过） |
| 方法 | `string allowMethods(string path)` | 该路径已注册的全部动词（405 Allow 头用；逗号分隔；ANY 展开全表） |
| 方法 | `string allowMethods(string path, Int32 tag)` | 执行 allowMethods(path, tag)，行为详见源实现。 |
| 方法 | `RouteInfo findWs(string path)` | WS 路由匹配（仅路径；静态段优先 + 先注册者优先；无命中返回 null → 引擎 400） |
| 方法 | `RouteInfo findWs(string path, Int32 tag)` | 执行 findWs(path, tag)，行为详见源实现。 |
| 方法 | `Map&lt;string,string&gt; extractParams(RouteInfo route, string path)` | 提取路径参数（route 命中 path 后调用；无参数路由返回空 Map； 通配段 {name*} → 剩余段以 '/' 连接，可为空串） |
| 方法 | `string checkDuplicate()` | 冲突检测（start() 调用）：同 method+pattern 重复注册返回首个重复 的 pattern 描述（调用方抛 ServerError.DuplicateRoute）；无重复返回 null。 树化等价性：同 pattern 的路由段链确定 → 必挂同一节点 → 节点内 双循环即全表按 (method, pattern) 分组的完整比较。 多监听器 v1.1：同 (method, pattern) 但 scope 不同（全局 vs 各 监听器专属）不算重复——不同端口的同名路径各自独立。 |
| 方法 | `string _dupScan(_RouteNode node)` | 节点递归扫描（节点四表内双循环 + 子树递归） |
| 方法 | `void _splitSegments(string path, List&lt;string&gt; outSegs)` | ── 内部：段拆分与模式匹配 ── pattern/path 按 '/' 拆段（空串/仅 '/' → 空表；不产生空段） |

## class `RouteGroup`

- **说明**：RouteGroup — 前缀分组（Spring @RequestMapping 形态；§4.2） 由 SLang.HttpServer.group() 构造（模块内 new，HttpResponse 安全模式）； 实例方法只做前缀拼接后转发 Router.add。

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `string _prefix = ""` | 字段 _prefix（类型见签名）。 |
| 构造 | `_init_(string prefix)` | 构造方法，初始化本类型实例。 |
| 方法 | `string _join(string path)` | 前缀 + 子路径（子路径不以 '/' 起始时自动补；"/" 子路径 = 裸前缀） |
| 方法 | `RouteInfo onGet(string path, Function handler)` | 执行 onGet(path, handler)，行为详见源实现。 |
| 方法 | `RouteInfo onGet(string path, Function handler, params Function[] mws)` | 路由级中间件形态（P10，§6.9） |
| 方法 | `RouteInfo onPost(string path, Function handler)` | 执行 onPost(path, handler)，行为详见源实现。 |
| 方法 | `RouteInfo onPost(string path, Function handler, params Function[] mws)` | 执行 onPost(path, handler, mws)，行为详见源实现。 |
| 方法 | `RouteInfo onPut(string path, Function handler)` | 执行 onPut(path, handler)，行为详见源实现。 |
| 方法 | `RouteInfo onPut(string path, Function handler, params Function[] mws)` | 执行 onPut(path, handler, mws)，行为详见源实现。 |
| 方法 | `RouteInfo onDelete(string path, Function handler)` | 执行 onDelete(path, handler)，行为详见源实现。 |
| 方法 | `RouteInfo onDelete(string path, Function handler, params Function[] mws)` | 执行 onDelete(path, handler, mws)，行为详见源实现。 |
| 方法 | `RouteInfo onPatch(string path, Function handler)` | 执行 onPatch(path, handler)，行为详见源实现。 |
| 方法 | `RouteInfo onPatch(string path, Function handler, params Function[] mws)` | 执行 onPatch(path, handler, mws)，行为详见源实现。 |
| 方法 | `RouteInfo onAny(string path, Function handler)` | 执行 onAny(path, handler)，行为详见源实现。 |
| 方法 | `RouteInfo onAny(string path, Function handler, params Function[] mws)` | 执行 onAny(path, handler, mws)，行为详见源实现。 |
| 方法 | `RouteInfo on(string method, string path, Function handler)` | 原始形式（动态注册 / 方法变量） |
| 方法 | `RouteInfo on(string method, string path, Function handler, params Function[] mws)` | 原始形式 + 路由级中间件（P10 params 尾参形态） |
| 方法 | `RouteInfo websocket(string path, Function handler)` | WS 升级路由（组内前缀） |
