# Debug/Profiling.sl

> 源文件：`Debug/Profiling.sl`

## class `Profiling`

- **说明**：SLang 标准库类型 Profiling（详见源文件）。

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `static bool enabled = true` | 性能分析总开关：false 时计时静默 |
| 字段 | `static bool         _inited    = false` | ---- 计时器（key 列表 + 起始毫秒列表，并行存储）---- |
| 字段 | `static List&lt;string&gt; _timerKeys = null` | 字段 List（类型见签名）。 |
| 字段 | `static List&lt;Int64&gt;  _timerVals = null` | 字段 List（类型见签名）。 |
| 方法 | `void _ensure()` | 执行 _ensure()。 |
| 方法 | `void setEnabled(bool v)` | 总开关 |
| 方法 | `bool isEnabled()` | 判断状态是否（isEnabled）。 |
| 方法 | `void time(string key)` | ---- 计时（性能分析）---- |
| 方法 | `void timeEnd(string key)` | 执行 timeEnd(key)，行为详见源实现。 |
| 方法 | `int _findTimer(string key)` | ---- 内部 ---- |
