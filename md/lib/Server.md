# SLang Server（`SLang.HttpServer` + `SLang.WebSocketServer`）

HTTP/WS 服务框架，只支持两种协议，分属两个门面类（2026-10-26 自 `SLang.Server` 单类拆分）：

- **`SLang.HttpServer`** —— HTTP 服务（GET/POST 等动词路由、中间件、文档、认证、流式、上传）；
- **`SLang.WebSocketServer`** —— WebSocket 独立类，实例双形态：**形态 A** 挂在 `HttpServer` 同端口升级（`_init_()` 无参、port=0）；**形态 B** 独立端口 WS 服务器（`_init_( port )`）。

引擎为 `SLang.HttpServerCore` 模块级静态单例（v1 单 VM 单服务器语义），两门面是薄壳实例：`app.onGet(...)` 与 `SLang.HttpServerCore.onGet(...)` 等价。设计文档与实现实录见 `SlangAllInOne/SLangCore/Lib/SLang/Server/SERVER_DESIGN.md`；验收用例集 `test/Other/ServerTest/`（独立工程，宿主选择器 `ServerTest`）：`ServerProbeTest.sl`（P0 探针）/ `ServerCoreTest.sl`（P0 引擎）/ `ServerP1Test.sl`（P1）/ `ServerP15Test.sl`（P1.5 上传）/ `ServerP2Test.sl`（P2 中间件与流式）/ `ServerP3Test.sl`（P3 文档+认证）/ `ServerP4Test.sl`（P4 attribute 控制器）/ `ServerP45Test.sl`（P4.5 直接 await 糖）/ `ServerP5Test.sl`（P5 打磨：限流/Range/心跳/Jwt 签验/流式上传/路由树）/ `ServerP6Test.sl`（P6：app 级钩子 + WS 标签定向广播 + broadcast 二进制）/ `ServerP7Test.sl`（P7：multipart 流式解析）/ `ServerP9Test.sl`（P9：SwaggerUI 自研）/ `ServerP10Test.sl`（P10：cookie 读写 · formAll 同名多值 · 路由级中间件）/ `ServerMysqlTest.sl`（MySQL 集成：路由 handler 内 MySQL 查询 + `?` 绑定 + fetchone，端口 19511，2026-10-27）/ `ServerBench.sl`（基准）。

## 快速开始

```csharp
import Std;
import Core;
import SLangServer;

SLang.HttpServer app = SLang.HttpServer( 8080 )

app.onGet( "/", function( SLang.Request req, SLang.Response res )
{
    res.text( "hello" )
} )

app.run()    # 阻塞运行直至 stop()；start() = 后台启动
```

工程 `.jsonc` 需加依赖（产物目录按实际位置调整）：

```jsonc
"references": [ { "path": "../../out/export/SLangServer", "name": "SLangServer.module.slb" } ]
```

## 内联 function 直传注册

handler 无需先定义闭包变量，`function( SLang.Request req, SLang.Response res ) { ... }` 可直接写在注册调用的实参位置——编译器自动把该内联闭包提升为具名闭包再传入（0.0.39 起支持，与先定义后传入完全等价）：

```csharp
# 表单登录：缺字段 jsonFail 短路
app.onPost( "/login", function( SLang.Request req, SLang.Response res )
{
    string user = req.form( "user" )
    string pass = req.form( "pass" )
    if user == null || pass == null
    {
        res.jsonFail( 1001, "user/pass required" )
        ret
    }
    res.jsonOk( "welcome " + user )
} )

# JSON body → DTO → 201（NewUser 类须 @Serializable）
app.onPost( "/users", function( SLang.Request req, SLang.Response res )
{
    NewUser u = req.body<NewUser>()
    res.status( 201 ).jsonOk( u.name + ":" + u.age.toString() )
} )

# 路径参数 + 查询参数
app.onGet( "/user/{id}", function( SLang.Request req, SLang.Response res )
{
    Int32 id = req.pathInt( "id", 0 )
    Int32 n = req.queryInt( "n", 1 )
    res.text( "id=" + id.toString() + ",n=" + n.toString() )
} )

# 体内可挂起：Coroutine.delay / await 均可（见下节）
app.onGet( "/slow", function( SLang.Request req, SLang.Response res )
{
    Coroutine.delay( 120 )
    res.text( "slow ok" )
} )
```

注记：

- **零捕获**：SL 闭包不捕获外层局部变量，handler 体内只能引用参数与全局可见的静态成员；需要外层状态时先定义闭包变量再传入，或用类字段；
- `function( ... ) { ... }` 必须单独作为一项实参，不能与其他表达式逗号并列混写；闭包体内不允许再写内联闭包（嵌套定义不支持）；
- 任意调用的实参位置通用：中间件 `app.use( function( req, res, nx ) { ... } )`、auth 回调 `SLang.Plugins.auth( function( req ) { ... } )`、WS handler 同样适用。

## handler 内 await

handler 运行在协程上下文，体内 `await` 慢调用（DB / 网络 / 文件 IO）只挂起本请求，不阻塞其他连接。三种 await 目标形态：

