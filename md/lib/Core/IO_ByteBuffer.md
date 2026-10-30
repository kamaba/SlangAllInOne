# IO/ByteBuffer.sl

> 源文件：`IO/ByteBuffer.sl`

## class `ByteBuffer`

- **说明**：SLang 标准库类型 ByteBuffer（详见源文件）。

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `Int64 _bid = 0` | C VM 端注册表句柄：0 = 未持有 / 已释放 |
| 方法 | `override _init_()` | ── 构造 ── |
| 构造 | `_init_(Int32 initialCapacity)` | 构造方法，初始化本类型实例。 |
| 方法 | `ByteBuffer fromBytes(UInt8Array bytes)` | ── 静态工厂（destroy-then-replace，防注册表句柄泄漏） ── |
| 方法 | `ByteBuffer wrap(UInt8Array bytes)` | P0：与 fromBytes 等价的深拷贝语义，零拷贝待 root-pin 机制后启用 |
| 方法 | `ByteBuffer fromString(string text)` | 执行 fromString(text)，行为详见源实现。 |
| 方法 | `ByteBuffer fromHex(string hex)` | 执行 fromHex(hex)，行为详见源实现。 |
| 方法 | `ByteBuffer fromHandle(Int64 handle)` | 供 Std 等跨模块将系统调用返回的注册表 id 包装成 ByteBuffer 对象 （Lz4/Zlib 压缩等返回新缓冲的场景；接管 id，禁止与现有句柄重复持有） |
| 属性 | `get Int32 readerIndex()` | ── 索引与容量属性 ── |
| 属性 | `set void readerIndex(Int32 index)` | 设置 readerIndex 的值。 |
| 属性 | `get Int32 writerIndex()` | 获取 writerIndex 的值。 |
| 属性 | `set void writerIndex(Int32 index)` | 设置 writerIndex 的值。 |
| 属性 | `get Int32 capacity()` | 获取 capacity 的值。 |
| 属性 | `get Int32 maxCapacity()` | 获取 maxCapacity 的值。 |
| 属性 | `get Int32 readableBytes()` | 获取 readableBytes 的值。 |
| 属性 | `get Int32 writableBytes()` | 获取 writableBytes 的值。 |
| 属性 | `get Int64 handle()` | 原生句柄（FileStream 等原生流直读写；仅供标准库内部使用） |
| 方法 | `void ensureWritable(Int32 minWritableBytes)` | ── 容量管理 ── 超出 maxCapacity 时抛 CapacityExceeded |
| 方法 | `void discardReadBytes()` | 将已读区滑动归零（压缩碎片，代价是 memmove） |
| 方法 | `void clear()` | readerIndex = writerIndex = 0（不清底层数组） |
| 方法 | `void shrink()` | capacity 收缩到 readableBytes |
| 方法 | `UInt8 readU8()` | ── 定宽读（推进 readerIndex，先做可读性守卫） ── |
| 方法 | `bool readBool()` | 执行 readBool()。 |
| 方法 | `Int16 readI16Le()` | 执行 readI16Le()。 |
| 方法 | `Int16 readI16Be()` | 执行 readI16Be()。 |
| 方法 | `UInt16 readU16Le()` | 执行 readU16Le()。 |
| 方法 | `UInt16 readU16Be()` | 执行 readU16Be()。 |
| 方法 | `Int32 readI32Le()` | 执行 readI32Le()。 |
| 方法 | `Int32 readI32Be()` | 执行 readI32Be()。 |
| 方法 | `UInt32 readU32Le()` | 执行 readU32Le()。 |
| 方法 | `UInt32 readU32Be()` | 执行 readU32Be()。 |
| 方法 | `Int64 readI64Le()` | 执行 readI64Le()。 |
| 方法 | `Int64 readI64Be()` | 执行 readI64Be()。 |
| 方法 | `UInt64 readU64Le()` | 执行 readU64Le()。 |
| 方法 | `UInt64 readU64Be()` | 执行 readU64Be()。 |
| 方法 | `Float32 readF32Le()` | 执行 readF32Le()。 |
| 方法 | `Float32 readF32Be()` | 执行 readF32Be()。 |
| 方法 | `Float64 readF64Le()` | 执行 readF64Le()。 |
| 方法 | `Float64 readF64Be()` | 执行 readF64Be()。 |
| 方法 | `UInt64 readVarUint()` | ── 变长读写（varint/zigzag，STREAM_DESIGN.md §15.3） ── 无符号 LEB128；截断时返回 0 且不推进 readerIndex（以 readerIndex 是否前移判断成功）。设计偏差：返回 UInt64 而非 Int64（无符号语义完整） |
| 方法 | `Int64 readVarInt()` | 有符号：LEB128 + ZigZag |
| 方法 | `void writeVarUint(Int64 value)` | 无符号 LEB128 编码，返回写入字节数（1..10） |
| 方法 | `void writeVarInt(Int64 value)` | ZigZag + LEB128 编码 |
| 方法 | `Int32 varUintEncodedSize(Int64 value)` | 编码长度预查（长度前缀分帧用），不写缓冲 |
| 方法 | `void readBytes(ByteBuffer dst, Int32 len)` | ── 批量搬运 ── 把 this 的 len 字节搬运到 dst（双方索引各自推进；经临时堆缓冲中转， 切片/副本视图重叠也不会互相污染） |
| 方法 | `void writeBytes(ByteBuffer src)` | 搬入 src 的全部可读字节 |
| 方法 | `void writeBytes(ByteBuffer src, Int32 len)` | IO 读写 / 流控制（writeBytes）。 |
| 方法 | `UInt8Array readByteArray(Int32 len)` | 读出 len 字节为新数组（len 钳制到 readableBytes） |
| 方法 | `string readString(Int32 len)` | 读出 len 字节并按 UTF-8 解码为字符串（SL 字符串为 C 风格 \0 结尾，内嵌 NUL 会截断；二进制安全用 readByteArray） |
| 方法 | `string readLine()` | 读到行尾（含 '\n'）；无剩余行时返回 null，不抛异常 |
| 方法 | `void skipBytes(Int32 len)` | 跳过 len 字节（只推进 readerIndex） |
| 方法 | `void writeByteArray(UInt8Array bytes)` | IO 读写 / 流控制（writeByteArray）。 |
| 方法 | `void writeString(string text)` | 按 UTF-8 追加文本字节 |
| 方法 | `void writeU8(UInt8 value)` | ── 定宽写（推进 writerIndex，容量不足自动扩容） ── |
| 方法 | `void writeBool(bool value)` | IO 读写 / 流控制（writeBool）。 |
| 方法 | `void writeI16Le(Int16 value)` | IO 读写 / 流控制（writeI16Le）。 |
| 方法 | `void writeI16Be(Int16 value)` | IO 读写 / 流控制（writeI16Be）。 |
| 方法 | `void writeU16Le(UInt16 value)` | IO 读写 / 流控制（writeU16Le）。 |
| 方法 | `void writeU16Be(UInt16 value)` | IO 读写 / 流控制（writeU16Be）。 |
| 方法 | `void writeI32Le(Int32 value)` | IO 读写 / 流控制（writeI32Le）。 |
| 方法 | `void writeI32Be(Int32 value)` | IO 读写 / 流控制（writeI32Be）。 |
| 方法 | `void writeU32Le(UInt32 value)` | IO 读写 / 流控制（writeU32Le）。 |
| 方法 | `void writeU32Be(UInt32 value)` | IO 读写 / 流控制（writeU32Be）。 |
| 方法 | `void writeI64Le(Int64 value)` | IO 读写 / 流控制（writeI64Le）。 |
| 方法 | `void writeI64Be(Int64 value)` | IO 读写 / 流控制（writeI64Be）。 |
| 方法 | `void writeU64Le(UInt64 value)` | IO 读写 / 流控制（writeU64Le）。 |
| 方法 | `void writeU64Be(UInt64 value)` | IO 读写 / 流控制（writeU64Be）。 |
| 方法 | `void writeF32Le(Float32 value)` | IO 读写 / 流控制（writeF32Le）。 |
| 方法 | `void writeF32Be(Float32 value)` | IO 读写 / 流控制（writeF32Be）。 |
| 方法 | `void writeF64Le(Float64 value)` | IO 读写 / 流控制（writeF64Le）。 |
| 方法 | `void writeF64Be(Float64 value)` | IO 读写 / 流控制（writeF64Be）。 |
| 方法 | `ByteBuffer slice()` | ── 视图（共享底层存储；经注册表句柄引用同一 root） ── 可读区视图（从 readerIndex 起，长 readableBytes） |
| 方法 | `ByteBuffer slice(Int32 index, Int32 length)` | [index, index+length) 视图，越界抛 IndexOutOfRange |
| 方法 | `ByteBuffer duplicate()` | 共享全部存储的副本视图（独立双索引） |
| 方法 | `ByteBuffer copy()` | 深拷贝（独立存储） |
| 方法 | `Int32 indexOf(UInt8 value)` | ── 查找与比较（可读区语义；失败返回默认值，不抛异常） ── 从 readerIndex 起找单个字节，返回相对 readerIndex 的偏移，未找到返回 -1 |
| 方法 | `Int32 indexOf(ByteBuffer pattern)` | 从 readerIndex 起找 pattern，返回相对 readerIndex 的偏移，未找到返回 -1 |
| 方法 | `bool startsWith(ByteBuffer prefix)` | 可读区是否以 prefix 开头（从 readerIndex 起比较） |
| 方法 | `bool equals(ByteBuffer other)` | 可读区逐字节相等（对 Object.equals(object) 的类型重载） |
| 方法 | `UInt8Array toArray()` | ── 转换 ── 可读区导出为数组拷贝（不改变索引） |
| 方法 | `string toHex()` | 可读区导出为小写十六进制串（不改变索引） |
| 方法 | `string toString()` | 可读区按 UTF-8 解码（不改变索引） |
| 属性 | `get Int32 hashCode()` | 可读区 FNV-1a 哈希（值语义；与 Object.hashCode 的 getter 形式一致） |
| 方法 | `void release()` | ── 生命周期（设计文档 §4.1 补充项：注册表手动释放入口） ── 幂等：释放后句柄归零，后续读写由守卫抛 BufferError.Released |
