# Server 库类与方法索引

> 本目录为 `SLangCore/Lib/SLang/Server` 标准库自动提取的 API 参考，点击模块名查看方法/字段明细。

| 类型 | 种类 | 模块(.sl) | 基类/接口 | 说明 |
|------|------|-----------|-----------|------|
| `ApiResult` | class | [ApiResult.sl](ApiResult.md) |  | SLang/Server/ApiResult.sl — 统一 JSON 返回体（P1） 设计契约：SERVER_DESIGN.md §4.3 / §6.7 输出… |
| `_UrlCodec` | class | [BodyParser.sl](BodyParser.md) |  | _UrlCodec — 内部 URL 解码工具（percent-decode + '+'→空格；UTF-8 组装）。 Uri 无现成解码（SERVER_DESI… |
| `_MultipartBody` | class | [BodyParser.sl](BodyParser.md) |  | _MultipartBody — multipart 解析结果（内部）。 errorCode：0 = OK / 400 = boundary 缺失或格式坏 / … |
| `BodyParser` | class | [BodyParser.sl](BodyParser.md) |  | BodyParser — 格式判定与 form / multipart 解码（静态工具） |
| `Docs` | class | [Docs.sl](Docs.md) |  | SLang/Server/Docs.sl — OpenAPI 文档 + /docs 页面 + importOpenApi（P3） 设计契约：SERVER_DES… |
| `HttpBodyReader` | class | [HttpBodyReader.sl](HttpBodyReader.md) |  | SLang 标准库类型 HttpBodyReader（详见源文件）。 |
| `_HttpParseResult` | class | [HttpServerCore.sl](HttpServerCore.md) |  | SLang/Server/HttpServerCore.sl — HTTP/1.1 连接引擎（P0 → P1 → P1.5） 设计契约：SERVER_DESIG… |
| `HttpServerCore` | class | [HttpServerCore.sl](HttpServerCore.md) |  | SLang 标准库类型 HttpServerCore（详见源文件）。 |
| `JwtClaims` | class | [Jwt.sl](Jwt.md) |  | SLang/Server/Jwt.sl — JWT claims 读取 + HS256 签验（P3 decode → P5 sign/verify） SLang… |
| `Jwt` | class | [Jwt.sl](Jwt.md) |  | SLang 标准库类型 Jwt（详见源文件）。 |
| `MultipartPart` | class | [MultipartReader.sl](MultipartReader.md) |  | SLang/Server/MultipartReader.sl — multipart 流式解析（P7，§6.6） 设计契约：SERVER_DESIGN.md … |
| `MultipartReader` | class | [MultipartReader.sl](MultipartReader.md) |  | ── multipart 流式解析器（req.multipartStream() 构造；用户勿直接 new）── |
| `Next` | class | [Plugin.sl](Plugin.md) |  | SLang/Server/Plugin.sl — 中间件管道与插件模型（P2） 设计契约：SERVER_DESIGN.md §4.7 / §6.9 模型： - … |
| `ServerPlugin` | class | [Plugin.sl](Plugin.md) |  | ServerPlugin — 插件基类（钩子默认空实现；子类 override 重写—— SL 无 virtual 关键字，成员方法默认可被子类重写，§2.3 … |
| `_Pipeline` | class | [Plugin.sl](Plugin.md) |  | _Pipeline — 管道执行器（内部；连接协程内联） 每环框架构造 Next 实例（内持下一环索引，§6.9——SL 无方法引用， 框架持索引逐环构造）；尾… |
| `_PluginHost` | class | [Plugin.sl](Plugin.md) |  | _PluginHost — 中间件/插件宿主（内部静态；HttpServerCore 生命周期联动） 单 VM 协程调度无锁（§3 并发模型不变量） |
| `_LoggerPlugin` | class | [Plugins.sl](Plugins.md) |  | SLang/Server/Plugins.sl — 内置插件门面（P2） 设计契约：SERVER_DESIGN.md §4.7（内置插件路线：logger / … |
| `_CorsPlugin` | class | [Plugins.sl](Plugins.md) |  | ── cors：跨域（自动应答 OPTIONS 预检 + 放行头）── |
| `_StaticFilesPlugin` | class | [Plugins.sl](Plugins.md) |  | ── staticFiles：静态目录服务（root 下文件直出；仅 GET）── |
| `_SwaggerUIPlugin` | class | [Plugins.sl](Plugins.md) |  | ── swaggerUI（P9 收官，§10 风险 #8）：Swagger UI 静态包托管 ── 路由：GET /swagger → 自研 index（外链 … |
| `_BodyLimitPlugin` | class | [Plugins.sl](Plugins.md) |  | ── bodyLimit（P3，§4.7）：场景化 body 上限收紧（低于全局 maxBodyBytes 的应用级限制；超限 413 ApiResult 短路… |
| `_RequestIdPlugin` | class | [Plugins.sl](Plugins.md) |  | ── requestId（P3，§4.7）：X-Request-Id 响应头（Guid；请求追踪）── |
| `_RateBucket` | class | [Plugins.sl](Plugins.md) |  | ── rateLimit（P5，§4.7）：按客户端 IP 固定窗口限流 ── 窗口内请求数超 max → 429 + Retry-After（剩余秒）短路； … |
| `_RateLimitPlugin` | class | [Plugins.sl](Plugins.md) |  | SLang 标准库类型 _RateLimitPlugin（详见源文件）。 |
| `_AuthPlugin` | class | [Plugins.sl](Plugins.md) |  | ── auth（P3，§4.11）：认证插件——三挂法共用一类 ── mode 0 = 通用回调（收整个 req）；1 = Bearer 预设（Jwt.deco… |
| `Plugins` | class | [Plugins.sl](Plugins.md) |  | Plugins — 内置插件工厂门面（静态；产物为普通 ServerPlugin 子类） |
| `Request` | class | [Request.sl](Request.md) |  | SLang/Server/Request.sl — 请求上下文（读侧 API，P1 全表 → P1.5 增补） 设计契约：SERVER_DESIGN.md §6… |
| `Response` | class | [Response.sl](Response.md) |  | SLang/Server/Response.sl — 响应输出（写侧 API，P1 全表 → P2 流式增补） 设计契约：SERVER_DESIGN.md §4… |
| `OnGet` | class | [RouteAttrs.sl](RouteAttrs.md) |  | SLang/Server/RouteAttrs.sl — 预装载路由 attribute 家族（P4 / P9 §26） 设计契约：SERVER_DESIGN.… |
| `OnPost` | class | [RouteAttrs.sl](RouteAttrs.md) |  | @OnPost("/save") — POST 路由（方法级） |
| `OnPut` | class | [RouteAttrs.sl](RouteAttrs.md) |  | @OnPut("/item") — PUT 路由（方法级） |
| `OnDelete` | class | [RouteAttrs.sl](RouteAttrs.md) |  | @OnDelete("/item/{id}") — DELETE 路由（方法级） |
| `OnPatch` | class | [RouteAttrs.sl](RouteAttrs.md) |  | @OnPatch("/item/{id}") — PATCH 路由（方法级） |
| `OnHead` | class | [RouteAttrs.sl](RouteAttrs.md) |  | @OnHead("/info") — HEAD 路由（方法级；Router 侧 HEAD 视同 GET） |
| `OnOptions` | class | [RouteAttrs.sl](RouteAttrs.md) |  | @OnOptions("/info") — OPTIONS 路由（方法级；CORS 预检） |
| `OnAny` | class | [RouteAttrs.sl](RouteAttrs.md) |  | @OnAny("/echo") — 全动词路由（方法级；接受全部 HTTP 动词） |
| `Route` | class | [RouteAttrs.sl](RouteAttrs.md) |  | @Route("/x", "POST") — 显式动词通用形式（方法级）。 verb 缺省（单参形态）= "ANY"；registerPreload 内大写规整 |
| `OnRoute` | class | [RouteAttrs.sl](RouteAttrs.md) |  | @OnRoute("/api") — 类级路由前缀（Spring RequestMapping 形态）。 该类内全部方法级路由的 pattern 拼接 pref… |
| `RouteInfo` | class | [Router.sl](Router.md) |  | SLang/Server/Router.sl — 路由器（P1） 设计契约：SERVER_DESIGN.md §4.2 / §6.2 匹配规则：pattern … |
| `RouteParam` | class | [Router.sl](Router.md) |  | 文档参数/字段记录（P3；RouteInfo 结构化元数据） |
| `RouteResp` | class | [Router.sl](Router.md) |  | 文档响应记录（P3；状态码 + 样例文本 + 类名 + mediaType） |
| `_RouteNode` | class | [Router.sl](Router.md) |  | _RouteNode — 段前缀树节点（P5 路由匹配优化，§6.2） 树结构：静态边 Map&lt;段,子节点&gt; + 单一参数边（{x} 段共享）+ 通配表 （{x… |
| `Router` | class | [Router.sl](Router.md) |  | SLang 标准库类型 Router（详见源文件）。 |
| `RouteGroup` | class | [Router.sl](Router.md) |  | RouteGroup — 前缀分组（Spring @RequestMapping 形态；§4.2） 由 SLang.HttpServer.group() 构造（… |
| `ServerConfig` | class | [Server.sl](Server.md) |  | SLang/Server/Server.sl — 配置与错误码 + HTTP 应用门面（实例形态） 设计契约：SERVER_DESIGN.md §0 / §4.… |
| `_SrvUtil` | class | [Server.sl](Server.md) |  | _SrvUtil — 模块内部工具（不入 jsonc struct）。 注：struct 登记类方法体内局部/形参位泛型容器 .add 曾解析失败，根因为 Fr… |
| `HttpServer` | class | [Server.sl](Server.md) |  | SLang.HttpServer — HTTP 应用门面（App 本体，实例形态） 设计契约：SERVER_DESIGN.md §0 / §4.1-§4.2 /… |
| `ServerListener` | class | [Server.sl](Server.md) |  | ServerListener — 扩展监听器视图（多监听器 v1.1） 由 SLang.HttpServer.listen() 构造（模块内构造，RouteGr… |
| `_Mime` | class | [StreamIo.sl](StreamIo.md) |  | SLang/Server/StreamIo.sl — 流式写出器与 MIME 表（P2） 设计契约：SERVER_DESIGN.md §4.5 / §6.6 /… |
| `StreamWriter` | class | [StreamIo.sl](StreamIo.md) |  | StreamWriter — chunked 流式写出器（模块内构造：Response.stream()） 头部由 Response.stream() 先行发出… |
| `SseWriter` | class | [StreamIo.sl](StreamIo.md) |  | SseWriter — Server-Sent Events 写出器（模块内构造：Response.sse()； 线格式 §6.6，CRLF 行界） |
| `UploadedFile` | class | [Upload.sl](Upload.md) |  | SLang/Server/Upload.sl — 文件上传句柄（P1.5） 设计契约：SERVER_DESIGN.md §4.4（UploadedFile 表）… |
| `_WsSessions` | class | [WebSocketServer.sl](WebSocketServer.md) |  | SLang/Server/WebSocketServer.sl — WsSession / 会话注册表 / WebSocket 服务（实例双形态） 设计契约：S… |
| `WsSession` | class | [WebSocketServer.sl](WebSocketServer.md) |  | WsSession — WebSocket 会话（模块内构造；用户侧只消费） |
| `WebSocketServer` | class | [WebSocketServer.sl](WebSocketServer.md) |  | WebSocketServer — WebSocket 服务（实例形态，双形态） 形态 A（HTTP 同端口升级——依附 HttpServer 监听）： SLa… |
| `_WsEventRoutes` | class | [WebSocketServer.sl](WebSocketServer.md) |  | WsEventBuilder — WS 事件式糖（P2，§4.6：wsEvents(path).onOpen(...) .onMessage(...).onCl… |
| `WsEventBuilder` | class | [WebSocketServer.sl](WebSocketServer.md) |  | SLang 标准库类型 WsEventBuilder（详见源文件）。 |
