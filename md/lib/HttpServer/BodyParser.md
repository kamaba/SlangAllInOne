# BodyParser.sl

> 源文件：`BodyParser.sl`

## class `_UrlCodec`

- **说明**：_UrlCodec — 内部 URL 解码工具（percent-decode + '+'→空格；UTF-8 组装）。 Uri 无现成解码（SERVER_DESIGN.md §2.3），本类为查询参数与 form 共用解码器。 非法 %HH 序列原样保留（RFC 宽容语义）。

| 类型 | 签名 | 说明 |
|------|------|------|
| 方法 | `string decode(string s)` | 转换 / 序列化 / 格式化（decode）。 |
| 方法 | `Int32 _hexVal(Int32 c)` | 十六进制字符 → 0..15；非法返回 -1 |

## class `_MultipartBody`

- **说明**：_MultipartBody — multipart 解析结果（内部）。 errorCode：0 = OK / 400 = boundary 缺失或格式坏 / 413 = 单文件超 maxFileBytes （协议层语义由引擎按 errorCode 应答 + 优雅断连，SERVER_DESIGN.md §6.11）

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `Int32 _errorCode = 0` | 字段 _errorCode（类型见签名）。 |
| 字段 | `Map&lt;string,string&gt; _fields = null` | 字段 _fields（类型见签名）。 |
| 字段 | `List&lt;UploadedFile&gt; _files = null` | 字段 _files（类型见签名）。 |
| 方法 | `override _init_()` | 执行 _init_()。 |

## class `BodyParser`

- **说明**：BodyParser — 格式判定与 form / multipart 解码（静态工具）

| 类型 | 签名 | 说明 |
|------|------|------|
| 方法 | `EBodyFormat detect(string contentType, Int32 bodyLen)` | Content-Type → EBodyFormat（忽略大小写；参数段 ';' 后剥离后比较）。 无 body（len == 0）且无 Content-Type → None |
| 方法 | `bool isMultipart(string contentType)` | multipart/form-data 判定（引擎 body 上限选择用：multipart → maxUploadBytes，其余 maxBodyBytes，SERVER_DESIGN.md §6.4） |
| 方法 | `string _mimeOf(string contentType)` | 剥离 Content-Type 参数段（"; boundary=..."）取裸 mime |
| 方法 | `Map&lt;string,string&gt; parseForm(string text)` | urlencoded form 解码："a=1&b=hello+world&c=%E4%BD%A0" → Map； 键重复后者覆盖前者（m[k]=v put 语义，Map._getItem_ 头注记）； 无 '=' 的段跳过；值解码经 _UrlCodec（percent + '+'→空格） |
| 方法 | `void collectFormMulti(string text, Map&lt;string, List&lt;string&gt; &gt; outMulti)` | 同名多值收集（P10 formAll 底座，§6.4）："a=1&a=2&b=x" → { a: [1,2], b: [x] }（出现序保留，不去重；无 '=' 段跳过）。 与 parseForm 平行实现（后者 Map 覆盖语义无法携带多值）。 值类型 List&lt;string&gt;：跨模块点分泛型参数 Front 不受限（模块内 静态方法形参，Request._formMulti 消费端先拷局部再索引——纪律同 HttpHeaders） |
| 方法 | `bool _startsWithFold(string s, string prefix)` | ── 文本辅助（大小写折叠前缀/后缀）── |
| 方法 | `bool _endsWithFold(string s, string suffix)` | 执行 _endsWithFold(s, suffix)，行为详见源实现。 |
| 方法 | `_MultipartBody parseMultipart(string contentType, ByteBuffer body, Int32 maxFileBytes)` | multipart/form-data 解析（RFC 7578，SERVER_DESIGN.md §6.4） 报文形态： --B\r\n part 头(至空行) \r\n 内容 \r\n--B\r\n ... \r\n--B-- [epilogue] 内容区以 "\r\n--B" 定界（内容不含结尾 CRLF，boundary 不得出现在内容中）； v1 全量驻留内存（总量受引擎 maxUploadBytes 上限约束，流式为 P5）。 对 body 只经 slice 视图消费（不推进源 readerIndex，body 三视图不受影响）。 解析入口。errorCode：0 = OK / 400 = boundary 缺失或格式坏 / 413 = 单文件超 maxFileBytes（内容不驻留，直接中止） |
| 方法 | `string _extractBoundary(string contentType)` | Content-Type 参数提取 boundary（忽略大小写；值可带引号； 未找到/空值返回空串 → 调用方按 400 处理） |
| 方法 | `string _dispParam(string value, string wantKey)` | Content-Disposition 参数取值：按 ';' 分段找 key（忽略大小写）， 值去空白 + 剥引号；未找到返回 null。 形态：form-data; name="field"; filename="a.txt" |
| 方法 | `string _safeFilename(string raw, Int32 seq)` | 文件名安全化：按 '/' 与 '\\' 剥离路径段（防 ../ 穿越，只留 basename，§6.4 第 6 步）；空名生成 "upload_&lt;序号&gt;" |
| 方法 | `Int32 _findFold(string s, string sub)` | 忽略大小写查找子串（返回首匹配下标；未找到 -1；空 sub 返回 0） |
