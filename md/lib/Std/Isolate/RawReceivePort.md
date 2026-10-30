# Isolate/RawReceivePort.sl

> 源文件：`Isolate/RawReceivePort.sl`

## class `RawReceivePort`

- **说明**：SLang 标准库类型 RawReceivePort（详见源文件）。

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `Int64 _portId = 0` | 字段 _portId（类型见签名）。 |
| 方法 | `void _init_()` | 执行 _init_()。 |
| 属性 | `get SendPort sendPort()` | 获取 sendPort 的值。 |
| 方法 | `void listen(Function handler)` | 迭代器 / 订阅控制（listen）。 |
| 方法 | `object recv()` | 执行 recv()。 |
| 方法 | `Result tryRecv()` | 执行 tryRecv()。 |
| 方法 | `void close()` | IO 读写 / 流控制（close）。 |
| 属性 | `get Int32 count()` | 获取 count 的值。 |
| 属性 | `get bool isClosed()` | 获取 isClosed 的值。 |
