# 运算符（Operators）

> 本文是 SLang 运算符的**使用说明**：运算符一览、各运算符语义与边界、自增自减、运算符重载、索引器，以及常见坑。与其它语言习惯不同之处均已单独标注。

---

## 0) 速查：最容易踩的坑

1. **整数除法是截断除法**：`5 / 2 == 2`（向零截断），不是真除法。要得到浮点结果，至少有一个操作数是浮点（`5.0 / 2`）。`%` 取模同理。
2. **除零 / 模零不报错**：整数 `a / 0` 与 `a % 0` 结果都是 `0`（不是异常）。浮点除零得到 `Inf`/`NaN`。
3. **`&&` / `||` 不短路**：两侧操作数**都会被求值**（与 C/Java/Python 不同）。需要短路效果请改用 `if` 嵌套或 `?:`。
4. **没有 `===` / `!==`**：`===` 与 `!==` 不是合法运算符，写出来会编译报错。相等判断只用 `==` / `!=`。
5. **运算符重载必须是实例方法 + `override`，单参数（右操作数）**：不是 `static` 双参数。
6. **`++` / `--` 默认关闭**：需在工程配置里开启 `compile.isSupportDoublePlus`，且仅支持后置 `i++` / `i--`，建议直接用 `i += 1`。
7. **对象构造必须写 `new`，且运算符操作数须是已赋值变量**：创建对象必须 `new ClassName(args)`（**不能省略 `new`** 写成 `ClassName(args)`）；自定义类实例参与运算时，操作数必须是已经赋给变量的对象，**不能把 `new X() + new X()` 直接写在一行**——先构造、赋给变量，再对变量做运算。

---

## 1) 运算符一览

| 类别 | 运算符 |
|------|--------|
| 算术 | `+` `-` `*` `/` `%` |
| 一元 | `-`（负号）`!`（逻辑非）`~`（按位取反） |
| 比较 | `==` `!=` `>` `>=` `<` `<=` |
| 逻辑 | `&&` `||` （短路见 §4） |
| 位运算 | `&` `|` `^` `~` `<<` `>>` |
| 复合赋值 | `+=` `-=` `*=` `/=` `%=` `&=` `|=` `^=` `<<=` `>>=` |

> `==` 与 `!=` 对基本类型是值比较；对对象默认是引用比较（除非重载 `_eq_`，见 §9）；枚举类型只支持 `==` / `!=`。

---

## 2) 算术运算符 `+ - * / %`

```sl
int a = 1 + 2 * 3          # 7
int b = (a - 1) % 4        # 2
```

- **`/` 是截断除法**：`7 / 2` 得到 `3`（向零截断，`-7 / 2` 得到 `-3`）。若任一操作数为浮点，则按浮点除法：`7.0 / 2` 得到 `3.5`。
- **`%` 取模**：结果与左操作数同号（C 风格截断语义）；`a % 0` 结果为 `0`。
- **除零 / 模零**：整数运算结果为 `0`，**不抛异常**；浮点除零得到 `Inf` / `NaN`。
- **`+` 字符串拼接**：当一侧是字符串时执行拼接，另一侧若是基本类型会转为文本；**类实例不会自动调用 `toString()`**（拼接结果会是空串），需显式写 `.toString()`。详见 [`./string.md`](./string.md)。

```sl
int x = 7 / 2            # 3（截断）
double y = 7.0 / 2        # 3.5（浮点）
string s = "v=" + 3       # "v=3"
string t = "o=" + obj.toString()   # 类实例必须显式 toString
```

---

## 3) 比较运算符 `== != > >= < <=`

- **基本类型（数值 / bool / 枚举 / 字符串）**：`==` / `!=` 按值比较（字符串按内容逐字节比较，区分大小写）。
- **对象（默认）**：`==` / `!=` 是**引用比较**（是否同一对象），`equals()` 才是逻辑相等（见 §10）。
- **枚举**：只支持 `==` / `!=`，用 `>` / `<` 等会编译报错。
- **与 `null` 比较**：只允许 `==` / `!=`（如 `obj == null`），其它比较运算符对 `null` 报错。
- 比较运算返回 `bool`。

```sl
int a = 1, b = 1
bool e1 = (a == b)        # true（值相等）
Point p1 = new Point(1,2)
Point p2 = new Point(1,2)
bool e2 = (p1 == p2)      # false（引用不同）
bool e3 = p1.equals(p2)   # true（逻辑相等，需 Point 重写 equals）
```

---

## 4) 逻辑运算符 `&& || !`

- **`&&` / `||` 不短路**：无论左操作数结果如何，右操作数**必然被求值**。这与大多数语言不同。
- 操作数按"真值"判定：`true`、非零数值、非空字符串一般视为真；`false`、`0`、空串、`null` 视为假。
- `!` 是逻辑非，返回 `bool`。

```sl
bool r = a > 0 && b > 0    # 右半 b > 0 一定会执行（不短路）
bool n = !flag
```

> 需要"左假则跳过右侧副作用"的短路语义，请改写：
> ```sl
> bool r = false
> if a > 0
> {
>     r = b > 0
> }
> ```

