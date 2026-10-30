# Net/Websocket.sl

> 源文件：`Net/Websocket.sl`

## class `WsMessage`

- **说明**：WsMessage — 一条完整消息（分片已重组）

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `public Int32 op = 0` | 操作码（WsOpCode.Text / WsOpCode.Binary） |
| 字段 | `public ByteBuffer payload = null` | 载荷（归属本消息；消费完调 release 归还，勿外部持有引用跨越 release） |
| 构造 | `_init_(Int32 opCode, ByteBuffer buf)` | 构造方法，初始化本类型实例。 |
| 属性 | `get bool isText()` | 获取 isText 的值。 |
| 属性 | `get bool isBinary()` | 获取 isBinary 的值。 |
| 属性 | `get Int32 size()` | 获取 size 的值。 |
| 方法 | `string text()` | 载荷按 UTF-8 解码为文本（内嵌 NUL 截断语义同 ByteBuffer.toString） |
| 方法 | `ByteBuffer binary()` | 载荷原样返回（归属仍在本消息，release 前有效） |
| 方法 | `void release()` | 释放载荷（幂等：释放后置 null，重复调用无副作用） |

## class `WsCloseInfo`

- **说明**：WsCloseInfo — 关闭原因（对端 Close 帧解析结果）

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `public Int32 code = 0` | 状态码（载荷 &lt; 2 字节非法时按 1005 无状态码处理） |
| 字段 | `public string reason = ""` | 关闭原因文本（可为空串） |
| 字段 | `public bool wasClean = false` | 是否完成 Close 协商（收到对端 Close 即视为 clean） |

## class `WsOptions`

- **说明**：WsOptions — 连接 / 接入选项

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `public string protocols = ""` | 子协议（逗号分隔列表，如 "chat,superchat"；空 = 不协商） |
| 字段 | `public Int32 maxMessageSize = 16777216` | 单条消息上限字节（含分片重组后；超出抛 WsError.MessageTooBig） |
| 字段 | `public Int32 handshakeTimeoutMs = 10000` | 握手连接超时毫秒（Tcp.connectTimeout 透传） |
| 字段 | `public bool autoPong = true` | 收到 Ping 自动回 Pong（receive 循环内尽力发送） |
| 字段 | `public string caPem = ""` | wss CA 证书链 PEM 文本（空 = 跳过验证，与 TlsOptions.caPem 一致） |

## class `_WsFrame`

- **说明**：_WsFrame — 内部帧结构（解析中间产物，不对外）

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `bool fin = false` | 字段 fin（类型见签名）。 |
| 字段 | `Int32 opcode = 0` | 字段 opcode（类型见签名）。 |
| 字段 | `ByteBuffer payload = null` | 字段 payload（类型见签名）。 |

## class `WebSocketStream`

