# Container/HashSet.sl

> 源文件：`Container/HashSet.sl`

## class `SetEntity<T>`

- **说明**：集合元素实体：hashId 缓存 value.hashCode（桶链快速过滤用），value 公开可读写。 link 字段用于哈希桶冲突链（同 bucket 的链式地址），删除后复用作空闲链表节点（.NET 空间复用优化）。 独立顶级类：与 Map.MapEntity 对称，便于调试观察。

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `public int hashId = 0` | 字段 int（类型见签名）。 |
| 字段 | `public T value = null` | 字段 T（类型见签名）。 |
| 字段 | `public int link = -1` | 字段 int（类型见签名）。 |
| 方法 | `string toString()` | 转换为 Stringundefined 类型（toString）。 |

## class `HashSet<T>`

- **基类**：Object
- **说明**：无序不重复集合：仿 C# HashSet<T>（即只存 key 的 Dictionary），API 参考 Python set / Dart Set。 类名使用 HashSet 以避免与属性 setter 关键字 set 冲突（小写容器语法糖为 hashset()）。 核心数据结构（与 Core.Map 一致）： _buckets  -- 桶数组，存储 entries 中的索引+1（0 表示空桶） _entries  -- 实际存放元素的实体数组（SetEntity，hashId 缓存哈希，-1 表示空闲槽） _count    -- 已使用的槽位数（含已删除的空闲槽） _freeList -- 被删除元素的空闲链表头（-1 表示无空闲槽） _freeCount-- 空闲槽数量 有效元素个数 = _count - _freeCount 元素匹配用 hashCode + == 值比较（与 Map 的 key 匹配语义一致） 性能设计：桶链查找/插入/删除、扩容重哈希、集合运算、迭代推进等查找比较与遍历的耗时操作 全部通过 SystemSet* 系统调用映射到 CVM 原生实现（set_system_method.c）， SL 层仅负责 hashCode 虚调用（用户类可重写）、SetEntity 泛型实例化与初始数组分配。

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `Array&lt;int&gt; _buckets = null` | --- C# HashSet 核心字段 --- |
| 字段 | `int _count = 0` | 字段 _count（类型见签名）。 |
| 字段 | `int _freeList = -1` | 字段 _freeList（类型见签名）。 |
| 字段 | `int _freeCount = 0` | 字段 _freeCount（类型见签名）。 |
| 字段 | `int _index = -1` | --- 迭代器字段 --- |
| 字段 | `T _current = null` | 字段 _current（类型见签名）。 |
| 方法 | `override _init_()` | 默认构造，容量为0，首次添加时分配为4（与 C# HashSet 一致） |
| 方法 | `void _init_(int capacity)` | 指定初始容量构造（负数按 0 处理） |
| 方法 | `void _init_(Array&lt;T&gt; items)` | 从数组构造（Python set(iterable) / Dart Set.from）：哈希须在 SL 层计算故逐个 add |
| 属性 | `get int length()` | 有效元素个数（Python len(set) / Dart set.length） |
| 属性 | `get bool isEmpty()` | 获取 isEmpty 的值。 |
| 属性 | `get bool isNotEmpty()` | 获取 isNotEmpty 的值。 |
| 属性 | `get int capacity()` | 容量（内部数组长度） |
| 属性 | `set void capacity(int value)` | 设置 capacity 的值。 |
| 方法 | `void grow()` | 容量扩展：0-&gt;4，之后倍增 4-&gt;8-&gt;16...（与 C# 容器一致） |
| 方法 | `void ensureCapacity(int min)` | 预分配容量，避免多次扩容重哈希（C# HashSet.EnsureCapacity） |
| 方法 | `void resize(int newSize)` | 重哈希：新数组分配、空闲槽压缩、桶链重建全部在 VM 层完成（SystemSetRehash） |
| 方法 | `int getHash(T item)` | 计算元素的哈希值（虚调用，用户类可重写 hashCode） |
| 方法 | `bool add(T item)` | 添加元素（C# HashSet.Add / Python set.add / Dart Set.add） 已存在返回 false，新增返回 true；桶链查重、空闲槽复用、扩容重哈希均在 VM 层完成 |
| 方法 | `void addRange(Array&lt;T&gt; items)` | 从数组批量添加（Python set.update(iterable)）：哈希须在 SL 层计算故逐个 add |
| 方法 | `bool contains(T item)` | 是否包含指定元素（Python in / C# Contains / Dart contains）：VM 层桶链查找 |
| 方法 | `bool remove(T item)` | 移除指定元素（C# HashSet.Remove / Dart Set.remove）：VM 层桶链查找并摘除，成功返回 true |
| 方法 | `void clear()` | 清空集合（Python set.clear / C# Clear）：VM 层置空内部数组并复位迭代器 |
| 方法 | `void unionWith(HashSet&lt;T&gt; other)` | ---- 修改型集合运算（VM 层完成）---- 并集并入（Python \|= / set.update；C# UnionWith） |
| 方法 | `void intersectWith(HashSet&lt;T&gt; other)` | 交集保留（Python &=；C# IntersectWith）：删除不在 other 中的元素 |
| 方法 | `void exceptWith(HashSet&lt;T&gt; other)` | 差集移除（Python -=；C# ExceptWith）：删除同时在 other 中的元素 |
| 方法 | `void symmetricExceptWith(HashSet&lt;T&gt; other)` | 对称差（Python ^=；C# SymmetricExceptWith）：删除交集并并入双方独有元素 |
| 方法 | `HashSet&lt;T&gt; union(HashSet&lt;T&gt; other)` | ---- 非修改型集合运算（返回新 HashSet，底层为 VM 调用组合）---- 并集（Python \| / set.union） |
| 方法 | `HashSet&lt;T&gt; intersection(HashSet&lt;T&gt; other)` | 交集（Python & / set.intersection） |
| 方法 | `HashSet&lt;T&gt; difference(HashSet&lt;T&gt; other)` | 差集（Python - / set.difference） |
| 方法 | `HashSet&lt;T&gt; symmetricDifference(HashSet&lt;T&gt; other)` | 对称差（Python ^ / set.symmetric_difference） |
| 方法 | `HashSet&lt;T&gt; copy()` | 浅拷贝（Python set.copy / Dart Set.toSet）：VM 层单次调用完成 |
| 方法 | `bool isSubsetOf(HashSet&lt;T&gt; other)` | ---- 判断型集合运算（VM 层完成）---- 子集判断（Python issubset；C# IsSubsetOf）：空集是任何集合的子集 |
| 方法 | `bool isSupersetOf(HashSet&lt;T&gt; other)` | 超集判断（Python issuperset；C# IsSupersetOf）：任何集合是空集的超集 |
| 方法 | `bool isProperSubsetOf(HashSet&lt;T&gt; other)` | 真子集判断（Python set &lt; set） |
| 方法 | `bool isProperSupersetOf(HashSet&lt;T&gt; other)` | 真超集判断（Python set &gt; set） |
| 方法 | `bool overlaps(HashSet&lt;T&gt; other)` | 交集非空判断（C# Overlaps）：任一公共元素即 true |
| 方法 | `bool setEquals(HashSet&lt;T&gt; other)` | 集合相等判断（C# SetEquals）：元素完全相同（与顺序无关） |
| 方法 | `Array&lt;T&gt; toArray()` | ---- 转换 ---- 拷贝出元素数组（长度精确为当前有效元素数）：VM 层遍历填充 |
| 方法 | `List&lt;T&gt; toList()` | 转换为列表（SystemArrayCopy 系统级拷贝） |
| 属性 | `get T first()` | 首元素（Dart Set.first）：遍历在 VM 层完成 |
| 属性 | `get T last()` | 末元素（Dart Set.last）：遍历在 VM 层完成 |
| 方法 | `void reset()` | ---- 迭代器（foreach 热路径，SystemSetMoveNext 在 VM 层推进并跳过空闲槽）---- |
| 方法 | `bool moveNext()` | 执行 moveNext()。 |
| 属性 | `get T current()` | 获取 current 的值。 |
| 属性 | `get int index()` | 获取 index 的值。 |
| 方法 | `string toString()` | 输出 {a,b,c} 格式（同 Python/Dart 集合字面量）：桶结构遍历在 VM 层完成（toArray） |
