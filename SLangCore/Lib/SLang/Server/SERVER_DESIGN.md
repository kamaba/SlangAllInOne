# SLang Server — HTTP / WebSocket 服务框架设计

> **文档拆分说明**（2026-10-27，原单文件过大拆为 4 份；章节编号全部保持不变，既有 `SERVER_DESIGN.md §X` 形式的外部引用按下表定位）：
>
> | 文档 | 覆盖章节 | 内容 |
> |------|----------|------|
> | SERVER_DESIGN.md（本文档） | §0–§3、§8–§11 | 摘要 / 目标与非目标 / 现状盘点 / 总体架构 ＋ 分阶段实施计划 / 工程落位与文档同步 / 风险与已知限制 / 附录 |
> | [SERVER_SYNTAX.md](SERVER_SYNTAX.md) | §4 | 语法设计（API 契约权威定义，核心章节） |
> | [SERVER_MODULES.md](SERVER_MODULES.md) | §5–§7 | 模块工程与类型清单 / 核心机制设计 / attribute 路由接线 |
> | [SERVER_CHANGELOG.md](SERVER_CHANGELOG.md) | §12–§28 | 落地实录（P0→P10 及历次重构，代码实况与设计的差异记录） |
>
> 正文中「落地实录 / 见文末 §N」类引用一律指 [SERVER_CHANGELOG.md](SERVER_CHANGELOG.md) 中的对应 § 章节。

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
| G8 | **依赖边界：只引用 Core / Std 两模块** | jsonc `references` 白名单 = `[Core, Std]`；禁用 Math / Render / Tensora / SLangMysql / 插件体系 / 任何 native DLL（MySQL 集成由用例集 ServerMysqlTest 承担，见 §8 记注） |
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

> **✅ §4.10 双形态修订记注（2026-10-27）**：attribute 控制器绑定语义定稿——形态 1（类级 `@OnRoute`）= 实例控制器声明（每请求 new 实例；`@InstanceAttr` 单例）；形态 2（类上无 `@OnRoute`）= **必须绑定 static 函数**（静态 method-ref 直调、不实例化，签名仍 `(Request, Response)`），非 static 方法装配期打印错误并拒绝注册（路由不存在 → 404）。实现：C VM `vm_sys_attribute_host_method_ref` 按"声明类非静态方法表未命中 = static"判别双形态返回（RuntimeClass 只挂实例方法表，静态方法直接 method_id 派发不入类表）；新系统方法 `SystemAttributeHostMethodIsStatic` 供 SL 侧 `registerPreload` 形态 2 判定（Core.jsonc systemCalls / `Attribute.sl` `hostMethodIsStatic()` + `ownerMemberName()` 对应登记）；CallClosure 与协程派发（spawnClosure2）两侧既有 static method-ref 分支直接复用，零新增派发代码。验收：ServerP4Test 14 断言全绿（T1e/T1f static 直挂 + 新增 T1j 非 static 拒绝 404）；ServerTest 全量 269 OK / 0 FAIL（P9 singleton 4 项既有 FAIL 经全链重编 Core→Std→SLangServer→包 恢复全绿——陈旧构建状态所致）；ExpendTest 259/0 零回归。

> **✅ 集成用例记注（2026-10-27，非分期）**：`ServerMysqlTest.sl` 落地——HTTP 路由 handler 内执行 MySQL 查询的端到端验收（端口 19511）：T0 探针（`clientVersion() > 0` 证明 `@DllStaticImport` FFI 静态预载生效、非 SL 兜底 / connect / 建库建表插 3 行）→ T1 查询（SELECT `columnCount`=4 / rows=3 / 行数据经 HTTP 往返）→ T2（路径参数 + `?` 绑定 + `fetchone` / 未命中 404）→ TC1 清库，9 断言全绿、套件 all done（ServerTest 全量 264 OK / 4 FAIL，4 FAIL 均为 P9 singleton 既有失败）。降级语义：`clientVersion <= 0` 或 connect 返回 null → 打印 skip 提前返回，无 MySQL 环境不产生 FAIL。**G8 边界不变**：SLangServer 模块自身仍仅引 Core/Std；`SLangMysql` 模块引用与连接参数（`data` 段）由用例集 jsonc 承担——集成发生在测试层。配套改动：测试宿主 `CSimpleVMTest` 新增 `StageNativeDlls`（读 staged 模块 json 的 `dllImports[].path`——仅 `static` 非空条目——与 `vmDllImports[].name`，原生 DLL basename 自源导出树平铺补拷至 staged 模块目录），保证 cvm 双预载循环与 FFI 三重回退链均命中。

每阶段完成即触发 §9 文档同步清单（R14：代码改了文档必须跟上）。

---

## §9 工程落位与文档同步

| 事项 | 落点 |
|------|------|
| 模块登记 | `Server.jsonc` + `Server.sp`（本目录）；导出 `out/export/SLangServer/` |
| 用例集 | **2026-10-25 起独立 `test/Other/ServerTest/` 用例集**（宿主 `CSimpleVMTest` 选择器 `ServerTest`，`-test` 入口约定见 `md/project/test-guide.md`）：P0 探针/引擎（ServerProbeTest/ServerCoreTest）自 NetTest 迁入，P1~P4.5 六件自 `test/ExpendTest/Server/` 迁入（该目录随之移除，ExpendTest/NetTest 不再引 SLangServer）；**ServerMysqlTest（2026-10-27）**= MySQL 集成用例（端口 19511，handler 内查询 + `?` 绑定，`SLangMysql` 由用例集 jsonc references 拉入，G8 不受影响） |
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
| 20 | **SL `params` 无数组透传语义**（P10 实锤，§28.2）：Front `MetaVisitCall` 把"逐个多余位置实参"装箱成 `object[]`，没有 C# 式"尾实参为数组则拆开透传"分支（`MetaParam.cs` 存在被注释的透传草稿 = 从未实现；`md/syntax/function.md` 亦未承诺）——把现成数组作为尾实参传给 params 形参会得到"长度 1、元素为数组"的嵌套数组，遍历元素静默失败 | 库内一切"批量登记"型 API | 规范本就未承诺透传，不改 Front；库内规避形态：批量落点一律显式数组形参（如 `RouteInfo.useAll( Function[] )`）、门面 params 版两步转发（`add(三参)` + `useAll(数组引用直传)`）；对外文档显著标注"params 形态仅限逐个独立实参传法"（md/lib/Server.md） |

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

> §12–§28 落地实录已拆分至 [SERVER_CHANGELOG.md](SERVER_CHANGELOG.md)（章节编号不变）。
