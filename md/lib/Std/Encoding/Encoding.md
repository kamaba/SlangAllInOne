# Encoding/Encoding.sl

> 源文件：`Encoding/Encoding.sl`

## class `Encoding`

- **说明**：SLang 标准库类型 Encoding（详见源文件）。

| 类型 | 签名 | 说明 |
|------|------|------|
| 方法 | `Int32 codeValue(EncodingCode code)` | ── 编码代码 ── enum -&gt; Int32 不能用 as 转换（Front 不支持），显式映射为 C 侧 sl_core_encoding.h 的 CORE_ENCODING_* 值（逐项一一对应） |
| 方法 | `EncodingCode codeFromName(string name)` | 按标准名查编码代码（精确匹配小写规范名，标准库暂无 toLower）： utf-8 / utf-8-bom / utf-16le / utf-16le-bom / utf-16be / utf-16be-bom / utf-32le / utf-32le-bom / utf-32be / utf-32be-bom / gb2312 / ascii； 未知名抛 UnknownEncoding |
| 方法 | `string nameFromCode(EncodingCode code)` | 编码代码 -&gt; 标准名（小写规范名，codeFromName 的逆映射） |
| 方法 | `bool hasBom(EncodingCode code)` | 该编码变体编码时是否写入 BOM（仅 *_BOM 系为 true） |
| 方法 | `Int32 maxByteCount(EncodingCode code, Int32 inputSize)` | ── 尺寸预查 ── 编码 inputSize 字节 UTF-8 输入最坏情况下的目标编码字节数（含 BOM）； inputSize 为负或超出 Int32 容器上限时返回 0 |
| 方法 | `Int32 maxCharCount(EncodingCode code, Int32 inputSize)` | 解码 inputSize 字节目标编码输入最坏情况下的 UTF-8 输出字节数 （BOM 不产生输出）；inputSize 为负或超出 Int32 容器上限时返回 0 |
| 方法 | `ByteBuffer encode(EncodingCode code, string text)` | ── 编码 / 解码 ── 把 UTF-8 文本编码为目标编码字节流，返回新缓冲（中间缓冲即时释放）； 目标字符集无法表示的码点抛 EncodeFailed |
| 方法 | `ByteBuffer encode(EncodingCode code, ByteBuffer src)` | 把 src 可读区的 UTF-8 字节编码为目标编码字节流，返回新缓冲； src 索引不变。输入非法 UTF-8 或含不可表示码点抛 EncodeFailed |
| 方法 | `string decode(EncodingCode code, ByteBuffer src)` | 把 src 可读区的目标编码字节解码为 UTF-8 文本；src 索引不变。 开头 BOM 自动识别并剥离；非法字节序列抛 DecodeFailed； 内嵌 NUL 截断语义同 ByteBuffer.toString |
| 方法 | `ByteBuffer decodeBytes(EncodingCode code, ByteBuffer src)` | 解码为 UTF-8 字节缓冲（不经 string，保留全部字节含 NUL）， decode 的字节级本体；中间无缓冲，直接返回注册表缓冲 |
| 方法 | `ByteBuffer convert(EncodingCode fromCode, EncodingCode toCode, ByteBuffer src)` | 跨编码转换（C# Encoding.Convert 对位）：fromCode 字节 -&gt; UTF-8 -&gt; toCode 字节，返回新缓冲；src 索引不变，中间 UTF-8 缓冲即时释放 |
| 方法 | `ByteBuffer preamble(EncodingCode code)` | ── BOM / 前导 ── 返回该编码的 BOM 字节（新缓冲；无 BOM 编码为空缓冲， 如 GB2312 / ASCII 与非 *_BOM 变体） |

## class `Utf8`

- **说明**：便捷类 — 常用编码零枚举样板（本体全部转发 Encoding 中枢类） UTF-8（无 BOM；解码自动识别并剥离 BOM）

