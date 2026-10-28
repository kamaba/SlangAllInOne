# SLang Server 设计 · 语法设计（原 §4）

> 本文档由单文件 `SERVER_DESIGN.md` 拆分而来（2026-10-27），完整收录原 **§4 语法设计**；章节编号与正文内容保持原样、未作改动。
> 其余部分：总览与规划（§0–§3、§8–§11）见 [SERVER_DESIGN.md](SERVER_DESIGN.md) · 模块与机制（§5–§7）见 [SERVER_MODULES.md](SERVER_MODULES.md) · 落地实录（§12–§28）见 [SERVER_CHANGELOG.md](SERVER_CHANGELOG.md)。

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

# 4) 数据库查询：多表并发 + 等其它任务全部执行完（waitAll）——DB 访问（Sqlite / SLangMysql 封装；
#    集成验证 = test/Other/ServerTest/ServerMysqlTest.sl，2026-10-27：handler 内 MySQL 查询 + `?` 绑定）
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

**两种绑定形态**（2026-10-27 修订，缺省即生效）：

```sl
# 形态 1 · 实例控制器：类级 @OnRoute = 控制器声明（自动实例化，每请求
# new 一个实例；@InstanceAttr 改单例 bind-once，§26）
@OnRoute( "/api/v1" )
public class UserController
{
    @OnGet( "/users/{id}" )                      # -> GET /api/v1/users/{id}（前缀拼接）
    public void getUser( SLang.Request req, SLang.Response res ) { ... }

    @OnPost( "/users" )                          # -> POST /api/v1/users；异步/同步方法随意混排
    public void createUser( SLang.Request req, SLang.Response res )
    {
        CreateUserReq b = req.body<CreateUserReq>();
        User u = await persistUser( b ) as User;  # 直接 await 一步到位（§7.5 糖，P4.5 已落地）——派发时本方法已在
                                                  # handler 协程上运行（§6.1），落库等慢操作封装为协程函数即可，
                                                  # 方法体内无需再 spawn 拿 Task；
        res.status( 201 ).jsonOk( u );
    }
}

# 形态 2 · 静态直挂：类上无 @OnRoute → 必须绑定 static 函数（静态
# method-ref 直调，不实例化）；签名仍是 ( Request, Response )
public class PingController
{
    @OnGet( "/ping" )                             # -> GET /ping（无前缀，方法路径即全路径）
    public static void ping( SLang.Request req, SLang.Response res ) { res.text( "pong" ) }
}

app.usePreloadRoutes();    # 装配期批量接线（各 attribute _enter_ 自动注册，§26 形态 3）
```

- **签名与闭包完全一致**：`public void m( SLang.Request req, SLang.Response res )`（形态 2 为 `public static void m(...)`）；注册后与 §4.2 闭包注册**同一条派发路径**——协程派发 / 中间件管道 / 超时守护 / 文档收集全部同权，方法体内同样可自由 `await / yield / Coroutine.delay`（§4.2 执行模型保证），且 `await` 可直写协程函数调用——`await persistUser( b ) as User` 一步到位（§7.5 糖，P4.5）；
- **实例语义（双形态）**：类级 `@OnRoute` = 实例控制器声明——每请求 new 一个实例（v1 语义最简、免共享状态心智负担；`@InstanceAttr` 显式单例，§26）；类上无 `@OnRoute` → 必须绑定 **static 函数**（静态 method-ref，不实例化）——非 static 方法装配期打印错误并**拒绝注册**（路由不存在 → 404，日志可查，装配流程不中断）；
- **类级前缀**（形态 1 声明）：`@OnRoute( "/api/v1" )` 标在类上则与方法路径拼接（Spring `@RequestMapping` 类级先例）；等价分组仍可用 §4.2 `app.group()`；
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