```csharp
# ① 直接 await 慢方法：目标非 Task，自动 spawn 协程并等待取回（编译糖）
app.onGet( "/save", function( SLang.Request req, SLang.Response res )
{
    Int32 id = await Db.saveUser( req.query( "k" ) ) as Int32
    res.text( "saved:" + id.toString() )
} )

# ② await 无返回值目标：只等完成不取值
app.onGet( "/audit", function( SLang.Request req, SLang.Response res )
{
    await Db.logAudit( req.path )
    res.text( "audited " + req.path )
} )

# ③ await 返回 Task 的调用：透传挂起（HttpClient 异步族即此形态）
app.onGet( "/proxy", function( SLang.Request req, SLang.Response res )
{
    Net.HttpResponse r = await Net.HttpClient.httpGetAsync( "http://127.0.0.1:8080/slow" ) as Net.HttpResponse
    res.text( "proxy:" + r.body )
} )
```

并发与组合（语法全量见 `md/syntax/coroutine.md` §4–§8）：

```csharp
# 两步并发：spawn 先拿 Task，再分别 await（两调用并行跑）
app.onGet( "/both", function( SLang.Request req, SLang.Response res )
{
    Task t1 = Db.queryUser( "one" )
    Task t2 = Db.queryUser( "two" )
    Int32 v1 = await t1 as Int32
    Int32 v2 = await t2 as Int32
    res.jsonOk( v1 + v2 )
} )

# await + spawn 匿名闭包直接取值（就地并发的 CPU 计算）
app.onGet( "/calc", function( SLang.Request req, SLang.Response res )
{
    Int32 v = await spawn function() { ret 6 * 7 } as Int32
    res.text( v.toString() )
} )
```

注记：

- handler 执行超过 `cfg.handlerTimeoutMs`（默认 30000ms）未响应 → 504 收割（流式连接豁免，见「流式响应」）；
- 中间件洋葱环内同样可 await（挂起不阻塞其他请求）；
- await 目标抛异常按 handler 异常处理（既有 500/断连语义，见「生命周期与配置」）。

## 路由

| 注册 | 说明 |
|------|------|
| `app.onGet/onPost/onPut/onDelete/onPatch/onHead/onOptions/onAny(path, handler [, mw1, mw2, ...])` | 按动词注册；handler 签名 `(HttpRequest, Response)`；尾部可挂路由级中间件（P10，见「中间件与插件」节） |
| `app.on(method, path, handler [, mw1, mw2, ...])` | 自定义动词（尾参中间件同样支持） |
| `RouteInfo.use(mw)` / `RouteInfo.useAll(mws)` | 路由级中间件链式 / 批量挂载（P10，均返回 `RouteInfo` 可继续链）；`app.on*` 等注册调用即返回 `RouteInfo` |
| `app.group(prefix)` | `RouteGroup` 前缀分组：`g.onGet(...)` = prefix + path（尾参中间件同样支持） |
| `SLang.Router.checkDuplicate()` | 路径重复探测（重复抛 DuplicateRoute；`start()` 内部亦 fail-fast 同查） |

匹配规则：**静态段优先**（`/user/new` 不会被 `/user/{id}` 抢走）；`{name}` 提取路径参数；`{path*}` 通配尾段（仅最后一段，匹配剩余全部段，`req.pathParam("path")` 取整段）；重复路径注册抛错。WS 升级路由（`websocket` / `wsEvents`）经 `SLang.WebSocketServer` 形态 A 注册，见「WebSocket」节。

```csharp
app.onGet( "/user/{id}", function( SLang.Request req, SLang.Response res )
{
    Int32 id = req.pathInt( "id", 0 )
    res.text( "id=" + id.toString() )
} )
```

## attribute 控制器（P4）

C# 风格的声明式路由：attribute 标注 + `app.usePreloadRoutes()` 一行接线。
两种绑定形态（2026-10-27 起）：**形态 1** 类级 `@OnRoute` = 实例控制器（自动实例化，每请求一实例；`@InstanceAttr` 改单例）；**形态 2** 类上无 `@OnRoute` = 静态直挂——必须绑定 **static 函数**（参数仍为 `Request`/`Response`，不实例化），非 static 方法装配期报错拒绝注册（路由不存在 → 404）。

```csharp
import SLangServer;

# 形态 1 · 实例控制器：类级 @OnRoute = 前缀 + 实例化声明（方法路由拼在其后）
class P4AdminController
{
    @OnRoute( "/p4admin" )
    @OnGet( "/user" )           # GET /p4admin/user
    void plainGet( SLang.Request req, SLang.Response res )
    {
        res.text( "plain" )
    }

    @OnPost( "/user" )          # POST /p4admin/user
    void saveUser( SLang.Request req, SLang.Response res )
    {
        res.status( 201 ).jsonOk( req.bodyText() )
    }

    @Route( "/user", "DELETE" ) # @Route(path, verb)：显式动词（缺省 ANY）
    void delUser( SLang.Request req, SLang.Response res ) { ... }
}

# 形态 2 · 静态直挂：类上无 @OnRoute → 必须 static（不实例化）
class PingController
{
    @OnGet( "/ping" )           # GET /ping
    static void ping( SLang.Request req, SLang.Response res )
    {
        res.text( "pong" )
    }
}

SLang.HttpServer app = SLang.HttpServer( 8080 )
app.usePreloadRoutes()          # 拉取装配期路由表 → 进 Router
app.run()
```