| 类型 | 签名 | 说明 |
|------|------|------|
| 方法 | `ByteBuffer encode(string text)` | 转换 / 序列化 / 格式化（encode）。 |
| 方法 | `ByteBuffer encodeBom(string text)` | 显式带 BOM 变体（EF BB BF 头，Windows 记事本互通） |
| 方法 | `string decode(ByteBuffer src)` | 转换 / 序列化 / 格式化（decode）。 |
| 方法 | `Int32 maxByteCount(Int32 inputSize)` | 执行 maxByteCount(inputSize)，行为详见源实现。 |
| 方法 | `Int32 maxCharCount(Int32 inputSize)` | 执行 maxCharCount(inputSize)，行为详见源实现。 |

## class `Unicode`

- **说明**：UTF-16 小端（C# Encoding.Unicode 对位；解码自动识别 BE BOM 翻转端序）

| 类型 | 签名 | 说明 |
|------|------|------|
| 方法 | `ByteBuffer encode(string text)` | 转换 / 序列化 / 格式化（encode）。 |
| 方法 | `ByteBuffer encodeBom(string text)` | 显式带 BOM 变体（FF FE 头） |
| 方法 | `string decode(ByteBuffer src)` | 转换 / 序列化 / 格式化（decode）。 |
| 方法 | `Int32 maxByteCount(Int32 inputSize)` | 执行 maxByteCount(inputSize)，行为详见源实现。 |
| 方法 | `Int32 maxCharCount(Int32 inputSize)` | 执行 maxCharCount(inputSize)，行为详见源实现。 |

## class `BigEndianUnicode`

- **说明**：UTF-16 大端（C# Encoding.BigEndianUnicode 对位；解码自动识别 LE BOM）

| 类型 | 签名 | 说明 |
|------|------|------|
| 方法 | `ByteBuffer encode(string text)` | 转换 / 序列化 / 格式化（encode）。 |
| 方法 | `ByteBuffer encodeBom(string text)` | 显式带 BOM 变体（FE FF 头） |
| 方法 | `string decode(ByteBuffer src)` | 转换 / 序列化 / 格式化（decode）。 |
| 方法 | `Int32 maxByteCount(Int32 inputSize)` | 执行 maxByteCount(inputSize)，行为详见源实现。 |
| 方法 | `Int32 maxCharCount(Int32 inputSize)` | 执行 maxCharCount(inputSize)，行为详见源实现。 |

## class `Gb2312`

- **说明**：GB2312（EUC-CN：双字节 A1A1-F7FE 查表 + ASCII 透传； 表外字符抛 EncodeFailed，未赋值位抛 DecodeFailed）

| 类型 | 签名 | 说明 |
|------|------|------|
| 方法 | `ByteBuffer encode(string text)` | 转换 / 序列化 / 格式化（encode）。 |
| 方法 | `string decode(ByteBuffer src)` | 转换 / 序列化 / 格式化（decode）。 |
| 方法 | `Int32 maxByteCount(Int32 inputSize)` | 执行 maxByteCount(inputSize)，行为详见源实现。 |
| 方法 | `Int32 maxCharCount(Int32 inputSize)` | 执行 maxCharCount(inputSize)，行为详见源实现。 |

## class `Ascii`

- **说明**：严格 7 位 ASCII（<0x80 透传；含任何高位字节的输入抛 EncodeFailed / DecodeFailed——不做 1:1 字节映射的宽松 latin-1 语义）

| 类型 | 签名 | 说明 |
|------|------|------|
| 方法 | `ByteBuffer encode(string text)` | 转换 / 序列化 / 格式化（encode）。 |
| 方法 | `string decode(ByteBuffer src)` | 转换 / 序列化 / 格式化（decode）。 |
| 方法 | `Int32 maxByteCount(Int32 inputSize)` | 执行 maxByteCount(inputSize)，行为详见源实现。 |
| 方法 | `Int32 maxCharCount(Int32 inputSize)` | 执行 maxCharCount(inputSize)，行为详见源实现。 |
