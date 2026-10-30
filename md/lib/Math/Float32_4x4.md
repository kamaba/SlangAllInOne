# Float32_4x4.sl

> 源文件：`Float32_4x4.sl`

## class `Float32_4x4`

- **说明**：SLang 标准库类型 Float32_4x4（详见源文件）。

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `public Float32 m00 = 0.0f` | 元素直接以字段存储（m{row}{col}，行主序），避免数组寻址开销； 元素级运算经 Mathf.dot3 走 FFI（math_lib.dll）加速 |
| 字段 | `public Float32 m01 = 0.0f` | 字段 Float32（类型见签名）。 |
| 字段 | `public Float32 m02 = 0.0f` | 字段 Float32（类型见签名）。 |
| 字段 | `public Float32 m03 = 0.0f` | 字段 Float32（类型见签名）。 |
| 字段 | `public Float32 m10 = 0.0f` | 字段 Float32（类型见签名）。 |
| 字段 | `public Float32 m11 = 0.0f` | 字段 Float32（类型见签名）。 |
| 字段 | `public Float32 m12 = 0.0f` | 字段 Float32（类型见签名）。 |
| 字段 | `public Float32 m13 = 0.0f` | 字段 Float32（类型见签名）。 |
| 字段 | `public Float32 m20 = 0.0f` | 字段 Float32（类型见签名）。 |
| 字段 | `public Float32 m21 = 0.0f` | 字段 Float32（类型见签名）。 |
| 字段 | `public Float32 m22 = 0.0f` | 字段 Float32（类型见签名）。 |
| 字段 | `public Float32 m23 = 0.0f` | 字段 Float32（类型见签名）。 |
| 字段 | `public Float32 m30 = 0.0f` | 字段 Float32（类型见签名）。 |
| 字段 | `public Float32 m31 = 0.0f` | 字段 Float32（类型见签名）。 |
| 字段 | `public Float32 m32 = 0.0f` | 字段 Float32（类型见签名）。 |
| 字段 | `public Float32 m33 = 0.0f` | 字段 Float32（类型见签名）。 |
| 方法 | `void _init_()` | ── 构造 ───────────────────────────────────────────── |
| 方法 | `void _init_(Array&lt;Float32&gt; values)` | 执行 _init_(values)，行为详见源实现。 |
| 方法 | `void _init_(Float32_3x3 m)` | 执行 _init_(m)，行为详见源实现。 |
| 方法 | `Float32 _getItem_(int index)` | ── 索引访问 ───────────────────────────────────────── |
| 方法 | `void _setItem_(int index, Float32 value)` | 执行 _setItem_(index, value)，行为详见源实现。 |
| 方法 | `Float32 getValue(int row, int col)` | getValue/setValue（get/set 为语言关键字，不可作方法名） |
| 方法 | `void setValue(int row, int col, Float32 value)` | 执行 setValue(row, col, value)，行为详见源实现。 |
| 方法 | `Float32_4x4 _mul_(Float32_4x4 b)` | ── 运算符重载 ─────────────────────────────────────── |
| 方法 | `Float32_4x4 _add_(Float32_4x4 b)` | 执行 _add_(b)，行为详见源实现。 |
| 方法 | `bool _eq_(Float32_4x4 b)` | 执行 _eq_(b)，行为详见源实现。 |
| 方法 | `bool _ne_(Float32_4x4 b)` | 执行 _ne_(b)，行为详见源实现。 |
| 方法 | `Float32_4x4 multiply(Float32_4x4 b)` | ── 矩阵运算 ───────────────────────────────────────── |
| 方法 | `Float32_3 transformPoint(Float32_3 v)` | 变换点（w 补 1，带平移） |
| 方法 | `Float32_3 transformDirection(Float32_3 v)` | 变换方向（w 补 0，忽略平移） |
| 方法 | `Float32_4x4 transpose()` | 执行 transpose()。 |
| 方法 | `Float32 determinant()` | 执行 determinant()。 |
| 方法 | `Float32_4x4 inverse()` | 伴随矩阵 / det，不可逆时返回零矩阵 |
| 方法 | `Float32_4x4 clone()` | 克隆 / 复制（clone）。 |
| 方法 | `Float32_3x3 toFloat32_3x3()` | 降维到 2D 仿射：x/y 基取前两列，平移分量（第四列 x/y）落入第三列，底行取 (0,0,1) |
| 属性 | `get Float32_4x4 identity()` | ── 静态常量与工厂 ──────────────────────────────────── |
| 属性 | `get Float32_4x4 zero()` | 获取 zero 的值。 |
| 方法 | `Float32_4x4 translation(Float32 x, Float32 y, Float32 z)` | 执行 translation(x, y, z)，行为详见源实现。 |
| 方法 | `Float32_4x4 translation(Float32_3 t)` | 执行 translation(t)，行为详见源实现。 |
| 方法 | `Float32_4x4 scale(Float32 x, Float32 y, Float32 z)` | 执行 scale(x, y, z)，行为详见源实现。 |
| 方法 | `Float32_4x4 scale(Float32_3 s)` | 执行 scale(s)，行为详见源实现。 |
| 方法 | `Float32_4x4 scale(Float32 s)` | 执行 scale(s)，行为详见源实现。 |
| 方法 | `Float32_4x4 rotationX(Float32 radians)` | 绕 X 轴旋转（弧度） |
| 方法 | `Float32_4x4 rotationY(Float32 radians)` | 绕 Y 轴旋转（弧度） |
| 方法 | `Float32_4x4 rotationZ(Float32 radians)` | 绕 Z 轴旋转（弧度） |
| 方法 | `Float32_4x4 rotationAxis(Float32_3 axis, Float32 radians)` | 绕任意轴旋转（弧度，axis 内部会归一化） |
| 方法 | `Float32_4x4 trs(Float32_3 translation, Float32_3 rotationEuler, Float32_3 scale)` | 局部 TRS 组合：translation * rotation * scale |
| 方法 | `Float32_4x4 perspective(Float32 fovYRadians, Float32 aspect, Float32 near, Float32 far)` | 透视投影（右手系，depth 映射到 [-1,1]） |
| 方法 | `Float32_4x4 ortho(Float32 left, Float32 right, Float32 bottom, Float32 top, Float32 near, Float32 far)` | 正交投影 |
| 方法 | `Float32_4x4 lookAt(Float32_3 eye, Float32_3 target, Float32_3 upHint)` | 视图矩阵（右手系 lookAt） |
| 方法 | `string toString()` | 转换为 Stringundefined 类型（toString）。 |
