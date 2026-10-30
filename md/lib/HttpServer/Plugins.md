# Plugins.sl

> 源文件：`Plugins.sl`

## class `_LoggerPlugin`

- **说明**：SLang/Server/Plugins.sl — 内置插件门面（P2） 设计契约：SERVER_DESIGN.md §4.7（内置插件路线：logger / cors / staticFiles；P3 增 bodyLimit/requestId/auth，P5 增 rateLimit） 用法（一行装一个插件，产物为普通 ServerPlugin 子类，经 app.use 注册）： var app = SLang.HttpServer( 8080 ); app.use( SLang.Plugins.logger() ); app.use( SLang.Plugins.cors() ); app.use( SLang.Plugins.staticFiles( "./www" ) ); 实现约束：中间件闭包零捕获（P0 复盘纪律）——staticFiles 的 root 经 静态字段传递（v1 单实例：重复注册后者覆盖前者，P2 实录记录）； 中间件逻辑收进静态方法、闭包只做转发；onInstall 内注册走引擎级 静态通道 HttpServerCore.use（插件无门面实例引用——闭包/插件 零捕获纪律，Server.sl 门面注记同源）。 ── logger：请求日志（方法/路径/状态/耗时）──

| 类型 | 签名 | 说明 |
|------|------|------|
| 方法 | `void onInstall()` | 执行 onInstall()。 |
| 方法 | `void _serve(SLang.Request req, SLang.Response res, SLang.Next nx)` | 执行 _serve(req, res, nx)，行为详见源实现。 |

## class `_CorsPlugin`

- **说明**：── cors：跨域（自动应答 OPTIONS 预检 + 放行头）──

| 类型 | 签名 | 说明 |
|------|------|------|
| 方法 | `void onInstall()` | 执行 onInstall()。 |
| 方法 | `void _serve(SLang.Request req, SLang.Response res, SLang.Next nx)` | 执行 _serve(req, res, nx)，行为详见源实现。 |

## class `_StaticFilesPlugin`

- **说明**：── staticFiles：静态目录服务（root 下文件直出；仅 GET）──

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `static string _root = ""` | 静态根目录（闭包零捕获纪律：root 经静态字段传递；v1 单实例， 重复注册后者覆盖前者） |
| 构造 | `_init_(string root)` | 构造方法，初始化本类型实例。 |
| 方法 | `void onInstall()` | 执行 onInstall()。 |
| 方法 | `void _serve(SLang.Request req, SLang.Response res, SLang.Next nx)` | 执行 _serve(req, res, nx)，行为详见源实现。 |
| 方法 | `bool _hasDotDot(string path)` | '..' 独立路径段检测（前后为 '/' 或串首尾；"file..txt" 不误杀） |

## class `_SwaggerUIPlugin`

- **说明**：── swaggerUI（P9 收官，§10 风险 #8）：Swagger UI 静态包托管 ── 路由：GET /swagger → 自研 index（外链 dist 资产 + /openapi.json）； GET /swagger/<file> → dist 目录文件直出。 让位约定（/docs 同款）：用户已注册 GET /swagger 则本插件不接管， 由用户路由应答（findExact 先查 + ret 让位）。

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `static string _dist = ""` | 闭包零捕获纪律：dist 目录经静态字段传递（v1 单实例，后者覆盖） |
| 构造 | `_init_(string distDir)` | 构造方法，初始化本类型实例。 |
| 方法 | `void onInstall()` | 执行 onInstall()。 |
| 方法 | `void _serve(SLang.Request req, SLang.Response res, SLang.Next nx)` | 执行 _serve(req, res, nx)，行为详见源实现。 |
| 方法 | `void _serveIndex(SLang.Response res)` | GET /swagger：自研 index 直出（让位检查在 _serve 运行期做： 中间件先于路由执行，findExact 命中用户路由则已放行至此） |
| 方法 | `string _indexPage()` | index.html（外链 dist 资产 + /openapi.json；零自包含） 约束：长字符串一律 StringBuilder 逐段追加（"+" 链截断）；若 JS 需要 "$" 须经 String.fromCharCode(36) 运行期生成（"$" 是 SL 插值前缀， 本页恰好不含） |

