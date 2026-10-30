# StreamIo.sl

> 源文件：`StreamIo.sl`

## class `_Mime`

- **说明**：SLang/Server/StreamIo.sl — 流式写出器与 MIME 表（P2） 设计契约：SERVER_DESIGN.md §4.5 / §6.6 / 附录 B StreamWriter：chunked 流式写出（RFC 9112 §7.1：<hex 长度>\r\n<数据>\r\n 每 write 一块；close() → 0\r\n\r\n 终止块）；HTTP/1.0 降级 close-delimited（裸写不编码块，连接收尾断连，§6.6）； 状态机 Streaming → Closed（Closed 后再写抛 AlreadyResponded）。 SseWriter：text/event-stream 线格式（§6.6：event:/data:/注释行）。 背压：底层 TcpStream.write 挂起语义（发送缓冲满协程让出）； 慢客户端超时由 cfg.writeTimeoutMs 守护（引擎连接级 setWriteTimeout）。 _Mime：内置 MIME 表（附录 B；扩展名小写化匹配）。 _Mime — MIME 类型表（静态工具；staticFiles / res.file / sendFile 共用）

| 类型 | 签名 | 说明 |
|------|------|------|
| 方法 | `string of(string path)` | 按路径扩展名取 MIME（扩展名小写化；无扩展/未命中 octet-stream） |
| 方法 | `string ofExt(string ext)` | 按小写扩展名取 MIME（SERVER_DESIGN.md 附录 B） |

## class `StreamWriter`

- **说明**：StreamWriter — chunked 流式写出器（模块内构造：Response.stream()） 头部由 Response.stream() 先行发出（状态行 + Transfer-Encoding: chunked + 用户头）；本类只管块编码与终止块

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `bool _chunked = true` | false = HTTP/1.0 close-delimited（裸写，不编码块，§6.6） |
| 字段 | `bool _closed = false` | 字段 _closed（类型见签名）。 |
| 构造 | `_init_(Net.TcpStream conn, bool chunked)` | 构造方法，初始化本类型实例。 |
| 属性 | `get bool isClosed()` | 是否已关闭（引擎兜底判定用） |
| 方法 | `void write(string text)` | 写一块文本（UTF-8）；空串 no-op（避免 0 长块语义冲突） |
| 方法 | `void writeBytes(ByteBuffer payload)` | 写一块二进制（视图写出，不推进源索引）；空 no-op |
| 方法 | `void flush()` | 空操作——写路径即时下发无用户态缓冲（NetStream.flush 同款语义， 保留 API 习惯，§4.5） |
| 方法 | `void close()` | 关闭：0 长终止块（HTTP/1.0 降级 = 无操作）；幂等 |
| 方法 | `void _writeChunk(ByteBuffer payload)` | 块编码写出：&lt;hex&gt;\r\n&lt;数据&gt;\r\n（chunked）/ 裸写（close-delimited） |
| 方法 | `void _ensureClosed()` | 引擎兜底收尾（handler 退出未调 close() 时补终止块；幂等；尽力） |

## class `SseWriter`

- **说明**：SseWriter — Server-Sent Events 写出器（模块内构造：Response.sse()； 线格式 §6.6，CRLF 行界）

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `StreamWriter _w = null` | 字段 _w（类型见签名）。 |
| 构造 | `_init_(StreamWriter w)` | 构造方法，初始化本类型实例。 |
| 方法 | `void send(string payload)` | 默认事件：data: &lt;payload&gt;\r\n\r\n（data 是关键字，参数名用 payload） |
| 方法 | `void sendEvent(string event, string payload)` | 具名事件：event: &lt;event&gt;\r\ndata: &lt;payload&gt;\r\n\r\n |
| 方法 | `void comment(string text)` | 心跳注释行：: &lt;text&gt;\r\n\r\n（防中间层掐空闲连接） |
| 方法 | `void close()` | 关闭（透传底层 chunked 终止块） |
