# WebSocketServer.sl

> 源文件：`WebSocketServer.sl`

## class `_WsSessions`

- **说明**：SLang/Server/WebSocketServer.sl — WsSession / 会话注册表 / WebSocket 服务（实例双形态） 设计契约：SERVER_DESIGN.md §4.6 / §6.8 WsSession：包装 Net.WebSocketStream + 会话标识 + 路由信息（路径参数 / 查询参数与 HTTP 路由同一套 {param} 语法）；模块内构造（引擎升级分流 / 独立服务 accept 后创建），跨模块字段/方法消费（HttpResponse 安全模式）。 注册表：按 pattern 分组（sessions/broadcast 的底座）。 WebSocketServer（2026-10-26 自静态门面转实例形态——服务器类按协议 分工，WS 侧 API 整体收口到本类；原 SLang.Server 上的 websocket/ wsEvents/sessions/broadcast 四方法随之迁移）： 形态 A（HTTP 同端口升级）：无参构造——依附 HttpServer 的监听端口， 注册升级路由（websocket/wsEvents）+ 会话查询/组播； 形态 B（独立端口）：带端口构造——裸 TCP 直握手，不经 HTTP 层， onMessage/onClose 回调 + 自有生命周期。 两形态 idleTimeout(ms) 统一配置 WS 空闲心跳（升级形态写 ServerConfig.wsIdleTimeoutMs、独立形态写本服务字段）。 v1 语义说明：引擎与会话注册表均为模块级静态（C VM 跨模块多实例化 实例态隔离不可靠，[2026-10-17] 复盘 ①；§19 Server→HttpServer 实例 门面同款薄壳纪律）——实例方法只是转发层，状态跨实例共享，单 VM 单 WS 服务语义。 ── 会话注册表（内部静态；pattern → List<WsSession>）──

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `static Map&lt;string, object&gt; _byPattern = null` | 字段 Map（类型见签名）。 |
| 方法 | `void _ensure()` | 执行 _ensure()。 |
| 方法 | `void register(string pattern, WsSession s)` | 执行 register(pattern, s)，行为详见源实现。 |
| 方法 | `void unregister(string pattern, WsSession s)` | 执行 unregister(pattern, s)，行为详见源实现。 |
| 方法 | `List&lt;WsSession&gt; sessions(string pattern)` | 在线会话快照（该 pattern 全部会话）。 注意：struct 登记类的方法体内 List.add 链解析失败（Front Meta 层， _SrvUtil 头注记同款）——拷贝循环收进本内部类（sessions 是内部类方法） |
| 方法 | `void _copySessions(List&lt;WsSession&gt; src, List&lt;WsSession&gt; dst)` | 会话拷贝（内部类方法：List.add 在内部类内可解析） |
| 方法 | `Int32 broadcast(string pattern, string text)` | 组播文本（已断会话 try? 吞错跳过） |
| 方法 | `Int32 broadcastBinary(string pattern, ByteBuffer payload)` | 组播二进制（P6，§4.6 broadcast binary 重载；已断会话跳过） |
| 方法 | `Int32 broadcastTag(string pattern, string tag, string text)` | 定向组播文本（P6，§4.6：只发带 tag 标签的会话——s.tag 打标） |
| 方法 | `Int32 broadcastTagBinary(string pattern, string tag, ByteBuffer payload)` | 定向组播二进制（P6，§4.6） |
| 方法 | `void tagSession(WsSession s, string name)` | ── 会话标签（P6，§4.6 定向广播底座；struct 登记类 WsSession 方法体内 List.add 链解析失败纪律——容器写操作全部收进本 内部类，_SrvUtil/_WsSessions 先例同款）── 打标签（幂等；null/空名忽略） |
| 方法 | `void untagSession(WsSession s, string name)` | 移除标签（无该标签 no-op） |
| 方法 | `bool sessionTagged(WsSession s, string name)` | 是否带该标签 |
| 方法 | `List&lt;string&gt; sessionTags(WsSession s)` | 标签快照（List&lt;string&gt; 拷贝） |
| 方法 | `bool _hasTag(List&lt;string&gt; ts, string name)` | 标签线性查找（标签数少，无需哈希集） |

## class `WsSession`

