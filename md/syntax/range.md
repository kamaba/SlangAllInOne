# 范围（Range）

> 本文是 `Range` 的**使用说明**：定义方式、迭代规则、成员方法、包含判断的边界，以及常见限制与替代方案。与其它语言习惯不同之处均已单独标注。

`Range` 是一个**惰性区间**结构：它不存储区间里的每一个元素，只记录起点、终点和步长，迭代时按需计算每个值。因此即使是一个 `1..1000000` 这样的区间，也几乎不占用额外内存，适合做快速遍历与生成。

---

## 0) 速查：最容易踩的规则

1. **迭代是半开区间 `[start, end)`**：升序时包含起点、**不含终点**（如 `1..100` 产出 `1,2,…,99`）。
2. **`isContain(t)` 是两端都开的 `(start, end)`**：起点和终点本身**都不算包含**——和迭代"含起点"不一致，是已知坑（见 §5）。
3. **步长只能在构造时给定**：没有 `step()` / `SetStep()` 之类的方法，构造后再也改不了步长。
4. **`..` 语法糖两端目前只支持数字字面量**（如 `1..100`），不支持变量或表达式（如 `1..n`、`a..b`）。
5. **`Range` 不能直接 `Cast` 成数组**：要物化成数组用 `toArray()`。

---

## 1) 类型规则

| 项 | 规则 |
|----|------|
| 类型名 | `Range<T>`，关键字/泛型类型，引用 Core 后直接可用，无需 import |
| 泛型约束 | `T : Num`，即 `T` 必须是数值类型（`int`/`short`/`long`/`float`/`double`/`Num` 等），非数值类型无法实例化 |
| 迭代接口 | 实现 `IIterable<T>` 与 `IIterator<T>`，因此可以直接用于 `for v in r` |
| 惰性 | 只存起点/终点/步长，迭代时按需计算，**不预分配元素** |
| 类型判断 | `is Range<int>` / `as Range<int>` 见 [`./cast.md`](./cast.md) |

---

## 2) 定义方式

有三种等价的写法，选顺手的即可。

### 2.1 `..` 区间语法糖（最简洁，整数/浮点字面量）

```sl
r1 = 1..100          # 等价于 range(1, 100, 1)，int 区间
r2 = 1.0f..10.0f     # float 区间，步长 1.0f
```

- 只能写**字面量**；`1..n`、`a..b`、含表达式的端点当前均不支持。
- 终点按"不含"处理（`1..100` 的最大值取不到 `100`）。

### 2.2 `range(...)` 小写构造糖

```sl
r3 = range(1, 100)           # 起点 1、终点 100、步长 1
r4 = range(1, 100, 2)        # 起点 1、终点 100、步长 2（产出 1,3,5,…,99）
r5 = range(100)              # 只给终点：起点取 0、步长 1 → 等价于 0..100（产出 0..99）
r6 = range(1.0f, 200.0f, 1.0f)
```

### 2.3 `Range<T>` 显式泛型 + 构造

```sl
Range<int>    r7 = new(1, 100)        # 起点 1、终点 100、步长 1
Range<double> r8 = new(3.2d, 54.3d, 0.22d)
Range<short>  r9 = Range<short>(1s, 100s, 2s)
```

构造重载一览（三种形态）：

| 调用 | 起点 | 终点 | 步长 |
|------|------|------|------|
| `range(end)` / `new(end)` | `0` | `end` | `1` |
| `range(start, end)` / `new(start, end)` | `start` | `end` | `1` |
| `range(start, end, step)` / `new(start, end, step)` | `start` | `end` | `step` |

> 步长可以是负数，用来表达**降序区间**（见 §3.2）；步长写 `0` 会得到**永远不会前进的空区间**（见 §7）。

---

## 3) 迭代（遍历）

`Range` 实现 `IIterable`，可直接放进 `for ... in` 循环：

