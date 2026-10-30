# MultipartReader.sl

> 源文件：`MultipartReader.sl`

## class `MultipartPart`

- **说明**：SLang/Server/MultipartReader.sl — multipart 流式解析（P7，§6.6） 设计契约：SERVER_DESIGN.md §6.6（请求侧流式上传扩展）/ §6.4 （multipart 语义——与全内存版 BodyParser.parseMultipart 对齐） 生命周期：streamBody=true 路由 + multipart/form-data Content-Type 时 req.multipartStream() 构造本解析器（单请求缓存实例）。nextPart() 迭代 part（MultipartPart）：read(dst) 流式读内容 / readAll() 聚合 / saveAs(path) 边收边落盘（FileStream，目录须已存在）。 语义对齐（§6.4）：preamble 行容忍；part 头只认 Content-Disposition / Content-Type（默认 application/octet-stream），无冒号头行忽略（宽容）； 无 name 的 part 内容丢弃（宽容）；filename 经 BodyParser._safeFilename 安全化（路径剥离 + upload_<seq> 兜底）；字段值不解码（直传语义）。 内存语义：内容经 _win 工作窗口（64KB 量级）+ _pat("\r\n--B") 原生 indexOf 匹配；未命中时窗口尾悬挂保留 (patLen-1) 字节防 boundary 被 TCP 分段切断（跨块正确）；part 内容不驻留内存（saveAs 边收边写）。 收尾（P7 修正，引擎 6a 配合）：_win 预读字节已从底层 bodyStream 实例 消费——handler 返回后引擎收尾先经 _drainTail() 以 multipart 语义排干 剩余结构（防 _win 残留被底层 drainer 跳过而错吃下一请求字节），再由 缓存的 bodyStream 实例排干 CL 余量（epilogue）；失败断连止损。 错误：截断报文（boundary 未闭合 / body 尽而无完整行 / 行积压超限）抛 Net.HttpError.Protocol；底层累计超限抛 StreamBodyError.LimitExceeded （multipart 场景上限 = cfg.maxUploadBytes，见 Request.multipartStream）。 已知限制：用户 dst 可写区极小（如百字节）读大 part 时每轮全窗重扫 （O(n²) 最坏），正常 64KB 分块循环无影响；saveAs 在句柄过期后调用 写出空文件（read 恒 0）——句柄随 nextPart 推进即过期，勿跨迭代持有。 ── 单个 part 句柄（MultipartReader.nextPart 产出；用户勿直接 new）──

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `MultipartReader _owner = null` | 归属解析器（read 经它消费内容区） |
| 字段 | `string _field = ""` | 表单字段名 |
| 字段 | `string _filename = null` | 文件名（null = 普通字段；已剥离路径） |
| 字段 | `string _contentType = ""` | part 声明的 Content-Type |
| 构造 | `_init_(MultipartReader owner, string field, string filename, string contentType)` | 构造方法，初始化本类型实例。 |
| 属性 | `get string field()` | ── 元数据 ── |
| 属性 | `get string filename()` | 获取 filename 的值。 |
| 属性 | `get string contentType()` | 获取 contentType 的值。 |
| 属性 | `get bool isFile()` | 是否文件 part（有 filename 声明） |
| 方法 | `Int32 read(ByteBuffer dst)` | 读一段内容入 dst 可写区：返回本次字节数（0 = 本 part 结束）； 句柄过期（nextPart 已推进）恒 0。截断抛 Protocol；底层超限抛 StreamBodyError.LimitExceeded |
| 方法 | `ByteBuffer readAll()` | 聚合本 part 全量（小体量场景；大文件用 read 循环 / saveAs） |
| 方法 | `bool saveAs(string path)` | 边收边落盘（FileStream 流式写；目录须已存在；失败返回 false） |

## class `MultipartReader`

- **说明**：── multipart 流式解析器（req.multipartStream() 构造；用户勿直接 new）──

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `HttpBodyReader _r = null` | 底层 body 读取器（req.bodyStream() 缓存实例；CL/chunked 解码 + 限额） |
| 字段 | `ByteBuffer _pat = null` | 内容区定界模式 "\r\n--&lt;boundary&gt;"（原生 indexOf 匹配） |
| 字段 | `Int32 _patLen = 0` | 字段 _patLen（类型见签名）。 |
| 字段 | `string _dashB = ""` | 首分隔符行 "--&lt;boundary&gt;"（行模式比对） |
| 字段 | `ByteBuffer _dashClose = null` | 收尾标记 "--"（boundary 行后续判定） |
| 字段 | `ByteBuffer _win = null` | 工作窗口（预读 + 匹配；容量 68KB = 64KB 积压上限 + 4KB fill 余量） |
| 字段 | `Int32 _winMax = 65536` | 行模式积压上限（无换行积压超此值视为坏流） |
| 字段 | `Int32 _state = 0` | 状态机：0 = 首分隔符前 / 1 = part 头区 / 2 = 内容区 / 3 = boundary 已消化（待判收尾或空行）/ 4 = 结束 |
| 字段 | `MultipartPart _cur = null` | 当前 part 句柄（readAll/read 过期判定锚点） |
| 字段 | `Int32 _seq = 0` | 文件序号（安全名兜底 upload_&lt;seq&gt;） |
| 构造 | `_init_(HttpBodyReader reader, string boundary)` | 构造方法，初始化本类型实例。 |
| 方法 | `MultipartReader of(HttpBodyReader reader, string contentType)` | 工厂：从 Content-Type 提取 boundary 构造（boundary 缺失返回 null） |
| 属性 | `get bool isDone()` | multipart 结构是否已完整消费（含收尾 "--B--"） |
| 方法 | `MultipartPart nextPart()` | 迭代下一个 part：返回句柄（元数据 + read/readAll/saveAs）； null = 全部结束。自动排干未读完的当前 part；无 name 的 part 内容丢弃不产出（宽容）。截断抛 Protocol；超限抛 LimitExceeded |
| 方法 | `Int32 _readContent(ByteBuffer dst)` | 内容区读取（状态 2 专用）：批量写当前 part 内容入 dst 可写区， 返回本次字节数；0 = 本 part 结束（boundary 已消化、_state 推进 3）。 跨块悬挂保留：未命中时窗口尾留 (patLen-1) 字节下轮 fill 后重扫。 |
| 方法 | `string _ensureLine()` | 行模式取一行（剥 CRLF）：无完整行则拉取重试；积压超 _winMax 视为坏流；body 尽而无完整行视为截断 |
| 方法 | `Int32 _fill()` | 窗口拉取：底层读取器（CL/chunked 解码 + 限额）读入 _win 可写区； 已读区满则先压缩腾位（防膨胀） |
| 方法 | `void _drainContent()` | 排干当前内容区（状态 2 → 3）：nextPart 自动推进 / 无 name part 丢弃 / 引擎收尾复用 |
| 方法 | `void _drainTail()` | 收尾排干（引擎 6a）：以 multipart 语义消费完剩余结构（丢弃式）， 直至收尾分隔符或异常。_win 预读残留由此闭环，防底层 drainer 按 CL 余量排干时跳过 _win 数据错吃下一请求字节 |
