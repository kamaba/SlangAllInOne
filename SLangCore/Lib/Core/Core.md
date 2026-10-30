# Core Project Guide

- Project Entry File: `Core.sp`
- Project Config File: `Core.jsonc`

## Project Entry Conventions

### `_main_`

Primary runtime entry. Normal execution starts here.

### `_test_`

Test entry. Used when test mode is enabled.

### `_before_`

Compile pre-hook entry (Project class). Executed before compilation.

### `_after_`

Compile post-hook entry (Project class). Executed after compilation, before IR export.

## Global Integration

`global.xxx` / `global.func()` is integrated with `Project{}` semantic source.

### JSONC `data` on `Project`

Prefer a root-level `"data": { ... }` block. Legacy `"global"."data"` is still read; root keys override on name clash.

- Primitive values (`int32`/`string`/`float`/`bool`/`null`) are injected as **static members on `Project`** (not on the compiler `global` MetaData shell). Access via `global.<name>`. 
- Array values are supported (primitive and nested arrays), e.g. `global.arr[0]`, `global.arr2[1][0]`. 
- Object values become `MetaData` shape types, still as **fields on `Project`**, e.g. `global.vardata2.a`. 

## Example

```jsonc
"data": {
  "var1": 12,
  "arr": [1,2,3],
  "arr2": [[1,2],[3,4]],
  "vardata2": { "a": 10, "b": 20, "flags": [true,false] }
},
"global": {
  "imports": ["Some.Module"]
}
```

Access:

- `global.var1`
- `global.arr[0]`
- `global.arr2[1][0]`
- `global.vardata2.a`
- `global.vardata2.b`


<!-- CORE-API-START -->
## 类与方法参考（自动提取）

详见 [`doc/README.md`](doc/README.md)（按模块拆分，可逐类查询）。