```sl
for v in 1..100
{
    Console.println("v=$v")
}

for v in range(0, 10, 2)      # 0,2,4,6,8
{
    Console.println("even=$v")
}
```

### 3.1 升序区间：半开区间 `[start, end)`

步长为正时，产出序列为 `start, start+step, start+2*step, …`，**直到值不再小于终点**为止：

| 写法 | 产出的值 |
|------|----------|
| `1..100` | `1, 2, …, 99` |
| `range(1, 100, 2)` | `1, 3, …, 99` |
| `range(100)` | `0, 1, …, 99` |

### 3.2 降序区间：步长为负

把步长写成负数即可反向遍历，产出 `start, start+step, …`，**直到值不再大于终点**：

```sl
for v in range(10, 0, -1)     # 产出 10,9,8,…,1（不含 0）
{
    Console.println("countdown=$v")
}
```

### 3.3 空区间（不会进入循环体）

以下情况区间为空，循环体一次都不执行：

- 步长为 `0`（任何起点终点都如此）；
- 升序但起点 `>=` 终点（如 `range(100, 1)`）；
- 降序但起点 `<=` 终点（如 `range(1, 100, -1)`）。

---

## 4) 成员方法 / 属性全表

下表即 `Range<T>` 的**全部**成员，没有其它隐藏方法。

| 成员 | 签名 | 说明 |
|------|------|------|
| `_init_(T end)` | 构造 | 起点 `0`、终点 `end`、步长 `1` |
| `_init_(T start, T end)` | 构造 | 步长 `1` |
| `_init_(T start, T end, T step)` | 构造 | 显式指定步长 |
| `isContain` | `bool isContain(T t)` | 判断 `t` 是否在**开区间**内，见 §5 |
| `toArray` | `Array<T> toArray()` | 把区间物化成数组，结果带缓存（见 §6） |
| `reset` | `void reset()` | 把迭代游标重置回起点（`for ... in` 每次循环前会自动调用） |
| `moveNext` | `bool moveNext()` | 推进到下一个值；无更多值时返回 `false` |
| `current` | `T current()` | 返回上一次 `moveNext` 推进到的当前值；首次推进前为 `null` |
| `iterator` | `IIterator<T> iterator()` | 返回自身，供 `for ... in` 使用 |
| `toString` | `string toString()` | 返回形如 `"Range(1,100,1)"` 的文本 |

> 没有 `step()` / `SetStep()` / `length` / `count` / `size` 这类成员——步长只读（构造时定），区间长度也不提供直接查询。

---

## 5) 包含判断 `isContain` 的边界（重要坑）

`isContain(t)` 判定的是**两端都开的区间 `(start, end)`**：既不包含起点，也不包含终点。

```sl
r = 1..100            # start=1, end=100
r.isContain(1)        # false  ← 起点不算
r.isContain(100)      # false  ← 终点不算
r.isContain(50)       # true
r.isContain(0)        # false
r.isContain(101)      # false
```

注意它与迭代行为**不一致**：

| 操作 | `1..100` 是否含 `1` | 是否含 `100` |
|------|----------------------|--------------|
| `for v in …` 迭代产出 | ✅ 含（首值 `1`） | ❌ 不含 |
| `isContain(...)` 判断 | ❌ 不含 | ❌ 不含 |

降序时同理，开区间落在 `(end, start)`：

```sl
r = range(100, 1, -1)   # 迭代产出 100,99,…,1
r.isContain(100)        # true   （此时 100 落在 (1,100) 开区间内）
r.isContain(1)          # false  （终点 1 不算）
r.isContain(50)         # true
```

> 结论：要判断"是否落在区间覆盖的数值集合里"，用 `isContain` 时记得它**排除了两个端点**；若想包含端点，自己做 `t >= start && t < end`（升序）或等价的判断。

---

## 6) 与数组互转（`toArray`）

把区间物化成真正的 `Array<T>`：

