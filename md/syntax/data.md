# data（数据类型）

`data` 是一种轻量的数据结构定义方式，更接近 C# 里的 `struct` / 纯数据载体。它的成员声明风格接近 `class`，但用途更偏向于描述结构化数据、配置数据以及数据字面量。

`data` 的定位：

- 只用于提供数据，不提供函数行为
- 内部不支持定义成员函数 / 普通函数
- 重点是结构、成员值、结构匹配、打印与比较

---

## 1. 基本声明

普通 `data`：

```sl
data UserInfo
{
    id = 0
    name = ""
}
```

只读 `const data`：

```sl
const data Rule
{
    min = 1
    max = 100
}
```

静态 `static data`（单例，成员经类型名直接访问）：

```sl
static data Counter
{
    total = 0
}
```

说明与约束：

- `data` 适合描述一组字段，不强调行为。
- `const data` 应视为只读数据：可以读取 `Rule.min`、`Rule.max`，不应再对其成员重新赋值。
- `static data` 表示静态数据单例，成员经类型名访问；非 `const` 的静态 `data` 允许静态写入，`const` 静态 `data` 写入会报错。
- 修饰符使用范围：`static` / `const` 这类类型级修饰仅 `data`（与 `enum` 的 `const`）允许——`static` 是 `data` 独有，`const` 不允许出现在 `class` / `interface` 上。

---

## 2. 成员声明形式

`data` 内部可以像 `class` 字段一样声明成员，也可以使用数组字面量、对象字面量，以及嵌套 `data` 字面量。

支持的核心成员值类型：

- 常数：`int`/`int8`/`int16`/`int32`/`int64`/`uint`/`string`/`bool`/`float`/`double` 等
- 数组：`[]`
- 匿名对象 / 匿名 data：`{}`
- 具名 `class` 实例：`ClassName(){}`
- 具名 `data` 实例：`DataName(){}`
- `enum` 值：`EnumName.Member`

### 2.1 标量成员

```sl
data UserInfo
{
    id = 0
    name = "guest"
    enabled = true
}
```

数字字面量默认按 `int32` 推导，只有加了后缀/显式类型才会确定更多类型。

### 2.2 数组成员

直接用 `[]` 初始化数组成员，数组内部可以再放常数、数组、匿名 data、具名 data / class / enum 等：

```sl
data ScoreInfo
{
    scores = [100, 98, 87]
    tags = ["math", "final", "top"]
}

data GroupInfo
{
    matrix = [[1, 2], [3, 4]]
    students = [
        { name = "A", age = 18 },
        { name = "B", age = 19 }
    ]
}
```

### 2.3 对象成员

用 `{}` 表示一个匿名对象结构，内部可以继续包含数组或子对象：

```sl
data StudentRecord
{
    sid = 0
    name = ""
    profile = { grade = 3, rank = 1 }
}

data ComplexProfile
{
    profile = {
        grade = 3
        rank = 1
        contact = {
            city = "Shenzhen"
            zip = 518000
        }
        subjects = ["math", "physics"]
    }
}
```

### 2.4 嵌套 data 成员

可以把另一个 `data` 当作成员值来初始化，也支持直接写匿名 `data`：

```sl
data MetaInfo
{
    level = 1
    passed = false
}

data StudentRecord
{
    sid = 0
    name = ""
    meta = MetaInfo(){ level = 2, passed = true }
}

data A
{
    nd = {
        a = 20
        b = 30
    }
}
```

### 2.5 class / data / enum 成员

`data` 的成员值也支持具名 `class`、具名 `data`、`enum`：

```sl
class CC { va = 100 }

data A
{
    cc = CC(){ va = 200 }
}

data DA { a = 20 }
data B
{
    vb = DA(){ a = 30 }
}

enum DataKind { Base = 1, Advanced = 2 }
data C
{
    kind = DataKind.Advanced
}
```

### 2.6 组合示例

```sl
data MetaInfo
{
    level = 1
    passed = false
}

data FullStudentRecord
{
    sid = 0
    name = ""
    scores = [95, 88, 91]
    profile = {
        grade = 3
        rank = 5
        address = {
            city = "Shenzhen"
            zip = 518000
        }
    }
    awards = [
        { name = "Math", year = 2024 },
        { name = "Physics", year = 2025 }
    ]
    meta = MetaInfo(){ level = 2, passed = true }
}
```

---

## 3. 初始化方式

`data` 的初始化方式与 `class` 对象很接近，常见有三种。

### 3.1 先声明，再 `new()`

```sl
StudentRecord a = new()
a.sid = 10
a = { sid = 11, name = "next" }            # 整体重赋值
a = StudentRecord(){ sid = 12, name = "final" }
```

