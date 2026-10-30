# Upload.sl

> 源文件：`Upload.sl`

## class `UploadedFile`

- **说明**：SLang/Server/Upload.sl — 文件上传句柄（P1.5） 设计契约：SERVER_DESIGN.md §4.4（UploadedFile 表）/ §6.5（生命周期与安全剥离） 语义： - 实例由 BodyParser 解析 multipart 产出（引擎构造期经 Request._ensureMultipart）， 用户勿直接 new； - filename 已剥离路径段（防 ../ 穿越，只留 basename）；空名生成 "upload_<序号>"； - bytes() 返回 slice 视图（不推进源索引）；内容缓冲归属本对象，请求结束由引擎 统一 _release 回收——勿跨请求持有，需要持久化就 saveAs； - saveAs / saveInto 落盘（Std.IO.File.writeAllBytes）；目录不存在返回 false （不自动建目录，显式优于隐式，§6.5）；saveInto 重名自动改名 name(1).ext； - ext() 仅供业务白名单判断，不作为 MIME 判定依据（MIME 用 part 声明的 contentType，§6.5）。

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `string _field = ""` | 表单字段名 |
| 字段 | `string _filename = ""` | 原始文件名（已剥离路径） |
| 字段 | `string _contentType = ""` | part 声明的 Content-Type |
| 字段 | `ByteBuffer _data = null` | 内容缓冲（归属本对象） |
| 构造 | `_init_(string field, string filename, string contentType, ByteBuffer content)` | 构造方法，初始化本类型实例。 |
| 属性 | `get string field()` | ── 元数据 ── |
| 属性 | `get string filename()` | 获取 filename 的值。 |
| 属性 | `get string contentType()` | 获取 contentType 的值。 |
| 属性 | `get Int64 size()` | 字节数 |
| 方法 | `string ext()` | 扩展名（小写、无点；无扩展空串；非 ASCII 字节原样保留） |
| 方法 | `ByteBuffer bytes()` | ── 内容 ── 内容视图（slice，不推进源；勿跨请求持有） |
| 方法 | `bool saveAs(string path)` | ── 落盘 ── 落盘到指定完整路径（目录须已存在；失败返回 false） |
| 方法 | `bool saveInto(string dir)` | 落盘到目录 + 原文件名（重名自动改名 name(1).ext；目录须已存在） |
| 方法 | `void _release()` | 内容缓冲回收（引擎请求收尾调用；幂等） |