| attribute | 位置 | 说明 |
|-----------|------|------|
| `@OnGet/@OnPost/@OnPut/@OnDelete/@OnPatch/@OnHead/@OnOptions/@OnAny( path )` | 方法 | 动词家族，名即动词；`@OnAny` = 任意动词 |
| `@Route( path [, verb] )` | 方法 | 显式动词通用形式（verb 缺省/空 = ANY，ASCII 大写化） |
| `@OnRoute( prefix )` | 类 | **实例控制器声明** + 前缀：本类方法路由全部拼接在其后（v1 只查声明类自身，不沿基类链） |
| `@InstanceAttr( [name] )` | 类 | 单例控制器（Std 通用机制，P9）：装配期构造单实例写入合成静态字段，本类全部方法路由绑定该实例（跨请求/跨 handler 状态共享）；缺省字段名 `instance`，`@InstanceAttr("inst")` → `ClassB.inst` |

要点：

- **形态 1 · 每请求一实例（类级 `@OnRoute`）**：命中时 new 控制器实例后派发目标方法（handler 语义与动态注册完全一致，`await`/`Coroutine.delay` 照常可用，超时 504 同 §6.1 守护）；
- **形态 2 · 静态直挂（类上无 `@OnRoute`）**：必须绑定 **static 函数**（静态 method-ref 直调，不实例化）；非 static 方法 → 装配期打印错误并拒绝注册（路由不存在 → 404，日志可查）；
- **单例控制器（`@InstanceAttr`，Std 通用，P9）**：跨请求/跨 handler 共享实例字段（计数器、缓存、连接池等有状态控制器用）；单例为进程级（同类多 app 共享同一实例）；装配期实例同时写入合成静态字段（`Class.instance` 源代码直接可访问，类型即宿主类，免转型）；
- **与动态注册共存**：preload 路由先注册，动态 `app.onGet(...)` 后注册照常工作；同路径重复注册仍受 `checkDuplicate` fail-fast 约束；
- **多次拉取幂等**：`usePreloadRoutes()` 重复调用返回 0 条新增（装配期注册中心只拉一次）；
- handler 签名与动态注册一致（`function( SLang.Request, SLang.Response )`）；属性类定义：`@On*`/`@Route`/`@OnRoute` 于 `Lib/SLang/Server/RouteAttrs.sl`，`@InstanceAttr` 于 `Lib/Std/InstanceAttr.sl`（旧 `@Singleton` 已收编退役）。

单例示例（`@InstanceAttr` 与 `@OnRoute` 可叠加）：

```csharp
@InstanceAttr
@OnRoute( "/counter" )
class CounterController
{
    Int32 hits = 0

    @OnGet( "/hits" )              # GET /counter/hits —— 跨请求递增
    void hits( SLang.Request req, SLang.Response res )
    {
        this.hits = this.hits + 1
        res.text( "hits=" + this.hits.toString() )
    }

    @OnPost( "/reset" )            # POST /counter/reset —— 改写同一实例字段
    void reset( SLang.Request req, SLang.Response res )
    {
        this.hits = 0
        res.text( "reset ok" )
    }
}

# 源代码任意处直接取同一单例（装配期已构造，类型即宿主类）：
CounterController.instance.hits = 100

# 自定义字段名：@InstanceAttr( "inst" ) → CounterController.inst
```

## Request（请求读取）

| API | 说明 |
|-----|------|
| `method` / `path` / `rawQuery` / `headers` | 请求行与头 |
| `pathParam(name)` / `pathInt(name, def)` / `pathInt64(name, def)` | 路径参数（坏格式/缺失用默认值） |
| `query(name)` / `queryInt` / `queryBool` / `hasQuery` | 查询参数（percent-decode、`+`→空格） |
| `header(name)` | 单头（大小写不敏感） |
| `bodyText()` / `bodyBytes()` | 原文 body |
| `body<T>()` | JSON 反序列化为 DTO（**类必须 `@Serializable()`**，否则解析结果不可用） |
| `form(name)` / `formInt` / `formBool` / `hasForm` | `application/x-www-form-urlencoded` 表单字段（multipart 普通字段同表并入）；**键重复后者覆盖前者（末值语义，§6.4）** |
| `formAll(name)` | 同名多值全序收集（P10）：urlencoded 按出现序逐段收（不去重）→ `List<string>`；不存在返回空表（`length` 判定）；multipart 普通字段并入（已知限制：同名多字段仅并入单值） |
| `cookie(name)` / `hasCookie(name)` / `cookieKeys()` | Cookie 头读取（P10，惰性解析）：单值（不存在 null；同名多条取最末条——浏览器按 Path 长度升序发送）/ 存在性 / 全部键 `List<string>`；值不解码 |
| `file(name)` / `files(name)` / `fileCount` | multipart 文件（P1.5）：`UploadedFile` 句柄（`filename` / `content` / `size` / `saveAs(path)` / `saveInto(dir)` 重名自动改名；filename 服务端安全剥离防穿越） |

## Response（响应写出，链式）