| 类型 | 种类 | 模块(.sl) | 基类/接口 | 说明 |
|------|------|-----------|-----------|------|
| `AOT` | class | AOT.sl |  | SLang 标准库类型 AOT（详见源文件）。 |
| `Array&lt;T&gt;` | class | Array.sl | implements IIterable&lt;T&gt;, IIterator&lt;T&gt; | SLang 标准库类型 Array&lt;T&gt;（详见源文件）。 |
| `Attribute` | class | Attribute.sl |  | SLang 标准库类型 Attribute（详见源文件）。 |
| `Serializable` | class | Attribute.sl |  | 序列化标签: 标注在 class/data 上, 声明该类型支持通用序列化 成员序列化规则: public 成员默认参与序列化 protected/privat… |
| `SerializeField` | class | Attribute.sl |  | 序列化标签: 强制 protected/private 成员参与序列化 |
| `NonSerialized` | class | Attribute.sl |  | 序列化标签: 排除该 public 成员不参与序列化 |
| `Boolean` | class | Boolean.sl |  | 布尔包装类型：将原始 bool 封装为对象，便于在需要 Object 的场合（集合、反射等）传递布尔值。 |
| `IClone` | interface | CloneIterface.sl | implements IClone | 克隆契约：实现该接口的类型可通过 clone() 返回自身的一个独立副本（深/浅拷贝语义由实现决定）。 |
| `IClone&lt;T&gt;` | interface | CloneIterface.sl | implements IClone&lt;T&gt; | 泛型克隆契约：强类型 clone()，返回 T 的副本。 |
| `Channel&lt;T&gt;` | class | Container/Channel.sl |  | SLang 标准库类型 Channel&lt;T&gt;（详见源文件）。 |
| `SetEntity&lt;T&gt;` | class | Container/HashSet.sl |  | 集合元素实体：hashId 缓存 value.hashCode（桶链快速过滤用），value 公开可读写。 link 字段用于哈希桶冲突链（同 bucket 的… |
| `HashSet&lt;T&gt;` | class | Container/HashSet.sl | extends Object  | 无序不重复集合：仿 C# HashSet&lt;T&gt;（即只存 key 的 Dictionary），API 参考 Python set / Dart Set。 类名使用… |
| `IList&lt;T&gt;` | interface | Container/IList.sl | implements IList&lt;T&gt; | 列表（有序集合）契约：支持按索引增删、容量管理与转数组。 标准库 List&lt;T&gt; 等顺序容器均实现此接口，供泛型算法与遍历统一处理。 |
| `IMap&lt;T1, T2&gt;` | interface | Container/IMap.sl | implements IMap&lt;T1, T2&gt; | 映射（键值对集合）契约：支持容量管理、增删与下标访问。 标准库 Map&lt;TKey,TValue&gt; 等字典容器实现此接口，m[key] 读写通过 _getItem… |
| `LinkedList&lt;T&gt;` | class | Container/LinkedList.sl |  | SLang 标准库类型 LinkedList&lt;T&gt;（详见源文件）。 |
| `List&lt;T&gt;` | class | Container/List.sl |  | SLang 标准库类型 List&lt;T&gt;（详见源文件）。 |
| `MapEntity&lt;TKey,TValue&gt;` | class | Container/Map.sl |  | 键值对实体：hashId 缓存 key.hashCode（供哈希类容器扩展使用），key/value 公开可读写。 link 字段用于哈希桶链表（同 bucke… |
| `Map&lt;TKey,TValue&gt;` | class | Container/Map.sl | extends Object  | 字典容器：仿 C# Dictionary&lt;TKey,TValue&gt; 的哈希表实现。 核心数据结构： _buckets  -- 桶数组，存储 entries 中的… |
| `Queue&lt;T&gt;` | class | Container/Queue.sl | extends Object  | 先进先出（FIFO）队列：仿 C# Queue&lt;T&gt;，API 参考 Python collections.deque / Dart Queue。 核心数据结构（… |
| `Stack&lt;T&gt;` | class | Container/Stack.sl | extends Object  | 后进先出（LIFO）栈：仿 C# Stack&lt;T&gt;，API 参考 Python list.append/pop / Dart List。 核心数据结构： _it… |
| `Tuple&lt;T1&gt;` | class | Container/Tuple.sl |  | 模板形式：Tuple&lt;T1&gt;（单元素，强类型定长） |
| `Tuple&lt;T1,T2&gt;` | class | Container/Tuple.sl |  | 模板形式：Tuple&lt;T1,T2&gt; |
| `Tuple&lt;T1,T2,T3&gt;` | class | Container/Tuple.sl |  | 模板形式：Tuple&lt;T1,T2,T3&gt; |
| `Tuple&lt;T1,T2,T3,T4&gt;` | class | Container/Tuple.sl |  | 模板形式：Tuple&lt;T1,T2,T3,T4&gt; |
| `Tuple&lt;T1,T2,T3,T4,T5&gt;` | class | Container/Tuple.sl |  | 模板形式：Tuple&lt;T1,T2,T3,T4,T5&gt; |
| `Tuple&lt;T1,T2,T3,T4,T5,T6&gt;` | class | Container/Tuple.sl |  | 模板形式：Tuple&lt;T1,T2,T3,T4,T5,T6&gt; |
| `Tuple&lt;T1,T2,T3,T4,T5,T6,T7&gt;` | class | Container/Tuple.sl |  | 模板形式：Tuple&lt;T1,T2,T3,T4,T5,T6,T7&gt; |
| `Tuple&lt;T1,T2,T3,T4,T5,T6,T7,T8&gt;` | class | Container/Tuple.sl |  | 模板形式：Tuple&lt;T1,T2,T3,T4,T5,T6,T7,T8&gt; |
| `Tuple` | class | Container/Tuple.sl |  | 无模板形式：Tuple（Python 风格，动态类型，基于数组可无限扩展） |
| `CoroutineStatus` | class | Coroutine.sl |  | SLang 标准库类型 CoroutineStatus（详见源文件）。 |
| `CoroutineBlockReason` | class | Coroutine.sl |  | SLang 标准库类型 CoroutineBlockReason（详见源文件）。 |
| `Task` | class | Coroutine.sl |  | SLang 标准库类型 Task（详见源文件）。 |
| `Coroutine` | class | Coroutine.sl |  | SLang 标准库类型 Coroutine（详见源文件）。 |
| `BaseCsv` | class | DataStruct/BaseCsv.sl |  | CSV 文件门面：基于 Table 二维表容器实现的 CSV 读写工具。 Table 承载列名表头、定宽数据行、类型化取值与查询统计能力（解析/序列化在 VM … |
| `Table` | class | DataStruct/Table.sl | extends Object  | 二维表容器：CSV / Excel / 数据库结果集的中间数据层（仿 DataTable / pandas DataFrame 的精简版）。 核心数据结构： _… |
| `TreeNode&lt;T&gt;` | class | DataStruct/Tree.sl |  | 树结构库：N 叉树（左孩子右兄弟）+ 二叉树 + 二叉搜索树，最通用树算法的统一实现。 本文件五个类同时被 Xml/Yaml/Json/Toml/Config(… |
| `Tree&lt;T&gt;` | class | DataStruct/Tree.sl | extends Object  | N 叉树（持有根节点，foreach 按先序迭代 _value） |
| `BinaryNode&lt;T&gt;` | class | DataStruct/Tree.sl |  | 二叉树节点（三叉链：_left/_right/_parent） |
| `BinaryTree&lt;T&gt;` | class | DataStruct/Tree.sl | extends Object  | 二叉树（持有根节点，foreach 按中序迭代 _value） |
| `BinarySearchTree&lt;T&gt;` | class | DataStruct/Tree.sl |  | 二叉搜索树（继承 BinaryTree，插入/查找/删除全部在 VM 层完成） 值须可有序比较（数值按大小、字符串按字典序）；重复值插入返回已存在节点。 |
| `FrameData` | class | Data/FrameData.sl |  | 帧数据录制与调试剖析基础设施：按调用栈记录多帧 data 快照，支持帧间 diff、变化字段对比。 配合 Monitor / Trace 用于运行时调试、回归比… |
| `Monitor` | class | Data/FrameData.sl |  | 监视器：对一组被观测 data 自动按帧录制快照；可配置采样频率、触发条件与变化断点。 |
| `Trace` | class | Data/FrameData.sl |  | 调用栈追踪器：在记录日志的同时附带当前压栈作用域信息，可复用 Log 落盘并导出。 |
| `DllImport` | class | DllImport.sl |  | SLang 标准库类型 DllImport（详见源文件）。 |
| `DllStaticImport` | class | DllStaticImport.sl |  | SLang 标准库类型 DllStaticImport（详见源文件）。 |
| `OSVersionNumber` | class | Environment.sl |  | OSVersionNumber - numeric OS version (§13.5: numeric layer, for &gt;=). |
| `ProbeOSVersionNumber` | class | Environment.sl |  | ProbeOSVersionNumber - numeric OS version, raw probe (§8.5.6). Mirrors OSVersion… |
| `Cpu` | class | Environment.sl |  | Cpu / Ai / Render / Network / Script / Embedded - six new category detail object… |
| `ProbeCpu` | class | Environment.sl |  | ── cpu topology (§12.12; probe channel — raw values) ── |
| `Ai` | class | Environment.sl |  | ── ai stacks (§12.13; current channel) ── |
| `ProbeAi` | class | Environment.sl |  | ── ai stacks (§12.13; probe channel — raw values) ── |
| `Render` | class | Environment.sl |  | ── render (§12.14; current channel) ── |
| `ProbeRender` | class | Environment.sl |  | ── render (§12.14; probe channel — raw values) ── |
| `Network` | class | Environment.sl |  | ── network (§12.15; current channel) ── |
| `ProbeNetwork` | class | Environment.sl |  | ── network (§12.15; probe channel — raw values) ── |
| `Script` | class | Environment.sl |  | ── script runtimes (§12.16; current channel) ── |
| `ProbeScript` | class | Environment.sl |  | ── script runtimes (§12.16; probe channel — raw values) ── |
| `Embedded` | class | Environment.sl |  | ── embedded (§12.17; current channel) ── |
| `ProbeEmbedded` | class | Environment.sl |  | ── embedded (§12.17; probe channel — raw values) ── |
| `DeviceInfo` | class | Environment.sl |  | ── device details (§12.6; P3) ── |
| `Device` | class | Environment.sl |  | ── device kinds (§12.6; current channel) ── |
| `ProbeDeviceInfo` | class | Environment.sl |  | ── device details (§12.6; probe channel — raw values) ── |
| `ProbeDevice` | class | Environment.sl |  | ── device kinds (§12.6; probe channel — raw values) ── |
| `current` | class | Environment.sl |  | Static getters forward to SystemPlatformEnv* system methods; the CVM side probes… |
| `probe` | class | Environment.sl |  | probe - raw probed values (§8.5.6: probe = raw, current = effective). Mirrors cu… |
| `Override` | class | Environment.sl |  | Override - runtime override query (§8.5.6: three read forms). Class name uses ca… |
| `env` | class | Environment.sl |  | env - process environment variables (§13.2 ③). |
| `custom` | class | Environment.sl |  | custom - custom condition values (jsonc require.custom, §13.2 ④). |
| `sys` | class | Environment.sl |  | sys - directory / newline / timing (container for the old Environment static mem… |
| `legacy` | class | Environment.sl |  | legacy - P1.6 compatibility shell (§13.13). New code should use Environment.env.… |
| `DefItem` | class | Environment/Platform_Defs.sl |  | Single definition member descriptor. |
| `defs` | class | Environment/Platform_Defs.sl |  | ★ Registry — table data provided by C side (sl_platform_def.c). |
| `Error` | class | Error.sl |  | SLang 标准库类型 Error（详见源文件）。 |
| `Exclude` | class | Exclude.sl |  | SLang 标准库类型 Exclude（详见源文件）。 |
| `Float16` | class | Float16.sl |  | 16 位半精度浮点数，对应 C# Half，用于机器学习/图形等紧凑数值表示。 |
| `Float16_Brain` | class | Float16.sl |  | SLang 标准库类型 Float16_Brain（详见源文件）。 |
| `Float32` | class | Float32.sl |  | 历史遗留的 import CSharp.System; 所指命名空间并不存在（曾静默失败），随 import 错误严格化已移除。 32 位单精度浮点数，对应 C… |
| `Float64` | class | Float64.sl |  | 历史遗留的 import CSharp.System; 所指命名空间并不存在（曾静默失败），随 import 错误严格化已移除。 64 位双精度浮点数（默认浮点… |
| `Float8` | class | Float8.sl |  | 8 位浮点数（低精度变体），用于高吞吐/低存储需求的数值批量计算。 |
| `Float8_E5M2` | class | Float8.sl |  | SLang 标准库类型 Float8_E5M2（详见源文件）。 |
| `Guid` | class | Guid.sl |  | Guid - Globally Unique Identifier. Inspired by: CLR  : System.Guid (NewGuid, ToS… |
| `BinaryCodec` | class | IO/BinaryCodec.sl |  | Core/IO/BinaryCodec.sl — 二进制编解码器（STREAM_DESIGN.md §8.6） P2 范围：闭包注入版 Codec&lt;object… |
| `ByteBuffer` | class | IO/ByteBuffer.sl |  | SLang 标准库类型 ByteBuffer（详见源文件）。 |
| `MemoryStream` | class | IO/ByteStream.sl |  | MemoryStream — 内存流（P1 唯一 L0 具体子类） 读写共用一个 ByteBuffer：readerIndex 即 position，write… |
| `_FusedConverter&lt;S,T,M&gt;` | class | IO/Codec.sl |  | _FusedConverter&lt;S,T,M&gt; — fuse 的组合实现（内部辅助类） |
| `_FusedCodec&lt;S,T,M&gt;` | class | IO/Codec.sl |  | _FusedCodec&lt;S,T,M&gt; — fuseCodec 的组合实现（内部辅助类） |
| `Utf8Codec` | class | IO/Encoding.sl |  | Core/IO/Encoding.sl — UTF-8 编解码器（STREAM_DESIGN.md §7.1） P2 范围：Utf8Codec（string ↔… |
| `JsonCodec&lt;T&gt;` | class | IO/JsonCodec.sl |  | JsonCodec&lt;T&gt; — T ↔ string（对象 ↔ JSON 文本） S = T（业务对象），T = string（文本，分块单位） |
| `LengthPrefix` | class | IO/LengthPrefix.sl |  | Core/IO/LengthPrefix.sl — 长度前缀分帧机制（STREAM_DESIGN.md §8.1） P2 范围：分帧机制本体（静态工具 + 三个… |
| `_FramedDecodeStream&lt;T&gt;` | class | IO/LengthPrefix.sl |  | _FramedDecodeStream&lt;T&gt; — 拉模式分帧解码流 生产协程循环 read → acc 累积 → drainFrames；异常（含 EOF 残留… |
| `_FrameEncodeSink&lt;T&gt;` | class | IO/LengthPrefix.sl |  | _FrameEncodeSink&lt;T&gt; — 分帧编码写入端 |
| `_FramedBindStream&lt;T&gt;` | class | IO/LengthPrefix.sl |  | _FramedBindStream&lt;T&gt; — 推模式分帧解码流（chunked decoder） 订阅上游 ByteBuffer chunk 流：onData … |
| `ProtoCodec&lt;T&gt;` | class | IO/ProtoCodec.sl |  | ProtoCodec&lt;T&gt; — T ↔ ByteBuffer（消息对象 ↔ ProtoBuf wire format） S = T（消息对象），T = Byte… |
| `_FnConverter&lt;S,T&gt;` | class | IO/ProtoCodec.sl |  | _FnConverter&lt;S,T&gt; — Function → Converter 适配器（闭包注入的落地实现） |
| `_FnChunkSink&lt;S,T&gt;` | class | IO/ProtoCodec.sl |  | _FnChunkSink&lt;S,T&gt; — 闭包逐项分块 sink（_FnConverter 的 chunked 支撑） |
| `Serialize` | class | IO/Serialize.sl |  | Core/IO/Serialize.sl — 序列化门面（STREAM_DESIGN.md §8.7） T 按 Codec 分两个方向编排： - 字节向：Cod… |
| `_StreamEvent` | class | IO/Stream.sl |  | Core/IO/Stream.sl — L1 元素层：推/拉双模事件流 设计契约：md/design/STREAM_DESIGN.md §6 / §11.1 /… |
| `_CancelFlag` | class | IO/Stream.sl |  | _CancelFlag — 取消标记（闭包内可写的布尔载体） |
| `StreamSubscription` | class | IO/Stream.sl |  | StreamSubscription — 订阅句柄（非泛型） cancel：置取消标记 + 关闭事件通道，级联终止分发协程与上游生产。 |
| `StreamIterator&lt;T&gt;` | class | IO/Stream.sl | extends Object  | StreamIterator&lt;T&gt; — 拉模式迭代器 moveNext 首调时才 listen 引流：事件写入无缓冲上限 Channel&lt;T&gt;， 之后每次 mo… |
| `_ControllerStream&lt;T&gt;` | class | IO/Stream.sl |  | _ControllerStream&lt;T&gt; — controller.stream 的实现 listen 启动分发协程：从事件通道取 _StreamEvent 逐… |
| `StreamController&lt;T&gt;` | class | IO/Stream.sl |  | StreamController&lt;T&gt; — 流的写入端 默认无缓冲上限（add 永不挂起）；_init_(capacity) 指定容量后 add 在通道满时挂起… |
| `StreamSink&lt;T&gt;` | class | IO/Stream.sl |  | StreamSink&lt;T&gt; — controller 的 sink 视图（extends Codec 的分块输出端） fromByteStream 桥接关键：d… |
| `_MapStream&lt;S,U&gt;` | class | IO/Stream.sl |  | _MapStream&lt;S,U&gt; — 惰性映射：fn(v) 结果转发给下游 onData |
| `_WhereStream&lt;T&gt;` | class | IO/Stream.sl |  | _WhereStream&lt;T&gt; — 惰性过滤：fn(v) as bool 为 true 才放行 |
| `_TakeStream&lt;T&gt;` | class | IO/Stream.sl |  | _TakeStream&lt;T&gt; — 惰性截断：取满 N 后 cancel 上游 + 触发 onDone sub 延迟绑定：闭包先声明捕获，listen 返回后再赋… |
| `_SkipStream&lt;T&gt;` | class | IO/Stream.sl |  | _SkipStream&lt;T&gt; — 惰性跳过：丢弃前 N 个后透传 |
| `_FromIterableStream&lt;T&gt;` | class | IO/Stream.sl |  | _FromIterableStream&lt;T&gt; — 数组生产流：生产协程逐个 add 后 close |
| `_GenerateStream&lt;T&gt;` | class | IO/Stream.sl |  | _GenerateStream&lt;T&gt; — 生成生产流：gen(i) 产出 i ∈ [0, count) |
| `_PeriodicStream&lt;T&gt;` | class | IO/Stream.sl |  | _PeriodicStream&lt;T&gt; — 周期流：每 millis 毫秒产出一个 tick() 元素 |
| `_EmptyStream&lt;T&gt;` | class | IO/Stream.sl |  | _EmptyStream&lt;T&gt; — 空流：订阅即 done |
| `_ErrorStream&lt;T&gt;` | class | IO/Stream.sl |  | _ErrorStream&lt;T&gt; — 错误流：订阅即 error + done |
| `_FromByteStreamStream&lt;T&gt;` | class | IO/Stream.sl |  | _FromByteStreamStream&lt;T&gt; — 字节流解码生产流（L0×L2×L1 三层桥接） 生产协程循环 read → decoder 分块转换 → … |
| `Int16` | class | Int16.sl |  | 16 位有符号整数，取值范围 -32768 ~ 32767，对应 C# short。 |
| `Int32` | class | Int32.sl |  | 32 位有符号整数（默认整数字面量类型），取值范围 -2^31 ~ 2^31-1，对应 C# int。 是大多数算术、索引与循环计数的基准类型，提供整型家族互转… |
| `Int64` | class | Int64.sl |  | 64 位有符号整数，取值范围 -2^63 ~ 2^63-1，对应 C# long。 用于大数计数、文件偏移、时间戳等超出 Int32 范围的场景。 |
| `Int8` | class | Int8.sl |  | 8 位有符号整数（二进制补码），取值范围 -128 ~ 127，对应 C# sbyte。 提供与整型家族的显式转换、比较、取绝对值与二进制/十六进制等进制串输出… |
| `Iterater` | class | IterateVariable.sl | implements IIterator | 迭代器适配器：包装任意 IIterable 提供一个带 index / value 的游标式迭代器（foreach 底层常用），支持复位、前进与取值。 |
| `Iterater&lt;T&gt;` | class | IterateVariable.sl | implements IIterator&lt;T&gt; | 泛型迭代器适配器：强类型版 Iterater，包装 IIterable&lt;T&gt; 提供带 index / value 的游标式迭代。 |
| `IIterator` | interface | IteratorInterface.sl | implements IIterator | 迭代器与可迭代契约（标准库统一遍历协议） 任何支持 foreach / Range 遍历 / 容器迭代的类型都实现 IIterable&lt;T&gt;，由其返回 IIte… |
| `IIterable` | interface | IteratorInterface.sl | implements IIterable | SLang 标准库接口 IIterable（详见源文件）。 |
| `IIterator&lt;out T&gt;` | interface | IteratorInterface.sl | implements IIterator&lt;out T&gt; | SLang 标准库接口 IIterator&lt;out T&gt;（详见源文件）。 |
| `IIterable&lt;T&gt;` | interface | IteratorInterface.sl | implements IIterable&lt;T&gt; | SLang 标准库接口 IIterable&lt;T&gt;（详见源文件）。 |
| `Member` | class | Member.sl |  | 反射 / 解构成员描述：携带名称、下标与值的轻量记录结构。 用于元组解构、反射取值等场景，把“某个具名/具下标的槽位及其当前值”打包成一个对象。 |
| `Memory` | class | Memory.sl |  | Memory - Memory management and garbage collection API. Inspired by: CLR  : Syste… |
| `Monitor` | class | Monitor.sl |  | Monitor 点监视采样门面（DEBUG_SYSTEM_DESIGN.md v4） 链路：Monitor.* → Front 特译 Debug IR（comp… |
| `Nickname` | class | Nickname.sl |  | SLang 标准库类型 Nickname（详见源文件）。 |
| `Object` | class | Object.sl |  | SLang 标准库类型 Object（详见源文件）。 |
| `Ptr` | class | Ptr.sl |  | Ptr - Pointer abstraction for native memory access. Inspired by: CLR  : System.I… |
| `Ptr&lt;T&gt;` | class | Ptr.sl |  | Ptr&lt;T&gt; - Typed pointer for accessing object internals. Inspired by: C++  : T* (t… |
| `Random` | class | Random.sl |  | 伪随机数生成器：基于线性同余算法（LCG，a=1103515245 c=12345 m=2^31-1）按种子生成确定性随机序列，支持整型 / 浮点 / 区间取样… |
| `Range&lt;T:Num&gt;` | class | Range.sl | implements IIterable&lt;T&gt;, IIterator&lt;T&gt; | SLang 标准库类型 Range&lt;T:Num&gt;（详见源文件）。 |
| `Result` | class | Result.sl |  | 通用返回结果封装：value 携带业务数据，code 携带状态码（0=成功），message 携带提示信息。 与 Core.Result&lt;T&gt; 配对（泛型版 v… |
| `Result&lt;T&gt;` | class | Result.sl |  | 泛型版返回结果封装（语义同 Result，value 强类型 T）。 |
| `String` | class | String.sl |  | SLang 标准库类型 String（详见源文件）。 |
| `ConfitFormat` | class | Text/BaseConfigFormat.sl |  | 配置格式基类（模板方法骨架）：以 JSON 字符串为输入构造，提供空实现的初始化 / 序列化方法， 供具体配置格式（如 TOML / YAML 等）派生并重写其… |
| `BaseJson` | class | Text/BaseJson.sl |  | JSON 文本门面：基于 Tree&lt;string&gt; 树容器实现的 JSON 文本解析与序列化工具。 只处理文本，不做文件读写；文件相关功能见 Std/Text/… |
| `BaseToml` | class | Text/BaseToml.sl | implements IDataStruct | TOML 配置数据结构的基类骨架：以 JSON 字符串初始化，toString 等方法留空实现，待具体派生类完成。 |
| `BaseXml` | class | Text/BaseXml.sl |  | XML 文本门面：基于 Tree&lt;string&gt; 树容器实现的 XML 文本解析与序列化工具。 只处理文本，不做文件读写；文件相关功能见 Std/Text/Xm… |
| `BaseYaml` | class | Text/BaseYaml.sl |  | YAML 文本门面：基于 Tree&lt;string&gt; 树容器实现的 YAML 文本解析与序列化工具。 只处理文本，不做文件读写；文件相关功能见 Std/Text/… |
| `JsonValue` | class | Text/JsonValue.sl | extends Object  | JSON 层次化节点视图：包装 TreeNode&lt;string&gt; 的弱类型 JSON 节点， 提供多层嵌套导航与类型化取值，弥补 BaseJson 路径取值（s… |
| `Lz4` | class | Text/Lz4.sl |  | SLang 标准库类型 Lz4（详见源文件）。 |
| `PbTag` | class | Text/ProtocalBuffers.sl |  | 字段 tag：fieldNumber(1..2^29) + wireType(0..5) |
| `PbCoding` | class | Text/ProtocalBuffers.sl |  | 线格式原语薄封装：zigzag 走 C 层 SystemZigZagEncode / SystemZigZagDecode |
| `PbWriter` | class | Text/ProtocalBuffers.sl |  | ── 写入器 ───────────────────────────────────────────────── |
| `PbReader` | class | Text/ProtocalBuffers.sl |  | ── 读取器 ───────────────────────────────────────────────── |
| `ProtocalBuffers` | class | Text/ProtocalBuffers.sl |  | ── 门面（保留原 ProtocalBuffers 类名与 extends Object 约定）── |
| `StringBuilder` | class | Text/StringBuilder.sl |  | Core/Container/StringBuilder.sl — 可变字符串构建器（快速变体） 存储后端复用 IO/ByteBuffer（本体在 C VM 端… |
| `MetaClass` | class | Type.sl |  | 元类：承载类型的命名空间与类名等元信息，供反射读取类型标识。 |
| `Type` | class | Type.sl |  | 类型对象：运行时类型的统一表示，封装底层类型枚举（eType）与元类（MetaClass），用于反射判断与类型信息读取。 |
| `UInt16` | class | UInt16.sl |  | 16 位无符号整数，取值范围 0 ~ 65535，对应 C# ushort。 |
| `UInt32` | class | UInt32.sl |  | 32 位无符号整数，取值范围 0 ~ 4294967295，对应 C# uint。 |
| `UInt64` | class | UInt64.sl |  | 64 位无符号整数，对应 C# ulong，用于大计数、容量与句柄等场景。 |
| `UInt8` | class | UInt8.sl |  | 8 位无符号整数，取值范围 0 ~ 255，对应 C# byte。 |
| `Void` | class | Void.sl |  | 空类型占位：表示“无返回值”或“无类型”的语法占位类型，本身不含任何成员。 用于需要类型参数但语义上无值的场景（如某些泛型约束或返回占位）。 |
<!-- CORE-API-END -->