---

## 5) 位运算符 `& | ^ ~ << >>`

按位运算，操作数为整数类型：

```sl
int m = 0xFF & 0x0F       # 0x0F
int o = 1 | 2             # 3
int x = 1 << 4            # 16
int inv = ~0xF            # 按位取反（结果按目标整数宽度）
```

- `~` 是按位取反（一元）。
- `<<` / `>>` 为左移 / 右移；右操作数为移位数。

---

## 6) 复合赋值 `+= -= *= /= %= &= |= ^= <<= >>=`

```sl
int a = 1
a += 2        # a = 3
a *= 3        # a = 9
a <<= 1       # a = 18
```

- 对**基本类型**全部可用，语义等价于 `a = a <op> b`。
- 对**自定义类**，`+=` / `*=` / `/=` 可以重载（对应 `_iadd_` / `_imul_` / `_itruediv_`，见 §9）；`-=` / `%=` / `&=` / `|=` / `^=` / `<<=` / `>>=` **没有**对应的重载钩子，自定义类上不能重载（基本类型上仍可用）。

---

## 7) 一元运算符 `-` `!` `~`

```sl
int a = -1            # 负号，等价于 0 - 1
int b = -a            # 1
bool c = !true        # false
int d = ~0xF          # 按位取反
```

- 一元负号 `-` 直接可用（`-1`、`x + -1` 都合法），括号仅为可读性。
- `!` 逻辑非、`~` 按位取反均为一元前缀运算符。

---

## 8) 自增 / 自减 `++` `--`

`i++` / `i--` 属于可选项：

- **默认关闭**：必须在工程 `.jsonc` 的 `compile` 段开启 `"isSupportDoublePlus": true` 才可用。
- **仅后置**：只支持 `i++` / `i--`（作为独立语句使用），不支持前置 `++i` / `--i`。
- 为避免配置依赖与解析歧义，**推荐统一用 `i += 1` / `i -= 1`** 代替。

```jsonc
// 工程 .jsonc
{
  "compile": { "isSupportDoublePlus": true }
}
```
```sl
int i = 0
i++          # 自增（需开启上述选项）；否则请用 i += 1
i--          # 自减
```

---

## 9) 运算符重载

自定义类可以通过约定方法名实现运算符重载：凡是出现 `a op b` 形式的运算，语言都会去查找左操作数类型上对应的约定方法并调用它。

> **关键规则（与旧文档不同，务必注意）**：
> - 重载方法是**实例方法**，必须带 **`override`** 标记（或 `final`），**不能写成 `static`**。
> - 只有**一个参数**（即右操作数 `b`）；左操作数是方法接收者 `this`。
> - 算术 / 逻辑类返回值类型是当前类；比较类（`_lt_` 等）返回 `bool`。
> - 参数类型可以收窄为当前类自身，也可以写 `Object`（用于支持多类型右侧，需内部 `is` 判断）。

### 方法名对照表

| 方法名 | 运算符 | 返回值 | 说明 |
|--------|--------|--------|------|
| `_add_` | `+` | 当前类 | |
| `_sub_` | `-` | 当前类 | |
| `_mul_` | `*` | 当前类 | |
| `_truediv_` | `/` | 当前类 | |
| `_mod_` | `%` | 当前类 | |
| `_iadd_` | `+=` | 当前类 | |
| `_imul_` | `*=` | 当前类 | |
| `_itruediv_` | `/=` | 当前类 | |
| `_lt_` | `<` | `bool` | |
| `_le_` | `<=` | `bool` | |
| `_gt_` | `>` | `bool` | |
| `_ge_` | `>=` | `bool` | |
| `_eq_` | `==` | `bool` | |
| `_ne_` | `!=` | `bool` | |
| `_and_` | `&&` | 当前类 | 注：重载时返回当前类实例，不是 `bool` |
| `_or_` | `\|\|` | 当前类 | 同上 |

> 位运算（`& | ^ ~ << >>`）和 `-=` / `%=` 等**没有**重载钩子，无法为自定义类重载。

### 正确写法示例

```sl
class Vector2
{
    float x
    float y

    _init_(float _x, float _y)
    {
        x = _x
        y = _y
    }

    # 重载 + ：实例方法 + override，单参数（右操作数）
    override Vector2 _add_( Vector2 other )
    {
        ret new Vector2( x + other.x, y + other.y )
    }

    # 重载 == ：返回 bool
    override bool _eq_( Vector2 other )
    {
        ret x == other.x && y == other.y
    }

    # 重载 != ：通常直接取反 _eq_
    override bool _ne_( Vector2 other )
    {
        ret !this._eq_( other )
    }

    # * 常需兼容"标量 × 向量"，把参数声明为 Object 后内部判断
    override Object _mul_( Object obj1 )
    {
        if obj1 is float f
        {
            ret new Vector2( x * f, y * f )
        }
        ret this
    }

    override string toString()
    {
        ret "(" + x + ", " + y + ")"
    }
}

var v1 = new Vector2(1.0, 2.0)
var v2 = new Vector2(3.0, 4.0)
var v3 = v1 + v2        # 调用 _add_
var eq = (v1 == v2)     # 调用 _eq_
```

