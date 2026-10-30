# Net/HttpClient.sl

> 源文件：`Net/HttpClient.sl`

## class `HttpHeaders`

- **说明**：Net/HttpClient.sl — HTTP/1.1 客户端（TcpStream / TlsStream 之上） 设计契约：csimple_lang/md/design/NET_DESIGN.md L1118（Phase 3: TLS -> HttpClient）；STREAM_DESIGN.md §9.6（body 三态读取语义） 用法: import Std; var resp = Net.HttpClient.httpGet( "http://127.0.0.1:8080/hello" ) resp.statusCode       # 200 resp.body             # 响应文本 resp.headers.getHeader( "Content-Type" ) var req = Net.HttpRequest() req.method = Net.HttpMethod.Post   # 请求方法枚举（Get/Post/Put/Delete/Head） req.url = "https://example.com/api" req.body = "ping=1" req.headers.add( "Content-Type", "application/x-www-form-urlencoded" ) var c = Net.HttpClient() c.caPem = caText          # https CA 验证（空 = 跳过验证） var r2 = c.send( req ) 协程异步形态（直接返回 Task，调用方无需自己包装闭包）: Task t1 = Net.HttpClient.httpGetAsync( "https://example.com/a" ) Task t2 = c.sendAsync( req2 )            # 实例配置生效（caPem 等） Coroutine.waitAll2( t1, t2 )             # 并发：两请求 IO 同时挂起 Net.HttpResponse r1 = await t1 as Net.HttpResponse Net.HttpResponse r2b = await t2 as Net.HttpResponse # 异常向 await 处重抛，调用方 try/catch 即可 语义要点: - 每请求一连接：自动发 Connection: close，响应读毕即关连接 （无连接复用，Stage B 限制，详见 md/syntax/net.md 限制表） - body 三态读取：Content-Length 精确读 / Transfer-Encoding: chunked 逐块聚合 / 两者皆无读到 EOF - HEAD 与 204/205/304 状态不读 body - https 经 TlsStream.wrap（caPem 空 = 跳过验证，与 TlsStream 一致） - 响应解析经预读缓冲（ByteBuffer），跨 read 边界的安全行解析 - 非法 URL 抛 HttpError.UriFormat；非 http/https 抛 HttpError.UnsupportedScheme；响应报文损坏抛 HttpError.Protocol； 底层网络异常（NetError / TlsError）原样透传 请求方法：HttpMethod 枚举（extends Int32；Get=0 Post=1 Put=2 Delete=3 Head=4， 见下方枚举定义）。枚举作类字段类型 / 枚举值赋字段均有先例 （Render/Pipeline/GpuTexture.sl 的 EFilterMode / EAddressMode 字段） HttpHeaders — 请求 / 响应头集合（名字大小写不敏感）

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `List&lt;string&gt; _names = null` | 字段 _names（类型见签名）。 |
| 字段 | `List&lt;string&gt; _values = null` | 字段 _values（类型见签名）。 |
| 构造 | `_init_()` | 构造方法，初始化本类型实例。 |
| 属性 | `get int count()` | 获取 count 的值。 |
| 方法 | `void add(string name, string value)` | 追加（允许同名头共存） |
| 方法 | `void setHeader(string name, string value)` | 覆盖同名头（大小写不敏感；不存在则追加） 注意：方法名不能叫 set——set 是 SL 属性 setter 关键字，会触发解析歧义 注意：跨类静态调用的实参先提取局部变量——直接传 this._names[i] （this.字段[索引器] 复合表达式）会导致参数收集失败、方法匹配 NotFound |
| 方法 | `string getHeader(string name)` | 取值（大小写不敏感；不存在返回 null） 注意：方法名不能叫 get——get 是 SL 属性 getter 关键字，会触发解析歧义 |
| 方法 | `bool contains(string name)` | 判断 / 校验是否（contains）。 |
| 方法 | `string nameAt(int index)` | 执行 nameAt(index)，行为详见源实现。 |
| 方法 | `string valueAt(int index)` | 执行 valueAt(index)，行为详见源实现。 |

## class `HttpRequest`

- **说明**：HttpRequest — 请求描述

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `public HttpMethod method = HttpMethod.Get` | 请求方法（默认 Get；枚举字段先例：Render/Pipeline/GpuTexture.sl 的 EFilterMode） |
| 字段 | `public string url = ""` | 字段 string（类型见签名）。 |
| 字段 | `public HttpHeaders headers = null` | 字段 HttpHeaders（类型见签名）。 |
| 字段 | `public string body = ""` | 文本 body（UTF-8；空串 = 无 body，内嵌 NUL 会被截断） |
| 构造 | `_init_()` | 构造方法，初始化本类型实例。 |