- **说明**：WebSocketStream — WebSocket 连接（NetStream 消息子类）

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `NetStream _raw = null` | 底层字节流（TcpStream / TlsStream，握手期由静态方法持有后移交） |
| 字段 | `ByteBuffer _recvBuf = null` | 帧解析累积缓冲（握手期复用，握手后继续盛帧数据） |
| 字段 | `bool _isClient = false` | 客户端角色（发帧掩码 / 收帧禁掩码；服务端反之） |
| 字段 | `bool _sentClose = false` | 已发出 Close（幂等守卫） |
| 字段 | `WsState _state = WsState.Connecting` | 连接状态机（enum 字段默认值先例：HttpClient.method） |
| 字段 | `WsCloseInfo _closeInfo = null` | 对端 Close 解析结果（未收到为 null） |
| 字段 | `string _protocol = ""` | 协商成功的子协议（未协商为空串） |
| 字段 | `Int32 _maxMessageSize = 16777216` | 字段 _maxMessageSize（类型见签名）。 |
| 字段 | `bool _autoPong = true` | 字段 _autoPong（类型见签名）。 |
| 字段 | `bool _inFrag = false` | 分片重组状态（_inFrag = true 期间 _fragAcc 累积 / _fragOpcode 记首帧） |
| 字段 | `ByteBuffer _fragAcc = null` | 字段 _fragAcc（类型见签名）。 |
| 字段 | `Int32 _fragOpcode = 0` | 字段 _fragOpcode（类型见签名）。 |
| 构造 | `_init_(NetStream raw, ByteBuffer recvBuf, bool isClient, string protocol, WsOptions opt)` | 构造方法，初始化本类型实例。 |
| 属性 | `get WsState state()` | ── 状态查询 ── |
| 属性 | `get WsCloseInfo closeInfo()` | 获取 closeInfo 的值。 |
| 属性 | `get string protocol()` | 获取 protocol 的值。 |
| 属性 | `get bool isClient()` | 获取 isClient 的值。 |
| 方法 | `WebSocketStream connect(string url)` | 连接（客户端） 连接 ws / wss 端点（默认选项） |
| 方法 | `WebSocketStream connect(string url, WsOptions opt)` | 连接 ws / wss 端点：建连 -&gt; 发起 Upgrade 握手 -&gt; 校验响应 |
| 方法 | `Task connectAsync(string url)` | 协程异步连接（结果经 Task.awaitTask() 取回，object as WebSocketStream） |
| 方法 | `Task connectAsync(string url, WsOptions opt)` | 协程异步连接（带选项） |
| 方法 | `WebSocketStream _connectHandshake(NetStream s, ByteBuffer buf, string key, WsOptions opt)` | 客户端握手响应校验：101 + Upgrade 头组 + Accept 比对 |
| 方法 | `WebSocketStream accept(TcpStream raw)` | 接入（服务端） 在已 accept 的连接上应答握手（默认选项） |
| 方法 | `WebSocketStream accept(TcpStream raw, WsOptions opt)` | 在已 accept 的连接上应答握手：解析请求 -&gt; 回 101 -&gt; 移交消息层 |
| 方法 | `WebSocketStream accept(TcpStream raw, ByteBuffer preRead, WsOptions opt)` | 带预读残留的接入重载（SERVER_DESIGN.md §6.8 / §2.2 缺口 9）： HTTP 层已消费请求行+头（经 readLine 推进 readerIndex）之后，缓冲里 可能残留客户端提前发来的帧字节——本重载把 preRead 的可读字节 （readerIndex 起）先行灌入握手缓冲再解析，残留帧不丢失。 纯增量重载，不影响既有两参形式；消费方：SLangServer HTTP 同端口 WS 升级分流。preRead 归调用方所有（本方法只读其可读区）。 |
| 方法 | `string _acceptHandshake(NetStream s, ByteBuffer buf, WsOptions opt)` | 服务端握手应答：请求行 + 头校验 -&gt; 101 + Accept 回填 |
| 方法 | `string _acceptToken(string key)` | Accept 令牌：Base64( SHA-1( key + RFC 6455 固定 GUID ) ) |
| 方法 | `WsMessage receive()` | 收消息（同步拉模式） 收一条完整消息（分片已重组 / 控制帧已处理）； 返回 null = 连接关闭（Close 协商完成或底层 EOF）。 消息载荷归属返回值，消费完调 msg.release() 归还。 |
| 方法 | `Stream&lt;WsMessage&gt; messages()` | 消息流（Stream 体系直连）：引流协程循环收消息灌进 controller， 消费方经 Stream&lt;WsMessage&gt; 逐条读取；连接关闭 / 出错时 ctrl.close() 收尾。 try? 异常语义：失败返回默认值（类类型 = null），与关闭返回 null 合流 |
| 方法 | `_WsFrame _readFrame()` | 帧层（内部） 读一帧（null = EOF）；帧头 / 掩码方向 / 控制帧约束 / 尺寸全面校验 |
| 方法 | `void _writeFrame(Int32 opcode, ByteBuffer payload)` | 发一帧（掩码按角色自动施加；payload 会被读空——调用方传拷贝 / 视图） |
| 方法 | `void _trySend(Int32 opcode, ByteBuffer payload)` | 尽力发送：连接已断 / 写失败时静默放弃，不打断收包主流程 （Pong 回显 / Close 协商容错路径） |
| 方法 | `void sendText(string text)` | 发消息 发文本消息（UTF-8） |
| 方法 | `void sendBinary(ByteBuffer payload)` | 发二进制消息（内部走 slice 视图，src 不被读空） |
| 方法 | `void sendBinary(UInt8Array payload)` | 发二进制消息（字节数组） |
| 方法 | `void sendPing()` | 发心跳探测（空载荷 Ping） |
| 方法 | `void sendPong()` | 发心跳应答（空载荷 Pong；对端主动 Ping 时通常无需手调，autoPong 已回） |
| 方法 | `void sendClose()` | 发 Close 并进入 Closing（默认 1000 正常关闭） |
| 方法 | `void sendClose(Int32 code, string reason)` | 发 Close 并进入 Closing（幂等：已发过直接返回） |
| 方法 | `ByteBuffer _closePayload(Int32 code, string reason)` | Close 载荷：U16 状态码 + 可选 UTF-8 原因（截断到 123 字节满足 &lt;= 125） |
| 方法 | `Int32 read(ByteBuffer dst)` | ByteStream 契约（消息流适配） 消息粒度读：一次 read 收一条消息写入 dst（超出 dst 容量部分丢弃）； 返回 0 = 关闭（置位 _eof） |
| 方法 | `void write(ByteBuffer src)` | 消息语义：裸字节写不支持（发消息走 sendText / sendBinary） |
| 方法 | `void flush()` | IO 读写 / 流控制（flush）。 |
| 方法 | `void closeWrite()` | 半关闭：停发（尽力发 Close 通知对端，对端 receive 将见 null） |
| 方法 | `void close()` | 完全覆写：尽力发 Close 帧 -&gt; 关底层流 -&gt; 封口（TcpStream 同款） |
| 方法 | `void _releaseFrag()` | 分片累积缓冲回收（close / 出错路径共用） |
| 方法 | `string _readLine(NetStream s, ByteBuffer buf)` | 静态辅助（HttpClient 同款文本 / 解析工具 + WS 专属） 读一行（含 '\n'）：buf 有行直接取，否则从流拉；EOF 无行返回 null |
| 方法 | `string _stripEol(string line)` | 去行尾 CRLF / LF |
| 方法 | `bool _containsFold(string hay, string needle)` | 忽略大小写子串查找（Connection 头值判 upgrade 用） |
| 方法 | `HttpHeaders _readHeaders(NetStream s, ByteBuffer buf)` | 头域循环读取（空行截止；名字后冒号 + 可选前导空格） |
| 方法 | `Int32 _statusCode(string line)` | 状态行状态码解析（"HTTP/1.1 101 ..." -&gt; 101；非法返回 -1） |
| 方法 | `bool _eqExact(string a, string b)` | 精确比对（不折叠大小写；Sec-WebSocket-Accept 用） |
| 方法 | `bool _startsWithFold(string s, string prefix)` | 忽略大小写前缀匹配（服务端请求行判 "GET " 用） |
| 方法 | `string _pickProtocol(string supported, string requested)` | 子协议协商：遍历 supported 的每个 token， 命中 requested 列表（大小写不敏感）即返回；无交集返回空串 |
| 方法 | `bool _listContainsFold(string list, string token)` | 逗号 / 空白分隔列表包含判定（token 粒度，大小写不敏感） |
| 方法 | `WsCloseInfo _parseClose(ByteBuffer payload)` | Close 帧载荷解析：U16 状态码 + 可选 UTF-8 原因； 载荷 &lt; 2 字节非法按 1005（无状态码）处理；调用会推进 payload.readerIndex |
| 方法 | `bool _fill(NetStream s, ByteBuffer buf, Int32 need)` | 累积读取：循环从流拉直到 buf 可读 &gt;= need； EOF（n == 0）返回 false；容量不足先压缩再扩容（4096 起步） |

