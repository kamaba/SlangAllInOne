# Zip/GZip.sl

> 源文件：`Zip/GZip.sl`

## class `GZip`

- **说明**：SLang 标准库类型 GZip（详见源文件）。

| 类型 | 签名 | 说明 |
|------|------|------|
| 方法 | `Int32 compressBound(Int32 inputSize)` | ── 尺寸预查 ── 压缩 inputSize 字节最坏情况下的 gzip 流尺寸（RFC 1952 头尾 + DEFLATE 上界）； inputSize 为负或超出 Int32 容器上限时返回 0 |
| 方法 | `ByteBuffer compress(ByteBuffer src)` | ── 压缩 / 解压 ── 压缩 src 的可读区，返回新缓冲；src 索引不变 |
| 方法 | `ByteBuffer decompress(ByteBuffer src)` | 解压 gzip 流（本类或 gzip 工具产物均可），返回新缓冲；src 索引不变。 数据损坏 / 截断 / 尾部 ISIZE 与实际不符时抛 DecompressFailed |
| 方法 | `ByteBuffer compress(string src)` | ── string / UInt8Array 入口（经 Core.ByteBuffer 适配，本体同上）── 压缩 UTF-8 文本字节，返回新缓冲（中间缓冲即时释放，不依赖注册表 GC） |
| 方法 | `ByteBuffer compress(UInt8Array src)` | 压缩整个字节数组，返回新缓冲 |
| 方法 | `string decompressString(ByteBuffer src)` | 解压并按 UTF-8 解码为字符串（内嵌 NUL 截断语义同 ByteBuffer.toString） |
| 方法 | `UInt8Array decompressBytes(ByteBuffer src)` | 解压并导出为字节数组 |
| 方法 | `ByteBuffer compress(ByteStream src)` | ── Stream 桥接（L0 字节流，见 Core/IO/ByteStream.sl）── 读源流至 EOF 并压缩（源流读位置推进到末尾；中间缓冲即时释放）。 慎用于无限流——readAll(0) 会一直读到 EOF |
| 方法 | `void compressTo(ByteStream dst, ByteBuffer src)` | 压缩 src 并写入目标流（中间缓冲即时释放，数据归属 dst） |
| 方法 | `void decompressTo(ByteStream dst, ByteBuffer src)` | 解压 src 并写入目标流（中间缓冲即时释放，数据归属 dst） |
