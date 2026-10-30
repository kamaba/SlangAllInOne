# IO/Stream.sl

> 源文件：`IO/Stream.sl`

## class `_StreamEvent`

- **说明**：Core/IO/Stream.sl — L1 元素层：推/拉双模事件流 设计契约：md/design/STREAM_DESIGN.md §6 / §11.1 / §17(P1) P1 范围（可测子集 C/C2/D/E/F）： - abstract Stream<T>：listen 推模式 + IIterable<T> 拉模式 - StreamController / StreamSink / StreamSubscription - 惰性变换 map / where / take / skip / transform + 终端 forEach / toList - 生产流 fromIterable / generate / empty / error / fromByteStream - StreamTransformer<S,T> 抽象（具象 Transformer 为 P3） 合流 / 广播 / 分支（§6.2 / §6.3 的 P2/P3 项）不落本文件。 语义要点： - 推模式：listen 启动一个分发协程，从 controller 的事件通道逐个取出 _StreamEvent 分发给回调。回调在分发协程内串行同步执行。 - 拉模式：iterator 惰性引流 —— moveNext 首调时才 listen，事件写入 无缓冲上限 Channel<T>（send 永不挂起），recv 空则挂起（§11.1 E 组）。 - 单订阅语义：Stream 默认单订阅（多 listen 会分流事件）， 广播流为 P3（StreamController.broadcast）。 - add：事件通道容量满时挂起（§11.1 F 组，容量 1 controller 可测）； 默认构造为无缓冲上限（add 永不挂起）。 - cancel：置取消标记 + 关闭事件通道。分发循环在下一轮 recv / 标记 检查处退出；上游生产端对已关闭通道 send 抛异常而终止（粗粒度级联）。 - 错误不走异常通道：onError 回调接收（§14），throw 仅在 L0 字节层。 语言设施注记（p1-5 编译验证点，均为全库首例或稀有用法）： - 普通方法重载 Stream.listen（文档 md/syntax/class.md 支持， 全库现有重载仅 _init_ 构造） - try? 带返回值 + null 判定（先例 TryTest.sl：string r = try? f(...)） - 泛型方法 map<U> / transform<U> 与泛型基类继承 extends Stream<U> （Codec.sl 同款：_FusedCodec<S,T,M> extends Codec<S,M>） - 闭包捕获限制（doc/closure-design.md：仅外层方法局部变量/参数）： 所有 this._x 一律先拷局部再进闭包（ReceivePort.listen 同款模式） - 闭包内局部变量捕获 + 调用捕获对象的方法 / getter （先例 CoroutineTest 闭包体 g_sum / g_order 字段访问，更宽松） - getter 无括号调用（ev.kind / flag.value / ctrl.isClosed） 契约偏差（与 §6 对照，P4 精细化清单）： - 回调类型用 Function（设计稿 Func<void,T>，全库零命中弃用； 先例 Array.forEach / Coroutine.waitUntil / ReceivePort.listen） - StreamSubscription 非泛型、无 onData/onError/onDone setter （P1 无回调重挂场景） - controller.done 为轮询哨兵协程（P4 换事件通知机制） - take 取满 N 靠闭包捕获 sub 延迟绑定实现 cancel；若捕获实现为 值拷贝则降级为仅调 onDone 不 cancel，语义仍正确 - cancel 粗暴关闭通道：已缓冲的错误对象会丢失（P4 精细化） - StreamIterator 不透传错误：onError 仅关闭引流通道，元素流以 null 短路结束（P4 换 Result<T> 元素模型） _StreamEvent — 事件信封（非泛型） 嵌套泛型（Channel<StreamEvent<T>> 之类）全库无先例，故 payload/error 收敛为 object；kind: 0=data 1=error 2=done。getter 名 payload：data 是 SL 关键字（ETokenType.Data）不可作标识符。

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `object _data = null` | 字段 _data（类型见签名）。 |
| 字段 | `object _error = null` | 字段 _error（类型见签名）。 |
| 字段 | `int _kind = 0` | 字段 _kind（类型见签名）。 |
| 方法 | `void markData(object v)` | 执行 markData(v)，行为详见源实现。 |
| 方法 | `void markError(object e)` | 执行 markError(e)，行为详见源实现。 |
| 方法 | `void markDone()` | 执行 markDone()。 |
| 属性 | `get int kind()` | 获取 kind 的值。 |
| 属性 | `get object payload()` | 获取 payload 的值。 |
| 属性 | `get object errorValue()` | getter 名 errorValue：error 为 Result 语义保留名（见 md/syntax/result.md），避让 |

## class `_CancelFlag`

- **说明**：_CancelFlag — 取消标记（闭包内可写的布尔载体）

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `bool _v = false` | 字段 _v（类型见签名）。 |
| 属性 | `get bool value()` | 获取 value 的值。 |
| 方法 | `void setValue(bool v)` | 执行 setValue(v)，行为详见源实现。 |

## class `StreamSubscription`

