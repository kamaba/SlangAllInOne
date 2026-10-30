# Matrix.sl

> 源文件：`Matrix.sl`

## class `Matrix`

- **说明**：SLang 标准库类型 Matrix（详见源文件）。

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `Array&lt;Float32&gt; _data = null` | 行主序存储：_data[row * cols + col] |
| 字段 | `public Int32 rows = 0` | 字段 Int32（类型见签名）。 |
| 字段 | `public Int32 cols = 0` | 字段 Int32（类型见签名）。 |
| 方法 | `void _init_(Int32 _rows, Int32 _cols)` | ── 构造 ───────────────────────────────────────────── |
| 方法 | `void _init_(Int32 _rows, Int32 _cols, Array&lt;Float32&gt; values)` | 执行 _init_(_rows, _cols, values)，行为详见源实现。 |
| 方法 | `Float32 _getItem_(int index)` | ── 索引访问 ───────────────────────────────────────── |
| 方法 | `void _setItem_(int index, Float32 value)` | 执行 _setItem_(index, value)，行为详见源实现。 |
| 方法 | `Float32 getValue(int row, int col)` | 执行 getValue(row, col)，行为详见源实现。 |
| 方法 | `void setValue(int row, int col, Float32 value)` | 执行 setValue(row, col, value)，行为详见源实现。 |
| 方法 | `Int32 count()` | 执行 count()。 |
| 方法 | `bool isSquare()` | 判断状态是否（isSquare）。 |
| 方法 | `Matrix _add_(Matrix b)` | ── 运算符重载 ─────────────────────────────────────── |
| 方法 | `Matrix _sub_(Matrix b)` | 执行 _sub_(b)，行为详见源实现。 |
| 方法 | `Matrix _mul_(Object obj1)` | 执行 _mul_(obj1)，行为详见源实现。 |
| 方法 | `bool _eq_(Matrix b)` | 执行 _eq_(b)，行为详见源实现。 |
| 方法 | `bool _ne_(Matrix b)` | 执行 _ne_(b)，行为详见源实现。 |
| 方法 | `Matrix transpose()` | ── 矩阵运算 ───────────────────────────────────────── |
| 方法 | `Matrix clone()` | 克隆 / 复制（clone）。 |
| 方法 | `Matrix minorMatrix(int row, int col)` | 方阵：取子式（去掉 row / col） |
| 方法 | `Float32 determinant()` | 方阵行列式（递归展开，仅适合小规模） |
| 方法 | `bool isInvertible()` | 判断状态是否（isInvertible）。 |
| 方法 | `Matrix identity(Int32 n)` | ── 静态工厂 ───────────────────────────────────────── |
| 方法 | `Matrix zero(Int32 rows, Int32 cols)` | 执行 zero(rows, cols)，行为详见源实现。 |
| 方法 | `string toString()` | 转换为 Stringundefined 类型（toString）。 |
