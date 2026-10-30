# Container/Tuple.sl

> 源文件：`Container/Tuple.sl`

## class `Tuple<T1>`

- **说明**：模板形式：Tuple<T1>（单元素，强类型定长）

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `public T1 item1 = null` | 字段 T1（类型见签名）。 |
| 构造 | `_init_(T1 v1)` | 构造方法，初始化本类型实例。 |
| 方法 | `Tuple&lt;T1&gt; create(T1 v1)` | 初始化 / 创建（create）。 |
| 属性 | `get int length()` | 获取 length 的值。 |
| 方法 | `object _getItem_(int index)` | 下标读取：index 超出 [0, length) 返回 null |
| 方法 | `void _setItem_(int index, object value)` | 下标写入：index 超出 [0, length) 静默忽略 |
| 方法 | `string toString()` | 转换为 Stringundefined 类型（toString）。 |
| 方法 | `string _valueToString(object v)` | 执行 _valueToString(v)，行为详见源实现。 |

## class `Tuple<T1,T2>`

- **说明**：模板形式：Tuple<T1,T2>

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `public T1 item1 = null` | 字段 T1（类型见签名）。 |
| 字段 | `public T2 item2 = null` | 字段 T2（类型见签名）。 |
| 构造 | `_init_(T1 v1, T2 v2)` | 构造方法，初始化本类型实例。 |
| 方法 | `Tuple&lt;T1,T2&gt; create(T1 v1, T2 v2)` | 初始化 / 创建（create）。 |
| 属性 | `get int length()` | 获取 length 的值。 |
| 方法 | `object _getItem_(int index)` | 执行 _getItem_(index)，行为详见源实现。 |
| 方法 | `void _setItem_(int index, object value)` | 执行 _setItem_(index, value)，行为详见源实现。 |
| 方法 | `string toString()` | 转换为 Stringundefined 类型（toString）。 |
| 方法 | `string _valueToString(object v)` | 执行 _valueToString(v)，行为详见源实现。 |

## class `Tuple<T1,T2,T3>`

- **说明**：模板形式：Tuple<T1,T2,T3>

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `public T1 item1 = null` | 字段 T1（类型见签名）。 |
| 字段 | `public T2 item2 = null` | 字段 T2（类型见签名）。 |
| 字段 | `public T3 item3 = null` | 字段 T3（类型见签名）。 |
| 构造 | `_init_(T1 v1, T2 v2, T3 v3)` | 构造方法，初始化本类型实例。 |
| 方法 | `Tuple&lt;T1,T2,T3&gt; create(T1 v1, T2 v2, T3 v3)` | 初始化 / 创建（create）。 |
| 属性 | `get int length()` | 获取 length 的值。 |
| 方法 | `object _getItem_(int index)` | 执行 _getItem_(index)，行为详见源实现。 |
| 方法 | `void _setItem_(int index, object value)` | 执行 _setItem_(index, value)，行为详见源实现。 |
| 方法 | `string toString()` | 转换为 Stringundefined 类型（toString）。 |
| 方法 | `string _valueToString(object v)` | 执行 _valueToString(v)，行为详见源实现。 |

## class `Tuple<T1,T2,T3,T4>`

- **说明**：模板形式：Tuple<T1,T2,T3,T4>

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `public T1 item1 = null` | 字段 T1（类型见签名）。 |
| 字段 | `public T2 item2 = null` | 字段 T2（类型见签名）。 |
| 字段 | `public T3 item3 = null` | 字段 T3（类型见签名）。 |
| 字段 | `public T4 item4 = null` | 字段 T4（类型见签名）。 |
| 构造 | `_init_(T1 v1, T2 v2, T3 v3, T4 v4)` | 构造方法，初始化本类型实例。 |
| 方法 | `Tuple&lt;T1,T2,T3,T4&gt; create(T1 v1, T2 v2, T3 v3, T4 v4)` | 初始化 / 创建（create）。 |
| 属性 | `get int length()` | 获取 length 的值。 |
| 方法 | `object _getItem_(int index)` | 执行 _getItem_(index)，行为详见源实现。 |
| 方法 | `void _setItem_(int index, object value)` | 执行 _setItem_(index, value)，行为详见源实现。 |
| 方法 | `string toString()` | 转换为 Stringundefined 类型（toString）。 |
| 方法 | `string _valueToString(object v)` | 执行 _valueToString(v)，行为详见源实现。 |

## class `Tuple<T1,T2,T3,T4,T5>`