非 `const` 的 `data` 对象，`new()` 之后允许成员重写，也允许整体重赋值。

### 3.2 直接使用 `DataName(){ ... }`

```sl
StudentRecord b = StudentRecord(){ sid = 2, name = "n2" }
```

### 3.3 先声明，再赋值 `{ ... }`

```sl
StudentRecord d = { sid = 4, name = "n4" }
```

### 3.4 静态 data 的访问

顶层静态 `data` 的成员可直接经类型名访问与改写（非 `const` 时）：

```sl
Counter.total = 10
```

`const data` / `const` 静态 `data` 不允许上述修改行为。

---

## 4. 链式读取

`data` 支持链式读取内部成员值，包括匿名对象链、具名 `data` 链、`class` 成员链、`const data` 成员链：

```sl
city = StudentRecord.profile.address.city
level = StudentRecord.meta.level
passLine = ScoreRule.passLine
```

---

## 5. 自带系统方法

### 5.1 clone

```sl
StudentRecord sr = new(){ sid = 1 }
srClone = sr.clone()                 # 克隆，底层直接复制数据
```

### 5.2 toString() / toJson() / toJsonPretty()

```sl
StudentRecord sr = new(){ sid = 7 }
str  = sr.toString()                 # 结构化文本输出
json1 = sr.toJson()                  # 紧凑 JSON
json2 = sr.toJsonPretty()            # 缩进美化 JSON
```

`toJson()` 返回紧凑 JSON 文本；`toJsonPretty()` 返回缩进美化版。映射规则：标量映射为数值/布尔/字符串；`enum` 映射为底层的整数值；嵌套 `data` 递归展开为 `{}`；数组映射为 `[]`；`null` 成员映射为 `null`。

### 5.3 JSON 反序列化（BaseJson.toData）

已有 `BaseJson` 实例可反向还原出已定义的 `data` 实例：

```sl
BaseJson j = BaseJson.fromData(s)      # 或 BaseJson(text) 解析文本

JtSample back = j.toData<JtSample>()   # 模板实参即目标类型，返回强类型
var back2 = j.toData("JtSample")       # 显式类型名：返回 object
var nil  = j.toData("NoSuchType")      # 未知类型名 -> null
```

反向还原规则：对象节点按成员名匹配写入（标量 / string / enum 按底层值 / 嵌套 data / 数组均可还原）；JSON 中多余成员忽略；缺失成员保持 `data` 默认值。

> 说明：`object as DataName`（转换为 data 类型）当前不推荐用于强类型还原，请用 `j.toData<DataName>()`。

---

## 6. 比较与打印

两个 `data` 使用 `==` / `!=` 比较时，按"结构 + 成员数据内容"判定相等，而不是比较引用：

- 同引用优先快速判等；
- 一边匿名 `data`、另一边具名 `data`：直接不相等；
- 两边都是匿名 `data`：先比结构（成员数量），再比成员定义（名称/类型/顺序），最后比成员值（支持嵌套递归比较）；
- 两边都是具名 `data`：先类型一致，再比成员值。

```sl
data Book { name = "ok", price = 25 }
Book a = { name = "ok1" }
Book b = { name = "ok" }
Book c = new()
# a == b 为 false（内容不同）
# b == c 为 true（结构与内容相同）
```

打印 `data` 时输出包含字段名与字段值的结构化结果，而不是类型名或地址。

---

## 7. 约束

`data` 比 `class` 更强调结构，因此约束也更严格：

- `data` 不支持继承，不能使用 `extends`。
- `data` 不定义方法，通常只包含成员变量。
- `const data` 视为只读结构，不应再修改成员。

---

## 8. 与 bind 配合

`bind` 可以把一个或多个 `data` 结构绑定到 `class` / `interface` 上，详见 [bind.md](./bind.md)。如果多个被绑定的 `data` 中存在同名字段，应当在目标类型中显式消除歧义。

---

## 9. 使用技巧与注意事项

1. **数字成员默认 `int32`**：未加后缀/显式类型的数字字面量按 32 位整数处理；需要其它类型时加后缀（`L` / `f` 等）或写显式类型。
2. **匿名结构用逗号分隔字段**：匿名 `data` 的字段以逗号分隔。
3. **优先用 `toJson()` 做结构化输出**：比 `toString()` 更适合机器解析；反序列化用 `BaseJson.toData<类型>()`。
4. **`const data` 用于配置**：把一组常量配置定义为 `const data`，既集中又只读，引用时像访问普通字段。
5. **整体重赋值需非 `const`**：只有非 `const` 的 `data` 对象才允许 `a = { ... }` 这种整体重赋值。
6. **比较看内容不看引用**：`data` 的 `==` 比较内容，适合做"值相等"判断，不必逐字段比对。
