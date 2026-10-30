# Float16_4x4.sl

> 源文件：`Float16_4x4.sl`

## class `Float16_4x4`

- **说明**：SLang 标准库类型 Float16_4x4（详见源文件）。

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `public Float16 m00 = 0.0h` | 元素直接以字段存储（m{row}{col}，行主序），避免数组寻址开销； 高消耗运算（乘/加/转置/行列式/求逆/变换/工厂）下沉 cvm： SystemMathMat4h*（systemCalls -&gt; math_lib.dll 的 mathvm_mat4h_*）， C 侧直接按 member_data 读写字段内存（half 位模式，f32 中转计算）； 结果经 out 参数写回；标量形参走 Float32（前端自动 F16&lt;-&gt;F32 收敛） |
| 字段 | `public Float16 m01 = 0.0h` | 字段 Float16（类型见签名）。 |
| 字段 | `public Float16 m02 = 0.0h` | 字段 Float16（类型见签名）。 |
| 字段 | `public Float16 m03 = 0.0h` | 字段 Float16（类型见签名）。 |
| 字段 | `public Float16 m10 = 0.0h` | 字段 Float16（类型见签名）。 |
| 字段 | `public Float16 m11 = 0.0h` | 字段 Float16（类型见签名）。 |
| 字段 | `public Float16 m12 = 0.0h` | 字段 Float16（类型见签名）。 |
| 字段 | `public Float16 m13 = 0.0h` | 字段 Float16（类型见签名）。 |
| 字段 | `public Float16 m20 = 0.0h` | 字段 Float16（类型见签名）。 |
| 字段 | `public Float16 m21 = 0.0h` | 字段 Float16（类型见签名）。 |
| 字段 | `public Float16 m22 = 0.0h` | 字段 Float16（类型见签名）。 |
| 字段 | `public Float16 m23 = 0.0h` | 字段 Float16（类型见签名）。 |
| 字段 | `public Float16 m30 = 0.0h` | 字段 Float16（类型见签名）。 |
| 字段 | `public Float16 m31 = 0.0h` | 字段 Float16（类型见签名）。 |
| 字段 | `public Float16 m32 = 0.0h` | 字段 Float16（类型见签名）。 |
| 字段 | `public Float16 m33 = 0.0h` | 字段 Float16（类型见签名）。 |
| 方法 | `void _init_()` | ── 构造 ───────────────────────────────────────────── |
| 方法 | `void _init_(Array&lt;Float16&gt; values)` | 执行 _init_(values)，行为详见源实现。 |
| 方法 | `void _init_(Float16_3x3 m)` | 执行 _init_(m)，行为详见源实现。 |
| 方法 | `void _init_(Float32_4x4 m)` | 由 Float32_4x4 降精度（隐式收敛，见 Float16_3._init_(Float32_3) 先例） |
| 方法 | `Float16 _getItem_(int index)` | ── 索引访问 ───────────────────────────────────────── |
| 方法 | `void _setItem_(int index, Float16 value)` | 执行 _setItem_(index, value)，行为详见源实现。 |
| 方法 | `Float16 getValue(int row, int col)` | getValue/setValue（get/set 为语言关键字，不可作方法名） |
| 方法 | `void setValue(int row, int col, Float16 value)` | 执行 setValue(row, col, value)，行为详见源实现。 |
| 方法 | `Float16_4x4 _mul_(Float16_4x4 b)` | ── 运算符重载 ─────────────────────────────────────── |
| 方法 | `Float16_4x4 _add_(Float16_4x4 b)` | 执行 _add_(b)，行为详见源实现。 |
| 方法 | `bool _eq_(Float16_4x4 b)` | 执行 _eq_(b)，行为详见源实现。 |
| 方法 | `bool _ne_(Float16_4x4 b)` | 执行 _ne_(b)，行为详见源实现。 |
| 方法 | `Float16_4x4 multiply(Float16_4x4 b)` | ── 矩阵运算 ───────────────────────────────────────── |
| 方法 | `Float16_3 transformPoint(Float16_3 v)` | 变换点（w 补 1，带平移） |
| 方法 | `Float16_3 transformDirection(Float16_3 v)` | 变换方向（w 补 0，忽略平移） |
| 方法 | `Float16_4x4 transpose()` | 执行 transpose()。 |
| 方法 | `Float16 determinant()` | 执行 determinant()。 |
| 方法 | `Float16_4x4 inverse()` | 伴随矩阵 / det，不可逆时返回零矩阵 |
| 方法 | `Float16_4x4 clone()` | 克隆 / 复制（clone）。 |
| 方法 | `Float16_3x3 toFloat16_3x3()` | 降维到 2D 仿射：x/y 基取前两列，平移分量（第四列 x/y）落入第三列，底行取 (0,0,1) |
| 方法 | `Float32_4x4 toFloat32_4x4()` | 提升到 Float32_4x4 |
| 属性 | `get Float16_4x4 identity()` | ── 静态常量与工厂 ──────────────────────────────────── |
| 属性 | `get Float16_4x4 zero()` | 获取 zero 的值。 |
| 方法 | `Float16_4x4 translation(Float16 x, Float16 y, Float16 z)` | 执行 translation(x, y, z)，行为详见源实现。 |
| 方法 | `Float16_4x4 translation(Float16_3 t)` | 执行 translation(t)，行为详见源实现。 |
| 方法 | `Float16_4x4 scale(Float16 x, Float16 y, Float16 z)` | 执行 scale(x, y, z)，行为详见源实现。 |
| 方法 | `Float16_4x4 scale(Float16_3 s)` | 执行 scale(s)，行为详见源实现。 |
| 方法 | `Float16_4x4 scale(Float16 s)` | 执行 scale(s)，行为详见源实现。 |
| 方法 | `Float16_4x4 rotationX(Float16 radians)` | 绕 X 轴旋转（弧度） |
| 方法 | `Float16_4x4 rotationY(Float16 radians)` | 绕 Y 轴旋转（弧度） |
| 方法 | `Float16_4x4 rotationZ(Float16 radians)` | 绕 Z 轴旋转（弧度） |
| 方法 | `Float16_4x4 rotationAxis(Float16_3 axis, Float16 radians)` | 绕任意轴旋转（弧度，axis 内部会归一化） |
| 方法 | `Float16_4x4 trs(Float16_3 translation, Float16_3 rotationEuler, Float16_3 scale)` | 局部 TRS 组合：translation * rotation * scale |
| 方法 | `Float16_4x4 perspective(Float16 fovYRadians, Float16 aspect, Float16 near, Float16 far)` | 透视投影（右手系，depth 映射到 [-1,1]） |
| 方法 | `Float16_4x4 ortho(Float16 left, Float16 right, Float16 bottom, Float16 top, Float16 near, Float16 far)` | 正交投影 |
| 方法 | `Float16_4x4 lookAt(Float16_3 eye, Float16_3 target, Float16_3 upHint)` | 视图矩阵（右手系 lookAt） |
| 方法 | `string toString()` | 转换为 Stringundefined 类型（toString）。 |
