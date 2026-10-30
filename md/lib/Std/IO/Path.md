# IO/Path.sl

> 源文件：`IO/Path.sl`

## class `IO`

- **说明**：Path 路径处理工具类（纯静态） 参考 C# System.IO.Path 说明： - 底层路径运算来自 C VM 系统调用（SystemPath*，注册见 Std.jsonc systemCalls） - 命名对照 C#：IsPathRooted -> isPathRooted、GetDirectoryName -> getDirectoryName 等 - 平台探测复用 Core 的 SystemPlatformEnvGetInt("os")（1=window 2=linux 3=mac）

| 类型 | 签名 | 说明 |
|------|------|------|
| 属性 | `get string directorySeparatorChar()` | ── 平台分隔符 ───────────────────────────────────── 目录分隔符：Windows 为 "\"，Unix 为 "/" 类似 C# Path.DirectorySeparatorChar |
| 属性 | `get string altDirectorySeparatorChar()` | 备用目录分隔符：两端均为 "/" 类似 C# Path.AltDirectorySeparatorChar |
| 属性 | `get string pathSeparator()` | 环境变量列表分隔符：Windows 为 ";"，Unix 为 ":" 类似 C# Path.PathSeparator |
| 属性 | `get string volumeSeparatorChar()` | 卷分隔符：Windows 为 ":"，Unix 为 "/" 类似 C# Path.VolumeSeparatorChar |
| 方法 | `string combine(params string[] paths)` | ── 路径拼接 ───────────────────────────────────── 将多段路径拼为一个路径 空段被跳过；后段为绝对路径时覆盖已拼接的前段（与 C# 一致） 类似 C# Path.Combine(params string[] paths) |
| 方法 | `string getDirectoryName(string path)` | ── 路径分解 ───────────────────────────────────── 取目录部分（不含末尾分隔符；无分隔符时返回 ""） 类似 C# Path.GetDirectoryName(string path) |
| 方法 | `string getFileName(string path)` | 取文件名部分（含扩展名；无分隔符时返回原串） 类似 C# Path.GetFileName(string path) |
| 方法 | `string getFileNameWithoutExtension(string path)` | 取文件名（不含扩展名）部分 类似 C# Path.GetFileNameWithoutExtension(string path) |
| 方法 | `string getExtension(string path)` | 取扩展名（含前导点 "."，如 ".txt"；无扩展名返回 ""） 只在文件名部分查找点，与 C# 一致（"dir.d/file" 无扩展名） 类似 C# Path.GetExtension(string path) |
| 方法 | `string getExtensionOfName(string name)` | 在文件名中找扩展名（含点） ".gitignore" 这类以点开头的隐藏文件名不算扩展名，返回 "" |
| 方法 | `bool hasExtension(string path)` | 判断路径是否含扩展名 类似 C# Path.HasExtension(string path) |
| 方法 | `string changeExtension(string path, string extension)` | 替换扩展名（extension 含不含前导点均可；null/空串表示移除扩展名） 类似 C# Path.ChangeExtension(string path, string extension) |
| 方法 | `string getPathRoot(string path)` | ── 根与绝对路径 ───────────────────────────────── 取路径的根部分（"/" 或 "C:\"）；相对路径返回 "" 类似 C# Path.GetPathRoot(string path) |
| 方法 | `bool isPathRooted(string path)` | 判断是否绝对路径（"/..." 或 "X:/..."、"X:\..."） 类似 C# Path.IsPathRooted(string path) |
| 方法 | `string getFullPath(string path)` | 取绝对路径（相对路径按当前工作目录展开） 类似 C# Path.GetFullPath(string path) |
| 方法 | `string getTempPath()` | ── 临时路径 / 随机名 ──────────────────────────── 取临时目录（保证以目录分隔符结尾） 依次尝试环境变量 TEMP、TMP，最后回退 "/tmp" 类似 C# Path.GetTempPath() |
| 方法 | `string getRandomFileName()` | 生成随机文件名（8 位随机串 + "." + 3 位随机串，基于 GUID） 类似 C# Path.GetRandomFileName() |
