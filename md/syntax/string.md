# 字符串（string / String）

> 本文是 `string` 的**使用说明**：字面量写法、字符串插值、`String` 的可用方法、运算符规则，以及常见限制与替代方案。凡与其它语言习惯不同之处均已单独标注。

---

## 0) 速查：三条最容易踩的规则

1. **`string` 是 UTF-8 字节串，不是 Unicode 字符序列**。`length`、`front`、`end`、`slice`、`SystemStringCharCodeAt`、`toUInt8Array` 全部按**字节**计数与索引，所以 `"中文".length == 6`。
2. **`String` 只有 8 个方法/属性**（`format` / `toFormat` / `length` / `toString` / `front` / `end` / `slice` / `toUInt8Array`，另有 3 个构造重载）。没有 `toUpperCase`、`trim`、`indexOf`、`substring`、`replace`、`split`、`charAt`、`startsWith` —— 替代方案见 §8。
3. **插值 `$name` / `${expr}` 与 `format("{0}")` 是两套独立机制**：前者等价于字符串 `+` 拼接，后者是占位符替换；同一字符串里可以叠加使用。

---

## 1) 类型规则

| 项 | 规则 |
|----|------|
| 类型名 | `String`，关键字别名 `string`（见 [`./type.md`](./type.md)）；引用 Core 后直接可用，无需 import |
| 编码与单位 | UTF-8；**所有长度、索引、切片都按字节**计算 |
| `char` 类型 | **不存在**。单引号 `'a'` 仍是长度为 1 的 `string`，见 §2.2 |
| 可变性 | **不可变**。每次 `+` 都产生新字符串；循环拼接开销较大，量大时用 `Text.StringBuilder`（§9） |
| 内嵌 NUL | `\0` 会截断字符串内容；二进制数据请用 `toUInt8Array()` / `ByteBuffer` |
| 下标与遍历 | 不支持 `s[i]`，也不支持 `for ... in` 遍历字符串；按字节访问见 §6 |
| 类型判断 | `is string` / `as string` 见 [`./cast.md`](./cast.md) |

---

## 2) 字面量：四种形式

### 2.1 双引号 `"..."`（主力形式）

```sl
string a = "hello"
string b = "a\tb\n\u4E2D"
```

支持的转义序列：

