# IO/Directory.sl

> 源文件：`IO/Directory.sl`

## class `IO`

- **说明**：SLang 标准库类型 IO（详见源文件）。

| 类型 | 签名 | 说明 |
|------|------|------|
| 方法 | `bool exists(string path)` | 判断目录是否存在 类似 C# Directory.Exists(string path) |
| 方法 | `bool createDirectory(string path)` | 创建目录（含父目录） 类似 C# Directory.CreateDirectory(string path) |
| 方法 | `bool delete(string path)` | 删除空目录 类似 C# Directory.Delete(string path) |
| 方法 | `string getCurrentDirectory()` | 获取当前工作目录 类似 C# Directory.GetCurrentDirectory() |
| 方法 | `bool setCurrentDirectory(string path)` | 设置当前工作目录 类似 C# Directory.SetCurrentDirectory(string path) |
| 方法 | `string getFiles(string path)` | 列出目录下的文件和子目录名（换行分隔的字符串） 类似 C# Directory.GetFileSystemEntries(string path) |
| 属性 | `get string current()` | 获取当前目录 |
