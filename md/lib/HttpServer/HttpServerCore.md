# HttpServerCore.sl

> 源文件：`HttpServerCore.sl`

## class `_HttpParseResult`

- **说明**：SLang/Server/HttpServerCore.sl — HTTP/1.1 连接引擎（P0 → P1 → P1.5） 设计契约：SERVER_DESIGN.md §6.1 / §6.2 / §6.8 / §6.4-6.5（上传） 范围（P1）： - _HttpParser：请求行 / 头（行数与总字节双上限）/ body（Content-Length 精确读 | chunked 聚合 | 无则空）解析，预读缓冲跨 read 边界安全； - 响应编码：状态行 + Content-Type/Length/Connection + 用户头 + body； - keep-alive 循环（每连接一协程；Connection: close / HTTP/1.0 即断， 残留预读自然衔接下一条请求）； - handler 协程派发：spawnClosure2 独立协程 + waitTimeout 超时守护 （超时 cancel + 504 + 断连）+ awaitTask 等待（异常传播走 500 兜底）； - 路由：Router（{param} 段参数提取 / 404·405+Allow / ANY / HEAD 视同 GET / DuplicateRoute fail-fast）； - WS Upgrade 分流：Upgrade: websocket 命中 WS 路由 → 三参 accept （预读残留直传）→ WsSession 会话；未命中 / 握手失败 → 400。 范围（P1.5 上传）： - body 上限分流：multipart 请求按 maxUploadBytes 判 413（CL 与 chunked 两路），其余请求维持 maxBodyBytes（§6.4 第 5 步）； - multipart 即时解析：handler 派发前经 Request._ensureMultipart （构造期语义 §6.5）——单文件超 maxFileBytes → 413、boundary 缺失/格式坏 → 400，均优雅断连（协议层，§6.11）； - 请求级资源回收 _releaseRequest：body + multipart 文件内容缓冲 （UploadedFile._data）请求收尾统一回收（§6.5）。 范围（P2 管道与流式）： - 中间件管道：连接协程内联执行（onion 嵌套；中间件可 await，§6.9）， 尾环 = handler 协程派发 或 404/405 应答（未匹配请求同样过管道 ——staticFiles / CORS 预检依赖此语义）；_PluginHost 承载中间件与 插件（生命周期 / WS 钩子广播），reset 联动清空； - 流式响应三态写出：chunked（stream/sse——头已直发，引擎兜底 close）/ sendFile 直写完成（Content-Length 精确）/ 普通缓冲； handler 超时豁免：流式开启后 handlerTimeoutMs 不再掐（转无限 等待，写侧由连接级 writeTimeoutMs 守护，§6.1 / §6.6）。 随后阶段：P3 文档（OpenAPI/docs）+ 认证（auth 插件/Jwt）。 复用（不改动，G8 边界内）：Net.TcpServer / Net.TcpStream / Net.HttpHeaders / Net.WebSocketStream / Coroutine / ByteBuffer。语言纪律：get/set/next/ data/as/is/out/return 为关键字不作方法名与标识符；Function 字段先拷 局部再传参（HttpHeaders 头注记先例）；子类实参经局部赋型上行 （HttpTest 头注记先例）。 内部：请求解析结果（errorCode 0 = OK；400 / 413 / 431）

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `Int32 _errorCode = 0` | 字段 _errorCode（类型见签名）。 |
| 字段 | `string _method = ""` | 字段 _method（类型见签名）。 |
| 字段 | `string _path = ""` | 字段 _path（类型见签名）。 |
| 字段 | `string _rawQuery = ""` | 字段 _rawQuery（类型见签名）。 |
| 字段 | `bool _http10 = false` | 字段 _http10（类型见签名）。 |
| 字段 | `ByteBuffer _body = null` | 字段 _body（类型见签名）。 |
| 字段 | `Int64 _streamCl = 0` | ── 请求侧流式（P5，§6.6）── stopAtHead 形态：头区空行后停止预读，body 元信息经此带出 |
| 字段 | `bool _streamChunked = false` | 字段 _streamChunked（类型见签名）。 |

## class `HttpServerCore`

