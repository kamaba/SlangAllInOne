# SLang Server — HTTP / WebSocket 服务框架设计

> 状态：**v2 · P5 已落地（2026-10-26）** · v1 2026-10-14 · v2 2026-10-14（评审修订） · P0 2026-10-17（引擎+探针全绿） · P1 2026-10-17（路由与封装全绿） · P1.5 2026-10-20（文件上传全绿） · P2 2026-10-20（管道与流式全绿） · P3 2026-10-21（文档+认证全绿） · P4 2026-10-24（attribute 控制器全绿） · P4.5 2026-10-25（直接 await 糖全绿，见 §8 P4.5 行与「§18 P4.5 落地实录」） · P5 2026-10-26（前缀树/Range/WS 心跳/rateLimit/Jwt HS256/请求侧流式全绿，见 §8 P5 行与「§20 P5 落地实录」） · 类拆分 2026-10-26（SLang.Server → SLang.HttpServer + SLang.WebSocketServer，见「§21 类拆分实录」） · **v1 收官 2026-10-26**（RouteAttrs override 误诊撤销全量恢复 + SwaggerUI 插件落地，全量 241 OK / 0 FAIL，见「§27 实录」）
> 落位：`source/Front/Lib/SLang/Server/`（模块名 `SLangServer`，命名空间 `SLang`）；SLangCore 布局：`SLangCore/Lib/SLang/Server/`
> 参照系：Python FastAPI（路由注册/自动文档）、Java Spring Boot（控制器/插件生态）、Node Express（Request/Response 双参签名）
> 关联：`md/lib/Std/net/Http.md` §7（Route/@On* 已接线 SLangServer）、`csimple_lang/md/design/ATTRIBUTE_DESIGN.md` §6.6（Route 另立项）、`csimple_lang/md/design/NETSTREAM_DESIGN.md`（Tcp 挂起协议）
>
> **v2 修订记录**（评审意见落位）：
> ① 路由注册改 `onGet` 家族——`get` / `set` 是 SL 关键字不能作方法名（`HttpClient.sl` 头注记先例）；
> ② `HttpContext` 拆分为 **`SLang.Request`（读）+ `SLang.Response`（写）**，处理器双参签名 `function( req, res )`，语义更明确；
> ③ 新增**请求体格式处理**（json / form / multipart / bin，按 Content-Type 自动分流，§4.4 / §6.4）；
> ④ 新增**文件上传** `SLang.UploadedFile`（multipart 解析 + saveAs/saveInto，§4.4 / §6.5）；
> ⑤ 明确**依赖边界：只引用 Core / Std 两个模块**，其它库一概不调（§1.1 G8）；
> ⑥ `ApiResult.data` 字段更名 `payload`（`data` 是关键字），输出 JSON 键名仍为 `"data"`（§6.7）；
> ⑦ 中间件放行改为 `SLang.Next` 类 `nx.go()`（`next` 是关键字，不能作参数名/方法名）；
> ⑧ 插件基类钩子去除 `virtual`——**语言无 `virtual` 关键字**，成员方法默认可被子类重写（`override` 标记、`final` 封禁），基类钩子直接 `public void` 空实现；
> ⑨ 补齐 **HTTP 流式传输**设计：响应侧 `res.stream()`（chunked）/ `res.sse()`（SSE）/ `res.sendFile()`（流式下载）落 P2（§4.5 / §6.6）；请求侧流式（边收边落盘上传、Range 断点续传）维持 P5；
> ⑩ 新增 **attribute 动词映射路由** `@OnGet/@OnPost/...` 家族（C# `[HttpPost("...")]` 形态，`@OnPost("admin/user")` 一参即路径，§4.10 重写）+ 确立 **handler 协程执行模型**：全部 HTTP handler（闭包注册与 attribute 控制器统一）经 `Coroutine.spawnClosure2` 派发为独立协程，handler 内可自由 `await / yield / Coroutine.delay`，连接协程 `awaitTask` 等待完成再写响应，超时 `waitTimeout + cancel` 兜底（§4.2 / §6.1，新增 `cfg.handlerTimeoutMs`）；
> ⑪ **异步示例补全**：真实业务约半数处理器是异步的——§4.1/§4.2/§4.5/§4.6/§4.7/§4.10 各节示例补 `await` 系列写法（下游 `httpGetAsync` 直等、`spawn + await` 并发聚合、`Channel` 生产消费、SSE 逐帧、WS 任务回推、中间件异步鉴权、控制器异步方法），并修正 §4.2 示例 `orders.size()` → `orders.length`（`List<T>` 长度属性）。
> ⑫ **handler 直接 await 协程函数调用**（评审反馈："OnPost 下边的函数直接可以 await，而不是在里边再 spawn"）：`@On*` / `on*` 派发时 handler **已经是协程**（§6.1），方法体内**直接 `await fn( 实参 ) as T` 一步到位**——落 §7.5 语言糖（P4.5）：`await` 后跟**返回非 Task 的调用**时 Front 自动包 spawn 脱糖（现状直写会被同步求值传 `awaitTask`，语义错误）；**返回 Task 的调用**（`httpGetAsync` 族）现状即合法直写。§4.1/§4.2/§4.6/§4.7/§4.10 示例全部改为直接形态；**并发聚合（先发起多个、再依次等）仍需显式 spawn**（§4.2 写法 2 保留并注明分界）；§2.2 缺口表、§7.3 探针、§8 P4.5、§10 风险 18 同步。
> ⑬ **异步写法场景库扩充**（评审反馈："增加数据库查询的 await、等其它任务执行完的 await，多增加一些 await"）：§4.2 速览 4 条 → 8 条——新增 ④ **数据库多表并发查询** + `waitAll` 等其它任务全部执行完（总耗时 ≈ 最慢一条 SQL）、⑤ 竞速取最快 `waitAny`（多镜像源）、⑥ **串行依赖链**（前序 await 结果作后序入参，只能顺序等）、⑦ **fire-and-forget 后台任务**（spawn 后刻意不 await、响应先回）；原聚合原语速查改列 ⑧；§8 P4.5 生效范围同步。
> ⑭ **认证与授权设计**（评审反馈："把 Swagger 或者 JWT 的一些关联也设计下，还有 header 验证 token 一类的"）：新增 §4.11——`SLang.Plugins.auth()` 认证中间件插件（Bearer / API Key / 自定义回调，401 短路）+ `req.auth` 身份槽（§6.3）+ `SLang.Jwt`（decode/claims 纯 SL 先行；sign/verify HS256 待 crypto 哈希原语，P5+）+ WS 升级 token 校验（`s.query("token")`——升级分流在管道之前，§6.1）+ `r.security()` 文档元数据与 OpenAPI `securitySchemes`/operation 级 `security` 生成（Apifox 导入自带认证配置，§4.8 / §6.10）；§0 / §1.1 G13 / §2.2 缺口 12 / §4.7 / §5 / §8 P3·P5 / §10 风险 19 / 附录 D 同步。

---

## §0 摘要（30 秒）

在 `Lib/SLang/Server/` 新建 `SLangServer` 模块，提供 **HTTP + WebSocket 一体的应用服务框架**：

- **两个门面类**：`SLang.HttpServer`（HTTP 应用门面）——`HttpServer()` 构造 → `app.onGet/onPost/...` 注册路由 → `app.run(8080)` 启动；`SLang.WebSocketServer`（WS 门面，双形态：升级路由器 / 独立端口服务器，§4.6）——HTTP 与 WebSocket 各一类、职责单一（2026-10-26 拆分，§21）；
- **语法极简**（本文档第一目标）：路由处理器就是普通闭包 `function( SLang.Request req, SLang.Response res ) { ... }`——**Request 管读、Response 管写**，路径参数 / 查询参数 / JSON·form·bin 三种 body / JSON 返回 / 文件上传全是行级 API；
- **handler 协程执行**：每个请求处理器派发为独立协程（`Coroutine.spawnClosure2`），处理器内可自由 `await`（异步子任务 / Channel；**`await` 后直接写函数调用**——`await fn(实参) as T` 一步到位，§7.5 语言糖）/ `yield` / `Coroutine.delay`——SSE 逐帧推送、聚合下游调用天然支持；`cfg.handlerTimeoutMs` 超时自动 `cancel` + 504 兜底（§4.2 / §6.1）；闭包注册与 §4.10 attribute 控制器**统一走同一条派发路径**；
- **统一 JSON 封装** `ApiResult`（`{"code","message","data"}`）+ `res.jsonOk / jsonFail`；
- **请求体按 Content-Type 自动分流**：`application/json` / `application/x-www-form-urlencoded` / `multipart/form-data`（文件上传）/ `text/*` / 二进制；
- **文件上传**：`req.file("avatar")` → `UploadedFile.saveAs(path)`，multipart 全解析（boundary / part 头 / 文件名安全剥离）；
- **流式传输**：`res.stream()`（chunked 分块下发）/ `res.sse()`（Server-Sent Events，AI 流式输出标配）/ `res.sendFile()`（大文件流式下载不整载内存）；写挂起天然背压；请求侧流式上传为 P5；
- **内置 API 文档**：`/docs`（自包含 HTML 页面）+ `/openapi.json`（OpenAPI 3.0.3 规范，**可直接导入 Apifox / Postman / SwaggerHub**）；反向支持从 OpenAPI 文件导入接口定义；
- **插件模型**：中间件管道（`nx.go()` 放行）+ `ServerPlugin` 基类（Logger / CORS / StaticFiles 内置起步）；
- **认证与授权**：`SLang.Plugins.auth(...)` 认证中间件（Bearer / API Key / 自定义校验回调，未过 → 401 短路）+ handler 侧 `req.auth` 身份槽；`SLang.Jwt` 读取与签验 claims（decode 不验签；sign/verify HS256 已随 P5 落地，密钥走 `ServerConfig.jwtSecret`，§4.11）；`r.security()` 路由元数据 → OpenAPI `securitySchemes` 自动生成（Apifox 导入自带认证配置，§4.11）；
- **P0–P3 纯 SL 层实现**，复用 `Net.TcpServer` / `WebSocketStream.accept` / `BaseJson` / `Coroutine.spawnClosure2`，**零 C VM 改动、零 Front 改动**；P4 attribute 控制器（`@OnGet/@OnPost/...` 动词家族）才动 C VM；P4.5 **直接 await 语言糖**仅动 Front（§7.5）；
- **只依赖 Core / Std** 两个模块（硬边界）。

```sl
# ── 全部核心能力一览（语法目标，详见 §4）──
import SLangServer;

var app = SLang.HttpServer();                      # ① 服务（HTTP 门面）
var ws  = SLang.WebSocketServer();                 # ① WS 门面（形态 A 升级路由，见 §4.6）
app.use( SLang.Plugins.logger() );                 # ③ 插件
app.use( SLang.Plugins.cors() );
app.use( SLang.Plugins.staticFiles( "./www" ) );
app.use( SLang.Plugins.authBearer() );            # ③ 认证（Bearer → req.auth，缺失/非法 401 短路）

app.onGet( "/api/user/{id}", function( SLang.Request req, SLang.Response res )   # ② 路径注册
{
    var u = User( req.pathInt( "id" ), "tom" );
    res.jsonOk( u );                               # JSON 封装 {"code":0,"data":{...}}
} );

app.onPost( "/api/upload/avatar", function( SLang.Request req, SLang.Response res )   # ④ 文件上传
{
    SLang.UploadedFile f = req.file( "avatar" );
    if f == null
    {
        res.jsonFail( 400, "no file" );
        ret
    }
    f.saveAs( "./uploads/" + f.filename );
    res.jsonOk( f.filename );
} );

app.onGet( "/api/sse/progress", function( SLang.Request req, SLang.Response res )   # ⑤ 流式（SSE）
{
    SLang.SseWriter sse = res.sse();
    for Int32 i = 0, i <= 100, i = i + 10
    {
        sse.sendEvent( "progress", i.toString() );
        Coroutine.delay( 500 );
    }
    sse.close();
} );

ws.websocket( "/ws/chat", function( SLang.WsSession s )        # WebSocket 升级路由（挂在 ws 上，与 app 同端口）
{
    while true
    {
        Net.WsMessage m = s.receive();
        if m == null
        {
            break
        }
        s.sendText( "echo: " + m.text() );
        m.release();
    }
} );

app.run( 8080 );                                   # 启动（/docs 自动挂载；同一端口：HTTP 路由 + WS 升级并存）
```

---

## §1 目标与非目标

### 1.1 目标

| # | 目标 | 度量 |
|---|------|------|
| G1 | **语法简单**（第一优先级）：一个类 + 闭包完成 HTTP/WS 服务 | 最小示例 ≤ 5 行；读 API 全挂 `req`、写 API 全挂 `res`，无散落工具类 |
| G2 | 服务启动 / 停止 / 生命周期钩子 | `run / start / stop` + 插件钩子 `ServerPlugin.onStart / onStop` + app 级事件钩子 `onStart / onStop / onError`（P6 已落地，§23） |
| G3 | 路径注册：方法 + 路径参数 + 查询参数 + 路由分组 | REST 动词 `onGet/onPost/...` + `onAny` + `{param}` 段参数 |
| G4 | 插件加载：中间件管道 + 插件基类 + 内置插件 | `app.use(...)`，插件可注册路由/中间件/钩子 |
| G5 | JSON 封装：统一返回体 + 对象自动序列化 | `ApiResult` + `res.jsonOk/jsonFail` + `req.body<T>()` |
| G6 | 文档：Swagger 风格 `/docs` + OpenAPI 3.0 导出 + Apifox 导入 | Apifox「导入 → OpenAPI/Swagger → URL」零手工 |
| G7 | HTTP 与 WebSocket 同端口（Upgrade 分流）+ WS 独立端口两种形态 | `ws.websocket(path, fn)`（`SLang.WebSocketServer` 形态 A）与 `SLang.WebSocketServer(port).run(port)`（形态 B）——一类双形态（§4.6） |
| G8 | **依赖边界：只引用 Core / Std 两模块** | jsonc `references` 白名单 = `[Core, Std]`；禁用 Math / Render / Tensora / SLMysql / 插件体系 / 任何 native DLL |
| G9 | 请求体格式处理：json / form / multipart / bin 按 Content-Type 自动分流 | `req.bodyFormat` 判定 + 各格式读取 API（§4.4） |
| G10 | 文件上传：multipart 解析 + `UploadedFile` 类 | `req.file("f")` → `saveAs/saveInto`（§4.4） |
| G11 | 流式传输：chunked 流式响应 + SSE + 流式文件下载 | `res.stream() / res.sse() / res.sendFile()`（§4.5）；写挂起天然背压；请求侧流式 P5 |
| G12 | **handler 协程执行**：处理器独立协程派发，`await / yield / delay` 合法（`await` 可直写协程函数调用——§7.5 糖，P4.5），超时可取消 | `Coroutine.spawnClosure2` 派发 + `awaitTask` 等待 + `cfg.handlerTimeoutMs` 超时 → `cancel` + 504（§4.2 / §6.1）；闭包注册与 attribute 注册（§4.10）统一生效 |
| G13 | **认证与授权**：认证中间件（Bearer / API Key / 自定义回调，未过 → 401 短路）+ `req.auth` 身份槽 + `SLang.Jwt` claims 读取 + WS token 校验 + 文档关联 | `SLang.Plugins.auth / authBearer / authApiKey`（§4.11）+ `req.auth`（§6.3）+ `SLang.Jwt.decode` + WS 会话开头校验 / `onWsOpen` 钩子（§4.11）+ `r.security()` → OpenAPI `securitySchemes` 与 operation 级 `security`（§4.8 / §6.10）；`Jwt.sign/verify` 签验 HS256（P5 已落地，§4.11） |

### 1.2 非目标（v1 明确不做）

- HTTPS / WSS **服务端**（TLS 服务端需证书装载与 SNI，P5 再议；客户端 `Net.TlsStream` 不受影响）；
- HTTP/2、QUIC、反向代理、集群；
- 多进程 / 多 VM 实例负载模型（单 VM 协程调度即全部并发，见 §10）；
- 模板引擎 / ORM / 依赖注入容器（Spring 全家桶不做，只借其**用法形态**）；
- 流式**请求**（边收边落盘上传、Range 断点续传）：v1 请求体全量驻留内存、受上限约束，P5（**响应侧流式 chunked / SSE / 文件流为 P2 落地**，见 §4.5）；
- WASM 目标（socket 能力在 wasm 侧降级，本模块不参与 wasm 构建）。

---

## §2 现状盘点：复用与缺口

### 2.1 直接复用（不改动，全部位于 Core / Std——满足 G8）

| 现有能力 | 位置 | 在本框架中的角色 |
|----------|------|------------------|
| TCP 监听/接入（协程挂起） | `Lib/Std/Net/TcpSocket.sl`（`Tcp.listen / TcpServer.accept`） | 连接层：`HttpServerCore` 的 accept 循环 |
| WebSocket 帧层 + 服务端握手 | `Lib/Std/Net/Websocket.sl`（`WebSocketStream.accept`、`receive`、`sendText`） | WS 会话层：`WsSession` 直接包装 |
| HTTP 头集合 / 解析先例 | `Lib/Std/Net/HttpClient.sl`（`HttpHeaders`、`HttpMethod`、三态 body 读取） | 请求模型：`HttpHeaders` 直接复用；解析算法照搬改向 |
| JSON 树 + 对象序列化 | `Lib/Core/Text/BaseJson.sl`（`parse / fromData / toJson / toJsonPretty`）+ `Text.Json` | §6.7 JSON 封装 + §6.10 OpenAPI 生成 |
| 对象序列化规则 attribute | `Lib/Core/Attribute.sl`（`Serializable / SerializeField / NonSerialized`） | DTO 的成员可见性规则 |
| 协程调度 | `Lib/Core/Coroutine.sl`（`spawnClosure0..3`、`awaitTask`、`waitTimeout`、`Task.cancel`） | 每连接一协程、**每 handler 一协程**、每 WS 会话一协程；handler 超时守护（§6.1） |
| 文件读写 / 静态资源 | `Lib/Std/IO/File.sl`、`Directory.sl`、`Path.sl` | StaticFiles 插件 + `UploadedFile.saveAs` |
| 路由属性占位 | `Lib/Std/Net/Route.sl`（`@Route("/x")`，Preload、未接线、**未入 Std.jsonc 编译清单**） | P4 接线对象（见 §7） |

### 2.2 缺口（本设计补齐）

1. **HTTP/1.1 服务端**：请求行/头/body 解析、响应编码、keep-alive、状态码——`Net.md` 明言"不含 HTTP 服务端"；
2. **路由器**：方法×路径匹配、`{param}` 提取、405/404 判定、冲突检测；
3. **Request / Response 模型与返回封装**：读 API / 写 API / `ApiResult`；
4. **请求体格式处理**：Content-Type 分流、form 解码（percent-decode + `+`→空格）、multipart 解析；
5. **文件上传**：`UploadedFile` 类 + multipart 落盘；
6. **流式响应**：chunked 编码（`StreamWriter`）、SSE（`SseWriter`）、流式文件下载（`sendFile`）；
7. **中间件管道与插件框架**；
8. **OpenAPI 生成 + docs 页面**；
9. **`WebSocketStream.accept` 的预读缓冲变体**：HTTP 层已预读后才识别 Upgrade，握手需消费残留缓冲（§6.1，Std 侧唯一一处增量改动）；
10. **handler 协程派发与超时守护**：`spawnClosure2(handler, req, res)` 派发 + `awaitTask` 等待 + `waitTimeout/cancel` 超时路径（§6.1）——现有库无此编排先例（WS 会话 `spawnClosure1` 是单向派发，无等待/超时）；
11. **直接 await 协程函数调用语法**（评审⑫）：目标形态 `await persistUser( b ) as User` 一步到位、不出现中间 Task 变量——**现状直写语义错误**（`await` 操作数若为返回非 Task 的调用，会被**同步求值**后传给 `awaitTask`，§2.3 / §7.5），必须"先 `spawn` 拿 Task 再 `await`"两步。补齐方式 = Front 语法糖（§7.5，P4.5）：操作数为**有 Meta 签名的调用**且返回非 Task → 自动包 spawn 再 `awaitTask`；**返回 Task 的调用**（`httpGetAsync` 族）现状已合法直写（透传求值）。
12. **认证与授权链路**（评审⑭）：现状全缺——① 无认证中间件（Bearer / API Key / 自定义 header token 校验与 401 短路）；② 无身份传值槽（`req.auth`，§6.3）；③ **JWT 无签验原语**：SL 标准库无 SHA256/HMAC（`Lib/扩展库.md` crypto 为规划项）且 G8 禁引外部库——`Jwt.sign/verify`（HS256）留 P5+ 挂靠未来 crypto 库，**decode（不验签读 claims）纯 SL 先行**（base64url 复用 `Std/Encoding/Base64` 变体：`+`→`-`、`/`→`_`、去 `=` 填充，RFC 7515）；④ OpenAPI 生成不含认证描述（`securitySchemes` / operation 级 `security`，§6.10）；⑤ WS 升级分流在中间件管道之前（§6.1）——WS token 校验不能依赖全局中间件，须落在**会话回调开头**或插件 `onWsOpen` 钩子（§4.7 / §4.11）。补齐方式 = §4.11 全节 + `r.security()` 文档元数据（§4.8）。

### 2.3 语言层约束（已核实，设计必须绕行）

| 约束 | 来源 | 对策 |
|------|------|------|
| **`get` / `set` 是关键字**，不能作方法名 | `HttpClient.sl` 头注记（getHeader/setHeader 改名先例） | 路由注册用 **`onGet/onPost/onPut/onDelete/onPatch/onHead/onOptions/onAny`** 家族；原始形式 `app.on( "GET", path, fn )` |
| **`next` 是关键字**（ETokenType.Next） | `Parse/LexerParseToToken.cs` 2376 | 中间件第三参为 **`SLang.Next` 类型**（参数名 `nx`），放行调 **`nx.go()`** |
| **`data` 是关键字**（ETokenType.Data） | 同上 | `ApiResult` 字段名用 **`payload`**；输出 JSON 键名仍为 `"data"`（框架手工组包，§6.6） |
| `as` / `is` 是关键字 | 词法器 | 不用作任何方法名 |
| **SL 无 `virtual` 关键字**：成员方法默认可被子类重写，仅有 `override`（重写标记）/ `final`（封禁重写） | 语言作者确认；`Attribute.sl`、`Websocket.sl` 等主力库全为直接 `public void` + 子类 `override` 先例 | 基类钩子直接 `public void` 空实现；子类 `override public` 重写；不希望再被重写加 `final` |
| `Function` 闭包**无类型签名**，调用靠约定 arity | `WebSocketClient.onMessage` 先例 | 处理器/中间件签名在文档固化为**调用约定**（§4.2/§4.7），框架按约定转发 |
| **Function 变量多参直调无库内先例**（仅单参 `hMsg(msg)`） | 全 Lib/test 检索 | `(req, res)` 双参与 `(req, res, nx)` 三参依赖 `CallClosure(106)` 多参能力（IROpEnum 注记 `arg0, arg1, ...` + paramCount，机制存在）；**P0 前置探针验证**（§8） |
| **`await` 后跟返回非 Task 的函数调用 = 语义错误**：脱糖为 `awaitTask( fn(实参) )`——调用被**同步求值**，返回值（非 Task）传给 `awaitTask` | `Parse/StructParseToSyntax.cs` await 分支（操作数节点原样传入 `Coroutine.awaitTask`）；`md/syntax/coroutine.md` §4.2 文法 `await_expr := 'await' unary_expr` | 一步形态 `await fn(实参) as T` 由 **P4.5 语法糖**补齐（§7.5）；糖落地前**协程函数调用一律"先 `spawn` 拿 Task 再 `await`"两步**；**返回 Task 的调用**（`httpGetAsync` 族）透传即合法、现状可直接写 |
| 闭包**不能声明 throws** | `Serialize.sl` 文件头注记 | 框架侧全部 catch，处理器永不抛出（§6.11） |
| **跨模块 extends 模板类不支持** | `Serialize.sl` 注记 | 本模块不 extends `Stream<T>` 等模板类；`NetStream`（非模板）可 extends |
| Preload 阶段 SL `_enter_` 不执行（v1） | `ATTRIBUTE_DESIGN.md` D2 | P0–P3 不用 attribute；P4 走 C VM 原生 handler（§7） |
| 运行时**无方法枚举反射**（`Attribute.getMethodAttributes` 需先知方法名，且只返回 Runtime stage） | `Attribute.sl` + `Type.sl` 核查 | P4 用 C VM 装配期收集（§7.1），不做运行时扫描 |
| Front attribute 名称回退表仅含 `DllImport/Condition/Route→1` 等 | `ATTRIBUTE_DESIGN.md` §1 现状表 | P4 新 attribute 名需 Front 注册（§7.3 前置调研），优先复用已知名 `Route` |
| `this.字段` 直接作 if 条件有求值异常 | `Websocket.sl` 注记 | 实现遵循"先拷局部再判断"既有规避 |
| `Uri` 无 percent-decode 工具 | `Uri.sl` API 核查 | 框架内置 `_UrlCodec`（percent-decode + `+`→空格，§6.4） |

---

## §3 总体架构

```
                        ┌────────────────────────────────────────────────┐
                        │  SLang.HttpServer（HTTP 应用门面 = App）          │
                        │  SLang.WebSocketServer（WS 门面·双形态路由器）   │
                        │  路由表 / 插件列表 / ServerConfig（§4.9）        │
                        └───────┬───────────────────────────┬────────────┘
                                │ 注册                       │ 注册
              ┌─────────────────▼──────────┐   ┌────────────▼─────────────┐
              │ Router（HTTP 路由）          │   │ WsRouter（WS 升级路由）    │
              │ Method+Pattern → RouteInfo  │   │ Pattern → WsRouteInfo     │
              └─────────────────▲──────────┘   └────────────▲─────────────┘
                                │ 匹配                        │ Upgrade 分流
┌───────────────────────────────┴────────────────────────────┴──────────────┐
│ HttpServerCore（连接引擎，每连接一协程）                                       │
│  accept 循环 → 请求解析（请求行/头/body：Content-Length|chunked|EOF）
│  → 中间件管道（req, res, nx；连接协程内联） → handler 协程派发（spawnClosure2 → awaitTask / 超时 cancel）
│  → 管道后置环回程 → 响应编码（keep-alive/chunked）
│  → Upgrade: websocket ? WebSocketStream.acceptBuffered(残留缓冲) ──► WsSession│
└───────────────────────────────┬────────────────────────────────────────────┘
                                │ 复用（不改动）—— 仅 Core / Std
              ┌─────────────────▼──────────────────────────────┐
              │ Net.TcpServer / TcpStream（C VM 协程挂起 IO）    │
              │ Net.WebSocketStream（帧层/握手）  BaseJson（序列化）│
              └────────────────────────────────────────────────┘
        BodyParser（Content-Type 分流：Json/Form/Multipart/Text/Binary）
            ├─ form 解码（_UrlCodec：percent-decode + '+'→空格）
            └─ multipart 解析（boundary/part 头/文件名安全剥离）→ UploadedFile

WS 双形态（SLang.WebSocketServer 一类承载）：形态 A = 升级路由器（与 HttpServer 同端口，Upgrade 分流）· 形态 B = 独立端口服务器（SLang.WebSocketServer( port )）——不经 HTTP，裸 TCP + WS 握手直入 WsSession
```

**并发模型**：C VM 协程单线程协作调度 → **框架全部共享状态（路由表/会话表）无锁**，这是设计不变量（§10）。

**分层原则**：`HttpServer` / `WebSocketServer`（门面/组装）→ `Router`/`WsRouter`（匹配）→ `HttpServerCore`（协议 IO）→ `BodyParser`（格式）→ `Net.*`（传输）。插件只允许触碰门面层 API。

---

## §4 语法设计（核心章节：使用简单）

> 本章是 API 契约的**权威定义**；所有示例语法均已对照现有库先例（`var` / 闭包字面量 / 方法重载 / 链式返回 this）与词法器关键字表校验。
> 用户侧可用 typealias 缩短书写（`md/syntax/typealias.md`）：
> `typealias Req = SLang.Request;` · `typealias Res = SLang.Response;`