```csharp
res.status( 201 ).header( "X-Trace", "t1" ).text( "created" )
res.json( user )                       # 序列化对象（DTO 同样须 @Serializable）
res.jsonOk( payload )                  # {"ok":true,"data":...}
res.jsonFail( 1001, "bad input", 400 ) # 业务码 + 消息（httpStatus 可省，默认 400）
res.html( "<b>hi</b>" )
res.redirect( "/login" )
res.bytes( buffer )                    # 二进制（application/octet-stream）
res.sendFile( "./big.bin" )            # 文件直写下载（64KB 分块、Content-Length 精确，keep-alive 续用）
res.file( "./a.pdf", "report.pdf" )    # sendFile + Content-Disposition 附件头
res.setCookie( "sid", "abc123" )       # P10：简易形态（name=value，链式同上）
res.setCookie( "sid", "abc123", "/", 3600, true, true, "Lax" )
                                       # P10 属性形态：path / maxAge 秒 / secure / httpOnly / sameSite
                                       # （maxAge <= 0 省略 Max-Age；SameSite=None 自动补 Secure）
```

setCookie 说明（P10）：

- **Set-Cookie 不可逗号合并**：多次调用逐行重复写出，各 cookie 一行；
- 属性七参全量：`name, value, path, maxAge, secure, httpOnly, sameSite`（`path` 常用 `"/"`）；
- 读侧配套见 Request 表 `cookie` / `hasCookie` / `cookieKeys` 三条。

## 中间件与插件（P2）

中间件 = 三参 Function（注册序即执行序；onion 模型：调 `nx.go()` 放行，`go()` 之后的代码 = 后置环；不调 = 短路；重复调 `go()` no-op）：

```csharp
app.use( function( SLang.Request req, SLang.Response res, SLang.Next nx )
{
    if req.header( "X-Token" ) == ""
    {
        res.jsonFail( 401, "unauthorized", 401 )   # 短路：后续环与 handler 不再执行
        ret
    }
    nx.go()                                        # 放行进下一环（最内环 = handler / 404·405 尾环）
    res.header( "X-Trace", "after" )               # 此处 = 后置环（内环完成后自然回程）
} )
```

未匹配的请求（404/405）同样过管道——CORS 预检 / 静态文件等内置插件依赖此语义。

### 路由级中间件（P10）

全局 `app.use(...)` 之外，可把中间件挂到**单条路由**——三种写法（同为三参 Function，与全局中间件同一逻辑可复用）：

```csharp
# ① 注册时尾参直挂（app.on* / g.on* / app.on 全家族；登记序即执行序）
app.onGet( "/admin", hAdmin, mwAuth, mwAudit )

# ② 链式挂载（注册调用返回 RouteInfo）
SLang.RouteInfo r = app.onGet( "/admin", hAdmin )
r.use( mwAuth ).use( mwAudit )          # use 返回 RouteInfo，可继续链

# ③ 批量挂载（直传现成数组）
SLang.RouteInfo r2 = app.onGet( "/admin2", hAdmin )
r2.useAll( mwArray )                    # 显式 Function[] 形参，数组原样透传
```

执行序：**全局中间件 onion → 路由级中间件（登记序）→ handler**；路由级 mw 不调 `nx.go()` 即短路——后续路由级 mw 与 handler 不再执行。未匹配路由（404/405）不走路由级 mw（它们属于具体路由）。

⚠ **params 尾参形态仅限"逐个独立实参"传法**：SL 的 params 语义是把逐个多余实参装箱成数组，**没有**"尾实参是数组则拆开透传"的语义——把现成 `Function[]` 数组作为单个尾实参传入 params 形参会被再包一层导致中间件丢失。直传数组请一律走写法 ③（`RouteInfo.useAll` 显式数组形参）。

插件 = `ServerPlugin` 子类（`onInstall` 在 `use()` 时立即执行 = 注册点；`onStart`/`onStop` 随 start/stop；`onWsOpen`/`onWsClose` 会话钩子广播）。SL 闭包零捕获、类方法拿不到外层局部 `app`，`onInstall` 内直接写引擎级形态（与实例门面等效）：

```csharp
class MyPlugin : SLang.ServerPlugin
{
    override void onInstall()          # 注册中间件/路由就在这里（立即生效）
    {
        SLang.HttpServerCore.onGet( "/mark", function( SLang.Request req, SLang.Response res ) { ... } )
    }
    override void onStart() { ... }
    override void onStop()  { ... }
}
app.use( MyPlugin() )
```

内置插件（`SLang.Plugins`）：

```csharp
app.use( SLang.Plugins.logger() )                    # 请求日志
app.use( SLang.Plugins.cors() )                      # CORS：预检 OPTIONS → 204 + Access-Control-Allow-* 头
app.use( SLang.Plugins.staticFiles( "./public" ) )   # 静态目录：GET 直出（HEAD 放行）、扩展名定 MIME、Range 断点续传透传
app.use( SLang.Plugins.rateLimit( 100 ) )            # P5：按 IP 固定窗口限流（60s 窗口内超 100 次 → 429 + Retry-After）
app.use( SLang.Plugins.rateLimit( 100, 30000 ) )    # 同上，自定义窗口毫秒
app.use( SLang.Plugins.swaggerUI( "./swagger-ui-dist" ) )  # P9：GET /swagger 自研 index（外链 dist 资产 + /openapi.json）
                                                      #      + GET /swagger/<file> dist 直出（MIME/Range/'..' 403/
                                                      #      未命中放行；用户已注册 /swagger 则让位）
```

## 断点续传（P5）

