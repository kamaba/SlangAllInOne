# Net/Uri.sl

> 源文件：`Net/Uri.sl`

## class `Uri`

- **说明**：SLang 标准库类型 Uri（详见源文件）。

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `string _text = ""` | 字段 _text（类型见签名）。 |
| 字段 | `string _scheme = ""` | 字段 _scheme（类型见签名）。 |
| 字段 | `string _host = ""` | 字段 _host（类型见签名）。 |
| 字段 | `Int32 _port = -1` | 字段 _port（类型见签名）。 |
| 字段 | `string _path = ""` | 字段 _path（类型见签名）。 |
| 字段 | `string _query = ""` | 字段 _query（类型见签名）。 |
| 构造 | `_init_(string text)` | 构造即解析；非法 URL 抛 HttpError.UriFormat |
| 属性 | `get string scheme()` | ── 解析结果 ── |
| 属性 | `get string host()` | 获取 host 的值。 |
| 属性 | `get Int32 port()` | 显式端口；URL 未给出为 -1 |
| 属性 | `get string path()` | 获取 path 的值。 |
| 属性 | `get string query()` | query 原样（不含 '?'） |
| 方法 | `string toString()` | 转换为 Stringundefined 类型（toString）。 |
| 属性 | `get bool isHttp()` | 获取 isHttp 的值。 |
| 属性 | `get bool isHttps()` | 获取 isHttps 的值。 |
| 属性 | `get bool isWs()` | 获取 isWs 的值。 |
| 属性 | `get bool isWss()` | 获取 isWss 的值。 |
| 属性 | `get Int32 effectivePort()` | 端口未显式给出时按 scheme 补默认（http/ws=80 / https/wss=443） |
| 属性 | `get string hostHeader()` | Host 请求头：显式非默认端口时拼 host:port |
| 属性 | `get string pathAndQuery()` | 请求行路径（path 空时为 "/"；query 非空时拼 "?query"） |
| 方法 | `bool _isAlpha(Int32 c)` | ── 字符辅助（SystemString* 直调，Path/Png 同款先例）── |
| 方法 | `bool _isSchemeByte(Int32 c)` | 执行 _isSchemeByte(c)，行为详见源实现。 |
| 方法 | `Int32 _parsePort(string text, Int32 start, Int32 end)` | [start, end) 数字端口；非数字 / 超出 1-65535 返回 -1 |
| 方法 | `bool eqFold(string a, string b)` | 忽略大小写全串比较（ASCII 折叠） 注意：跨类静态调用时实参不能用 this.字段[索引器] 复合表达式（会导致 参数收集失败、方法匹配 NotFound），调用方需先提取局部变量—— 故与 Std 惯例的 _ 前缀不同、用公开名，便于 HttpHeaders 等复用 |
| 方法 | `Int32 fold(Int32 c)` | ASCII 小写折叠（'A'-'Z' -&gt; 'a'-'z'） |
