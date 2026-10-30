# IO/ProtoCodec.sl

> 源文件：`IO/ProtoCodec.sl`

## class `ProtoCodec<T>`

- **说明**：ProtoCodec<T> — T ↔ ByteBuffer（消息对象 ↔ ProtoBuf wire format） S = T（消息对象），T = ByteBuffer（字节，分帧单位）

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `Function _encoderFn = null` | encode 闭包：T → ByteBuffer（内部用 PbWriter 编码） |
| 字段 | `Function _decoderFn = null` | decode 闭包：ByteBuffer → T（内部用 PbReader 解码） |
| 构造 | `_init_(Function encoderFn, Function decoderFn)` | 构造方法，初始化本类型实例。 |
| 属性 | `get Converter&lt;T, ByteBuffer&gt; encoder()` | ── Codec 契约：encoder / decoder 为闭包适配的 Converter ── |
| 属性 | `get Converter&lt;ByteBuffer, T&gt; decoder()` | 获取 get Converter&lt;ByteBuffer, T&gt; decoder() 的值。 |
| 方法 | `Stream&lt;T&gt; decodeStream(ByteStream src)` | Converter 契约：分块编码方向（startChunkedConversion 的通用覆写） 由基类 _ProtoCodecBase&lt;S,T&gt; 提供，逐消息委托 encoder 落地。 ── 分帧流式三件套（机制在 LengthPrefix，见 §8.1）── 字节流 → 分帧多消息流（varint 长度前缀 + 半包续接， RPC / 文件批量存储的标准做法） |
| 方法 | `Stream&lt;T&gt; decodeStream(ByteStream src, Int32 maxFrame)` | 转换 / 序列化 / 格式化（decodeStream）。 |
| 方法 | `StreamSink&lt;T&gt; encodeSink(ByteStream dst)` | 消息写入端：add(msg) → encode → 帧直写 |
| 方法 | `StreamSink&lt;T&gt; encodeSink(ByteStream dst, Int32 maxFrame)` | 转换 / 序列化 / 格式化（encodeSink）。 |
| 方法 | `Stream&lt;T&gt; bindStream(Stream&lt;ByteBuffer&gt; chunks)` | chunked decoder：Stream&lt;ByteBuffer&gt; → Stream&lt;T&gt;（处理半包） |
| 方法 | `Stream&lt;T&gt; bindStream(Stream&lt;ByteBuffer&gt; chunks, Int32 maxFrame)` | 执行 bindStream(chunks, maxFrame)，行为详见源实现。 |

## class `_FnConverter<S,T>`

- **说明**：_FnConverter<S,T> — Function → Converter 适配器（闭包注入的落地实现）

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `Function _fn = null` | 字段 _fn（类型见签名）。 |
| 构造 | `_init_(Function fn)` | 构造方法，初始化本类型实例。 |
| 方法 | `T convert(S input)` | 转换 / 序列化 / 格式化（convert）。 |
| 方法 | `ChunkedConversionSink&lt;S&gt; startChunkedConversion(ChunkedConversionSink&lt;T&gt; sink)` | 无状态逐项分块转换：每个分块独立 convert 转发（适合逐消息 codec；有跨块状态的 codec 应提供自己的 chunked 实现） |

## class `_FnChunkSink<S,T>`

- **说明**：_FnChunkSink<S,T> — 闭包逐项分块 sink（_FnConverter 的 chunked 支撑）

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `Function _fn = null` | 字段 _fn（类型见签名）。 |
| 字段 | `ChunkedConversionSink&lt;T&gt; _sink = null` | 字段 _sink（类型见签名）。 |
| 构造 | `_init_(Function fn, ChunkedConversionSink&lt;T&gt; sink)` | 构造方法，初始化本类型实例。 |
| 方法 | `void add(S chunk)` | 添加 / 插入元素（add）。 |
| 方法 | `void close()` | IO 读写 / 流控制（close）。 |