`sendFile` / `staticFiles` 均支持 Range：请求带 `Range: bytes=a-b` → 206 + `Content-Range`；`bytes=a-` 开区间尾段、`bytes=-n` 尾部 n 字节；start 越界 → 416 + `Content-Range: bytes */size`；畸形 Range 忽略按全量 200。响应恒带 `Accept-Ranges: bytes`。`res.sendFileRange( path, req.header( "Range" ) )` 可显式控制。

## 请求侧流式上传（P5）

路由声明 `streamBody = true` → 引擎不预读 body，连接移交 handler，超大上传不驻留内存：

```csharp
SLang.RouteInfo r = app.onPost( "/big-upload", hUpload )
r.streamBody = true

# handler 内：
SLang.HttpBodyReader rd = req.bodyStream()      # 非 streamBody 路由返回 null
var fs = FileStream( "out.bin", FileMode.Create )
ByteBuffer chunk = ByteBuffer( 4096 )
while true
{
    Int32 n = rd.read( chunk )                   # 0 = 结束；超上限抛 StreamBodyError.LimitExceeded
    if n <= 0 { break }
    var view = chunk.slice( 0, n )
    fs.write( view )                            # 边收边落盘
    chunk.clear()
}
fs.close()
```

Content-Length 精确与 chunked 两模式感知；上限 = `cfg.maxBodyBytes`（multipart 放宽至 `maxUploadBytes`），显式形态 `req.bodyStream( maxBytes )` 自管。handler 未消费完即返回 → 引擎丢弃式排干后 keep-alive 续用（排干失败断连止损）。

## multipart 流式解析（P7）

`streamBody = true` 路由 + `multipart/form-data` 组合：`req.multipartStream() → SLang.MultipartReader`，逐 part 消费，大文件上传不驻留内存。同一请求多次调用返回同一实例；非流式路由 / Content-Type 非 multipart / boundary 缺失 → 返 null（非流式路由请用 `form()` / `file()` 内存族，CT 缺陷由 handler 裁决）：

```csharp
SLang.RouteInfo r = app.onPost( "/upload", hUp )
r.streamBody = true

# handler 内：
SLang.MultipartReader mr = req.multipartStream()
if mr == null
{
    res.text( "bad multipart" )
}
else
{
    while true
    {
        SLang.MultipartPart p = mr.nextPart()      # null = 全部 part 消费完
        if p == null { break }
        if p.isFile
        {
            p.saveAs( "upload_" + p.filename )     # 直落盘（非 throws，失败返 false）
            # 自控增量：Int32 n = p.read( chunk )  # 0 = 本 part 结束
            # 内存聚合：ByteBuffer fb = p.readAll()
        }
        else
        {
            ByteBuffer fb = p.readAll()            # 表单字段（小体量）
            string val = fb.toString()
            fb.release()
        }
    }
    # 此处 mr.isDone == true（终界已见）
}
```

`MultipartPart` 元数据：`field`（字段名）/ `filename`（null = 普通字段，已剥路径）/ `contentType` / `isFile`。鲁棒性：boundary 跨 TCP 分帧匹配不受切分影响；preamble 区容忍；handler 半途返回（`break` / 提前收尾）→ 引擎自动排干剩余 part 与字节，keep-alive 续用。

## WS 空闲心跳（P5）

`cfg.wsIdleTimeoutMs`（缺省 0 不启用）：空闲超过该时长无入站消息的 WS 会话被看门狗关闭（handler 的 `receive()` 返回 null 自然收尾）；活跃消息持续刷新计时。两形态通用便捷写法：`ws.idleTimeout( ms )`（实例方法；同端口形态下先建 `SLang.HttpServer` 实例再调用，可同步写 `cfg.wsIdleTimeoutMs`）。

## Jwt 签发与验签（P5，HS256）

```csharp
# 签发（iat 恒写；exp 秒数 > 0 时写入）
SLang.JwtClaims c = SLang.JwtClaims()
c.put( "sub", "user-42" )
string token = SLang.Jwt.sign( c, secret, 3600 )          # 显式密钥
string token2 = SLang.Jwt.sign( c, 3600 )                # 便捷形态：密钥取 ServerConfig.jwtSecret（未配置抛 MissingJwtSecret）

# 验签（全量：三段格式 + alg 必须 HS256 + 签名逐字节比对 + exp 过期拦截）
SLang.JwtClaims who = SLang.Jwt.verify( token, secret )  # 失败 null（含篡改/错密钥/过期/alg 降级）
SLang.JwtClaims who2 = SLang.Jwt.verify( token )          # 便捷形态
```

`decode`（不验签读取）语义独立保留；第三方 token 验真一律走 `verify`。

## 路由匹配（P5 树化）

路由表为段前缀树（静态段 > 参数段 > 通配的择优语义不变、同数先注册者优先）：静态段走字面边、`{param}` 共享参数边、`{path*}` 挂前缀节点——匹配只评估相关分支，非语义变更。

## 流式响应（P2）

流式连接豁免 `handlerTimeoutMs` 超时收割（长推送不被杀）：

```csharp
SLang.StreamWriter w = res.stream()     # chunked：200 + Transfer-Encoding: chunked
w.write( "part1" )
w.writeBytes( buf )                     # 二进制块
w.close()                               # 发终止块（幂等；未调则引擎兜底 close）

SLang.SseWriter sse = res.sse()         # SSE：200 + text/event-stream
sse.send( "data: hi" )                  # 裸帧
sse.sendEvent( "tick", "1" )            # event: + data: 组帧
sse.comment( "keepalive" )              # 注释帧
sse.close()
```