> ⚠️ **对象构造与运算的写法约束**：
> - 必须用 `new` 创建对象：`new Vector2(1.0, 2.0)`，不能省略 `new` 写成 `Vector2(1.0, 2.0)`。
> - 运算符的左右操作数必须是**已赋值的变量**，不能直接对构造表达式做运算。下面这样写是**错误**的：
>   ```sl
>   var v = new Vector2(1, 2) + new Vector2(3, 4)   # ❌ 不能把 new 构造表达式直接当操作数
>   ```
>   正确写法：先构造赋给变量，再相加（如上例 `v1 + v2`）。
>
> 标准库里 `Math` 命名空间下的 `Int32_2`、`Matrix`、`Quaternion` 等数学类型就是这种写法，可参考。

---

## 10) 索引器（下标访问）`_getItem_` / `_setItem_`

通过定义 `_getItem_` 和 `_setItem_` 约定方法，自定义类型可以支持 `obj[index]` 形式的下标访问。

- `_getItem_(int index)`：返回指定位置的元素（参数类型可任意，不限于 `int`）。
- `void _setItem_(int index, T value)`：写入指定位置。

```sl
class IntArray
{
    Array<int> _data
    _init_(int capacity) { _data = new Array<int>(capacity) }

    int _getItem_(int _index)        { ret _data._getItem_(_index) }
    void _setItem_(int _index, int _value) { _data._setItem_(_index, _value) }
}

var arr = new IntArray(10)
arr[0] = 42          # 调用 _setItem_(0, 42)
var v = arr[0]       # 调用 _getItem_(0)
```

`Array<T>` 与 `List<T>` 等标准容器已实现该约定，可直接 `list[0]` / `arr[i]`。

> 注：索引器只作用于 `obj[index]` 形式；`obj.$name` 是另一套按名动态访问成员的机制，与索引器无关。

---

## 11) Object 约定方法

以下方法定义在 `Object` 根类上，所有类均继承，可用 `override` 重写：

| 方法名 | 签名 | 说明 |
|--------|------|------|
| `toString()` | `string toString()` | 返回对象文本表示；打印对象时自动调用，但 `+` 拼接**不对类实例自动调用**（见 §2） |
| `equals()` | `bool equals(object obj)` | 逻辑相等判断（区别于 `==` 的引用相等） |
| `hashCode` | `Int32 get hashCode()` | 返回对象哈希码（getter 属性） |
| `refEquals()` | `static bool refEquals(object a, object b)` | 静态引用相等比较（null 安全） |
| `type` | `Type get type()` | 获取对象运行时类型（getter 属性） |

```sl
class Point
{
    int x
    int y
    _init_(int _x, int _y) { x = _x; y = _y }

    override string toString()
    {
        ret "(" + x + ", " + y + ")"
    }
    override bool equals(object obj)
    {
        var p = obj as Point
        if p == null { ret false }
        ret x == p.x && y == p.y
    }
}

var p1 = new Point(1, 2)
Console.println(p1)              # 自动调用 toString() -> (1, 2)
Console.println(p1 == p2)        # false（引用比较，除非重载 _eq_）
Console.println(p1.equals(p2))   # true（逻辑相等）
```

---

## 12) 类型转换（as / is）

相关转换运算符在 [`./cast.md`](./cast.md) 专门说明：

- `obj as Type`：类型转换，不匹配返回 `null`。
- `obj is Type` / `obj isnot Type`：类型判断。

```sl
var p = obj as Point
if p != null { ... }
```

---

## 13) 综合示例

```sl
# 算术：整数截断除法 + 浮点除法
int q = 7 / 2            # 3
double f = 7.0 / 2       # 3.5
int m = 7 % 3            # 1
int z = 5 / 0            # 0（除零不报错）

# 比较 / 逻辑（不短路）
bool b = (a == 1) && (c > 2)    # 右半一定执行

# 位运算
int mask = (1 << 3) | (1 << 1)  # 10

# 复合赋值
count += 1
count *= 2

# 自定义类运算符重载（实例方法 + override）
# 注意：先构造并赋给变量，再对变量做运算（不能直接 new X() + new X()）
var v1 = new Vector2(1, 2)
var v2 = new Vector2(3, 4)
var vc = v1 + v2   # _add_

# 索引器
arr[0] = 10

# 真值输出：类实例需显式 toString
Console.println("p=" + p.toString())
```

---

## 14) 相关文档

- 语法：[`./cast.md`](./cast.md)（`as` / `is` / `isnot`）、[`./string.md`](./string.md)（字符串拼接与 `toString` 行为）、[`./if.md`](./if.md)（条件真值）
- 库：[`../lib/Core/`](../lib/Core/) 下的数学/容器文档（运算符重载范例见 `Math` 命名空间下的 `Int32_2` / `Matrix` / `Quaternion` 等类型）