### §4.1 最小可用（HTTP）

```sl
import SLangServer;

var app = SLang.HttpServer();
app.onGet( "/hello", function( SLang.Request req, SLang.Response res )
{
    res.text( "hello world" );
} );
app.run( 8080 );          # 阻塞当前协程直至 stop()；启动横幅打印 http://0.0.0.0:8080
```

- `run(port)` = `start(port)` + `awaitStop()`；`start` 立即返回（accept 循环进新协程），`stop()` 优雅收尾。
- 重复注册同 method+pattern：`start()` 时抛 `ServerError.DuplicateRoute`。
- 未匹配路径 → 404 + `ApiResult` JSON 体；路径命中但方法不命中 → 405。
- WebSocket 不在 `app` 上：升级路由与独立端口一律经 `SLang.WebSocketServer`（§4.6）。

```sl
# ── 异步处理器（真实业务约半数是异步的；协程派发见 §4.2，无需任何额外声明）──
app.onGet( "/ip", function( SLang.Request req, SLang.Response res )
{
    # 直接 await 一步到位：httpGetAsync 返回 Task，await 直写调用即透传求值——现状合法（§7.5）
    Net.HttpResponse r = await Net.HttpClient.httpGetAsync( "http://api.ipify.org" ) as Net.HttpResponse;
    res.text( r.body );        # 挂起等下游期间，其他请求照常并发
} );
```

### §4.2 路径注册（目标②）

```sl
# ── 动词注册（get/set 是关键字 → 统一 on 前缀）──
# onGet / onPost / onPut / onDelete / onPatch / onHead / onOptions / onAny
app.onPost( "/api/users", function( SLang.Request req, SLang.Response res )
{
    # body JSON → DTO（Serializable 类；解析失败返回 null）
    CreateUserReq body = req.body<CreateUserReq>();
    if body == null
    {
        res.jsonFail( 400, "bad json body" );
        ret
    }
    var u = User( 1, body.name );
    res.status( 201 ).jsonOk( u );
} );

# ── 路径参数 {name}（单段匹配）──
app.onGet( "/api/user/{id}", function( SLang.Request req, SLang.Response res )
{
    Int32 id = req.pathInt( "id", 0 );        # 带默认值；坏格式回落默认
    ...
} );

# ── 查询参数 ?page=1&size=20 ──
app.onGet( "/api/users", function( SLang.Request req, SLang.Response res )
{
    Int32 page = req.queryInt( "page", 1 );
    Int32 size = req.queryInt( "size", 20 );
    ...
} );

# ── 通配后缀（P2）：/static/{path*} 匹配剩余全部段 ──

# ── 路由分组（前缀提取，Spring @RequestMapping 形态）──
var api = app.group( "/api/v1" );
api.onGet( "/users",  listUsers );
api.onPost( "/users", createUser );

# ── 原始形式（动态注册 / 方法变量）──
app.on( "GET", "/ping", pingHandler );
```

**处理器签名（调用约定）**：`function( SLang.Request req, SLang.Response res )`——**req 只读请求、res 只写响应**；无返回值语义（响应一律经 `res.*` 写出）。

**处理器执行模型（协程派发，G12）**——`app.onPost` 等**闭包注册**与 §4.10 **attribute 控制器**统一生效，用户代码无需感知派发细节：

- 框架对每个请求执行 `Coroutine.spawnClosure2( handler, req, res )`——handler 运行在**独立协程**，不在连接协程内联（`WsSession` 会话协程同款先例，§6.8；机制详见 §6.1）；
- handler 内可自由使用 `await`（等待 Task / Channel）、`yield`（`Coroutine.yieldNow()` 让出调度）、`Coroutine.delay`——SSE 逐帧推送（§4.5）、聚合下游异步调用等场景无需任何额外声明；`await` 操作数三种形态：**Task 变量**（`await t as T`）、**返回 Task 的调用**（`await httpGetAsync( url ) as T`——透传求值，现状即合法）、**返回非 Task 的协程函数调用**（`await persistUser( b ) as User`——§7.5 语言糖一步到位；P4.5 落地前须"先 `spawn` 拿 Task 再 `await`"两步）；
- 连接协程 `awaitTask` 等 handler 协程完成后再编码响应、继续 keep-alive 循环——**同一连接上请求严格串行，跨连接天然并发**；
- 超时守护 `cfg.handlerTimeoutMs`（§4.9）：超时 → `task.cancel()`（协作式取消）+ 504 + 断连；响应已进入流式/已提交后守护移交 `writeTimeoutMs`（§6.1）；
- 单线程协作调度不变量（§3）：协程化提供的是 **IO 并发**而非 CPU 并行（§10 风险 5）。

```sl
# ── 异步 handler 写法速览（修订⑪：签名与同步 handler 完全一致——是否 await 只关乎方法体内部，框架无需任何额外声明；
#    修订⑬：场景库扩至 8 条：顺序等 / 并发聚合 / 直接 await / DB 多表并发 waitAll / 竞速 waitAny / 串行依赖链 / fire-and-forget / 原语速查）──

# 1) 顺序 await：等单个下游——httpGetAsync 返回 Task，await 直写调用即透传（现状合法，§7.5）
app.onGet( "/api/ip", function( SLang.Request req, SLang.Response res )
{
    Net.HttpResponse r = await Net.HttpClient.httpGetAsync( "http://api.ipify.org" ) as Net.HttpResponse;
    res.text( r.body );      # 挂起等下游期间：该连接空闲、其他请求照常执行
} );

# 2) 并发聚合：先发起多个下游、再依次 await——总耗时 ≈ 最慢者（不是相加）
#    ⚠ 与直接 await 的分界：直接 await 是"顺序等"（前一个完成才开始下一个，耗时相加），
#      并发聚合必须保留显式发起——Task 变量先拿、再逐个 await；协程函数用显式 spawn（§7.5）
app.onPost( "/api/report", function( SLang.Request req, SLang.Response res )
{
    Task t1 = Net.HttpClient.httpGetAsync( "http://svc-a/orders" );   # 发起即让出
    Task t2 = Net.HttpClient.httpGetAsync( "http://svc-b/users" );    # 两个下游已并行在跑
    Net.HttpResponse r1 = await t1 as Net.HttpResponse;
    Net.HttpResponse r2 = await t2 as Net.HttpResponse;
    res.jsonOk( SystemStringLength( r1.body ) + SystemStringLength( r2.body ) );
} );

# 3) 直接 await 协程函数调用拿单一结果（DB 访问 / 重计算封装成协程函数，主流程保持线性）
app.onGet( "/api/orders", function( SLang.Request req, SLang.Response res )
{
    List<string> orders = await queryOrders( req.queryInt( "page", 1 ) ) as List<string>;
    # 直接 await 一步到位：返回非 Task 的调用由 §7.5 糖自动包 spawn 再 awaitTask（P4.5 已落地）
    Coroutine.delay( 100 );          # delay / yieldNow 让出调度：均合法
    res.jsonOk( orders.length );
} );

# 4) 数据库查询：多表并发 + 等其它任务全部执行完（waitAll）——DB 访问（Sqlite / SLMysql 封装）
#    封装为协程函数后即可 spawn / await；三个查询并行在跑，waitAll 挂起直到全部完成，
#    总耗时 ≈ 最慢的一条 SQL（不是三条相加）；waitAll 后逐个 await 只是取各自结果、立即返回不阻塞
app.onGet( "/api/report", function( SLang.Request req, SLang.Response res )
{
    Int32 day = req.queryInt( "day", 0 );
    Task t1 = spawn queryOrders( day );       # 并发必须显式 spawn（写法 2 同款分界，§7.5）
    Task t2 = spawn queryUsers( day );
    Task t3 = spawn queryStats( day );
    Coroutine.waitAll( t1, t2, t3 );          # 等其它任务执行完：全部完成才返回（params 家族）
    List<string> orders = await t1 as List<string>;   # 已完成：await 立即返回
    List<string> users  = await t2 as List<string>;
    Int32 total = await t3 as Int32;
    res.jsonOk( orders.length + users.length + total );
} );

# 5) 竞速取最快（waitAny）：同一资源多镜像源并发拉取，谁先回来用谁；落选者照常跑完不干扰
app.onGet( "/api/mirror", function( SLang.Request req, SLang.Response res )
{
    string path = req.query( "path" );
    Task t1 = Net.HttpClient.httpGetAsync( "http://mirror-a/" + path );
    Task t2 = Net.HttpClient.httpGetAsync( "http://mirror-b/" + path );
    Task first = Coroutine.waitAny( t1, t2 ); # 任一完成即返回该 Task
    Net.HttpResponse r = await first as Net.HttpResponse;
    res.text( r.body );
} );

# 6) 串行依赖链：前一个 await 的结果决定下一个的入参——只能顺序等（耗时相加），写法 4 的并发不适用
app.onGet( "/api/user/{id}/orders", function( SLang.Request req, SLang.Response res )
{
    User u = await queryUser( req.pathInt( "id", 0 ) ) as User;    # 直接 await（§7.5 糖，P4.5 已落地）
    if u == null
    {
        res.jsonFail( 404, "user not found" );
        ret
    }
    List<string> orders = await queryUserOrders( u ) as List<string>;  # 依赖前序结果 u：必须等完才发
    res.jsonOk( orders );
} );

# 7) fire-and-forget 后台任务：记审计 / 发通知等慢旁路 spawn 出去就走，刻意不 await、响应先回；
#    任务在自身协程上跑完自动结束，不阻塞本 handler 与连接（§6.1）
app.onPost( "/api/orders", function( SLang.Request req, SLang.Response res )
{
    Order o = req.body<Order>();
    Int32 id = await createOrder( o ) as Int32;   # 主链路：落单必须等结果（直接 await，§7.5 糖，P4.5）
    Task t = spawn sendNotify( id );              # 旁路：拿到 Task 但不等——响应不因通知变慢
    res.status( 201 ).jsonOk( id );
} );

# 8) 多任务聚合原语与 Channel 协作（handler 内片段）：
#    Coroutine.waitAll( t1, t2 )            # 全部完成才返回（params 家族）
#    Task first = Coroutine.waitAny( t1, t2 )   # 任一完成即返回该 Task
#    Channel<T>( capacity )                 # Core/Container：send 满则挂起、recv 空则挂起、close 后取尽 → null
#                                            #（SSE 逐帧消费实战见 §4.5 "2b"，会话协程用法见 §4.6）
```

### §4.3 JSON 返回封装（用户点名功能一）

统一返回体 `ApiResult`（注意：类字段名 `payload`，**输出 JSON 键名仍为 `"data"`**，见 §6.6）：

```json
{ "code": 0, "message": "ok", "data": { "id": 1, "name": "tom" } }
```

```sl
public class ApiResult
{
    public Int32 code = 0                # 0 = 成功；非 0 业务错误码（用户自定义段 ≥ 1000）
    public string message = "ok"
    public object payload = null         # 任意 Serializable 对象 / null（data 是关键字，字段名用 payload）
}
```

`res` 写出 API：

| API | 语义 |
|-----|------|
| `res.json( obj )` | 任意对象 → `BaseJson.fromData` → `application/json; charset=utf-8`，200 |
| `res.jsonOk( payload )` | = `res.json( ApiResult.ok( payload ) )`（统一封装） |
| `res.jsonFail( code, msg )` | = `res.json( ApiResult.fail( code, msg ) )`，HTTP 仍 200（业务码与 HTTP 码分离，Apifox 侧按 code 断言） |
| `res.jsonFail( code, msg, httpStatus )` | 三参重载，同时改 HTTP 状态码 |
| `res.rawJson( text )` | 预构建 JSON 串直写（OpenApiBuilder 等内部使用） |
| `res.text( s )` / `res.html( s )` | `text/plain` / `text/html`，200 |
| `res.bytes( buf )` | 二进制（`ByteBuffer`），默认 `application/octet-stream` |
| `res.file( path )` / `res.file( path, downloadName )` | 文件下载：按扩展名置 MIME + `Content-Disposition`（P2） |
| `res.redirect( url )` | 302 + `Location` |
| `res.status( code )` | 链式置状态码，返回 res |
| `res.header( k, v )` | 链式追加响应头，返回 res |
| `res.contentType( mime )` | 链式覆盖 Content-Type，返回 res |

链式组合示例：`res.status( 201 ).header( "X-Trace-Id", tid ).jsonOk( u )`。
终端方法（json 族 / text / html / bytes / file / redirect）**第二次调用抛 `ServerError.AlreadyResponded`**（开发期防重复写出）。

### §4.4 请求体格式与文件上传（v2 新增，目标 G9/G10）

**按 Content-Type 自动分流**（`req.bodyFormat` 只读属性，`EBodyFormat` 枚举）：

| Content-Type | `req.bodyFormat` | 读取 API |
|--------------|------------------|----------|
| `application/json`（含 `+json` 后缀） | `EBodyFormat.Json` | `req.bodyJson()` → BaseJson · `req.body<T>()` → DTO |
| `application/x-www-form-urlencoded` | `EBodyFormat.Form` | `req.form( name )` / `req.formInt( name, def )` / `req.formBool( name, def )` · `req.hasForm( name )` · `req.formKeys()` |
| `multipart/form-data` | `EBodyFormat.Multipart` | 普通字段同 form API；文件走 `req.file / req.files` |
| `text/*` | `EBodyFormat.Text` | `req.bodyText()` |
| 其余（`application/octet-stream` 等） | `EBodyFormat.Binary` | `req.bodyBytes()` → ByteBuffer |
| 无 body（GET/HEAD/长度 0） | `EBodyFormat.None` | 各 API 返回空值 |

```sl
# ── form 表单（application/x-www-form-urlencoded）──
app.onPost( "/api/login", function( SLang.Request req, SLang.Response res )
{
    string user = req.form( "username" );          # 已 percent-decode + '+'→空格
    string pass = req.form( "password" );
    if SystemStringLength( user ) == 0
    {
        res.jsonFail( 400, "username required" );
        ret
    }
    ...
} );

# ── JSON body ──
app.onPost( "/api/users", function( SLang.Request req, SLang.Response res )
{
    CreateUserReq body = req.body<CreateUserReq>();
    ...
} );

# ── bin（原始二进制，如 protobuf / 图片直传）──
app.onPost( "/api/raw", function( SLang.Request req, SLang.Response res )
{
    ByteBuffer b = req.bodyBytes();
    ...
    b.release();
} );

# ── 文件上传（multipart/form-data）──
app.onPost( "/api/upload/avatar", function( SLang.Request req, SLang.Response res )
{
    SLang.UploadedFile f = req.file( "avatar" );       # 单文件（字段名；null = 无）
    if f == null
    {
        res.jsonFail( 400, "no file" );
        ret
    }
    if f.size > 5242880
    {
        res.jsonFail( 400, "file too large" );
        ret
    }
    f.saveAs( "./uploads/avatar_" + f.filename );      # 落盘
    res.jsonOk( f.filename );
} );

# ── 多文件同字段（如批量照片）──
app.onPost( "/api/upload/photos", function( SLang.Request req, SLang.Response res )
{
    List<SLang.UploadedFile> list = req.files( "photos" );
    for Int32 i = 0, i < list.length, i = i + 1
    {
        list[i].saveInto( "./uploads" );               # 目录 + 原名（重名自动改名 file(1).txt）
    }
    res.jsonOk( req.fileCount );
} );
```

**`SLang.UploadedFile`（文件上传类，目标 G10）**：

| 成员 | 语义 |
|------|------|
| `f.field` → string | 表单字段名 |
| `f.filename` → string | 原始文件名（**已剥离路径**，防 `../` 穿越，只留 basename） |
| `f.contentType` → string | part 声明的 Content-Type |
| `f.size` → Int64 | 字节数 |
| `f.ext()` → string | 扩展名（小写、无点；无扩展空串） |
| `f.bytes()` → ByteBuffer | 内容视图（归属文件对象，请求结束统一回收；勿跨请求持有） |
| `f.saveAs( path )` → bool | 落盘到指定完整路径（`Std.IO.File`） |
| `f.saveInto( dir )` → bool | 落盘到目录 + 原文件名（重名自动改名 `name(1).ext`） |

配套配置（§4.9）：`maxUploadBytes`（multipart 请求总量上限，默认 100MB）、`maxFileBytes`（单文件上限，默认 50MB）；超限 413 断连。上传目录不存在时由用户保证（`saveAs` 失败返回 false，不自动建目录——显式优于隐式）。

### §4.5 流式传输（chunked / SSE / 文件流，目标 G11）

**1. chunked 流式响应**（`Transfer-Encoding: chunked`，边生成边下发）：

```sl
app.onGet( "/api/export", function( SLang.Request req, SLang.Response res )
{
    res.status( 200 ).contentType( "text/plain" );    # 头部设置须在 stream() 之前完成
    SLang.StreamWriter w = res.stream();              # 即刻发出状态行+头，进入流式态
    for Int32 i = 0, i < 10, i = i + 1
    {
        w.write( "part " + i.toString() + "\n" );     # 每次 write 即编码一个 chunk 下发
        Coroutine.delay( 100 );
    }
    w.close();                                        # 0 长终止块，响应完成，连接可继续复用
} );
```

**2. SSE**（`text/event-stream`，浏览器 `EventSource` / Apifox 可直连——AI 流式输出标配）：

```sl
app.onGet( "/api/sse/progress", function( SLang.Request req, SLang.Response res )
{
    SLang.SseWriter sse = res.sse();                  # 自动置 Content-Type + Cache-Control: no-cache
    for Int32 i = 0, i <= 100, i = i + 10
    {
        sse.sendEvent( "progress", i.toString() );    # → "event: progress\ndata: 10\n\n"
        Coroutine.delay( 500 );
        sse.comment( "keepalive" );                   # 心跳注释行，防中间层掐空闲连接
    }
    sse.send( "done" );                               # 默认事件 → "data: done\n\n"
    sse.close();
} );
```

**2b. SSE + Channel/await**（每帧数据来自异步生产者——AI 流式输出 / 任务进度推送同款；`recv()` 无数据自动挂起，不空转）：

```sl
app.onGet( "/api/sse/tokens", function( SLang.Request req, SLang.Response res )
{
    SLang.SseWriter sse = res.sse();
    Channel<string> ch = Channel<string>( 8 );     # Core/Container/Channel；有界 → 生产者写满即挂起（背压）
    spawn aiGenerate( ch );                        # 生产者协程：逐 token ch.send( ... )，完毕 ch.close()
    string token = ch.recv();                      # 空则挂起等数据
    while token != null
    {
        sse.send( token );                         # 每收一个 token 推一帧
        token = ch.recv();
    }
    sse.close();                                   # 生产者 close → recv 取尽返回 null → 循环自然退出
} );
```

**3. 流式文件下载**（大文件 64KB 分块读发，不整载内存）：

```sl
app.onGet( "/download/{name}", function( SLang.Request req, SLang.Response res )
{
    res.sendFile( "./files/" + req.pathParam( "name" ) );   # Content-Length=文件大小 → 非 chunked
} );
```

要点：

- `res.stream()` / `res.sse()` 是**流式终端**：调用即发出响应头并锁定响应（此后 `res.json` 等终端方法抛 `ServerError.AlreadyResponded`）；`sendFile` 是普通终端（内部流式实现，对用户透明）；
- `SLang.StreamWriter`：`write( string )` / `writeBytes( ByteBuffer )` / `flush()`（空操作——写路径即时下发、无用户态缓冲，`NetStream.flush` 同款语义，保留 API 习惯）/ `close()`；handler 未调 `close()` 即退出时框架**兜底补终止块**（防连接悬挂）；
- `SLang.SseWriter`：`send( data )` / `sendEvent( event, data )` / `comment( text )`（心跳注释行）/ `close()`；
- **背压**：底层 `TcpStream.write` 写不出去时协程挂起（C VM 挂起语义）→ 慢客户端天然限速、发送缓冲不膨胀；
- 超时与保活：`cfg.writeTimeoutMs`（§4.9，默认 30s）防慢客户端拖死协程；流式期间每次写出刷新 keep-alive 空闲计时；
- OpenAPI 文档：SSE 接口的响应 content 记 `text/event-stream`（§6.10）；
- **请求侧流式（P5 展望）**：注册期 `r.streamBody = true` → 解析器不预读 body → `req.bodyStream()` 返回 `HttpBodyReader`（`read( ByteBuffer )` 循环、上限累计）→ 边收边落盘上传，超大文件不驻留内存（详见 §6.6）。

### §4.6 WebSocket：`SLang.WebSocketServer`（两种形态）

**构造形态即语义**：`SLang.WebSocketServer()` 不传端口 = **形态 A**（升级路由器，与 HttpServer 同端口）；`SLang.WebSocketServer( port )` 传端口 = **形态 B**（独立端口服务器）。

**形态 A：HTTP 同端口升级路由**（推荐，FastAPI `@app.websocket` 对应物）

```sl
# 每连接一协程；receive() 返回 null = 连接关闭（WebSocketClient 事件循环同款语义）
var app = SLang.HttpServer( 8080 );
var ws  = SLang.WebSocketServer();
ws.websocket( "/ws/chat", function( SLang.WsSession s )
{
    while true
    {
        Net.WsMessage m = s.receive();
        if m == null
        {
            break
        }
        s.sendText( "echo: " + m.text() );
        m.release();
    }
} );

app.run( 8080 );  # 同一端口：HTTP 路由 + WS 升级并存（Upgrade 分流在管道之前，§6.1）
```

**handler 内 await**（会话协程内随处挂起——等待期间本协程让出调度，其他会话照常收发）：

```sl
# 消息触发异步任务 → await 结果回推（重活封装成协程函数，主循环保持线性）
ws.websocket( "/ws/job", function( SLang.WsSession s )
{
    while true
    {
        Net.WsMessage m = s.receive();
        if m == null
        {
            break
        }
        string out = await runJob( m.text() ) as string;
        # 直接 await 一步到位：返回非 Task 的调用由 §7.5 糖自动包 spawn（P4.5 已落地）；
        # 挂起等结果期间其他会话不受影响；
        s.sendText( out );
        m.release();
    }
} );
```

**事件式糖（P2）**——内部仍是一协程，适合不想写循环的场景：

```sl
ws.wsEvents( "/ws/chat" )
    .onOpen(    function( SLang.WsSession s ) { ... } )
    .onMessage( function( SLang.WsSession s, Net.WsMessage m ) { ...; m.release() } )
    .onClose(   function( SLang.WsSession s ) { } );   # 回调签名：onOpen/onClose = ( s )；onMessage = ( s, m )
```

**形态 B：独立端口 WS 服务**（无 HTTP 层，裸 TCP 直握手）

```sl
var wss = SLang.WebSocketServer( 9000 );   # 传端口 = 形态 B：独立端口服务器
wss.onMessage( function( SLang.WsSession s, Net.WsMessage m )     # 方法注册（传闭包实参，非字段赋值）
{
    s.sendText( "echo: " + m.text() );
    m.release();
} );
wss.onClose( function( SLang.WsSession s ) { } );
wss.run( 9000 );  # 或 start() / start( port ) / stop() / awaitStop()；isRunning 查运行态
```

**会话与广播**：

```sl
s.id                    # string，GUID（会话注册表键）
s.remoteAddress         # "ip:port"
s.routePattern          # 命中的路由模式（如 "/ws/chat/{room}"）
s.pathParam( "room" )   # 升级 URL 的路径参数（与 HTTP 路由同一套 {param} 语法）
s.pathInt( "id", 0 )    # 整型便捷（带缺省值）
s.query( "token" )      # 升级 URL 查询参数
s.sendText / s.sendBinary / s.sendPing / s.close / s.closeInfo / s.isOpen

ws.sessions( "/ws/chat" )            # 形态 A：→ List<WsSession>（该路由在线会话）
ws.broadcast( "/ws/chat", "hi" )     # 形态 A：组播文本 → Int32 送达数
ws.broadcast( "/ws/chat", payload )  # 形态 A：组播二进制（P6，§21 偏差 ④ 已落地）
ws.broadcastTag( "/ws/chat", "vip", "go" )   # 形态 A：标签定向文本（P6，§21 偏差 ② 已落地）
wss.sessions()                       # 形态 B：→ List<WsSession>（全部在线会话）
wss.broadcast( "hi" )                # 形态 B：组播文本 → Int32
ws.idleTimeout( 15000 );             # WS 空闲心跳（P5）：写 ServerConfig.wsIdleTimeoutMs，<= 0 不启用（缺省关）；
                                     # 形态 A 时序 = 先构造 HttpServer 再调用（§20）
```

- `s.tag( name )` / `s.untag( name )` / `s.tagged( name )` / `s.tags`（`List<string>` 快照）已随 P6 落地（§23）；`broadcastTag` 亦有二进制载荷重载——`broadcast` / `broadcastTag` 全家族 = 两形态 × 文本/二进制 × 全量/定向共 12 方法。

### §4.7 中间件与插件（目标③）

**中间件**（Koa 洋葱模型，全局注册；三参签名，`next` 是关键字 → `SLang.Next nx` + `nx.go()` 放行）：

```sl
# 签名约定：function( SLang.Request req, SLang.Response res, SLang.Next nx )
# 调 nx.go() 放行进下一环；不调 = 短路（CORS 预检 / 鉴权拒绝等）
app.use( function( SLang.Request req, SLang.Response res, SLang.Next nx )
{
    Int64 t0 = Timer.millis();                      # Std/OS/Timer，依赖边界内
    string token = req.header( "Authorization" );
    if SystemStringLength( token ) == 0
    {
        res.jsonFail( 401, "unauthorized" );        # 短路：管道终止，不再进 handler
        ret
    }
    req.userData = "uid:1";                         # 中间件 → 处理器传值（object 槽）
    nx.go();                                        # 放行
    Console.println( "cost " + ( Timer.millis() - t0 ) + "ms" );   # 后置逻辑
} );
```

**中间件内同样可以 await**（中间件内联于连接协程——有栈协程任意深度挂起；异步鉴权 / 限流查下游等场景合法，后置环仍能正常回程）：

```sl
app.use( function( SLang.Request req, SLang.Response res, SLang.Next nx )
{
    # 直接 await 一步到位：返回 Task 的调用透传即合法（§7.5）
    Net.HttpResponse r = await Net.HttpClient.httpGetAsync( "http://auth-svc/check?token=" + req.query( "token" ) ) as Net.HttpResponse;
    # 挂起等下游鉴权结果
    if !r.isOk
    {
        res.jsonFail( 401, "token invalid" );           # 短路：管道终止，不进 handler
        ret
    }
    nx.go();                                            # 放行（后置环在 handler 协程完成后回程）
} );
```

**插件**（`ServerPlugin` 基类，钩子方法默认空实现——SL 无 `virtual` 关键字，方法默认可被子类 `override` 重写，避免 interface 可选方法问题）：

```sl
public class ServerPlugin
{
    public void onInstall() { }                     # 注册中间件/路由/钩子的唯一入口（子类 override 重写；无参——闭包零捕获纪律，插件内注册走引擎级形态，§21 偏差 ①）
    public void onStart() { }                        # start 后、accept 前
    public void onStop() { }                         # stop 收尾
    public void onWsOpen( SLang.WsSession s ) { }    # WS 会话级钩子（可做在线统计）
    public void onWsClose( SLang.WsSession s ) { }   # 不希望子类再重写时加 final
}

# 使用：一行装一个插件
app.use( SLang.Plugins.logger() );                 # 请求日志（方法/路径/状态/耗时）
app.use( SLang.Plugins.cors() );                   # CORS（自动应答 OPTIONS 预检）
app.use( SLang.Plugins.staticFiles( "./www" ) );   # 静态目录（内置 MIME 表，见附录 B）

# 自定义插件
public class AuthPlugin extends SLang.ServerPlugin
{
    override public void onInstall()                        # 无参 → 注册走引擎级形态（语义等价 app.use，§21 偏差 ①）
    {
        SLang.HttpServerCore.use( function( SLang.Request req, SLang.Response res, SLang.Next nx ) { ... } );
    }
}
app.use( AuthPlugin() );
```

