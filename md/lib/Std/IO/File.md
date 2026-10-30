# IO/File.sl

> 源文件：`IO/File.sl`

## class `File`

- **说明**：SLang 标准库类型 File（详见源文件）。

| 类型 | 签名 | 说明 |
|------|------|------|
| 方法 | `bool exists(string path)` | 判断文件是否存在 类似 C# File.Exists(string path) |
| 方法 | `bool delete(string path)` | 删除文件 类似 C# File.Delete(string path) |
| 方法 | `bool copy(string src, string dst)` | 复制文件 类似 C# File.Copy(string src, string dst) |
| 方法 | `bool move(string src, string dst)` | 移动/重命名文件 类似 C# File.Move(string src, string dst) |
| 方法 | `Int64 getSize(string path)` | 获取文件大小（字节） 类似 C# new FileInfo(path).Length |
| 方法 | `string readAllText(string path)` | 读取文件全部文本 类似 C# File.ReadAllText(string path) |
| 方法 | `bool writeAllText(string path, string content)` | 写入文件全部文本（覆盖） 类似 C# File.WriteAllText(string path, string content) |
| 方法 | `bool appendText(string path, string content)` | 追加文本到文件末尾 类似 C# File.AppendAllText(string path, string content) |
| 方法 | `FileStream openRead(string path)` | ── 流式接口（STREAM_DESIGN.md §4.4）── 打开只读文件流 类似 C# File.OpenRead(string path) |
| 方法 | `FileStream openWrite(string path)` | 打开写文件流（存在则截断） 类似 C# File.OpenWrite(string path) |
| 方法 | `UInt8Array readAllBytes(string path)` | 读取文件全部字节 类似 C# File.ReadAllBytes(string path) |
| 方法 | `bool writeAllBytes(string path, UInt8Array bytes)` | 写入字节到文件（覆盖） 类似 C# File.WriteAllBytes(string path, byte[] bytes) |
