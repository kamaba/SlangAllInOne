# Text/ProtocalBuffers.sl

> 源文件：`Text/ProtocalBuffers.sl`

## class `PbTag`

- **说明**：字段 tag：fieldNumber(1..2^29) + wireType(0..5)

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `public Int32 fieldNumber = 0` | 字段 Int32（类型见签名）。 |
| 字段 | `public Int32 wireType = 0` | 字段 Int32（类型见签名）。 |
| 方法 | `override _init_()` | 执行 _init_()。 |
| 方法 | `PbTag make(Int32 field, Int32 wire)` | 初始化 / 创建（make）。 |
| 方法 | `Int32 encode(Int32 field, Int32 wire)` | tag 原始整数 = (field &lt;&lt; 3) \| wire |
| 方法 | `PbTag decode(Int32 raw)` | 转换 / 序列化 / 格式化（decode）。 |
| 方法 | `string toString()` | 转换为 Stringundefined 类型（toString）。 |

## class `PbCoding`

- **说明**：线格式原语薄封装：zigzag 走 C 层 SystemZigZagEncode / SystemZigZagDecode

| 类型 | 签名 | 说明 |
|------|------|------|
| 方法 | `override _init_()` | 执行 _init_()。 |
| 方法 | `Int64 mask32()` | 低 32 位的 64 位掩码（避免写 2^32 字面量）：0x10000&lt;&lt;16 - 1 |
| 方法 | `Int64 zigzagEncode32(Int32 n)` | ── zigzag：有符号 &lt;-&gt; 无符号 varint 的映射（C 层实现）────── 32 位值经 64 位 zigzag 编码数学等价（结果恒在 [0, 2^32) 内）， 解码同理，故 sint32 直接借道 64 位原语 |
| 方法 | `Int32 zigzagDecode32(Int64 value)` | 执行 zigzagDecode32(value)，行为详见源实现。 |
| 方法 | `Int64 zigzagEncode64(Int64 n)` | 执行 zigzagEncode64(n)，行为详见源实现。 |
| 方法 | `Int64 zigzagDecode64(Int64 value)` | 执行 zigzagDecode64(value)，行为详见源实现。 |

## class `PbWriter`

- **说明**：── 写入器 ─────────────────────────────────────────────────

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `ByteBuffer _buf = null` | 字段 _buf（类型见签名）。 |
| 方法 | `override _init_()` | 执行 _init_()。 |
| 属性 | `get Int32 length()` | 获取 length 的值。 |
| 方法 | `void writeRawByte(Int32 b)` | 追加一个原始字节 |
| 方法 | `void writeVarint(Int64 v)` | 原始 varint（无 zigzag）；负数按 64 位位模式写出（10 字节）， 正是 protobuf int32/int64 负值的线格式 |
| 方法 | `void writeTag(Int32 field, Int32 wire)` | IO 读写 / 流控制（writeTag）。 |
| 方法 | `void writeInt32(Int32 field, Int32 v)` | ── 整数类型 ─────────────────────────────────────────── |
| 方法 | `void writeInt64(Int32 field, Int64 v)` | IO 读写 / 流控制（writeInt64）。 |
| 方法 | `void writeUInt32(Int32 field, Int32 v)` | IO 读写 / 流控制（writeUInt32）。 |
| 方法 | `void writeUInt64(Int32 field, Int64 v)` | IO 读写 / 流控制（writeUInt64）。 |
| 方法 | `void writeSInt32(Int32 field, Int32 v)` | IO 读写 / 流控制（writeSInt32）。 |
| 方法 | `void writeSInt64(Int32 field, Int64 v)` | IO 读写 / 流控制（writeSInt64）。 |
| 方法 | `void writeBool(Int32 field, bool v)` | IO 读写 / 流控制（writeBool）。 |
| 方法 | `void writeEnum(Int32 field, Int32 v)` | IO 读写 / 流控制（writeEnum）。 |
| 方法 | `void writeFixed32(Int32 field, Int32 v)` | ── 定长小端（浮点位打包在 C 层 writeF32Le / writeF64Le 完成）── |
| 方法 | `void writeSFixed32(Int32 field, Int32 v)` | IO 读写 / 流控制（writeSFixed32）。 |
| 方法 | `void writeFixed64(Int32 field, Int64 v)` | IO 读写 / 流控制（writeFixed64）。 |
| 方法 | `void writeSFixed64(Int32 field, Int64 v)` | IO 读写 / 流控制（writeSFixed64）。 |
| 方法 | `void writeFloat(Int32 field, Float32 v)` | IO 读写 / 流控制（writeFloat）。 |
| 方法 | `void writeDouble(Int32 field, Float64 v)` | IO 读写 / 流控制（writeDouble）。 |
| 方法 | `void writeString(Int32 field, string s)` | ── 长度前缀类型 ─────────────────────────────────────── |
| 方法 | `void writeBytes(Int32 field, Array&lt;UInt8&gt; bytes)` | IO 读写 / 流控制（writeBytes）。 |
| 方法 | `void writeMessage(Int32 field, PbWriter sub)` | IO 读写 / 流控制（writeMessage）。 |
| 方法 | `Array&lt;UInt8&gt; toBytes()` | 导出最终字节数组 |
| 方法 | `string toString()` | 转换为 Stringundefined 类型（toString）。 |

