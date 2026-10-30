# Rect.sl

> 源文件：`Rect.sl`

## class `Rect`

- **说明**：SLang 标准库类型 Rect（详见源文件）。

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `public Int32 x = 0` | 字段 Int32（类型见签名）。 |
| 字段 | `public Int32 y = 0` | 字段 Int32（类型见签名）。 |
| 字段 | `public Int32 width = 0` | 字段 Int32（类型见签名）。 |
| 字段 | `public Int32 height = 0` | 字段 Int32（类型见签名）。 |
| 方法 | `void _init_()` | ── 构造 ───────────────────────────────────────────── |
| 方法 | `void _init_(Int32 _x, Int32 _y, Int32 _width, Int32 _height)` | 执行 _init_(_x, _y, _width, _height)，行为详见源实现。 |
| 方法 | `void _init_(Int32_2 position, Int32_2 size)` | 执行 _init_(position, size)，行为详见源实现。 |
| 属性 | `get Int32 left()` | ── 边界属性 ───────────────────────────────────────── |
| 属性 | `get Int32 top()` | 获取 top 的值。 |
| 属性 | `get Int32 right()` | 获取 right 的值。 |
| 属性 | `get Int32 bottom()` | 获取 bottom 的值。 |
| 属性 | `get Int32_2 position()` | 获取 position 的值。 |
| 属性 | `get Int32_2 size()` | 获取 size 的值。 |
| 属性 | `get Int32_2 min()` | 获取 min 的值。 |
| 属性 | `get Int32_2 max()` | 获取 max 的值。 |
| 属性 | `get Int32_2 center()` | 中心点（整除） |
| 属性 | `get Int32 area()` | 获取 area 的值。 |
| 方法 | `bool isEmpty()` | 判断状态是否（isEmpty）。 |
| 方法 | `Int32 _getItem_(int index)` | ── 索引访问 ───────────────────────────────────────── |
| 方法 | `void _setItem_(int index, Int32 value)` | 执行 _setItem_(index, value)，行为详见源实现。 |
| 方法 | `bool _eq_(Rect r)` | ── 运算符重载 ─────────────────────────────────────── |
| 方法 | `bool _ne_(Rect r)` | 执行 _ne_(r)，行为详见源实现。 |
| 方法 | `bool contains(Int32 px, Int32 py)` | ── 几何运算 ───────────────────────────────────────── |
| 方法 | `bool contains(Int32_2 p)` | 判断 / 校验是否（contains）。 |
| 方法 | `bool contains(Rect other)` | 判断 / 校验是否（contains）。 |
| 方法 | `bool intersects(Rect other)` | 执行 intersects(other)，行为详见源实现。 |
| 方法 | `Rect intersection(Rect other)` | 交集（无交集返回空矩形） |
| 方法 | `Rect unionWith(Rect other)` | 并集（方法名避开 union 关键字） |
| 方法 | `Rect inflate(Int32 dx, Int32 dy)` | 执行 inflate(dx, dy)，行为详见源实现。 |
| 方法 | `Rect offset(Int32 dx, Int32 dy)` | 执行 offset(dx, dy)，行为详见源实现。 |
| 方法 | `Rect offset(Int32_2 d)` | 执行 offset(d)，行为详见源实现。 |
| 方法 | `Rect set(Int32 _x, Int32 _y, Int32 _width, Int32 _height)` | 设置 / 保存（set）。 |
| 方法 | `Rect clone()` | 克隆 / 复制（clone）。 |
| 属性 | `get Rect zero()` | ── 静态工厂 ───────────────────────────────────────── |
| 方法 | `Rect fromLTRB(Int32 left, Int32 top, Int32 right, Int32 bottom)` | 执行 fromLTRB(left, top, right, bottom)，行为详见源实现。 |
| 方法 | `Rect fromPoints(Int32_2 a, Int32_2 b)` | 执行 fromPoints(a, b)，行为详见源实现。 |
| 方法 | `string toString()` | 转换为 Stringundefined 类型（toString）。 |
