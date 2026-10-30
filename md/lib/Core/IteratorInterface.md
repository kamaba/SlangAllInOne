# IteratorInterface.sl

> 源文件：`IteratorInterface.sl`

## interface `IIterator`

- **接口**：IIterator
- **说明**：迭代器与可迭代契约（标准库统一遍历协议） 任何支持 foreach / Range 遍历 / 容器迭代的类型都实现 IIterable<T>，由其返回 IIterator<T>。 非泛型版本用于未知元素类型的弱类型场景。

| 类型 | 签名 | 说明 |
|------|------|------|
| 方法 | `void reset()` | 将迭代器复位到序列起始之前（下一次 moveNext 指向首个元素）。 |
| 方法 | `bool moveNext()` | 尝试前进到下一个元素；存在则返回 true，迭代结束返回 false。 |
| 属性 | `get object current()` | 获取当前迭代位置的元素（moveNext 返回 true 后有效；弱类型 object）。 |

## interface `IIterable`

- **接口**：IIterable
- **说明**：SLang 标准库接口 IIterable（详见源文件）。

| 类型 | 签名 | 说明 |
|------|------|------|
| 方法 | `IIterator iterator()` | 返回一个新的迭代器，用于遍历本集合（弱类型）。 |

## interface `IIterator<out T>`

- **接口**：IIterator&lt;out T&gt;
- **说明**：SLang 标准库接口 IIterator<out T>（详见源文件）。

| 类型 | 签名 | 说明 |
|------|------|------|
| 方法 | `void reset()` | 将迭代器复位到序列起始之前。 |
| 方法 | `bool moveNext()` | 尝试前进到下一个元素；存在则返回 true，否则 false。 |
| 属性 | `get T current()` | 获取当前位置的元素（强类型 T）。 |

## interface `IIterable<T>`

- **接口**：IIterable&lt;T&gt;
- **说明**：SLang 标准库接口 IIterable<T>（详见源文件）。

| 类型 | 签名 | 说明 |
|------|------|------|
| 方法 | `IIterator&lt;T&gt; iterator()` | 返回一个强类型新迭代器，用于遍历本集合。 |
