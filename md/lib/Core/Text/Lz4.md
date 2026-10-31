# Text/Lz4.sl

> 源文件：`Text/Lz4.sl`

## class `Lz4`

- **说明**：SLang 标准库类型 Lz4（详见源文件）。

| 类型 | 签名 | 说明 |
|------|------|------|
| 方法 | `Int32 compressBound(Int32 inputSize)` | ── 尺寸预查 ── 压缩 inputSize 字节最坏情况下的容器尺寸（4 字节头 + LZ4 上界）； inputSize 为负或超出 LZ4 单块上限（约 2GB）时返回 0 |
| 方法 | `ByteBuffer compress(ByteBuffer src)` | ── 压缩 / 解压 ── 压缩 src 的可读区，返回新缓冲；src 索引不变 |
| 方法 | `ByteBuffer decompress(ByteBuffer src)` | 解压 SystemLz4Compress 产物，返回新缓冲；src 索引不变。 数据损坏 / 截断 / 头部非法时抛 DecompressFailed |