- **说明**：WsSession — WebSocket 会话（模块内构造；用户侧只消费）

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `string _id = ""` | 会话标识（GUID 字符串；注册表键） |
| 字段 | `string _remote = ""` | 对端地址（"ip:port"） |
| 字段 | `string _pattern = ""` | 命中的路由 pattern（注册表分组键） |
| 字段 | `Map&lt;string,string&gt; _pathParams = null` | 升级 URL 的路径参数 |
| 字段 | `string _rawQuery = ""` | 升级 URL 原始 query（惰性解码） |
| 字段 | `Map&lt;string,string&gt; _queryParsed = null` | 字段 _queryParsed（类型见签名）。 |
| 字段 | `Int64 _lastActive = 0` | ── 空闲心跳（P5，§6.8）── 最后活跃时刻（receive 返回时刷新；构造即 now） |
| 字段 | `Int32 _idleMs = 0` | 空闲超时毫秒（引擎/独立服务接线时写入；&lt;= 0 = 不启用） |
| 字段 | `bool _watchdogOn = false` | 看门狗已启动（防重复 spawn） |
| 字段 | `List&lt;string&gt; _tags = null` | ── 会话标签（P6，§4.6 定向广播底座；惰性建表，写操作经 _WsSessions 内部类——struct 登记类 List.add 纪律）── |
| 构造 | `_init_(Net.WebSocketStream ws, string pattern, Map&lt;string,string&gt; pathParams, string rawQuery)` | 引擎/独立服务内部构造（用户勿直接 new） |
| 方法 | `void _startHeartbeat(Int32 idleMs)` | 空闲心跳配置 + 看门狗启动（引擎在会话注册后调用；idleMs &lt;= 0 不启用）。 语义：空闲超过 idleMs（无任何入站消息）→ 看门狗主动 close 会话 （handler 的 receive 随之返回 null 自然收尾）；对端主动 Ping 的 autoPong 回帧发生在 handler 协程（receive 循环内），与看门狗的 close 写帧存在极小交错窗口（单 VM 非抢占，仅在写挂起点切换）， v1 接受——写锁留后续。 |
| 方法 | `void _watchdogLoop(WsSession s)` | 看门狗协程体：周期检查空闲；超时关会话后退出（会话先关也退出） |
| 属性 | `get string id()` | ── 会话标识 ── |
| 属性 | `get string remoteAddress()` | 获取 remoteAddress 的值。 |
| 属性 | `get string routePattern()` | 命中的路由 pattern（注册/broadcast 分组键） |
| 方法 | `string pathParam(string name)` | ── 升级 URL 参数（与 HTTP 路由同一套 {param} 语法）── 路径段参数；不存在返回 null |
| 方法 | `Int32 pathInt(string name, Int32 defVal)` | 路径参数 Int32 化；坏格式用 defVal |
| 方法 | `string query(string name)` | 查询参数（已解码：percent-decode + '+'→空格）；不存在返回 null |
| 方法 | `void tag(string name)` | ── 会话标签（P6，§4.6：定向广播 broadcastTag 按标签过滤； 容器写操作经 _WsSessions 内部类——struct 登记类 List.add 纪律）── 打标签（幂等；null/空名忽略） |
| 方法 | `void untag(string name)` | 移除标签（无该标签 no-op） |
| 方法 | `bool tagged(string name)` | 是否带该标签 |
| 属性 | `get List&lt;string&gt; tags()` | 标签快照（List&lt;string&gt; 拷贝） |
| 方法 | `void sendText(string text)` | 执行 sendText(text)，行为详见源实现。 |
| 方法 | `void sendBinary(ByteBuffer payload)` | 二进制（底层 slice 视图，src 不被读空） |
| 方法 | `void sendPing()` | 执行 sendPing()。 |
| 方法 | `void close()` | 优雅关闭（尽力发 Close 帧后关底层流） |
| 属性 | `get bool isOpen()` | 获取 isOpen 的值。 |

## class `WebSocketServer`

