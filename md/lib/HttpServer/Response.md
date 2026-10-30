# Response.sl

> 源文件：`Response.sl`

## class `Response`

- **说明**：SLang/Server/Response.sl — 响应输出（写侧 API，P1 全表 → P2 流式增补） 设计契约：SERVER_DESIGN.md §4.3 / §4.5 / §6.3 / §6.6 语义：普通终端方法把响应暂存到本对象，handler 协程结束后由引擎统一 编码写出（恒精确 Content-Length）；终端方法第二次调用抛 ServerError.AlreadyResponded（开发期防重复写出）。 链式：status / header / contentType 返回 this（须在终端方法之前调用）。 注意：Content-Type / Content-Length / Connection 三头由引擎管理， 自定义 Content-Type 走 contentType(mime)，经 header() 设置会被跳过。 P2 增补（流式，§4.5 / §6.6）： - stream() / sse()：流式终端——调用即发出状态行+头并锁定响应，返回 写出器（chunked 块编码 / SSE 线格式）；handler 退出未 close() 时 引擎兜底补终止块；HTTP/1.0 降级 close-delimited（连接收尾断连）； - sendFile( path )：普通终端（内部流式实现：64KB 分块直写， Content-Length = 文件大小，非 chunked，对用户透明）； - file( path, downloadName )：sendFile + Content-Disposition 附件头。 直写通道：引擎派发前经 _bind 绑定连接（_conn/_keepAlive/_http10）。

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `Int32 _status = 200` | 字段 _status（类型见签名）。 |
| 字段 | `ByteBuffer _body = null` | 字段 _body（类型见签名）。 |
| 字段 | `bool _responded = false` | 字段 _responded（类型见签名）。 |
| 字段 | `List&lt;string&gt; _cookies = null` | ── Set-Cookie 表（P10 补齐 P3 裁剪项，§4.3 / §6.3）── 已序列化的 Set-Cookie 值（"name=value[; attrs]"，逐条独立成头行—— Set-Cookie 是 HTTP 唯一必须多行重复的头，不走 HttpHeaders 覆盖语义） |
| 字段 | `bool _keepAlive = true` | 字段 _keepAlive（类型见签名）。 |
| 字段 | `bool _http10 = false` | 字段 _http10（类型见签名）。 |
| 字段 | `bool _streaming = false` | chunked 流式开启（stream/sse）：头已直发，引擎不再走缓冲写出 |
| 字段 | `StreamWriter _streamWriter = null` | 字段 _streamWriter（类型见签名）。 |
| 字段 | `bool _direct = false` | sendFile 直写完成（Content-Length 精确，keep-alive 可继续） |
| 方法 | `override _init_()` | 执行 _init_()。 |
| 方法 | `void _bind(Net.TcpStream client, bool keepAlive, bool http10)` | 引擎绑定（派发前；用户勿调）——流式直写通道 + 连接语义 |
| 属性 | `get bool isResponded()` | 是否已有终端写出（handler 忘记响应时引擎兜底 500） |
| 属性 | `get bool isStreaming()` | 是否处于流式输出（stream/sse 已开启——头已直发；引擎超时豁免与 写出路径判定用，§6.1 / §6.6） |
| 方法 | `Response status(Int32 code)` | ── 链式（终端方法之前调用）── 置状态码 |
| 方法 | `Response header(string name, string value)` | 追加响应头（覆盖同名，大小写不敏感） |
| 方法 | `Response contentType(string mime)` | 覆盖 Content-Type |
| 方法 | `Response setCookie(string name, string value)` | ── Set-Cookie（P10 补齐 P3 裁剪项，SERVER_DESIGN.md §4.3 / §6.3）── 非终端：暂存 cookie 行，随终端方法一并写出（三条头写出路径统一 消费 _cookies：缓冲 / 流式头 / sendFile 头——见 _userHeadersText）。 同名多次调用 = 多条独立 Set-Cookie 行（HTTP 语义：Set-Cookie 是 唯一必须逐行重复、不可逗号合并的头）。 简单形态：Set-Cookie: name=value |
| 方法 | `Response setCookie(string name, string value, string path, Int32 maxAge, bool secure, bool httpOnly, string sameSite)` | 属性形态：path 常用 "/"；maxAge 秒（&lt;= 0 省略 Max-Age）； secure / httpOnly 附加标记；sameSite = "Strict"/"Lax"/"None" （空串省略）。sameSite=None 时按现代浏览器要求自动补 Secure。 |
| 方法 | `Response clearCookies()` | 清空已暂存 cookie（改主意场景；幂等） |
| 方法 | `void _addCookie(string line)` | 执行 _addCookie(line)，行为详见源实现。 |
| 方法 | `void text(string s)` | ── 终端方法（二次调用抛 ServerError.AlreadyResponded）── 文本响应（text/plain） |
| 方法 | `void html(string s)` | HTML 响应（text/html） |
| 方法 | `void json(object obj)` | 任意对象 → JSON（BaseJson.fromData；null → "null"） |
| 方法 | `void rawJson(string jsonText)` | 预构建 JSON 串直写（application/json；openapi.json 等内部使用） |
| 方法 | `void jsonOk(object payload)` | 统一成功封装 = json( ApiResult.ok( payload ) ) （输出 {"code":0,"message":"ok","data":...}；payload null → data:null） |
| 方法 | `void jsonFail(Int32 code, string message)` | 统一失败封装（HTTP 仍 200：业务码与 HTTP 码分离） |
| 方法 | `void jsonFail(Int32 code, string message, Int32 httpStatus)` | 三参重载：同时改 HTTP 状态码 |
| 方法 | `void bytes(ByteBuffer buf)` | 二进制响应（application/octet-stream；缓冲归属本响应，写出后引擎回收） |
| 方法 | `void redirect(string url)` | 重定向（302 + Location；空 body） |
| 方法 | `StreamWriter stream()` | ── 流式终端（P2，§4.5 / §6.6）── chunked 流式响应：即刻发出状态行 + 头（Transfer-Encoding: chunked）， 返回写出器（write/writeBytes/flush/close）；HTTP/1.0 降级 close-delimited（裸写，连接收尾断连）。头部设置（status/contentType/ header 链式）须在本调用之前完成 |
| 方法 | `SseWriter sse()` | SSE 流式响应（text/event-stream + Cache-Control: no-cache 自动置） |
| 方法 | `void sendFile(string path)` | 流式文件下载（大文件 64KB 分块读发不整载内存；Content-Length = 文件大小，非 chunked；MIME 按扩展名）。文件不存在 → 404 终端 |
| 方法 | `void sendFileRange(string path, string rangeSpec)` | 流式文件下载 + Range 断点续传（P5，§4.5）： rangeSpec = 请求 Range 头原值（如 "bytes=100-199" / "bytes=100-" / "bytes=-100"）；null / 畸形 / 多 range → 忽略按全量 200（RFC 9110 允许服务器忽略 Range；v1 只取首个 range，多 range 不做合成分块）； start 越界（&gt;= 文件大小）→ 416 + Content-Range: bytes */size。 有效 → 206 + Content-Range: bytes s-e/size + Content-Length = 区间长。 |
| 字段 | `static Int64 _rangeStart = 0` | 区间解析结果槽（_parseRange 输出；模块级静态——跨方法带出双值， _SrvUtil 同款纪律，无并发共享语义：单 VM 协程非抢占 + 调用点立即消费） |
| 字段 | `static Int64 _rangeEnd = 0` | 字段 Int64（类型见签名）。 |
| 方法 | `Int32 _parseRange(string spec, Int64 fsize)` | Range 值解析（"bytes=" 之后的部分）： 返回 0 = 有效（_rangeStart/_rangeEnd 已置） 返回 1 = 416（区间不可满足：start &gt;= size） 返回 -1 = 畸形忽略（按全量 200） v1 只取首个 range（逗号分隔截断）；"a-b" 越界 end 钳到 size-1 |
| 方法 | `void _writeRangeHead(Int64 fsize, Int64 start, Int64 len)` | 文件下载响应头直发（sendFile/sendFileRange 共用；Content-Length = len（区间或全量），Accept-Ranges 声明支持断点续传；keep-alive 可继续） |
| 方法 | `void file(string path, string downloadName)` | 文件下载（sendFile + Content-Disposition 附件头） |
| 方法 | `void _writeStreamHead()` | 流式响应头直发（状态行 + chunked/Connection + 用户头；引擎管理头 跳过；Transfer-Encoding 同引擎管理） |
| 方法 | `string _userHeadersText()` | 用户附加头文本（引擎管理头跳过：Content-Type/Length/Connection/ Transfer-Encoding；跨类静态调用的实参先拷局部——HttpHeaders 纪律）。 Set-Cookie 不经 HttpHeaders（多行重复语义）：逐条独立成行，P10 |
| 方法 | `void _terminal()` | 终端守卫 |
