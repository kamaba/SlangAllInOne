# IO/ByteStream.sl

> 源文件：`IO/ByteStream.sl`

## class `MemoryStream`

- **说明**：MemoryStream — 内存流（P1 唯一 L0 具体子类） 读写共用一个 ByteBuffer：readerIndex 即 position，writerIndex 即数据尾。 序列化最常用的目标（ProtoBuf encode → MemoryStream → toArray）。

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `ByteBuffer _buf = null` | 字段 _buf（类型见签名）。 |
| 方法 | `override _init_()` | ── 构造 ── |
| 构造 | `_init_(Int32 initialCapacity)` | 构造方法，初始化本类型实例。 |
| 构造 | `_init_(ByteBuffer backing)` | 复用外部 ByteBuffer（避免二次拷贝） |
| 属性 | `get Int64 length()` | ── 能力/状态 ── |
| 属性 | `get Int64 position()` | 获取 position 的值。 |
| 属性 | `set void position(Int64 pos)` | 设置 position 的值。 |
| 方法 | `Int64 seek(Int64 offset, SeekOrigin origin)` | IO 读写 / 流控制（seek）。 |
| 方法 | `Int32 read(ByteBuffer dst)` | ── 核心读写 ── |
| 方法 | `void write(ByteBuffer src)` | IO 读写 / 流控制（write）。 |
| 方法 | `void flush()` | IO 读写 / 流控制（flush）。 |
| 方法 | `ByteBuffer toByteBuffer()` | ── 访问内部缓冲 ── 返回内部缓冲（不拷贝）；调用方继续读即从当前 readerIndex 开始 |
| 方法 | `UInt8Array toArray()` | 转换 / 序列化 / 格式化（toArray）。 |
| 方法 | `void reset()` | 清空并复位索引 |