- **说明**：WebSocketServer — WebSocket 服务（实例形态，双形态） 形态 A（HTTP 同端口升级——依附 HttpServer 监听）： SLang.WebSocketServer ws = SLang.WebSocketServer(); ws.websocket( "/chat", function( SLang.WsSession s ) { ... } ); ws.wsEvents( "/tick" ).onOpen( fn ).onMessage( fn ).onClose( fn ); ws.sessions( "/chat" ); ws.broadcast( "/chat", text ); # HttpServer.start() 后升级路由生效（Upgrade 分流在引擎层） 形态 B（独立端口——裸 TCP 直握手，不经 HTTP 层；§4.6 形态 B）： SLang.WebSocketServer wss = SLang.WebSocketServer( 9090 ); wss.onMessage( function( SLang.WsSession s, Net.WsMessage m ) { ... } ); wss.onClose(  function( SLang.WsSession s ) { ... } ); wss.start();                          # 或 run( port ) 阻塞形态 wss.sessions(); wss.broadcast( text ); 两形态通用：idleTimeout( ms ) 空闲心跳（升级形态写 ServerConfig， 独立形态写本服务字段）。 静态状态保留（v1 单 VM 单 WS 服务语义，§19 实例门面同款薄壳纪律）。

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `public Int32 port = 0` | 独立监听端口（构造入参；0 = 形态 A——不独立监听，仅升级路由注册器） |
| 字段 | `static Int32 _listenPort = 0` | ── 独立形态静态状态（模块级单例；实例方法转发）── |
| 字段 | `static bool _running = false` | 字段 bool（类型见签名）。 |
| 字段 | `static Task _acceptTask = null` | 字段 Task（类型见签名）。 |
| 字段 | `static Function _onMessage = null` | function( WsSession s, Net.WsMessage m )；消息回调（msg 归回调所有， 消费完调 m.release()；WebSocketClient.onMessage 先例） |
| 字段 | `static Function _onClose = null` | function( WsSession s )；会话收尾回调（可选） |
| 字段 | `static Int32 _idleTimeoutMs = 0` | WS 会话空闲超时毫秒（P5，§6.8；&lt;= 0 不启用；start 前生效） |
| 方法 | `string _key()` | 本服务在线会话注册键（sessions/broadcast 底座）。 静态 string 字面量默认值初始化不可靠（[2026-10-17] 复盘 ② 同族）， 经方法返回字面量（模块内字符串常量可靠） |
| 方法 | `void _init_()` | ── 构造 ── 形态 A：HTTP 同端口升级路由器（依附 HttpServer 监听；无独立端口） |
| 方法 | `void _init_(Int32 port)` | 形态 B：独立端口 WS 服务（裸 TCP 直握手） |
| 方法 | `RouteInfo websocket(string path, Function handler)` | ── 形态 A：HTTP 同端口升级路由（§4.6 形态 A）── WS 升级路由注册（HTTP 引擎 Upgrade 分流命中后进 handler）。 handler 签名约定：function( SLang.WsSession s )；会话协程内 循环 s.receive()（null = 关闭），消息消费完调 m.release() |
| 方法 | `WsEventBuilder wsEvents(string path)` | 事件式 WS 路由糖：wsEvents( path ).onOpen(fn).onMessage(fn).onClose(fn) （内部仍是一协程；onMessage 回调内消费完消息调 m.release()） |
| 方法 | `List&lt;WsSession&gt; sessions(string path)` | 该 WS 路由的在线会话快照 |
| 方法 | `Int32 broadcast(string path, string text)` | 组播文本到该 WS 路由（返回送达会话数；已断会话跳过） |
| 方法 | `Int32 broadcast(string path, ByteBuffer payload)` | 组播二进制到该 WS 路由（P6，§4.6 binary 重载；返回送达会话数） |
| 方法 | `Int32 broadcastTag(string path, string tag, string text)` | 定向组播文本（P6，§4.6：只发带 tag 标签的会话——s.tag 打标； 返回送达数） |
| 方法 | `Int32 broadcastTag(string path, string tag, ByteBuffer payload)` | 定向组播二进制（P6，§4.6；返回送达数） |
| 方法 | `void onMessage(Function fn)` | ── 形态 B：独立端口生命周期（§4.6 形态 B）── 消息回调（2 参：会话 + 消息；msg 归回调所有） |
| 方法 | `void onClose(Function fn)` | 会话收尾回调（1 参：会话） |
| 属性 | `get bool isRunning()` | 获取 isRunning 的值。 |
| 方法 | `void start(Int32 port)` | 启动独立监听（端口 = 构造端口 / 本方法覆盖；立即返回，accept 循环独立协程） |
| 方法 | `void start()` | 启动独立监听（端口 = 构造端口） |
| 方法 | `void _startInternal()` | 内部启动体（静态；端口取 _listenPort） |
| 方法 | `void stop()` | 停止：关监听 + 关全部会话（会话协程随 receive null 自然收尾注销） |
| 方法 | `void awaitStop()` | 挂起直至停止 |
| 方法 | `void run(Int32 port)` | run = start + awaitStop（阻塞当前协程直至 stop） |
| 方法 | `List&lt;WsSession&gt; sessions()` | ── 形态 B：独立端口会话查询 / 组播（无参重载）── 独立端口全部在线会话快照 |
| 方法 | `Int32 broadcast(string text)` | 组播文本到独立端口全部会话（返回送达数） |
| 方法 | `Int32 broadcast(ByteBuffer payload)` | 组播二进制到独立端口全部会话（P6，§4.6；返回送达数） |
| 方法 | `Int32 broadcastTag(string tag, string text)` | 定向组播文本（P6，§4.6：只发带 tag 标签的会话；返回送达数） |
| 方法 | `Int32 broadcastTag(string tag, ByteBuffer payload)` | 定向组播二进制（P6，§4.6；返回送达数） |
| 方法 | `void idleTimeout(Int32 idleTimeoutMs)` | ── 两形态通用：WS 空闲心跳（P5，§6.8）── 空闲超时配置：无入站消息超过 ms 即断开会话（&lt;= 0 不启用）。 形态 A（升级路由）：写 ServerConfig.wsIdleTimeoutMs（HttpServer 须已构造——时序：先 HttpServer( port ) 再本调用）； 形态 B（独立端口）：写本服务字段（start 前生效） |
| 方法 | `void _acceptLoop(Net.TcpServer srv)` | ── 内部：accept 循环（每连接一协程：握手 → 会话循环 → 收尾）── |
| 方法 | `void _runSession(Net.TcpStream client)` | 单连接会话：握手 → WsSession → 消息循环（onMessage）→ 收尾（onClose） |