## API 文档（P3）

`start()` 时自动挂载 `GET /docs`（自包含 HTML 页面：接口分组/参数/示例/GET 试一试，零外链）与 `GET /openapi.json`（OpenAPI 3.0.3）；用户已注册同路径则让位；`app.docs( false )` 关闭（生产建议；`reset()` 恢复默认开）。

文档元数据在注册时顺手填（返回 `RouteInfo`，链式）：

```csharp
app.onGet( "/api/user/{id}", hUser )
    .summary( "获取用户" ).tag( "用户" )            # tags 字段逗号分隔亦可
    .param( "id", "integer", "用户ID", true )       # in 按 pattern 含 {id} 自动推导
    .requestBody( CreateUserReq() )                  # 样例实例 → 探针法 schema + example
    .formField( "username", "用户名" )               # urlencoded 字段
    .uploadField( "avatar", "头像", "image/*" )      # multipart 文件字段
    .response( 200, User() )                         # 响应 schema（responseAs 指定 mediaType）
    .security( "bearerAuth" );                       # 或 "apiKeyAuth"
```

schema 复用：同名样例类只登记一次 `components.schemas`（类型名 = `Type.toString()`），operation 以 `#/components/schemas/<名>` 引用。任一路由声明过 `security` → 生成 `securitySchemes`（bearerAuth=http/bearer/JWT、apiKeyAuth=apiKey/X-API-Key header）+ operation 级 `security` → Apifox/Postman 导入后 Auth 自动配好。security 由开发者显式声明（auth 插件的 `.skip()` 白名单使框架无法可靠推断，显式优于隐式）。

**反向导入**（Apifox 导出 OpenAPI json → 路由骨架）：

```csharp
Int32 added = app.importOpenApi( "api-spec.json" );
# 未注册路径 → 文档路由（/docs 可见、命中 501；返回新建数）
# 已注册路径 → 仅合并 summary/tags/param/security 元数据
# 后续 onGet(...) 同名注册自动顶替 + 继承文档元数据（设计先行工作流）
```

## 认证（P3）

三种挂法（`SLang.Plugins`；通过 → 身份写 `req.auth`，未通过 → 401 短路）：

```csharp
# ① 通用回调：收整个 req，任意 header 组合；ret 身份对象 / ret null
app.use( SLang.Plugins.auth( function( SLang.Request req )
{
    string t1 = req.header( "X-Token" )
    string t2 = req.header( "X-Sign" )
    if t1 == null || t2 == null { ret null }
    ret checkSign( t1, t2 )
} ) );

# ② Bearer：Authorization: Bearer <token> → Jwt.decode → req.auth = JwtClaims
app.use( SLang.Plugins.authBearer().skip( "/api/login" ).ws( true ) );

# ③ API Key：自定义 header 名 + key 校验回调
app.use( SLang.Plugins.authApiKey( "X-API-Key", function( string key )
{
    ret loadAccountByKey( key )        # 身份对象 或 null
} ) );
```

- `.skip( path )`：公开路径白名单（精确匹配、链式多次）——未声明 = 全站锁死（最安全默认）；
- `.ws( true )`：WS 升级 token 接管（浏览器 WS 无法自定义头 → token 走 `?token=` 查询参数；失败即关会话；仅 bearer/apiKey 模式）；
- Bearer 模式 401 附 `WWW-Authenticate: Bearer` 头（RFC 6750）；
- **授权不做框架**：handler 内读 `req.auth as SLang.JwtClaims` 自判（403）。

**Jwt claims 读取 + HS256 签验**（P3 decode / P5 sign·verify）：

```csharp
SLang.JwtClaims c = SLang.Jwt.decode( "eyJhbGciOi..." );  # 不验签读取；格式非法 → null
c.subject;         # "sub"（缺失 null）
c.expiresAt;       # "exp" → Int64 秒（缺失 0）
c.expired;         # 现时 > exp（exp 缺失恒 false）——decode 不自动拒
c.claim( "uid" );  # 任意自定义 claim（缺失 null）

# P5：签发与全量验签见「Jwt 签发与验签」节；第三方 token 验真必须 verify（decode 不验签）
```

**其他 P3 插件**：`SLang.Plugins.bodyLimit( limitBytes )`（应用级 body 上限收紧，超限 413）；`SLang.Plugins.requestId()`（X-Request-Id 响应头，Guid）；`ServerConfig.maxConnections = 1024`（并发连接上限，超出 503）。

## WebSocket（`SLang.WebSocketServer`）

一个类两种用法，由构造形态决定：

| | 形态 A：同端口升级 | 形态 B：独立端口 |
|---|---|---|
| 构造 | `SLang.WebSocketServer()`（port=0） | `SLang.WebSocketServer( 9090 )` |
| 路由 | `ws.websocket( path, handler )` / `ws.wsEvents( path )` | 无路由，全站收发 |
| 回调 | handler 内 `s.receive()` 循环 | `ws.onMessage( fn )` / `ws.onClose( fn )` |
| 启动 | 随 `app.start( port )`（HTTP 同端口） | `ws.start( port )` / `ws.run( port )` |
| 会话 | `ws.sessions( path )` / `ws.broadcast( path, text )` | `ws.sessions()` / `ws.broadcast( text )` |
| 参数语法 | 与 HTTP 路由同一套 `{name}` / `{path*}` / `?query` | 无路径参数 |

