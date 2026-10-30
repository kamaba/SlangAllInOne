# IO/StdStream.sl

> 源文件：`IO/StdStream.sl`

## class `StdInStream`

- **说明**：Std/IO/StdStream.sl — 标准输入/输出流（STREAM_DESIGN.md §4.5） 语义要点： - 复用现有 SystemPrint / SystemReadLine syscall，统一到 ByteStream 抽象后，「Json.encode(obj, StdOutStream.shared())」这类把序列化目标 从文件泛化为任意流的写法即可成立。 - StdInStream 行缓冲：一次 read 返回一行（含行尾 '\n'）。 vm_sys_readline 在 EOF 返回空串，无法区分「空行」与「EOF」—— 已知偏差：空行会被当作 EOF（详见设计文档 §18 偏差清单）。 - StdErrStream 复用 SystemPrint 输出到 stdout：当前无 stderr syscall （已知偏差，见 §18）；接入 stderr 句柄后仅需替换 write 内一处调用。 - 三个流均 canSeek = false（基类默认），单向（另一方向抛 NotSupported）。

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `static StdInStream _instance = null` | 字段 StdInStream（类型见签名）。 |
| 方法 | `StdInStream shared()` | 进程级标准输入（单例） |
| 方法 | `override _init_()` | 执行 _init_()。 |
| 方法 | `Int32 read(ByteBuffer dst)` | 行缓冲读取：一次 read 返回一行（含 '\n'）；0 = EOF |
| 方法 | `void write(ByteBuffer src)` | IO 读写 / 流控制（write）。 |
| 方法 | `void flush()` | IO 读写 / 流控制（flush）。 |

## class `StdOutStream`

- **说明**：SLang 标准库类型 StdOutStream（详见源文件）。

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `static StdOutStream _instance = null` | 字段 StdOutStream（类型见签名）。 |
| 方法 | `StdOutStream shared()` | 进程级标准输出（单例） |
| 方法 | `override _init_()` | 执行 _init_()。 |
| 方法 | `Int32 read(ByteBuffer dst)` | 获取 / 读取（read）。 |
| 方法 | `void write(ByteBuffer src)` | 整段写出：按 UTF-8 解码 src 可读区后打印（不追加换行） |
| 方法 | `void flush()` | IO 读写 / 流控制（flush）。 |

## class `StdErrStream`

- **说明**：SLang 标准库类型 StdErrStream（详见源文件）。

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `static StdErrStream _instance = null` | 字段 StdErrStream（类型见签名）。 |
| 方法 | `StdErrStream shared()` | 进程级标准错误（单例） |
| 方法 | `override _init_()` | 执行 _init_()。 |
| 方法 | `Int32 read(ByteBuffer dst)` | 获取 / 读取（read）。 |
| 方法 | `void write(ByteBuffer src)` | 偏差：当前无 stderr syscall，复用 stdout（见文件头注记） |
| 方法 | `void flush()` | IO 读写 / 流控制（flush）。 |
