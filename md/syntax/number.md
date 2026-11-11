# 数字（Number / Num）

SLang 提供固定的数值类型（`int` / `long` / `float` / `double` / `decimal`）以及一个万能数字类型 `Num`，用于在不同数值形态之间灵活转换。

## 1. 字面量

```sl
var a = 42            # 十进制 int
var b = 0x1F          # 十六进制
var c = 0b1010        # 二进制
var d = 1_000_000     # 下划线分隔，提升可读性
var e = 1.5e3         # 科学计数法（= 1500.0）

var i = 100i          # 显式 int
var l = 100l          # 显式 long
var f = 1.5f          # 显式 float
var db = 1.5d         # 显式 double
var m = 3.14m         # 显式 decimal（高精度）
```

- 后缀：`i`=int、`l`=long、`f`=float、`d`=double、`m`=decimal。
- 不带后缀时：整数默认 `int`，小数默认 `double`。
- 十六进制以 `0x` 开头，二进制以 `0b` 开头；数字中间可用 `_` 分隔。

## 2. 固定数值类型

| 类型 | 位数 | 典型用途 |
|------|------|----------|
| `int` | 32 | 默认整数、计数、索引 |
| `long` | 64 | 大整数 |
| `float` | 32 | 单精度浮点 |
| `double` | 64 | 双精度浮点（默认小数） |
| `decimal` | 128 | 金融 / 高精度十进制运算 |

```sl
int x = 10
long big = 10000000000l
float f = 3.14f
double d = 3.14159265358979
decimal money = 9.99m

Console.println(x + big)        # int 与 long 运算，结果自动提升为 long
Console.println(f + d)          # float 与 double 运算，结果提升为 double
```

> 运算时，参与运算的两个数会按「更宽」的类型统一：`int + long -> long`，`float + double -> double`。

## 3. 万能类型 Num

`Num` 能在 `int` / `long` / `float` / `double` / `decimal` 之间自动转换，适合「来源不确定、需要统一处理」的场景（如配置文件、动态解析）。

```sl
Num n = 10          # 当前是 int 形态
n = 3.14           # 切换到 double 形态
n = 10000000000l   # 切换到 long 形态

int i = n as int           # 显式取出 int 形态
double d = n as double     # 显式取出 double 形态
long l = n.ToInt64()       # 方法形式转换
```

常用成员：

- 类型判断：`IsInt()` / `IsLong()` / `IsFloat()` / `IsDouble()` / `IsDecimal()`
- 转换取出：`ToInt32()` / `ToInt64()` / `ToSingle()` / `ToDouble()` / `ToDecimal()`
- 查询当前形态：`GetNumberType()`

```sl
Num n = readUserInput()     # 来源不确定
if (n is int)
{
    int v = n.toInt32()
    Console.println("整数：" + v)
}
else
{
    double v = n.toFloat64()
    Console.println("小数：" + v)
}
```

## 4. 运算与比较

```sl
int a = 10
int b = 3
Console.println(a + b)     # 13
Console.println(a - b)     # 7
Console.println(a * b)     # 30
Console.println(a / b)     # 3（整数除法，向零截断）
Console.println(a % b)     # 1

Console.println(a == b)    # false
Console.println(a > b)     # true
Console.println(a <= b)    # false
```

- 加减乘除取模：`+` `-` `*` `/` `%`。
- 比较：`==` `!=` `<` `>` `<=` `>=`。
- 整数除法会**截断为整数**；需要小数结果时，先把操作数转成 `double` / `float`。

## 5. 注意事项

- **整数除法截断**：`10 / 3` 得到 `3` 而非 `3.333`。要保留小数，使用 `10d / 3` 或先把变量声明为浮点类型。
- **浮点误差**：`float` / `double` 不适合金额等需要精确相等的场景，改用 `decimal`。
- **除零**：除以 `0` 会抛出异常，运算前请先判断除数。
- **常量折叠**：编译期能确定的常量表达式会在编译阶段求值。
- **类型推导**：用 `var` 声明时，整数推导出 `int`、小数推导出 `double`；需要其它类型请写显式后缀或类型标注。
- **格式化输出**：数值类型支持 `.ToString("F2")` 之类的格式串（具体格式符见字符串 / 标准库文档）。
- **范围限制**：`int` 约 ±21 亿、`long` 约 ±9.2×10¹⁸；超过范围请改用 `long` / `decimal`。