- **说明**：StreamSubscription — 订阅句柄（非泛型） cancel：置取消标记 + 关闭事件通道，级联终止分发协程与上游生产。

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `_CancelFlag _flag = null` | 字段 _flag（类型见签名）。 |
| 字段 | `Task _task = null` | 字段 _task（类型见签名）。 |
| 字段 | `Channel&lt;object&gt; _chan = null` | 字段 _chan（类型见签名）。 |
| 构造 | `_init_(_CancelFlag flag, Task task, Channel&lt;object&gt; chan)` | 构造方法，初始化本类型实例。 |
| 方法 | `bool cancel()` | 判断状态是否（cancel）。 |
| 属性 | `get bool isCanceled()` | 获取 isCanceled 的值。 |

## class `StreamIterator<T>`

- **基类**：Object
- **说明**：StreamIterator<T> — 拉模式迭代器 moveNext 首调时才 listen 引流：事件写入无缓冲上限 Channel<T>， 之后每次 moveNext 从通道 recv（空则挂起，§11.1 E 组）。

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `Stream&lt;T&gt; _stream = null` | 字段 _stream（类型见签名）。 |
| 字段 | `Channel&lt;T&gt; _chan = null` | 字段 _chan（类型见签名）。 |
| 字段 | `bool _started = false` | 字段 _started（类型见签名）。 |
| 字段 | `T _current = null` | 字段 _current（类型见签名）。 |
| 构造 | `_init_(Stream&lt;T&gt; stream)` | 构造方法，初始化本类型实例。 |
| 方法 | `bool moveNext()` | 执行 moveNext()。 |
| 属性 | `get T current()` | 获取 current 的值。 |
| 方法 | `void reset()` | 迭代器 / 订阅控制（reset）。 |

## class `_ControllerStream<T>`

- **说明**：_ControllerStream<T> — controller.stream 的实现 listen 启动分发协程：从事件通道取 _StreamEvent 逐个分发给回调。

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `StreamController&lt;T&gt; _ctrl = null` | 字段 _ctrl（类型见签名）。 |
| 构造 | `_init_(StreamController&lt;T&gt; ctrl)` | 构造方法，初始化本类型实例。 |
| 方法 | `StreamSubscription listen(Function onData, Function onError, Function onDone, bool cancelOnError)` | 迭代器 / 订阅控制（listen）。 |

## class `StreamController<T>`

- **说明**：StreamController<T> — 流的写入端 默认无缓冲上限（add 永不挂起）；_init_(capacity) 指定容量后 add 在通道满时挂起（§11.1 F 组背压）。

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `Channel&lt;object&gt; _channel = null` | 字段 _channel（类型见签名）。 |
| 字段 | `Stream&lt;T&gt; _stream = null` | 字段 _stream（类型见签名）。 |
| 字段 | `bool _closed = false` | 字段 _closed（类型见签名）。 |
| 构造 | `_init_()` | 构造方法，初始化本类型实例。 |
| 构造 | `_init_(int capacity)` | 构造方法，初始化本类型实例。 |
| 属性 | `get Stream&lt;T&gt; stream()` | 对应的读取端（惰性创建，重复读取返回同一实例）。 |
| 属性 | `get StreamSink&lt;T&gt; sink()` | 分块转换输出端（衔接 Codec 的 chunked API）。 |
| 属性 | `get Channel&lt;object&gt; events()` | 原始事件通道（_ControllerStream 分发协程的数据源）。 |
| 属性 | `get bool isClosed()` | 获取 isClosed 的值。 |
| 方法 | `void add(T value)` | 投递一个数据事件；通道满时挂起。 |
| 方法 | `void addError(object errInfo)` | 投递一个错误事件；通道满时挂起。 参数名 errInfo：error 为 Result 语义保留名，避免使用 |
| 方法 | `void close()` | 投递 done 事件并关闭通道（已缓冲事件仍可被取尽）。 |
| 属性 | `get Task done()` | 写入端收尾等待（P1 轮询实现，P4 换事件通知）。 |

## class `StreamSink<T>`

- **说明**：StreamSink<T> — controller 的 sink 视图（extends Codec 的分块输出端） fromByteStream 桥接关键：decoder 的 chunked 输出直接喂给 controller。

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `StreamController&lt;T&gt; _ctrl = null` | 字段 _ctrl（类型见签名）。 |
| 构造 | `_init_(StreamController&lt;T&gt; ctrl)` | 构造方法，初始化本类型实例。 |
| 方法 | `void add(T chunk)` | 添加 / 插入元素（add）。 |
| 方法 | `void close()` | IO 读写 / 流控制（close）。 |

## class `_MapStream<S,U>`

- **说明**：_MapStream<S,U> — 惰性映射：fn(v) 结果转发给下游 onData

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `Stream&lt;S&gt; _source = null` | 字段 _source（类型见签名）。 |
| 字段 | `Function _mapper = null` | 字段 _mapper（类型见签名）。 |
| 构造 | `_init_(Stream&lt;S&gt; source, Function mapper)` | 构造方法，初始化本类型实例。 |
| 方法 | `StreamSubscription listen(Function onData, Function onError, Function onDone, bool cancelOnError)` | 迭代器 / 订阅控制（listen）。 |

## class `_WhereStream<T>`

