# Float64_3x3.sl

> 源文件：`Float64_3x3.sl`

## class `Float64_3x3`

- **说明**：SLang 标准库类型 Float64_3x3（详见源文件）。

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `public Float64 m00 = 0.0d` | 元素直接以字段存储（m{row}{col}，行主序），避免数组寻址开销； 高消耗运算（乘/加/转置/行列式/求逆/变换/工厂）下沉 cvm： SystemMathMat3d*（systemCalls -&gt; math_lib.dll 的 mathvm_mat3d_*）， C 侧直接按 member_data 读写字段内存；结果经 out 参数写回 |
| 字段 | `public Float64 m01 = 0.0d` | 字段 Float64（类型见签名）。 |
| 字段 | `public Float64 m02 = 0.0d` | 字段 Float64（类型见签名）。 |
| 字段 | `public Float64 m10 = 0.0d` | 字段 Float64（类型见签名）。 |
| 字段 | `public Float64 m11 = 0.0d` | 字段 Float64（类型见签名）。 |
| 字段 | `public Float64 m12 = 0.0d` | 字段 Float64（类型见签名）。 |
| 字段 | `public Float64 m20 = 0.0d` | 字段 Float64（类型见签名）。 |
| 字段 | `public Float64 m21 = 0.0d` | 字段 Float64（类型见签名）。 |
| 字段 | `public Float64 m22 = 0.0d` | 字段 Float64（类型见签名）。 |
| 方法 | `void _init_()` | ── 构造 ───────────────────────────────────────────── |
| 方法 | `void _init_(Array&lt;Float64&gt; values)` | 执行 _init_(values)，行为详见源实现。 |
| 方法 | `void _init_(Float32_3x3 m)` | 由 Float32_3x3 提升（扩精度） |
| 方法 | `Float64 _getItem_(int index)` | ── 索引访问 ───────────────────────────────────────── |
| 方法 | `void _setItem_(int index, Float64 value)` | 执行 _setItem_(index, value)，行为详见源实现。 |
| 方法 | `Float64 getValue(int row, int col)` | getValue/setValue（get/set 为语言关键字，不可作方法名） |
| 方法 | `void setValue(int row, int col, Float64 value)` | 执行 setValue(row, col, value)，行为详见源实现。 |
| 方法 | `Float64_3x3 _mul_(Float64_3x3 b)` | ── 运算符重载 ─────────────────────────────────────── |
| 方法 | `Float64_3x3 _add_(Float64_3x3 b)` | 执行 _add_(b)，行为详见源实现。 |
| 方法 | `bool _eq_(Float64_3x3 b)` | 执行 _eq_(b)，行为详见源实现。 |
| 方法 | `bool _ne_(Float64_3x3 b)` | 执行 _ne_(b)，行为详见源实现。 |
| 方法 | `Float64_3x3 multiply(Float64_3x3 b)` | ── 矩阵运算 ───────────────────────────────────────── |
| 方法 | `Float64_3 transform(Float64_3 v)` | 执行 transform(v)，行为详见源实现。 |
| 方法 | `Float64_3x3 transpose()` | 执行 transpose()。 |
| 方法 | `Float64 determinant()` | 执行 determinant()。 |
| 方法 | `Float64_3x3 inverse()` | 伴随矩阵 / det，不可逆时返回零矩阵 |
| 方法 | `Float64_3x3 clone()` | 克隆 / 复制（clone）。 |
| 方法 | `Float32_3x3 toFloat32_3x3()` | 降精度到 Float32_3x3 |
| 属性 | `get Float64_3x3 identity()` | ── 静态常量与工厂 ──────────────────────────────────── |
| 属性 | `get Float64_3x3 zero()` | 获取 zero 的值。 |
| 方法 | `Float64_3x3 rotationX(Float64 radians)` | 绕 X 轴旋转（弧度） |
| 方法 | `Float64_3x3 rotationY(Float64 radians)` | 绕 Y 轴旋转（弧度） |
| 方法 | `Float64_3x3 rotationZ(Float64 radians)` | 绕 Z 轴旋转（弧度） |
| 方法 | `Float64_3x3 scale(Float64 sx, Float64 sy)` | 执行 scale(sx, sy)，行为详见源实现。 |
| 方法 | `Float64_3x3 translation(Float64 tx, Float64 ty)` | 执行 translation(tx, ty)，行为详见源实现。 |
| 方法 | `string toString()` | 转换为 Stringundefined 类型（toString）。 |