内置插件实况：`logger / cors / staticFiles`（P2 已落地）· `auth / authBearer / authApiKey`（P3 已落地，§4.11）· `rateLimit( max, windowMs )`（P5 已落地：按 IP 固定窗口，超限 429 短路）；`bodyLimit / requestId` 为设计项未落地。用户自定义插件即普通类，**无注册中心、无配置文件**，`app.use` 是唯一挂载点。

### §4.8 API 文档：/docs + OpenAPI + Apifox（用户点名功能二）

**使用**：`app.run()` 时自动挂载 `GET /docs` 与 `GET /openapi.json`（`app.docs( false )` 关闭，生产建议关）。

**文档元数据在注册时顺手填**（返回 `RouteInfo`，字段公开 + 链式便捷方法二选一）：

```sl
var r = app.onGet( "/api/user/{id}", getUserHandler );
r.summary = "获取单个用户";
r.tags = "用户";                          # 逗号分隔多标签
r.desc = "按 id 查询用户详情";

# 参数与 schema：实例探针法（传样例实例 → BaseJson.fromData → JSON 树 → 推导 schema）
# 不需要任何运行时反射（语言层无字段枚举，这是唯一零依赖方案）
r.param( "id", "integer", "用户ID", true );            # path/query 参数
r.requestBody( CreateUserReq() );                      # JSON body schema + example
r.formField( "username", "string", "用户名" );          # form 字段 → urlencoded requestBody schema
r.uploadField( "avatar", "头像文件", "image/*" );       # multipart 文件字段
r.response( 200, User() );                              # 响应 schema + example
r.response( 404, SLang.ApiResult.fail( 1001, "no such user" ) );
r.security( "bearerAuth" );                              # 认证要求 → operation 级 "security"（§4.11）

# 链式等价形式：
app.onGet( "/api/users", listHandler ).summary( "用户列表" ).tag( "用户" ).response( 200, User() );
```

**`/docs` 页面**：自包含单文件 HTML（内嵌字符串常量，零外链、零 CDN——`wasm/playground.html` 同款离线策略），渲染接口分组/参数/示例，GET 接口支持页内 try-it-out（同源 fetch）。

**`/openapi.json`**：OpenAPI 3.0.3 规范（`info / servers / paths / parameters / requestBody / responses / components.schemas` + `components.securitySchemes`——凡有路由填过 `r.security(...)`，即生成 `bearerAuth`（`type:"http", scheme:"bearer", bearerFormat:"JWT"`）/ `apiKeyAuth`（`type:"apiKey", in:"header", name:"X-API-Key"`）定义 + operation 级 `"security"` 要求，§4.11 / §6.10）。**Apifox 导入路径**：项目设置 → 数据导入 → OpenAPI/Swagger → 填 `http://<host>:<port>/openapi.json`（或下载文件导入）→ 接口/分组/示例/**认证方式**全量进入 Apifox（导入后每个接口的"Auth"自动配好 Bearer/API Key，调试请求自动附认证头，无需手工配置）。Postman / SwaggerHub / Insomnia 同理。

**反向导入（从 Apifox 导出 → 生成路由骨架）**：

```sl
# Apifox 导出 OpenAPI json 后：
var imported = app.importOpenApi( "api-spec.json" );   # → Int32（导入的路径数）
# 语义：未注册的路径以"文档路由"登记（/docs 可见、命中返回 501 ApiResult）
# 后续可用 app.onGet(...) 覆盖同名文档路由 → 设计先行/接口契约对齐工作流
```

### §4.9 生命周期与配置（目标①）

```sl
var app = SLang.HttpServer();

# ── 配置（字段直改，无 builder 链）──
var cfg = app.config;
cfg.host = "0.0.0.0";
cfg.port = 8080;                 # run(port) 为便捷覆盖
cfg.keepAliveTimeoutMs = 15000;  # 空闲连接超时（超时静默断开）
cfg.handlerTimeoutMs = 30000;    # handler 协程执行超时（防 await 死等；<= 0 无限等待；超时 cancel + 504 + 断连；流式开启/响应提交后移交 writeTimeoutMs）
cfg.writeTimeoutMs = 30000;        # 流式写挂起超时（防慢客户端拖死；<= 0 无限等待）
cfg.maxHeaderBytes = 16384;      # 请求头上限，超出 431
cfg.maxBodyBytes = 10485760;     # 普通请求 body 上限 10MB，超出 413
cfg.maxUploadBytes = 104857600;  # multipart 请求总量上限 100MB，超出 413
cfg.maxFileBytes = 52428800;     # 单文件上限 50MB，超出 413
cfg.maxConnections = 1024;       # 并发连接上限，超出 503（P3 生效）
cfg.wsIdleTimeoutMs = 0;         # WS 空闲心跳（P5）：<= 0 不启用（缺省关）；ws.idleTimeout( ms ) 同款写口（§4.6）
cfg.jwtSecret = "...";           # Jwt.sign/verify 默认密钥（P5，§4.11；sign/verify 两参便捷形态用它）

# ── 事件钩子（P6 已落地，§23；字段赋值右侧不能直接写闭包字面量——先存局部变量再赋值）──
function hOnStart = function() { Console.println( "up" ) }
app.onStart  = hOnStart;             # start 末尾触发（插件 onStart 之后）；钩子零捕获（体内只能引用全局静态）
function hOnStop = function() { Console.println( "down" ) }
app.onStop   = hOnStop;               # stop 收尾触发（插件 onStop 之后）
function hOnError = function( SLang.Request req, SLang.Response res, Error e ) { ... }
app.onError  = hOnError;              # 管道 catch 接线（处理器异常兜底；钩子内可写响应自救，未写则 500）

# ── 启停 ──
app.start( 8080 );    # 立即返回；accept 循环独立协程
app.awaitStop();      # 挂起直至 stop()（run = start + awaitStop）
app.stop();           # 关监听 → 逐个关会话/连接 → onStop 钩子
app.isRunning         # get bool
```

### §4.10 attribute 控制器（C# 风格映射路由，P4）

**动词专属 attribute 家族**：`@OnGet / @OnPost / @OnPut / @OnDelete / @OnPatch / @OnHead / @OnOptions / @OnAny`——与 §4.2 的 `onGet/onPost/...` API 家族**一一同名映射**；`@OnPost( "admin/user" )` 一参即路径（C# `[HttpPost("...")]` 同款形态）。

```sl
public class UserController
{
    @OnGet( "/api/users/{id}" )                   # 一参 = 路径；同步方法照常写
    public void getUser( SLang.Request req, SLang.Response res ) { ... }

    @OnPost( "/api/users" )                       # @OnPost("admin/user") 同款形态；异步/同步方法随意混排
    public void createUser( SLang.Request req, SLang.Response res )
    {
        CreateUserReq b = req.body<CreateUserReq>();
        User u = await persistUser( b ) as User;  # 直接 await 一步到位（§7.5 糖，P4.5 已落地）——派发时本方法已在
                                                  # handler 协程上运行（§6.1），落库等慢操作封装为协程函数即可，
                                                  # 方法体内无需再 spawn 拿 Task；
        res.status( 201 ).jsonOk( u );
    }

    @OnPut( "/api/users/{id}" )
    public void updateUser( SLang.Request req, SLang.Response res ) { ... }

    @OnDelete( "/api/users/{id}" )
    public void removeUser( SLang.Request req, SLang.Response res ) { ... }
}

app.use( UserController );    # 装配期批量注册（C VM 原生收集，见 §7）
```

- **签名与闭包完全一致**：`public void m( SLang.Request req, SLang.Response res )`；`app.use()` 批量注册后经**转发闭包**包装（§7.1），与 §4.2 闭包注册**同一条派发路径**——协程派发 / 中间件管道 / 超时守护 / 文档收集全部同权，方法体内同样可自由 `await / yield / Coroutine.delay`（§4.2 执行模型保证），且 `await` 可直写协程函数调用——`await persistUser( b ) as User` 一步到位（§7.5 糖，P4.5）；
- **控制器实例**：每请求 new 一个（v1 语义最简、免共享状态心智负担；单例模式 P5 评估）；
- **类级前缀**（可选）：`@OnRoute( "/api/v1" )` 标在类上则与方法路径拼接（Spring `@RequestMapping` 类级先例）；未标注则方法路径即全路径；等价分组仍可用 §4.2 `app.group()`；
- `@Route( path, verb )` 保留为**显式动词通用形式**（verb 第二参，默认 `"ANY"`），其余动词特性全部由 `@On*` 家族承载——`@OnAny( path )` 等价 `@Route( path, "ANY" )`；
- P0–P3 期间等价能力 = §4.2 的闭包注册；attribute 只是糖，**不提供任何闭包注册做不到的能力**。

### §4.11 认证与授权：auth 插件 + Jwt + WS token（G13）

**定位**：§4.7 "手写鉴权中间件"形态的产品化封装——`SLang.Plugins` 三个 auth 工厂（产物仍是普通 `ServerPlugin` 子类，无注册中心）；**认证**（你是谁）走框架，**授权**（你能干啥）不做框架、留在 handler 内自判。认证通过 → 身份对象写入 `req.auth`（§6.3）；未通过 → 401 短路。

**三种挂法**（覆盖 Bearer header / API Key header / 任意自定义 header 组合）：

```sl
# ① 通用：校验回调收整个 req，任意 header 组合都能验（X-Token + X-Sign 双头等）
#    约定：回调 ret 身份对象（任意类型，写入 req.auth）或 ret null（→ 401 短路）
app.use( SLang.Plugins.auth( function( SLang.Request req )
{
    string t1 = req.header( "X-Token" );
    string t2 = req.header( "X-Sign" );
    if t1 == null
    {
        ret null
    }
    if t2 == null
    {
        ret null
    }
    ret checkSign( t1, t2 );               # 身份对象 或 null
} ) );

# ② Bearer 预设：Authorization: Bearer <token> → Jwt.decode → req.auth = JwtClaims
#    header 缺失 / 前缀不符 / decode 失败 → 401
app.use( SLang.Plugins.authBearer().skip( "/api/login" ).skip( "/docs" ) );

# ③ API Key 预设：自定义 header 名 + key 校验回调
app.use( SLang.Plugins.authApiKey( "X-API-Key", function( string key )
{
    ret loadAccountByKey( key );           # 身份对象 或 null
} ) );
```

- **`.skip( path )`**：公开路径白名单（精确匹配，可链式多次）——登录接口、`/docs`、`/openapi.json`、静态资源根等；skip 之外全部要认证；**未声明 skip = 全站锁死**（最安全默认）；
- **401 响应协议**：`WWW-Authenticate: Bearer` 响应头（Bearer 模式，RFC 6750）+ `res.jsonFail( 401, "unauthorized" )`（§6.11 风格）；API Key / 自定义模式不带该头；
- 回调内**可 await**（中间件内联连接协程，§4.7 异步鉴权先例）——查下游鉴权服务 / 查库取身份合法；
- 校验回调的**带值返回**（`ret 身份` / `ret null`）走闭包调用返回值通路——与 §2.3 `CallClosure(106)` 多参探针**一并在 P0 验证**（现有回调先例均为无返回值，带值返回是本节新增机制点）；
- **授权不做框架**（无 RBAC 配置体系，Spring Security 全家桶是非目标）：handler 内读身份自判——

```sl
app.onDelete( "/api/users/{id}", function( SLang.Request req, SLang.Response res )
{
    SLang.JwtClaims me = req.auth as SLang.JwtClaims;      # 身份槽读取（as 转型先例 = HttpClient.sl L28）
    if me.claim( "role" ) != "admin"
    {
        res.jsonFail( 403, "forbidden" );                  # 授权失败 403（附录 A）
        ret
    }
    res.jsonOk( "deleted" );
} );
```

**`req.auth` 身份槽**（与 `req.userData` 的分工）：`userData` = 自由传值槽（任意语义）；`auth` = **约定身份槽**——auth 插件写入、handler 只读语义，文档与示例统一走 `req.auth`（§6.3）。

**`SLang.Jwt`——claims 读取（P3 纯 SL 先行）**：

```sl
SLang.JwtClaims c = SLang.Jwt.decode( "eyJhbGciOiJIUzI1NiIs..." );   # 不验签；格式非法 → null
c.subject;         # "sub" 标准 claim → string（缺失 null）
c.expiresAt;       # "exp" → Int64 秒级时间戳（缺失 = 0）
c.expired;         # 现时 > exp（exp 缺失恒 false）——decode 不自动拒，业务自行判
c.claim( "uid" );  # 任意自定义 claim → string（缺失 null）
```

- 实现零新依赖：payload 段 `BaseJson.parse`（§2.1）+ 段间 base64url 解码复用 `Std/Encoding/Base64` 的 url 变体（`+`→`-`、`/`→`_`、去 `=` 填充，RFC 7515）；
- claims 内部载体 = `Map<string,string>`；方法名 `claim`（读）/ `put`（写）避开 `get/set` 关键字（§2.3，HttpClient getHeader/setHeader 改名同款纪律）；Map API 依据 `Lib/Core/Container/Map.sl`。

**`sign` / `verify` 签验——HS256 已随 P5 落地**（C VM crypto 原语 Std/Encoding/Sha256，§20 产物）：

```sl
var c = SLang.JwtClaims();
c.put( "sub", "1001" );
string token = SLang.Jwt.sign( c, cfg.jwtSecret, 3600 );       # 签发：iat 恒写；exp = 现 + expSec（> 0 才写）
SLang.JwtClaims ok = SLang.Jwt.verify( token, cfg.jwtSecret );  # 全量校验：三段 / header.alg 必须字面 HS256（拒 none 降级）
                                                                # / 签名重算逐字节比对 / exp 过期拦截；不过 → null
# exp 由 sign 按当前时间代劳写入——不必再 c.put( "exp", ... )；
# SLang.Jwt.sign( c, 3600 ) 便捷形态：密钥取 ServerConfig.jwtSecret；SLang.Jwt.verify( token ) 同理
```

**依赖事实（P5 已补齐）**：SHA-256 / HMAC-SHA256 原语已落 Std/Encoding/Sha256（sl_core_sha256.c，标准测试向量验证，§20）——`sign/verify` HS256 全量落地；`decode` 不验签语义独立保留（己方签发、且签验发生在别处的同源身份读取场景）。

**WS 升级的 token 校验**——升级分流在中间件管道**之前**（§6.1），auth 中间件**天然不覆盖 WS 会话**，两个落点二选一：

```sl
# 落点 A：会话回调开头自查（最直接；浏览器 WS API 无法自定义 Authorization 头 → 惯例 token 走查询参数）
ws.websocket( "/ws/chat", function( SLang.WsSession s )   # 形态 A：升级路由挂在 SLang.WebSocketServer 实例上（§4.6）
{
    SLang.JwtClaims c = null;
    string token = s.query( "token" );                     # wss://host/ws/chat?token=...
    if token != null
    {
        c = SLang.Jwt.decode( token );
    }
    if c == null
    {
        s.close();                                         # 携码关闭：s.closeInfo(...)（§4.6）
        ret
    }
    s.sendText( "welcome" );                               # 正常会话逻辑
} );

# 落点 B：auth 插件统一接管（`.ws( true )` 开启 → 插件 onWsOpen 钩子（§4.7）内做同款
#         token 查询参数校验，失败即关会话；默认 false = 不接管）
app.use( SLang.Plugins.authBearer().skip( "/api/login" ).ws( true ) );
```

**与文档的关联**（§4.8 / §6.10）：受保护路由注册时顺手 `r.security( "bearerAuth" )`（或 `"apiKeyAuth"`，v1 仅此两值）→ OpenAPI `components.securitySchemes` 定义 + operation 级 `"security"` → **Apifox 导入后接口 Auth 自动配好、调试请求自动附认证头**。注意：auth 插件**不会**自动给路由打 security 标——`.skip()` 白名单使框架无法可靠推断单条路由是否实际受保护，**文档口径由开发者显式声明**（显式优于隐式，与 §4.8 全部元数据同哲学）。

---

## §5 模块工程与类型清单

### 5.1 文件布局（`SLangCore/Lib/SLang/Server/`，发布源 `source/Front/Lib/SLang/Server/`；实况 16 文件以 Server.jsonc compileFiles 为准）

| 文件 | 内容 |
|------|------|
| `Server.sl` | 命名空间 `SLang`：`HttpServer`（HTTP 门面/App）、`ServerConfig`、`ServerError`、内部组装逻辑 |
| `HttpServerCore.sl` | `HttpServerCore`（连接引擎，模块级静态单例）、`_HttpParser`（内部）、连接循环、响应编码、keep-alive、Upgrade 分流 |
| `RouteAttrs.sl` | `@OnGet/@OnPost/...` 动词家族 + `@OnRoute`（类级前缀）+ `@Route`（显式动词）attribute 类（P4，§7.4） |
| `Router.sl` | `Router`（P5 前缀树 `_RouteNode` + `RouteParam/RouteResp`）、`RouteInfo`、`RouteGroup`、路径段匹配 |
| `Request.sl` | `Request`（读侧 API 全量：路径/查询/头/body 分流/form/文件/`bodyStream`（P5 请求侧流式）） |
| `Response.sl` | `Response`（写侧 API 全量，含 `sendFileRange`——P5 Range 断点续传）、`Next`（中间件放行令牌） |
| `BodyParser.sl` | `EBodyFormat` 判定、form 解码（`_UrlCodec`：percent-decode + `+`→空格）、multipart 解析器（boundary/part 头/文件名安全剥离） |
| `Upload.sl` | `UploadedFile`（上传文件句柄：元数据/bytes/saveAs/saveInto） |
| `StreamIo.sl` | `StreamWriter`（chunked 流式写）、`SseWriter`（text/event-stream 写） |
| `HttpBodyReader.sl` | `HttpBodyReader`（请求侧流式读，P5 落地拆出：`read( dst )`/`readAll()`、超限抛 `StreamBodyError.LimitExceeded`，§6.6） |
| `Plugin.sl` | `ServerPlugin` 基类、中间件管道执行器 |
| `Plugins.sl` | 内置插件门面 `SLang.Plugins`（logger/cors/staticFiles/auth/authBearer/authApiKey/rateLimit 工厂；内部 `_AuthPlugin` 不导出，§4.7/§4.11） |
| `Jwt.sl` | `SLang.Jwt`（decode/sign/verify）+ `JwtClaims`（claims 载体，§4.11） |
| `Docs.sl` | `OpenApiBuilder`（实例探针 → schema）、`/docs` 内嵌 HTML 常量、`importOpenApi` 解析 |
| `ApiResult.sl` | `ApiResult` 统一返回体（字段 payload → JSON 键 "data"） |
| `WebSocketServer.sl` | `WebSocketServer`（实例双形态：升级路由器 / 独立端口）、`WsSession`、`WsEventBuilder`、会话注册表（§4.6） |
| `Server.jsonc` / `Server.sp` | 工程配置与入口（见 5.2） |
| `SERVER_DESIGN.md` | 本文档 |

### 5.2 工程配置要点（`Server.jsonc`）

```jsonc
# ★ 本 jsonc 块为 P0 设计稿摘录示意——实况 compileFiles（16 文件：RouteAttrs/Jwt/Docs/HttpBodyReader 已入列）
#   与 struct 登记清单（37 项：HttpServer/WsEventBuilder/HttpBodyReader/RouteParam/RouteResp 等）
#   一律以仓库内 Server.jsonc 为准（systemCalls 亦然：P4 起有 SystemServerRouteCount 等）。
{
  "project": { "name": "SLangServer", "desc": "HTTP + WebSocket application server framework (depends on Core/Std only)" },
  "compileFiles": { "files": [
      { "path": "Server.sl",          "group": "server", "tag": "core", "ignore": false, "priority": 0 },
      { "path": "HttpServerCore.sl",  "group": "server", "tag": "net",  "ignore": false, "priority": 0 },
      { "path": "Router.sl",          "group": "server", "tag": "core", "ignore": false, "priority": 0 },
      { "path": "Request.sl",         "group": "server", "tag": "core", "ignore": false, "priority": 0 },
      { "path": "Response.sl",        "group": "server", "tag": "core", "ignore": false, "priority": 0 },
      { "path": "BodyParser.sl",      "group": "server", "tag": "core", "ignore": false, "priority": 0 },
      { "path": "Upload.sl",          "group": "server", "tag": "io",   "ignore": false, "priority": 0 },
      { "path": "StreamIo.sl",        "group": "server", "tag": "io",   "ignore": false, "priority": 0 },
      { "path": "WebSocketServer.sl", "group": "server", "tag": "net",  "ignore": false, "priority": 0 },
      { "path": "ApiResult.sl",       "group": "server", "tag": "core", "ignore": false, "priority": 0 },
      { "path": "Plugin.sl",          "group": "server", "tag": "core", "ignore": false, "priority": 0 },
      { "path": "Plugins.sl",         "group": "server", "tag": "core", "ignore": false, "priority": 0 },
      { "path": "OpenApi.sl",         "group": "server", "tag": "doc",  "ignore": false, "priority": 0 },
      { "path": "Auth.sl",           "group": "server", "tag": "core", "ignore": false, "priority": 0 }
  ]},
  "systemCalls": [],                     # P0–P3 零新增系统方法（纯 SL 层）
  "references": [
      # ★ 依赖边界（G8）：白名单仅此两项——BaseJson/Coroutine/Attribute/容器（Core）
      #   与 Net.*/File/Timer（Std）；禁引 Math/Render/Tensora/SLMysql/插件/native DLL
      { "path": "../Core", "name": "Core" },
      { "path": "../Std",  "name": "Std" }
  ],
  "struct": [ { "namespace": "SLang", "children": [
      { "class": "HttpServer" }, { "class": "ServerConfig" },
      { "class": "Request" }, { "class": "Response" }, { "class": "Next" },
      { "class": "RouteInfo" }, { "class": "RouteGroup" }, { "class": "ApiResult" },
      { "class": "WsSession" }, { "class": "WsEventBuilder" }, { "class": "WebSocketServer" }, { "class": "ServerPlugin" },
      { "class": "Plugins" }, { "class": "UploadedFile" }, { "class": "StreamWriter" }, { "class": "SseWriter" }, { "class": "OpenApiBuilder" },
      { "class": "Jwt" }, { "class": "JwtClaims" }, { "class": "HttpBodyReader" }
      # 内部类（_HttpParser/_AuthPlugin）不入 struct
  ]}],
  "export": { "moduleName": "SLangServer", "outputDir": "..\\..\\..\\..\\out\\export", "...": "..." }
}
```

用法：用户工程 `import SLangServer;` → `SLang.HttpServer` / `SLang.WebSocketServer` 全路径（与 `SLang.Mysql` 同款命名空间惯例）。

### 5.3 公开类型总表

| 类型 | 职责 | 关键成员 |
|------|------|----------|
| `SLang.HttpServer` | HTTP 应用门面（App 本体；构造 `HttpServer()` = 80 端口 / `HttpServer( port )`） | `onGet/onPost/onPut/onDelete/onPatch/onHead/onOptions/onAny/on( method, path, fn )` · `group/use`（Function 中间件 / ServerPlugin / attribute 控制器）· `configure/reset/usePreloadRoutes/docs( bool )/importOpenApi( path )` · `run( port )/run()/start/stop/awaitStop` · `isRunning/config` |
| `SLang.ServerConfig` | 配置 | §4.9 字段表（含 `handlerTimeoutMs / wsIdleTimeoutMs / jwtSecret`） |
| `SLang.ServerError extends Error` | 框架错误码 | 附录 D |
| `SLang.Request` | **读侧**：请求上下文 | §6.3 全表（路径/查询/头/body 四格式/form/文件） |
| `SLang.Response` | **写侧**：响应输出 | §4.3 表 + `isResponded` |
| `SLang.Next` | 中间件放行令牌 | `go()`（`next` 是关键字，不能直接命名） |
| `SLang.RouteInfo` | 路由记录 + 文档元数据 | `path/method/handler/summary/tags/desc` + `param/requestBody/formField/uploadField/response/security` |
| `SLang.RouteGroup` | 前缀分组 | `onGet/onPost/.../websocket`（自动拼前缀） |
| `SLang.ApiResult` | 统一 JSON 返回体 | `ok(payload)/fail(code,msg)` + `code/message/payload`（JSON 键 "data"） |
| `SLang.UploadedFile` | 上传文件句柄 | §4.4 表 |
| `SLang.StreamWriter` | chunked 流式写出器 | `write/writeBytes/flush/close`（§4.5） |
| `SLang.SseWriter` | SSE 写出器 | `send/sendEvent/comment/close`（§4.5） |
| `SLang.HttpBodyReader` | 请求侧流式读（P5；`RouteInfo.streamBody = true` 路由） | `read( dst ByteBuffer )/readAll()`；超限抛 `StreamBodyError.LimitExceeded`（§6.6） |
| `SLang.WsSession` | WebSocket 会话 | §4.6：`id/remoteAddress/routePattern/closeInfo/isOpen` · `pathParam/pathInt( name, defVal )/query` · `receive` · `sendText/sendBinary/sendPing/close` |
| `SLang.WebSocketServer` | WS 门面（双形态：构造不传端口 = 形态 A / 传端口 = 形态 B） | 形态 A：`websocket( path, fn ) → RouteInfo` · `wsEvents( path ) → WsEventBuilder` · `sessions( path ) → List<WsSession>` · `broadcast( path, text ) → Int32` · `idleTimeout( ms )`；形态 B：`onMessage( fn )/onClose( fn )`（方法注册）· `run( port )/start( port )/start()/stop()/awaitStop()` · `isRunning` · `sessions() → List<WsSession>` · `broadcast( text ) → Int32` |
| `SLang.WsEventBuilder` | WS 事件式糖构建器（P2；链式） | `onOpen( fn )/onMessage( fn )/onClose( fn )`——回调签名 onOpen/onClose = `( s )`、onMessage = `( s, m )` |
| `SLang.ServerPlugin` | 插件基类 | `onInstall()`（无参，§4.7）/`onStart/onStop/onWsOpen/onWsClose` |
| `SLang.Plugins` | 内置插件工厂 | `logger()/cors()/staticFiles(root)` + `auth(fn)/authBearer()/authApiKey(header,fn)`（§4.11；产物含 `.skip(path)/.ws(bool)` 链式配置） |
| `SLang.OpenApiBuilder` | 文档生成（内部亦可直用） | `build() → string`（openapi.json 全文，含 `components.securitySchemes`，§6.10） |
| `SLang.Jwt` | JWT 读取与签验（decode P3；sign/verify HS256 P5） | `decode( token ) → JwtClaims`（不验签；格式非法 → null）· `sign( claims, secret, expSec ) / sign( claims, expSec )` · `verify( token, secret ) / verify( token )`（全量校验，不过 → null，§4.11） |
| `SLang.JwtClaims` | claims 载体（内部 `Map<string,string>`） | `subject/expiresAt/expired`（只读属性）+ `claim(name)/put(name,value)`（读写自定义 claim，命名避 `get/set` 关键字） |
| `EBodyFormat`（enum extends Int32） | 请求体格式 | `None/Json/Form/Multipart/Text/Binary` |

---

## §6 核心机制设计

### §6.1 HttpServerCore（连接引擎）

**连接循环**（每连接一协程，`TcpServer.onConnection` 模式）：

```
Tcp.listen( host, port, backlog )
loop: client = accept()
    spawn 协程 handleConnection( client ):
        client.setReadTimeout( keepAliveTimeoutMs )
        loop:                                  # keep-alive 循环
            req = _HttpParser.parse( client )  # 挂起语义：无数据时协程挂起
            ├ 超时/EOF → 关连接，break
            ├ 头超限 → 431 + close
            ├ Upgrade: websocket 且命中 ws 路由 → WebSocketStream.acceptBuffered → 会话协程，break
            ├ Upgrade: websocket 未命中 → 400
            ├ 解析失败 → 400 + close
            └ 正常 → 构造 Request+Response → 管道执行（中间件环内联，§6.9）
                    └ 尾环 = handler 协程派发（spawnClosure2 + awaitTask / 超时 cancel，见下）
                    → 管道后置环回程 → 响应编码写出
                    Connection: close 或 HTTP/1.0 → close，break；否则继续
