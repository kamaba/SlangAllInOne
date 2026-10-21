# SLang Server（`SLang.HttpServerCore` + `SLang.Server`）

HTTP/WS 服务框架。设计文档与实现实录见 `SlangAllInOne/SLangCore/Lib/SLang/Server/SERVER_DESIGN.md`；验收用例 `test/ExpendTest/Server/ServerP1Test.sl`（P1）/ `ServerP15Test.sl`（P1.5 上传）/ `ServerP2Test.sl`（P2 中间件与流式）。

## 快速开始

```csharp
import Std;
import Core;
import SLangServer;

SLang.Server.onGet( "/", function( SLang.Request req, SLang.Response res )
{
    res.text( "hello" )
} )

SLang.Server.run( 8080 )    # 阻塞运行直至 stop()；start() = 后台启动
```

工程 `.jsonc` 需加依赖（产物目录按实际位置调整）：

```jsonc
"references": [ { "path": "../../out/export/SLangServer", "name": "SLangServer.module.json" } ]
```

## 路由

| 注册 | 说明 |
|------|------|
| `onGet/onPost/onPut/onDelete/onPatch/onHead/onOptions/onAny(path, handler)` | 按动词注册；handler 签名 `(HttpRequest, Response)` |
| `on(method, path, handler)` | 自定义动词 |
| `websocket(path, handler)` | WS 路由（进程内升级形态，见下） |
| `wsEvents(path)` | WS 事件式糖：`.onOpen(...).onMessage(...).onClose(...)` 链（见下） |
| `group(prefix)` | `RouteGroup` 前缀分组：`g.onGet(...)` = prefix + path |
| `checkDuplicate()` / `start()` | 路径重复 fail-fast（重复抛 DuplicateRoute，start 前调用） |

匹配规则：**静态段优先**（`/user/new` 不会被 `/user/{id}` 抢走）；`{name}` 提取路径参数；`{path*}` 通配尾段（仅最后一段，匹配剩余全部段，`req.pathParam("path")` 取整段）；重复路径注册抛错。

```csharp
SLang.Server.onGet( "/user/{id}", function( SLang.Request req, SLang.Response res )
{
    Int32 id = req.pathInt( "id", 0 )
    res.text( "id=" + id.toString() )
} )
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
| `form(name)` / `formInt` / `formBool` / `hasForm` | `application/x-www-form-urlencoded` 表单字段（multipart 普通字段同表并入） |
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
```

## 中间件与插件（P2）

中间件 = 三参 Function（注册序即执行序；onion 模型：调 `nx.go()` 放行，`go()` 之后的代码 = 后置环；不调 = 短路；重复调 `go()` no-op）：

```csharp
SLang.Server.use( function( SLang.Request req, SLang.Response res, SLang.Next nx )
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

插件 = `ServerPlugin` 子类（`onInstall` 在 `use()` 时立即执行 = 注册点；`onStart`/`onStop` 随 start/stop；`onWsOpen`/`onWsClose` 会话钩子广播）：

```csharp
class MyPlugin : SLang.ServerPlugin
{
    override void onInstall()          # 注册中间件/路由就在这里（立即生效）
    {
        SLang.Server.onGet( "/mark", function( SLang.Request req, SLang.Response res ) { ... } )
    }
    override void onStart() { ... }
    override void onStop()  { ... }
}
SLang.Server.use( MyPlugin() )
```

内置插件（`SLang.Plugins`）：

```csharp
SLang.Server.use( SLang.Plugins.logger() )                    # 请求日志
SLang.Server.use( SLang.Plugins.cors() )                      # CORS：预检 OPTIONS → 204 + Access-Control-Allow-* 头
SLang.Server.use( SLang.Plugins.staticFiles( "./public" ) )   # 静态目录：GET 直出（HEAD 放行）、扩展名定 MIME
```

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

`start()` 时自动挂载 `GET /docs`（自包含 HTML 页面：接口分组/参数/示例/GET 试一试，零外链）与 `GET /openapi.json`（OpenAPI 3.0.3）；用户已注册同路径则让位；`SLang.Server.docs( false )` 关闭（生产建议；`reset()` 恢复默认开）。

文档元数据在注册时顺手填（返回 `RouteInfo`，链式）：

```csharp
SLang.Server.onGet( "/api/user/{id}", hUser )
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
Int32 added = SLang.Server.importOpenApi( "api-spec.json" );
# 未注册路径 → 文档路由（/docs 可见、命中 501；返回新建数）
# 已注册路径 → 仅合并 summary/tags/param/security 元数据
# 后续 onGet(...) 同名注册自动顶替 + 继承文档元数据（设计先行工作流）
```

## 认证（P3）

三种挂法（`SLang.Plugins`；通过 → 身份写 `req.auth`，未通过 → 401 短路）：

```csharp
# ① 通用回调：收整个 req，任意 header 组合；ret 身份对象 / ret null
SLang.Server.use( SLang.Plugins.auth( function( SLang.Request req )
{
    string t1 = req.header( "X-Token" )
    string t2 = req.header( "X-Sign" )
    if t1 == null || t2 == null { ret null }
    ret checkSign( t1, t2 )
} ) );

