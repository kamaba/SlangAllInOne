# SLang Server 设计 · 模块与核心机制（原 §5–§7）

> 本文档由单文件 `SERVER_DESIGN.md` 拆分而来（2026-10-27），完整收录原 **§5 模块工程与类型清单 / §6 核心机制设计 / §7 attribute 路由接线**；章节编号与正文内容保持原样、未作改动。
> 其余部分：总览与规划（§0–§3、§8–§11）见 [SERVER_DESIGN.md](SERVER_DESIGN.md) · 语法设计（§4）见 [SERVER_SYNTAX.md](SERVER_SYNTAX.md) · 落地实录（§12–§28）见 [SERVER_CHANGELOG.md](SERVER_CHANGELOG.md)。

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
      #   与 Net.*/File/Timer（Std）；禁引 Math/Render/Tensora/SLangMysql/插件/native DLL
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
→ 键重复：后者覆盖前者（与查询参数一致；同名多值 formAll(name) **已落地（P10，§28）**）
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
2. **宿主接口**（Core.Attribute 基类方法，系统方法 `SystemAttributeHostMethodRef/Of/IsStatic/HostClassNew`）：`hostMethodRef()` = 双形态（§4.10，2026-10-27 修订：static 方法 → 静态 method-ref 不实例化；实例方法 → LATE 实例闭包，每请求一实例）；`hostMethodIsStatic()` = 宿主方法是否 static（形态 2 判定，registerPreload 消费）；`hostMethodRefOf(inst)` = 绑定实例 method-ref（单例全程复用，§26）；`hostClassNew()` = 构造宿主新实例；
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