```

**请求解析**（算法与 `HttpClient` 响应解析对称，`Websocket.sl _readLine/_fill` 同款预读缓冲技术）：

- 请求行 `METHOD SP path SP HTTP/1.1`；路径拆 `path?query`；
- 头循环至空行，头总字节 ≤ `maxHeaderBytes`，行数上限 100；
- body 三态（与客户端一致）：`Content-Length` 精确读 / `Transfer-Encoding: chunked` 聚合 / 两者皆无读到 EOF（仅对写侧关闭的请求）；
- body 上限：普通请求 `maxBodyBytes`、multipart 请求 `maxUploadBytes`，超出 413 并断连（防内存攻击）。

**响应编码**：

```
HTTP/1.1 <code> <reason>\r\n
Content-Type: <mime>\r\n
Content-Length: <n>\r\n        # 普通响应恒精确长度；流式响应改 Transfer-Encoding: chunked（§6.6）
Connection: keep-alive|close\r\n
<用户附加头>\r\n
\r\n
<body>
```

**状态码 ↔ reason 表**：内置 2xx/3xx/4xx/5xx 常用 30 项（附录 A），未知码用空 reason。

**handler 协程派发与超时守护**（G12；`WsSession` 会话协程 `spawnClosure1` 的同款模式补齐等待/超时两环）：

```
task = Coroutine.spawnClosure2( handler, req, res )   # 已注册系统方法（SystemCoroutineSpawnClosure2），
                                                      # 非 CallClosure(106) —— 双参 handler 派发不依赖风险#1 探针
if res.isStreaming or res.isResponded:                # handler 在派发前不可能写 res，此分支实际覆盖
    awaitTask( task )                                 # 「守护期内已开流式」的续等场景（防 SSE 长推送被误掐）
elif handlerTimeoutMs > 0 and Coroutine.waitTimeout( task, handlerTimeoutMs ):   # 超时 true / 完成 false
    task.cancel()                                     # 协作式取消：handler 在下一调度点（await/yield/delay/IO）退出
    if !res.isResponded:  写 504 ApiResult.fail + Connection: close
    close 连接, break                                  # 超时路径强制断连，杜绝未死协程的任何后续读写竞态
else:
    awaitTask( task )                                 # 正常完成（或 handlerTimeoutMs <= 0 无限等待）
    → 管道后置环回程 → 响应编码写出 → 继续 keep-alive
