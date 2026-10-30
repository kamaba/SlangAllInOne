# Debug/Log.sl

> 源文件：`Debug/Log.sl`

## class `Log`

- **说明**：SLang 标准库类型 Log（详见源文件）。

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `static bool _enableInfo    = true` | ---- 级别开关 ---- |
| 字段 | `static bool _enableWarning = true` | 字段 bool（类型见签名）。 |
| 字段 | `static bool _enableError   = true` | 字段 bool（类型见签名）。 |
| 字段 | `static string _logFilePath = ""` | ---- 文件输出 ---- |
| 字段 | `static bool   _writeToFile = false` | 字段 bool（类型见签名）。 |
| 字段 | `static bool _enableConsole = true` | ---- 实时控制台输出 ---- |
| 字段 | `static bool   _showTime   = true` | ---- 显示配置 ---- |
| 字段 | `static bool   _showLevel  = true` | 字段 bool（类型见签名）。 |
| 字段 | `static string _timeFormat = "yyyy:MM:dd hh:mm:ss ffff"` | 字段 string（类型见签名）。 |
| 字段 | `static int _flushIntervalSec = 0` | ---- 文件落盘同步 ---- 0 = 每条日志立即写入文件（默认）；&gt;0 = 攒缓冲，每 N 秒最多落盘一次（或缓冲满） |
| 方法 | `void setLogType(bool f, bool f2, bool f3)` | 设置各级别开关 f  : 启用 Info 级（含 Verbose / Debug） f2 : 启用 Warning 级 f3 : 启用 Error 级（含 Fatal / Exception） |
| 方法 | `void setFilePath(string path, bool start = true)` | 设置日志输出文件路径；start=true 立即启用文件输出（文件不存在则创建空文件） |
| 方法 | `void setConsoleOutput(bool enabled)` | 开关实时控制台输出（默认开启） enabled=false：关闭 SystemPrintln 实时打印，日志仅写入文件 |
| 方法 | `void setShowTime(bool show)` | ---- 显示配置 ---- 日志行是否带 [时间] 前缀块（默认 true） |
| 方法 | `void setShowLevel(bool show)` | 日志行是否带 [LEVEL] 前缀块（默认 true） |
| 方法 | `void setTimeFormat(string fmt)` | 时间串格式（默认 "yyyy:MM:dd hh:mm:ss ffff"） 占位符：yyyy 年 / MM 月 / dd 日 / hh 时 / mm 分 / ss 秒 / ffff 毫秒；其余字符原样 |
| 方法 | `void setFlushInterval(int seconds)` | ---- 文件落盘同步 ---- 同步间隔（秒）：&lt;=0 每条立即写盘（默认）；&gt;0 攒缓冲，每 N 秒最多落盘一次 |
| 方法 | `void save()` | 手动立即把文件缓冲落盘（缓冲模式下退出前建议调用，避免丢最后一批） |
| 方法 | `void save(string path)` | 立即落盘并切换输出文件：缓冲内容写入 path，后续日志继续写该文件 |
| 方法 | `void closeFile()` | 关闭文件输出（不再落盘，控制台仍照常输出） |
| 方法 | `void clearFile()` | 清空日志文件内容（仅在已设置路径时有效） |
| 方法 | `void reset()` | 恢复默认：全部级别开启、停止文件输出、恢复实时控制台输出、 恢复时间/级别显示与默认时间格式、恢复每条立即落盘 |
| 方法 | `void setMinLevel(int level)` | 按最小级别一次性开关：level &lt;= 阈值才输出 level: 0=verbose/debug, 1=info, 2=warning, 3=error, 4=fatal |
| 方法 | `bool isEnabled(int level)` | 查询某级别是否启用 level: 0=debug/verbose, 1=info, 2=warning, 3=error, 4=fatal |
| 方法 | `void print(string msg)` | ---- 输出方法 ---- 实时原始打印（不加级别前缀，受 _enableConsole 开关控制） |
| 方法 | `void verbose(string msg)` | 最细粒度（= debug） |
| 方法 | `void debug(string msg)` | 执行 debug(msg)，行为详见源实现。 |
| 方法 | `void info(string msg)` | 执行 info(msg)，行为详见源实现。 |
| 方法 | `void warning(string msg)` | 执行 warning(msg)，行为详见源实现。 |
| 方法 | `void logError(string msg)` | 方法名 logError：error 为 Result 语义保留名，类成员名须避让 |
| 方法 | `void fatal(string msg)` | 致命错误：始终输出（无视级别开关，但受 _enableConsole 控制） |
| 方法 | `void exception(string msg)` | 异常信息（含可选堆栈/详情） |
| 方法 | `void exception(string msg, string detail)` | 执行 exception(msg, detail)，行为详见源实现。 |
| 方法 | `void log(int level, string msg)` | 通用：按级别输出（level 映射见 isEnabled） level: 0=debug/verbose, 1=info, 2=warning, 3=error, 4=fatal |
| 方法 | `void assert(bool flag, string msg)` | 断言：flag 为 false 时输出断言失败（始终输出，无视级别开关） 整链下沉 C 原生 SystemLogAssert：通过时热路径零字符串分配 |
| 方法 | `void _emit(string level, string msg, bool enabled)` | ---- 内部 ---- 输出一条 [时间][LEVEL] msg 日志；enabled=false 时静默 实时控制台输出受 _enableConsole 控制；文件输出受 _writeToFile 控制 整链下沉 C 原生 SystemLogEmit：时间格式化 + 拼接 + 双路输出一次完成， 消除 SL 层多次字符串堆分配 |

