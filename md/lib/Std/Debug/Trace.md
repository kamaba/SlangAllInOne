# Debug/Trace.sl

> 源文件：`Debug/Trace.sl`

## class `Trace`

- **说明**：SLang 标准库类型 Trace（详见源文件）。

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `static bool enabled = true` | 追踪总开关：false 时所有 Trace 输出静默 |
| 字段 | `static bool         _inited     = false` | ---- 作用域追踪（模拟调用栈）---- |
| 字段 | `static List&lt;string&gt; _scopeStack = null` | 字段 List（类型见签名）。 |
| 字段 | `static int          _depth      = 0` | 字段 int（类型见签名）。 |
| 方法 | `void _ensure()` | 执行 _ensure()。 |
| 方法 | `void setEnabled(bool v)` | 追踪总开关 |
| 方法 | `bool isEnabled()` | 判断状态是否（isEnabled）。 |
| 方法 | `void trace(string msg)` | ---- 追踪 ---- 一条追踪信息（带时间戳），标记"走到这里了" |
| 方法 | `void Enter(string scope)` | 进入一个作用域（入栈），后续追踪增加缩进 |
| 方法 | `void Exit(string scope)` | 退出一个作用域（出栈） |
| 方法 | `void Step(string msg)` | 逐步追踪（常用于循环/长流程中标记进度） |
| 方法 | `void DumpStack()` | 打印当前模拟调用栈（Enter/Exit 累积的作用域） |
| 方法 | `void Break()` | ---- 断点 ---- 注：VM 当前未暴露真实断点/异常 API，Break 仅打印断点标记与作用域栈，便于定位； 若后续 VM 提供断点 system call，可在此接管（如抛调试异常/挂起）。 |
| 方法 | `string _indent()` | ---- 内部 ---- |