```

- **为什么派发独立协程而非连接协程内联**：内联虽然同样可 `await`（有栈协程任意深度挂起），但独立协程额外获得 **`Task` 句柄**——超时 `cancel()`、优雅停机（`stop()` 对运行中 handler 协程逐个 cancel 再收尾）都依赖句柄可达；
- **管道衔接**：中间件管道保留在连接协程**内联**执行（onion 同步嵌套语义不变，后置环在 `awaitTask` 返回后自然回程）；最内环 `nx.go()` 触发上述派发；中间件因内联于连接协程，自身也可 `await`；
- **流式豁免**：handler 一旦开启 `res.stream()/sse()/sendFile` 或已提交响应，超时守护即**移交 `writeTimeoutMs`**（每次写出刷新，防慢客户端）——SSE/大文件下载等长时合法推送不被 `handlerTimeoutMs` 误杀；
- **超时后竞态防御**：504 写出后 `res` 置 `isResponded`，handler 协程若在 cancel 生效前恢复执行，其 `res.*` 全部 no-op（写侧门禁）；
- **cancel 的协作式边界**：handler 纯计算死循环（不碰任何挂起点）时 cancel 无法生效——归 §10 风险 5 的 CPU 密集声明，非本机制缺陷；
- **语义待实测项**（P0 探针，§8）：`awaitTask` 对已 cancel / 已死 Task 的返回路径（不得永久挂起）；`waitTimeout` 超时/完成返回值方向。

### §6.2 Router（匹配规则）

- 路由表：`List<RouteInfo>` 线性扫描（v1 规模假设 < 200 条；前缀树为 P5 优化项，非语义变更）；
- 匹配键：`( method, pattern )`；pattern 按 `/` 拆段，`{name}` 段匹配任意非空单段并捕获；
- **优先级**：精确段 > 参数段（先注册静态段更多的 pattern；`/api/user/{id}` 让位 `/api/user/me`）；
- 未注册 method `any` 的路由对该 pattern 接受全部动词；
- 判定序：精确/参数匹配成功但 verb 不符 → **405**（`Allow` 头列出可用动词）；全无匹配 → **404**；
- 冲突检测：`start()` 时对 `(method, pattern)` 去重，重复抛 `ServerError.DuplicateRoute`（fail-fast，防静默覆盖）；
- 路径参数提取进 `req._pathParams`（`Map<string,string>`），查询参数惰性解析进 `req._query`（经 `_UrlCodec` 解码）。

### §6.3 Request（读侧 API 全表）

| API | 语义 |
|-----|------|
| `req.method` → string | "GET" / "POST"…（原始大写） |
| `req.path` → string | 不含 query 的路径 |
| `req.rawQuery` → string | 原始 query 串（可为空） |
| `req.pathParam( name )` → string | 路径段参数；不存在返回 null |
| `req.pathInt( name )` / `req.pathInt( name, def )` | Int32 化；坏格式用 def（单参版 def=0） |
| `req.pathInt64( name, def )` / `req.pathFloat( name, def )` | 同上 Int64 / Float64 |
| `req.query( name )` → string | 查询参数（已解码）；不存在 null |
| `req.queryInt / req.queryBool( name, def )` | 数值/布尔化（`1/true/on` 为真） |
| `req.hasQuery( name )` → bool | — |
| `req.queryKeys()` → List\<string\> | — |
| `req.header( name )` → string | 请求头（大小写不敏感，`HttpHeaders.getHeader` 直通） |
| `req.headers` → Net.HttpHeaders | 原始头集合 |
| `req.contentType` → string | 原始 Content-Type（含参数，如 boundary） |
| `req.bodyFormat` → EBodyFormat | 格式判定（§4.4 分流表） |
| `req.contentLength` → Int64 | 请求声明长度 |
| `req.bodyText()` → string | body 文本（UTF-8）；无 body 空串 |
| `req.bodyJson()` → BaseJson | body 作 JSON 树解析；失败 null |
| `req.body<T>()` → T | `BaseJson.toData<T>` 直通；失败 null（**不抛**，闭包无 throws） |
| `req.bodyBytes()` → ByteBuffer | body 二进制视图（归属 req，请求结束统一回收） |
| `req.form( name )` → string | form 字段值（urlencoded 或 multipart 普通字段；已解码） |
| `req.formInt / req.formBool( name, def )` | 数值/布尔化 |
| `req.hasForm( name )` → bool · `req.formKeys()` → List\<string\> | — |
| `req.file( field )` → UploadedFile | 该字段首个文件；无返回 null |
| `req.files( field )` → List\<UploadedFile\> | 该字段全部文件（多文件） |
| `req.fileCount` → Int32 | 本请求文件总数 |
| `req.isUpgrade` → bool | Upgrade 头探测 |
| `req.ip` / `req.port` | 对端地址（`TcpStream.remoteAddress/remotePort` 直通） |
| `req.userData` → object | 中间件传值槽（自由读写） |
| `req.auth` → object | **约定身份槽**：auth 插件校验通过后写入身份（多为 `SLang.JwtClaims`）、handler 只读使用；与 `userData` 的分工见 §4.11 |

**Response（写侧）**：见 §4.3 表；附加控制：

| API | 语义 |
|-----|------|
| `res.isResponded` → bool | 是否已有终端写出 |
| `res.setCookie( name, value )` | P3 |

### §6.4 请求体格式处理（BodyParser）

**Content-Type → EBodyFormat 判定**（忽略大小写；参数段剥离后比较）：

```
application/json | */+json               → Json
application/x-www-form-urlencoded        → Form
multipart/form-data                      → Multipart
text/*                                   → Text
其余（含 application/octet-stream）        → Binary
无 Content-Type 且无 body                 → None
```

**form 解码（urlencoded）**：

```
"a=1&b=hello+world&c=%E4%BD%A0%E5%A5%BD"
→ 按 '&' 分段 → 首个 '=' 切键值 → _UrlCodec 解码（%HH 逐字节 + '+'→空格 → UTF-8 组装）
→ 键重复：后者覆盖前者（与查询参数一致；同名多值 formAll(name) 为 P3）
```

`_UrlCodec`（内部静态工具，`Uri` 无现成解码）：`decode( string ) → string`（%HH 非法序列原样保留）；查询参数解码同用。

**multipart/form-data 解析（RFC 7578）**：

```
1. Content-Type 参数提取 boundary（忽略大小写、可带引号；缺失 → 400）
2. 分隔符 = "--" + boundary；结束符 = 分隔符 + "--"；段间以 CRLF 相接
3. 逐 part：分隔符行 → part 头（Content-Disposition / Content-Type，头规则同请求头）→ 空行
   → 内容直到下一分隔符（内容不含结尾 CRLF）
4. Content-Disposition: form-data; name="field"[; filename="f.txt"]
   有 filename → 文件 part → UploadedFile（内容进独立 ByteBuffer）
   无 filename → 普通字段 → form 表（值解码同 _UrlCodec 规则中的直传语义，multipart 字段值不解码）
5. 尺寸约束：总量 ≤ maxUploadBytes、单文件 ≤ maxFileBytes（超限 413）；
   part 头行数/大小同请求头限制
6. filename 安全：取 basename（按 '/' 与 '\\' 剥离路径段，防 ../ 穿越）；空名生成 "upload_<序号>"
7. v1 全量驻留内存；流式（边收边落盘）为 P5
```

### §6.5 文件上传（UploadedFile）

- 生命周期：`Request` 构造期由 BodyParser 解析 multipart 产出，`List<UploadedFile>` + 字段名索引（`Map<string, List<UploadedFile>>`）挂在 req 上；请求结束（响应写出/连接关闭）统一 `release()` 内容缓冲；
- `bytes()` 每次返回 `slice()` 视图（不推进源，`Websocket.sl` 同款零拷贝手法）；**勿跨请求持有**——需要持久化就 `saveAs`；
- `saveAs( path )` / `saveInto( dir )`：`Std.IO.File` 写出；`saveInto` 重名自动改名 `name(1).ext`；目录不存在返回 false（不自动创建，显式优于隐式）；
- 扩展名信任：`f.ext()` 仅供业务白名单判断（如仅允许 png/jpg），**不**作为 MIME 判定依据（MIME 用 part 声明的 contentType）。

### §6.6 流式传输机制（响应侧 + 请求侧落地）

**chunked 编码**（RFC 9112 §7.1）：

```
HTTP/1.1 200 OK\r\n
Transfer-Encoding: chunked\r\n        # 流式响应不带 Content-Length
<用户头>\r\n
\r\n
5\r\npart1\r\n                         # 每次 write 一个 chunk：<hex 长度>\r\n<数据>\r\n
0\r\n\r\n                              # close() 终止块
```

**StreamWriter 状态机**：`Header（stream() 前可改状态/头）→ Streaming（只接受 write/flush）→ Closed（再写抛 AlreadyResponded）`

- 头部先行：`stream()` 调用点即编码状态行 + 头并写出——`status / contentType / header` 链式必须在之前完成；
- HTTP/1.0 客户端不支持 chunked → 降级 close-delimited（写完直接断连）；
- 兜底收尾：handler 协程退出（含异常路径）未调 `close()` → 框架补 `0\r\n\r\n`，连接按 keep-alive 规则继续或关闭。

**SSE 线格式**（`SseWriter` 内部组装，用户只调语义 API）：

```
event: progress\r\ndata: 10\r\n\r\n     # sendEvent( "progress", "10" )
data: done\r\n\r\n                      # send( "done" )
: keepalive\r\n\r\n                     # comment( "keepalive" ) 心跳注释行
```

**背压与超时**：写路径全走 `TcpStream.write`（C VM 协程挂起语义）→ 发送缓冲满则挂起，天然背压；`cfg.writeTimeoutMs`（默认 30s，<= 0 无限）超时抛 `NetError.Timeout` → 走管道异常协议收尾（§6.11）；对端断开写失败同理。

**sendFile（流式下载）**：`Std.IO.File` 64KB 分块读 + write 循环；`Content-Length` = 文件大小（非 chunked）；MIME 按扩展名（附录 B）；Range / 断点续传为 P5。

**请求侧流式（P5 落地；multipart 流式解析 P7 已落地）**：

- 注册期声明：`RouteInfo.streamBody = true` → `_HttpParser` 解析到头区空行即停、不预读 body，连接与预读残留移交 handler；
- `req.bodyStream()` → `HttpBodyReader`：`read( ByteBuffer dst ) → Int32`（0 = EOF；Content-Length / chunked 感知；累计字节超上限走 413 语义）；P7 起双形态缓存化（同一请求恒返同一实例，引擎收尾与 handler 共享消费进度）；
- 边收边落盘上传：handler 循环 read → `File` 追加写；multipart 流式解析 **P7 已落地**（`req.multipartStream()` → `MultipartReader`：boundary 跨块匹配、part 级 `read`/`readAll`/`saveAs`，详见 §24），`UploadedFile` 全内存形态并行保留（非流式路由专属）；
- Upgrade（WS）路由不受影响（Upgrade 请求无 body 语义）。

### §6.7 JSON 封装与序列化契约

- 对象 → JSON：一律 `BaseJson.fromData( obj )`；成员规则 = `Serializable` 体系（public 默认参与 / `@NonSerialized` 排除 / `@SerializeField` 强制，见 `Lib/Core/Attribute.sl`）；
- JSON → 对象：`BaseJson.toData<T>()`；
- **`ApiResult` 封装的组包方式**：因 `data` 是关键字、字段只能叫 `payload`，`res.jsonOk( payload )` 的输出由框架**手工组 JSON 树**（`{"code":..,"message":..,"data":<fromData(payload)>}`），键名稳定为 `"data"` 且键序固定（code → message → data）——不依赖 fromData 对 ApiResult 自身的字段名序列化；嵌套 payload 仍走 fromData 递归（**P0 验收含嵌套 DTO 用例**，若 fromData 嵌套深度有坑即整体回落手工 JsonValue 组装并记入 §10）；
- 数值/布尔/字符串/容器（List/Map/Array）映射表跟随 fromData 现状，不自造。

### §6.8 WebSocket 会话

- `WsSession` 包装 `Net.WebSocketStream` + 注册表键（GUID）+ 路由信息 + 标签表（P2）；
- **`acceptBuffered` 增量**：`Websocket.sl` 新增重载 `accept( TcpStream raw, ByteBuffer preRead, WsOptions opt )`——`_readLine/_readHeaders` 优先消费 `preRead` 残留字节再读流（Std 侧唯一改动，纯增量、不影响现有两参形式；实现时同步 `md/lib/Std/net/Websocket.md`）；
- 会话协程：升级成功后 `spawnClosure1( handler, session )`；协程退出（handler ret / receive null）→ 注销注册表 → `onWsClose` 钩子；
- 广播 = 遍历该路由会话表逐个 `sendText`；单会话已断（`try?` 吞错）跳过；
- 心跳：透传 `WebSocketStream` 的 autoPong；服务端主动 Ping 策略（闲置 N 秒探测）P3 再议。

### §6.9 插件模型与中间件管道

**管道执行**（`Plugin.sl` 内执行器）：

```
runPipeline( req, res, mws, handler ):
    环序：mws[0] → mws[1] → … → handler
    Next 令牌：每环框架构造 SLang.Next 实例（内持下一环索引），
              nx.go() = 调用下一环（SL 无方法引用 → 框架持索引逐环构造）
    规则：任一环未调 nx.go() 即短路；中间件必须经 res.* 写响应或短路
    异常：任一环抛错 → 捕获 → app.onError(req, res, e) → 未消费则 500 ApiResult 兜底
```

- **中间件 vs 插件**：中间件 = 单个三参 `Function`；插件 = 类（可携带配置与多条注册）；`app.use( Function )` 与 `app.use( ServerPlugin )` 重载区分；
- 插件 `onInstall` 在 `use()` 时**立即**执行（非 start 时），保证"先 use 中间件、后注册路由"与"路由文档由插件追加"都成立；
- 执行序：全局中间件按注册序 → 路由 handler；**路由级中间件**（`app.onGet( path, fn, mw1 )` variadic 尾参）P3；
- WS 会话钩子（`onWsOpen/onWsClose`）对所有插件广播调用。

### §6.10 OpenAPI 生成与 docs 页面

**实例探针法**（零反射约束下的 schema 推导）：

```
样例实例 → BaseJson.fromData → JSON 树 → 逐节点映射 schema：
    string → {"type":"string"}     number(整数) → {"type":"integer"}
    bool → {"type":"boolean"}      array → {"type":"array","items":<元素探针>}
    object → {"type":"object","properties":{...}}   null → {"nullable":true}
生成的 schema 进 components.schemas（类型名做键，复用去重），operation 引用 $ref
```

**openapi.json 骨架**（OpenAPI 3.0.3）：

```json
{
  "openapi": "3.0.3",
  "info": { "title": "<app 名>", "version": "1.0.0" },
  "servers": [ { "url": "http://0.0.0.0:8080" } ],
  "paths": {
    "/api/user/{id}": {
      "get": {
        "summary": "获取单个用户", "tags": ["用户"],
        "parameters": [ { "name": "id", "in": "path", "required": true, "schema": { "type": "integer" } } ],
        "responses": { "200": { "content": { "application/json": { "schema": { "$ref": "#/components/schemas/User" } } } } }
      }
    }
  },
  "components": {
    "schemas": { "User": { ... }, "CreateUserReq": { ... } },
    "securitySchemes": {
      "bearerAuth": { "type": "http", "scheme": "bearer", "bearerFormat": "JWT" },
      "apiKeyAuth": { "type": "apiKey", "in": "header", "name": "X-API-Key" }
    }
  }
}
```

**securitySchemes 生成规则**（与 §4.11 auth 关联）：任一路由声明过 `r.security(...)` → 生成 `components.securitySchemes`（v1 仅两值，定义固定如上：`bearerAuth` = http/bearer/JWT、`apiKeyAuth` = apiKey/X-API-Key header），且该 operation 追加 `"security": [ { "bearerAuth": [] } ]`（数组内并列多值 = OR 语义，满足其一即可）；**全站无任何声明则两段整体省略**。Apifox 导入后受保护接口 Auth 自动配好、调试请求自动附认证头（无需手工配置）。auth 插件不自动打标，security 由开发者显式声明（§4.11 末段）。

**form / multipart 的文档形态**：`r.formField(...)` 收集 → requestBody `application/x-www-form-urlencoded` 的 object schema；`r.uploadField(...)` → requestBody `multipart/form-data`（该字段 `type: string, format: binary`）。

**SSE 的文档形态**：响应 content 记 `text/event-stream`（探针/示例不受影响；Apifox 侧按事件流调试）。

**文档路由**：`GET /docs` → 内嵌 HTML（读同源 `/openapi.json` 渲染）；`GET /openapi.json` → 生成全文。两路由与用户路由冲突时**用户优先**（冲突检测豁免内置路由，`app.docs(false)` 整体关闭）。

**importOpenApi**：解析 paths → 对未注册 pattern 建"文档路由"（RouteInfo.handler = 框架内置 501 应答）；已被真实路由覆盖的路径仅合并文档元数据。

### §6.11 错误处理协议

| 层 | 行为 |
|----|------|
| 协议层（解析失败/超限/boundary 缺失） | 400/413/431 + `ApiResult.fail` 体 + 按需断连；不进管道 |
| 匹配层 | 404 / 405 + `ApiResult.fail` 体 |
| 处理器/中间件异常 | 全捕获（闭包无 throws 的补偿）→ `app.onError(req, res, e)` → 未消费则 500 `ApiResult.fail(500,"internal error")` |
| WS 会话异常 | 会话协程内捕获 → 关连接 → `onWsClose`；不影响其他会话 |
| 服务器级（listen 失败等） | 原样抛 `NetError.*` / `ServerError.*` 给调用方（启动期错误不吞） |

---

## §7 attribute 路由接线（P9 §26 形态 3 定稿；P4 原生收集形态已退役）

**现行方案（2026-10-26，attribute 四形态之「形态 3 · runtime 装载」）**：VM 只提供**一次性通用机制**，全部装配逻辑写在各 attribute 子类的 `_enter_` 里（SL 代码），VM 不写任何 per-attribute 的 C99 代码：

1. **触发通道**（`vm_runtime_attribute_preload_enter_sl`，挂载 `vm_scheduler_enter` 根帧建立后、入口调度前）：扫描全部 stage==Preload 的 attribute → 实例化（args 按 `_init_` 重载参数个数匹配，复用 P7 实例链）→ 注入宿主名（`_ownerClassName`/`_ownerMemberName`，类级与方法级 owner 均为 Front 导出短名，键位一致）→ 调 `_enter_`；**类级先行、方法级在后**（@Singleton/@OnRoute 先就绪，@On* 才能消费）；已有原生 handler 的（DllImport/DllStaticImport）经 `vm_runtime_attribute_has_native_collect` 跳过；
2. **宿主接口**（Core.Attribute 基类方法，系统方法 `SystemAttributeHostMethodRef/Of/HostClassNew`）：`hostMethodRef()` = LATE 实例闭包（每请求一实例，§4.10）；`hostMethodRefOf(inst)` = 绑定实例 method-ref（单例全程复用，§26）；`hostClassNew()` = 构造宿主新实例；
3. **SL 注册中心**（`HttpServer.shared()` 隐式共享 Server + 静态缓冲）：`@On*`/`@Route` 的 `_enter_` 调 `registerPreload( verb, path, this )`（前缀拼接/单例感知/verb 规整在注册中心内完成）；`@OnRoute` → `registerPrefix`；`@Singleton` → `registerSingleton( owner, hostClassNew() )`；`app.usePreloadRoutes()` 把缓冲并入本 app 的 Router。

**挂载点语义**（本阶段踩过的真坑）：入口经 `vm_prepare_entry_method_slots` 以**无帧 armed**状态存活（`vm->ip` 已指向入口字节码），native 子帧执行（`vm_execute_method_by_id`）在帧链弹空后会**流入已武装的入口代码**——把入口与装配交错执行（现象：装配注册晚于测试读取 / Probe B1-B6 await 探针被啃坏）。正解 = 挂载 `vm_scheduler_enter` 建立根帧之后：子帧 barrier 落在根帧上，弹回即停（与 P7 方法帧内回调同机理）。

**误诊更正（2026-10-26 复核定案，原「Front 跨模块 override 吞方法」限制撤销）**：此前记录的「override 重写方法体在 IR 期被吞」为**误诊**——最小复现（OnGet 单类恢复 override 重导）显示 `SLangServer.SLang.OnGet._enter_` 槽位与指令体均正常导出。真因是当时 Server.sl 存在编译错误（`MetaCoreParseCallLinkFailed`：`Map.put` 不存在、索引表达式作左值），方法链解析失败**连带**同文件方法被丢，与 override 关键字无关。RouteAttrs.sl 已全量恢复 11 个 `_enter_` 的规范 `override` 形态，重导后 234 OK / 0 FAIL 全绿。教训：见到「方法导出缺失」先查编译日志报错，勿先归因语言机制。

### 7.1 P4 历史方案（装配期原生收集 + 系统方法导出，已退役）

> 2026-10-26 形态 3 重构退役：`vm_route_attribute.c`（10 个原生收集 handler）与 `server_system_method.c`（`SystemServerRoute*` 三系统方法）整体删除，`Server.jsonc systemCalls` 清空。以下保留历史设计记录（曾以该形态落地 P4 并通过全部验收）。

与 `ATTRIBUTE_DESIGN.md` §4.3 注册表演进方向一致（"按名 + stage==Preload 匹配"）：

1. **C VM**（`vm/runtime/attribute/vm_runtime_attribute.c`）：注册路由 attribute 原生 handler——装配期扫描全模块 `attributeList` 中 **`OnGet/OnPost/OnPut/OnDelete/OnPatch/OnHead/OnOptions/OnAny`（动词家族，新名）与 `Route`（已知名）/ `OnRoute`（类级前缀）** 实例（含 path/verb/宿主类/宿主方法），收集进原生路由表（AOT 注册表同款模式；`@On*` 名→verb 映射在原生层完成）；
2. **C VM**：新增系统方法 `SystemServerGetPreloadRoutes()` → 返回路由描述（List/序列化串）；
3. **SL 层**：`app.usePreloadRoutes()` 在 start 时拉表 → 生成 `RouteInfo` → 进 Router。**转发闭包**（无反射约束 §2.3 的解法）：SL 层凭 (类名, 方法名) 字符串无法发起调用，故 handler = 单行转发闭包 `function(req, res){ SLang.ServerBridge.call( routeIdx, req, res ); }`——`ServerBridge.call` 为系统方法：C VM 按 `routeIdx` 查 (宿主类, method 引用)，new 控制器实例（每请求一实例，§4.10）后 **VM 级直接调用目标方法**；方法体因此运行在 handler 协程栈上（经 §6.1 派发路径），内部 `await / yield / Coroutine.delay` 与闭包 handler 完全同权；
4. **R7 四处同步**：`@On*` 家族 + `@Route`/`@OnRoute` 声明（`RouteAttrs.sl`，收编自 `Lib/Std/Net/Route.sl`）+ `Server.jsonc systemCalls[]` + `src/vm/system_method_call/server_system_method.c` + `Front/Define.cs ESystemMethodCall`；新 .c 文件三处登记（R6）。

### 7.2 备选轻量方案（若 C VM 排期紧张）

`Route` stage 改 Runtime + 新增 `SystemAttributeListAttributedMethods( className )`（枚举带 attribute 的方法名）→ SL 层 `app.use( Controller )` 逐方法 `getMethodAttributes` 查询。改动同为 C VM 侧，但收集逻辑留在 SL，原生面更小。

### 7.3 前置调研项（P4 开工条件）

- Front `MetaAttribute.ResolveHandleType()` 名称回退表对**新 attribute 名**的支持方式——`@OnGet/@OnPost/...` 动词家族为**批量新名**（8 个一次性注册），调研：① 未知名是否默认按带参构造解析（若可靠则家族免注册）② 评估在工程/ jsonc 侧声明已知 attribute 名清单的可行性（免每次动 Front）；不可靠则 P4 需 Front 一次性登记全家族；`@Doc` 等文档元数据 attribute 同理；
- `@OnGet( path )` 单参与 `@Route( path, verb )` 双参构造在 Front attribute 解析层的合法性（`@DllStaticImport` 双参先例存在，风险低）；
- **handler 协程派发语义探针**（§6.1 待实测项，P0 完成，与 §7 无依赖但同为 P4 验收前置）：`awaitTask` 对已 cancel/已死 Task 的返回路径、`waitTimeout` 返回方向；
- **直接 await 语言糖的脱糖时机调研**（§7.5，P4.5 开工条件，P0 后即可启动）：① 脱糖判别下沉 IR/Meta 层（类型已知处）的可行性与挂点；② `httpGetAsync` 族（返回 Task 的调用）透传路径**不回归**为验收红线；③ 复用 spawn 包装闭包机制（`StructParseToSyntax.cs` 双分流）后实参求值时机的语义确认（包装闭包路径实参延迟到协程首跑求值，与"await 处立即求值"存在可见差异，需文档声明）。

### 7.4 存量处置

`Lib/Std/Net/Route.sl`（未入编译清单的占位）在 P4 落地时**迁入本模块改写为 `RouteAttrs.sl`**（`@On*` 动词家族 + `@Route`/`@OnRoute`），原文件删除——避免同名 attribute 双定义；`ATTRIBUTE_DESIGN.md` §6.6 与 `md/lib/Std/net/Http.md` L156 的"未接线"说明同步更新（R14）。

### 7.5 直接 await 协程函数调用——语言糖（P4.5，仅动 Front）

**目标形态**（修订⑫定稿）：`@On*` / `on*` 派发时 handler **已经是协程**（§6.1），方法体内对**返回非 Task 的协程函数**直接一步、不出现中间 Task 变量：

```sl
User u = await persistUser( b ) as User;     # 而非：Task t = spawn persistUser( b ); User u = await t as User;
```

**现状语义**：`await expr` 脱糖为 `Coroutine.awaitTask( expr )`，操作数节点**原样传入**（`Parse/StructParseToSyntax.cs` await 分支）：

| `await` 操作数 | 脱糖结果 | 现状结论 |
|---------------|----------|----------|
| Task 变量（`await t as T`） | `awaitTask( t )` | 基础形态，正确 |
| **返回 Task 的调用**（`httpGetAsync` 族） | 调用先求值得 Task → `awaitTask( task )`（透传） | **现状即合法**，可直写 |
| **返回非 Task 的调用**（`persistUser( b )`） | 调用被**同步求值**，非 Task 值传给 `awaitTask` | **语义错误** → 本糖补齐对象 |

**糖规则**（复用 spawn 双分流机制，`StructParseToSyntax.cs`）：

1. `await` 后操作数为**调用**、被调方法有 Meta 签名且**返回非 Task** → 脱糖为「spawn + awaitTask」：提升无参包装闭包 `function spawnClosureTmpN() { ret <原调用> }` + `spawnClosure0`（与裸方法名 spawn 同款分流）→ `awaitTask( spawnClosure0( ... ) )`；
2. 操作数为**返回 Task 的调用** → 维持透传，**不包 spawn**（否则 `awaitTask` 拿到 Task 对象本身而非结果）；
3. 操作数为 Task 变量 / 其他表达式 → 维持现状。

**实现落点与关键难点**：现有 await / spawn 脱糖都发生在 **parse 层**，而 parse 层**不知道调用返回类型**——「包不包 spawn」的判别必须在类型已知处做。倾向方案：await 节点带「待定」标记进 IR，在 **IR/Meta 层**按被调方法签名补包 spawn；备选保守方案：显式标注（`await spawn fn( 实参 )`）先行、自动判别后置。**验收红线**：① `httpGetAsync` 族（返回 Task 的调用）透传不回归；② 显式 spawn 并发聚合不回归；③ `awaitTask( Task 变量 )` 基础形态不回归。另需文档声明：包装闭包路径实参**延迟到协程首跑求值**（与"await 处立即求值"存在可见差异，§7.3 调研项 ③）。

> **✅ 落地注记（2026-10-25，await spawn 组合）**：上段「备选保守方案：显式标注（`await spawn fn( 实参 )`）」已落地——`await spawn` 组合语法支持 **调用形态与匿名闭包**双目标（`await spawn fn( 实参 )` / `await spawn cn.f( 实参 )` / `await spawn function(){...}`），语义严格等价 `Task t = spawn ...; ret await t`。实现 = `StructParseToSyntax.cs` `TransformCoroutineKeywordNodes` 改**两遍扫描**（pass0 展开 spawn → 产物为返回 Task 的 `spawnClosureN` 合成调用节点；pass1 await 以该调用为操作数命中 §18 换绑标记，MetaCore 见返回 Task 走透传分支），复用 P4.5 换绑机制零新增 IR 改动。与直接 await 糖的关键差异：实参求值时机同裸 spawn 分流（方法名/实例链**延迟到协程首跑**），且支持匿名闭包目标（直接糖只接调用形态）。文法详见 `md/syntax/coroutine.md` §4.2「await spawn 组合」；三目标形态 + 存量回归共 13 项断言实跑全 OK（SpAwaitTest），ServerTest P0–P4.5 全量回归全绿。

**文档同步**（R13/R14）：`md/syntax/coroutine.md` §4 await 文法与脱糖说明、`md/lib/Server.md`（P3 起的用户侧文档）同步本糖；§4 各示例中"P4.5 前两步 fallback"注记在糖落地后移除。

---

## §8 分阶段实施计划

| 阶段 | 范围 | 产出 | 验收 |
|------|------|------|------|
| **P0** 引擎 | `HttpServerCore` + `_HttpParser` + 响应编码 + keep-alive；`WebSocketStream.acceptBuffered` 重载（Std 增量）；**前置探针：CallClosure 多参直调（双参/三参闭包变量调用）+ handler 协程派发语义（§6.1：`awaitTask` 对已 cancel/已死 Task 的返回路径、`waitTimeout` 返回方向）** | 无路由的裸 HTTP 服务 + `test/Other/NetTest/` 旁路探针 | ✅ **2026-10-17 全绿**：ServerProbeTest A1–B6（多参闭包/带值返回/死 Task awaitTask 不挂起/waitTimeout 双向/cancel）+ ServerCoreTest S1a–S4b（回环 200·404·405+Allow·413·431·504·keep-alive·HEAD·WS 预读残留帧 echo:hello），NetTest 全套 FAIL=0；落地偏差见文末「P0 落地实录」（静态单例化 / 三坑复盘 / HttpServerCore 含 P0 精确路由） |
| **P1** 路由与封装 | `Router/RouteInfo/RouteGroup` + `Request/Response/Next` 全表 + `ApiResult` + **BodyParser（json/form/bin）** + `app.run/start/stop` + WS 路由升级 + `WsSession` + `WebSocketServer` 独立形态 | §4.1–§4.4 与 §4.6 全部示例可运行 | ✅ **2026-10-17 全绿**：`test/ExpendTest/Server/ServerP1Test.sl` T1–T8 共 42 项（动词家族+405+keep-alive / 路径参数+RouteGroup / 查询参数 / json·form·bin body / Response 链式 / WS 两形态 / WebSocketServer 独立端口 / DuplicateRoute fail-fast）全 OK；ExpendTest 293/293、NetTest 104/104 回归全绿；落地偏差见文末「P1 落地实录」 |
| **P1.5** 上传 | multipart 解析器 + `UploadedFile`（saveAs/saveInto/安全剥离）+ `maxUploadBytes/maxFileBytes` | §4.4 文件上传全部示例可运行 | ✅ **2026-10-20 全绿**：`test/ExpendTest/Server/ServerP15Test.sl` T1–T7 共 10 项（混合字段+form 族并入 / 二进制内容 hex 往返 / 多文件同字段 / 路径穿越剥离+空名 `upload_<序号>` / saveAs+saveInto 重名自动改名 `dup(1).txt` / 单文件超限 413 / multipart 总量超限 413 / boundary 缺失 400）全 OK；P1 42 项回归全绿；落地偏差见文末「P1.5 落地实录」（附：宿主引用模块联动拷贝修复） |
| **P2** 管道插件与流式 | 中间件管道（Next.go）+ `ServerPlugin` + `logger/cors/staticFiles` + **流式三件套（`StreamWriter` chunked / `SseWriter` SSE / `sendFile` 流式下载）** + `wsEvents` 糖 + 通配路由 | §4.5 与 §4.7 全部示例可运行 | ✅ **2026-10-20 全绿**：`test/ExpendTest/Server/ServerP2Test.sl` T1–T4 共 24 项（管道短路 401 / onion 序 + userData 传值 / 404 过管道 / onInstall·onStart·onStop 钩子三联 / CORS 预检 204 / 静态 MIME / 穿越 403 / chunked 编码·终止块·keep-alive / SSE 线格式 / 流式超时豁免 / sendFile 160KB 往返 / file() 附件头 / {path*} 通配三态 / wsEvents 开·收·关）全 OK；P1 42 项 + P1.5 10 项回归全绿（ExpendTest 全量零 FAIL）；落地偏差见文末「P2 落地实录」（附：C VM CastClass Step 6 闭包放行修复） |
| **P3** 文档+认证 | `OpenApiBuilder` + `/docs` + `/openapi.json` + `importOpenApi` + `bodyLimit/requestId/auth` 插件 + `SLang.Jwt.decode` + `maxConnections` | §4.8 全部能力 + §4.11 auth 三挂法 / `.skip` 白名单 / WS token 两落点 | ✅ **2026-10-21 全绿**：`test/ExpendTest/Server/ServerP3Test.sl` T1–T6 共 33 项（openapi 3.0.3 骨架/paths/param in:path/requestBody $ref/嵌套 schema/securitySchemes 双定义+operation security/form 字段；/docs 自包含页 + 用户让位 + docs(false) 关闭；Bearer 401+WWW-Authenticate·坏 token·claims 透传·skip 放行；API Key 三态；通用回调双头三态；Jwt.decode 五组（claims/exp 三态/坏格式 null）；importOpenApi 计数·501·共存·覆盖让位·元数据继承；maxConnections 503）全 OK；P1 45 + P1.5 10 + P2 24 回归全绿（ExpendTest 零 FAIL）；落地偏差见文末「P3 落地实录」（附：Front 三坑规避实录——`$` 插值吞 token/长字面量 "+" 链截断/`out`·`params` 关键字） |
| **P4** attribute | §7 接线：C VM 原生收集 **`@OnGet/@OnPost/@OnPut/@OnDelete/@OnPatch/@OnHead/@OnOptions/@OnAny` 动词家族 + `@Route`/`@OnRoute`**（新名→verb 原生映射）+ `ServerBridge.call(routeIdx, req, res)` 转发闭包系统方法 + R7 四处同步 + R6 登记 | §4.10 语法可用 | ✅ **2026-10-24 全绿**：`test/ExpendTest/Server/ServerP4Test.sl` T1–T3 共 13 项（preload count==6 / OnRoute prefix join / 每请求一实例 / @Route 双参 DELETE / plain OnGet / OnAny 双动词 / 动态注册共存 / 404 / 405+Allow / await+delay 异步 handler / 超时 504 / 二次拉取幂等 / duplicate fail-fast）全 OK；ExpendTest 全量回归零 FAIL；`Route.sl` 迁入改写为 `RouteAttrs.sl`（原文件删除）；相关 md 同步（Server.md 新增 P4 节 / Http.md §7 更新）；落地偏差见文末「§17 P4 落地实录」（附：C VM declaringTypeFullName 短名回退修复） |
| **P4.5** 直接 await 糖 | Front 语法糖（§7.5）：`await` 后跟返回非 Task 的调用自动包 spawn 脱糖（判别下沉 IR/Meta 层，§7.3 调研先行）+ `md/syntax/coroutine.md` §4 同步（R13） | §4.1 / §4.2 写法 1·3·6·7 / §4.6 / §4.7 / §4.10 createUser 全部直接 await 形态生效 | ✅ **2026-10-25 全绿**：`test/ExpendTest/Server/ServerP45Test.sl` T1–T3 共 13 项（静态 0/1/3 参直等 / 实例方法直等（receiver→方法引用 this 绑定）/ 目标体内 delay 真挂起 / void 目标 / **Task 调用透传不回归**（同 httpGetAsync 类型学通道）/ **显式 spawn waitAll2 聚合不回归** / **Task 变量基础形态不回归** / 函数值调用保守路径 / 三形态混用）全 OK；ExpendTest 全量零 FAIL；BaseTest 26 FAIL = 2026-10-23 既有基线逐条一致（零新增）；Math/NullFast/Special/BenchMark exit 0；实现形态 = 换绑标记（非 IR 判别下沉，见 §18 实录）；coroutine.md §4.2 + function.md VM 侧注同步 |
| **P5** 打磨 | 前缀树路由 / **请求侧流式（`r.streamBody` + `HttpBodyReader` 边收边落盘上传）** / Range 断点续传 / 主动心跳 / `rateLimit` 插件 / `SLang.Jwt.sign/verify`（HS256 签验 + `ServerConfig.jwtSecret`，**前置依赖 = 标准库 crypto 哈希原语落地**，G8 边界内，§4.11）/ TLS 服务端评估 | 性能与运维项 | ✅ **2026-10-26 全绿**：`test/Other/ServerTest/ServerP5Test.sl` T1–T6 共 28 项（rateLimit 固定窗口 3+1 边界 / Range 全态 206·206·206·416·畸形全量·Accept-Ranges·staticFiles 透传 / WS 空闲心跳 600ms 看门狗 + 活跃会话存活 / Jwt sign·verify·错密钥·篡改·过期·alg 降级·cfg 便捷形态 + MissingJwtSecret / 流式上传 CL 精确·chunked·600KB 落盘·未消费排干 keep-alive·非流式路由不回归 / 路由树语义重放 6 项）全 OK；ServerTest 全量 178/178、ExpendTest 250、NetTest 81 回归零 FAIL；BaseTest 26 FAIL = 既有基线逐条一致零新增；MathTest/NullFast exit 0；落地实录见文末「§20 P5 落地实录」（含 TLS 服务端评估结论） |

每阶段完成即触发 §9 文档同步清单（R14：代码改了文档必须跟上）。

---

## §9 工程落位与文档同步

| 事项 | 落点 |
|------|------|
| 模块登记 | `Server.jsonc` + `Server.sp`（本目录）；导出 `out/export/SLangServer/` |
| 用例集 | **2026-10-25 起独立 `test/Other/ServerTest/` 用例集**（宿主 `CSimpleVMTest` 选择器 `ServerTest`，`-test` 入口约定见 `md/project/test-guide.md`）：P0 探针/引擎（ServerProbeTest/ServerCoreTest）自 NetTest 迁入，P1~P4.5 六件自 `test/ExpendTest/Server/` 迁入（该目录随之移除，ExpendTest/NetTest 不再引 SLangServer） |
| 文档（用户侧） | `md/lib/` 新增 `Server.md`（用法文档，本文档 §4 收敛而成）+ `md/INDEX.md` §4 挂链（R13） |
| 文档（Std 侧） | `md/lib/Std/net/Websocket.md` 补 `acceptBuffered` 重载；`md/lib/Std/net/Net.md` L34"不含 HTTP 服务端"措辞更新为指向 SLangServer |
| AGENTS.md | §1 表格 `simple_language/` 行与 §3 路由表补 `SLang/Server` 条目 |
| 故障排查 | C VM 侧改动（仅 P4）按 R12 先插桩后修复；复盘按 R10 写入 `md/ai/troubleshooting/` 对应分片（路由见 故障排查流程.md §6） |
| 构建脚本 | 无需改 `scripts/compile-stdlib.ps1`（其编译三件套 Core/Math/Std）；SLangServer 由用例集 jsonc references 拉入编译链，必要时评估加入批量脚本 `-Tests` 矩阵 |
| 依赖边界守护 | 评审/提交时核对 jsonc `references` 仅 Core/Std（G8）；SL 源文件 import 只允许 `SLangServer` 自身 + `Std` + `Core` |

---

## §10 风险与已知限制

| # | 风险/限制 | 影响 | 对策/声明 |
|---|-----------|------|-----------|
| 1 | **Function 变量多参直调无先例**（`(req,res)` / `(req,res,nx)` 依赖 CallClosure 多参） | P1 全部签名 | P0 前置探针；若不支持，回落单参签名 `function( SLang.Request req )` + `req.res` 取 Response（类型不变，仅取用方式变），文档已备该降级路径 |
| 2 | 闭包无类型签名 → 处理器 arity/类型错误运行期才炸 | G1 体验 | 文档固化签名约定；P1 用例覆盖错误签名场景（框架按约定 catch，返回 500 而非崩 VM） |
| 3 | `BaseJson.fromData` 嵌套对象序列化深度/容器支持未验证 | G5 | P0 验收专项；不达标则 ApiResult 整体手工组树（JsonValue），DTO 仍走 toData |
| 4 | multipart v1 全量驻留内存（受 maxUploadBytes 约束） | 大文件内存峰值 | **P7 已根治流式路径**（`multipartStream()` → MultipartReader 逐 part 消费，§6.6/§24）；内存形态（form/file）保留小文件便利性；默认 100MB 上限可配 |
| 5 | 单 VM 协程 = 单核事件循环，CPU 密集 handler 阻塞全部连接 | 吞吐 | 设计声明：v1 面向 IO 密集；CPU 密集建议 isolate（`Lib/Std/Isolate`）外置，P5 评估 handler-isolate 桥 |
| 6 | 无 TLS 服务端 | 生产部署 | v1 明确非目标（§1.2）；前置反代（nginx）承接 TLS 是标准解 |
| 7 | 预读缓冲与 WS 握手衔接（acceptBuffered） | 升级失败率 | P0 探针用例：客户端握手紧跟额外字节（如提前发的首条消息）不丢失 |
| 8 | `docs` 页面自研（无 Swagger UI 完整功能） | 文档体验 | ~~定位为"够用的只读文档 + GET 试调"；完整 Swagger UI 静态包为 P5 可选（体积 ~1MB）~~ **已闭环（2026-10-26）**：`SLang.Plugins.swaggerUI( distDir )` 插件落地——`GET /swagger` 自研 index（外链 dist 资产 + `/openapi.json`）+ `GET /swagger/<file>` dist 直出（§27 实录） |
| 9 | `HttpHeaders`/`File`/`Timer` 依赖 Std 模块引用链 | 模块耦合 | G8 白名单内；与 Mysql→Core 同款机制，风险低 |
| 10 | `SLang` 命名空间跨模块共享（Mysql/Server 并存） | 名称冲突 | 类名互不重叠（Server/Request/Response/... vs Mysql/...）；新增类名前先查 `Lib/SLang/**` |
| 11 | keep-alive 空闲占用协程 | 资源 | 每连接一协程成本极低（C VM 协程轻量）；`keepAliveTimeoutMs` 兜底回收 |
| 12 | 修改公共结构体布局的增量构建坑（AGENTS.md 已知坑） | 仅 P4 C VM 改动 | 遵循"改布局必删树全量重建" |
| 13 | 关键字碰撞（get/set/next/data/as/is） | API 命名 | 已全部规避（§2.3 表）；后续新增 API 命名前查词法器 case 表 |
| 14 | chunked/keep-alive 交互与 SSE 长连接：流式期间连接复用状态机复杂；慢客户端长期占用协程 | P2 流式三件套 | 流式期间每次写出刷新空闲计时；`writeTimeoutMs` 超时兜底断连；close 兜底补终止块（handler 异常退出防连接悬挂）；P2 用例覆盖"流式完成后同连接继续请求"与"handler 中途退出"两条路径 |
| 15 | **handler 协程超时守护语义依赖 P0 探针**：`awaitTask` 对已 cancel/已死 Task 若返回不可靠（如永久挂起），§6.1 守护路径失效 | G12 全部 handler | P0 探针先行（§8）；不达标则守护改为 `waitTimeout` 单一原语（连接协程只轮询 waitTimeout、不走 awaitTask），设计已备该降级路径 |
| 16 | `Task.cancel` 为协作式取消：纯计算死循环 handler 不经调度点，cancel 无效 | 极端 handler 卡死 | 设计声明（与协程模型一致）：超时路径已强制断连止损（连接关闭即客户端侧解除，Task 泄漏至进程退出量级可控）；CPU 密集建议 isolate 外置（与风险 #5 同源） |
| 17 | 每请求 new 控制器实例（§4.10）+ 每请求 spawn handler 协程：分配开销 | 高 QPS 下 GC 压力 | C VM 协程与对象均轻量（风险 #11 同源）；v1 接受，P5 评估控制器池化/单例选项（单例需用户自证无状态）；BenchMark 压测验证 |
| 18 | **直接 await 糖的返回类型判别时机**（§7.5）：parse 层无调用返回类型，误把返回 Task 的调用包 spawn → `awaitTask` 拿到 Task 对象本身而非结果（静默语义错误） | P4.5 语义正确性 | 判别下沉 IR/Meta 层（类型已知处）+ §7.3 前置调研先行；不可靠则退显式标注保守方案（`await spawn fn( 实参 )`）；糖落地前示例一律注明两步 fallback；透传 / 聚合 / Task 变量三条回归用例进 §8 P4.5 验收 |
| 19 | **认证分期依赖**（§4.11）：① JWT 无哈希原语——SL 标准库缺 SHA256/HMAC，G8 白名单禁引外部库 → `sign/verify` 只能留 P5+ 挂靠 crypto 哈希原语（P0–P3 不自造哈希）；② auth 校验回调 `ret 身份 / ret null` 走**闭包带值返回**通路——现有库回调先例均无返回值，属新增机制点 | P3 认证能力边界 | ① `decode` 不验签 → 设计锁定使用纪律（仅己方签发且签验在别处的同源读取，§4.11），`verify` 落地前第三方 token 验真一律不做、文档显著标注；② 进 P0 探针（与 `CallClosure(106)` 多参直调一并排雷，风险 #1 同批次）；探针不达标则 auth 回调改 void 协议降级（回调写 `req.auth` 槽、插件查槽判空短路） |

---

## §11 附录

### A. 状态码 reason 表（HttpServerCore 内置）

200 OK · 201 Created · 204 No Content · 301 Moved Permanently · 302 Found · 304 Not Modified · 400 Bad Request · 401 Unauthorized · 403 Forbidden · 404 Not Found · 405 Method Not Allowed · 409 Conflict · 413 Payload Too Large · 415 Unsupported Media Type · 431 Request Header Fields Too Large · 500 Internal Server Error · 501 Not Implemented · 503 Service Unavailable（其余按需增补，未知码 reason 置空）

### B. 内置 MIME 表（StaticFiles / res.file / contentType 判定）

html → text/html · js → application/javascript · css → text/css · json → application/json · xml → text/xml · txt → text/plain · png/jpg/jpeg/gif/webp/svg/ico → image/* · mp3/wav → audio/* · mp4/webm → video/* · pdf · zip · gz · wasm → application/wasm · woff/woff2 → font/*（未命中 → application/octet-stream）

### C. OpenAPI 类型映射

| SL 类型 | JSON schema |
|---------|-------------|
| string | `{"type":"string"}` |
| Int8/16/32/64（探针整数值） | `{"type":"integer"}` |
| Float32/64 | `{"type":"number"}` |
| bool | `{"type":"boolean"}` |
| List/Array（探针数组） | `{"type":"array","items":…}` |
| 类实例（探针对象） | `{"type":"object","properties":{…}}` 进 components.schemas |
| null 字段 | `{"nullable":true}` |
| 上传字段（`uploadField`） | `{"type":"string","format":"binary"}`（multipart） |

### D. ServerError 码表

| 名称 | code | 语义 |
|------|------|------|
| DuplicateRoute | 1 | 同 method+pattern 重复注册 |
| AlreadyResponded | 2 | 终端响应方法二次调用 |
| NotRunning | 3 | stop/awaitStop 于未启动时调用 |
| AlreadyRunning | 4 | 重复 start |
| InvalidConfig | 5 | 配置非法（端口 0、目录不存在等） |
| BadUpgrade | 6 | Upgrade 握手失败 |
| DocConflict | 7 | 内置文档路由与用户路由命名冲突（用户优先，仅告警） |
| BadSkipPath | 8 | auth 插件 `.skip()` 白名单路径非法（空串 / 不以 `/` 起始） |
| UnknownSecurity | 9 | `r.security()` 声明值超出 v1 集合（仅 `bearerAuth` / `apiKeyAuth`，§4.11） |
| MissingJwtSecret | 10 | `Jwt.sign/verify` 调用时 `ServerConfig.jwtSecret` 未配置（P5+，随签验一并落地） |

---

> **评审通过后的第一步**：按 §8 P0 开工——先建 `Server.jsonc` / `Server.sp` / 空骨架文件与本文档落位，再写 **CallClosure 多参直调探针**（风险 #1 前置排雷）与 **handler 协程派发探针**（风险 #15 前置排雷），然后实现 `HttpServerCore` 探针用例（`test/Other/NetTest/` 旁路），跑通 curl 往返后进入 P1。

---

## §12 P0 落地实录（2026-10-17，代码实况与设计的差异记录）

**产物**：`Server.sl`（ServerConfig/ServerError P0 子集）+ `HttpServerCore.sl`（解析/编码/keep-alive/超时守护/P0 精确路由）+ `Request.sl`/`Response.sl`（P0 子集）+ `Server.jsonc`/`Server.sp`；Std 增量 `Websocket.sl` 三参 `accept(raw, preRead, opt)` 重载；验收用例 `test/Other/NetTest/{ServerProbeTest,ServerCoreTest}.sl`（S 组端口 19371–19374）。

**探针结论（风险 #1/#15/#19 ② 全部排雷通过）**：CallClosure 双参/三参直调、object 传参带值返回、Function 字段拷局部调用全部可用；`waitTimeout` 完成→true / 超时→false 方向正确；`awaitTask` 对已死/已 cancel Task 安全返回不挂起；`spawnClosure2` 双参派发 + await 可用——P1 起按双参签名推进，无需启用 §10 风险 1 的单参降级路径。

**与设计的偏差（均为实现细节，不改变 P1+ 设计）**：
1. **HttpServerCore 为模块级静态单例**（`configure(cfg)/reset()/start()/stop()/awaitStop()/onGet/onPost/onAny/on`），非 §3 的实例形态——C VM 对跨模块引用类多实例化的实例态隔离不可靠（连续 new 多实例时 S2 连接读到 S1 的路由表，闭包零捕获 + 实参传值亦无法规避；详复盘 [2026-10-17]）；v1 单服务器语义下无功能损失，P1 门面 `SLang.Server` 按单实例收口（2026-10-25 已按设计转实例门面——`new SLang.Server( port )` 缺省 80，引擎单例语义保留，见 §19 实录）。
2. **HttpServerCore 内置 P0 精确路由**（提前于 P1 Router 落地了 method+path 精确匹配 + ANY + HEAD 视同 GET + 404/405+Allow），因引擎验收需要路由才能测 404/405；P1 Router（`{param}`/分组/优先级）替换该内部表。
3. **413/431/504/500 走优雅断连** `_gracefulClose`（closeWrite FIN → delay 50ms → 丢弃式收尾读 → close）——直接 close 在入站 body 未读完时触发 RST，HttpClient 收不到响应（设计 §6.11 未提，经验补充）。
4. **`ServerConfig.host` 空值兜底 `"0.0.0.0"`**（跨模块 string 字段默认值消费侧丢失，Int32 正常）；用户工程写 `SLang.ServerConfig()` 后应显式 `cfg.host/cfg.port`（HttpClient 显式字段先例同款纪律）。
5. **`List<object>` + as 转型替代 `List<Net.TcpStream>`**（泛型参数位禁点分类型）；`ApiResult` 类未落地前错误体由 `_errorBody()` 手工组包（键序 code→message→data 与 §6.7 一致）。
6. jsonc 路径基准 = .sp 所在目录（`Lib/SLang/Server/` 深度 5 → `outputDir` 5 个 `..`、references `../../Core`/`../../Std`）；G8 白名单生效。

**下一步（P1）**：`SLang.Server` 门面（包装静态 HttpServerCore）+ `Router/RouteInfo/RouteGroup`（`{param}` 提取/优先级/冲突检测/DuplicateRoute）+ Request/Response 全表（pathParam/query 族 + json/jsonOk/jsonFail/redirect）+ `ApiResult` + BodyParser（json/form/bin 分流）+ WS 路由升级（`app.websocket` + `WebSocketStream.accept(c, preRead, opt)` 接线）+ `WsSession`/`WebSocketServer`；用例迁入 `test/ExpendTest/Server/`（§9）。

---

## §13 P1 落地实录（2026-10-17，代码实况与设计的差异记录）

**产物**：新增 `Router.sl`（RouteInfo/RouteGroup/Router 匹配引擎）、`ApiResult.sl`、`BodyParser.sl`、`WebSocketServer.sl`（独立形态 + WsSession/_WsSessions 注册表）；扩展 `Server.sl` 门面（on* 动词家族/websocket/use/run/start/stop/checkDuplicate）、`Request.sl`（pathParam 族/query 族/body 三形态/bodyJson）、`Response.sl`（链式 + jsonOk/jsonFail/html/redirect）；验收用例 `test/ExpendTest/Server/ServerP1Test.sl`（T1–T8，端口 19401–19408）+ `ProjectTest.jsonc`/`ProjectTest.sp` 登记（references 增 `out/export/SLangServer`）。

**验收**：ServerP1Test T1a–T8c 共 42 项全 OK；ExpendTest 全量 293/293 OK；NetTest 104/104 OK（C VM 网络层改动 P0 回归）。

**与设计的偏差 / 实况要点**：
1. **Router 匹配 = best-static 选择**（非设计 §6.2 的"注册序优先"）：同路径下静态段多者优先、同静态段数先注册优先；`{param}` 参数段以 `RouteInfo._paramSegIdx`（参数名→路径段下标对位表）提取，不依赖参数声明序。静态段优先保证 `/user/new` 不被 `/user/{id}` 抢走。
2. **DTO 序列化契约**：`req.body<T>()` / `SystemJsonFromData` 只展开 `@Serializable()` 标注类的成员——P1 用例 DTO 漏标注时 json 解析走 toString 嫁接（`"Object:92944154"`）假成功形态；文档须明示（`md/lib/Core/ProtocalBuffers.md` 先例）。
3. **WS 握手交接重建**：HttpServerCore 分流到 WS 路由时 HTTP 解析已消费请求行+头，`WebSocketStream.accept` 无法重读 socket——用已解析值重建最小握手请求（`GET <path>[?query] HTTP/1.1` + Upgrade/Connection/Version/Key 四头）灌 `preRead` 参数（§4.6 形态 A 接线点）。
4. **WebSocketServer 独立形态会话收尾**：`_runSession` 的 catch 路径（stop 强制关闭 / IO 异常）必须补 unregister + onClose 回调——漏掉则 `sessions` 计数泄漏、`onClose` 不触发（T7e 用例抓出）。
5. **C VM 修复：net_slot_alloc 单调推进分配**（`csimple_lang/src/lib/os/sys_net.c`）：原实现槽位下标即 sid、close 后立即复用——被 cancel_wait 唤醒的僵尸 accept 协程重执行系统调用时旧 sid 命中复用槽位上的新 socket，抢走新一代监听器连接（T7 连接被抢根因）。修复 = `g_net_slot_hint` 游标单调找空槽、全表满才回收；复盘见 `md/ai/troubleshooting/04-concurrent-net.md` [2026-10-17]。
6. **Front 修复：闭包形参泛型方法调用 NRE**（`MetaCallNode.cs` / `MetaMemberFunction.cs`）：handler 闭包形参作调用对象调 `req.body<T>()` 时 realMetaType 判空回退 + 泛型展开链 mc 兜底；复盘见 `md/ai/troubleshooting/01-front-compile.md` [2026-10-17]。
7. **SL 语言约束落地记录**：跨文件类型引用须带 `SLang.` 前缀（RouteGroup/WebSocketServer/Router）；`this.x` 不可直接作方法实参（须先赋局部别名）；`isnot` 关键字已有实现但无用例（本模块未用）。
8. **响应写出契约补充**：handler 已暂存响应后抛异常 → 引擎照常写出暂存响应（非 500）；未响应才 500（§6.11 语义细化）。

**下一步（P1.5 上传）**：multipart 解析器 + `UploadedFile`（saveAs/saveInto/安全剥离）+ `maxUploadBytes/maxFileBytes`；验收 = §8 P1.5 行。

---

## §14 P1.5 落地实录（2026-10-20，代码实况与设计的差异记录）

**产物**：新增 `Upload.sl`（UploadedFile 上传句柄）；扩展 `BodyParser.sl`（multipart/form-data RFC 7578 全量解析：boundary 提取 / part 头 / 普通字段并入 form 表 / 文件 part / filename 安全剥离 / `_MultipartBody` 内部结果类）、`Request.sl`（file/files/fileCount 文件族 + `_ensureMultipart` 惰性解析 + form 族并入 multipart 字段）、`HttpServerCore.sl`（body 上限分流 maxUploadBytes / multipart 派发前即时解析 400·413 / `_releaseRequest` 请求级资源回收）、`Server.sl`（ServerConfig 增 maxUploadBytes=100MB / maxFileBytes=50MB）；`Server.jsonc` 登记 Upload.sl + UploadedFile struct；验收用例 `test/ExpendTest/Server/ServerP15Test.sl`（T1–T7，端口 19411–19413，原始 TCP 手搓 multipart 构造——HttpClient body 为纯 string 不支持二进制，multipart 必须原始客户端）。

**验收**：ServerP15Test T1–T7 共 10 项全 OK；ServerP1Test T1–T8 共 42 项回归全绿（ExpendTest 全量零 FAIL）。

**与设计的偏差 / 实况要点**：
1. **multipart 即时解析时点 = handler 派发前**（引擎连接协程内 `req._ensureMultipart()`，§6.5「构造期」语义的等价落点——Request 构造发生在路由匹配后，引擎在 spawnClosure2 之前即时触发，保证单文件超限 413 / boundary 缺失 400 走协议层优雅断连，handler 永不见坏包）；`Request._ensureMultipart` 保持惰性幂等（重复调用返回缓存，非 multipart 格式恒 0）。
2. **form 族并入**：multipart 普通字段直接挂进 `_ensureForm` 的缓存表（值不解码，§6.4 直传语义），form/formInt/formBool/hasForm/formKeys 对 urlencoded 与 multipart 统一生效。
3. **`upload_<序号>` 序号 = 文件表下标**（`_safeFilename(raw, seq)` 的 seq 取 `result._files.length`）——多 part 请求中第 N 个空名文件生成 `upload_<N-1>`，非全局从 0 计。
4. **saveInto 目录拼接统一 `/`**（Windows 侧同样接受，不引 Path.combine 免跨模块点分调用）；重名改名 `stem(N)ext` 含点扩展保原大小写。
5. **SL 语言坑两枚**：① `data` / `base` 是关键字不能作参数/变量名（UploadedFile 构造参数 `data→content`、saveInto 局部 `base→dirBase`）；② `bool.toString()` 输出 **"True/False"**（C# 风格大写开头），测试断言小写 "true" 会假失败。
6. **Front 已知限制（记录备修）**：闭包方法体内 `List<SLang.UploadedFile>`（typealias 或点分类型均触发）在模板实例化链 NRE（`MetaClass.AddMetaTemplateClassByMetaClassAndMetaTypeList`，与 P1 复盘 6 同族）；**链式访问 `req.files("x").length` 正常**——测试侧以链式 + 字段区分规避，Front 修复后可补强逐元素用例（`ps[0].filename`）。
7. **宿主修复（附带产出，`CSimpleVMTest/Program.cs`）**：`CopyModuleIntoPackage` 增 `StageReferencedModules`——解析主模块 `moduleReferences`，非系统库引用（ExpendTest→SLangServer）的导出产物（两处标准导出树 `SlangAllInOne\out\export\<名>\` / `SlangAllInOne\SLangCore\out\export\<名>\`）连带拷入包 `<pkg>\<名>\`；Core/Std/Math 走包内 `<exe>\lib\` 直查不拷。**背景**：此前引用模块不跟随，C VM 对落空引用**静默 skip**（仅 VM.txt Warning、退出码 0），跨模块调用全部落到空壳方法——`ServerConfig` 字段全空 / `Server.start` no-op / 测试挂死后 VM 判定无在途 IO "成功"收尾，极具迷惑性（本次 P1.5 验收首跑即踩，最小复现 + 同一 slb 换目录运行二分定位 ~2 小时）；复盘见 `md/ai/troubleshooting/06-build-engineering.md` [2026-10-20]。

**下一步（P2 管道插件与流式）**：中间件管道（`SLang.Next` + nx.go()）+ `ServerPlugin` 基类 + logger/cors/staticFiles 内置插件 + 流式三件套（`StreamWriter` chunked / `SseWriter` SSE / `sendFile`）+ `wsEvents` 糖 + 通配路由 `{path*}`；验收 = §8 P2 行。

---

## §15 P2 落地实录（2026-10-20，代码实况与设计的差异记录）

**产物**：新增 `Plugin.sl`（`Next` 放行令牌 / `_Pipeline` 管道执行器 / `ServerPlugin` 插件基类（onInstall·onStart·onStop·onWsOpen·onWsClose 钩子）/ `_PluginHost` 静态宿主（`List<Function>` 中间件表 + `List<object>` 插件表 + 钩子广播））、`Plugins.sl`（`logger()/cors()/staticFiles(root)` 内置插件）、`StreamIo.sl`（`StreamWriter` chunked write·writeBytes·flush·close / `SseWriter` send·sendEvent·comment·close）；扩展 `Response.sl`（`stream()/sse()/sendFile()/file()` + `_direct` 直写通道 + `_streamWriter` 绑定）、`HttpServerCore.sl`（管道执行接入（§6.9）+ 流式三态写出分支 + 管道异常/契约违约 500 兜底）、`Router.sl`（`{path*}` 通配尾段——仅识别最后一段，匹配剩余全部段）、`Server.sl` 门面（`use(Function)`/`use(ServerPlugin)`/`wsEvents(path)`）；`Server.jsonc` 登记 Plugin/Plugins/StreamIo 三文件；验收用例 `test/ExpendTest/Server/ServerP2Test.sl`（T1–T4 共 24 项，端口 19421–19424，原始 TCP 手搓收发）。

**验收**：✅ 2026-10-20 全绿——ServerP2Test T1 管道 5 项（短路 401 / onion 序 + userData 传值 / 404 过管道 / onInstall 立即性 + onStart / onStop）、T2 内置插件 6 项（CORS 预检 204 / 静态 txt·html MIME / miss→404 带 CORS 头 / 穿越 403 / 路由+静态共存）、T3 流式 5 项（chunked 编码+终止块 / 引擎 close 回退 / keep-alive 续用 / SSE 线格式 / 流式连接超时豁免）、T4 5 项（sendFile 160KB 往返 / 缺失 404 / file() 附件头 / 通配多段·单段·空段 / wsEvents 开·收·关）全 OK；P1 42 项 + P1.5 10 项回归全绿（ExpendTest 全量零 FAIL、测试输出零调试残留）。

**与设计的偏差 / 实况要点**：
1. **onInstall() 无参**（设计 §4.7 `onInstall(app)` 传实例）——P1 起门面为静态形态（§12 复盘 ①），插件经 `SLang.Server.*` 静态调用注册；Plugin.sl 类头注记已载。
2. **onion 执行形态 = 连接协程内联同步嵌套**：`Next.go()` 直调 `_runFrom(idx+1)`，后置环在 handler 协程 `awaitTask` 返回后自然回程；中间件自身可 await（§4.7 契约兑现）。SL 无方法引用 → 框架持环索引逐环构造 `Next`（§6.9 设计原样落地）；`nx.go()` 幂等（重复调用 no-op 防双派发）。
3. **未匹配请求同样过管道**（404/405 = 尾环应答模式）——staticFiles/CORS 预检语义依赖此；管道正常返回但零响应 = 契约违约 500 + 断连；管道异常四分支：流式头已发→兜底终止块+断连 / sendFile 半截→断连 / 已缓冲完成→照常写出（首个响应胜出）/ 未响应→500。
4. 🔥 **C VM 修复（本次核心附带产出，`csimple_lang/src/vm/runtime/vm_runtime.c` OpCode_CastClass Step 6）**：管道首验 T1/T2 全 500，根因链——`_middlewares` 底层 `Array<Function>` 元素槽 etype=Class(20) → `List<T>._getItem_` 方法体 `ret SystemArrayGetValueThis(...) as T` 被 Front 内联发射 CastClass（目标 = 模板参数节点，运行期绑定 Core.Function）→ VM 侧 Step 6 的 etype 闸只认 `EVMType_Object`（**全库 30+ 处 Object||Class 并列检查的唯一例外**），Class etype 闭包引用被吃掉 push null → `mw==null` → no-response 500。**修复双改动**：① 闸放宽 `Object||Class`（Class etype 值必经类型化引用槽装载、持真实对象指针，非 scalar union 别名——闸本意只拦 raw scalar）；② 闭包对象特判：闭包载体是无绑定 RuntimeType 的裸 payload VMObject（`vm_object_get_runtime_type` 返回 NULL，extends 检查不可用），故 source_rt==NULL 时以 closure magic（'CLSR'/native FFI 两族）识别 + 目标类名双形态（`"Function"`/`"Core.Function"`——RuntimeClass 名带命名空间、与 payload 侧 def 类型名形态不同）放行。P1/P1.5 的 `List<RouteInfo>` 等真类实例全绿 = extends 路径本就正常，差异全在闭包无 rt；取证过程（IR 反查定位发射点 + 三层插桩对账）复盘见 `md/ai/troubleshooting/03-vm-runtime.md` [2026-10-20] 条。
5. **staticFiles 仅 GET 直出**（HEAD 放行——sendFile 直写路径未做 HEAD 摘除，已知限制，后续随 P5 打磨补）；MIME 按扩展名映射、未知名 `application/octet-stream`。
6. **流式连接豁免 `handlerTimeoutMs`**（T3e 专项验证）：chunked/SSE 连接不参与超时收割——否则长推送必被 400ms 级超时杀死；普通 handler 超时行为不变（P0 504 路径）。

**下一步（P3 文档+认证）**：`OpenApiBuilder` + `/docs` + `/openapi.json` + `importOpenApi`（未注册路径文档路由 501 → onGet 覆盖工作流）+ `bodyLimit/requestId/auth` 插件 + `SLang.Jwt.decode` + `maxConnections`；验收 = §8 P3 行（Apifox 实际导入 + securitySchemes 自动配 Auth）。

---

## §16 P3 落地实录（2026-10-21，代码实况与设计的差异记录）

**产物**：新增 `Docs.sl`（openapi.json 生成（探针法 schema：样例实例 → fromData → JSON 树 → 逐节点映射 string/integer/number/boolean/array/object/nullable；手工组 TreeNode 树 + BaseJson.fromTree 序列化）/ `/docs` 自包含 HTML 页面（零外链零 CDN，同源 fetch openapi.json 渲染 + GET try-it-out）/ `importOpenApi`（文档路由 isDocOnly·501 + 覆盖让位 + 元数据合并））、`Jwt.sl`（`JwtClaims`（claim/put/subject/expiresAt/expired）+ `Jwt.decode`（三段定位·base64url 反归一·payload 解析·Map 载体）；零新依赖）；扩展 `Router.sl`（`RouteInfo` 结构化文档元数据（docParams/docForms/docBodyText/docResponses/security/isDocOnly/isBuiltin + 链式 `param/requestBody/formField/uploadField/response/responseAs/security`）+ `RouteParam`/`RouteResp` 记录类 + `findExact` 精确查找 + `add` 文档路由让位继承）、`Plugins.sl`（`_BodyLimitPlugin`（contentLength 超限 413）/ `_RequestIdPlugin`（Guid → X-Request-Id）/ `_AuthPlugin`（三挂法单类：通用回调收 req·Bearer→Jwt.decode→req.auth=JwtClaims·API Key 自定义头；`.skip()` 白名单·`.ws(true)` token 接管（onWsOpen 查询参数校验失败关会话）；401 附 `WWW-Authenticate: Bearer`（RFC 6750，仅 Bearer 模式））+ 工厂 `bodyLimit/requestId/auth/authBearer/authApiKey`）、`Plugin.sl`（`ServerPlugin` 基类增 `skip/ws` 链式占位（子类 override，返回类型统一 ServerPlugin——跨模块链式调用按基类签名决议））、`HttpServerCore.sl`（start 挂载 /docs + /openapi.json（`_docsEnabled` 开关，reset 恢复默认开）+ maxConnections 超限 503 协议层应答 + `_errorBody` 503）、`Server.sl`（ServerConfig.maxConnections=1024 + 门面 `docs(bool)`/`importOpenApi(path)`）；`Server.jsonc` 登记 Docs/Jwt + struct 增 RouteParam/RouteResp/Jwt/JwtClaims；验收用例 `test/ExpendTest/Server/ServerP3Test.sl`（T1–T6 共 33 项，端口 19431–19435）。

**验收**：✅ 2026-10-21 全绿——T1 openapi 生成 7 项（3.0.3 骨架+servers / paths+summary+tags / path 参数 in/required/type / requestBody $ref+schema 复用+example / 嵌套 DTO properties / securitySchemes 双定义+operation security / form 字段 urlencoded）、T2 docs 3 项（自包含页 / 用户让位 / docs(false) 关闭）、T3 auth 10 项（Bearer 四态：缺失 401+头·坏 token·好 token claims 透传·skip 放行 / API Key 三态 / 通用回调三态）、T4 Jwt 5 项（claims 读取 / exp 未来 false·过去 true·缺失恒 false / 坏格式三连 null）、T5 importOpenApi 5 项（计数 / 501 / 共存 / 覆盖让位 / 元数据继承）、T6 1 项（maxConnections 首连接 200·次连接 503）全 OK；P1 45 + P1.5 10 + P2 24 回归全绿（ExpendTest 零 FAIL）。

**与设计的偏差 / 实况要点**：
1. **链式 .skip()/.ws() 上移基类**：静态工厂返回 `ServerPlugin`（跨模块子类上行赋型纪律，§12 复盘 ①）导致 `.skip()` 在基类上不可见（MetaCore 链解析失败）——`ServerPlugin` 基类加 no-op 占位、`_AuthPlugin` override（返回类型必须一致），非 auth 插件调用为 no-op。
2. **探针法 schema 键 = `Type.toString()`**：设计的 `SystemObjectGetType(sample).className` 实为 `Type.metaClass.className`（两跳，Meta 层不通过）——改用 `ty.toString()`（内含 className + 模板参数展开，DTO 无模板 = 纯类名）。
3. **`BaseJson.fromTree` 收 Tree 不收 TreeNode**：根节点需 `Tree.setRoot(node)` 包一层。
4. **importOpenApi 只回填轻量元数据**：summary/tags/desc/param/security（样例实例无法从 JSON 反推，requestBody/responses 不回填——v1 偏差已注记类头）；ANY 路由在 openapi.json 展开 7 动词同 op；WS 路由不进 openapi.json。
5. 🔥 **Front 三坑规避实录（本轮排障主战场，SL 侧全数绕开、未改 Front）**：
   - **`$` 是字符串插值前缀**（md/syntax/keywords.md §3.5）：字符串字面量**任何位置**出现 `$`（含 `"$"+` 拆分拼接）都会吞掉后续 token——`"$ref"` 键值对改 `Docs._dollar()`（ByteBuffer 构造 "$" 单字符）拼接，JS 侧 `sch.$ref` 改 `String.fromCharCode(36)+'ref'` 运行期生成；
   - **长字符串字面量 "+" 链求值截断**：`ret "段1" + "段2" + ...` 跨行链实测**仅首段字面量存活**（pageJs 21 字符 = 首段；变量链 5 段/局部累加 20 段均正常——字面量链特有）；`_htmlPage/_pageCss/_pageJs` 全部重写为 `StringBuilder.append` 逐段追加（一次通过）；
   - **关键字撞名**：`out`（变量定义名禁用；`string out = ...` 报 NodeStructParseN `'=' 后缺少赋值表达式`——报错信息与真实原因相距甚远）、`params`（变参关键字，作局部变量名同样炸）——改名 `res/paramsNode/bufOut`；
   - 另两处编译期纪律：`ret 方法调用()` 跨行续 `+` 链中段裸标识符会被误判类名（拆局部变量）；`for` 三段分隔符是**逗号**不是分号（`for i = 0; i < n; i++` 静默 NRE，无报错线索）。
6. **maxConnections 503 = 协议层应答**：accept 循环内 `_writeSimple(503) + _gracefulClose`，不进管道不占连接协程（§6.11 精神）；keep-alive 占住名额的连接在 stop/超时释放后恢复。

**下一步（P4.5 直接 await 糖）**：§7.5——`await` 后跟返回非 Task 的调用自动包 spawn 脱糖（判别下沉 IR/Meta 层，§7.3 调研项先行）；验收 = §8 P4.5 行（透传/聚合/Task 变量三条回归红线）。

---

## §17 P4 落地实录（2026-10-24，代码实况与设计的差异记录）

**产物**：C VM 新增 `vm/runtime/attribute/vm_route_attribute.c`（路由表：`s_route_append` 方法条目（verb 大写/path/method_id）+ `s_prefix_append` 类前缀表（class_id→prefix）+ `_enter_` join（method_id→RuntimeClass→前缀拼接→"verb|path|class|method" 行）+ 查询四接口（count/line/class_id/method_id，join 前一律空响应）+ 10 个 attribute handler（On 动词家族 8 共享 collect（名→verb 映射表）/ `@Route` 双参显式 verb（缺省 ANY·大写化，enter/exit 挂此条目）/ `@OnRoute` 类级 collect_class（六字段结构第五 NULL 教训：collect_class 必须显式写满））；`vm_runtime_attribute.c` 扩展 collect 方法级+类级双扫描（stage==Preload 且 handler 名匹配分发）+ `vm_runtime_attribute_reset` 集成路由表重置；`server_system_method.c` 三系统方法（`ServerGetPreloadRouteCount` / `ServerGetPreloadRouteLine` / `ServerBridgeCall`——new 控制器实例 + VM 级直调目标方法）；SL 层 `RouteAttrs.sl`（10 属性类收编自 Std/Net/Route.sl，原文件删除）+ `Server.sl` `usePreloadRoutes()`（拉表→RouteInfo→Router，重复调用幂等返回 0）+ `Server.jsonc` systemCalls/struct 三处登记；R6 CMakeLists+vcxproj 登记零错误零警告；验收用例 `test/ExpendTest/Server/ServerP4Test.sl`（T1–T3 共 13 项，端口 19441）。

**验收**：✅ 2026-10-24 全绿——T1 路由 9 项（preload count==6 / OnRoute prefix join / 每请求一实例（两次请求实例不同）/ @Route("DELETE") / plain OnGet / OnAny 两动词命中 / 动态注册共存 / 404 / 405+Allow）、T2 异步 2 项（await+delay 200 / 慢 handler 超时 504）、T3 幂等 2 项（二次拉取仍 6 条 / duplicate fail-fast）全 OK；ExpendTest 全量（P1 45 + P1.5 10 + P2 24 + P3 33 + P4 13 + 其余全套）回归零 FAIL、exit 0。

**与设计的偏差 / 实况要点**：

1. **🔥 根因定位链（R12 插桩纪律实录，11 FAIL → 0）**：首轮回归 11/13 FAIL。逐层排除：① Front 契约链实锤完好——导出 json 中类级 `@OnRoute`（stage=2 targets=1）与方法级 `@OnPost`（stage=2 targets=16、methodId 非零）全数正确，slb/json 同秒生成排除旧包，UVarInt 负数位模式编码往返无损（C# `(long)(uint)value` ↔ C `(int32)(uint32)(uint64)v` 对称）；② C VM 三处插桩（collect 统计/append 丢弃原因/enter 无条件）重建重跑——collect 完美（6 方法+1 类前缀全 matched=6/1，handlers=12）、append 零丢弃（routes=6 prefixes=1）、**enter joined=0**：断点锁定 `find_runtime_class_by_method_id` 恒 NULL。
2. **🔥 根因：`declaringTypeFullName` 短名 vs 类 `fullName` 全名**——Front 导出方法字段的 `declaringTypeFullName` 为**短名**（`"P4AdminController"`，甚至 Core.Object.refEquals 也是 `"Project"`——该字段整体不可靠），而类 `fullName` 带命名空间前缀（`"ProjectTest.P4AdminController"`）；`sl_runtime_assembly_find_class_by_full_name` 全等比较 → **owner_class 恒 NULL** → `method_entries[].runtime_class=NULL` → P4 join 全灭。现有调用链未炸的原因：方法调用走扁平 `method_id_hash`、类方法绑定走 `bind_class_methods`（类内嵌 `non_static_method_list[].id` 全名 id），均不依赖该字段——只有 P4 路由 join 首次消费它。
3. **修复：本模块短名回退**（`sl_runtime_assembly.c` 方法注册循环）：全名匹配失败且 declaringTypeFullName 非空时，**限定本模块 class_list** 按 `cls->name` 短名回退（Front 同模块类名唯一约束；不跨模块避免歧义）。仅救 NULL：已匹配成功的路径（如 Core 宿主类 "Project"）零影响。副作用边界核实：`runtime_class_add_method` 与 `bind_class_methods` 同表且 bind 先 clear 再 rebind（enter_all 之后跑），owner_class 唯一持久效果即 `method_entries[].runtime_class`——P4 join / array·ffi·coroutine 系统方法 host_rc 同获更正确数据。json 中另有的 `declaringClassId` 字段（数值正确，=-998246793 与类 id 一致）C 模型未解析，彻底根治需 Front 编码+C 解码双端扩字段并全量重编 slb，留作后续演进项。
4. **诊断插桩已收敛**：P4DBG 三处临时日志全部移除，保留 join 成功统计日志（joined_count>0 门控）。
5. **跑法备忘**：回归命令 `csimple_lang.exe run --no-banner <module.json>`（cwd=ExpendTest，Sqlite3Test 资源相对路径要求）；VM 日志在 `csimple_lang\build\logs\VM.txt`（cwd 相对）。

**下一步（P5 打磨）**：前缀树路由 / 请求侧流式（`r.streamBody` + `HttpBodyReader` 边收边落盘上传） / Range 断点续传 / 主动心跳 / `rateLimit` 插件 / `SLang.Jwt.sign/verify`（HS256，前置依赖 = 标准库 crypto 哈希原语）/ TLS 服务端评估；验收 = §8 P5 行（基准 + 压测）。

---

## §18 P4.5 落地实录（2026-10-25，代码实况与设计的差异记录）

**产物**：SL 层 `Lib/Core/Coroutine.sl` 增标记方法族（`__awaitCall( object )` 换绑标记 + `__awaitSpawn0..3( Function, object... )` 非直等执行体：`awaitTask( spawnClosureN( f, 实参 ) )`）；Front 三处——`Parse/StructParseToSyntax.cs` await 分支（操作数为调用形态且非函数值变量（判据与 spawn 分流一同源 `IsLocalScopeDefineName`）时发射 `Coroutine.__awaitCall( <调用原样> )`，其余形态维持 `awaitTask`）、`Core/MetaCallNode.cs`（internal `SetAwaitSugarBinding` 换绑 setter）、`Core/MetaCallLink.cs`（`TrySwapAwaitSugarMarker` 换绑核心 + `FindCoroutineMethodByArity`/`GetFirstParamMetaClass` 辅助，挂在 `AddVisitNodeList` 的 MemberFunctionName 分支顶部）；`Log/LID.cs` + `ErrorDefinitions.csv` 增 21480（糖不支持目标/超 3 参）；验收用例 `test/ExpendTest/Server/ServerP45Test.sl`（T1–T3 共 13 项）。

**验收**：✅ 2026-10-25 全绿——T1 直等 6 项（静态 0/1/3 参（`__awaitSpawn0..3` 全档）/ 实例方法（receiver→方法引用，this 绑定验证 mul=10×5）/ 目标体内 `delay(120)` 真挂起后取回 / void 目标副作用）、T2 三红线 3 项（返回 Task 的调用**透传不回归**（`makeSlowTask( 7 )` 与 `httpGetAsync` 同「调用形态 + Task 返回」类型学通道）/ 显式 spawn `waitAll2` 聚合不回归 / Task 变量基础形态不回归）、T3 边界 2 项（函数值变量调用保守路径（`function mkt = ServerP45Test.makeSlowTask` 方法引用 + 中间 Task 变量）/ 直等+透传+变量三形态混用）全 OK；ExpendTest 全量零 FAIL；BaseTest OK=679 FAIL=26 与 2026-10-23 既有基线（Monitor P5/P6 9 项 + CoroutineTest 5 项 + TupleTest 10 项 + P6 debug 2 项）**逐条完全一致零新增**；MathTest/NullFastTest/SpecialTest/BenchMark exit 0。

**与设计的偏差 / 实况要点**：

1. **实现形态 = 换绑标记，非设计倾向的 IR/Meta 判别下沉**：调研发现「方法引用」特性（2026-10-18）+ C VM `spawnClosure` 的方法引用专用通道（`vm_sys_coroutine_spawn_method_ref`，P4 落地时同源扩展）已提供全部建材——**零闭包合成**方案成立：parse 层发射单实参标记调用 → MetaCore 在 visit 构建前（类型已知点）换绑目标函数指针 + 重建实参集合。比设计的「提升无参包装闭包 + spawnClosure0」更优：实参在 **await 点立即求值**（原设计的包装闭包路径延迟到协程首跑），且无闭包合成成本。IR 层零改动。
2. **Task 判定基准 = `awaitTask` 首参类型**（`FindCoroutineMethodByArity` 权威查找 + `ReferenceEquals` 同 ref 壳实例比较 + 名字兜底），免按名查找的跨模块壳类失配。
3. **换绑幂等性**：只改 Meta 层绑定（`m_MetaFunction`/`m_MetaInputParamCollection`），词法/语法树不动——重解析时 `CreateCallNode` 从原始术语自然重建（标记重现，再次换绑）；换绑后不再是标记名，重复触发自然短路。
4. **spawn 分支的内层改造**：实参调用链 visit 列表**末位 MethodCall 原位换 MethodReference**（receiver visit 节点不动——实例引用 receiver 留栈供 `NewMethodRef` 弹出，静态引用前置 MetaClass 访问节点无栈值，与自然方法引用形态完全一致）；方法引用表达式以新壳 `MetaCallLinkExpressNode( innerLink )` 作为新实参集合首参（返回类型缓存从零重算 = 引用值类型 `FunctionSignatureMetaClass`）；原实参表达式（上游已解析）原样提升——IR 发射即在 await 点求值。
5. **边界与降级**：目标为 get/set/构造/模板方法或实参 > 3 → **编译期 Error 21480**（VM 方法引用 spawn v1 仅固定 0..3 参，变长形态拒绝）；实参非调用链 / 系统调用 / 类型未知 / 函数值变量调用 → **留标记兜底**（`__awaitCall` 函数体 = `awaitTask( v as Task )`，运行期语义与旧脱糖一致：同步求值 + 直等，null → awaitTask 报错路径不变）。函数值变量调用的静态签名类型（FunctionSignature）与 Task 形参不兼容是**类型系统既有局限**（`awaitTask` 严格 Task 匹配），非本糖回归——用例 T3a 已注记并用中间 Task 变量承载。
6. **C VM / IR / 导出格式零改动**：本阶段纯 Front（Parse + MetaCore）+ Core 库（Coroutine.sl，需重编 Core.module.slb 并刷新消费工程 lib）。ExpendTest lib 刷新 + 全量重编后 C VM 直接跑通。
7. **跑法备忘**：`compile-tests.ps1 -Tests a,b,c` 的 `-File` 传参只绑首个（PS5.1 数组参数限制）——多套件用 `-Command` 形式；MathTest/SpecialTest 的 TestMap Module 路径与实际导出目录（`test\<套件>\export\...`）失配致 fresh 检查误报 FAILED，产物实际已刷新（脚本层既有问题，非编译失败）。
8. **文档同步**：`md/syntax/coroutine.md` §4 关键字表 + §4.2 直接 await 糖节（三分支规则表 + 边界警示）重写；`md/syntax/function.md` VM 侧注更新（协程 spawn 例外——方法引用经专用通道支持，此前「不支持」表述已过时）；本文件 §8 P4.5 行打勾 + 本实录。

---

## §19 实例门面转换实录（2026-10-25，静态门面 → 设计目标实例形态）

**背景**：P0-P4 落地期间门面曾收口为静态形态（§12 复盘 ①），用户点名回归设计目标形态（§0/§4.1/§4.9）——`SLang.Server` 须 new 出来，构造带端口，缺省 80。本次为纯 API 形态重构，功能零增减。

**产物**：`Server.sl` 重写为实例门面（423 行）——双构造 `_init_()`（缺省 80）/ `_init_( Int32 port )`（构造期经 `HttpServerCore.configure` seed 默认配置，start 前可改）；`public get ServerConfig config()`（读引擎 `_cfg` 引用直返，start 前直改字段生效，null 兜底重 seed）；`configure( cfg )`（全量覆盖 + `this.port` 同步）；`start()/start( port )/run()/run( port )/stop()/awaitStop()/reset()/isRunning`；路由族 `onGet/onPost/onPut/onDelete/onPatch/onHead/onOptions/onAny/on`（返回 RouteInfo）+ `group( prefix )`；`use( Function )/use( ServerPlugin )`；`websocket( path )/wsEvents( path )/sessions( path )/broadcast( path, text )`；`docs( bool )/importOpenApi( file )`。`HttpServerCore.sl` 增引擎级静态通道 `sessions( path )`/`broadcast( path, text )`（闭包零捕获纪律下协程内取会话/广播的唯一通道）；`Plugins.sl` 插件 onInstall 自注册改走 `HttpServerCore` 静态；`Plugin.sl`/`RouteAttrs.sl` 类头注记同步。

**验收**：✅ 2026-10-25 全绿——模块重导（`CompileStdlib` 显式工程路径模式 → `out\export\SLangServer\` slb+json 双产物，slb mtime fresh 核验）后 ServerTest 联合宿主全量：P0 探针 + P0 引擎 + P1 + P1.5 + P2 + P3 + P4 + P4.5 八套件全部 OK、零 FAIL、exit 0（用例明细见 §8 对应行）。

**与设计的偏差 / 实况要点**：

1. **实例门面是薄壳，引擎层维持模块级静态单例**：`Server` 实例仅持 `public Int32 port`，全部状态（配置/路由/中间件/WS 会话）仍在 `HttpServerCore` 模块级——C VM 多实例实例态隔离不可靠的结论（§12 复盘 ①）未变，v1 单 VM 单服务器语义，跨实例共享路由/中间件/会话；`this.port` 只作构造记忆与便捷覆盖的落位点。
2. **`reset()` 只清路由不清配置**（引擎原语义保留）——推论两条：① 同端口重新装配可省略重复 configure（`app.stop(); app.reset()` 后直接重注册路由再 start）；② 同方法内端口切换用重赋值重 seed：`app = SLang.Server( newPort ); app.reset()`（P3 t3Auth 三段端口切换即此形态）。
3. **测试改写五条转换模式**（P1 45 处 + P1.5 13 处 + P2 19 处 + P3 35 处编辑；P4 本就实例形态零改动）：
   - 纯配置段：`cfg = ServerConfig(); cfg.port = X; SLang.Server.configure( cfg ); reset` → `SLang.Server app = SLang.Server( X ); app.reset()`；
   - 带额外字段：`SLang.ServerConfig cfg = app.config; cfg.字段 = V`（getter 返回引擎 `_cfg` 引用，直改即生效）；
   - 路由/生命周期：`app.onXxx( path, fn ); app.start( PORT ); app.stop()`（**保留 `start( port )` 显式端口便捷形态**，测试用它自证端口语义）；
   - 闭包内取会话/广播：`SLang.HttpServerCore.sessions( path )` / `SLang.HttpServerCore.broadcast( path, text )`（闭包零捕获，不可引用 `app` 实例）；
   - 同端口重复 configure 块整体省略（推论 ① 的直接应用，P3 t2DocsPage T2b/T2c 段）。
4. **`config` getter 双形态调用**：`app.config`（无括号）与 `app.config()`（带括号）均合法，测试统一用无括号形态。
5. **发布树 `publish\release\SLangServer.module.slb` 未随本次刷新**（12:04 旧产物）——测试消费链走 `out\export\` → 宿主 `StageReferencedModules` 拷入包目录，本次已随测试运行自动刷新 `package\win32-debug\SLangServer\`；独立发布产物待下次 publish/pack 时重打。

**下一步（P5 打磨）**：同 §17（前缀树路由 / 请求侧流式 / Range / 心跳 / rateLimit / Jwt.sign·verify / TLS 评估）。

---

## §20 P5 落地实录（2026-10-26，代码实况与设计的差异记录）

**产物**：

- **前缀树路由**：`Router.sl` 重构——`_RouteNode`（静态边 `Map<string,object>` + 参数边 `_RouteNode _param` 共享 + 四表：`_routes`/`_wsRoutes`/`_wild`/`_wsWild`）替代 v1 双线性表；注册经 `_attach`/`_descendBuild` 挂树，匹配经 `_collect`（DFS 沿段下降，每层至多静态+参数两条分支）+ `_pickBest`（静态段多者优先 / 同数 `_seq` 注册序平局裁决）；`checkDuplicate` 改树遍历 `_dupScan`（同 pattern 必挂同节点，节点内双循环等价全表分组比较）；Docs 消费侧新增 `Router.allRoutes()` 树遍历快照。
- **Range 断点续传**：`Response.sendFileRange( path, rangeSpec )`（`sendFile` 委托其 null 形态）——"a-b"/"a-"/"-n" 三态解析（`_parseRange`：有效 → 206 + Content-Range + FileStream seek 定位 + 64KB 分块截取；start 越界/倒置 → 416 + `Content-Range: bytes */size`；畸形 → RFC 9110 允许忽略按全量 200）；恒发 `Accept-Ranges: bytes`；`staticFiles` 插件透传 req 的 Range 头；`_reason` 表补 416/429。
- **WS 空闲心跳**：`WsSession._startHeartbeat( idleMs )`（看门狗协程：步长 idle/4 钳制 [100,1000]ms 轮询 `_lastActive`，超时 `close` 会话 → handler receive 返回 null 自然收尾）；`receive()` 返回即刷新活跃时刻；`ServerConfig.wsIdleTimeoutMs`（<= 0 不启用，缺省关）+ 引擎升级分流/独立端口两形态接线。
- **rateLimit 插件**：`SLang.Plugins.rateLimit( max, windowMs )`——按客户端 IP 固定窗口；超限 429 + `Retry-After`（剩余秒向上取整）短路；桶表 `Map<string,object>` + as 转型（_WsSessions 纪律），每 256 次放行判定顺带清一遍过期桶。
- **C VM crypto 原语**：`src/core/sl_core_sha256.c/h`（SHA-256 FIPS 180-4 + HMAC-SHA256 RFC 2104，照 `sl_core_sha1.c` 纪律：纯 C / 无平台代码 / 两段 sizing；R4 零警告通过）；VM 适配 `vm_sys_sha256_digest` / `vm_sys_hmac_sha256`（`byte_buffer_system_method.c` Section 15）；R6 登记（CMakeLists + vm_lib vcxproj + filters）；R7 四处同步（SL 声明 `Std/Encoding/Sha256.sl`、`Std.jsonc` systemCalls 两条、C 实现与头、—— C# `ESystemMethodCall` 枚举经查证**无需登记**：SystemSha1 先例即无枚举条目，systemCalls 按名经 dlsym 动态解析）；标准测试向量验证（SHA-256("abc")=ba7816bf… / HMAC-SHA256("key","msg")=2d93cbc1…）。
- **Jwt HS256**：`Jwt.sign( claims, secret, expSec )`（iat 恒写 / exp>0 写；`MissingJwtSecret` 防御）+ `sign( claims, expSec )` 便捷形态（密钥取 `ServerConfig.jwtSecret`）+ `verify( token, secret )` / `verify( token )`——全量校验（三段 / **header.alg 必须字面 HS256**（拒绝 none 降级）/ 签名重算逐字节比对 / exp 过期拦截）；base64url 编码归一（`Base64.encodeToString` + '+'→'-'、'/'→'_'、剥 '='）与既有 `_normB64Url` 解码对称；`decode` 不验签语义独立保留。
- **请求侧流式**：`RouteInfo.streamBody = true` 注册期声明 → 引擎 `_parse` 增 `stopAtHead`（头区空行即停，CL/chunked 元信息经 `_HttpParseResult._streamCl/_streamChunked` 带出）→ 命中路由时 `Request._bindStream` 移交连接 + 预读缓冲 → `req.bodyStream()` 构造 `HttpBodyReader`（新文件 `HttpBodyReader.sl`：`read( dst )` CL 精确/chunked 感知/累计超限抛 `StreamBodyError.LimitExceeded`、`readAll()` 聚合；上限取 `cfg.maxBodyBytes`，multipart 放宽 `maxUploadBytes`）；未命中路由走 `_parseHeadless` 补读 body（v1 全量缓冲语义零变化）；handler 返回后引擎 `_releaseRequest` → 6a 收尾：未消费完整且拟 keep-alive → 引擎丢弃式排干（复用读取器），排干失败/超限 → graceful close 断连止损。
- **TLS 服务端评估**（结论性，不落代码）：mbedtls 3.6.7 已在树（`sys_tls.c` 客户端 session 形态含 `mbedtls_ssl_config_defaults(server)` 分支——即 conf 层已具备服务端骨架）；落地方案 = `Net.TlsServer.listen` + accept 后 `sys_tls_server_handshake`（装载 own_cert/own_key，PEM 文本经 SL 传入）+ `TlsStream` 包装既有双向；工作量集中在证书/私钥参数链路 + SL 层 API + `ServerConfig.tls` 段；**维持 P6+ 不在 P5 落地**的理由不变（生产标准解 = 前置反代，见 §1.2/§10 风险 6）——评估完成，决策：留待真实部署需求触发。
- **错误码**：`ServerError.MissingJwtSecret = 10` 接入（附录 D 最后一项归位）；`StreamBodyError` 新枚举（LimitExceeded=1）。

**验收**：✅ 2026-10-26 全绿——`ServerP5Test.sl` T1–T6 共 28 项全 OK（明细见 §8 P5 行）；ServerTest 全量 178/178（P0 探针 + P0 引擎 + P1~P4.5 + P5）；ExpendTest 250/250、NetTest 81/81 回归零 FAIL；BaseTest 26 FAIL = 2026-10-23 既有基线**逐条一致零新增**；MathTest / NullFast exit 0。

**与设计的偏差 / 实况要点**：

1. **路由树保留"收集后择优"而非树内单径**：`{path*}` 通配挂前缀节点 + 参数边共享意味着同一路径仍可能多候选（与 v1 线性扫描的候选集完全一致）——设计倾向的前缀树 O(段数) 单径裁剪需要"静态段全局优先注册序"约束，会改变语义；v1 语义保持优先，树化的收益落在**候选集收缩**（不相关分支不再评估），符合 §1.2「前缀树为优化项，非语义变更」的定界。
2. **流式请求的解析策略 = 先头后路由再补 body**：`stopAtHead` 首遍解析头 → 按路由判定 streamBody → 命中即移交 / 未命中 `_parseHeadless` 补读。非 streamBody 路径多一次头区"重解析"（buf 索引已在头区后，`_parseHeadless` 只做 body 三态，不重复 IO）——比"回滚 buf 索引重跑全量 _parse"简单且零成本，语义与 v1 完全一致。
3. **streamBody + maxUploadBytes 的耦合**：流式 multipart（boundary 跨块）v1 不做流式解析（§6.6 既定），`HttpBodyReader` 上限对 multipart Content-Type 自动放宽到 `maxUploadBytes`——handler 拿到原始流自行处理 boundary；`UploadedFile` 全内存形态与流式形态并行（设计原文照办）。
4. **Front 已知坑两条（新踩）**：① **下标访问禁用算术表达式**（`segs[n-1]` 报 21340 无行号——变量下标走 `GetMetaVariableByName` 快路、算术下标走 `_getItem_` 探测路径失败；P1~P4.5 代码从未用过此形态；拆局部 `Int32 last = n - 1` 规避）；② **`null` 检查后 `&&` 链式成员访问触发 File 层 NRE**（`back != null && back.subject == ...`——既有坑的新形态，P5 测试重踩；if 块内先取局部再判）。
5. **旧包 cvm 的静默陷阱**：宿主测试跑在 `package\win32-debug`（内嵌 cvm 快照），改 C VM 后必须刷新包内 `bin\`——本次 SHA256 符号缺失即此因（systemCalls 未注册 → 返回 0 → SL 抛错未捕获 → 主协程静默终止且 exit 0）。`release-local.ps1` 全链已内建该刷新，手工改 VM 时需单独拷贝。
6. **R7 第四处（C# `Define.cs`）查证免登记**：`ESystemMethodCall` 枚举已非按名消费通道（SystemSha1 2026-10 先例即无枚举条目）；`systemCalls` 经模块 "systemCalls" export → `vm_sysfunc_resolve_symbol` dlsym 按名解析。R7 文案后续维护时可将第四处标注为"按名解析通道免登记"。
7. **`jsonOk(纯数字串)` 序列化为数字**（`"300"` → `"data":300`）：`BaseJson.fromData` 对纯数字字符串按数值输出，既有语义非 P5 引入——测试断言按数字形态收口。

**下一步（P6+ 展望）**：TLS 服务端（评估已毕，待部署需求触发）/ ~~multipart 流式解析（boundary 跨块匹配）~~（**P7 已落地**，§24）/ 控制器池化与单例选项（风险 #17）/ 完整 Swagger UI 静态包（风险 #8）/ ~~BenchMark 压测矩阵~~（**P8 已落地**，§25——M1/M2 矩阵与实测数据）。

---

## §21 HttpServer / WebSocketServer 类拆分实录（2026-10-26，用户点名重构）

**背景**：用户点名——`SLang.Server` 一类承载 HTTP 与 WebSocket 双协议职责过宽，按协议拆为两类：`SLang.HttpServer`（仅 HTTP）与 `SLang.WebSocketServer`（WS 独立门面），HTTP 与 WebSocket 各一类、职责单一。

**产物**：

- `Server.sl`：`Server` 类改名 `HttpServer`（HTTP 门面，构造缺省 80 端口）；WS 四方法（`websocket/wsEvents/sessions/broadcast`）从门面迁出；L149-152 类头注记保留历史形态说明（P0–P4 曾以 `SLang.Server.configure` 静态形态落地，§19）。
- `WebSocketServer.sl`：静态引擎形态 → **实例双形态门面**——形态 A（构造不传端口 = 升级路由器，`websocket( path, fn ) → RouteInfo` / `wsEvents( path ) → WsEventBuilder` / `sessions( path )` / `broadcast( path, text ) → Int32`）+ 形态 B（构造传端口 = 独立端口服务器，`onMessage( fn )/onClose( fn )` / `run( port )/start()/stop()/awaitStop()` / `sessions()` / `broadcast( text ) → Int32`）；`idleTimeout( ms )` P5 WS 空闲心跳写口（写 `WebSocketServer._idleTimeoutMs` + 若 `HttpServerCore._cfg != null` 同步 `cfg.wsIdleTimeoutMs`；**形态 A 时序 = 先构造 HttpServer 再调用**）；`WsEventBuilder` 链式事件糖保留。
- `Server.jsonc`：struct 登记同步（37 项——`Server` → `HttpServer`，增 `WsEventBuilder/HttpBodyReader` 等）。
- 六个测试文件批量改写（Probe/Core/P1/P1.5/P2/P3/P4/P4.5/P5 的 `SLang.Server` → `SLang.HttpServer`，WS API 调用挂 `WebSocketServer` 实例）；库注释 9 处清理。
- 文档同步（R14）：`md/lib/Server.md` 全文重写（361 → 419 行 + WsCloseInfo 三字段补全）；本文档 §0–§5 现行设计章节同步（§12–§20 历史实录保持原样）。

**验收**：✅ SLangServer 库重编通过；ServerTest 全量回归 **178/178 OK**（Probe 11 + Core 12 + P1 43 + P1.5 8 + P2 21 + P3 31 + P4 13 + P4.5 11 + P5 28）；R17 收尾——`package\win32-debug` cvm 产物 `--clean-first` 全量重编至 0.0.38 并刷新 `bin\` 三产物，**回归复跑仍 178/178 OK**，两处 CLI（`slang.exe version` / `bin\csimple_lang.exe version`）版本一致（vsix 待 release-local.ps1 发布时刷新）。

**与设计的偏差 / 实况要点**：

1. **`ServerPlugin.onInstall()` 维持无参**（设计稿曾为 `onInstall( SLang.Server app )` 传门面）：SL 闭包零捕获纪律下插件内无法引用实例——注册走引擎级形态 `SLang.HttpServerCore.use( ... )`（与 `app.use(...)` 语义等价，v1 单 VM 单服务器语义）。
2. **`s.tag(...)`/`s.tagged(...)` 会话标签未实现**（设计项，定向广播 P6+ 评估）。→ **P6 已落地**（`tag/untag/tagged/tags` + `broadcastTag` 全家族，§23）。
3. **形态 B 回调注册为方法调用而非字段赋值**（`wss.onMessage( fn )`），且**形态 B 无 onOpen 注册**（onOpen 仅在 WsEventBuilder 链上）；无无参 `run()`（仅 `run( port )` / `start()`）。
4. **`broadcast` 仅文本重载**（→ Int32 送达数）——binary( ByteBuffer ) 重载未落地。→ **P6 已落地**（broadcast/broadcastTag 全家族各带二进制重载，§23）。
5. **`ServerConfig.showBanner` 未实现**（已从 §4.9 移除）；**app 级事件钩子 `onStart/onStop/onError` 未实现**（§4.9 已标注设计预留——生命周期钩子现仅有插件级 `ServerPlugin.onStart/onStop`）。→ 钩子三项 **P6 已落地**（字段赋值形态 set/get 访问器，§23；showBanner 维持移除状态不变）。
6. **构建基建坑（R17 收尾时发现）：Ninja 头依赖追踪失效——版本 bump 必须全量重编**：0.0.37→0.0.38 只改 `cli_version.h` 后，增量构建产出"缝合怪"二进制（exe banner 0.0.31 / `version` 命令 0.0.34，新旧混体）。根因：中文版 MSVC `/showIncludes` 输出前缀「注意： 包含文件：」未被 CMake/Ninja deps 过滤器识别（该行直接透传 stdout 即证据），`.ninja_deps` 不记头依赖 → **只改头文件永不触发重编**（touch `cli_version.h` 后增量构建实测 "no work to do"，对象 mtime 不变），只改 .c 才会重编。实验：设 `VSLANG=1033` 后 clean 重编日志仍为中文前缀、touch 测试仍失效——VSLANG 改不了 cl.exe 输出语言，**不进 common.ps1**。定案纪律：**版本 bump 后用 `cmake --build csimple_lang\build\Debug --clean-first -j 8` 全量重编**（629 步），再按 §20 偏差 ⑤ 把 `build\Debug\bin\` 三产物（`csimple_lang.exe` / `csimple_lang_dll.dll` / `csimple_lang_dll.pdb`）拷进 `package\win32-debug\bin\`；已同步进 PROJECTS.md §7 操作规则第 5 条。

**下一步（P6+ 展望）**：~~`s.tag/s.tagged` 定向广播 / `broadcast` binary 重载 / app 级事件钩子~~——三项均已随 **P6** 落地（§23）；~~multipart 流式解析~~已随 **P7** 落地（§24）；~~BenchMark 压测矩阵~~已随 **P8** 落地（§25）；剩余展望（TLS 服务端 / 控制器池化与单例选项 / 完整 Swagger UI 静态包）。

---

## §22 实参位置内联闭包编译器增强实录（2026-10-26，示例驱动，0.0.39）

**背景**：用户点名——`md/lib/Server.md` 示例区补写 `app.onPost( "xxx", function( Request req, Response res ) {...} )` 内联直传示例与 handler 内 await 示例。考据发现既有快速开始/路由两处示例（§0 时代即写入）正是实参位置内联闭包形态，而该形态编译器**不支持**（无任何拦截器认领，落普通表达式解析报 49 错）——属历史坏示例。用户拍板：**增强编译器支持该形态**（参照 `Isolate.run/spawn` 的闭包提升机制通用化到任意调用实参）。

**产物**（Front `StructParseToSyntax.cs`，零运行时改动，纯 Parse 层）：

- 新增通用变换器 `TransformInlineClosureArgNodes`（插在 `LiftIsolateClosure` 之后）：任意调用的实参段恰为 `[function 关键字, Par, Brace]` 三件套时，提升为具名闭包 `inlineClosureTmpN`（`AddParseSyntaxNodeInfo` 先于调用语句发射），原实参位置替换为名字引用节点；实参切段复用 `SplitIsolateArgSegments`，下钻规则与 `TransformIsolateCallNodes` 同构（Brace 跳过防双重处理 / parNode.childList / IdentifierLink 链扩展 DigLink / bracketNodeList）。
- 挂点双处（与 Isolate 变换器一一对应）：语句级（`TransformIsolateCallNodes` 之后）+ `ret`/`Transience` 表达式分支；`await/spawn` 专属糖在前级 `TransformCoroutineKeywordNodes` 已消化，本变换器兜底通用调用。
- 约束（编译错误拦截）：仅方法体内可用（需语句发射环境）；闭包体内禁用（闭包嵌套定义不支持，`m_ClosureBodyDepth` 防护）；`function( 参数 ) { 体 }` 必须单独作为一项实参。无匹配时零副作用（`GetInlineClosureSegKind` 全 0 直接 return 不动节点）。

**验收**：✅ 冒烟工程 `test/Other/ServerTest/_docsmoke/`（临时，验证后删除）A 系 7 例——A1 表单登录+缺字段 jsonFail / A2 DTO 201 / A3 path+query / A4 delay 挂起 / A5 直接 await 糖 / A6 void await / A7 Task 透传（httpGetAsync）全 OK；B 系 3 例——B1 `await spawn function(){...} as Int32` / B2 `await spawn 裸方法` / B3 两步并发（`Task t = spawn f()` + `await t as Int32`）全 OK（**`await spawn` 组合形态此前全仓零测试覆盖**，本例补齐）。全量回归见 §21 验收口径（178/178 + 版本锚点 0.0.39）。

**文档同步（R14）**：`md/lib/Server.md` 新增「内联 function 直传注册」「handler 内 await」两节（示例逐字取自冒烟验证通过的形态）；`md/syntax/function.md` 基本语法补实参位置内联闭包条目。

## §23 P6 落地实录（2026-10-26，app 级钩子 + WS 标签定向广播 + broadcast 二进制，0.0.40）

**背景**：用户指令「继续实现 未完成的 httpserver 的功能吧」——落地 §21 展望清单剩余三项设计预留：偏差② `s.tag/s.tagged` 会话标签 + `broadcastTag` 定向广播、偏差④ `broadcast` binary( ByteBuffer ) 重载、偏差⑤ app 级事件钩子 `onStart/onStop/onError`（§4.9 设计预留）。三项合并为 **P6** 一次交付。

**产物**（纯 SL 库层，零引擎改动）：

- `HttpServerCore.sl`：三钩子静态 `Function _hookOnStart/_hookOnStop/_hookOnError`（L89-94）；触发接线三处——`start` 末尾 onStart（L268，先拷局部 + null 守卫 + 异常吞）、`stop` 收尾 onStop（L307，同款）、管道 catch onError（L582：handler/中间件异常兜底，钩子内可写响应自救、未写则 500 ApiResult 兜底）；`reset` 清三钩子；引擎级静态通道 broadcast 文本/二进制 + broadcastTag 文本/二进制四转发（L187-208）。
- `WebSocketServer.sl`：`_WsSessions` 静态登记表扩标签族——`broadcast`(L127) / `broadcastBinary`(L146) / `broadcastTag`(L165) / `broadcastTagBinary`(L192) / `tagSession`(L223) / `untagSession`(L245)；`WsSession` 新增 `List<string> _tags` 字段（L332）+ 门面 `tag/untag/tagged/tags`（L472-494，`tags` 返回快照防外部篡改）；实例门面全家族 12 方法 = 两形态（组播 pattern / 实例自路径）× 文本/二进制 × 全量/定向（L645-653 / L778-786 等），全返回 Int32 送达数。
- `Server.sl`：`HttpServer` 六访问器 set/get × onStart/onStop/onError（L268-296，转发 HttpServerCore 静态——SL 字段不能存 Function，访问器中转）。
- `test/Other/ServerTest/ServerP6Test.sl`（497 行）：T1 钩子 7 断言（onStart/onStop 各一次、onError 自救 599、异常路径+错误对象可见、正常路由不受扰、静默钩子 500 兜底双触发）；T2 WS 标签 8 断言（两客户端上线、handler 内消息驱动打标 `login:vip`、broadcastTag 定向送达非目标零泄漏）；T3 形态 B 5 断言（`WebSocketServer` 实例直用，broadcastTag/broadcast 二进制）；辅助件：手搓 `P6WsClient`（raw socket + WS 帧编解码）+ `blowUp()`/`binOf()`。`ServerTest.sp` / `ServerTest.jsonc` 注册。

**验收**：✅ ServerTest **198/198**（178 既有 + 20 P6）；R17 版本 bump **0.0.40**（7 锚点：`cli_version.h` PATCH+STRING / `CommandExecutor.cs` / `CMakeLists` / vcxproj PostBuildEvent / csproj / package.json / package-lock.json）；C VM clean-first 重编 **629/629**，产物入 `version_0.0.40/`。**T4g `cfg secret + MissingJwtSecret` 首跑偶发 FAIL（197/198）**——初判 flaky 留档后复跑复发（~3/5 失败率），插桩裁决实锤根因（推翻 flaky 定案）：verify 签名段解码走 `Base64.decodeString`，其内嵌 NUL 截断语义在 HMAC-SHA256 值域含 0x00 时截断签名（单 token 概率 1-(255/256)³² ≈ 11.8%）→ 签名失配概率性验签失败（同轮 token 相同 → 轮内恒定；exp 变化 HMAC 重掷 → 轮盘随机）。修复 = verify dv 段改二进制安全链 `ByteBuffer.fromString + Base64.decode(ByteBuffer)`（全程字节句柄不经字符串化，NUL 截断从类型上消除）；T4g 同步强化为回归防线——20 rep × 独立 jti = 20 个独立 HMAC 样本，解码层回归 ~92% 概率当场抓获。修复后 8 轮 + 插桩回改后 3 轮均全绿 198/198。

**实况要点（SL 约束规避姿势，后续迭代参照）**：

1. 字段赋值右侧不能直接写闭包字面量 → 先存局部变量再赋值：`function hOnStart = function(){...}` → `app.onStart = hOnStart`（§4.9 示例已按此形态改写）。
2. 合成闭包无 throws 声明、闭包体内不能直接 throw → 经 `static void blowUp() throws` 方法传播（onError 测试异常源）。
3. 跨模块点分类型不能作泛型参数（`List<SLang.WsSession>` 触发 Front NRE，HttpServerCore.sl L79 权威注记）→ 测试观测槽改静态字段 + `List<string>`（内建类型参数安全）+ 链式 `sessions(...).length`。
4. `Error` 不能作静态方法形参类型 → onError 回调 `function(req,res,e)` 只能以 Function 动态调用、catch 绑定变量直传 `hErr( req, res, e )`。
5. 闭包零捕获 → 观测值经静态字段回传；闭包体内引用静态须类名限定（`ServerP6Test._evtStart`）。
6. WS 验收三手法：**首帧探测法**（静默客户端零驱动即零收帧、首帧必是自己的 echo——若定向广播泄漏则首帧为泄漏帧）；**消息驱动登记**（协程调度序无契约，连接序登记不可依赖）；`Coroutine.delay(100)` 时序屏障。
7. 环境记录：`Enter-VsDevShell` 非直接可调 cmdlet——须先 `Import-Module "...\Common7\Tools\Microsoft.VisualStudio.DevShell.dll"` 再进 shell，否则 cl.exe 缺 INCLUDE/LIB 报 C1083；版本 bump 后 Ninja 头依赖失效（中文 MSVC 路径）→ 必须 `--clean-first`。

**文档同步（R14）**：`md/lib/Server.md` 四处——验收清单追加 ServerP6Test、WsSession 表补 `tag/untag/tagged/tags` 行、新增「广播与标签（P6）」小节（全家族 8 形态示例 + handler 内打标典型用法）、新增「app 级事件钩子（P6）」小节（三钩子示例 + 触发时序 + `reset()` 注释翻转）；本文 §1 G2 / §4.6 / §4.9 / §21 偏差②④⑤ / §21 展望清单同步翻转至 P6 已落地。

---

## §24 P7 落地实录（2026-10-26，multipart 流式解析 MultipartReader）

**背景**：用户指令「后边还有没实现的 http server 的设计吗？ 如果有，则继续实现」——展望清单查证（§20/§21 剩余四项）：TLS 服务端（维持留待部署需求触发）、multipart 流式解析、控制器池化与单例选项（风险 #17）、BenchMark 压测矩阵。裁决本轮 **P7 = multipart 流式解析**（§6.6 既定进阶项、风险 #4 的根治路径；池化涉语义变更待单独立项，压测依赖量化基线，TLS 按既定决策留待）。

**产物**：

- **`MultipartReader.sl`**（新文件，487 行）：
  - `MultipartPart`：元数据 `field`（字段名）/ `filename`（null = 普通字段，已剥路径）/ `contentType` / `isFile`；内容三形态——`read( ByteBuffer dst ) → Int32`（0 = 本 part 结束；句柄过期即 nextPart 推进后恒 0）、`readAll() → ByteBuffer`（新建归调用方，用后可 release）、`saveAs( path ) → bool`（**非 throws**：内部 label/catch 包 FileStream Create + flush + close，失败返 false 不炸 handler）；
  - `MultipartReader` 五状态机（0 找首 boundary / 1 part 头区 / 2 内容区 / 3 找次 boundary / 4 done）：`static of( reader, contentType )` 工厂——CT 非 multipart / boundary 参数缺失 → **返 null 且不读流**；`nextPart() → MultipartPart | null`——自动排干未读完的当前 part（`_drainContent`）、preamble 行容忍（state 0 非 boundary 行无状态转移继续循环）、终界 `--suffix--` → state 4 返 null；`isDone`（`_state == 4`）；boundary 跨块鲁棒——`\r\n--boundary` 匹配在缓冲边界处按需补读（`_fill`）完成，不受 TCP 分帧切分影响。
- **`Request.sl`**：`_streamReader` / `_mpReader` 缓存字段；`bodyStream()` 改**双形态缓存化**（同一请求恒返同一 `HttpBodyReader`——引擎收尾与 handler 共享消费进度）；`multipartStream()`——流式路由且 CT 合法 → `MultipartReader.of( 缓存 bodyStream, ct )` 并缓存返出，否则返 null（非流式路由用 form/file 内存族；boundary 缺失交 handler 裁决）。
- **`HttpServerCore.sl`** 引擎两处：
  - **4a 段流式豁免**（§6.5 构造期 multipart 即时解析）：条件改 `req.isStreamBody == false && req.bodyFormat == EBodyFormat.Multipart`。根因：`BodyParser.detect` 纯 Content-Type 基（multipart 判定与 bodyLen 无关）→ 流式路由 `_body == null` 时 bodyFormat 仍为 Multipart；而 `parseMultipart` 在 **boundary 缺失时先于 null-body 守卫即抛 400**（先查 boundary 后查 body）→ boundary 缺失的流式 multipart 请求会在 handler 前被引擎 400 误伤，剥夺 handler 经 `multipartStream()` 返 null 自行裁决的选择权；且流式路由 body 不驻留、`_ensureMultipart` 空转（form/file 恒空）——该分支唯一可观察效果是误伤，故跳过。
  - **6a 收尾段窥视式 multipart 排干**：`MultipartReader mpDrain = req._mpReader` **窥视缓存**（不调 `multipartStream()`——其内部 `bodyStream()` 缓存路径虽安全，但语义边界在"引擎不替 handler 决定 multipart 有效性"）→ 非 null → `_drainTail()` 以 multipart 语义排干剩余 part（解析器预读窗口闭环，防底层 drainer 按 CL 余量排干时跳过预读数据错吃下一请求字节）→ 后续沿用 P5 缓存 drainer 排 CL 余量；失败/超限 → gracefulClose 断连止损。
- **`Server.jsonc`**：compileFiles 登记 `MultipartReader.sl`（16 → 17 文件）。
- **`ServerP7Test.sl`**（~800 行，15 检查；19471-19472 双端口）+ `ServerTest.sp` / `ServerTest.jsonc` 注册：T1 基本读写（缓存单实例 / 字段 + 文件 / 2 parts + isDone）；T2 `saveAs` 300KB 落盘（size + head/mid/tail 三窗口字节校验）；T3 boundary 跨 TCP 分帧（手搓 `P7RawClient` 5 段确定性投递，切点落在 boundary 内部）；T4 空 multipart（仅终界）/ preamble 容忍；T5 混合语义（非流式路由 mp=null + form 正常 / 非 multipart CT 回落 bodyStream / boundary 缺失返 null 且同连接 keep-alive 存活——引擎 4a 豁免的回归防线）；T6 非流式路由 form/file 内存语义回归；T7 半读收尾（multipart 文件 part 读 100/5000 后 **break** + raw 流读 100/300 后返回 → 引擎排干 + 同连接 keep-alive 存活——定向验证 6a 闭环）。

**验收**：✅ ServerTest **213/213**（198 既有 + 15 P7），exit 0。

**实况要点**：

1. **P5 缺陷顺带根治（drainer 多吃错位）**：P5 引擎 6a 收尾每次新造 `HttpBodyReader`，CL 余量按完整 CL 重新起算 → handler 已消费字节被 drainer 重复排干（多吃）→ 下一请求解析错位风险。P7 将 `bodyStream()` 缓存化（单实例共享 `_remain`/`_total` 进度）+ 6a 经缓存实例排干——缺陷从构造上消除（T7a/T7b 双路回归覆盖）。
2. **`nextPart()` 自动排干当前 part**：handler 对文件 part 半读后 `break`（不再迭代）才能让引擎 `_drainTail` 有活可干——T7a 即按此定向设计；若迭代到底（nextPart 返 null）则引擎收尾只剩 CL 余量排空。
3. **流式判定与 CT 判定正交**：`bodyFormat` 是纯 Content-Type 判定（流式路由 `_body == null` 时仍为 Multipart）——是否流式由 `isStreamBody` 决定；故 4a 豁免条件必须双因子（非流式 && Multipart），单看 bodyFormat 会误伤流式路由。
4. **测试客户端形态**：P5 `P5RawClient` 复制为 `P7RawClient`（connect / 分段 send / readLine / readN / readResp / close）——raw socket 确定性分段投递是分帧鲁棒性测试（T3）的可靠手段。
5. **SL 约束规避（沿 P5/P6 姿势）**：助手以类名限定静态复用（`ServerP7Test.sfFind` 等）；闭包零捕获 → 观测经静态字段回传；非 throws 方法可直接调用 throws 方法（P5 `rawReq` 先例）；`readAll()` 归调用方 → 用后 release 防泄漏纪律进测试。

**文档同步（R14）**：`md/lib/Server.md` P5 流式上传节后新增「multipart 流式解析（P7）」节（示例取自 T1 已验证形态）；本文 §6.6 标题与请求侧小节翻转 + §10 风险 #4 对策更新 + §20/§21 展望清单翻转。

**下一步（P8 候选）**：控制器池化与单例选项（风险 #17，涉语义变更）/ ~~BenchMark 压测矩阵~~（**P8 已落地**，§25）/ 完整 Swagger UI 静态包（风险 #8）/ TLS 服务端（留待部署需求触发）。

---

## §25 P8 落地实录（2026-10-26，BenchMark 压测矩阵量化流式收益）

**背景**：用户指令「生成 BenchMark 压测矩阵以量化流式收益」——P5（请求侧流式）与 P7（multipart 流式解析）相继落地后，流式收益一直停留在定性论证（「不驻留全量 body」）；P8 以可复现基准补上量化基线，兑现 §20 展望中自 P5 起延后的「基准+压测」验收项。

**产物**（纯测试侧，零库/引擎改动）：

- **`test/Other/ServerTest/ServerBench.sl`**（751 行）+ `ServerTest.sp` / `ServerTest.jsonc` 注册（213 → 223 检查）。
- **矩阵设计（维度 × 指标）**：
  - **M1 上传解析矩阵**（端口 19481）：`{stream, memory} × {64KB, 512KB, 2MB, 8MB}` 共 8 格；指标 = 耗时 ms（min-of-3）/ 吞吐 MB/s / SL 堆分配计数增量。两路由 handler 语义对称（文件均落盘为同尺寸文件），唯一变量 = 引擎解析路径——stream 路由 `/bench/stream`（`rStream.streamBody = true`；handler 经 `req.multipartStream()` 逐 `nextPart()`，文件 part `saveAs("bench_stream.bin")`、字段 part `readAll()+release`，回 `sv=1`）；memory 路由 `/bench/memory`（引擎 4a 预解析；handler 经 `req.form("note")` + `req.file("blob")` 落盘 `bench_mem.bin`，回 `u=bench|sz=<size>|sv=1`）。
  - **M2 连接矩阵**（端口 19482）：`{keepalive, close} × 100 req` `GET /probe`（极小响应体）；指标 = 总耗时 / req-per-s / us-per-req。keepalive = 同连接循环 n 次；close = 每请求新建连接（请求头带 `Connection: close`）；10 次同连接预热在前。
- **计量纪律**：计时 3 次取最小——请求 buffer 深拷贝在计时窗外，窗 = connect→全量发送→读完整响应；每轮 `Memory.collect()` 摊平跨轮残留后以 `Memory.totalAllocated()` / `OS.Timer.clock()` 差值计；预热轮（不计时）兼正确性验证——响应内容 + 落盘尺寸 == size + 净荷头/中/尾三窗口各 16 字节校验（`dataWindowOk`，净荷 = "0123456789" 循环可预测）。**基准与回归合一**：模块自带 10 项 check（8 × 「M1 \<mode\> \<档位\> respond+save ok」+「M1 timed runs all ok」+「M2 200 responses ok」）。
- **辅助件**：`BenchRawClient`（raw socket：connect / send / sendBuf / readLine / readN / readResp / close——沿 P5/P7 确定性投递姿势）+ `BenchResp` 应答结构；multipart 拼装 `mpField/mpFile/mpFinish`（boundary=BNC，头+body 拼单 buffer 单次 write）；格式化 `fmtMbps`（`sizeBytes * 10000L / ( dms * 1048576L )` 定点 1 位小数）/ `fmtRps`（`n * 1000L / dms`）/ `fmtUspr`（`ms * 1000 / n`）；单格结果经静态字段 `gMinMs/gMinAlloc/gAllocValid/gAllOk` 回传（闭包零捕获约束，沿 P6/P7 姿势）。

**实测数据**（2026-10-26，win32-debug C VM，同机同进程；ratio 方向 = memory/stream）：

M1 上传矩阵（min-of-3；alloc = SL 堆分配计数增量）：

| 档位 | stream：ms / MB/s / alloc | memory：ms / MB/s / alloc | 时间比 | alloc 比 |
|---|---|---|---|---|
| 64KB | 18 / 3.4 / +136 | 20 / 3.1 / +143 | 1.1x | 1.0x |
| 512KB | 45 / 11.1 / +150 | 47 / 10.6 / +143 | 1.0x | 0.9x |
| 2MB | 142 / 14.0 / +196 | 136 / 14.7 / +143 | 0.9x | 0.7x |
| 8MB | 533 / 15.0 / +376 | 487 / 16.4 / +143 | 0.9x | 0.3x |

M2 连接矩阵（100 req）：

| 模式 | 总耗时 | 吞吐 | 单请求 |
|---|---|---|---|
| keepalive | 646ms | 154 req/s | 6460 us/req |
| close | 829ms | 120 req/s | 8290 us/req |

keepalive vs close：**时间 -22%（646 vs 829ms）、吞吐 +28%（154 vs 120 req/s）**——无 TLS 下纯 TCP 连接建立/拆除成本的直接实证，叠加 TLS 后该差距将进一步放大。

**数据解读（诚实口径）**：

1. **SL 堆分配计数是内存收益的下界证据而非全貌**：`Memory.totalAllocated()` 度量 SL 堆对象分配（客户端+服务端同进程活动的合计差值），**不含 ByteBuffer/native 内存**——两模式 body 字节均驻留 ByteBuffer，故「流式不驻留全量 body」的核心收益（native 内存峰值 O(块) vs O(body)）不在该计数器可见范围。可见部分：memory 模式 alloc 恒 +143（4a 预解析的 SL 侧对象开销为常数，body 字节不经 SL 堆）；stream 模式 136→376 随档位缓增（`MultipartPart` 与读块对象按 part 生命周期分配）。8MB 档 alloc 比 0.3x 的方向由此而来，但绝对量级小（均为百级计数）。
2. **时间维度**：小档 stream 占优（64KB 快 10%、512KB 快 4%），大档 stream 落后（2MB 慢 4%、8MB 慢 9%）——交叉点在 512KB-2MB 之间，流式的时间代价上限 ~9%（8MB 档，分块流式状态机的解析开销 vs 整块扫描；小档反超因 4a 预解析构造 UploadedFile 的固定开销在小 body 下占比更高）。
3. **吞吐绝对值**（3.4-16.4MB/s）为 debug 构建的保守值；流式的主收益维度（release 构建 + 32MB+ 档的 native 内存峰值对比）留待基准扩展。

**验收**：✅ ServerTest **223/223**（213 既有 + 10 ServerBench），exit 0；R18 版本 bump **0.0.42**（锚点沿 R17 七处 + PROJECTS.md 版本总表：`cli_version.h` PATCH+STRING / `CommandExecutor.cs` / 根 CMakeLists `SLVM_VERSION_DIR` / vcxproj PostBuildEvent / `project\cmake\CMakeLists.txt` / `SlangAllInOne.csproj` / package.json + package-lock.json）。

**实况要点**：

1. **局部变量命名必须避开关键字表**：初版 `string tr` / `string label` 分别撞 `ETokenType.Transience` 与 `ETokenType.Label`（`label cl { } catch { }` 语法字）——`tr = ...` 语句起始在词法层即切为关键字 Token（LexerParseToToken.cs L2412 关键字 switch），派发 `MetaTRStatements` 后表达式以 `=` 开头无法建树 → Front NRE（`MetaCoreParseFileExpressFailed root is Null`）。修复 = `tr`→`tRatio`、`label`→`lbl`（`ar` 经词法表证实安全保留）。教训：SLang 局部变量命名先查 LexerParseToToken.cs L2181-2505 关键字 switch（tr/label 均无局部变量先例）。
2. **先例检索判定语法合法性**：`( tr10 / 10 ).toString()` 曾疑需重构，经 NaNBench.sl L30 `( 9223372036854775807L - 1L ).toString()` 直接先例证实合法——省掉 3 处表达式重构；`10L/10000L` 字面量后缀同有先例（EqBench / QuickSort / NumberTest）。
3. **alloc 计数器防御**：`bestAlloc < 0` → 显示 "wrap"、ratio 显示 "n/a"（计数器回绕出口，本次实测未触发）。
4. **基准与回归合一**：预热轮兼正确性验证（respond + save + 三窗口字节校验），压测模块本身就是 10 项回归防线——不为基准另写第二套正确性代码。

**文档同步（R14）**：本次纯测试侧产物、无库 API 变更，`md/lib/Server.md` 不动；本文 §20/§21/§24 展望清单的 BenchMark 项翻转（已落地，§25）；§10 风险 #17 的「BenchMark 压测验证」缓解维持，待池化立项后直接复用本矩阵。

**下一步（P9 候选）**：控制器池化与单例选项（风险 #17，涉语义变更——落地后复用 ServerBench 矩阵量化池化收益）/ 完整 Swagger UI 静态包（风险 #8）/ TLS 服务端（留待部署需求触发）/ 基准扩展（release 构建 + 32MB+ 档 + 并发客户端维度，量化 native 内存峰值——流式的主收益证据）。

---

## §26 P9 落地实录（2026-10-26，@Singleton 单例控制器 + attribute 形态 3 重构）

P9 以两项交付收官（同日连续落地，全量回归 234 OK / 0 FAIL）：

### 26.1 @Singleton 单例控制器（§4.10 默认每请求一实例之上的显式 opt-in）

- **语义**：类级 `@Singleton`（与 `@OnRoute` 可叠加）→ 装配期构造单实例（`hostClassNew()`），该类**全部方法路由**绑同一实例（`hostMethodRefOf(单实例)`，绑定实例 method-ref）；跨 handler 状态共享（T1e：POST reset 改写 → GET counter 读到归零后重计）。默认语义不变：无标注 = 每请求一实例（LATE 闭包，T1f/T1g 对照组恒 hits=1）。**单例作用域 = 注册中心键（宿主类短名，进程级）**——非"每 app 一单例"（Spring per-ApplicationContext 对照语义已在形态 3 下消解为注册中心单一权威）；SLang 事件循环单线程派发，无并发竞争。
- **池化裁决（拒绝）**：SLang 无字段枚举/无运行时反射 → 池无法重置实例字段 → 池化仅对无状态控制器安全；无状态场景下单例（1 实例）严格优于池（N 实例）——池化不立项，单例覆盖全部合法用例。

### 26.2 attribute 形态 3 重构（§7 现行方案，P4 原生收集通道整体退役）

按用户指令把 attribute 处理统一为四形态模型（编译中 / IR 导出 / **runtime 装载** / 执行期）：**VM 零 per-attribute C99 代码，逻辑全部写在各 Attribute 子类的 `_enter_` 里经通用调用机制执行**。形态 3 通道 + Core.Attribute 三宿主接口 + `HttpServer.shared()` 注册中心三项机制落地后，`@On*` 十一族全部改为 `_enter_` 自注册；`vm_route_attribute.c`（10 个 C 收集 handler）与 `server_system_method.c`（`SystemServerRoute*` 三系统方法）**整体删除**。派发路径零特判：单例路由 = 既有 bound method-ref 分支，非单例 = 既有 LATE 闭包分支。

### 26.3 调试复盘（两项机制级发现，均已治本）

1. **无帧 armed 入口与 native 子帧执行的坠入问题**：触发通道最初挂载 `cli_command.c`（vm_initialize 之后、scheduler 之前），此时入口字节码已武装但无帧——`vm_execute_method_by_id` 的子帧弹空后解释器**直接流入入口代码**，19 个 attribute 的 `_enter_` 执行与入口测试交错（现象：usePreloadRoutes 读到 null、Probe B1-B6 await 探针被啃出 no-coroutine-context）。正解 = 挂载 `vm_scheduler_enter` 根帧建立后（子帧 barrier 落根帧，弹回即停）。**教训：native 再入执行不可依赖"主循环尚未起跑"，必须确认帧链边界。**
2. **Front 跨模块 override 吞方法（误诊，2026-10-26 撤销）**：复核定案为误诊——override 重写导出正常（OnGet 最小复现槽位与指令体俱全）；真因是当时 Server.sl 编译错误（`Map.put`/索引左值）致方法链解析失败连带方法被丢。RouteAttrs 已全量恢复 override 并重导回归全绿（见 §7 误诊更正）。
3. **SL 语法踩坑（历史纪律新增）**：`default` 是关键字（方法名 `default()` 编译失败 → 改 `shared()`）；单行 if 连排需空行分隔；`Map` 无 `put`（用 `add(key,value)` 或索引写）；索引表达式不能直接作二元运算左值/实参（先落局部变量再使用）。

### 26.4 量化与验收

- **ServerP9Test 11 条全绿**：T1a 装配条数 ≥10 / T1b-T1e 单例四态（首请求、跨请求共享、字段改写、reset 后重计）/ T1f-T1g 每请求一实例对照 / T2 pre-reset + 异步单例两连击（协程 delay 内 bound method-ref 派发正常）。
- **ServerBench M3 控制器实例矩阵**（4 字段控制器 200 req keepalive）：singleton 68B/req vs fresh 69B/req——微响应场景实例化开销占比极小（实测印证 §10 风险 #17 的量级评估：控制器实例化非热点，单例价值在**状态共享语义**而非吞吐）；400 响应全对。
- **回归**：ServerTest 全量 234 OK / 0 FAIL（基线 223 + P9 新增 11）；ExpendTest 抽查全绿（AttributeRuntimeTest P7 机制无回归）。
- **版本**：0.0.43（R17/R18 四端七锚点 + C VM --clean-first 全量重编 + win32-debug 包刷新，hash 校验一致）。

**下一步（v1 收官候选）**：~~完整 Swagger UI 静态包（风险 #8）~~（**已随 SwaggerUI 插件落地**，§27）/ TLS 服务端（留待部署需求触发）/ 基准扩展（release 构建 + 并发客户端维度）/ ~~Front 跨模块 override 修复（26.3-2）后 RouteAttrs 恢复 override 关键字~~（**误诊撤销 + RouteAttrs 已全量恢复 override**，26.3-2）。

---

## §27 SwaggerUI 插件落地实录（2026-10-26，v1 收官 f4 · §10 风险 #8 闭环）

v1 收官候选清单末项：`SLang.Plugins.swaggerUI( distDir )` 内置插件，`docs` 自研只读文档（§4.8）之上的**完整 Swagger UI 交互调试台**。

### 27.1 设计（staticFiles 纪律复用 + /docs 同款让位）

- **双路由接管**：`GET /swagger` → 自研 index 页（外链 `dist` 资产 + `/openapi.json`，零自包含——bundle.js 1.68MB / swagger-ui.css 187KB 官方 dist 真实文件）；`GET /swagger/<file>` → dist 目录文件直出。
- **staticFiles 同款纪律**：仅 GET 直出；`'..'` 独立段 403；dist 未命中 → `nx.go()` 放行（尾环 404，不误吞其他路由）；`res.sendFileRange` 流式直出（MIME 随扩展名 + Range 断点续传透传）。
- **让位时序（与 /docs 的差异点）**：中间件先于路由执行，且用户可在插件安装后才注册路由 → 让位检查在 `_serve` **运行期**做 `Router.findExact( "GET", "/swagger" ) != null` → `nx.go()`（非 mount 期一次性检查）。
- **闭包零捕获**：dist 目录经静态字段 `_dist` 传递（v1 单实例，重复注册后者覆盖——与 staticFiles/_StaticFilesPlugin 同款纪律）。
- **SwaggerUIBundle 配置裁剪**：`presets:[...apis]` + `layout:"BaseLayout"`——官方 `swagger-ui-dist@5` 的 StandaloneLayout/DownloadUrl 会引用 `swagger-ui-standalone-preset.js`（自备 dist 可缺省不带），裁剪后仅依赖 bundle.js + css 两资产即可渲染。

### 27.2 实现

- **`_SwaggerUIPlugin`（`Plugins.sl` L159-301）**：`_init_(distDir)` 静态字段赋值 → `onInstall` 闭包转发 → `_serve` 静态方法（方法/前缀判定 → 让位 → 穿越防护 → 拼全路径 → 未命中放行 → `sendFileRange` 短路）。
- **门面**：`SLang.Plugins.swaggerUI( distDir )`（`Plugins.sl` L677）。
- **SL 语法约束落位**：index 页长字符串一律 `StringBuilder` 逐段追加（`+` 链截断）；页面 JS 不含 `$`（SL 插值前缀——如需须经 `String.fromCharCode(36)` 运行期生成）。
- **路径拼接坑（实测修复）**：`rel` 剥 `/swagger/` 前缀后**无前导斜杠**（staticFiles 的 `rel = req.path` 自带 `/`），`full = dirBase + rel` 会拼成 `distDir文件名` → 未命中放行 404——显式补 `"/"`：`full = dirBase + "/" + rel`（T7b/T7c 首跑 FAIL 的根因）。

### 27.3 测试与验收

- **ServerP3Test T7 七断言全绿**（port 19436）：T7a `/swagger` index 四引用（bundle.js/css/openapi.json/text-html）/ T7b css dist 直出（text/css）/ T7c bundle.js dist 直出（application/javascript）/ T7d `'..'` 穿越段 403 / T7e dist 未命中放行（尾环 404）/ T7f 普通路由不受影响（/ping 200 pong）/ T7g 用户已注册 `/swagger` 让位（用户应答 "mine"）。
- **fixture**：`SLangCore/test/Other/ServerTest/swagger-ui/`（官方 swagger-ui-dist@5 真实 dist 两文件）；**测试宿主 cwd = 测试工程目录**（宿主 Main 在 RunCVM 前切 `Environment.CurrentDirectory = projectDir`，`p2_hooks.txt` 等相对路径产物落此为证）→ dist 用裸相对路径 `"swagger-ui"`。
- **回归**：ServerTest 全量 **241 OK / 0 FAIL**（基线 234 + T7 新增 7）。
- **版本**：0.0.43（纯 SL 侧改动，无 C VM/锚点变更，无需 bump）。

**下一步（v1 收官后展望）**：TLS 服务端（留待部署需求触发）/ 基准扩展（release 构建 + 32MB+ 档 + 并发客户端维度）/ 控制器池化裁决维持拒绝（§26.1）。