- **说明**：模板形式：Tuple<T1,T2,T3,T4,T5>

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `public T1 item1 = null` | 字段 T1（类型见签名）。 |
| 字段 | `public T2 item2 = null` | 字段 T2（类型见签名）。 |
| 字段 | `public T3 item3 = null` | 字段 T3（类型见签名）。 |
| 字段 | `public T4 item4 = null` | 字段 T4（类型见签名）。 |
| 字段 | `public T5 item5 = null` | 字段 T5（类型见签名）。 |
| 构造 | `_init_(T1 v1, T2 v2, T3 v3, T4 v4, T5 v5)` | 构造方法，初始化本类型实例。 |
| 方法 | `Tuple&lt;T1,T2,T3,T4,T5&gt; create(T1 v1, T2 v2, T3 v3, T4 v4, T5 v5)` | 初始化 / 创建（create）。 |
| 属性 | `get int length()` | 获取 length 的值。 |
| 方法 | `object _getItem_(int index)` | 执行 _getItem_(index)，行为详见源实现。 |
| 方法 | `void _setItem_(int index, object value)` | 执行 _setItem_(index, value)，行为详见源实现。 |
| 方法 | `string toString()` | 转换为 Stringundefined 类型（toString）。 |
| 方法 | `string _valueToString(object v)` | 执行 _valueToString(v)，行为详见源实现。 |

## class `Tuple<T1,T2,T3,T4,T5,T6>`

- **说明**：模板形式：Tuple<T1,T2,T3,T4,T5,T6>

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `public T1 item1 = null` | 字段 T1（类型见签名）。 |
| 字段 | `public T2 item2 = null` | 字段 T2（类型见签名）。 |
| 字段 | `public T3 item3 = null` | 字段 T3（类型见签名）。 |
| 字段 | `public T4 item4 = null` | 字段 T4（类型见签名）。 |
| 字段 | `public T5 item5 = null` | 字段 T5（类型见签名）。 |
| 字段 | `public T6 item6 = null` | 字段 T6（类型见签名）。 |
| 构造 | `_init_(T1 v1, T2 v2, T3 v3, T4 v4, T5 v5, T6 v6)` | 构造方法，初始化本类型实例。 |
| 方法 | `Tuple&lt;T1,T2,T3,T4,T5,T6&gt; create(T1 v1, T2 v2, T3 v3, T4 v4, T5 v5, T6 v6)` | 初始化 / 创建（create）。 |
| 属性 | `get int length()` | 获取 length 的值。 |
| 方法 | `object _getItem_(int index)` | 执行 _getItem_(index)，行为详见源实现。 |
| 方法 | `void _setItem_(int index, object value)` | 执行 _setItem_(index, value)，行为详见源实现。 |
| 方法 | `string toString()` | 转换为 Stringundefined 类型（toString）。 |
| 方法 | `string _valueToString(object v)` | 执行 _valueToString(v)，行为详见源实现。 |

## class `Tuple<T1,T2,T3,T4,T5,T6,T7>`

- **说明**：模板形式：Tuple<T1,T2,T3,T4,T5,T6,T7>

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `public T1 item1 = null` | 字段 T1（类型见签名）。 |
| 字段 | `public T2 item2 = null` | 字段 T2（类型见签名）。 |
| 字段 | `public T3 item3 = null` | 字段 T3（类型见签名）。 |
| 字段 | `public T4 item4 = null` | 字段 T4（类型见签名）。 |
| 字段 | `public T5 item5 = null` | 字段 T5（类型见签名）。 |
| 字段 | `public T6 item6 = null` | 字段 T6（类型见签名）。 |
| 字段 | `public T7 item7 = null` | 字段 T7（类型见签名）。 |
| 构造 | `_init_(T1 v1, T2 v2, T3 v3, T4 v4, T5 v5, T6 v6, T7 v7)` | 构造方法，初始化本类型实例。 |
| 方法 | `Tuple&lt;T1,T2,T3,T4,T5,T6,T7&gt; create(T1 v1, T2 v2, T3 v3, T4 v4, T5 v5, T6 v6, T7 v7)` | 初始化 / 创建（create）。 |
| 属性 | `get int length()` | 获取 length 的值。 |
| 方法 | `object _getItem_(int index)` | 执行 _getItem_(index)，行为详见源实现。 |
| 方法 | `void _setItem_(int index, object value)` | 执行 _setItem_(index, value)，行为详见源实现。 |
| 方法 | `string toString()` | 转换为 Stringundefined 类型（toString）。 |
| 方法 | `string _valueToString(object v)` | 执行 _valueToString(v)，行为详见源实现。 |