- **说明**：SLang 标准库类型 HttpServerCore（详见源文件）。

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `static ServerConfig _cfg = null` | P0 形态：模块级单例（全静态）——SERVER_DESIGN.md §1.2「单 VM 协程 调度即全部并发」的 v1 服务器语义。实测跨模块类多实例化在 C VM 存在实例态串扰（S2 连接读到 S1 的路由表，闭包零捕获 + 实参传值 亦无法规避），静态化是最小可靠路径。门面 SLang.HttpServer 已转 实例形态（构造带端口），全部经本类静态转发——单 VM 单服务器语义， 多实例待 C VM 实例隔离修复。 |
| 字段 | `static bool _running = false` | 字段 bool（类型见签名）。 |
| 字段 | `static Task _acceptTask = null` | 字段 Task（类型见签名）。 |
| 字段 | `static List&lt;object&gt; _conns = null` | 跨模块点分类型不能作泛型参数（Front：模板中不允许 . 连接符号）—— 连接表用 List&lt;object&gt; + as Net.TcpStream 转型 |
| 字段 | `static List&lt;object&gt; _servers = null` | ── 多监听器（v1.1）：同进程多端口挂载 ── 监听器表（主监听器 + listen() 扩展监听器；object + as 转型同 _conns 纪律），平行 tag / port 表——连接协程经 _tagOf/_portOf 身份扫描反查（TcpServer 跨模块多实例安全：C 侧 sid 薄包装）。 主监听器 tag 恒 = 1；扩展监听器由 _nextTag 分配 2,3,... |
| 字段 | `static List&lt;Int32&gt; _serverTags = null` | 字段 List（类型见签名）。 |
| 字段 | `static List&lt;Int32&gt; _serverPorts = null` | 字段 List（类型见签名）。 |
| 字段 | `static List&lt;string&gt; _pendHosts = null` | listen() 待注册缓冲（未 running 时调用先缓存，start() 统一 bind；stop/reset 清空） |
| 字段 | `static List&lt;Int32&gt; _pendPorts = null` | 字段 List（类型见签名）。 |
| 字段 | `static List&lt;Int32&gt; _pendTags = null` | 字段 List（类型见签名）。 |
| 字段 | `static Int32 _nextTag = 2` | 监听器 tag 发生器（主监听器 = 1 固定；listen() 分配 2 起； stop 重置 2） |
| 字段 | `static string _listenHost = ""` | 监听参数构造期提取为单层静态字段（this._cfg.host 双层链求值坑规避） |
| 字段 | `static Int32 _listenPort = 0` | 字段 Int32（类型见签名）。 |
| 字段 | `public static bool _docsEnabled = true` | 文档路由开关（P3，§4.8 app.docs(false) 消费；start 挂载 /docs + /openapi.json；reset 恢复默认开） |
| 字段 | `public static Function _hookOnStart = null` | app 级事件钩子（P6，§4.9：门面 set/get 访问器写读； onStart/onStop = function()；onError = function( Request req, Response res, Error e )——钩子零捕获（体内只能引用全局静态）； reset 清空） |
| 字段 | `public static Function _hookOnStop = null` | 字段 static（类型见签名）。 |
| 字段 | `public static Function _hookOnError = null` | 字段 static（类型见签名）。 |
| 方法 | `void setListenPort(Int32 port)` | 便捷覆盖监听端口（Server.start(port)/run(port) 用；start 前生效） |
| 方法 | `void configure(ServerConfig cfg)` | 初始化配置（构造替代；重复调用覆盖配置，start 前生效） |
| 方法 | `void reset()` | 清空路由表与中间件/插件（stop 后重新配置用；连接表由 stop 清理）； app 级事件钩子一并清空（P6，§4.9） |
| 方法 | `void use(Function middleware)` | ── 中间件/插件（P2；SLang.Server.use 转发）── 注册中间件（三参 Function(req,res,nx)；注册序即执行序） |
| 方法 | `void use(ServerPlugin plugin)` | 注册插件（onInstall 立即执行；生命周期/WS 钩子由引擎广播） |
| 方法 | `RouteInfo on(string method, string path, Function handler)` | ── 路由注册（P1 起经 Router；推荐用 SLang.HttpServer 门面——返回 RouteInfo 可写文档元数据）── 原始形式（动态注册 / 方法变量） |
| 方法 | `RouteInfo onGet(string path, Function handler)` | 执行 onGet(path, handler)，行为详见源实现。 |
| 方法 | `RouteInfo onPost(string path, Function handler)` | 执行 onPost(path, handler)，行为详见源实现。 |
| 方法 | `RouteInfo onAny(string path, Function handler)` | 执行 onAny(path, handler)，行为详见源实现。 |
| 方法 | `RouteInfo websocket(string path, Function handler)` | WS 升级路由（SLang.WebSocketServer.websocket 同源） |
| 方法 | `List&lt;WsSession&gt; sessions(string path)` | ── WS 会话查询 / 组播（引擎级静态通道；门面 app.sessions / app.broadcast 实例方法同源转发）── 闭包零捕获场景（waitCond 轮询判据 / WS 会话回调内组播等无 实例引用可用的位置）经本组静态查询与组播，语义与门面实例 形态完全一致（§4.6）。 该 WS 路由的在线会话快照 |
| 方法 | `Int32 broadcast(string path, string text)` | 组播文本（返回送达会话数；已断会话跳过） |
| 方法 | `Int32 broadcast(string path, ByteBuffer payload)` | 组播二进制（P6，§4.6 binary 重载；返回送达会话数） |
| 方法 | `Int32 broadcastTag(string path, string tag, string text)` | 定向组播文本（P6，§4.6：只发带 tag 标签的会话——s.tag 打标； 闭包零捕获场景经本静态通道，语义与门面一致） |
| 方法 | `Int32 broadcastTag(string path, string tag, ByteBuffer payload)` | 定向组播二进制（P6，§4.6） |
| 属性 | `get bool isRunning()` | ── 生命周期 ── |
| 方法 | `void start()` | 启动监听（立即返回；accept 循环进独立协程） |
| 方法 | `Int32 listen(string host, Int32 port)` | ── 多监听器（v1.1）：同进程扩展端口挂载 ── 登记扩展监听器（SLang.HttpServer.listen 转发）。主监听器 = 1 固定，本 API 分配 2,3,... 并返回 tag；未 running 时入缓冲 （start() 统一 bind，tag 不变），running 中立即 bind。 |
| 方法 | `void _bindListener(string host, Int32 port, Int32 tag)` | 立即绑定一个扩展监听器并启动其 accept 循环（running 中 listen / start() 缓冲消费共用；tag 由调用方给定——缓冲登记期分配值不可换） |
| 方法 | `Int32 _tagOf(Net.TcpServer srv)` | 监听器身份 → tag（列表身份扫描；未命中兜底 1 = 主监听器） |
| 方法 | `Int32 _portOf(Net.TcpServer srv)` | 监听器身份 → port（_tagOf 同款扫描；未命中兜底配置端口） |
| 方法 | `void stop()` | 停止：关监听 + 关全部在途连接（各连接协程随读失败/EOF 退出） |
| 方法 | `void awaitStop()` | 挂起直至停止（等待 accept 循环协程收尾） |
| 方法 | `void _acceptLoop(Net.TcpServer srv)` | ── 内部：accept 循环（独立协程；每连接再派发一协程）── |
| 方法 | `void _cleanupConn(Net.TcpStream c)` | 连接收尾：从连接表移除 + 尽力关闭（幂等） |
| 方法 | `void _runConn(Net.TcpStream c, Net.TcpServer srv)` | 连接处理入口（连接协程体）：异常兜底静默（对端异常断开 / 写失败等）。 srv = 接入连接的监听器（多监听器 v1.1：tag/port 由身份扫描反查） |
| 方法 | `void _handleConnection(Net.TcpStream client, Net.TcpServer srv)` | ── 内部：连接处理（每连接一协程；keep-alive 循环）── |
| 方法 | `bool _runPipeline(Net.TcpStream client, ServerConfig cfg, RouteInfo route, Int32 noRoute, Request req, Response res, bool isHead, Int32 tag)` | ── 管道与尾环（P2，§6.9 / §6.1）── 管道入口：无任何中间件（全局 + 路由级）直通尾环；有则 _Pipeline 逐环（Next.go 链）。P10：路由级中间件参与判定——仅全局为空但 路由级非空同样走 _Pipeline。 返回 true = 尾环已自行断连收尾（handler 超时路径，调用方 break） |
| 方法 | `bool _tail(Net.TcpStream client, ServerConfig cfg, RouteInfo route, Int32 noRoute, Request req, Response res, bool isHead, Int32 tag)` | 尾环：handler 协程派发（§6.1）或 404/405 应答（经中间件后的终点； res 终端写出由调用方统一处理）。 返回 true = 超时路径已断连收尾（调用方 break） |
| 方法 | `void _gracefulClose(Net.TcpStream client)` | 优雅断连：停发（closeWrite = shutdown Write，NetCloseTest F1 先例） → 让出 50ms（客户端收响应）→ 丢弃式收尾读（消费对端残余 body， 防未读缓冲触发 RST）→ close。协程内 delay 挂起不阻塞调度； 收尾读窗口 500ms，超时静默放弃 |
| 方法 | `Int32 _uploadFileLimit()` | 单文件上传上限（P1.5；Request 惰性 multipart 解析用； 未配置时按 ServerConfig 默认 50MB） |
| 方法 | `void _releaseRequest(Request req)` | 请求级资源回收：body 缓冲 + multipart 文件内容缓冲 （UploadedFile._data，§6.5 请求结束统一回收；幂等） |
| 方法 | `bool _isWsUpgrade(_HttpParseResult r)` | ── WebSocket Upgrade 分流（§6.1 / §6.8）── 升级请求判定：Upgrade 头含 websocket（大小写不敏感） |
| 方法 | `void _runWsSession(Net.TcpStream client, RouteInfo wsRoute, _HttpParseResult r, ByteBuffer buf)` | WS 会话：三参 accept（预读残留直传，残留帧不丢失）→ WsSession → 会话回调（单参 Function(session)）→ 收尾注销注册表。 握手失败 → 400；本方法返回 = 连接终结（由调用方 break） |
| 方法 | `bool _wantKeepAlive(_HttpParseResult r)` | keep-alive 判定：Connection 头显式优先，否则 HTTP/1.1 默认开 |
| 方法 | `void _writeResponse(Net.TcpStream client, Response res, bool keepAlive, bool isHead)` | ── 响应编码 ── 响应写出（Content-Length 恒精确；HEAD 不写 body；写毕由调用方回收 body） |
| 方法 | `void _writeSimple(Net.TcpStream client, Int32 status, string jsonBody)` | 简单 JSON 错误响应（尽力写出，失败静默；恒 Connection: close） |
| 方法 | `void _writeSimple(Net.TcpStream client, Int32 status, string jsonBody, string extraName, string extraValue)` | 带单附加头变体（如 405 的 Allow） |
| 方法 | `string _errorBody(Int32 code)` | ApiResult 形态错误体（键序 code → message → data；data 是关键字， 框架手工组包，SERVER_DESIGN.md §6.7；ApiResult 类随 P1 落地） |
| 方法 | `string _reason(Int32 code)` | 状态码 reason（SERVER_DESIGN.md 附录 A 常用子集；未知码空串） |
| 方法 | `_HttpParseResult _parse(Net.NetStream s, ByteBuffer buf, ServerConfig cfg, bool stopAtHead)` | ── 请求解析（预读缓冲模式；HttpClient 响应解析的对称实现）── 解析一条完整请求；对端干净关闭（EOF）返回 null；协议错误经 _errorCode 带出；读超时 / IO 异常原样上抛（连接层收尾）。 stopAtHead = true（P5 §6.6 请求侧流式）：解析到头区空行即停， 不预读 body——body 元信息（Content-Length / chunked）存入 _streamCl/_streamChunked，连接 + 预读残留由调用方移交 handler |
| 方法 | `_HttpParseResult _parseHeadless(Net.NetStream s, ByteBuffer buf, ServerConfig cfg, _HttpParseResult r)` | 补读 body（P5，§6.6）：stopAtHead 形态解析过头的请求，命中非 streamBody 路由时经此把 body 按三态读全（头区已消费，直接从 buf 残留/连接续读）。r 的头信息保留，仅填 _body / _errorCode |
| 方法 | `Int32 _readChunked(Net.NetStream s, ByteBuffer buf, ByteBuffer dst, Int32 maxBytes)` | chunked 请求 body 聚合（hex size 行 -&gt; 块 -&gt; CRLF；0 终止 + trailer 空行） 返回 0 = OK；400 = 协议错误 / EOF 截断；413 = 累计超限 |
| 方法 | `Int32 _readBytesChecked(Net.NetStream s, ByteBuffer buf, ByteBuffer dst, Int32 need)` | 精确读 need 字节入 dst（先消费 buf 预读，不足再从流拉）； EOF 截断返回 400（读超时 / IO 异常原样上抛） |
| 方法 | `string _readLine(Net.NetStream s, ByteBuffer buf)` | ── 文本 / 解析辅助（HttpClient 同款；Std 侧为模块内私有不便跨模块复用）── 读一行（含 '\n'）：buf 有行直接取，否则从流拉；EOF 无行返回 null。 单行上限 64KB（防无换行恶意行撑爆内存；头区另有 maxHeaderBytes 判定） |
| 方法 | `string _stripEol(string line)` | 去行尾 CRLF / LF |
| 方法 | `Int32 _chunkSize(string line)` | chunk size 行解析：hex 段到 ';' 前截止（忽略 chunk 扩展） |
| 方法 | `Int32 _parseHex(string s)` | 十六进制解析（Int32 中转，&gt; 2e9 返回 -1） |
| 方法 | `Int64 _parseDec64(string s)` | 十进制解析（Content-Length 用；非法返回 -1） |
| 方法 | `Int64 _parseDec64Full(string s)` | 全量程十进制解析（真 Int64，溢出判 -1）：pathInt64 专用。 _parseDec64 维持 2e9 上限（Int32 档调用方语义不变）。 |
| 方法 | `bool _containsFold(string hay, string needle)` | 忽略大小写子串查找 |
| 方法 | `bool _startsWithFold(string s, string prefix)` | 忽略大小写前缀匹配 |
| 方法 | `bool _eqExact(string a, string b)` | 精确比对（不折叠大小写） |
