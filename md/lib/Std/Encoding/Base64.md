# Encoding/Base64.sl

> 源文件：`Encoding/Base64.sl`

## class `Base64`

- **说明**：SLang 标准库类型 Base64（详见源文件）。

| 类型 | 签名 | 说明 |
|------|------|------|
| 方法 | `Int32 encodeBound(Int32 inputSize)` | ── 尺寸预查 ── 编码 inputSize 字节所需的 Base64 文本尺寸（((n+2)/3)*4 向上取整）； inputSize 为负或超出 Int32 容器上限时返回 0 |
| 方法 | `ByteBuffer encode(ByteBuffer src)` | ── 编码 / 解码 ── 把 src 的可读区编码为 Base64 文本，返回新缓冲；src 索引不变 |
| 方法 | `ByteBuffer decode(ByteBuffer src)` | 解码 Base64 文本（本类或任何 RFC 4648 标准产物均可），返回新缓冲； src 索引不变。文本非法（长度非 4 倍数 / 非法字符 / 填充位置不合法） 时抛 DecodeFailed |
| 方法 | `ByteBuffer encode(string src)` | ── string / UInt8Array 入口（经 Core.ByteBuffer 适配，本体同上）── 编码 UTF-8 文本字节，返回新缓冲（中间缓冲即时释放，不依赖注册表 GC） |
| 方法 | `ByteBuffer encode(UInt8Array src)` | 编码整个字节数组，返回新缓冲 |
| 方法 | `string encodeToString(ByteBuffer src)` | ── 输出适配（中间缓冲即时释放）── 编码并按 UTF-8 解码为 Base64 文本字符串 |
| 方法 | `string encodeToString(string src)` | 文本到文本高频快捷入口：UTF-8 文本 → Base64 文本 |
| 方法 | `string decodeString(ByteBuffer src)` | 解码并按 UTF-8 还原为原始文本（内嵌 NUL 截断语义同 ByteBuffer.toString） |
| 方法 | `string decodeString(string src)` | 文本到文本高频快捷入口：Base64 文本 → 原始 UTF-8 文本 |
| 方法 | `UInt8Array decodeBytes(ByteBuffer src)` | 解码并导出为字节数组 |
| 方法 | `ByteBuffer encode(ByteStream src)` | ── Stream 桥接（L0 字节流，见 Core/IO/ByteStream.sl）── 读源流至 EOF 并编码（源流读位置推进到末尾；中间缓冲即时释放）。 慎用于无限流——readAll(0) 会一直读到 EOF |
| 方法 | `void encodeTo(ByteStream dst, ByteBuffer src)` | 编码 src 并写入目标流（中间缓冲即时释放，数据归属 dst） |
| 方法 | `void decodeTo(ByteStream dst, ByteBuffer src)` | 解码 src 并写入目标流（中间缓冲即时释放，数据归属 dst） |