## class `Tuple<T1,T2,T3,T4,T5,T6,T7,T8>`

- **说明**：模板形式：Tuple<T1,T2,T3,T4,T5,T6,T7,T8>

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `public T1 item1 = null` | 字段 T1（类型见签名）。 |
| 字段 | `public T2 item2 = null` | 字段 T2（类型见签名）。 |
| 字段 | `public T3 item3 = null` | 字段 T3（类型见签名）。 |
| 字段 | `public T4 item4 = null` | 字段 T4（类型见签名）。 |
| 字段 | `public T5 item5 = null` | 字段 T5（类型见签名）。 |
| 字段 | `public T6 item6 = null` | 字段 T6（类型见签名）。 |
| 字段 | `public T7 item7 = null` | 字段 T7（类型见签名）。 |
| 字段 | `public T8 item8 = null` | 字段 T8（类型见签名）。 |
| 构造 | `_init_(T1 v1, T2 v2, T3 v3, T4 v4, T5 v5, T6 v6, T7 v7, T8 v8)` | 构造方法，初始化本类型实例。 |
| 方法 | `Tuple&lt;T1,T2,T3,T4,T5,T6,T7,T8&gt; create(T1 v1, T2 v2, T3 v3, T4 v4, T5 v5, T6 v6, T7 v7, T8 v8)` | 初始化 / 创建（create）。 |
| 属性 | `get int length()` | 获取 length 的值。 |
| 方法 | `object _getItem_(int index)` | 执行 _getItem_(index)，行为详见源实现。 |
| 方法 | `void _setItem_(int index, object value)` | 执行 _setItem_(index, value)，行为详见源实现。 |
| 方法 | `string toString()` | 转换为 Stringundefined 类型（toString）。 |
| 方法 | `string _valueToString(object v)` | 执行 _valueToString(v)，行为详见源实现。 |

## class `Tuple`

- **说明**：无模板形式：Tuple（Python 风格，动态类型，基于数组可无限扩展）

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `Array&lt;object&gt; _values = null` | 字段 _values（类型见签名）。 |
| 字段 | `int _length = 0` | 字段 _length（类型见签名）。 |
| 字段 | `int _capacity = 0` | 字段 _capacity（类型见签名）。 |
| 方法 | `override _init_()` | 空元组：Tuple()，长度 0 |
| 构造 | `_init_(val1)` | 构造方法，初始化本类型实例。 |
| 构造 | `_init_(val1, val2)` | 构造方法，初始化本类型实例。 |
| 构造 | `_init_(val1, val2, val3)` | 构造方法，初始化本类型实例。 |
| 构造 | `_init_(val1, val2, val3, val4)` | 构造方法，初始化本类型实例。 |
| 构造 | `_init_(val1, val2, val3, val4, val5)` | 构造方法，初始化本类型实例。 |
| 构造 | `_init_(val1, val2, val3, val4, val5, val6)` | 构造方法，初始化本类型实例。 |
| 构造 | `_init_(val1, val2, val3, val4, val5, val6, val7)` | 构造方法，初始化本类型实例。 |
| 构造 | `_init_(val1, val2, val3, val4, val5, val6, val7, val8)` | 构造方法，初始化本类型实例。 |
| 方法 | `Tuple create(params object[] values)` | 不限长静态工厂：可传任意个元素（内部按数组存储） |
| 方法 | `Tuple add(object value)` | 追加一个元素（容量不足自动扩容），返回 this 便于链式调用：t.add(1).add(2) |
| 属性 | `get int length()` | 获取 length 的值。 |
| 属性 | `get bool isEmpty()` | 获取 isEmpty 的值。 |
| 方法 | `object _getItem_(int index)` | 下标读取：index 超出 [0, length) 返回 null |
| 方法 | `void _setItem_(int index, object value)` | 下标写入：index 超出 [0, length) 静默忽略 |
| 方法 | `int indexOf(object value)` | 元素首次出现下标，未找到返回 -1 |
| 方法 | `bool contains(object value)` | 判断 / 校验是否（contains）。 |
| 方法 | `void clear()` | 执行 clear()。 |
| 方法 | `void _appendValue(object val)` | 内部：追加一个元素（首次使用时初始化内部数组，容量不足时扩容） |
| 方法 | `void _grow()` | 内部：容量扩展 0-&gt;4，之后倍增 4-&gt;8-&gt;16... |
| 方法 | `string toString()` | 转换为 Stringundefined 类型（toString）。 |
