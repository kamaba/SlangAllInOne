# Request.sl

> 源文件：`Request.sl`

## class `Request`

- **说明**：SLang/Server/Request.sl — 请求上下文（读侧 API，P1 全表 → P1.5 增补） 设计契约：SERVER_DESIGN.md §6.3 / §4.4 P1 全表：方法/路径/原始查询/请求头/body 三视图（text/json/bytes/<T>）/ bodyFormat 分流/form 族（urlencoded）/路径参数族（路由 {param} 提取）/ 查询参数族（percent + '+'→空格解码）/对端地址/传值槽（userData）/ 身份槽（auth，P3 auth 插件写入）。 实例由引擎构造（构造入参即全部字段，无公开无参构造语义）； bodyBytes() 返回 slice 视图（不推进源索引），勿跨请求持有。 P1.5 增补：文件族（file/files/fileCount）+ multipart 普通字段并入 form 族（引擎构造期经 _ensureMultipart 即时解析，§6.5；单文件超限 → 413、boundary 缺失 → 400 由引擎协议层应答）。

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `string _method = ""` | 字段 _method（类型见签名）。 |
| 字段 | `string _path = ""` | 字段 _path（类型见签名）。 |
| 字段 | `string _rawQuery = ""` | 字段 _rawQuery（类型见签名）。 |
| 字段 | `ByteBuffer _body = null` | body 缓冲（无 body 为 null；归属本请求，响应写出后引擎统一回收） |
| 字段 | `string _ip = ""` | 字段 _ip（类型见签名）。 |
| 字段 | `Int32 _port = 0` | 字段 _port（类型见签名）。 |
| 字段 | `Int32 _localPort = 0` | 本请求进入的监听端口（多监听器 v1.1：引擎构造后赋值；构造签名 不动——0 = 未赋值兜底） |
| 字段 | `Map&lt;string,string&gt; _pathParams = null` | 路由 {param} 提取结果（无参数路由为空 Map） |
| 字段 | `Map&lt;string,string&gt; _queryParsed = null` | 查询参数惰性解析缓存 |
| 字段 | `Map&lt;string,string&gt; _formParsed = null` | form 字段惰性解析缓存（urlencoded；multipart 经 _mpFields 并入） |
| 字段 | `bool _formDone = false` | 字段 _formDone（类型见签名）。 |
| 字段 | `Map&lt;string,string&gt; _cookieParsed = null` | ── cookie 惰性解析缓存（P10，读侧；§4.3）── Cookie 头（可多条；逐条按 '; ' 拆对、首个 '=' 切键值；值不解码） |
| 字段 | `Map&lt;string,string&gt; _mpFields = null` | multipart 解析结果（惰性一次；引擎派发前即时触发，§6.5） |
| 字段 | `List&lt;UploadedFile&gt; _mpFiles = null` | 字段 _mpFiles（类型见签名）。 |
| 字段 | `bool _mpDone = false` | 字段 _mpDone（类型见签名）。 |
| 字段 | `Int32 _mpCode = 0` | 0 = OK / 400 = boundary 缺失或格式坏 / 413 = 单文件超限 |
| 字段 | `ByteBuffer _streamBuf = null` | 字段 _streamBuf（类型见签名）。 |
| 字段 | `Int64 _streamCl = 0` | 字段 _streamCl（类型见签名）。 |
| 字段 | `bool _streamChunked = false` | 字段 _streamChunked（类型见签名）。 |
| 字段 | `HttpBodyReader _streamReader = null` | ── 流式读取器缓存（P7，§6.6）── bodyStream() 首取定形缓存单实例：后续调用（含引擎 keep-alive 收尾 drainer）返回同一实例，_remain 与 handler 消费进度接力 （修复 P5 期每次新造实例按完整 CL 起算的多吃错位）；multipart 解析器（multipartStream）同样缓存，引擎收尾据此以 multipart 语义排干剩余结构（_win 预读窗口残留由此闭环） |
| 字段 | `MultipartReader _mpReader = null` | 字段 _mpReader（类型见签名）。 |
| 字段 | `public object userData = null` | ── 传值槽（中间件 → 处理器；引擎不触碰）── 自由传值槽（任意语义） |
| 字段 | `public object auth = null` | 约定身份槽（auth 插件校验通过后写入身份、handler 只读使用； 多为 SLang.JwtClaims；与 userData 分工见 §4.11，P3 auth 落地） |
| 构造 | `_init_(string method, string path, string rawQuery, Net.HttpHeaders headers, ByteBuffer body, string ip, Int32 port, Map&lt;string,string&gt; pathParams)` | 引擎内部构造（用户勿直接 new） |
| 方法 | `void _bindStream(Net.NetStream conn, ByteBuffer buf, Int64 contentLength, bool chunked)` | 引擎绑定（streamBody 路由派发前；用户勿调）——连接 + 预读 缓冲 + body 元信息移交（§6.6） |
| 属性 | `get bool isStreamBody()` | 是否流式 body 路由（引擎收尾判定 + handler 侧能力探测） |
| 方法 | `HttpBodyReader bodyStream()` | 流式 body 读取器（streamBody 路由专用；非流式路由返回 null）。 P7：首取定形缓存单实例——同请求多次调用/引擎收尾复用同一实例 （消费进度接力；maxBytes 形态在实例已存在时忽略其上限）。 上限 = cfg.maxBodyBytes（multipart 场景放宽为 maxUploadBytes） |
| 方法 | `HttpBodyReader bodyStream(Int64 maxBytes)` | 流式 body 读取器（显式上限形态；调用方自管限额场景）。 首取定形：实例已存在（含无参形态先取）则忽略本次上限 |
| 方法 | `MultipartReader multipartStream()` | multipart 流式解析器（P7，§6.6；streamBody 路由专用）。 Content-Type 非 multipart / boundary 缺失 → 返回 null（调用方 可回退 bodyStream 裸读）。底层经 bodyStream() 缓存实例（multipart 场景上限已放宽为 maxUploadBytes）；两种消费路径互斥——同一请求 勿混用 multipartStream 与 bodyStream 裸读（字节归属交错）。 解析器一次构造缓存（构造失败不缓存，可重试）；引擎 keep-alive 收尾复用缓存实例以 multipart 语义排干剩余结构 |
| 属性 | `get string method()` | ── 请求行 ── 请求方法（原始大写，如 "GET" / "POST"） |
| 属性 | `get string path()` | 路径（不含 query） |
| 属性 | `get string rawQuery()` | 原始 query 串（可为空串） |
| 属性 | `get string ip()` | 对端地址 / 端口 |
| 属性 | `get Int32 port()` | 获取 port 的值。 |
| 属性 | `get Int32 localPort()` | 本请求进入的监听端口（多监听器 v1.1：主监听器 = 配置端口， 扩展监听器 = listen() 端口——同一 handler 挂多端口时据此分流） |
| 属性 | `set void localPort(Int32 p)` | 引擎赋值（_handleConnection 构造后绑定；用户侧只读） |
| 方法 | `string header(string name)` | 取请求头（大小写不敏感；不存在返回 null） |
| 属性 | `get string contentType()` | 原始 Content-Type（含参数，如 boundary；无则空串） |
| 属性 | `get Int64 contentLength()` | 请求声明长度（Content-Length；无头或格式非法为 0） |
| 属性 | `get bool isUpgrade()` | Upgrade 头探测（Upgrade: websocket 升级请求为 true） |
| 方法 | `string cookie(string name)` | ── cookie（P10 读侧，§4.3；Cookie 头惰性解析）── cookie 值；不存在返回 null。同名多条（RFC 6265 罕见形态）取 最末一条（路径更具体的在后——浏览器按 Path 长度升序发送） |
| 方法 | `bool hasCookie(string name)` | 是否携带该 cookie |
| 方法 | `List&lt;string&gt; cookieKeys()` | 全部 cookie 名（无 cookie 为空表；拷贝经 _SrvUtil——formKeys 同款） |
| 方法 | `void _ensureCookie()` | cookie 惰性解析（Cookie 头可多条——HttpHeaders 表内逐条消费； 每条按 ';' 分段、段内首个 '=' 切键值、两端去空白；值不解码） |
| 方法 | `void _cookiePair(string seg, Map&lt;string,string&gt; m)` | 单个 cookie 对（"name=value"）入表；无 '=' 忽略；去键值两端空白 |
| 方法 | `string bodyText()` | ── body 三视图 ── body 文本（UTF-8；无 body 空串；可重复调用，不消耗索引） |
| 方法 | `ByteBuffer bodyBytes()` | body 二进制视图（slice 视图；无 body 返回 null） |
| 方法 | `BaseJson bodyJson()` | body 作 JSON 树解析；空 body / 解析失败返回 null |
| 属性 | `get EBodyFormat bodyFormat()` | body 格式判定（Content-Type 分流，§4.4 表） |
| 方法 | `string form(string name)` | ── form 表单（urlencoded + multipart 普通字段；§4.4）── multipart 字段值不解码（直传语义，§6.4）；格式坏/超限时 form 族 返回空（协议层已由引擎以 400/413 应答，正常流程到不了 handler）。 form 字段值（urlencoded 已解码；multipart 直传）；不存在返回 null |
| 方法 | `Int32 formInt(string name, Int32 defVal)` | form 字段 Int32 化；不存在/坏格式用 defVal |
| 方法 | `bool formBool(string name, bool defVal)` | form 字段布尔化（1/true/on 为真，其余假）；不存在用 defVal |
| 方法 | `bool hasForm(string name)` | 判断 / 校验是否（hasForm）。 |
| 方法 | `List&lt;string&gt; formKeys()` | 全部字段名（无 form 为空表）。 注意：struct 登记类的泛型返回方法体内，局部/形参 List 的 .add 链 解析失败（Front Meta 层，「节点[add] 没有在类[Core.List&lt;Core.String&gt;]」； 内部类不受影响）——拷贝循环收进内部类 _SrvUtil（queryKeys 同款） |
| 方法 | `List&lt;string&gt; formAll(string name)` | ── form 同名多值（P10 补齐 P3 裁剪项，§6.4）── 该字段的全部同名值（按出现序；urlencoded 逐段扫描 + multipart 普通字段并入平行表；不存在返回空表——调用方 length 判定）。 form(name) 与 formAll 的关系：form 走覆盖语义表——键重复时 后者覆盖前者（§6.4，末值），同名多值全序须用 formAll(name)。 |
| 方法 | `bool _ensureFormMulti()` | 惰性构建同名多值表： urlencoded → bodyText 逐段扫（不去重，formAll 全序语义）； multipart  → _ensureMultipart 后按 _mpFields（后者覆盖语义， 多值经 _MultipartBody 聚平行表——multipart 普通字段值不解码） |
| 方法 | `bool _ensureForm()` | 惰性解析 form（urlencoded 直解；multipart 普通字段并入，§4.4） |
| 方法 | `UploadedFile file(string field)` | ── 文件上传（multipart/form-data；§4.4 / §6.5）── 该字段首个文件；无返回 null |
| 方法 | `List&lt;UploadedFile&gt; files(string field)` | 该字段全部文件（多文件同字段）；无返回空表 |
| 属性 | `get Int32 fileCount()` | 本请求文件总数 |
| 方法 | `Int32 _ensureMultipart()` | multipart 惰性解析（引擎在 handler 派发前即时触发——构造期语义 §6.5；重复调用返回缓存）。返回 0 = OK / 400 = boundary 缺失或 格式坏 / 413 = 单文件超 maxFileBytes（引擎按协议层应答 + 断连） |
| 方法 | `string pathParam(string name)` | ── 路径参数（路由 {param} 提取；§4.2）── 路径段参数；不存在返回 null |
| 方法 | `Int32 pathInt(string name, Int32 defVal)` | 路径参数 Int32 化；不存在/坏格式用 defVal（单参版 defVal=0） |
| 方法 | `Int32 pathInt(string name)` | 执行 pathInt(name)，行为详见源实现。 |
| 方法 | `Int64 pathInt64(string name, Int64 defVal)` | 路径参数 Int64 化；不存在/坏格式/溢出用 defVal |
| 方法 | `Float64 pathFloat(string name, Float64 defVal)` | 路径参数 Float64 化；不存在/坏格式（非数字串）用 defVal |
| 方法 | `string query(string name)` | ── 查询参数（?a=1&b=x；percent + '+'→空格解码）── 查询参数值；不存在返回 null |
| 方法 | `Int32 queryInt(string name, Int32 defVal)` | 查询参数 Int32 化；不存在/坏格式用 defVal |
| 方法 | `bool queryBool(string name, bool defVal)` | 查询参数布尔化（1/true/on 为真）；不存在用 defVal |
| 方法 | `bool hasQuery(string name)` | 判断 / 校验是否（hasQuery）。 |
| 方法 | `List&lt;string&gt; queryKeys()` | 全部查询参数名（无查询为空表；拷贝经 _SrvUtil——见 formKeys 注记） |
| 方法 | `bool _isNumeric(string s)` | 数字串校验（可选一元 '-' + 数字 + 至多一个 '.'；空串 false） |
