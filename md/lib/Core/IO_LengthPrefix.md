# IO/LengthPrefix.sl

> 源文件：`IO/LengthPrefix.sl`

## class `LengthPrefix`

- **说明**：Core/IO/LengthPrefix.sl — 长度前缀分帧机制（STREAM_DESIGN.md §8.1） P2 范围：分帧机制本体（静态工具 + 三个内部支撑类）。帧格式 `varuint(len) + payload`（无符号 LEB128 长度前缀 + 裸 payload）， 供 ProtoCodec 流式编解码（§8.4）复用；设计稿中的 LengthPrefixCodec StreamTransformer（§6.3）为 P3，不落本文件。 语义要点： - 帧边界：varuint 长度前缀声明 payload 字节数，接收端按长度切帧。 - 半包契约：长度前缀或 payload 不完整时 tryReadFrame 返回 null， 且不消费 readerIndex（varint 读走的索引已回退），调用方可继续 累积后重试（半包续接）。 - 超限契约：payload 长度超过 maxFrame 抛 StreamIOError.FrameTooLarge （防恶意长度前缀撑爆内存；readFrameLength 以 -2 报告，drainFrames 转 throw）。 - varint 截断判定沿用 ProtocalBuffers.sl 先例：C 层截断返回 0 且 不推进 readerIndex，以 readerIndex 是否前移判成功。 已知偏差（详见设计文档 §17 实现注记）： - 设计稿 bind() 因 `bind` 为 SL 保留 token（类头语法位）改名 bindStream，语义不变。 - 设计稿 LengthPrefixCodec（StreamTransformer 形态）在 P3 行；P2 先以静态工具 + ProtoCodec 薄壳落地分帧机制。 LengthPrefix — 长度前缀分帧静态工具（无实例）

| 类型 | 签名 | 说明 |
|------|------|------|
| 方法 | `Int32 defaultMaxFrame()` | 默认单帧上限 64 KiB（设计稿 §12.3 WebSocket maxFrameSize 同值） |
| 方法 | `void writeFrame(ByteBuffer dst, ByteBuffer payload)` | ── 写侧：帧 = varuint(payload 可读长度) + payload 可读区 ── 把 payload 的可读区打包成帧写入 dst（不检查上限，写入方自决） |
| 方法 | `void writeFrameBytes(ByteBuffer dst, UInt8Array payload)` | 数组形式（payload 整体为一帧） |
| 方法 | `Int32 readFrameLength(ByteBuffer src, Int32 maxFrame)` | ── 读侧：单帧尝试解析 ── 读取长度前缀。返回值： &gt;= 0  完整帧的 payload 长度（varint 已被消费，payload 未动） -1    半包（varint 或 payload 不完整；readerIndex 已回退） -2    超限（payload 长度 &gt; maxFrame；readerIndex 已回退） |
| 方法 | `ByteBuffer tryReadFrame(ByteBuffer src, Int32 maxFrame)` | 尝试从 src 读出一帧（半包续接语义）。 成功 → 独立 ByteBuffer（消费 src 对应区间） 半包 → null（不消费 readerIndex） 超限 → throw StreamIOError.FrameTooLarge |

## class `_FramedDecodeStream<T>`

- **说明**：_FramedDecodeStream<T> — 拉模式分帧解码流 生产协程循环 read → acc 累积 → drainFrames；异常（含 EOF 残留半包的 UnexpectedEof）经 label{}catch{} 统一转投 addError 后 close。

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `ByteStream _src = null` | 字段 _src（类型见签名）。 |
| 字段 | `Codec&lt;T, ByteBuffer&gt; _codec = null` | 字段 ByteBuffer（类型见签名）。 |
| 字段 | `Int32 _maxFrame = 0` | 字段 _maxFrame（类型见签名）。 |
| 构造 | `_init_(ByteStream src, Codec&lt;T, ByteBuffer&gt; codec, Int32 maxFrame)` | 构造方法，初始化本类型实例。 |
| 方法 | `StreamSubscription listen(Function onData, Function onError, Function onDone, bool cancelOnError)` | 迭代器 / 订阅控制（listen）。 |

## class `_FrameEncodeSink<T>`

- **说明**：_FrameEncodeSink<T> — 分帧编码写入端

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `ByteStream _dst = null` | 字段 _dst（类型见签名）。 |
| 字段 | `Codec&lt;T, ByteBuffer&gt; _codec = null` | 字段 ByteBuffer（类型见签名）。 |
| 字段 | `Int32 _maxFrame = 0` | 字段 _maxFrame（类型见签名）。 |
| 构造 | `_init_(ByteStream dst, Codec&lt;T, ByteBuffer&gt; codec, Int32 maxFrame)` | 构造方法，初始化本类型实例。 |
| 方法 | `void add(T chunk)` | 覆写自 StreamSink.add（父链无 throws）；throws 为本实现新增—— 超限/底层写失败以异常上抛，由调用方决定降级策略。 |
| 方法 | `void close()` | IO 读写 / 流控制（close）。 |

## class `_FramedBindStream<T>`

- **说明**：_FramedBindStream<T> — 推模式分帧解码流（chunked decoder） 订阅上游 ByteBuffer chunk 流：onData 累积 + 抽帧转发；上游错误透传； 上游 done 时残留半包转 UnexpectedEof。中转 controller 无缓冲上限 （转发不丢事件）。

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `Stream&lt;ByteBuffer&gt; _source = null` | 字段 _source（类型见签名）。 |
| 字段 | `Codec&lt;T, ByteBuffer&gt; _codec = null` | 字段 ByteBuffer（类型见签名）。 |
| 字段 | `Int32 _maxFrame = 0` | 字段 _maxFrame（类型见签名）。 |
| 构造 | `_init_(Stream&lt;ByteBuffer&gt; source, Codec&lt;T, ByteBuffer&gt; codec, Int32 maxFrame)` | 构造方法，初始化本类型实例。 |
| 方法 | `StreamSubscription listen(Function onData, Function onError, Function onDone, bool cancelOnError)` | 迭代器 / 订阅控制（listen）。 |
