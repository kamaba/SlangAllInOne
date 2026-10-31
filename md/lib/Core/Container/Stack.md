# Container/Stack.sl

> 源文件：`Container/Stack.sl`

## class `Stack<T>`

- **基类**：Object
- **说明**：后进先出（LIFO）栈：仿 C# Stack<T>，API 参考 Python list.append/pop / Dart List。 核心数据结构： _items    -- 底层数组（栈底在下标 0，栈顶在下标 _count-1） _count    -- 有效元素个数 _capacity -- 当前容量（恒等于 _items.length） 设计（与 LinkedList/Set 一致的分层）： - SL 层：泛型数组实例化（Array<T> 须由前端实例化）、容量决策与新数组分配； - C 层：入栈/出栈置值、扩容拷贝、查找比较、遍历物化、迭代推进等 全部耗时操作通过 SystemStack* 系统调用映射到 CVM 原生实现 （stack_system_method.c）。 空栈 pop/peek 返回 null（与本库其他容器越界返回 null 的语义一致）。

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `Array&lt;T&gt; _items = null` | --- 核心字段 --- |
| 字段 | `int _count = 0` | 字段 _count（类型见签名）。 |
| 字段 | `int _capacity = 0` | 字段 _capacity（类型见签名）。 |
| 字段 | `int _index = -1` | --- 迭代器字段（LIFO 迭代：从栈顶向栈底）--- |
| 字段 | `T _current = null` | 字段 _current（类型见签名）。 |
| 方法 | `override _init_()` | 默认构造，容量为0，首次 push 时扩容为4（与 C# Stack&lt;T&gt; 一致） |
| 方法 | `void _init_(int capacity)` | 指定初始容量构造（负数按 0 处理） |
| 方法 | `void _init_(Array&lt;T&gt; items)` | 从数组构造（元素按下标顺序入栈，数组首元素成为栈底）：遍历在 VM 层完成（SystemStackPushRange） |
| 属性 | `get int length()` | 有效元素个数（Python len(stack) / C# Count / Dart length） |
| 属性 | `get bool isEmpty()` | 获取 isEmpty 的值。 |
| 属性 | `get bool isNotEmpty()` | 获取 isNotEmpty 的值。 |
| 属性 | `get int capacity()` | 容量（内部数组长度） |
| 属性 | `set void capacity(int value)` | 设置 capacity 的值。 |
| 方法 | `void ensureCapacity(int min)` | 预分配容量，避免多次扩容拷贝（C# Stack.EnsureCapacity） |
| 方法 | `void grow()` | 容量扩展：0-&gt;4，之后倍增 4-&gt;8-&gt;16...（与 C# 容器一致） |
| 方法 | `void resizeArray(int newCapacity)` | 内部方法：换用新数组（新数组须由 SL 层分配，元素拷贝在 VM 层完成） |
| 方法 | `void push(T item)` | ── 栈操作 ── 入栈（C# Push / Python append）：容量已满时先扩容，置值与 _count++ 在 VM 层完成 |
| 方法 | `void pushRange(Array&lt;T&gt; items)` | 批量入栈（Python extend）：遍历与批量置值在 VM 层完成 |
| 方法 | `T pop()` | 出栈（C# Pop / Python pop）：弹出并移除栈顶；空栈返回 null |
| 属性 | `get T peek()` | 查看栈顶但不移除（C# Peek / Python stack[-1]）；空栈返回 null |
| 属性 | `get T bottom()` | 栈底元素（首个入栈元素）：读取在 VM 层完成 |
| 方法 | `bool contains(T item)` | ── 查找（VM 层完成）── 是否包含指定元素（Python in / C# Contains / Dart contains） |
| 方法 | `int indexOf(T item)` | 查找元素首次出现的位置（按栈底-&gt;栈顶方向，即底层数组下标），未找到返回 -1 |
| 方法 | `int lastIndexOf(T item)` | 查找元素最后一次出现的位置（按栈顶-&gt;栈底方向查找，返回底层数组下标），未找到返回 -1 |
| 方法 | `void clear()` | ── 删除 ── 清空栈（Python clear / C# Clear）：槽位置空、_count/_capacity/_items 与迭代器复位全部在 VM 层完成 |
| 方法 | `Array&lt;T&gt; toArray()` | ── 转换 ── 拷贝出元素数组（栈底-&gt;栈顶顺序，长度精确为当前元素数）：遍历在 VM 层完成 |
| 方法 | `List&lt;T&gt; toList()` | 转换为列表（SystemArrayCopy 系统级拷贝） |
| 方法 | `Stack&lt;T&gt; copy()` | 浅拷贝（Python stack.copy() / Dart List.of）：元素按下标顺序重新入栈，栈序不变 |
| 方法 | `void reset()` | ── 迭代器（foreach 热路径，SystemStackMoveNext 在 VM 层按 LIFO 顺序推进）── |
| 方法 | `bool moveNext()` | 执行 moveNext()。 |
| 属性 | `get T current()` | 获取 current 的值。 |
| 属性 | `get int index()` | 获取 index 的值。 |
| 方法 | `string toString()` | 输出 [a,b,c] 格式（栈底-&gt;栈顶，栈顶为最右侧元素）：结构遍历在 VM 层完成（toArray） |
