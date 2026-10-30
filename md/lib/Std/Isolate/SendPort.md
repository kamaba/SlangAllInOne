# Isolate/SendPort.sl

> 源文件：`Isolate/SendPort.sl`

## class `SendPort`

- **说明**：SLang 标准库类型 SendPort（详见源文件）。

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `Int64 _portId = 0` | 字段 _portId（类型见签名）。 |
| 方法 | `void _init_(Int64 portId)` | 执行 _init_(portId)，行为详见源实现。 |
| 方法 | `void send(object message)` | 执行 send(message)，行为详见源实现。 |
| 属性 | `get Int64 portId()` | 获取 portId 的值。 |
