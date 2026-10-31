# Std 库类与方法索引

> 本目录为 `SLangCore/Lib/Std` 标准库自动提取的 API 参考，点击模块名查看方法/字段明细。

| 类型 | 种类 | 模块(.sl) | 基类/接口 | 说明 |
|------|------|-----------|-----------|------|
| `Row` | class | [Cache/Redis.sl](Cache/Redis.md) |  | Row - 行数据，仿 Python sqlite3.Row |
| `Cursor` | class | [Cache/Redis.sl](Cache/Redis.md) |  | Cursor - 游标，仿 Python sqlite3.Cursor |
| `Command` | class | [Cache/Redis.sl](Cache/Redis.md) |  | Command - 命令对象（ADO.NET 风格辅助类，保留已有定义） |
| `Connection` | class | [Cache/Redis.sl](Cache/Redis.md) |  | Connection - 数据库连接，仿 Python sqlite3.Connection |
| `Sqlite3` | class | [Cache/Redis.sl](Cache/Redis.md) |  | Sqlite3 - 入口类，connect() 连接数据库（仿 Python sqlite3.connect） |
| `Component` | class | [Component.sl](Component.md) |  | 组件基类（Unity 风格，仅含共用方法） 设计取舍： - 不引用 GameObject / Transform 等「Unity 独立类」，保持 Std 模块自… |
| `Row` | class | [DB/Sqlite.sl](DB/Sqlite.md) |  | Row - 行数据，仿 Python sqlite3.Row |
| `Cursor` | class | [DB/Sqlite.sl](DB/Sqlite.md) |  | Cursor - 游标，仿 Python sqlite3.Cursor |
| `Command` | class | [DB/Sqlite.sl](DB/Sqlite.md) |  | Command - 命令对象（ADO.NET 风格辅助类，保留已有定义） |
| `Connection` | class | [DB/Sqlite.sl](DB/Sqlite.md) |  | Connection - 数据库连接，仿 Python sqlite3.Connection |
| `Sqlite3` | class | [DB/Sqlite.sl](DB/Sqlite.md) |  | Sqlite3 - 入口类，connect() 连接数据库（仿 Python sqlite3.connect） |
| `Log` | class | [Debug/Log.sl](Debug/Log.md) |  | SLang 标准库类型 Log（详见源文件）。 |
| `Logger` | class | [Debug/Log.sl](Debug/Log.md) |  | 非静态日志器：每个实例独立配置，可在 isolate / 协程中分别持有， 互不干扰（与全局静态 Log 正好相反）。 用法： Logger lg = new … |
| `Profiling` | class | [Debug/Profiling.sl](Debug/Profiling.md) |  | SLang 标准库类型 Profiling（详见源文件）。 |
| `Trace` | class | [Debug/Trace.sl](Debug/Trace.md) |  | SLang 标准库类型 Trace（详见源文件）。 |
| `Base64` | class | [Encoding/Base64.sl](Encoding/Base64.md) |  | SLang 标准库类型 Base64（详见源文件）。 |
| `Encoding` | class | [Encoding/Encoding.sl](Encoding/Encoding.md) |  | SLang 标准库类型 Encoding（详见源文件）。 |
| `Utf8` | class | [Encoding/Encoding.sl](Encoding/Encoding.md) |  | 便捷类 — 常用编码零枚举样板（本体全部转发 Encoding 中枢类） UTF-8（无 BOM；解码自动识别并剥离 BOM） |
| `Unicode` | class | [Encoding/Encoding.sl](Encoding/Encoding.md) |  | UTF-16 小端（C# Encoding.Unicode 对位；解码自动识别 BE BOM 翻转端序） |
| `BigEndianUnicode` | class | [Encoding/Encoding.sl](Encoding/Encoding.md) |  | UTF-16 大端（C# Encoding.BigEndianUnicode 对位；解码自动识别 LE BOM） |
| `Gb2312` | class | [Encoding/Encoding.sl](Encoding/Encoding.md) |  | GB2312（EUC-CN：双字节 A1A1-F7FE 查表 + ASCII 透传； 表外字符抛 EncodeFailed，未赋值位抛 DecodeFailed… |
| `Ascii` | class | [Encoding/Encoding.sl](Encoding/Encoding.md) |  | 严格 7 位 ASCII（&lt;0x80 透传；含任何高位字节的输入抛 EncodeFailed / DecodeFailed——不做 1:1 字节映射的宽松 la… |
| `Md5` | class | [Encoding/Md5.sl](Encoding/Md5.md) |  | SLang 标准库类型 Md5（详见源文件）。 |
| `Sha1` | class | [Encoding/Sha1.sl](Encoding/Sha1.md) |  | SLang 标准库类型 Sha1（详见源文件）。 |
| `Sha256` | class | [Encoding/Sha256.sl](Encoding/Sha256.md) |  | SLang 标准库类型 Sha256（详见源文件）。 |
| `FFI` | class | [FFI/Library.sl](FFI/Library.md) |  | SLang 标准库类型 FFI（详见源文件）。 |
| `FFI` | class | [FFI/Library.sl](FFI/Library.md) |  | SLang 标准库类型 FFI（详见源文件）。 |
| `FFI` | class | [FFI/Struct.sl](FFI/Struct.md) |  | SLang 标准库类型 FFI（详见源文件）。 |
| `GPU` | class | [GPU/GPU.sl](GPU/GPU.md) |  | SLang 标准库类型 GPU（详见源文件）。 |
| `Console` | class | [IO/Console.sl](IO/Console.md) |  | SLang 标准库类型 Console（详见源文件）。 |
| `IO` | class | [IO/Directory.sl](IO/Directory.md) |  | SLang 标准库类型 IO（详见源文件）。 |
| `File` | class | [IO/File.sl](IO/File.md) |  | SLang 标准库类型 File（详见源文件）。 |
| `FileStream` | class | [IO/FileStream.sl](IO/FileStream.md) |  | SLang 标准库类型 FileStream（详见源文件）。 |
| `IO` | class | [IO/Path.sl](IO/Path.md) |  | Path 路径处理工具类（纯静态） 参考 C# System.IO.Path 说明： - 底层路径运算来自 C VM 系统调用（SystemPath*，注册见 … |
| `StdInStream` | class | [IO/StdStream.sl](IO/StdStream.md) |  | Std/IO/StdStream.sl — 标准输入/输出流（STREAM_DESIGN.md §4.5） 语义要点： - 复用现有 SystemPrint /… |
| `StdOutStream` | class | [IO/StdStream.sl](IO/StdStream.md) |  | SLang 标准库类型 StdOutStream（详见源文件）。 |
| `StdErrStream` | class | [IO/StdStream.sl](IO/StdStream.md) |  | SLang 标准库类型 StdErrStream（详见源文件）。 |
| `InstanceAttr` | class | [InstanceAttr.sl](InstanceAttr.md) |  | @InstanceAttr — 类级单例实例标记（通用机制，服务器路由单例同源于此）。 机制（attribute 四形态之「形态 3 · runtime 装载」… |
| `Capability` | class | [Isolate/Capability.sl](Isolate/Capability.md) |  | SLang 标准库类型 Capability（详见源文件）。 |
| `Isolate` | class | [Isolate/Isolate.sl](Isolate/Isolate.md) |  | SLang 标准库类型 Isolate（详见源文件）。 |
| `IsolateError` | class | [Isolate/IsolateError.sl](Isolate/IsolateError.md) |  | SLang 标准库类型 IsolateError（详见源文件）。 |
| `IsolateGroup` | class | [Isolate/IsolateGroup.sl](Isolate/IsolateGroup.md) |  | SLang 标准库类型 IsolateGroup（详见源文件）。 |
| `IsolateStatus` | class | [Isolate/IsolateStatus.sl](Isolate/IsolateStatus.md) |  | SLang 标准库类型 IsolateStatus（详见源文件）。 |
| `RawReceivePort` | class | [Isolate/RawReceivePort.sl](Isolate/RawReceivePort.md) |  | SLang 标准库类型 RawReceivePort（详见源文件）。 |
| `ReceivePort` | class | [Isolate/ReceivePort.sl](Isolate/ReceivePort.md) |  | SLang 标准库类型 ReceivePort（详见源文件）。 |
| `SendPort` | class | [Isolate/SendPort.sl](Isolate/SendPort.md) |  | SLang 标准库类型 SendPort（详见源文件）。 |
| `StreamBridge` | class | [Isolate/StreamBridge.sl](Isolate/StreamBridge.md) |  | SLang 标准库类型 StreamBridge（详见源文件）。 |
| `TransferableData` | class | [Isolate/TransferableData.sl](Isolate/TransferableData.md) |  | SLang 标准库类型 TransferableData（详见源文件）。 |
| `HttpHeaders` | class | [Net/HttpClient.sl](Net/HttpClient.md) |  | Net/HttpClient.sl — HTTP/1.1 客户端（TcpStream / TlsStream 之上） 设计契约：csimple_lang/md/… |
| `HttpRequest` | class | [Net/HttpClient.sl](Net/HttpClient.md) |  | HttpRequest — 请求描述 |
| `HttpResponse` | class | [Net/HttpClient.sl](Net/HttpClient.md) |  | HttpResponse — 响应 |
| `HttpClient` | class | [Net/HttpClient.sl](Net/HttpClient.md) |  | HttpClient — 客户端（每请求一连接） |
| `MqttMessage` | class | [Net/Mqtt.sl](Net/Mqtt.md) |  | MqttMessage — 一条收到的 PUBLISH 消息 |
| `MqttConnectOptions` | class | [Net/Mqtt.sl](Net/Mqtt.md) |  | MqttConnectOptions — CONNECT 报文参数 |
| `_MqttPacket` | class | [Net/Mqtt.sl](Net/Mqtt.md) |  | _MqttPacket — 内部已解析包（固定头 + 载荷，不对外注册） |
| `MqttCodec` | class | [Net/Mqtt.sl](Net/Mqtt.md) |  | MqttCodec — 编解码（全静态） |
| `MqttClient` | class | [Net/Mqtt.sl](Net/Mqtt.md) |  | MqttClient — MQTT 3.1.1 客户端（QoS 0 / 1） |
| `TcpStream` | class | [Net/NetStream.sl](Net/NetStream.md) |  | TcpStream — TCP 双向流 |
| `UdpStream` | class | [Net/NetStream.sl](Net/NetStream.md) |  | UdpStream — UDP 报文流 |
| `TcpSocket` | class | [Net/TcpSocket.sl](Net/TcpSocket.md) |  | TcpSocket — 裸 socket 包装（一般经 Tcp / TcpServer 获取，勿直接构造） |
| `Tcp` | class | [Net/TcpSocket.sl](Net/TcpSocket.md) |  | Tcp — 外观类（SL 命名空间不能放裸函数 -&gt; 静态工厂收口） |
| `TcpServer` | class | [Net/TcpSocket.sl](Net/TcpSocket.md) |  | TcpServer — 服务端监听器 |
| `TlsOptions` | class | [Net/TlsStream.sl](Net/TlsStream.md) |  | TlsOptions — TLS 会话参数（可变配置对象，字段直接赋值） |
| `TlsStream` | class | [Net/TlsStream.sl](Net/TlsStream.md) |  | TlsStream — TLS 双向流（一般经 wrap / accept 获取，勿直接构造） |
| `UdpSocket` | class | [Net/UdpSocket.sl](Net/UdpSocket.md) |  | Net/UdpSocket.sl — UDP 套接字 设计契约：csimple_lang/md/design/NETSTREAM_DESIGN.md §6.6 … |
| `Udp` | class | [Net/UdpSocket.sl](Net/UdpSocket.md) |  | Udp — 外观类（SL 命名空间不能放裸函数 -&gt; 静态工厂收口） |
| `UdpDatagram` | class | [Net/UdpSocket.sl](Net/UdpSocket.md) |  | UdpDatagram — 数据报值对象（datagrams() 流的元素） |
| `Uri` | class | [Net/Uri.sl](Net/Uri.md) |  | SLang 标准库类型 Uri（详见源文件）。 |
| `WsMessage` | class | [Net/Websocket.sl](Net/Websocket.md) |  | WsMessage — 一条完整消息（分片已重组） |
| `WsCloseInfo` | class | [Net/Websocket.sl](Net/Websocket.md) |  | WsCloseInfo — 关闭原因（对端 Close 帧解析结果） |
| `WsOptions` | class | [Net/Websocket.sl](Net/Websocket.md) |  | WsOptions — 连接 / 接入选项 |
| `_WsFrame` | class | [Net/Websocket.sl](Net/Websocket.md) |  | _WsFrame — 内部帧结构（解析中间产物，不对外） |
| `WebSocketStream` | class | [Net/Websocket.sl](Net/Websocket.md) |  | WebSocketStream — WebSocket 连接（NetStream 消息子类） |
| `WebSocketClient` | class | [Net/Websocket.sl](Net/Websocket.md) |  | WebSocketClient — 高层回调式客户端（HttpClient 风格门面 + Python WebSocketApp 事件模型：onOpen / o… |
| `DateTime` | class | [OS/DateTime.sl](OS/DateTime.md) |  | DateTime 日期时间类型，API 参照 C# 的 System.DateTime 设计 内部表示：Unix 纪元毫秒（Int64）+ 是否按 UTC 解释… |
| `ProcessStartInfo` | class | [OS/Process.sl](OS/Process.md) |  | 进程启动配置（builder 对象，字段与 C# ProcessStartInfo 对应） |
| `ProcessResult` | class | [OS/Process.sl](OS/Process.md) |  | run() 的聚合结果（exitCode + 捕获的输出） |
| `Process` | class | [OS/Process.sl](OS/Process.md) |  | 进程句柄对象（SL 侧不持有任何平台结构，只存 _handle；行为经系统方法下探） |
| `Timer` | class | [OS/Timer.sl](OS/Timer.md) |  | Timer 提供高精度时钟和延时功能，类似 Dart 的 Stopwatch、C# 的 Stopwatch、Swift 的 DispatchSourceTime… |
| `Codecs` | class | [Text/Codecs.sl](Text/Codecs.md) |  | SLang 标准库类型 Codecs（详见源文件）。 |
| `Text` | class | [Text/Csv.sl](Text/Csv.md) |  | CSV 文件操作门面：在 BaseCsv（内存解析/序列化/表操作基础能力）之上扩展文件读写。 BaseCsv 只提供基础方法；本类补充文件进出（load/re… |
| `Text` | class | [Text/Json.sl](Text/Json.md) |  | JSON 文件操作门面：在 BaseJson（内存解析/序列化/树操作基础能力）之上扩展文件读写。 BaseJson 只处理文本；本类补充文件进出（load/r… |
| `RegExpCharSet` | class | [Text/RegExp.sl](Text/RegExp.md) |  | RegExpCharSet - 字符集合（[...] 与 \d\w\s 的公共载体） ASCII 部分（码点 0..127）用 128 槽 0/1 表；非 AS… |
| `RegExpInst` | class | [Text/RegExp.sl](Text/RegExp.md) |  | RegExpInst - 编译后的指令（字段含义随 op 变化，见 RegExp 类操作码注释） |
| `RegExpMatch` | class | [Text/RegExp.sl](Text/RegExp.md) |  | RegExpMatch - 一次成功匹配的结果 index/end 为字节位置；group(0) 为整体匹配；组未参与匹配时 group 返回空串。 |
| `RegExpState` | class | [Text/RegExp.sl](Text/RegExp.md) |  | RegExpState - 单次匹配的执行状态（每次匹配新建，天然并发安全） |
| `RegExpCompiled` | class | [Text/RegExp.sl](Text/RegExp.md) |  | RegExpCompiled - 编译产物缓存条目（P4-D 模式缓存） |
| `RegExp` | class | [Text/RegExp.sl](Text/RegExp.md) |  | RegExp - 正则表达式主类 模式编译为指令链（List&lt;RegExpInst&gt;，x/y/z/w/v 字段含义见各操作码）， 匹配时经 _run 递归回溯执… |
| `Text` | class | [Text/Toml.sl](Text/Toml.md) |  | TOML 文件操作门面：在 BaseToml（内存解析/序列化/树操作基础能力）之上扩展文件读写。 BaseToml 只处理文本；本类补充文件进出（load/r… |
| `Text` | class | [Text/Xml.sl](Text/Xml.md) |  | XML 文件操作门面：在 BaseXml（内存解析/序列化/树操作基础能力）之上扩展文件读写。 BaseXml 只处理文本；本类补充文件进出（load/read… |
| `Text` | class | [Text/Yaml.sl](Text/Yaml.md) |  | YAML 文件操作门面：在 BaseYaml（内存解析/序列化/树操作基础能力）之上扩展文件读写。 BaseYaml 只处理文本；本类补充文件进出（load/r… |
| `GZip` | class | [Zip/GZip.sl](Zip/GZip.md) |  | SLang 标准库类型 GZip（详见源文件）。 |
| `Zlib` | class | [Zip/Zip.sl](Zip/Zip.md) |  | SLang 标准库类型 Zlib（详见源文件）。 |
