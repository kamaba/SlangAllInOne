# Container/Map.sl

> 源文件：`Container/Map.sl`

## class `MapEntity<TKey,TValue>`

- **说明**：键值对实体：hashId 缓存 key.hashCode（供哈希类容器扩展使用），key/value 公开可读写。 link 字段用于哈希桶链表（同 bucket 冲突时的链式地址）与删除后的空闲链表复用。 独立顶级类：外部模块通过 Map 迭代器 current / entryAt 访问 key、value。

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `public int hashId = 0` | 字段 int（类型见签名）。 |
| 字段 | `public TKey key = null` | 字段 TKey（类型见签名）。 |
| 字段 | `public TValue value = null` | 字段 TValue（类型见签名）。 |
| 字段 | `public int link = -1` | 字段 int（类型见签名）。 |
| 方法 | `string toString()` | 转换为 Stringundefined 类型（toString）。 |

## class `Map<TKey,TValue>`

- **基类**：Object
- **说明**：字典容器：仿 C# Dictionary<TKey,TValue> 的哈希表实现。 核心数据结构： _buckets  -- 桶数组，存储 entries 中的索引+1（0 表示空桶） _entries  -- 实际存放 key-value 的实体数组 _count    -- 已使用的槽位数（含已删除的空闲槽） _freeList -- 被删除元素的空闲链表头（-1 表示无空闲槽，复用空位是 .NET 核心优化） _freeCount-- 空闲槽数量 有效元素个数 = _count - _freeCount key 匹配用 hashCode + == 值比较（数值/字符串/布尔按值，类按 equals 语义）

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `Array&lt;int&gt; _buckets = null` | --- C# Dictionary 核心字段 --- |
| 字段 | `int _count = 0` | 字段 _count（类型见签名）。 |
| 字段 | `int _freeList = -1` | 字段 _freeList（类型见签名）。 |
| 字段 | `int _freeCount = 0` | 字段 _freeCount（类型见签名）。 |
| 字段 | `int _index = -1` | --- 迭代器字段 --- |
| 字段 | `MapEntity&lt;TKey,TValue&gt; _current = null` | 字段 _current（类型见签名）。 |
| 方法 | `override _init_()` | 默认构造，容量为0，首次添加时扩容为4（与 C# Dictionary 一致） |
| 方法 | `void _init_(int capacity)` | 指定初始容量构造（负数按 0 处理） |
| 属性 | `get int length()` | 有效元素个数 |
| 属性 | `get bool isEmpty()` | 获取 isEmpty 的值。 |
| 属性 | `get bool isNotEmpty()` | 获取 isNotEmpty 的值。 |
| 属性 | `get int capacity()` | 容量（内部数组长度） |
| 属性 | `set void capacity(int value)` | 设置 capacity 的值。 |
| 方法 | `void grow()` | 容量扩展：0-&gt;4，之后倍增 4-&gt;8-&gt;16...（与 C# 容器一致） |
| 方法 | `void ensureCapacity(int min)` | 执行 ensureCapacity(min)，行为详见源实现。 |
| 方法 | `void resize(int newSize)` | 重新分配 _buckets 和 _entries，并将已有有效元素重新哈希 |
| 方法 | `int getHash(TKey key)` | 计算 key 的哈希值 |
| 方法 | `int indexOfKey(TKey key)` | 查找 key 在 entries 中的下标，未找到返回 -1 通过 SystemMapFindEntry 系统调用在 VM 层完成桶链遍历（while 循环）， 避免 SL 层多次 SystemArrayGetValueThis + 成员访问的开销 |
| 方法 | `bool tryAdd(TKey key, TValue value)` | 执行 tryAdd(key, value)，行为详见源实现。 |
| 方法 | `bool tryGetValue(TKey key, TValue value)` | 执行 tryGetValue(key, value)，行为详见源实现。 |
| 方法 | `void insertEntry(TKey key, TValue value)` | 插入新 entry（不复用空闲槽时在 _count 位置追加，必要时扩容） |
| 方法 | `bool add(TKey key, TValue value)` | add 语义（同 C# Dictionary.Add 的无异常版 / TryAdd）：key 已存在时不修改原值并返回 false，新插入返回 true 需要覆盖旧值请用 m[key] = value（put 语义） |
| 方法 | `void _setItem_(TKey key, TValue value)` | m[key] = value 写入语义（put，同 Java HashMap.put / Dart m[k]=v）：key 已存在则更新 value，不存在则插入 |
| 方法 | `TValue _getItem_(TKey key)` | m[key] 读取语义：key 不存在返回 null（Dart Map 语义） |
| 方法 | `bool containsKey(TKey key)` | 是否包含指定 key |
| 方法 | `bool containsValue(TValue value)` | 是否包含指定 value |
| 方法 | `TValue getOrDefault(TKey key, TValue defaultValue)` | 读取指定 key 的值，不存在返回 defaultValue（Java 8 getOrDefault） |
| 方法 | `TValue putIfAbsent(TKey key, TValue value)` | key 不存在时才插入（Java 8 putIfAbsent）：返回已存在的值，原本不存在则插入并返回 null |
| 方法 | `TValue remove(TKey key)` | 删除指定 key 并返回其旧值（Java remove / Dart remove 语义），key 不存在返回 null |
| 方法 | `void removeAt(int index)` | 按下标删除实体（下标非法忽略） |
| 方法 | `MapEntity&lt;TKey,TValue&gt; entryAt(int index)` | 按下标取实体（下标非法或已删除返回 null） |
| 方法 | `void clear()` | 执行 clear()。 |
| 属性 | `get List&lt;TKey&gt; keys()` | 全部 key 组成的列表（Dart Map.keys） |
| 属性 | `get List&lt;TValue&gt; values()` | 全部 value 组成的列表（Dart Map.values） |
| 方法 | `void reset()` | 接口层：迭代器 |
| 方法 | `bool moveNext()` | 执行 moveNext()。 |
| 属性 | `get MapEntity&lt;TKey,TValue&gt; current()` | 获取 current 的值。 |
| 属性 | `set void current(TValue val)` | 迭代位置写入：替换当前实体的 value（key 不可变） |
| 属性 | `get int index()` | 获取 index 的值。 |
| 属性 | `set void index(int ind)` | 设置 index 的值。 |
| 方法 | `string toString()` | 输出 {key=value,key=value} 格式（同 Java HashMap.toString） |
