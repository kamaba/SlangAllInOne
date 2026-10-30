# Isolate/TransferableData.sl

> 源文件：`Isolate/TransferableData.sl`

## class `TransferableData`

- **说明**：SLang 标准库类型 TransferableData（详见源文件）。

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `Int64 _handle = 0` | 字段 _handle（类型见签名）。 |
| 方法 | `void _init_(Int64 handle)` | 执行 _init_(handle)，行为详见源实现。 |
| 方法 | `TransferableData fromBytes(Array&lt;UInt8&gt; bytes)` | 执行 fromBytes(bytes)，行为详见源实现。 |
| 方法 | `Array&lt;UInt8&gt; materialize()` | 执行 materialize()。 |
| 属性 | `get Int32 size()` | 获取 size 的值。 |
| 属性 | `get bool isValid()` | 获取 isValid 的值。 |