- **说明**：_WhereStream<T> — 惰性过滤：fn(v) as bool 为 true 才放行

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `Stream&lt;T&gt; _source = null` | 字段 _source（类型见签名）。 |
| 字段 | `Function _predicate = null` | 字段 _predicate（类型见签名）。 |
| 构造 | `_init_(Stream&lt;T&gt; source, Function predicate)` | 构造方法，初始化本类型实例。 |
| 方法 | `StreamSubscription listen(Function onData, Function onError, Function onDone, bool cancelOnError)` | 迭代器 / 订阅控制（listen）。 |

## class `_TakeStream<T>`

- **说明**：_TakeStream<T> — 惰性截断：取满 N 后 cancel 上游 + 触发 onDone sub 延迟绑定：闭包先声明捕获，listen 返回后再赋值（见文件头偏差注记）。

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `Stream&lt;T&gt; _source = null` | 字段 _source（类型见签名）。 |
| 字段 | `int _count = 0` | 字段 _count（类型见签名）。 |
| 构造 | `_init_(Stream&lt;T&gt; source, int count)` | 构造方法，初始化本类型实例。 |
| 方法 | `StreamSubscription listen(Function onData, Function onError, Function onDone, bool cancelOnError)` | 迭代器 / 订阅控制（listen）。 |

## class `_SkipStream<T>`

- **说明**：_SkipStream<T> — 惰性跳过：丢弃前 N 个后透传

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `Stream&lt;T&gt; _source = null` | 字段 _source（类型见签名）。 |
| 字段 | `int _count = 0` | 字段 _count（类型见签名）。 |
| 构造 | `_init_(Stream&lt;T&gt; source, int count)` | 构造方法，初始化本类型实例。 |
| 方法 | `StreamSubscription listen(Function onData, Function onError, Function onDone, bool cancelOnError)` | 迭代器 / 订阅控制（listen）。 |

## class `_FromIterableStream<T>`

- **说明**：_FromIterableStream<T> — 数组生产流：生产协程逐个 add 后 close

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `Array&lt;T&gt; _items = null` | 字段 _items（类型见签名）。 |
| 构造 | `_init_(Array&lt;T&gt; items)` | 构造方法，初始化本类型实例。 |
| 方法 | `StreamSubscription listen(Function onData, Function onError, Function onDone, bool cancelOnError)` | 迭代器 / 订阅控制（listen）。 |

## class `_GenerateStream<T>`

- **说明**：_GenerateStream<T> — 生成生产流：gen(i) 产出 i ∈ [0, count)

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `int _count = 0` | 字段 _count（类型见签名）。 |
| 字段 | `Function _gen = null` | 字段 _gen（类型见签名）。 |
| 构造 | `_init_(int count, Function gen)` | 构造方法，初始化本类型实例。 |
| 方法 | `StreamSubscription listen(Function onData, Function onError, Function onDone, bool cancelOnError)` | 迭代器 / 订阅控制（listen）。 |

## class `_PeriodicStream<T>`

- **说明**：_PeriodicStream<T> — 周期流：每 millis 毫秒产出一个 tick() 元素

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `Int64 _millis = 0` | 字段 _millis（类型见签名）。 |
| 字段 | `Function _tick = null` | 字段 _tick（类型见签名）。 |
| 构造 | `_init_(Int64 millis, Function tick)` | 构造方法，初始化本类型实例。 |
| 方法 | `StreamSubscription listen(Function onData, Function onError, Function onDone, bool cancelOnError)` | 迭代器 / 订阅控制（listen）。 |

## class `_EmptyStream<T>`

- **说明**：_EmptyStream<T> — 空流：订阅即 done

| 类型 | 签名 | 说明 |
|------|------|------|
| 方法 | `StreamSubscription listen(Function onData, Function onError, Function onDone, bool cancelOnError)` | 迭代器 / 订阅控制（listen）。 |

## class `_ErrorStream<T>`

- **说明**：_ErrorStream<T> — 错误流：订阅即 error + done

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `object _error = null` | 字段 _error（类型见签名）。 |
| 构造 | `_init_(object errInfo)` | 构造方法，初始化本类型实例。 |
| 方法 | `StreamSubscription listen(Function onData, Function onError, Function onDone, bool cancelOnError)` | 迭代器 / 订阅控制（listen）。 |

## class `_FromByteStreamStream<T>`

- **说明**：_FromByteStreamStream<T> — 字节流解码生产流（L0×L2×L1 三层桥接） 生产协程循环 read → decoder 分块转换 → sink 写入 controller； read 异常（try? 返 null）转投 StreamIOError.Timeout 事件（P4 透传原始错误）。

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `ByteStream _src = null` | 字段 _src（类型见签名）。 |
| 字段 | `Codec&lt;T, ByteBuffer&gt; _codec = null` | 字段 ByteBuffer（类型见签名）。 |
| 构造 | `_init_(ByteStream src, Codec&lt;T, ByteBuffer&gt; codec)` | 构造方法，初始化本类型实例。 |
| 方法 | `StreamSubscription listen(Function onData, Function onError, Function onDone, bool cancelOnError)` | 迭代器 / 订阅控制（listen）。 |