## class `_BodyLimitPlugin`

- **说明**：── bodyLimit（P3，§4.7）：场景化 body 上限收紧（低于全局 maxBodyBytes 的应用级限制；超限 413 ApiResult 短路）──

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `static Int64 _limit = 0` | 闭包零捕获纪律：限额经静态字段传递（v1 单实例，后者覆盖前者） |
| 构造 | `_init_(Int64 limitBytes)` | 构造方法，初始化本类型实例。 |
| 方法 | `void onInstall()` | 执行 onInstall()。 |
| 方法 | `void _serve(SLang.Request req, SLang.Response res, SLang.Next nx)` | 执行 _serve(req, res, nx)，行为详见源实现。 |

## class `_RequestIdPlugin`

- **说明**：── requestId（P3，§4.7）：X-Request-Id 响应头（Guid；请求追踪）──

| 类型 | 签名 | 说明 |
|------|------|------|
| 方法 | `void onInstall()` | 执行 onInstall()。 |
| 方法 | `void _serve(SLang.Request req, SLang.Response res, SLang.Next nx)` | 执行 _serve(req, res, nx)，行为详见源实现。 |

## class `_RateBucket`

- **说明**：── rateLimit（P5，§4.7）：按客户端 IP 固定窗口限流 ── 窗口内请求数超 max → 429 + Retry-After（剩余秒）短路； 桶表懒清理（每 256 次判定顺带清一遍过期桶，防内存增长）。 v1 单实例（静态字段态，多 rateLimit 插件后者覆盖——staticFiles 同款纪律）。

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `Int64 _start = 0` | 字段 _start（类型见签名）。 |
| 字段 | `Int32 _count = 0` | 字段 _count（类型见签名）。 |
| 构造 | `_init_()` | 构造方法，初始化本类型实例。 |

## class `_RateLimitPlugin`

- **说明**：SLang 标准库类型 _RateLimitPlugin（详见源文件）。

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `static Int32 _max = 0` | 字段 Int32（类型见签名）。 |
| 字段 | `static Int32 _windowMs = 60000` | 字段 Int32（类型见签名）。 |
| 字段 | `static Map&lt;string, object&gt; _buckets = null` | 桶表（值 object 持有 + as 转型——Map&lt;string,_RateBucket&gt; 值为 模块内部类时 Front 泛型解析失败，_WsSessions 同款规避） |
| 字段 | `static Int32 _sweepCounter = 0` | 字段 Int32（类型见签名）。 |
| 构造 | `_init_(Int32 maxRequests, Int32 windowMs)` | 构造方法，初始化本类型实例。 |
| 方法 | `void onInstall()` | 执行 onInstall()。 |
| 方法 | `void _serve(SLang.Request req, SLang.Response res, SLang.Next nx)` | 执行 _serve(req, res, nx)，行为详见源实现。 |
| 方法 | `void _sweepExpired(Int64 now)` | 过期桶清理（窗口已翻转的桶整表移除；Map 无遍历删除——键快照后逐删） |

## class `_AuthPlugin`

