# Data/FrameData.sl

> 源文件：`Data/FrameData.sl`

## class `FrameData`

- **说明**：帧数据录制与调试剖析基础设施：按调用栈记录多帧 data 快照，支持帧间 diff、变化字段对比。 配合 Monitor / Trace 用于运行时调试、回归比对与性能剖析。

| 类型 | 签名 | 说明 |
|------|------|------|
| 方法 | `DataFrame create()` | 创建一个空的帧数据容器（静态工厂）。 |
| 方法 | `int frameCount()` | 当前已记录的帧数量。 |
| 方法 | `void record(string label, data snapshot)` | 追加一帧：以已克隆的 data 快照入栈。 |
| 方法 | `void recordMany(string label, Map&lt;string,data&gt; named)` | 以命名方式批量追加一帧（key 为字段名，value 为 data）。 |
| 方法 | `data getFrame(int idx)` | 取第 idx 帧的真实 data 副本（不共享内部引用，避免误改历史帧）。 |
| 方法 | `string getLabel(int idx)` | 取第 idx 帧的标签名。 |
| 方法 | `Int64 getTimestamp(int idx)` | 取第 idx 帧的时间戳。 |
| 方法 | `int getDepth(int idx)` | 取第 idx 帧的压栈深度。 |
| 方法 | `string diff(int i, int j)` | 对比第 i/j 两帧（仅比较 data），返回字段级 diff 文本。 |
| 方法 | `string diffPrev(int i)` | 对比第 i 帧与前一帧（等价 diff(i-1, i)）。 |
| 方法 | `List&lt;string&gt; changedFields(int i, int j)` | 返回第 i/j 帧之间发生变化的字段名列表。 |
| 方法 | `bool equals(int i, int j)` | 判断第 i/j 两帧的 data 是否相等（使用 DataAllEqual）。 |
| 方法 | `void exportToFile(string path)` | 将全部帧导出到指定路径的文件。 |

## class `Monitor`

- **说明**：监视器：对一组被观测 data 自动按帧录制快照；可配置采样频率、触发条件与变化断点。

| 类型 | 签名 | 说明 |
|------|------|------|
| 方法 | `Monitor watch(data d, string name)` | 创建并返回一个绑定名称为 name 的监视器（静态工厂）。 |
| 方法 | `void watch(data d, string name)` | 为指定 data 添加监视（实例方法）。 |
| 方法 | `void setSampleEvery(int n)` | 设置采样频率：每 n 次 record 才采一次。 |
| 方法 | `void setCondition(bool cond)` | 设置采样条件：仅当 cond 为真时才采样。 |
| 方法 | `void setBreakOnChange(bool on)` | 设置变化断点：被监视值发生变化时触发 Debug.Break()。 |
| 方法 | `void record(string label)` | 对所有被监视对象：克隆后记录一帧到 DataFrame。 |
| 方法 | `DataFrame getFrameData()` | 返回累积的帧数据（DataFrame）。 |
| 方法 | `void clear()` | 清空已记录的帧。 |

## class `Trace`

- **说明**：调用栈追踪器：在记录日志的同时附带当前压栈作用域信息，可复用 Log 落盘并导出。

| 类型 | 签名 | 说明 |
|------|------|------|
| 方法 | `Trace create(string name)` | 创建并返回一个命名为 name 的追踪器（静态工厂）。 |
| 方法 | `void setFile(string path)` | 复用 Log 的落盘通道，设置输出文件。 |
| 方法 | `void log(string msg, int level)` | 记录一条带当前压栈信息的日志（level 为等级）。 |
| 方法 | `void pushScope(string scope)` | 压入 / 弹出作用域（用于构建调用栈快照）。 |
| 方法 | `Array&lt;string&gt; stackSnapshot()` | 返回当前调用栈快照（作用域名数组）。 |
| 方法 | `void export(string path)` | 将追踪结果导出到指定路径。 |
