# Encoding/Sha1.sl

> 源文件：`Encoding/Sha1.sl`

## class `Sha1`

- **说明**：SLang 标准库类型 Sha1（详见源文件）。

| 类型 | 签名 | 说明 |
|------|------|------|
| 方法 | `ByteBuffer digest(ByteBuffer src)` | ── 摘要 ── 计算 src 可读区的 SHA-1 摘要，返回新 20 字节缓冲；src 索引不变 |
| 方法 | `ByteBuffer digest(string src)` | 计算 UTF-8 文本字节的 SHA-1 摘要，返回新缓冲（中间缓冲即时释放） |
| 方法 | `string digestHex(ByteBuffer src)` | ── 输出适配（中间缓冲即时释放）── 摘要并输出为 40 字符小写十六进制串 |
| 方法 | `string digestHex(string src)` | 文本到文本高频快捷入口：UTF-8 文本 -&gt; 小写十六进制摘要 |