## class `_WsEventRoutes`

- **说明**：WsEventBuilder — WS 事件式糖（P2，§4.6：wsEvents(path).onOpen(...) .onMessage(...).onClose(...)；内部仍是一协程，适合不想写循环的场景） WebSocketServer.wsEvents(path) 构造：构造期注册 WS 路由，会话回调经 静态注册表按 pattern 反查分发（闭包零捕获纪律，P0 复盘）。 回调签名：onOpen/onClose = function( WsSession s )； onMessage = function( WsSession s, Net.WsMessage m )——消息归回调 所有，消费完调 m.release()（§4.7 示例同款约定）。

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `static Map&lt;string, object&gt; _byPattern = null` | pattern → WsEventBuilder（静态注册表） |
| 方法 | `void register(string pattern, WsEventBuilder b)` | 执行 register(pattern, b)，行为详见源实现。 |
| 方法 | `WsEventBuilder find(string pattern)` | 获取 / 读取（find）。 |

## class `WsEventBuilder`

- **说明**：SLang 标准库类型 WsEventBuilder（详见源文件）。

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `string _pattern = ""` | 字段 _pattern（类型见签名）。 |
| 字段 | `Function _onOpen = null` | 字段 _onOpen（类型见签名）。 |
| 字段 | `Function _onMessage = null` | 字段 _onMessage（类型见签名）。 |
| 字段 | `Function _onClose = null` | 字段 _onClose（类型见签名）。 |
| 构造 | `_init_(string path)` | 构造即注册 WS 路由（WebSocketServer.wsEvents 调用；用户勿直接 new） |
| 方法 | `WsEventBuilder onOpen(Function fn)` | ── 链式事件注册 ── |
| 方法 | `WsEventBuilder onMessage(Function fn)` | 执行 onMessage(fn)，行为详见源实现。 |
| 方法 | `WsEventBuilder onClose(Function fn)` | 执行 onClose(fn)，行为详见源实现。 |
| 方法 | `void _serve(WsSession s)` | 会话服务（注册的 WS 路由回调；单协程——open → 消息循环 → close） |
