# Text/Toml.sl

> 源文件：`Text/Toml.sl`

## class `Text`

- **说明**：TOML 文件操作门面：在 BaseToml（内存解析/序列化/树操作基础能力）之上扩展文件读写。 BaseToml 只处理文本；本类补充文件进出（load/readFrom/save 等） 与关联路径（_path）的文件信息查询。 典型用法：Toml t = Toml.load("config.toml") -> t.getStr("server/host", "") / t.save()。

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `string _path = ""` | 当前关联的文件路径（load/readFrom/saveAs 成功时记录，save()/reload() 依据它读写） |
| 方法 | `Toml load(string path)` | ---- 静态工厂（从文件加载）---- 读取文件并解析；文件不可读或内容非法返回空实例 |
| 方法 | `bool readFrom(string path)` | ---- 实例文件操作 ---- 从文件读取并整体替换当前树；文件不存在、不可读或内容非法返回 false |
| 方法 | `bool reload()` | 按关联路径重新加载 |
| 方法 | `bool save()` | 写回关联路径；未关联路径返回 false |
| 方法 | `bool saveAs(string path)` | 写入指定路径并把它记录为关联路径 |
| 属性 | `get string path()` | ---- 关联文件信息 ---- 当前关联的文件路径（未关联为空串） |
| 属性 | `get bool fileExists()` | 关联文件是否存在 |
| 方法 | `Int64 fileSize()` | 关联文件大小（字节；未关联或不存在为 0） |
