# Text/Csv.sl

> 源文件：`Text/Csv.sl`

## class `Text`

- **说明**：CSV 文件操作门面：在 BaseCsv（内存解析/序列化/表操作基础能力）之上扩展文件读写。 BaseCsv 只提供基础方法；本类补充文件进出（load/readFrom/save/appendTo 等） 与关联路径（_path）的文件信息查询。 典型用法：Csv c = Csv.load("data.csv") -> c.getIntByName(0, "age", 0) / c.save()。

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `string _path = ""` | 当前关联的文件路径（load/readFrom/saveAs 成功时记录，save()/reload() 依据它读写） |
| 方法 | `Csv load(string path)` | ---- 静态工厂（从文件加载）---- 读取文件并解析（首行为表头，逗号分隔）；文件不可读返回空表实例 |
| 方法 | `Csv loadNoHeader(string path)` | 读取无表头文件（列名自动补 col{n}） |
| 方法 | `Csv loadDelimited(string path, bool hasHeader, string delimiter)` | 读取文件（自定义表头开关与分隔符） |
| 方法 | `bool readFrom(string path)` | ---- 实例文件操作 ---- 从文件读取并整体替换当前表（首行为表头，逗号分隔） |
| 方法 | `bool readFrom(string path, bool hasHeader, string delimiter)` | 从文件读取并整体替换当前表（自定义表头开关与分隔符） |
| 方法 | `bool reload()` | 按关联路径重新加载（沿用当前表头开关与分隔符） |
| 方法 | `bool save()` | 写回关联路径（使用构造时指定的分隔符）；未关联路径返回 false |
| 方法 | `bool saveAs(string path)` | 写入指定路径并把它记录为关联路径 |
| 方法 | `bool appendTo(string path)` | 追加数据行到指定文件（不含表头，避免重复表头；文件不存在时改为整表写入含表头） |
| 属性 | `get string path()` | ---- 关联文件信息 ---- 当前关联的文件路径（未关联为空串） |
| 属性 | `get bool fileExists()` | 关联文件是否存在 |
| 方法 | `Int64 fileSize()` | 关联文件大小（字节；未关联或不存在为 0） |
