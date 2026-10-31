# Container/Channel.sl

> 源文件：`Container/Channel.sl`

## class `Channel<T>`

- **说明**：SLang 标准库类型 Channel<T>（详见源文件）。

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `Int64 _chid = 0` | 字段 _chid（类型见签名）。 |
| 构造 | `_init_()` | 默认构造：无缓冲上限通道（capacity = 0 表示 unbounded） |
| 构造 | `_init_(int capacity)` | 指定容量构造：capacity &lt;= 0 视为无缓冲上限 |
| 方法 | `Channel&lt;T&gt; create()` | 初始化 / 创建（create）。 |
| 方法 | `Channel&lt;T&gt; create(int capacity)` | 初始化 / 创建（create）。 |
| 方法 | `void send(T value)` | 发送一个值。缓冲满时挂起当前协程直至有空位；通道已关闭时抛出异常。 |
| 方法 | `T recv()` | 接收一个值。缓冲空且未关闭时挂起当前协程；通道已关闭且缓冲空时返回 null。 |
| 方法 | `void close()` | 关闭通道。唤醒全部等待中的发送者与接收者。 |
| 属性 | `get int count()` | 缓冲内当前元素个数 |
| 属性 | `get bool isClosed()` | 通道是否已关闭 |