```sl
r = 1..5
arr = r.toArray()        # Array<int> = [1,2,3,4]  （注意不含 5）
Console.println(arr.length)   # 4

arr2 = r.toArray()       # 第二次调用复用同一份缓存数组，不再重新遍历
```

要点：

- `toArray()` 会**完整遍历一次**区间并把每个值写进数组，区间很大时一次性分配对应大小的数组。
- 结果会被**缓存复用**：同一个 `Range` 对象多次调用 `toArray()` 返回的是同一数组，不会重复分配。
- `Range` 与数组**不能**用 `Cast` 互转——物化数组只能走 `toArray()`，数组转区间则直接用 `range(...)` / `..` 重新构造。

---

## 7) 常见坑与限制

| 需求 / 写法 | 行为 | 说明 / 替代 |
|------|------|-------------|
| `1..n`、`a..b` | 编译不支持 | `..` 两端只能写数字字面量；变量端点请用 `range(a, b)` |
| 中途改步长 | 不行 | `Range` 无 `step()` / `SetStep()`，步长只能在构造时给定 |
| 查询区间长度 / 元素个数 | 无 `length`/`count` | 自己按 `(end-start)/step` 估算，或 `toArray().length` 物化后取 |
| `isContain(start)` | `false` | 起点不被包含（开区间），见 §5 |
| 步长写 `0` | 空区间 | `moveNext()` 恒返回 `false`，循环不执行、物化得空数组 |
| 起点 `>=` 终点（升序） | 空区间 | 如 `range(100, 1)` 为空；想要降序请用负步长 `range(100, 1, -1)` |
| `for ... in` 的索引 / 下标 | 不支持 | `Range` 没有 index 游标；需要下标请 `toArray()` 后用带索引的遍历，或自己维护计数器 |
| 重复迭代同一个 `Range` 对象 | 正常 | `for ... in` 每次循环前会自动 `reset()`；若手动 `moveNext` 循环，需自己先调 `reset()` |
| 把 `Range` 当数组用 | 不行 | 没有下标访问，需 `toArray()` 物化 |

---

## 8) 综合示例

```sl
# 三种定义等价
r1 = 1..100                       # 等价于 range(1, 100, 1)
r2 = range(1.0f, 200.0f, 1.0f)
Range<double> r3 = new(3.2d, 54.3d, 0.22d)
Range<short>  r4 = Range<short>(1s, 100s, 2s)

# 升序遍历：半开区间，含起点不含终点
sum = 0
for v in 1..100                  # 1,2,…,99
{
    sum = sum + v
}

# 自定义步长
evens = ""
for v in range(0, 10, 2)         # 0,2,4,6,8
{
    evens = evens + v.toString() + " "
}

# 降序区间
for v in range(10, 0, -1)        # 10,9,…,1
{
    Console.println("countdown=$v")
}

# 包含判断（开区间，两端都不含）
r = 1..100
b1 = r.isContain(50)             # true
b2 = r.isContain(1)              # false（起点不算）
b3 = r.isContain(100)            # false（终点不算）

# 物化成数组（带缓存）
arr = r.toArray()                # [1,2,…,99]
arrAgain = r.toArray()           # 复用同一份数组

# 若业务需要"含终点"，把终点扩一格：range(1,101) 的半开区间正好产出到 100
rInclusiveEnd = range(1, 101)    # 产出 1,2,…,100
```

---

## 9) 相关文档

- 语法：[`./forwhiledowhile.md`](./forwhiledowhile.md)（`for ... in` 遍历规则）、[`./type.md`](./type.md)（泛型与数值类型）、[`./cast.md`](./cast.md)（`is`/`as` 类型判断）、[`./string.md`](./string.md)（`String.slice` 也叫"区间"但语义不同）
- 库：[`../lib/Core/String.md`](../lib/Core/String.md)、[`../lib/Core/`](../lib/Core/) 下相关容器文档
