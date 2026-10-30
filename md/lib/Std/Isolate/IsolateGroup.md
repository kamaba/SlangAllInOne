# Isolate/IsolateGroup.sl

> 源文件：`Isolate/IsolateGroup.sl`

## class `IsolateGroup`

- **说明**：SLang 标准库类型 IsolateGroup（详见源文件）。

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `Int64 _handle = 0` | 字段 _handle（类型见签名）。 |
| 方法 | `void _init_(Int64 groupId)` | 执行 _init_(groupId)，行为详见源实现。 |
| 方法 | `IsolateGroup current()` | 迭代器 / 订阅控制（current）。 |
| 方法 | `void exit()` | 执行 exit()。 |
| 属性 | `get Int32 isolateCount()` | 获取 isolateCount 的值。 |
| 属性 | `get Int64 id()` | 获取 id 的值。 |
