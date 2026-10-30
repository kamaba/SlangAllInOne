# OS/Process.sl

> 源文件：`OS/Process.sl`

## class `ProcessStartInfo`

- **说明**：进程启动配置（builder 对象，字段与 C# ProcessStartInfo 对应）

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `public string program = ""` | 可执行文件路径或命令名（走 PATH 解析） |
| 字段 | `public Array&lt;string&gt; arguments = null` | argv 列表（不含 program 自身）；null 视为无参数 |
| 字段 | `public string workingDirectory = ""` | 工作目录；空串 = 继承 VM 进程当前目录 |
| 字段 | `public Map&lt;string,string&gt; environment = null` | 追加/覆盖的环境变量（key=value）；null 视为不修改 |
| 字段 | `public bool inheritEnvironment = true` | true: 在父进程环境上追加 environment；false: 仅用 environment |
| 字段 | `public ProcessStdio stdin = ProcessStdio.Inherit` | 三个标准流各自的重定向策略（一期 stdin 仅支持 Inherit/Null） |
| 字段 | `public ProcessStdio stdout = ProcessStdio.Inherit` | 字段 ProcessStdio（类型见签名）。 |
| 字段 | `public ProcessStdio stderr = ProcessStdio.Inherit` | 字段 ProcessStdio（类型见签名）。 |
| 方法 | `ProcessStartInfo create(string program, params string[] args)` | 便捷工厂：program + 变长 argv（第二个参数起即 argv，勿再写 info.arguments.add） |
| 方法 | `ProcessStartInfo arg(string value)` | 追加单个 argv 参数（链式便利方法） |
| 方法 | `ProcessStartInfo env(string key, string value)` | 设置/覆盖单个环境变量（链式便利方法） |

## class `ProcessResult`

- **说明**：run() 的聚合结果（exitCode + 捕获的输出）

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `public int exitCode = 0` | 进程退出码（非零不视为失败，由调用方判断 ok） |
| 字段 | `public string stdOut = ""` | Pipe 模式下捕获的标准输出；未捕获为空串 |
| 字段 | `public string stdErr = ""` | Pipe 模式下捕获的标准错误；未捕获为空串 |
| 属性 | `get bool ok()` | 是否成功退出（exitCode == 0） |
| 方法 | `string toString()` | 转换为 Stringundefined 类型（toString）。 |

## class `Process`

- **说明**：进程句柄对象（SL 侧不持有任何平台结构，只存 _handle；行为经系统方法下探）

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `Int64 _handle = 0` | VM 内部进程句柄（注册表 id，由 C VM 单调递增分配并直接写入；同 Core.Task 模式） |
| 方法 | `ProcessResult run(string program, params string[] args)` | 便捷路径：启动并阻塞直到结束，返回聚合结果 （stdout/stderr 为 Inherit 时自动升级为 Pipe 以便捕获） 变长 argv 便捷入口 |
| 方法 | `ProcessResult run(ProcessStartInfo info)` | 完整配置入口 |
| 方法 | `ProcessResult shell(string command)` | 显式 shell 路径：经 cmd /c 或 /bin/sh -c（stdout/stderr 均捕获） |
| 方法 | `Process start(ProcessStartInfo info)` | 控制路径：启动后返回句柄对象（stdio 按配置原样生效） |
| 属性 | `get Int64 id()` | 实例属性/方法 平台进程 id（Windows 为 dwProcessId） |
| 属性 | `get bool hasExited()` | 是否已退出（非阻塞查询） |
| 属性 | `get int exitCode()` | 退出码（尚未退出时 C VM 抛 ProcessError.NotExited，先用 hasExited 判断） |
| 方法 | `int wait()` | 阻塞等待直到结束，返回 exitCode |
| 方法 | `void kill()` | 强制终止（Windows TerminateProcess / Unix SIGKILL） |
| 方法 | `void terminate()` | 友好终止（Unix SIGTERM；Windows 等同 kill） |
| 方法 | `string readStdOut()` | 读取捕获的标准输出（等待结束后整体读取；非 Pipe 模式返回空串） |
| 方法 | `string readStdErr()` | 读取捕获的标准错误（同上） |
| 方法 | `string toString()` | 转换为 Stringundefined 类型（toString）。 |
