# Server.sl

> 源文件：`Server.sl`

## class `ServerConfig`

- **说明**：SLang/Server/Server.sl — 配置与错误码 + HTTP 应用门面（实例形态） 设计契约：SERVER_DESIGN.md §0 / §4.1-§4.2 / §4.9（生命周期与配置） / 附录 D（错误码表） 门面类 SLang.HttpServer（2026-10-26 自 SLang.Server 改名——服务器类 按协议分工：HttpServer 承载 HTTP + WebSocket 同端口升级两协议； WebSocket 侧 API（升级路由注册 / wsEvents / 会话查询 / 组播）整体 收口到 SLang.WebSocketServer 实例类）： var app = SLang.HttpServer();        # 缺省端口 80 var app = SLang.HttpServer( 8080 );  # 构造带端口 app.onGet( "/hello", function( SLang.Request req, SLang.Response res ) { res.text( "hello world" ); } ); app.run();                           # = start + awaitStop（阻塞直至 stop） app.run( 8080 );                     # run(port)/start(port) 便捷覆盖 WS 升级路由（同端口）：SLang.WebSocketServer ws = SLang.WebSocketServer() → ws.websocket( path, fn ) / ws.wsEvents( path )——详见 WebSocketServer.sl。 构造期落位默认 ServerConfig（cfg.port = 构造端口），start 前可经 app.config 直改字段；app.configure( cfg ) 为全量覆盖。 v1 语义说明：引擎（HttpServerCore / Router / 会话表）仍为模块级单例 （SERVER_DESIGN.md §12 复盘 ①——C VM 跨模块类多实例化的实例态隔离 不可靠），路由 / 中间件 / 插件 / WS 会话跨实例共享，单 VM 单服务器； 多实例需求待 C VM 实例隔离修复。插件 onInstall / 闭包等无实例引用 场景经引擎级静态通道（HttpServerCore.use / .onGet / .sessions / .broadcast）注册与查询，语义与实例形态完全一致。 配置字段直改（无 builder 链）；后续阶段字段随能力增补： P1.5：maxUploadBytes / maxFileBytes（multipart，已落地） P2：writeTimeoutMs（流式写挂起超时） P3：maxConnections / showBanner P5：wsIdleTimeoutMs / jwtSecret 服务器配置

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `public string host = "0.0.0.0"` | 监听地址 |
| 字段 | `public Int32 port = 8080` | 监听端口（门面构造 seed / start(port) 为便捷覆盖） |
| 字段 | `public Int32 keepAliveTimeoutMs = 15000` | 空闲连接超时毫秒（超时静默断开） |
| 字段 | `public Int32 handlerTimeoutMs = 30000` | handler 协程执行超时毫秒（防 await 死等；&lt;= 0 无限等待； 超时 cancel + 504 + 断连，SERVER_DESIGN.md §6.1） |
| 字段 | `public Int32 maxHeaderBytes = 16384` | 请求头上限字节，超出 431 |
| 字段 | `public Int32 maxBodyBytes = 10485760` | 普通请求 body 上限字节，超出 413 |
| 字段 | `public Int32 maxUploadBytes = 104857600` | multipart 请求总量上限字节，超出 413（P1.5，§4.9） |
| 字段 | `public Int32 maxFileBytes = 52428800` | 单文件上限字节，超出 413（P1.5，§4.9） |
| 字段 | `public Int32 writeTimeoutMs = 30000` | 流式写挂起超时毫秒（防慢客户端拖死；&lt;= 0 无限等待；P2，§4.9） |
| 字段 | `public Int32 maxConnections = 1024` | 并发连接上限（超出 503 + 断连；&lt;= 0 不限；P3，§4.9） |
| 字段 | `public Int32 wsIdleTimeoutMs = 0` | WS 会话空闲超时毫秒（无入站消息即断开；&lt;= 0 不启用；P5，§6.8）。 引擎在 WS 会话注册后启动看门狗协程：空闲超时 close 会话， handler 的 receive() 随之返回 null 自然收尾 |
| 字段 | `public string jwtSecret = ""` | JWT HS256 密钥（P5，§4.11；Jwt.sign 缺省密钥——sign/verify 显式 传 secret 优先；空串 = 未配置，sign 抛 MissingJwtSecret） |
| 构造 | `_init_()` | 字段默认值经无参构造显式落位（HttpClient._init_ 先例：跨模块消费侧 类字段默认值初始化不可靠，实测 host 读出空串致 listen 绑错地址） |

