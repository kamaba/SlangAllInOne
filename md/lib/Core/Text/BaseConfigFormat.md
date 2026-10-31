# Text/BaseConfigFormat.sl

> 源文件：`Text/BaseConfigFormat.sl`

## class `BaseConfigFormat`

- **说明**：配置文本门面：基于 Map<string, Map<string,string>> 实现的 INI / Linux 系统配置解析与序列化工具。 只处理文本，不做文件读写；文件相关功能见 Std/Text。 覆盖两类常见格式： Windows INI -- [节] + key = value（; 与 # 注释、引号值、CRLF 换行）； Linux conf  -- 顶层 key = value（# 注释，如 /etc 下的 sysctl.conf / os-release 风格）。 解析规则： 1) 按行扫描，行首尾空白忽略；空行与注释行（# 或 ; 开头）跳过； 2) [name] 切换当前节（同名节重复出现合并）；无 ']' 的非法节头忽略； 3) 键值分隔符先 '=' 后 ':'（兼容 key: value），均无时回退首空白 （sshd_config 风格 key value）； 4) 值被 " 或 ' 整体包裹时去引号并保留内部空白与 #/; 字符； 裸值以 " #"、" ;" 起的行内注释截断（无空格前缀的 # 不受影响，如密码）； 5) 顶层键值落入空名默认节 ""，省略节名的重载默认读写该节； 6) 重复键后者覆盖前者（put 语义）；Map 键集顺序即插入序。 序列化：默认节键值最前（无节头），其余节按插入序输出，节间空行分隔； 值含空白 / # / ; / = / : / [ 等字符时加双引号保护（往返一致）。 典型用法：BaseConfigFormat c = BaseConfigFormat("[db]\nhost = 127.0.0.1\nport = 3306") c.getStr("db", "host", "") / c.getInt("db", "port", 0) Map<string,string> db = c["db"]; db["port"] / c.toString()。

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `string _curSection = ""` | 解析过程中的当前节游标（解析结束后复位为默认节） |
| 方法 | `override _init_()` | ---- 构造 ---- |
| 方法 | `void _init_(string configText)` | 按配置文本构造（等价 parse） |
| 方法 | `BaseConfigFormat parse(string configText)` | ---- 静态工厂 ---- |
| 方法 | `bool parseText(string configText)` | ---- 解析 ---- 解析配置文本并替换当前内容；文本为 null 时返回 false 且不清空原内容。 |
| 方法 | `void _parseLine(string line)` | 单行解析：注释 / 节头 / 键值三分派（空白行静默忽略） |
| 方法 | `string _cleanValue(string raw)` | 值清洗：引号整体包裹取内部；裸值做行内注释截断 |
| 方法 | `string _trim(string text)` | 去除两端空白（空格32 / \t9 / \r13 / \n10） |
| 方法 | `int _firstWs(string text)` | 第一个空白字符（空格32 / \t9）下标，无则 -1 |
| 方法 | `int _findChar(string text, int ch)` | 查找第一个字符 ch 的下标，无则 -1（Core 无子串查找系统调用，逐字符扫描） |
| 方法 | `int _findWsPrefixed(string text, int ch)` | 查找第一个带空白前缀（空格32 / \t9）的字符 ch 下标，无则 -1 （行内注释定位用：" #" 与 " ;" 语法，防误伤无空格前缀的 # 值） |
| 方法 | `Map&lt;string,string&gt; _sectionOf(string section)` | 取节容器，不存在则新建（解析写入 / setStr 共用；null 节名归默认节） |
| 属性 | `get bool isEmpty()` | 获取 isEmpty 的值。 |
| 属性 | `get bool isNotEmpty()` | 获取 isNotEmpty 的值。 |
| 属性 | `get int sectionCount()` | 节数量（含可能无键值的空节） |
| 属性 | `get int keyCount()` | 全部键值对总数（各节求和） |
| 方法 | `List&lt;string&gt; sectionNames()` | 节名列表（插入序，空名默认节也在其中） |
| 方法 | `Map&lt;string,string&gt; getSection(string section)` | 指定节的键值表活引用，不存在返回 null |
| 方法 | `List&lt;string&gt; keys(string section)` | 指定节的键列表（插入序），节不存在返回空列表 |
| 方法 | `bool hasSection(string section)` | 判断 / 校验是否（hasSection）。 |
| 方法 | `bool hasKey(string section, string key)` | 判断 / 校验是否（hasKey）。 |
| 方法 | `bool hasKey(string key)` | 默认节是否存在指定键 |
| 方法 | `Map&lt;string,string&gt; _getItem_(string section)` | 节名索引器：cfg["db"] 取节表（不存在返回 null） 注：节表二次下标请先赋局部变量（Map&lt;string,string&gt; s = cfg["db"]; s["port"]）， 临时值链式下标 cfg["db"]["port"] 当前 VM 求值为空，不可用。 |
| 方法 | `string getStr(string section, string key, string defaultValue)` | ---- 类型化取值（未命中 / 值缺失返回默认值）---- |
| 方法 | `string getStr(string key, string defaultValue)` | 默认节（顶层键）取字符串值 |
| 方法 | `int getInt(string section, string key, int defaultValue)` | 执行 getInt(section, key, defaultValue)，行为详见源实现。 |
| 方法 | `int getInt(string key, int defaultValue)` | 执行 getInt(key, defaultValue)，行为详见源实现。 |
| 方法 | `Float64 getFloat(string section, string key, Float64 defaultValue)` | 执行 getFloat(section, key, defaultValue)，行为详见源实现。 |
| 方法 | `Float64 getFloat(string key, Float64 defaultValue)` | 执行 getFloat(key, defaultValue)，行为详见源实现。 |
| 方法 | `bool getBool(string section, string key, bool defaultValue)` | 布尔宽松匹配：true/1/yes/on 为真，false/0/no/off 为假（区分大小写），其余取默认值 |
| 方法 | `bool getBool(string key, bool defaultValue)` | 执行 getBool(key, defaultValue)，行为详见源实现。 |
| 方法 | `void setStr(string section, string key, string value)` | ---- 写入 / 删除 ---- 写入指定节键值（节不存在自动创建，put 语义） |
| 方法 | `void setStr(string key, string value)` | 写入默认节键值 |
| 方法 | `bool removeKey(string section, string key)` | 删除节内键值，返回是否存在并已删除 |
| 方法 | `bool removeKey(string key)` | 执行 removeKey(key)，行为详见源实现。 |
| 方法 | `bool removeSection(string section)` | 删除整节（含其全部键值），返回是否存在并已删除 |
| 方法 | `void clear()` | 执行 clear()。 |
| 方法 | `string toConfig()` | ---- 序列化 ---- 序列化为配置文本（默认节最前无节头，其余节按插入序，节间空行分隔） |
| 方法 | `void _writeSection(StringBuilder sb, string name)` | 写出单个节（空节跳过；默认节无节头） |
| 方法 | `bool _needsQuote(string value)` | 值是否需要引号保护（首尾空白 / 注释 / 分隔符 / 节头字符） |
| 方法 | `string _quoteValue(string value)` | 执行 _quoteValue(value)，行为详见源实现。 |
| 方法 | `string toString()` | 转换为 Stringundefined 类型（toString）。 |