| 转义 | 结果 | 转义 | 结果 |
|------|------|------|------|
| `\'` | `'` | `\"` | `"` |
| `\\` | `\` | `\$` | `$`（避免触发插值） |
| `\{` / `\}` | `{` / `}` | `\/` | `/` |
| `\a` `\b` `\f` `\v` | 响铃 / 退格 / 换页 / 垂直制表 | `\n` `\r` `\t` | 换行 / 回车 / 制表 |
| `\0` | NUL 字符 | `\uXXXX` | 4 位十六进制 → 对应字符 |

注意：

- **未知转义会被丢弃**：反斜杠和它后面的字符都不会进入结果，例如 `"\q"` 得到的是空串。请只使用上表列出的转义。
- **正则模式不要用双引号写 `\s` / `\d` 等**：反斜杠会被吞掉，`",\s*"` 实际得到 `",s*"`。写正则请用单引号原始串 `',\s*'`，或用 `"\u005C"` 表示反斜杠。
- 字符串内出现**裸换行**会报错；需要多行请改用 `f"""..."""`。
- 普通 `{` / `{0}` / `{}` 只是字面文本，只有调用 `format` 时才会被当作占位符解释，见 §5。
- `$` 在双引号串内会触发插值，见 §3。

### 2.2 单引号 `'...'`（原始串，仍是 `string`）

```sl
string c = 'a'
string j = '{"name":"okr","age":13}'
string q = 'Name:\'$name\''
```

规则：

- **只有 `\'` 被转义**；其它 `\x` 原样保留为「反斜杠 + 字符」两个字符，所以 `'\n'` 是字面 `\` `n`，不是换行。
- 字符串里直接换行时，回车 / 换行会归一为字面 `\n` 文本（同样是两字符）。
- **不做 `$` 插值**：`'$name'`、`'${expr}'` 都是原样文本。插值只对双引号系列生效。
- 适合写含大量 `"` 的 JSON / XML 片段，以及需要保留反斜杠的正则表达式。

### 2.3 三引号 `f"""..."""`（多行 f 串）

```sl
str6 = f"""我是一段话 我叫${name}
        第二行 "双引号可直接写" \$name 不插值
        End"""
```

| 项 | 规则 |
|----|------|
| 前缀 | **只识别 `f"""`**。`f"..."`（非三引号）不是 f 串，`f'''...'''` 不支持 |
| 结束 | 以连续三个 `"""` 结束；**单个 `"` 是字面字符** |
| 换行 | 保留**真实换行符**，直接敲回车即可 |
| 插值 | **仅 `${表达式}`**；`$变量` 简写按普通文本原样输出 |
| 转义 | 仅 `\\`、`\"`、`\'`、`\$`、`\{`、`\}`、`\uXXXX`；`\n` / `\t` / `\r` 等会**保留为字面反斜杠 + 字符** |
| 普通 `{...}` | 字面文本，同 §2.1 |

> 注意：在 `f"""` 里写 `\n` **不会换行**，要真换行就直接敲回车。这与双引号串正好相反。

### 2.4 `$"..."` 前缀

- `$"..."` 的值与普通 `"..."` 等价；**插值是否发生仍由串内的 `$name` / `${expr}` 决定，不是由这个 `$` 前缀开启**。
- `$"xxx"` 也常用于**按名访问成员**，如 `obj.$"field"`。
- 日常统一用普通双引号 + `$name` / `${expr}` 即可。

---

## 3) 字符串插值 `$`

### 3.1 三种形式（仅双引号 / `$"..."` 支持）

```sl
name = "QuTa"
score = 55
a = 100
b = 300
ct = ClassT(){ name = "mmm" }

s1 = "Name:$name"                       # $变量
s2 = "Name:$ct.name"                    # $对象.成员
s3 = "sum=${ a + b }"                   # ${表达式}：运算、函数调用、链式调用
s4 = "v=$a s=${(a + b).toString()}"     # 混用
```

| 形式 | 说明 | 结束条件 |
|------|------|----------|
| `$name` | 变量插值，读到空格或引号为止 | 空格 / `"` / 串尾 |
| `$obj.member` | 对象成员插值，`.` 属于名称链的一部分 | 同上 |
| `${expr}` | 表达式插值，花括号可嵌套 | 配平的 `}` |
| `$` + 其它 | 按字面 `$` + 字符保留；`\$` 可显式转义为字面 `$` | — |

> **`$v.toString()` 这类带函数调用或运算的写法请写成 `${v.toString()}`**：`$name` 简写以空格/引号为界，遇到括号容易把整段误当成名称。
>
> **`$name` 后紧跟的空格可能被吞掉**：若需精确保留空格，写成 `${name}`、把插值放在串尾，或改用 `+` / `format` 拼接。

### 3.2 插值等价于 `+` 拼接，不是 `format`

```sl
"sum=${ a + b }"          # 等价于 "sum=" + (a + b)
"Name:${name}!"           # 等价于 "Name:" + name + "!"
```

由此带来几条实际影响：

- 插值中的值按 §7 的 `+` 拼接规则转文本：`null` → `""`、bool → `"True"` / `"False"`。
- 插值**不处理** `{}` / `{0}` 占位符，那是 `format` 的职责。
- 两者可以叠加：先完成插值，再由 `format` 填空位。

```sl
"{} Name:${ct.name} {} Score:${score} a+b=${(a + b).toString()} bb = {}".format(name, score, "bb")
```

- f 三引号的 `${expr}` 同样按拼接处理。

语法糖简表另见 [`./keywords.md`](./keywords.md) 与 [`./introduction.md`](./introduction.md)。

---

## 4) `String` 成员方法全表

下表即 `String` 的**全部**成员，没有其它隐藏方法。

| 成员 | 签名 | 说明 |
|------|------|------|
| `_init_(Int8)` | `_init_(Int8 aa)` | 数值文本化后构造 |
| `_init_(Int32)` | `_init_(Int32 aa)` | 同上 |
| `_init_(String)` | `_init_(String aa)` | 直接取传入串 |
| `format` | `string format(params object[] _parmas)` | `{}` / `{N}` 占位符替换，详见 §5 |
| `length` | `get int length()` | **UTF-8 字节数**；`null` → `0`。getter 属性，`s.length` 与 `s.length()` 两种写法均可 |
| `toString` | `String toString()` | 返回自身 |
| `toFormat` | `static string toFormat(string _format, params object[] _parmas)` | 静态版 `format`，以 `_format` 为格式串 |
| `front` | `string front(int index)` | 取**前 n 字节**；`n <= 0` / 空串 / null → `""`；`n > 长度` → 整串 |
| `end` | `string end(int index)` | 取**后 n 字节**；边界同上 |
| `slice` | `string slice(int start, int end)` | 半开区间 `[start, end)`，越界自动钳制，见 §4.1 |
| `toUInt8Array` | `UInt8Array toUInt8Array()` | 返回逐字节拷贝的 `UInt8Array`；null → 空数组 |

> `front` / `end` 的「字符」说法不准确，**单位始终是字节**。方法名是 `slice` 而不是 `range`，因为 `range` 是语言里的区间构造糖（见 [`./range.md`](./range.md)）。

### 4.1 边界行为

设 `s = "abc"`：

| 调用 | 结果 |
|------|------|
| `s.length` | `3` |
| `"中文".length` | `6`（每个汉字 3 字节） |
| `s.front(0)` / `s.front(-1)` | `""` |
| `s.front(99)` | `"abc"` |
| `s.end(2)` | `"bc"` |
| `s.slice(1, 3)` | `"bc"` |
| `s.slice(-3, 999)` | `"abc"`（起点钳到 0，终点钳到长度） |
| `s.slice(5, 2)` | `""`（起点钳到长度，终点小于起点时再钳到起点） |
| `s.slice(2, 2)` | `""` |
| `s.toUInt8Array()` | `[97, 98, 99]` |

```sl
# 中文必须按 3 字节边界切，否则会得到不完整的 UTF-8 字节序列
string cn = "中文"
cn.front(3)        # "中"
cn.end(3)          # "文"
cn.slice(0, 3)     # "中"
cn.front(1)        # 只有第 1 个字节，不是合法 UTF-8 字符
```

---

## 5) `format` / `toFormat` 规则

### 5.1 占位符

| 写法 | 含义 |
|------|------|
| `{0}` `{1}` … | 索引式，取第 `N+1` 个实参 |
| `{}` | 自增式，从 0 起依次取；自增序号**只由 `{}` 推进**，`{N}` 不影响它 |
| `{N:格式符}` | **不支持**，会被当作非数字占位符原样保留 |
| 普通 `{...}` | 未调用 `format` 时只是字面文本 |

**未匹配的占位符原样保留**：越界索引、非数字内容、没有对应实参的 `{}`、缺少右 `}` 的片段，都会把 `{原文本}` 写回结果。

```sl
"{0} this is {1} that a {2}".format("mum", "skirt", "big")  # "mum this is skirt that a big"
"{} + {} = {0}".format(1, 2)                                 # "1 + 2 = 1"
"{9}".format(1)                                              # "{9}"（越界保留）
"{abc}".format(1)                                            # "{abc}"（非数字保留）
String.toFormat("{0}-{1}", 3, 4)                             # "3-4"
"x={} y={}".format(7, "z")                                   # "x=7 y=z"
```

### 5.2 值 → 文本

| 值 | 输出 |
|----|------|
| `null` | `""` |
| `bool` | `true` / `false`（**小写**） |
| `Int8` … `UInt64` | 十进制整数文本 |
| `Float8` / `Float16` / `Float32` / `Float64` / `Num` | 最短十进制表示，如 `4.0` → `"4"` |
| `string` | 原内容 |
| `params object[]` 元素 | 数组按元素**展开**后逐个转文本 |
| 类实例 / 嵌套数组 | `""`（不会自动调用 `toString`） |

缺少格式串时返回空串。

> 自定义对象参与 `format` 前请显式 `.toString()`；`+` 拼接同理（§7）。

---

## 6) 可直接调用的字符串系统函数

除成员方法外，下列函数可在 SL 代码里直接调用。它们与 §4 的成员方法是同一批能力，但**没有 `String` 成员包装**，适合做字节级处理。

| 函数 | 签名 | 行为 |
|------|------|------|
| `SystemStringCharCodeAt` | `Int32 (string, Int32)` | 取指定位置的 UTF-8 字节（0..255）；越界 / 空串 / null → `-1` |
| `SystemStringLength` | `Int32 (string)` | UTF-8 字节数；null → `0` |
| `SystemStringFront` | `string (string, Int32)` | 同 `front` |
| `SystemStringEnd` | `string (string, Int32)` | 同 `end` |
| `SystemStringRange` | `string (string, Int32, Int32)` | 同 `slice` |
| `SystemStringToUInt8Array` | `UInt8Array (string)` | 同 `toUInt8Array` |
| `SystemStringFormat` | `string (string, Array<object>)` | 同 `format` |

按字节遍历（因为没有 `s[i]` 下标）：

```sl
Int32 i = 0
while i < SystemStringLength(s)
{
    Int32 c = SystemStringCharCodeAt(s, i)   # 0..255；越界返回 -1
    i++
}
```

其它与字符串相关的常用函数：

| 函数 | 用途 |
|------|------|
| `SystemConvertString` | 任意基元值转串；`null` → `""`，bool → 小写 `true/false` |
| `SystemInt32Parse` | 把十进制字符串解析为 `Int32` |
| `SystemConvertInt32ToRadixString` | 把整数按 2..36 进制转成字符串 |
| `SystemArrayToString` | 数组文本化 |
| `SystemBuildDataString` | Data / TypeObject 的 JSON 风格文本 |
| `SystemReadLine` / `SystemInput` / `SystemConsoleReadKey` | 返回字符串的输入函数 |

> 正则相关能力属于 `Text.RegExp`（§9），不是 `String` 的成员。

系统方法的通用说明见 [`./system_method.md`](./system_method.md)。

---

## 7) 运算符、比较与转换规则

### 7.1 `+` 拼接

- **任一侧是字符串即执行拼接**，非字符串一侧先转成文本。
- `null` 参与拼接时视为 `""`。
- 每次拼接产生新字符串，循环拼接是 O(n²)；大量拼接请用 `Text.StringBuilder`。
- 类实例**不会自动调用 `toString()`**，拼接结果会是空串。`operator.md` 中「`+` 自动调用 toString」是对象约定层的描述，实际请显式写 `.toString()`。

```sl
"aaacc" + "deee"                 # "aaaccdeee"
'{"name":"okr","age":13}' + 3    # '{"name":"okr","age":13}3'
'a' + 'b'                        # "ab"
"v=" + null                      # "v="
"c1.a1 = " + c1.a1.toString()    # 自定义对象必须显式转
```

### 7.2 `==` / `!=`

- 两侧均为字符串时**按内容比较**（区分大小写、按字节），不是引用比较。
- 字符串与数值 / bool 等混合类型比较恒为 `false`。
- **不支持字典序 `<` / `>` 比较**；需要排序请自行实现字节序比较。
- 非空串为真值；但 `if s` 这类条件写法在 [`./if.md`](./if.md) 中标注为部分实现，建议显式写 `s != ""`。

### 7.3 bool 文本化大小写不一致（已知差异）

| 场景 | `true` 的输出 |
|------|--------------|
| `format` / `toFormat` | `true` |
| `SystemConvertString` | `true` |
| `+` 拼接（非字符串一侧） | `True` |

```sl
"{0}".format(true)   # "true"
"" + true            # "True"
```

做字符串断言或协议输出时统一走 `.toString()` 或 `format`，避免混用。

### 7.4 其它

- **类型转换**：`SystemConvertString`（基元 → 串）、`SystemInt32Parse`（串 → 整数）；数值转换函数会把字符串按十进制解析，详见 [`./system_method.md`](./system_method.md)。
- **按字节访问**：用 `SystemStringCharCodeAt(s, i)` 或 `s.toUInt8Array()` 后遍历。
- **编码**：`Utf8Codec` 提供 UTF-8 字节与字符串之间的转换，见 §9。
- **switch**：`case` 支持多值常量，但仅 number / string / bool 三类（[`./switch.md`](./switch.md)）。

---

## 8) 不存在的 API 与替代方案

| 需求 | `String` 上没有 | 替代方案 |
|------|----------------|----------|
| 大小写转换 | `toUpperCase` / `toLowerCase` | 自行按字节映射（仅 ASCII 安全） |
| 去空白 | `trim` / `trimStart` / `trimEnd` | 配合 `slice` 与字节扫描自行实现 |
| 查找 | `indexOf` / `lastIndexOf` / `contains` | `SystemStringLength` + `SystemStringCharCodeAt` 逐字节扫描，或用 `Text.RegExp.search` |
| 替换 / 切分 | `replace` / `split` | `Text.RegExp.replace(...)` / `Text.RegExp.split(...)` |
| 前后缀 | `startsWith` / `endsWith` | `front(n) == sub` / `end(n) == sub`，或字节扫描 |
| 取字符 | `charAt` | `SystemStringCharCodeAt(s, i)`（返回 UTF-8 字节 0..255） |
| 子串 | `substring(start, length)` | `slice(start, start + length)`（注意第二参数是**结束下标**不是长度） |
| 下标 / 迭代 | `s[i]` / `for ch in s` | `toUInt8Array()` 后遍历，或 `SystemStringCharCodeAt` 循环 |
| Unicode 字符数 | `length` 是字节数 | 自行按 UTF-8 前导字节统计码点数 |
| 数值格式化 | `{N:格式符}` / 对齐 / 精度 | `format` 只支持 `{}` / `{N}`；数值用各类型的 `toString(string format)` 或 `SystemConvertInt32ToRadixString` |
| 插值简写 | `$v.method()` | 写 `${v.method()}` |
| 单引号 f 串 | `f'''...'''` | 只支持 `f"""` |

---

## 9) 相关字符串设施

| 设施 | 说明 |
|------|------|
| `Text.StringBuilder` | **可变**字符串构建器：`append` / `appendFormat` / `appendLine` / `length`（字节数）/ `toUInt8Array` / `clear` / `release`；仅支持尾部追加，没有 insert/replace/delete/reverse。详见 [`../lib/Core/Text/StringBuilder.md`](../lib/Core/Text/StringBuilder.md) |
| `Text.RegExp` | 正则 `replace` / `split` / `search`，是字符串替换与切分的主要手段 |
| `Utf8Codec` | UTF-8 字节与字符串互转 |
| `ByteBuffer` / `Json` / `Xml` / `Yaml` / `Toml` | 各自提供文本出入口，用于二进制与序列化场景 |
| `String` API 速查 | [`../lib/Core/String.md`](../lib/Core/String.md) |

---

## 10) 综合示例

```sl
# 字面量
string dq = "a\tb\n\u4E2D"
string sq = '{"name":"okr","age":13}'
string fs = f"""第一行 ${1 + 1}
第二行 \$name 原样输出"""

# 插值；用 ${} 形式可确保后面的空格不被吞
string name = "QuTa"
int score = 55
string msg = "Name:${name} Score:${score} sum=${(1 + 2).toString()}"

# format（占位符）
string fmt = "{0} this is {1} that a {2}".format("mum", "skirt", "big")
string auto = "{} + {} = {0}".format(1, 2)          # "1 + 2 = 1"

# 字节语义与边界
string cn = "中文"
int n = cn.length                                   # 6
UInt8Array bytes = cn.toUInt8Array()                # 长度 6，bytes[0] == 228
string head = cn.front(3)                           # "中"
string tail = cn.end(3)                             # "文"
string mid = cn.slice(0, 3)                         # "中"
Int32 code = SystemStringCharCodeAt(cn, 0)          # 228；越界返回 -1

# 拼接与比较
string joined = "v=" + 3                            # "v=3"
bool same = (cn == "中文")                          # true（按内容比较）
string withObj = "obj=" + obj.toString()            # 自定义对象必须显式 toString

# 替代不存在的方法（正则里的 \s 用单引号原始串，避免双引号吞反斜杠）
var re = Text.RegExp(',\s*')
var parts = re.split("a, b ,c")                     # 替代 String.split
```

---

## 11) 相关文档

- 语法：[`./keywords.md`](./keywords.md)（`$` 插值糖）、[`./introduction.md`](./introduction.md)、[`./type.md`](./type.md)、[`./cast.md`](./cast.md)、[`./operator.md`](./operator.md)、[`./system_method.md`](./system_method.md)、[`./switch.md`](./switch.md)、[`./range.md`](./range.md)、[`./if.md`](./if.md)、[`./data.md`](./data.md)
- 库：[`../lib/Core/String.md`](../lib/Core/String.md)、[`../lib/Core/Text/StringBuilder.md`](../lib/Core/Text/StringBuilder.md)