## class `_SrvUtil`

- **说明**：_SrvUtil — 模块内部工具（不入 jsonc struct）。 注：struct 登记类方法体内局部/形参位泛型容器 .add 曾解析失败，根因为 Front gen 实例成员一次性快照时序缺陷——已在 MetaCallNode.GetFunction- OrVariableByOwnerClass 加 gen→原始模板类回退修复（2026-10-17），本类 保留作模块内部工具收口。

| 类型 | 签名 | 说明 |
|------|------|------|
| 方法 | `void copyKeys(Map&lt;string,string&gt; src, List&lt;string&gt; dst)` | Map 键拷贝进 List（queryKeys/formKeys 底座） |

## class `HttpServer`

- **说明**：SLang.HttpServer — HTTP 应用门面（App 本体，实例形态） 设计契约：SERVER_DESIGN.md §0 / §4.1-§4.2 / §4.6 / §4.9 用法： import SLangServer; var app = SLang.HttpServer( 8080 );  # 缺省端口 80 var cfg = app.config;                 # 直改字段（start 前生效） cfg.keepAliveTimeoutMs = 20000; app.onGet( "/hello", function( SLang.Request req, SLang.Response res ) { res.text( "hello world" ); } ); app.run();                           # = start + awaitStop（阻塞直至 stop） 形态说明（SERVER_DESIGN.md §12 复盘 ①）：P0-P4 曾以静态形态落地 （SLang.Server.configure( cfg ) / .onGet( path, fn ) / .run( port )）， 现按设计目标形态转实例（§19 实录）；引擎层维持模块级单例（C VM 多实例 实例态隔离不可靠），跨实例共享路由/中间件/会话——v1 单 VM 单服务器语义。

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `public Int32 port = 80` | 监听端口（构造入参；SLang.HttpServer() = 80；start(port)/run(port) 便捷覆盖后同步本字段） |
| 方法 | `void _init_()` | ── 构造 ── 缺省构造：端口 80（构造期落位默认配置，start 前可 app.config 直改） |
| 方法 | `void _init_(Int32 port)` | 带端口构造：SLang.HttpServer( 8080 )（构造期落位默认配置） |
| 属性 | `get ServerConfig config()` | ── 配置 / 生命周期 ── 运行配置（构造期已 seed 默认值；start 前直改字段生效—— SERVER_DESIGN.md §4.9「var cfg = app.config; cfg.port = 8080」形态） |
| 方法 | `void configure(ServerConfig cfg)` | 全量配置覆盖（构造期 seed 之外的显式配置；start 前生效； 重复调用覆盖；this.port 随 cfg.port 同步） |
| 方法 | `void start()` | 启动（立即返回，accept 循环独立协程；端口 = 配置端口—— 构造期 seed 自构造入参，app.config 直改后以直改值为准） |
| 方法 | `void start(Int32 port)` | 启动（便捷覆盖端口；立即返回） |
| 方法 | `void run()` | 阻塞当前协程直至 stop（run = start + awaitStop） |
| 方法 | `void run(Int32 port)` | 阻塞当前协程直至 stop（便捷覆盖端口） |
| 方法 | `void stop()` | 停止（关监听 + 关全部在途连接；路由表保留，可重新 start 复用； 需要清空路由用 reset()） |
| 方法 | `void awaitStop()` | 挂起直至停止（不经 run 形态时用） |
| 方法 | `void reset()` | 清空路由表（HTTP + WS；stop 后重新配置用） |
| 属性 | `get bool isRunning()` | 获取 isRunning 的值。 |
| 属性 | `get Function onStart()` | 获取 onStart 的值。 |
| 属性 | `get Function onStop()` | 获取 onStop 的值。 |
| 属性 | `get Function onError()` | 获取 onError 的值。 |
| 方法 | `RouteInfo onGet(string path, Function handler)` | ── 路由注册（动词家族；get/set 是关键字 → on 前缀）── P10：每动词两形态——双参基础形 + params 尾参路由级中间件形 （app.onGet( path, fn, mw1, mw2 )，§6.9 裁剪项补齐：mw 在全局 管道之后、该路由 handler 之前执行） |
| 方法 | `RouteInfo onGet(string path, Function handler, params Function[] mws)` | 执行 onGet(path, handler, mws)，行为详见源实现。 |
| 方法 | `RouteInfo onPost(string path, Function handler)` | 执行 onPost(path, handler)，行为详见源实现。 |
| 方法 | `RouteInfo onPost(string path, Function handler, params Function[] mws)` | 执行 onPost(path, handler, mws)，行为详见源实现。 |
| 方法 | `RouteInfo onPut(string path, Function handler)` | 执行 onPut(path, handler)，行为详见源实现。 |
| 方法 | `RouteInfo onPut(string path, Function handler, params Function[] mws)` | 执行 onPut(path, handler, mws)，行为详见源实现。 |
| 方法 | `RouteInfo onDelete(string path, Function handler)` | 执行 onDelete(path, handler)，行为详见源实现。 |
| 方法 | `RouteInfo onDelete(string path, Function handler, params Function[] mws)` | 执行 onDelete(path, handler, mws)，行为详见源实现。 |
| 方法 | `RouteInfo onPatch(string path, Function handler)` | 执行 onPatch(path, handler)，行为详见源实现。 |
| 方法 | `RouteInfo onPatch(string path, Function handler, params Function[] mws)` | 执行 onPatch(path, handler, mws)，行为详见源实现。 |
| 方法 | `RouteInfo onHead(string path, Function handler)` | 执行 onHead(path, handler)，行为详见源实现。 |
| 方法 | `RouteInfo onHead(string path, Function handler, params Function[] mws)` | 执行 onHead(path, handler, mws)，行为详见源实现。 |
| 方法 | `RouteInfo onOptions(string path, Function handler)` | 执行 onOptions(path, handler)，行为详见源实现。 |
| 方法 | `RouteInfo onOptions(string path, Function handler, params Function[] mws)` | 执行 onOptions(path, handler, mws)，行为详见源实现。 |
| 方法 | `RouteInfo onAny(string path, Function handler)` | 全动词（对该 pattern 接受全部 HTTP 动词） |
| 方法 | `RouteInfo onAny(string path, Function handler, params Function[] mws)` | 执行 onAny(path, handler, mws)，行为详见源实现。 |
| 方法 | `RouteInfo on(string method, string path, Function handler)` | 原始形式（动态注册 / 方法变量） |
| 方法 | `RouteInfo on(string method, string path, Function handler, params Function[] mws)` | 原始形式 + 路由级中间件（P10 params 尾参形态） |
| 字段 | `static List&lt;string&gt; _plVerbs = null` | ── 预装载路由注册中心（P4/P9 §26；attribute _enter_ 消费侧）── 装配期缓冲（模块静态：Preload attribute 的 _enter_ 在入口调度 前写入；reset() 不清空——与全局 Router 生命周期解耦，各 app 经 usePreloadRoutes() 按需拉取，可多 app 反复并入） |
| 字段 | `static List&lt;string&gt; _plPatterns = null` | 字段 List（类型见签名）。 |
| 字段 | `static List&lt;Function&gt; _plHandlers = null` | 字段 List（类型见签名）。 |
| 字段 | `static Map&lt;string, string&gt; _plPrefix = null` | 类级 @OnRoute 前缀表（宿主类全名 -&gt; prefix） |
| 字段 | `static HttpServer _preloadHost = null` | 隐式默认 Server（装配期注册载体；端口 0 占位，不启动—— 真实 app 构造时覆盖引擎配置） |
| 方法 | `HttpServer shared()` | 隐式共享 Server（首次访问构造；@On* 家族 attribute 的 _enter_ 经它注册装配期路由——「new 一个 Server 后调它的实例方法」； 名避关键字 default） |
| 方法 | `string _upperVerb(string v)` | verb 大写规整（HTTP 动词封闭集；大写原文直通——OnGet 家族 传常量，@Route 传用户串；v1 无自定义动词用例） |
| 方法 | `void registerPreload(string verb, string path, Attribute attr)` | 预装载路由注册（方法级 attribute _enter_ 调用）： 1. verb 大写规整；宿主类命中 @OnRoute 前缀则 prefix + path 拼接（§4.10）； 2. §4.10 双形态（2026-10-27 修订）： 形态 1 · 实例控制器（类级 @OnRoute）：宿主类已标 @InstanceAttr（Std）→ SystemAttributeGetInstanceField 取装配 期单实例 → hostMethodRefOf(单实例)（绑定实例 method-ref，全程 复用，bind-once，§26）；否则 hostMethodRef()（实例方法 → LATE 闭包，每请求一实例）； 形态 2 · 静态直挂（类上无 @OnRoute）：必须绑定静态函数 （hostMethodRef 对 static 方法返回静态 method-ref，不实例 化）；非 static 方法 → 打印错误并拒绝注册（请求 404， 日志可查，装配流程不中断）； 3. (verb, pattern, handler) 入缓冲，usePreloadRoutes() 拉取。 |
| 方法 | `void registerPrefix(string prefix, string className)` | 类级 @OnRoute 前缀登记（类级 attribute _enter_ 调用；先于 该类方法级 _enter_ 触发，前缀表就绪后拼接生效） |
| 方法 | `Int32 usePreloadRoutes()` | ── 预装载路由接线（P4，§4.10 / §7）── 把默认 Server 上缓冲的装配期路由（@OnGet 家族 / Route / OnRoute 控制器语法经各 attribute _enter_ 注册）并入 Router。configure 之后、start 之前调用；返回并入条数。重复调用按普通 Router.add 语义（同 method+pattern 重复注册由 start() fail-fast 拦截， ServerError.DuplicateRoute）。 |
| 方法 | `RouteGroup group(string prefix)` | ── 路由分组（前缀提取，Spring @RequestMapping 形态）── |
| 方法 | `ServerListener listen(Int32 port)` | ── 多监听器（v1.1）：同进程扩展端口挂载 ── 主监听器 = 构造端口（start()）；listen() 挂扩展端口，返回 ServerListener 视图——其 on*/websocket 注册的路由仅该端口可见 （app.on* 直注路由仍为全局，全部端口共享）。 var app  = SLang.HttpServer( 8080 ); var adm  = app.listen( 9090 ); adm.onGet( "/panel", fn );   # 仅 9090 可达 app.run(); start 前调用入缓冲（start 统一 bind，tag 已分配不变）； running 中调用立即 bind。 扩展监听器（host 取运行配置 host） |
| 方法 | `ServerListener listen(string host, Int32 port)` | 扩展监听器（显式 host；端口非法抛 ServerError.InvalidConfig） |
| 方法 | `void use(Function middleware)` | ── 中间件 / 插件（P2，§4.7）── 注册中间件（三参 Function：function( SLang.Request req, SLang.Response res, SLang.Next nx )；注册序即执行序； nx.go() 放行 / 不调 = 短路） |
| 方法 | `void use(ServerPlugin plugin)` | 注册插件（ServerPlugin 子类；onInstall 立即执行， onStart/onStop/onWsOpen/onWsClose 由引擎广播） |
| 方法 | `void docs(bool enable)` | ── API 文档（P3，§4.8）── 文档路由开关（false = start 不挂 /docs 与 /openapi.json； 生产建议关；reset() 恢复默认开） |
| 方法 | `Int32 importOpenApi(string jsonPath)` | 反向导入 OpenAPI json（Apifox 导出 → 路由骨架）： 返回新建文档路由数（未注册路径以 501 文档路由登记、/docs 可见； 已注册路径仅合并文档元数据；后续 onGet(...) 同名覆盖生效，§4.8） |