## class `PbReader`

- **说明**：── 读取器 ─────────────────────────────────────────────────

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `ByteBuffer _buf = null` | 字段 _buf（类型见签名）。 |
| 方法 | `override _init_()` | 执行 _init_()。 |
| 构造 | `_init_(Array&lt;UInt8&gt; bytes)` | fromBytes 为深拷贝语义（P0 约定），读取器独立持有数据 |
| 属性 | `get bool atEnd()` | 获取 atEnd 的值。 |
| 属性 | `get Int32 position()` | 获取 position 的值。 |
| 方法 | `Int64 readVarintRaw()` | ── varint / tag ──────────────────────────────────────── 原始 varint（无 zigzag）。C 层 readVarUint 截断时返回 0 且不推进 readerIndex，此处以 readerIndex 是否前移判失败，统一抛 Underflow |
| 方法 | `PbTag readTag()` | 执行 readTag()。 |
| 方法 | `Int32 readInt32()` | ── 整数类型 ─────────────────────────────────────────── protobuf 语义：int32 解码取 varint 低 32 位再按有符号解释 |
| 方法 | `Int64 readInt64()` | 执行 readInt64()。 |
| 方法 | `Int32 readUInt32()` | 执行 readUInt32()。 |
| 方法 | `Int64 readUInt64()` | 执行 readUInt64()。 |
| 方法 | `Int32 readSInt32()` | 执行 readSInt32()。 |
| 方法 | `Int64 readSInt64()` | 执行 readSInt64()。 |
| 方法 | `bool readBool()` | 执行 readBool()。 |
| 方法 | `Int32 readEnum()` | 执行 readEnum()。 |
| 方法 | `Int32 readFixed32()` | ── 定长（浮点位重释在 C 层 readF32Le / readF64Le 完成）── |
| 方法 | `Int64 readFixed64()` | 执行 readFixed64()。 |
| 方法 | `Int32 readSFixed32()` | 执行 readSFixed32()。 |
| 方法 | `Int64 readSFixed64()` | 执行 readSFixed64()。 |
| 方法 | `Float32 readFloat()` | 执行 readFloat()。 |
| 方法 | `Float64 readDouble()` | 执行 readDouble()。 |
| 方法 | `Int32 _readLength()` | ── 长度前缀 ─────────────────────────────────────────── 长度前缀统一入口：损坏数据（负长度）按 Underflow 处理 |
| 方法 | `Array&lt;UInt8&gt; readBytes()` | 执行 readBytes()。 |
| 方法 | `string readString()` | 执行 readString()。 |
| 方法 | `PbReader readMessage()` | 拷贝方案：剥出子消息原始字节再建独立读取器， 避免视图句柄在注册表里悬挂（P0 无 root-pin 机制） |
| 方法 | `Array&lt;UInt8&gt; readMessageBytes()` | 把整个子消息原始字节剥出来（交给上层 / 其他解码器） |
| 方法 | `void skipField(Int32 wireType)` | ── 跳过未知字段（前向/后向兼容）──────────────────────── |
| 方法 | `string toString()` | 转换为 Stringundefined 类型（toString）。 |

## class `ProtocalBuffers`

- **说明**：── 门面（保留原 ProtocalBuffers 类名与 extends Object 约定）──

| 类型 | 签名 | 说明 |
|------|------|------|
| 方法 | `override _init_()` | 执行 _init_()。 |
| 方法 | `PbWriter newWriter()` | 执行 newWriter()。 |
| 方法 | `PbReader newReader(Array&lt;UInt8&gt; bytes)` | 执行 newReader(bytes)，行为详见源实现。 |
| 方法 | `string toString()` | 转换为 Stringundefined 类型（toString）。 |
