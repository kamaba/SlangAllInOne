# Log 系统设计与使用说明

## 目标

Log 系统用于统一管理编译链路（`Token/Node/File/Meta/IR/Other`）中的诊断信息，支持：

- 基于 CSV 的错误码定义（唯一 `id`，对应 `LID.cs` 枚举）。
- 结构化日志级别（`Assert/Info/Warning/Error/Trace`）。
- 阻断控制：`pass` 标记跳过错误计数，阶段内错误数非零即判定该阶段失败并跳过后续阶段。
- 多线程并发写入。
- Token 上下文解析与展示（文件、行列、词素、类型）。

---

## CSV 定义规范（现行）

真源文件：`simple_language/source/Log/ErrorDefinitions.csv`（EmbeddedResource，由 `LogManager` 内嵌加载；`resources/errors.csv` 为历史旧副本，已过期不随动）。

### 表头（实际）

```csv
id,logType,enableAssert,pass,paramCount,domesticTips,zhMessage,,zhFixedTips,enMessage,enFixedTips
```

### 字段语义（对照 `LogManager.LoadFromCsvReader` 解析序）

| 列 | 字段 | 语义 |
|----|------|------|
| 0 | `id` | 错误码，全局唯一，对应 `LID.cs` 枚举值 |
| 1 | `logType` | 日志级别：`Assert/Info/Warning/Error/Trace`（大小写不敏感） |
| 2 | `enableAssert` | true 时命中该条触发 `Debug.Assert`（受 `LogManager.Options.EnableAssertFeature` 总开关控制） |
| 3 | `pass` | true 时不计入 `errorCount`，编译过程不因该条中断 |
| 4 | `paramCount` | 模板参数数量，须与调用点传入的 params 数量一致 |
| 5 | `domesticTips` | 示例/补充说明，输出为 `Demo:[...]` |
| 6 | `zhMessage` | 中文消息模板（`string.Format` 风格，`{0..n}` 对应 params） |
| 7 | （空列） | 占位列，无语义 |
| 8 | `zhFixedTips` | 中文修复建议，输出为 `Tips:[...]` |
| 9 | `enMessage` | 英文消息模板（2026-10-19 起全量填充，1471 行全覆盖；`--lang en` 时生效） |
| 10 | `enFixedTips` | 英文修复建议（同上） |

> 早期设计稿中的 `module/blockOnErrorAssert/abortCompilation/fixHint` 字段未在实际 CSV 中采用；`Log.HandleBlocking` 当前未启用（调用点注释），阻断实际由 `pass` + 阶段错误计数承担。
> 注：id 20118/20119/21465 三行的修复建议原误写入 `enMessage` 列（zhFixedTips 为空、英文模式不显示消息），2026-10-19 已归位到 zhFixedTips/enFixedTips 列并补齐 enMessage 翻译。

---

## 运行行为（现行）

1. 启动时从内嵌 CSV 加载全部定义到 `LogManager` 字典，运行期按 `LID` 取定义；未注册的 LID 静默丢弃（返回 null）。
2. 多线程：`ConcurrentQueue` 收集、文件写入加锁；Error/Assert 与 Warning 计数用 `Interlocked`。
3. 调用带 Token 重载时，`WriteCoreByToken` 把 `token.path/sourceBeginLine/sourceBeginChar/sourceEndLine/sourceEndChar` 拷入 LogData（null 安全），`ToString()` 自动输出 `File:[文件] Line:[起行] Col:[起列] - Line:[止行] Col:[止列]`（token 无结束位置时省略 `- Line:.. Col:..` 尾段；2026-10-19 前旧格式为 `Position:[文件_起行_止行]`）。
4. 阻断：`pass=true` 的定义不计入 `errorCount`；过程管理以阶段内错误数判定 `ProcessPhaseFailed`，后续阶段（IR/Export）被跳过。
5. 双写：Console + `Logs/Front.txt`（目录由 jsonc 派生的进程内状态定向，读取入口 `ProjectOutputEnvironment.GetEffectiveLogsDir()`；`SIMPLELANG_LOGS_DIR` 仅作外部只读覆盖。jsonc 未加载前兜底临时目录，见 `Log.FrontLogDefaultPath`）。
6. 语言切换（2026-10-19 起）：`LogManager.LanguageIndex` 决定取 zh（0）还是 en（1）列模板；入口有两个——CLI `--lang <zh|en>`（`CommandInputArgs` 解析、`CommandExecutor.Execute` 在 `LogManager.Initialize` 后应用，所有宿主共用）与代码直调 `LogManager.SetLanguage("en")` / `SetLanguage(1)`。非法 `--lang` 值回退 zh 并打印提示。en 模式下"传入参数与要求参数不对应!"内置提示同样切为英文（`Log.ParamCountMismatchTip`）。

---

## Token 位置信息传递约定（2026-10-12 全链路落位）