## class `ServerListener`

- **说明**：ServerListener — 扩展监听器视图（多监听器 v1.1） 由 SLang.HttpServer.listen() 构造（模块内构造，RouteGroup 同款安全 模式）。语义：本视图 on*/websocket 注册的路由打 scope = 本监听器 tag——仅该端口可见；主端口经 app.on* 直注的路由为全局（scope 0， 全部端口共享）。tag 由 HttpServerCore.listen() 分配（主监听器 = 1， 扩展 = 2,3,...；start 前登记入缓冲、start 统一 bind，tag 不变）。

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `Int32 _tag = 0` | 字段 _tag（类型见签名）。 |
| 字段 | `Int32 _port = 0` | 字段 _port（类型见签名）。 |
| 字段 | `string _host = ""` | 字段 _host（类型见签名）。 |
| 构造 | `_init_(string host, Int32 port, Int32 tag)` | 构造方法，初始化本类型实例。 |
| 属性 | `get Int32 tag()` | 本监听器 tag（RouteInfo.scope 打标值；调试 / 会话分流用） |
| 属性 | `get Int32 port()` | 本监听器端口 |
| 属性 | `get string host()` | 本监听器绑定地址 |
| 方法 | `RouteInfo _reg(string method, string path, Function handler)` | 打标注册（scope = 本监听器 tag；模块内两步注册收口） |
| 方法 | `RouteInfo onGet(string path, Function handler)` | ── 路由注册（动词家族，镜像 HttpServer/RouteGroup 形态； get/set 是关键字 → on 前缀）── |
| 方法 | `RouteInfo onGet(string path, Function handler, params Function[] mws)` | 执行 onGet(path, handler, mws)，行为详见源实现。 |
| 方法 | `RouteInfo onPost(string path, Function handler)` | 执行 onPost(path, handler)，行为详见源实现。 |
| 方法 | `RouteInfo onPost(string path, Function handler, params Function[] mws)` | 执行 onPost(path, handler, mws)，行为详见源实现。 |
| 方法 | `RouteInfo onPut(string path, Function handler)` | 执行 onPut(path, handler)，行为详见源实现。 |
| 方法 | `RouteInfo onPut(string path, Function handler, params Function[] mws)` | 执行 onPut(path, handler, mws)，行为详见源实现。 |
| 方法 | `RouteInfo onDelete(string path, Function handler)` | 执行 onDelete(path, handler)，行为详见源实现。 |
| 方法 | `RouteInfo onDelete(string path, Function handler, params Function[] mws)` | 执行 onDelete(path, handler, mws)，行为详见源实现。 |
| 方法 | `RouteInfo onPatch(string path, Function handler)` | 执行 onPatch(path, handler)，行为详见源实现。 |
| 方法 | `RouteInfo onPatch(string path, Function handler, params Function[] mws)` | 执行 onPatch(path, handler, mws)，行为详见源实现。 |
| 方法 | `RouteInfo onHead(string path, Function handler)` | 执行 onHead(path, handler)，行为详见源实现。 |
| 方法 | `RouteInfo onHead(string path, Function handler, params Function[] mws)` | 执行 onHead(path, handler, mws)，行为详见源实现。 |
| 方法 | `RouteInfo onOptions(string path, Function handler)` | 执行 onOptions(path, handler)，行为详见源实现。 |
| 方法 | `RouteInfo onOptions(string path, Function handler, params Function[] mws)` | 执行 onOptions(path, handler, mws)，行为详见源实现。 |
| 方法 | `RouteInfo onAny(string path, Function handler)` | 全动词（对该 pattern 接受全部 HTTP 动词；仅本监听器可见） |
| 方法 | `RouteInfo onAny(string path, Function handler, params Function[] mws)` | 执行 onAny(path, handler, mws)，行为详见源实现。 |
| 方法 | `RouteInfo on(string method, string path, Function handler)` | 原始形式（动态注册 / 方法变量） |
| 方法 | `RouteInfo on(string method, string path, Function handler, params Function[] mws)` | 原始形式 + 路由级中间件（params 尾参形态） |
| 方法 | `RouteInfo websocket(string path, Function handler)` | WS 升级路由（仅本监听器可升级） |