- **说明**：── auth（P3，§4.11）：认证插件——三挂法共用一类 ── mode 0 = 通用回调（收整个 req）；1 = Bearer 预设（Jwt.decode）； 2 = API Key 预设（自定义 header 名 + key 校验回调）。 通过 → 身份写 req.auth + 放行；未通过 → 401 ApiResult 短路 （Bearer 模式附 WWW-Authenticate: Bearer，RFC 6750）。 .skip(path) = 公开路径白名单（精确匹配，可链式；未声明 = 全站锁死）； .ws(true) = WS 升级 token 查询参数接管（onWsOpen 钩子校验， 失败即关会话；仅 bearer/apiKey 两模式，通用回调无 req 可用）。 v1 单实例（静态字段态，多 auth 插件后者覆盖——staticFiles 同款纪律）。

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `static Int32 _mode = 0` | 字段 Int32（类型见签名）。 |
| 字段 | `static Function _validator = null` | 通用回调 Function(Request)-&gt;object / API Key 回调 Function(string)-&gt;object |
| 字段 | `static string _apiKeyHeader = ""` | 字段 string（类型见签名）。 |
| 字段 | `static List&lt;string&gt; _skips = null` | 字段 List（类型见签名）。 |
| 字段 | `static bool _ws = false` | 字段 bool（类型见签名）。 |
| 构造 | `_init_(Int32 mode, Function validator, string apiKeyHeader)` | 构造方法，初始化本类型实例。 |
| 方法 | `ServerPlugin skip(string path)` | 公开路径白名单（链式；override 基类占位——返回类型须一致为 ServerPlugin，跨模块链式调用按基类签名决议） |
| 方法 | `ServerPlugin ws(bool on)` | WS 升级 token 接管开关（链式；同上 override 基类签名） |
| 方法 | `void onInstall()` | 执行 onInstall()。 |
| 方法 | `void onWsOpen(WsSession s)` | WS 升级校验（§4.11 落点 B：浏览器 WS 无法自定义头 → token 走 查询参数；onWsOpen 引擎广播触发，失败即关会话） |
| 方法 | `object _wsIdent(string token)` | token → 身份（bearer 解 JWT / apiKey 走校验回调；通用模式不适用） |
| 方法 | `void _serve(SLang.Request req, SLang.Response res, SLang.Next nx)` | 执行 _serve(req, res, nx)，行为详见源实现。 |
| 方法 | `void _deny(SLang.Response res, bool bearer)` | 401 应答（Bearer 模式附 WWW-Authenticate 头；RFC 6750） |

## class `Plugins`

- **说明**：Plugins — 内置插件工厂门面（静态；产物为普通 ServerPlugin 子类）

| 类型 | 签名 | 说明 |
|------|------|------|
| 方法 | `ServerPlugin logger()` | 请求日志（方法/路径/状态/耗时，[server] 前缀） |
| 方法 | `ServerPlugin cors()` | CORS（OPTIONS 预检 204 短路 + Access-Control-Allow-Origin: *） |
| 方法 | `ServerPlugin staticFiles(string root)` | 静态目录服务（root 下文件按扩展名 MIME 直出；仅 GET；'..' 段 403） |
| 方法 | `ServerPlugin swaggerUI(string distDir)` | Swagger UI 静态包托管（P9 收官）：GET /swagger 自研 index（外链 dist 资产 + /openapi.json）；GET /swagger/&lt;file&gt; 直出 dist 目录； 用户已注册 GET /swagger 让位（/docs 同款约定）；v1 单实例后者覆盖 |
| 方法 | `ServerPlugin bodyLimit(Int64 limitBytes)` | body 上限收紧（P3；超限 413；v1 单实例后者覆盖） |
| 方法 | `ServerPlugin requestId()` | X-Request-Id 响应头（P3；Guid 生成，请求追踪） |
| 方法 | `ServerPlugin rateLimit(Int32 maxRequests, Int32 windowMs)` | 按客户端 IP 固定窗口限流（P5；窗口内超 max → 429 + Retry-After； windowMs 缺省 60000；v1 单实例后者覆盖） |
| 方法 | `ServerPlugin rateLimit(Int32 maxRequests)` | 按客户端 IP 固定窗口限流（60 秒窗口便捷形态） |
| 方法 | `ServerPlugin auth(Function validator)` | 通用认证（P3，§4.11 ①）：回调收整个 req，ret 身份对象 / ret null |
| 方法 | `ServerPlugin authBearer()` | Bearer 预设（§4.11 ②）：Authorization: Bearer &lt;token&gt; → Jwt.decode → req.auth = JwtClaims；.skip/.ws 链式 |
| 方法 | `ServerPlugin authApiKey(string headerName, Function validator)` | API Key 预设（§4.11 ③）：自定义 header 名 + key 校验回调 |