### 形态 A——HTTP 同端口进程内升级

```csharp
SLang.WebSocketServer ws = SLang.WebSocketServer()   # 形态 A：无端口参数
ws.websocket( "/ws/{room}", function( SLang.WsSession s )
{
    bool looping = true
    while looping
    {
        Net.WsMessage m = s.receive()        # null = 对端关闭（含空闲心跳超时）
        if m == null { looping = false }
        else
        {
            if m.isText
            {
                s.sendText( "echo: " + m.text() )   # s.pathParam("room") / s.query("name") 可用
            }
            m.release()                     # 消息归属 handler，消费完必须归还
        }
    }
} )
```

事件式糖（不想写收发循环时；内部仍是一协程）：

```csharp
ws.wsEvents( "/chat/{room}" )
    .onOpen(    function( SLang.WsSession s ) { ... } )                              # s.pathParam("room") 可用
    .onMessage( function( SLang.WsSession s, Net.WsMessage m ) { ...; m.release() } )  # 每帧一调；msg 归回调所有
    .onClose(   function( SLang.WsSession s ) { ... } )
```

### 形态 B——独立端口

```csharp
SLang.WebSocketServer wss = SLang.WebSocketServer( 9090 )
wss.onMessage( function( SLang.WsSession s, Net.WsMessage m )     # msg 归回调所有，须 m.release()
{
    if m.isText { s.sendText( "echo: " + m.text() ) }
    m.release()
} )
wss.onClose( function( SLang.WsSession s ) { ... } )
wss.run( 9090 )       # start( 9090 ) + awaitStop()；stop() / isRunning 同 HttpServer
```

### WsSession / WsMessage

| `WsSession` | 说明 |
|-------------|------|
| `id` | 会话 GUID |
| `remoteAddress` | 对端地址 |
| `routePattern` | 命中的路由模式（形态 B 为 "/"） |
| `pathParam(name)` / `pathInt(name, def)` / `query(name)` | 路径/查询参数（形态 A） |
| `receive()` | 阻塞收一帧 → `Net.WsMessage`；null = 关闭；成功收帧刷新空闲心跳计时 |
| `sendText( text )` / `sendBinary( ByteBuffer )` / `sendPing()` | 发送 |
| `tag( name )` / `untag( name )` / `tagged( name )` / `tags` | 会话标签（P6）：`tags` 为 `List<string>` 快照；打标可在 handler 内任意时点 |
| `close()` / `isOpen` / `closeInfo` | 关闭（`Net.WsCloseInfo`：`code` / `reason` / `wasClean`） |

`Net.WsMessage`：`op`（WsOpCode.Text/Binary）、`payload`（ByteBuffer，归属本消息）、`isText` / `isBinary`（getter）、`size`（getter）、`text()`（文本帧内容）、**`release()` 归还**（消息归接收方所有，消费完必须调用，勿跨 release 持有 payload 引用）。

### 广播与标签（P6）

`broadcast` / `broadcastTag` 全家族均返回 `Int32` 实际送达数，且各带**文本 + 二进制（`ByteBuffer`）两种载荷形态**：

```csharp
# 全量广播（两形态）：
ws.broadcast( "/ws/room", "notice" )              # 形态 A：path 下全部会话
ws.broadcast( "/ws/room", payloadByteBuffer )     # 形态 A：二进制载荷
ws.broadcast( "notice" )                           # 形态 B：全站
ws.broadcast( payloadByteBuffer )                  # 形态 B：二进制载荷

# 标签定向广播（只达打过该标签的会话）：
ws.broadcastTag( "/ws/room", "vip", "go-vip" )     # 形态 A：path + tag
ws.broadcastTag( "/ws/room", "vip", payloadBuf )   # 形态 A：二进制载荷
ws.broadcastTag( "vip", "go-vip" )                 # 形态 B：tag
ws.broadcastTag( "vip", payloadBuf )               # 形态 B：二进制载荷
```

handler 内打标典型用法（登录态/角色分组，零捕获规则同其它闭包——体内引用静态须类名限定）：

```csharp
ws.websocket( "/ws/room", function( SLang.WsSession s )
{
    while true
    {
        Net.WsMessage m = s.receive()
        if m == null { break }
        if m.isText && m.text() == "login:vip"
        {
            s.tag( "vip" )                         # 此后 broadcastTag( ..., "vip", ... ) 定向可达
        }
        m.release()
    }
} )
```

## 生命周期与配置

```csharp
SLang.HttpServer app = SLang.HttpServer( 8080 )

SLang.ServerConfig cfg = app.config           # 活引用（改字段立即生效）
cfg.maxBodyBytes = 20971520                   # body 上限；maxHeaderBytes 同理
cfg.maxUploadBytes = 104857600                # 上传上限（P1.5）；maxFileBytes=50MB 单文件
cfg.handlerTimeoutMs = 30000                  # handler/中间件超时（0 = 不限；流式连接豁免）
cfg.wsIdleTimeoutMs = 60000                   # WS 空闲会话超时毫秒（P5；0 = 不启用）
cfg.jwtSecret = "s3cret"                       # Jwt.sign/verify 便捷形态密钥（P5）
app.configure( cfg )                          # 或整对象全量覆盖（port 字段同步到实例）

app.start()          # 后台启动（协程接受连接；用构造端口）
app.start( 9090 )    # 指定端口启动
app.awaitStop()      # 等待 stop
app.stop()           # 关监听 + 强制断开在途连接（触发 onClose）
app.reset()          # 清全部路由 + 清三钩子（下一轮测试复用）
app.isRunning        # 运行中标志
```

