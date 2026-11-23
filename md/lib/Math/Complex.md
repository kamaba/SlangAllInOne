# 复数（Complex64 / Complex32 / MathComplex）

> 归属：Math 库。使用前 `import Math;`。

SLang 提供两个复数类型与一个静态工具门面：

| 类型 | 精度 | 说明 |
|------|------|------|
| `Complex64` | 双精度（Float64） | 默认推荐；全功能 |
| `Complex32` | 单精度（Float32） | 性能/内存优先；可转 `Complex64` |
| `MathComplex` | 静态工具 | 复数静态函数（构造/四则/超越函数） |

`Complex64` 另有别名 `Complex`、`Complex128`；`Complex32` 别名 `C32`。

---

## 1. 规则说明

- 复数内部由 `real`（实部）与 `imag`（虚部）两个浮点分量表示，`z[0]`=实部、`z[1]`=虚部。
- 支持 `+ - * /` 四则、`==` `!=` 比较；复数可与同类型复数运算，也可与标量（`Float64`/`Int32`，`Complex32` 对应 `Float32`/`Int32`）相乘或相除。
- 所有运算方法返回复数类型自身，可链式使用。
- 除法按标准公式 `(a+bi)/(c+di) = ((ac+bd) + (bc-ad)i)/(c²+d²)`；分母为零时结果未定义（使用者需自行保证分母非零）。
- 底层数学函数经原生库加速，**绑定不可用时自动回退到纯语言实现**，两条路径结果一致，无需关心运行环境中是否有原生库。

---

## 2. 使用用例

```slang
import Math;

# 构造与基本运算
Complex64 a = Complex64( 3.0d, 4.0d )   # 3 + 4i
Complex64 b = Complex64( 1.0d, 2.0d )   # 1 + 2i
Complex64 sum = a + b                    # 4 + 6i
Complex64 prod = a * b                   # -5 + 10i
Complex64 quo = a / b                    # 2.2 - 0.4i
Complex64 scaled = a * 2.0d              # 6 + 8i

# 模、共轭、幅角
Float64 m = a.abs()                      # 5.0
Complex64 c = a.conjugate()              # 3 - 4i
Float64 ang = a.arg()                    # atan2(4,3)

# 欧拉公式：e^(iθ) = cosθ + i·sinθ
Complex64 euler = Complex64.expi( Mathd.Pi / 2.0d )   # ≈ 0 + 1i
Complex64 fromExp = Complex64( 0.0d, Mathd.Pi / 2.0d ).exp()
Float64 r = Complex64.fromPolar( 2.0d, 0.0d ).real    # 2.0

# 超越函数
Complex64 z = Complex64( 0.0d, 4.0d ).sqrt()          # ≈ 1.414 + 1.414i
Complex64 l = Complex64.one().log()                   # 0 + 0i

# 单精度 + 静态门面
Complex32 c32 = Complex32( 3.0f, 4.0f )
Float64 m64 = c32.toComplex64().abs()
Complex64 viaFacade = MathComplex.mul( a, b )         # 同 a*b
Complex64 pw = MathComplex.powInt( a, 3 )             # a 的 3 次幂
```

---

## 3. 可用方法与签名

### `Complex64`（`real`/`imag`: Float64）

| 类别 | 签名 |
|------|------|
| 构造 | `_init_()` / `_init_(Float64 real, Float64 imag)` / `_init_(Float64 real)` |
| 索引 | `[0]`=实部、`[1]`=虚部（可读可写） |
| 运算符 | `+ - * /`（复数、标量）、`== !=` |
| 模/幅角 | `Float64 abs()` / `Float64 arg()` |
| 变换 | `Complex64 conjugate()` / `Complex64 negate()` / `Complex64 scale(Float64 s)` / `Complex64 clone()` |
| 超越 | `Complex64 exp()` / `Complex64 sqrt()` / `Complex64 log()` |
| 静态常量 | `Complex64.zero` / `Complex64.one` / `Complex64.i` |
| 静态工具 | `Complex64 fromPolar(Float64 r, Float64 theta)` / `Complex64 expi(Float64 theta)` |
| 格式化 | `string toString()`（形如 `(3 + 4i)`） |

### `Complex32`（`real`/`imag`: Float32）

方法与 `Complex64` 对称，标量为 Float32；额外提供 `Complex64 toComplex64()`。静态常量 `zero/one/i`，静态工具 `fromPolar/expi`。

### `MathComplex`（静态门面，Float64）

| 签名 | 说明 |
|------|------|
| `Complex64 fromCartesian(Float64 real, Float64 imag)` | 由实部虚部构造 |
| `Complex64 fromPolar(Float64 r, Float64 theta)` | 由极坐标构造 |
| `Complex64 expi(Float64 theta)` | 欧拉公式 e^(iθ) |
| `Float64 real(Complex64 z)` / `Float64 imag(Complex64 z)` | 取分量 |
| `Float64 abs(Complex64 z)` / `Float64 arg(Complex64 z)` / `Float64 norm(Complex64 z)` | 模/幅角/模平方 |
| `Complex64 conjugate(Complex64 z)` | 共轭 |
| `Complex64 add/sub/mul/div(Complex64 a, Complex64 b)` | 四则 |
| `Complex64 exp/sqrt/log(Complex64 z)` | 超越函数 |
| `Complex64 sin(Complex64 z)` / `Complex64 cos(Complex64 z)` | 复变三角 |
| `Complex64 powInt(Complex64 z, Int32 n)` | 整数次幂（n≥0） |

---

## 4. 使用技巧与已知限制

- **标量乘除的类型**：`Complex64` 接受 `Float64` 和 `Int32` 标量；写整数字面量时注意用 `2.0d` 更稳妥，避免与整数重载混淆。
- **比较是精确相等**：`==`/`!=` 逐分量精确比较。浮点计算结果如需容差，用 `Mathd` 的绝对值差自行判断（库未提供近似比较）。
- **内联构造物的运算符**：在个别解析场景下，把「新建复数」直接作为 `==`/`!=` 的操作数可能不被支持；先赋给局部变量再比较即可（如用例中 `same`/`other` 写法）。这不影响 `+ - * /`。
- **标量零除**：`a / Complex64.zero()` 的结果未定义；除前请确认分母非零。
- **极坐标分支**：`arg()` 返回 `(-π, π]`；`sqrt()` 取主支（实部非负）。
- **精度选择**：量子态幅度、需要双精度累积的场景用 `Complex64`；大量元素、内存敏感且可接受单精度误差时用 `Complex32`，需要双精度结果时 `toComplex64()` 转换。
