# Monitor.sl

> 源文件：`Monitor.sl`

## class `Monitor`

- **说明**：Monitor 点监视采样门面（DEBUG_SYSTEM_DESIGN.md v4） 链路：Monitor.* → Front 特译 Debug IR（compile.debug 才生成，§7.2） → *.module.json 携带 optimizeLevel → C VM 分派 → 落帧 / 查询 采样类方法（watch*/begin/end）体为空壳：调用点全部由 Front 特译为 opcode 119/120/121（Core.jsonc 无对应系统调用注册）；compile.debug 关闭时整句消除。 查询/监听类为普通系统调用：compile.debug 关闭或 optimizeLevel>=2 时 返回空/0，不报错。 注：类名 Monitor（原 Debug，避免与 Std 的 SLang.Debug 混淆）。

| 类型 | 签名 | 说明 |
|------|------|------|
| 方法 | `void watch(object value, string tag)` | 单值 / data 整表监视（T1/T2）——特译 opcode 121 mode=0 |
| 方法 | `void watch(object target, string member, string tag)` | data/class 单成员监视（T3/T4）——特译 opcode 121 mode=1 （须声明在下方 P4 闭包重载之前：String 第 3 参精确匹配优先， 否则被 (object,string,object) 隐式转 object 抢先解析） |
| 方法 | `void watch(object value, string tag, object callback)` | 单值监视 + 绑定闭包（P4 组合糖）：注册 tag 单标签订阅并立即采样， 此后该 tag 每次落帧调用 callback()（无参，闭包语法同 listen）。 非闭包对象订阅失败静默；重复调用会重复占订阅位（表满后静默失效） 且不返回订阅号——需退订请改用 listen(tag, callback) 持订阅号。 |
| 方法 | `Int32 frameCount()` | 有效帧总数（o2 快速路径 / debug 关闭时为 0） |
| 方法 | `string getFrame(Int32 index)` | 单帧文本（越界返回空串） |
| 方法 | `string lastFrame()` | 最新帧文本（监听回调配套快取） |
| 方法 | `void setMaxTextLength(Int32 maxLength)` | 帧文本截断上限（超长标注 ...(len=N)，&lt;=0 恢复默认 256） |
| 方法 | `void begin(string tag)` | ---- P2：区间（DEBUG_SYSTEM_DESIGN §5.2）---- 区间开始（进入 scope_chain）——特译 opcode 119 |
| 方法 | `void end(string tag)` | 区间结束（计入耗时统计）——特译 opcode 120 |
| 方法 | `void mark(string tag)` | 行边界标记（frameTable 行轴，P6 启用） |
| 方法 | `void setSkip(Int32 n)` | ---- P2：采样控制（§5.3）---- 全局：前 n 次命中不采样（预热跳过） |
| 方法 | `void pause()` | 全局软暂停采样（查询类不受影响） |
| 方法 | `void resume()` | 恢复采样 |
| 方法 | `void enable(string tag)` | 单监视点启用 |
| 方法 | `void disable(string tag)` | 单监视点停用 |
| 方法 | `string diff(Int32 index)` | ---- P2：查询（§5.4）---- 第 index 帧与前帧对比（仅 data/class 目标，无前帧返回原文本） |
| 方法 | `Array&lt;Int32&gt; find(string tag, string scope = "")` | 按标签（+可选区间链前缀）找帧索引列表 |
| 方法 | `Array&lt;string&gt; series(string tag)` | 某标签的值序列（画帧表用） |
| 方法 | `string stats(string tag)` | 区间耗时统计 → JSON |
| 方法 | `string scopeChain()` | 当前区间链，如 "main &gt; loop" |
| 方法 | `void watchAssert(object value, string tag, bool cond)` | ---- P3：条件监视（§5.1）---- 断言监视：cond==false 时计入违规并落违规帧（kind=3）——特译 opcode 121 mode=2 |
| 方法 | `void watchIn(object value, string tag, string caller)` | 调用链过滤：仅在含 caller 的调用链上采样——特译 opcode 121 mode=3 |
| 方法 | `Int32 assertViolations()` | 违规累计计数（§5.4，watchAssert cond==false 次数） |
| 方法 | `Int32 listen(object callback)` | ---- P4：监听回调（§5.7/§10）---- 订阅落帧通知（全帧）：每次落帧（watch/成员 watch/违规帧/mark）后调用 callback()（无参）。返回订阅号（1 起，用于 unlisten）；表满返回 -1。 |
| 方法 | `Int32 listen(string tag, object callback)` | 订阅落帧通知（单标签）：仅 tag 匹配的帧触发。返回订阅号；表满 -1。 |
| 方法 | `bool unlisten(Int32 id)` | 退订成功 true；id 不存在 / 已退订 false（重复 unlisten 必然 false） |
| 方法 | `string stackView()` | ---- P5：栈查看（§5.6/§9.3）---- 当前操作数栈快照：每槽 {index,type,value} 的 JSON 数组；无栈 "[]" （命名 stackView：stack 为容器构造糖保留名，不可作成员名） |
| 方法 | `string frames()` | 调用帧列表 [{index,method,line}]（栈顶→栈底）；无帧 "[]" |
| 方法 | `string frameData(Int32 depth)` | 第 depth 层调用帧（0=当前执行帧）locals+args；越界 "[]" |
| 方法 | `string frameVar(Int32 depth, string name)` | 某帧上指定变量/参数值文本（先 locals 后 args）；未找到 "" |
| 方法 | `void log(string msg)` | ---- P6：Trace 与帧表（§5.4/§5.5/§13.6）---- 记一条日志：自动附用户帧 method/line 与调用链摘要（"a &gt; b &gt; c"， 最外层在前）。采样类语义：pause/skip 期间静默丢弃。 |
| 方法 | `string getTraceLog()` | 日志流文本：每条 log 一行 "#&lt;行&gt; &lt;method&gt;:&lt;line&gt; \| &lt;链&gt; \| &lt;msg&gt;"， 顺序与落点一致；无日志返回 "" |
| 方法 | `string frameTable(Array&lt;string&gt; labels)` | 帧表：行=mark 行边界（升序）、列=labels、单元格=该行处该 label 最近一帧的值文本（无匹配 "-"）。首行表头 "row \| &lt;label&gt;..."； labels 空 / 无帧返回 "" |