# ② Bearer：Authorization: Bearer <token> → Jwt.decode → req.auth = JwtClaims
SLang.Server.use( SLang.Plugins.authBearer().skip( "/api/login" ).ws( true ) );

# ③ API Key：自定义 header 名 + key 校验回调
SLang.Server.use( SLang.Plugins.authApiKey( "X-API-Key", function( string key )
{
    ret loadAccountByKey( key )        # 身份对象 或 null
} ) );
```

- `.skip( path )`：公开路径白名单（精确匹配、链式多次）——未声明 = 全站锁死（最安全默认）；
- `.ws( true )`：WS 升级 token 接管（浏览器 WS 无法自定义头 → token 走 `?token=` 查询参数；失败即关会话；仅 bearer/apiKey 模式）；
- Bearer 模式 401 附 `WWW-Authenticate: Bearer` 头（RFC 6750）；
- **授权不做框架**：handler 内读 `req.auth as SLang.JwtClaims` 自判（403）。

**Jwt claims 读取**（不验签——sign/verify 挂靠未来 crypto 库留 P5+；仅用于己方签发且签验发生在别处的同源身份读取）：

```csharp
SLang.JwtClaims c = SLang.Jwt.decode( "eyJhbGciOi..." );  # 格式非法 → null
c.subject;         # "sub"（缺失 null）
c.expiresAt;       # "exp" → Int64 秒（缺失 0）
c.expired;         # 现时 > exp（exp 缺失恒 false）——decode 不自动拒
c.claim( "uid" );  # 任意自定义 claim（缺失 null）
```

**其他 P3 插件**：`SLang.Plugins.bodyLimit( limitBytes )`（应用级 body 上限收紧，超限 413）；`SLang.Plugins.requestId()`（X-Request-Id 响应头，Guid）；`ServerConfig.maxConnections = 1024`（并发连接上限，超出 503）。

## WebSocket

形态 A——HTTP 进程内升级（同端口，`app.websocket(path, handler)`）：

```csharp
SLang.Server.websocket( "/ws/{room}", function( SLang.WsSession s )
{
    SLang.WsMessage m = s.receive()          # 循环收；null = 对端关闭
    if m != null && m.isText
    {
        s.sendText( "echo: " + m.text )      # s.pathParam("room") / s.query("name") 可用
    }
} )
```

形态 B——独立端口（`SLang.WebSocketServer`）：

```csharp
SLang.WebSocketServer.onMessage( function( SLang.WsSession s, SLang.WsMessage m ) { ... } )
SLang.WebSocketServer.onClose( function( SLang.WsSession s ) { ... } )
SLang.WebSocketServer.start( 9090 )
# SLang.WebSocketServer.sessions() / broadcast(text) / stop() / isRunning / port
```

全局辅助：`SLang.Server.sessions(path)` 列在线会话、`SLang.Server.broadcast(path, text)` 群发。

事件式糖（不想写收发循环时；内部仍是一协程）：

```csharp
SLang.Server.wsEvents( "/chat/{room}" )
    .onOpen(    function( SLang.WsSession s ) { ... } )                     # s.pathParam("room") 可用
    .onMessage( function( SLang.WsSession s, SLang.WsMessage m ) { ... } )   # 每帧一调
    .onClose(   function( SLang.WsSession s ) { ... } )
```

## 生命周期与配置

```csharp
SLang.Server.configure( cfg )   # ServerConfig：maxBodyBytes/maxHeaderBytes/backlog
                                #   上传上限（P1.5）：maxUploadBytes=100MB / maxFileBytes=50MB
                                #   handlerTimeoutMs：handler/中间件超时（0 = 不限；流式连接豁免）
SLang.Server.start( 8080 )      # 后台启动（协程接受连接）
SLang.Server.awaitStop()        # 等待 stop
SLang.Server.stop()             # 关监听 + 强制断开在途连接（触发 onClose）
SLang.Server.reset()            # 清全部路由（下一轮测试复用）
SLang.Server.isRunning
```

handler/中间件内抛异常：已暂存响应照常写出（首个响应胜出），未响应则 500 + 断连；流式头已发则兜底终止块 + 断连。

## 编译与运行

```powershell
# 库改动后先编库，再编消费工程（顺序不可颠倒）
dotnet run --project simple_language\source\SimpleLanguageFront.csproj -- compile -e ir -p SlangAllInOne\SLangCore\Lib\SLang\Server\Server.sp --format binary+json --no-banner
dotnet run --project simple_language\source\SimpleLanguageFront.csproj -- compile -e ir -p SlangAllInOne\SLangCore\test\ExpendTest\ProjectTest.sp --format binary+json --no-banner
csimple_lang.exe run SlangAllInOne\out\export\ProjectTest\ProjectTest.module.json
```