日志行携带源码位置是排障反查的第一线索。各阶段 `Log.Add*Log` 均提供带 Token 重载：token 非 null 时输出行自动多出 `File:[文件] Line:[起行] Col:[起列] - Line:[止行] Col:[止列]`；token 为 null 时安全省略，无 NRE 风险。

### 重载速查

| 阶段 | 无 Token 版 | 带 Token 版 | 消息去向 |
|------|-------------|-------------|----------|
| Project | `AddProjectLog(LID, msg, params)` | `AddProjectLog(LID, msg, token, extendMessage)` | msg 与 extendMessage 合并进 `Extend` |
| Process | `AddProcessLog(LID, msg, params)` | `AddProcessLog(LID, msg, token, extendMessage)` | 同上 |
| Token | `AddTokenLog(LID, msg)` | `AddTokenLog(LID, msg, token, extendMessage)`；无 Token 场景可用 `AddTokenByString(LID, path, sLine, sChar, eLine, eChar, msg)` 手工指定行列 | 同上 |
| Node | `AddNodeLog(LID, msg)` | `AddNodeLog(LID, token, msg, params)` | params 填模板 `Info`，msg 追加进 `Extend` |
| FileMeta | `AddFileMetaLog(LID, msg)` | `AddFileMetaLog(LID, token, msg="")`（单参槽=token）/ `AddFileMetaLog(LID, token, msg, params)` | 同 Node |
| MetaCore | `AddMetaCoreLog(LID, msg, params)` | `AddMetaCoreLog(LID, token, msg, params)`；`AddMetaCoreLog(LID, List<Token>, params)` 首 Token 定位、整表填充模板 | 同 Node |
| GenIR | `AddIRLog(LID, msg, params)` | `AddIRLog(LID, token, msg, params)` | 同 Node |

### 语义要点

1. **params 版**：`objs` 按序填充 CSV 模板（数量须等于 `paramCount`，否则日志追加参数不匹配提示——中文模式「传入参数与要求参数不对应!」/ 英文模式 "Parameter count mismatch between call site and definition!"，见 `Log.ParamCountMismatchTip`）；`msg` 作为现场补充信息进入 `Extend:[...]`。
2. **合并版**（AddTokenLog/AddProjectLog/AddProcessLog 的 Token 重载）：`msg` 与 `extendMessage` 经 `CombineExtendMessage` 合并（两者皆非空时 `msg + " " + extendMessage`）进 `Extend`，`Info` 直接取 CSV 模板——**只能配 `paramCount=0` 的 LID**。2026-10-12 前该路径 msg 会被丢弃，现已保留。
3. **新增调用点约定**：作用域内能拿到 Token（当前语法元素、最近 errorToken、成员定义 token 等）时必须优先传 Token 版；确实无 Token 才用无 Token 版。存量已补传 173 处（Parse 48 / FileMeta 35 / Core 70 / IR 20），均为纯增量插参、不改日志触发条件。
4. 位置段格式（2026-10-19 起）：`File:[路径] Line:[起行] Col:[起列] - Line:[止行] Col:[止列]`；token 无结束位置（止行止列均为 0）时省略 `- Line:.. Col:..` 尾段。旧格式 `Position:[文件_起行_止行]` 已废弃。

### 输出示例

```
[10:22:36 003] [Error] [ParseToken] [TokenLexerReturnNotSupported] File:[EnSmoke.sl] Line:[7] Col:[8] - Line:[6] Col:[13]  Info:[Error: the keyword [return] is not supported: use the ret keyword for return statements!] Extend:[identifier:[return] 返回语句请使用 ret 关键字] Tips:[Check return statements inside functions: use ret <expression> and replace return with ret.]
[10:38:54 066] [Info] [Project] [ProjectShowCompileFiles]  Info:[Number of files to compile: 1]
```

（第一条为 `--lang en` 下的错误输出；`Extend` 与部分动态信息为调用点传参文本，仍随调用点语言，不受 `--lang` 控制。）

---

## 落地建议

- 新增错误码：先在 CSV 加行、再在 `LID.cs` 加枚举，避免硬编码消息。
- `zhMessage` 模板的 `{0..n}` 数量必须与 `paramCount` 一致；调用点 params 数量不符时日志会追加参数不匹配提示。
- 🔥 2026-10-19 起 CSV 为中英双语全量（1471 行 `enMessage`/`enFixedTips` 已填满）：**新增行必须同时填写 zh 与 en 两列消息与提示**，并保持两侧占位符 `{0..n}` 数量一致（LidIndexer 追加的行缺 en 时需手工补齐）；含逗号字段用引号包裹，禁止消息内出现双引号/TAB/换行。
- 切换语言：CLI `--lang en`（或代码 `LogManager.SetLanguage("en")`），详见「运行行为」第 6 条。
- 新增日志调用点优先选用带 Token 重载（见上节约定），让排障者能从日志直达源码行。
- 调试顺序建议仍沿用项目既定链路：`IR -> Meta -> File -> Node -> Token -> Code`。