## class `HttpResponse`

- **说明**：HttpResponse — 响应

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `public Int32 statusCode = 0` | 字段 Int32（类型见签名）。 |
| 字段 | `public string reasonPhrase = ""` | 字段 string（类型见签名）。 |
| 字段 | `public string protocol = ""` | 字段 string（类型见签名）。 |
| 字段 | `public HttpHeaders headers = null` | 字段 HttpHeaders（类型见签名）。 |
| 字段 | `public string body = ""` | 字段 string（类型见签名）。 |
| 构造 | `_init_()` | 构造方法，初始化本类型实例。 |
| 属性 | `get bool isOk()` | 获取 isOk 的值。 |
| 属性 | `get Int64 contentLength()` | Content-Length 头（Int64；头缺失 / 格式非法返回 -1） |

## class `HttpClient`

- **说明**：HttpClient — 客户端（每请求一连接）

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `public Int32 connectTimeoutMs = 10000` | 连接超时毫秒（Tcp.connectTimeout 透传） |
| 字段 | `public Int32 readTimeoutMs = 0` | 读超时毫秒（&lt;= 0 = 无限等待；超时抛 NetError.Timeout） |
| 字段 | `public string caPem = ""` | https CA 证书链 PEM 文本（空 = 跳过验证，与 TlsOptions.caPem 一致） |
| 方法 | `HttpResponse httpGet(string url)` | 便捷 GET 注意：方法名不能叫 get——get 是 SL 属性 getter 关键字，会触发解析歧义 |
| 方法 | `HttpResponse httpPost(string url, string body, string contentType)` | 便捷 POST（文本 body + Content-Type） |
| 方法 | `HttpResponse send(HttpRequest req)` | 发送请求并读取完整响应（body 全量缓冲为文本） |
| 方法 | `Task httpGetAsync(string url)` | ---- 协程异步形态（直接返回 Task，调用方 await 取回 HttpResponse）---- 语义: - 返回的 Task 即协程本体；调用处不阻塞，await 时才等待结果 - 协程内全部网络 IO（connect / send / recv / TLS 握手）经 Option A 挂起当前协程，不阻塞调度器（md/syntax/coroutine.md §16.2） - 异常向 await 该 Task 的等待者重抛，故这些方法无需 throws 声明 - 闭包内调用宿主实例方法必须写显式 this. 前缀（coroutine.md §5.3） 异步便捷 GET：Task t = HttpClient.httpGetAsync( url )，之后 await t as HttpResponse |
| 方法 | `Task httpPostAsync(string url, string body, string contentType)` | 异步便捷 POST（文本 body + Content-Type） |
| 方法 | `Task sendAsync(HttpRequest req)` | 异步发送（实例配置生效：connectTimeoutMs / readTimeoutMs / caPem） |
| 方法 | `HttpResponse _readResponse(NetStream s, ByteBuffer buf, HttpRequest req)` | ── 响应解析（一切读经 recvBuf 预读缓冲中转）── |
| 方法 | `void _readChunked(NetStream s, ByteBuffer buf, ByteBuffer dst)` | chunked：hex size 行 -&gt; 块数据 -&gt; CRLF -&gt; size 0 -&gt; trailer 空行 |
| 方法 | `void _readBytes(NetStream s, ByteBuffer buf, ByteBuffer dst, Int32 need)` | 精确读 need 字节入 dst：先消费 buf 预读，不足再从流拉 |
| 方法 | `void _readToEof(NetStream s, ByteBuffer buf, ByteBuffer dst)` | 读到 EOF（无 Content-Length / chunked 时的 body） |
| 方法 | `string _readLine(NetStream s, ByteBuffer buf)` | 读一行（含 '\n'）：buf 有行直接取，否则从流拉；EOF 无行返回 null |
| 方法 | `string _stripEol(string line)` | ── 文本辅助 ── 去行尾 CRLF / LF |
| 方法 | `string _methodName(HttpMethod m)` | 方法名（HttpMethod -&gt; 请求行文本；未知值兜底 GET） |
| 方法 | `Int32 _chunkSize(string line)` | chunk size 行解析：hex 段到 ';' 前截止（忽略 chunk 扩展） |
| 方法 | `Int32 _parseHex(string s)` | 十六进制解析（Int32 中转，&gt; 2e9 返回 -1） |
| 方法 | `Int64 _parseDec64(string s)` | 十进制解析（Content-Length 用；非法返回 -1） |
| 方法 | `bool _containsFold(string hay, string needle)` | 忽略大小写子串查找（Transfer-Encoding 值判 chunked 用） |