## class `WebSocketClient`

- **说明**：WebSocketClient — 高层回调式客户端（HttpClient 风格门面 + Python WebSocketApp 事件模型：onOpen / onMessage / onClose / onError） 用法: var c = Net.WebSocketClient() c.onOpen = function() { Console.println( "opened" ) } c.onMessage = function( Net.WsMessage m ) { Console.println( "recv: " + m.text() ) m.release() } c.onClose = function( Net.WsCloseInfo info ) { } c.onError = function( Error e ) { } c.connect( "ws://127.0.0.1:9001/chat" )   # 握手 + 启动事件循环 c.sendText( "hi" ) c.waitClosed()                            # 等事件循环收尾 语义要点: - connect：建连握手原地抛错（失败调用方直接 catch）； 成功后启动分发协程——循环 receive() 把消息推给 onMessage - 事件顺序：onOpen 恰一次 -> onMessage 0..N 次 -> [onError 0..1 次] -> onClose 恰一次 - 协议违例 / onMessage 内抛错 -> onError（一次），随后 onClose 收尾； 未设 onError 时异常吞掉（_ControllerStream.listen 同款取舍） - onClose 参数 WsCloseInfo 可能为 null（异常断开，无协商信息） - close()：尽力发 Close 帧后关底层流，事件循环随后自然收尾触发 onClose - 配置字段连接前赋值（protocols / caPem / 握手超时 / 消息上限 / autoPong）

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `public Function onOpen = null` | ---- 回调（连接前赋值；null = 不通知）---- function() — 握手完成时调用一次 |
| 字段 | `public Function onMessage = null` | function( WsMessage msg ) — 每条 Text / Binary 消息 （msg 归回调所有，消费完调 m.release() 归还） |
| 字段 | `public Function onClose = null` | function( WsCloseInfo info ) — 连接收尾时调用一次（info 可能为 null） |
| 字段 | `public Function onError = null` | function( Error err ) — 事件循环异常（协议违例 / 回调抛错） |
| 字段 | `public string protocols = ""` | ---- 配置（连接前赋值；语义同 WsOptions 同名字段）---- |
| 字段 | `public string caPem = ""` | 字段 string（类型见签名）。 |
| 字段 | `public Int32 handshakeTimeoutMs = 10000` | 字段 Int32（类型见签名）。 |
| 字段 | `public Int32 maxMessageSize = 16777216` | 字段 Int32（类型见签名）。 |
| 字段 | `public bool autoPong = true` | 字段 bool（类型见签名）。 |
| 字段 | `public Int32 closeTimeoutMs = 5000` | 优雅关闭等待对端回显 Close 的超时（毫秒）；超时强制收尾防事件循环挂起 |
| 字段 | `WebSocketStream _ws = null` | 底层连接（connect 后非空） |
| 字段 | `Task _task = null` | 事件循环协程（connect 后非空） |
| 方法 | `WebSocketClient connect(string url)` | 连接并启动事件循环；握手失败原地抛（重连语义：新建 WebSocketClient） |
| 方法 | `void _runLoop(WebSocketStream ws, Function hOpen, Function hMsg, Function hClose, Function hErr)` | 事件循环体（独立静态方法：label-catch 保护 + 收尾回调顺序保证） |
| 方法 | `void waitClosed()` | 等待事件循环结束（onClose 已送达；返回后连接终结） |
| 方法 | `void _ensureConnected()` | 未连接守卫（发送族前置检查） |
| 方法 | `void sendText(string text)` | ── 发送（转发底层连接）── |
| 方法 | `void sendBinary(ByteBuffer payload)` | 执行 sendBinary(payload)，行为详见源实现。 |
| 方法 | `void sendBinary(UInt8Array payload)` | 执行 sendBinary(payload)，行为详见源实现。 |
| 方法 | `void sendPing()` | 执行 sendPing()。 |
| 方法 | `void close()` | ── 关闭 ── 优雅关闭：只发 Close 帧并等待对端回显，事件循环收尾触发 onClose （携带协商 closeInfo）；对端不回显时超时强制收尾。失败不阻断 |
| 方法 | `void close(Int32 code, string reason)` | 带状态码优雅关闭（语义同 close()，指定 code / reason） |
| 方法 | `void abort()` | 立即强制关闭：不等对端回显，事件循环立即结束（onClose 的 info 可能为 null） |
| 方法 | `void _beginClose(Int32 code, string reason)` | 执行 _beginClose(code, reason)，行为详见源实现。 |
| 属性 | `get WsState state()` | ── 状态查询（未连接时 state = Closed）── |
| 属性 | `get WsCloseInfo closeInfo()` | 获取 closeInfo 的值。 |
| 属性 | `get string protocol()` | 获取 protocol 的值。 |
| 属性 | `get bool isOpen()` | 获取 isOpen 的值。 |
