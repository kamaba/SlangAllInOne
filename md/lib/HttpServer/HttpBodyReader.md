# HttpBodyReader.sl

> 源文件：`HttpBodyReader.sl`

## class `HttpBodyReader`

- **说明**：SLang 标准库类型 HttpBodyReader（详见源文件）。

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `ByteBuffer _buf = null` | 字段 _buf（类型见签名）。 |
| 字段 | `Int64 _remain = 0` | Content-Length 模式：剩余字节数（-1 = chunked / 0 = 结束） |
| 字段 | `bool _chunked = false` | chunked 模式标志 |
| 字段 | `Int32 _chunkRemain = 0` | chunked 当前块剩余（0 = 待读块头） |
| 字段 | `bool _chunkEnd = false` | chunked 已见终止块 |
| 字段 | `Int64 _total = 0` | 累计已读 + 上限（超限抛 LimitExceeded） |
| 字段 | `Int64 _maxBytes = 0` | 字段 _maxBytes（类型见签名）。 |
| 字段 | `bool _done = false` | 消费完整（CL 读满 / chunked 终止块已消化） |
| 构造 | `_init_(Net.NetStream conn, ByteBuffer buf, Int64 contentLength, bool chunked, Int64 maxBytes)` | 引擎构造（Request._bindStream → req.bodyStream()；用户勿直接 new） |
| 属性 | `get bool isDone()` | 是否已消费完整（引擎 keep-alive 判定用） |
| 方法 | `Int32 read(ByteBuffer dst)` | 读一段 body 入 dst 可写区：返回本次字节数（0 = 结束）； EOF 截断抛 Net.HttpError.Protocol；超限抛 StreamBodyError.LimitExceeded |
| 方法 | `ByteBuffer readAll()` | 聚合全量（便捷形态；超大 body 请用 read 循环 + FileStream 落盘） |
| 方法 | `Int32 _readCl(ByteBuffer dst)` | ── Content-Length 模式 ── |
| 方法 | `Int32 _readChunked(ByteBuffer dst)` | ── chunked 模式 ── |
| 方法 | `Int32 _pull(ByteBuffer dst, Int32 take)` | 底层拉取：先消费 _buf 预读，不足再从连接读（_readBytesChecked 同款； 但 dst 只填 take 字节且返回实际值——EOF 返回 0 由调用方判协议错误） |