## class `Logger`

- **说明**：非静态日志器：每个实例独立配置，可在 isolate / 协程中分别持有， 互不干扰（与全局静态 Log 正好相反）。 用法： Logger lg = new Logger() lg._init_(true)                  # true = 开启实时控制台输出（默认） lg.setFilePath("iso1.log") lg.info("from isolate #1")

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `private bool _enableInfo    = true` | ---- 级别开关 ---- |
| 字段 | `private bool _enableWarning = true` | 字段 bool（类型见签名）。 |
| 字段 | `private bool _enableError   = true` | 字段 bool（类型见签名）。 |
| 字段 | `private string _logFilePath = ""` | ---- 文件输出 ---- |
| 字段 | `private bool   _writeToFile = false` | 字段 bool（类型见签名）。 |
| 字段 | `private bool _enableConsole = true` | ---- 实时控制台输出 ---- |
| 字段 | `private bool   _showTime   = true` | ---- 显示配置 ---- |
| 字段 | `private bool   _showLevel  = true` | 字段 bool（类型见签名）。 |
| 字段 | `private string _timeFormat = "yyyy:MM:dd hh:mm:ss ffff"` | 字段 string（类型见签名）。 |
| 字段 | `private int _flushIntervalSec = 0` | ---- 文件落盘同步 ---- 0 = 每条日志立即写入文件（默认）；&gt;0 = 攒缓冲，每 N 秒最多落盘一次（或缓冲满） |
| 方法 | `void _init_(bool consoleOutput = true)` | 显式初始化（new 之后调用，确保状态干净）；consoleOutput 控制实时控制台输出 |
| 方法 | `void setLogType(bool f, bool f2, bool f3)` | 执行 setLogType(f, f2, f3)，行为详见源实现。 |
| 方法 | `void setFilePath(string path, bool start = true)` | 执行 setFilePath(path, true)，行为详见源实现。 |
| 方法 | `void setConsoleOutput(bool enabled)` | 执行 setConsoleOutput(enabled)，行为详见源实现。 |
| 方法 | `void setShowTime(bool show)` | ---- 显示配置 ---- 日志行是否带 [时间] 前缀块（默认 true） |
| 方法 | `void setShowLevel(bool show)` | 日志行是否带 [LEVEL] 前缀块（默认 true） |
| 方法 | `void setTimeFormat(string fmt)` | 时间串格式（默认 "yyyy:MM:dd hh:mm:ss ffff"） 占位符：yyyy 年 / MM 月 / dd 日 / hh 时 / mm 分 / ss 秒 / ffff 毫秒；其余字符原样 |
| 方法 | `void setFlushInterval(int seconds)` | ---- 文件落盘同步 ---- 同步间隔（秒）：&lt;=0 每条立即写盘（默认）；&gt;0 攒缓冲，每 N 秒最多落盘一次 |
| 方法 | `void save()` | 手动立即把文件缓冲落盘（缓冲模式下退出前建议调用，避免丢最后一批） |
| 方法 | `void save(string path)` | 立即落盘并切换输出文件：缓冲内容写入 path，后续日志继续写该文件 |
| 方法 | `void closeFile()` | IO 读写 / 流控制（closeFile）。 |
| 方法 | `void clearFile()` | 执行 clearFile()。 |
| 方法 | `void reset()` | 迭代器 / 订阅控制（reset）。 |
| 方法 | `void setMinLevel(int level)` | 执行 setMinLevel(level)，行为详见源实现。 |
| 方法 | `bool isEnabled(int level)` | 判断状态是否（isEnabled）。 |
| 方法 | `void print(string msg)` | ---- 输出方法 ---- |
| 方法 | `void verbose(string msg)` | 执行 verbose(msg)，行为详见源实现。 |
| 方法 | `void debug(string msg)` | 执行 debug(msg)，行为详见源实现。 |
| 方法 | `void info(string msg)` | 执行 info(msg)，行为详见源实现。 |
| 方法 | `void warning(string msg)` | 执行 warning(msg)，行为详见源实现。 |
| 方法 | `void logError(string msg)` | 执行 logError(msg)，行为详见源实现。 |
| 方法 | `void fatal(string msg)` | 执行 fatal(msg)，行为详见源实现。 |
| 方法 | `void exception(string msg)` | 执行 exception(msg)，行为详见源实现。 |
| 方法 | `void exception(string msg, string detail)` | 执行 exception(msg, detail)，行为详见源实现。 |
| 方法 | `void log(int level, string msg)` | 数学函数（log）。 |