### app 级事件钩子（P6）

字段赋值形态（set/get 访问器）；钩子零捕获（体内只能引用全局静态，SL 闭包规则）；`reset()` 清空三钩子：

```csharp
SLang.HttpServer app = SLang.HttpServer( 8080 )

function hOnStart = function()
{
    Console.println( "server up" )     # 体内只能引用全局静态
}
app.onStart = hOnStart                 # 字段赋值右侧不能直接写闭包字面量——先存变量

function hOnStop = function() { ... }
app.onStop = hOnStop                   # stop() 收尾触发（插件 onStop 之后）

function hOnError = function( SLang.Request req, SLang.Response res, Error e )
{
    res.status( 599 )                   # 钩子内可写响应自救（未写则 500 兜底）
    res.text( "boom: " + e.toString() )
}
app.onError = hOnError                 # handler/中间件抛异常时触发（管道 catch 接线）
```

触发时序：`onStart` 在 start 末尾（插件 onStart 之后）；`onStop` 在 stop 收尾（插件 onStop 之后）；`onError` 在管道 catch 中（异常吞、不拖垮连接，`e` 为 Error 对象）。三钩子均可省略（null 时静默跳过）。

handler/中间件内抛异常：已暂存响应照常写出（首个响应胜出），未响应则 500 + 断连；流式头已发则兜底终止块 + 断连。`ServerError` 枚举：`DuplicateRoute=1` / `AlreadyResponded=2` / `NotRunning=3` / `AlreadyRunning=4` / `InvalidConfig=5` / `MissingJwtSecret=10`。

## 多端口监听（ServerListener，v1.1）

一个工程内监听多个端口：`app.listen(...)` 返回 `SLang.ServerListener` 句柄，可再挂路由（仅本监听器可见）；主监听器（`app.start()` 端口）tag=1，扩展监听器自 2 递增。`app.stop()` 一并关闭全部监听器。

```csharp
SLang.HttpServer app = SLang.HttpServer( 8080 )

# 全局路由：所有监听器（主 + 扩展）均可见
app.onGet( "/ping", function( SLang.Request req, SLang.Response res )
{
    res.text( "pong" )
} )

app.start()                        # 主监听器 8080（tag=1）

# 扩展监听器 9090：路由仅本端口可见（路径隔离）
SLang.ServerListener admin = app.listen( 9090 )
admin.onGet( "/secret", function( SLang.Request req, SLang.Response res )
{
    res.text( "admin only" )
} )
admin.onGet( "/greet", handlerGreet, [ mwAudit ] )    # 路由级中间件同款尾参
admin.websocket( "/ws", handlerWs )                   # WS 升级同样按监听器隔离

# 运行中动态加端口（亦可在 start() 前批量登记，随 start 一并拉起）
SLang.ServerListener dyn = app.listen( "127.0.0.1", 9091 )
Console.println( dyn.port.toString() + " tag=" + dyn.tag.toString() )
```

规则：

- 全局路由（`app.on*` / `g.on*` / 控制器 attribute 路由）对**所有**监听器可见；`ServerListener.on*` / `websocket` 注册的路由**仅本监听器**可见（含 `{param}` 提取与 405+Allow 判定）。
- 同名冲突判定按监听器隔离：全局与监听器视图可同名 pattern（跨监听器不判 DuplicateRoute）；请求优先命中本监听器专属路由，其次全局路由。
- `req.localPort`（只读）：本请求进入的监听端口——主监听器 = 配置端口，扩展监听器 = `listen()` 端口；同一 handler 挂多端口时据此分流。
- `listen()` 的 host 空值兜底 `0.0.0.0`；端口越界（<=0 或 >65535）抛 `ServerError.InvalidConfig`。

## 编译与运行

```powershell
# ① 编译 SLangServer 库（cwd = SlangAllInOne；库改动后先编库）
dotnet run --project "Project\CompileStdlib\SimpleLanguageCompileStdlib.csproj" -- "SLangCore\Lib\SLang\Server\Server"
# 产物：out\export\SLangServer\SLangServer.module.slb + SLangServer.module.json

# ② 编译消费工程（cwd = 仓库根；以 ServerTest 验收工程为例）
dotnet run --project "simple_language\source\SimpleLanguageFront.csproj" -- compile -e ir -p "SlangAllInOne\SLangCore\test\Other\ServerTest\ServerTest.sp" --format binary+json --no-banner

# ③ 运行（cwd 必须是 ServerTest 目录：测试夹具按 cwd 相对路径加载）
cd SlangAllInOne\SLangCore\test\Other\ServerTest
..\..\..\..\package\win32-debug\bin\csimple_lang.exe run --no-banner ..\..\..\..\out\export\ServerTest\ServerTest.module.json
```

注意：Front 编译失败时进程退出码仍为 0——以阶段汇总无 `Failed`、产物 mtime 新鲜为准。
