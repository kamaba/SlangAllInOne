# Encoding/Md5.sl

> 源文件：`Encoding/Md5.sl`

## class `Md5`

- **说明**：SLang 标准库类型 Md5（详见源文件）。

| 类型 | 签名 | 说明 |
|------|------|------|
| 方法 | `ByteBuffer digest(ByteBuffer src)` | ── 摘要 ── 计算 src 可读区的 MD5 摘要，返回新 16 字节缓冲；src 索引不变 |
| 方法 | `ByteBuffer digest(string src)` | 计算 UTF-8 文本字节的 MD5 摘要，返回新缓冲（中间缓冲即时释放） |
| 方法 | `string digestHex(ByteBuffer src)` | 摘要并输出为 32 字符小写十六进制串 |
| 方法 | `string digestHex(string src)` | 文本到文本高频快捷入口：UTF-8 文本 -&gt; 小写十六进制摘要 |
