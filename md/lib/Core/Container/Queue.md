# Container/Queue.sl

> 源文件：`Container/Queue.sl`

## class `Queue<T>`

- **基类**：Object
- **说明**：先进先出（FIFO）队列：仿 C# Queue<T>，API 参考 Python collections.deque / Dart Queue。 核心数据结构（环形缓冲）： _items    -- 底层数组（容量 _capacity，逻辑首元素在 _head，下一个入队槽位在 _tail） _head     -- 队首下标（下一个出队位置） _tail     -- 队尾下标（下一个入队位置，环绕递增） _count    -- 有效元素个数 _capacity -- 当前容量（恒等于 _items.length） 设计（与 Stack/LinkedList/Set 一致的分层）： - SL 层：泛型数组实例化（Array<T> 须由前端实例化）、容量决策与新数组分配； - C 层：入队/出队置值、环绕游标推进、扩容拷贝、查找比较、遍历物化、迭代推进等 全部耗时操作通过 SystemQueue* 系统调用映射到 CVM 原生实现 （queue_system_method.c）。 空队 dequeue/peek 返回 null（与本库其他容器越界返回 null 的语义一致）。

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `Array&lt;T&gt; _items = null` | --- 核心字段 --- |
| 字段 | `int _head = 0` | 字段 _head（类型见签名）。 |
| 字段 | `int _tail = 0` | 字段 _tail（类型见签名）。 |
| 字段 | `int _count = 0` | 字段 _count（类型见签名）。 |
| 字段 | `int _capacity = 0` | 字段 _capacity（类型见签名）。 |
| 字段 | `int _index = -1` | --- 迭代器字段（FIFO 迭代：从队首向队尾）--- |
| 字段 | `T _current = null` | 字段 _current（类型见签名）。 |
| 方法 | `override _init_()` | 默认构造，容量为0，首次 enqueue 时扩容为4（与 C# Queue&lt;T&gt; 一致） |
| 方法 | `void _init_(int capacity)` | 指定初始容量构造（负数按 0 处理） |
| 方法 | `void _init_(Array&lt;T&gt; items)` | 从数组构造（元素按下标顺序入队，数组首元素成为队首）：遍历在 VM 层完成（SystemQueueEnqueueRange） |
| 属性 | `get int length()` | 有效元素个数（Python len(queue) / C# Count / Dart length） |
| 属性 | `get bool isEmpty()` | 获取 isEmpty 的值。 |
| 属性 | `get bool isNotEmpty()` | 获取 isNotEmpty 的值。 |
| 属性 | `get int capacity()` | 容量（内部数组长度） |
| 属性 | `set void capacity(int value)` | 设置 capacity 的值。 |
| 方法 | `void ensureCapacity(int min)` | 预分配容量，避免多次扩容拷贝（C# Queue.EnsureCapacity） |
| 方法 | `void grow()` | 容量扩展：0-&gt;4，之后倍增 4-&gt;8-&gt;16...（与 C# 容器一致） |
| 方法 | `void resizeArray(int newCapacity)` | 内部方法：换用新数组（新数组须由 SL 层分配，元素按队首-&gt;队尾顺序拷贝并归位 _head/_tail，在 VM 层完成） |
| 方法 | `void enqueue(T item)` | ── 队列操作 ── 入队（C# Enqueue / Python append / Dart add）：容量已满时先扩容，置值与 _tail/_count 推进在 VM 层完成 |
| 方法 | `void enqueueRange(Array&lt;T&gt; items)` | 批量入队（Python extend）：遍历与批量置值在 VM 层完成 |
| 方法 | `T dequeue()` | 出队（C# Dequeue / Python popleft）：移除并返回队首；空队返回 null |
| 属性 | `get T peek()` | 查看队首但不移除（C# Peek / Python queue[0]）；空队返回 null |
| 属性 | `get T rear()` | 队尾元素（最后入队元素）：读取在 VM 层完成 |
| 方法 | `bool contains(T item)` | ── 查找（VM 层完成）── 是否包含指定元素（Python in / C# Contains / Dart contains） |
| 方法 | `int indexOf(T item)` | 查找元素首次出现的位置（按队首-&gt;队尾方向，返回逻辑下标），未找到返回 -1 |
| 方法 | `int lastIndexOf(T item)` | 查找元素最后一次出现的位置（按队首-&gt;队尾方向查找最后匹配，返回逻辑下标），未找到返回 -1 |
| 方法 | `void clear()` | ── 删除 ── 清空队列（Python clear / C# Clear）：槽位置空、_count/_capacity/_items/_head/_tail 与迭代器复位全部在 VM 层完成 |
| 方法 | `Array&lt;T&gt; toArray()` | ── 转换 ── 拷贝出元素数组（队首-&gt;队尾顺序，长度精确为当前元素数）：遍历在 VM 层完成 |
| 方法 | `List&lt;T&gt; toList()` | 转换为列表 |
| 方法 | `Queue&lt;T&gt; copy()` | 浅拷贝（Python queue.copy() / Dart Queue.of）：元素按队首-&gt;队尾顺序重新入队，队列序不变 |
| 方法 | `void reset()` | ── 迭代器（foreach 热路径，SystemQueueMoveNext 在 VM 层按 FIFO 顺序推进）── |
| 方法 | `bool moveNext()` | 执行 moveNext()。 |
| 属性 | `get T current()` | 获取 current 的值。 |
| 属性 | `get int index()` | 获取 index 的值。 |
| 方法 | `string toString()` | 输出 [a,b,c] 格式（队首-&gt;队尾）：结构遍历在 VM 层完成（toArray） |
