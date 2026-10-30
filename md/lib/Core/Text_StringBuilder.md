# Text/StringBuilder.sl

> 源文件：`Text/StringBuilder.sl`

## class `StringBuilder`

- **说明**：Core/Container/StringBuilder.sl — 可变字符串构建器（快速变体） 存储后端复用 IO/ByteBuffer（本体在 C VM 端注册表，SL 侧仅持句柄）， 追加按 UTF-8 编码写入，均摊扩容，避免 string + string 的 O(n^2) 拷贝。 数值/对象经 SystemConvertString 转换，格式化复用 SystemStringFormat （占位符 {0}/{1} 索引式或 {} 自增式，与 String.format 同一语义）。 生命周期：ByteBuffer 注册表无 GC 自动回收（csimple_lang/src/base/vm_byte_buffer.c 手动 destroy 模式），长生命周期程序建议用毕显式 release()； 释放后再追加仅触发 C 层告警不抛异常，建议弃用实例。 已知偏差（Java StringBuilder 对照）： - 仅支持尾部追加：insert/replace/delete/reverse 未实现 （ByteBuffer 后端无对应系统调用，待后续版本） - length 为 UTF-8 字节数而非字符数（与 SL String.length 语义一致； 多字节字符计数请转出后自行处理） - 内嵌 NUL 的字节序列会破坏 SL 字符串 C 风格 \0 语义， 二进制安全场景请用 toUInt8Array()

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `ByteBuffer _buf = null` | 存储后端：C VM 端 ByteBuffer 注册表对象（句柄 0 = 未持有/已释放） |
| 方法 | `override _init_()` | ── 构造 ── 空构建器（容量由 ByteBuffer 按需扩容） |
| 构造 | `_init_(string text)` | 以 text 起始内容构建（null 视为空串，C 层已兜底） |
| 构造 | `_init_(Int32 initialCapacity)` | 预留 initialCapacity 字节（提示性参数，超出仍自动扩容） |
| 方法 | `StringBuilder fromString(string text)` | ── 静态工厂 ── |
| 方法 | `StringBuilder append(string text)` | ── 追加（链式：ret this） ── |
| 方法 | `StringBuilder append(bool value)` | 添加 / 插入元素（append）。 |
| 方法 | `StringBuilder append(Int32 value)` | 添加 / 插入元素（append）。 |
| 方法 | `StringBuilder append(Int64 value)` | 添加 / 插入元素（append）。 |
| 方法 | `StringBuilder append(Float64 value)` | 添加 / 插入元素（append）。 |
| 方法 | `StringBuilder append(object value)` | 兜底重载：其余数值类型（Int8/UInt*/Float32/Float16/Float8 等） 经 SystemConvertString 转换；类实例不会自动分派 toString （C 层 SystemConvertString 无对象文本化协议），追加自定义 对象请先显式 .toString() |
| 方法 | `StringBuilder appendLine()` | 追加换行 |
| 方法 | `StringBuilder appendLine(string text)` | 追加文本并换行 |
| 方法 | `StringBuilder appendFormat(string format, params object[] args)` | 格式化追加（占位符语义同 String.format / String.toFormat） |
| 方法 | `void write(string text)` | ByteBuffer 风格别名（void 返回）：追加文本，不参与链式 |
| 属性 | `get int length()` | ── 状态 ── 已追加内容的 UTF-8 字节数 |
| 属性 | `get bool isEmpty()` | 获取 isEmpty 的值。 |
| 属性 | `get bool isNotEmpty()` | 获取 isNotEmpty 的值。 |
| 属性 | `get int capacity()` | 底层缓冲当前容量（字节） |
| 方法 | `string toString()` | ── 转换与清理 ── 当前内容按 UTF-8 解码（不改变缓冲索引，可反复调用） |
| 方法 | `UInt8Array toUInt8Array()` | 当前内容的 UTF-8 字节序列拷贝（二进制安全） |
| 方法 | `void clear()` | 内容清空（双索引归零，底层容量保留复用） |
| 方法 | `void release()` | ── 生命周期 ── 幂等释放 C VM 端注册表条目；释放后请弃用实例 |
