# Plugin.sl

> 源文件：`Plugin.sl`

## class `Next`

- **说明**：SLang/Server/Plugin.sl — 中间件管道与插件模型（P2） 设计契约：SERVER_DESIGN.md §4.7 / §6.9 模型： - 中间件 = 单个三参 Function：function( SLang.Request req, SLang.Response res, SLang.Next nx )——next 是关键字 → SLang.Next 类型令牌 + nx.go() 放行（§2.3 语言约束）； - 插件 = ServerPlugin 子类（可携带多条注册），onInstall 在 use() 时 立即执行（§6.9）； - 管道：连接协程内联执行（onion 同步嵌套——后置环在 handler 协程 awaitTask 返回后自然回程；中间件自身可 await，§4.7）；最内环 = handler 协程派发（或 404/405 尾环应答——未匹配请求同样过管道， staticFiles/CORS 预检依赖此语义）； - 幂等：nx.go() 重复调用 no-op（防双派发）；未调 go() = 短路 （中间件必须经 res.* 写响应或短路，§6.9 规则）。 与设计的偏差：onInstall() 无参（设计的 onInstall(app) 传实例——维持 无参：插件注册走引擎级静态通道 HttpServerCore.use / .onGet 等，门面 SLang.HttpServer 已转实例形态但插件 onInstall 无实例引用可用，语义等价 （Server.sl 门面注记同源）。 Next — 中间件放行令牌（模块内构造；用户侧只调 nx.go()）

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `_Pipeline _pipe = null` | 字段 _pipe（类型见签名）。 |
| 字段 | `Int32 _idx = 0` | 字段 _idx（类型见签名）。 |
| 字段 | `bool _gone = false` | 字段 _gone（类型见签名）。 |
| 构造 | `_init_(_Pipeline pipe, Int32 idx)` | 构造方法，初始化本类型实例。 |
| 方法 | `void go()` | 放行进下一环；最内环 = handler 派发（或 404/405 应答）。 幂等：已放行后的重复调用 no-op |

## class `ServerPlugin`

- **说明**：ServerPlugin — 插件基类（钩子默认空实现；子类 override 重写—— SL 无 virtual 关键字，成员方法默认可被子类重写，§2.3 ⑧）

| 类型 | 签名 | 说明 |
|------|------|------|
| 方法 | `void onInstall()` | 注册中间件/路由/钩子的唯一入口（use(plugin) 时立即执行） |
| 方法 | `void onStart()` | start 后、accept 前 |
| 方法 | `void onStop()` | stop 收尾 |
| 方法 | `void onWsOpen(WsSession s)` | WS 会话级钩子（对所有插件广播调用，§6.9） |
| 方法 | `void onWsClose(WsSession s)` | 执行 onWsClose(s)，行为详见源实现。 |
| 方法 | `ServerPlugin skip(string path)` | ── 链式配置占位（P3，§4.11）：基类返回自身 no-op，子类 override── 静态工厂返回类型是 ServerPlugin（跨模块子类上行赋型纪律）， 链式 .skip()/.ws() 须经基类签名可见；auth 之外插件调用为 no-op。 |
| 方法 | `ServerPlugin ws(bool on)` | 执行 ws(on)，行为详见源实现。 |

## class `_Pipeline`

- **说明**：_Pipeline — 管道执行器（内部；连接协程内联） 每环框架构造 Next 实例（内持下一环索引，§6.9——SL 无方法引用， 框架持索引逐环构造）；尾环透传引擎 _tail（handler 派发 / 404 / 405）。 返回值透传 _tail：true = 连接已收尾（超时断连路径，外层 break） P10：执行序 = 全局中间件（注册序）→ 路由级中间件（该 route 注册序， §6.9 裁剪项补齐）→ 尾环。索引空间连续：[0, _globalMw) 全局段、 [_globalMw, _mwCount) 路由段。

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `ServerConfig _cfg = null` | 字段 _cfg（类型见签名）。 |
| 字段 | `RouteInfo _route = null` | 字段 _route（类型见签名）。 |
| 字段 | `Int32 _noRoute = 0` | 0 = 有 handler；404 / 405 = 尾环应答模式 |
| 字段 | `Request _req = null` | 字段 _req（类型见签名）。 |
| 字段 | `Response _res = null` | 字段 _res（类型见签名）。 |
| 字段 | `bool _isHead = false` | 字段 _isHead（类型见签名）。 |
| 字段 | `Int32 _tag = 0` | 连接所在监听器 tag（多监听器 v1.1：尾环透传 _tail——405 Allow 生成按本监听器路由视图） |
| 字段 | `Int32 _mwCount = 0` | 字段 _mwCount（类型见签名）。 |
| 字段 | `Int32 _globalMw = 0` | 全局中间件段长（P10：路由级中间件紧随其后） |
| 构造 | `_init_(Net.TcpStream client, ServerConfig cfg, RouteInfo route, Int32 noRoute, Request req, Response res, bool isHead, Int32 tag)` | 构造方法，初始化本类型实例。 |
| 方法 | `bool _run()` | 管道入口（第 0 环起） |
| 方法 | `bool _runFrom(Int32 idx)` | 从第 idx 环继续（Next.go 入口）；idx == 中间件总数 → 尾环。 idx &lt; _globalMw → 全局表；否则路由段（route 可能为 null——防御 跳回尾环，未匹配请求（404/405）无路由级中间件） |

## class `_PluginHost`

- **说明**：_PluginHost — 中间件/插件宿主（内部静态；HttpServerCore 生命周期联动） 单 VM 协程调度无锁（§3 并发模型不变量）

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `static List&lt;Function&gt; _middlewares = null` | 中间件表（注册序即执行序） |
| 字段 | `static List&lt;object&gt; _plugins = null` | 插件表（生命周期/WS 钩子广播） |
| 方法 | `void _ensure()` | 执行 _ensure()。 |
| 方法 | `void addMiddleware(Function mw)` | 执行 addMiddleware(mw)，行为详见源实现。 |
| 方法 | `void addPlugin(ServerPlugin p)` | 执行 addPlugin(p)，行为详见源实现。 |
| 方法 | `void clear()` | 清空（HttpServerCore.reset 联动——stop 后重新配置场景） |
| 方法 | `Int32 middlewareCount()` | 执行 middlewareCount()。 |
| 方法 | `Function middlewareAt(Int32 i)` | 执行 middlewareAt(i)，行为详见源实现。 |
| 方法 | `void notifyStart()` | ── 钩子广播（单插件异常吞——不拖垮服务，§6.11 精神）── |
| 方法 | `void notifyStop()` | 执行 notifyStop()。 |
| 方法 | `void notifyWsOpen(WsSession s)` | 执行 notifyWsOpen(s)，行为详见源实现。 |
| 方法 | `void notifyWsClose(WsSession s)` | 执行 notifyWsClose(s)，行为详见源实现。 |
