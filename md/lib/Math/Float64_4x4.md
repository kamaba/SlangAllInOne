# Float64_4x4.sl

> 源文件：`Float64_4x4.sl`

## class `Float64_4x4`

- **说明**：SLang 标准库类型 Float64_4x4（详见源文件）。

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `public Float64 m00 = 0.0d` | 元素直接以字段存储（m{row}{col}，行主序），避免数组寻址开销； 高消耗运算（乘/加/转置/行列式/求逆/变换/工厂）下沉 cvm： SystemMathMat4d*（systemCalls -&gt; math_lib.dll 的 mathvm_mat4d_*）， C 侧直接按 member_data 读写字段内存；结果经 out 参数写回 |
| 字段 | `public Float64 m01 = 0.0d` | 字段 Float64（类型见签名）。 |
| 字段 | `public Float64 m02 = 0.0d` | 字段 Float64（类型见签名）。 |
| 字段 | `public Float64 m03 = 0.0d` | 字段 Float64（类型见签名）。 |
| 字段 | `public Float64 m10 = 0.0d` | 字段 Float64（类型见签名）。 |
| 字段 | `public Float64 m11 = 0.0d` | 字段 Float64（类型见签名）。 |
| 字段 | `public Float64 m12 = 0.0d` | 字段 Float64（类型见签名）。 |
| 字段 | `public Float64 m13 = 0.0d` | 字段 Float64（类型见签名）。 |
| 字段 | `public Float64 m20 = 0.0d` | 字段 Float64（类型见签名）。 |
| 字段 | `public Float64 m21 = 0.0d` | 字段 Float64（类型见签名）。 |
| 字段 | `public Float64 m22 = 0.0d` | 字段 Float64（类型见签名）。 |
| 字段 | `public Float64 m23 = 0.0d` | 字段 Float64（类型见签名）。 |
| 字段 | `public Float64 m30 = 0.0d` | 字段 Float64（类型见签名）。 |
| 字段 | `public Float64 m31 = 0.0d` | 字段 Float64（类型见签名）。 |
| 字段 | `public Float64 m32 = 0.0d` | 字段 Float64（类型见签名）。 |
| 字段 | `public Float64 m33 = 0.0d` | 字段 Float64（类型见签名）。 |
| 方法 | `void _init_()` | ── 构造 ───────────────────────────────────────────── |
| 方法 | `void _init_(Array&lt;Float64&gt; values)` | 执行 _init_(values)，行为详见源实现。 |
| 方法 | `void _init_(Float64_3x3 m)` | 执行 _init_(m)，行为详见源实现。 |
| 方法 | `void _init_(Float32_4x4 m)` | 执行 _init_(m)，行为详见源实现。 |
| 方法 | `Float64 _getItem_(int index)` | ── 索引访问 ───────────────────────────────────────── |
| 方法 | `void _setItem_(int index, Float64 value)` | 执行 _setItem_(index, value)，行为详见源实现。 |
| 方法 | `Float64 getValue(int row, int col)` | getValue/setValue（get/set 为语言关键字，不可作方法名） |
| 方法 | `void setValue(int row, int col, Float64 value)` | 执行 setValue(row, col, value)，行为详见源实现。 |
| 方法 | `Float64_4x4 _mul_(Float64_4x4 b)` | ── 运算符重载 ─────────────────────────────────────── |
| 方法 | `Float64_4x4 _add_(Float64_4x4 b)` | 执行 _add_(b)，行为详见源实现。 |
| 方法 | `bool _eq_(Float64_4x4 b)` | 执行 _eq_(b)，行为详见源实现。 |
| 方法 | `bool _ne_(Float64_4x4 b)` | 执行 _ne_(b)，行为详见源实现。 |
| 方法 | `Float64_4x4 multiply(Float64_4x4 b)` | ── 矩阵运算 ───────────────────────────────────────── |
| 方法 | `Float64_3 transformPoint(Float64_3 v)` | 变换点（w 补 1，带平移） |
| 方法 | `Float64_3 transformDirection(Float64_3 v)` | 变换方向（w 补 0，忽略平移） |
| 方法 | `Float64_4x4 transpose()` | 执行 transpose()。 |
| 方法 | `Float64 determinant()` | 执行 determinant()。 |
| 方法 | `Float64_4x4 inverse()` | 伴随矩阵 / det，不可逆时返回零矩阵 |
| 方法 | `Float64_4x4 clone()` | 克隆 / 复制（clone）。 |
| 方法 | `Float64_3x3 toFloat64_3x3()` | 降维到 2D 仿射：x/y 基取前两列，平移分量（第四列 x/y）落入第三列，底行取 (0,0,1) |
| 方法 | `Float32_4x4 toFloat32_4x4()` | 收敛到 Float32_4x4 |
| 属性 | `get Float64_4x4 identity()` | ── 静态常量与工厂 ──────────────────────────────────── |
| 属性 | `get Float64_4x4 zero()` | 获取 zero 的值。 |
| 方法 | `Float64_4x4 translation(Float64 x, Float64 y, Float64 z)` | 执行 translation(x, y, z)，行为详见源实现。 |
| 方法 | `Float64_4x4 translation(Float64_3 t)` | 执行 translation(t)，行为详见源实现。 |
| 方法 | `Float64_4x4 scale(Float64 x, Float64 y, Float64 z)` | 执行 scale(x, y, z)，行为详见源实现。 |
| 方法 | `Float64_4x4 scale(Float64_3 s)` | 执行 scale(s)，行为详见源实现。 |
| 方法 | `Float64_4x4 scale(Float64 s)` | 执行 scale(s)，行为详见源实现。 |
| 方法 | `Float64_4x4 rotationX(Float64 radians)` | 绕 X 轴旋转（弧度） |
| 方法 | `Float64_4x4 rotationY(Float64 radians)` | 绕 Y 轴旋转（弧度） |
| 方法 | `Float64_4x4 rotationZ(Float64 radians)` | 绕 Z 轴旋转（弧度） |
| 方法 | `Float64_4x4 rotationAxis(Float64_3 axis, Float64 radians)` | 绕任意轴旋转（弧度，axis 内部会归一化） |
| 方法 | `Float64_4x4 trs(Float64_3 translation, Float64_3 rotationEuler, Float64_3 scale)` | 局部 TRS 组合：translation * rotation * scale |
| 方法 | `Float64_4x4 perspective(Float64 fovYRadians, Float64 aspect, Float64 near, Float64 far)` | 透视投影（右手系，depth 映射到 [-1,1]） |
| 方法 | `Float64_4x4 ortho(Float64 left, Float64 right, Float64 bottom, Float64 top, Float64 near, Float64 far)` | 正交投影 |
| 方法 | `Float64_4x4 lookAt(Float64_3 eye, Float64_3 target, Float64_3 upHint)` | 视图矩阵（右手系 lookAt） |
| 方法 | `string toString()` | 转换为 Stringundefined 类型（toString）。 |
