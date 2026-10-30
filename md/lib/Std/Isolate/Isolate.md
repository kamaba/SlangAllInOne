# Isolate/Isolate.sl

> 源文件：`Isolate/Isolate.sl`

## class `Isolate`

- **说明**：SLang 标准库类型 Isolate（详见源文件）。

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `Int64 _handle = 0` | 字段 _handle（类型见签名）。 |
| 字段 | `Int64 _controlPortId = 0` | 字段 _controlPortId（类型见签名）。 |
| 字段 | `Int64 _pauseCapabilityId = 0` | 字段 _pauseCapabilityId（类型见签名）。 |
| 字段 | `Int64 _terminateCapabilityId = 0` | 字段 _terminateCapabilityId（类型见签名）。 |
| 方法 | `void _init_(SendPort controlPort, Capability pauseCapability, Capability terminateCapability)` | 执行 _init_(controlPort, pauseCapability, terminateCapability)，行为详见源实现。 |
| 方法 | `Isolate current()` | 迭代器 / 订阅控制（current）。 |
| 方法 | `void exit(SendPort port, object message)` | 执行 exit(port, message)，行为详见源实现。 |
| 方法 | `Capability pause()` | 执行 pause()。 |
| 方法 | `void resume(Capability capability)` | 执行 resume(capability)，行为详见源实现。 |
| 方法 | `void kill(Int32 priority)` | 执行 kill(priority)，行为详见源实现。 |
| 方法 | `void ping(SendPort responsePort, object response, Int32 priority)` | 执行 ping(responsePort, response, priority)，行为详见源实现。 |
| 方法 | `void setErrorsFatal(bool fatal)` | 执行 setErrorsFatal(fatal)，行为详见源实现。 |
| 方法 | `void addOnExitListener(SendPort port, object response)` | 执行 addOnExitListener(port, response)，行为详见源实现。 |
| 方法 | `void addErrorListener(SendPort port)` | 执行 addErrorListener(port)，行为详见源实现。 |
| 属性 | `get Int32 status()` | 获取 status 的值。 |
| 属性 | `get string debugName()` | 获取 debugName 的值。 |
| 属性 | `get Int64 handle()` | 获取 handle 的值。 |
| 属性 | `get SendPort controlPort()` | 获取 controlPort 的值。 |
| 属性 | `get Capability pauseCapability()` | 获取 pauseCapability 的值。 |
| 属性 | `get Capability terminateCapability()` | 获取 terminateCapability 的值。 |
