# FFI/Struct.sl

> 源文件：`FFI/Struct.sl`

## class `FFI`

- **说明**：SLang 标准库类型 FFI（详见源文件）。

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `Int64 _addr = 0` | 字段 _addr（类型见签名）。 |
| 字段 | `Int32 _id = 0` | 字段 _id（类型见签名）。 |
| 方法 | `void _init_()` | 执行 _init_()。 |
| 方法 | `void _init_(Int32 id)` | 执行 _init_(id)，行为详见源实现。 |
| 属性 | `get Int64 address()` | 获取 address 的值。 |
| 属性 | `get Int32 layoutId()` | 获取 layoutId 的值。 |
| 方法 | `bool free()` | 执行 free()。 |
| 方法 | `Int64 marshalOut(object obj)` | 执行 marshalOut(obj)，行为详见源实现。 |
| 方法 | `bool marshalIn(object obj)` | 执行 marshalIn(obj)，行为详见源实现。 |
| 方法 | `Int32 define(string sig)` | 执行 define(sig)，行为详见源实现。 |
| 方法 | `Int32 size(Int32 id)` | 执行 size(id)，行为详见源实现。 |
| 方法 | `Int64 alloc(Int32 id)` | 容量扩展 / 内存分配（alloc）。 |
| 方法 | `bool free(Int64 addr)` | 执行 free(addr)，行为详见源实现。 |
| 方法 | `Int64 marshalOut(object obj, Int32 id)` | 执行 marshalOut(obj, id)，行为详见源实现。 |
| 方法 | `bool marshalIn(Int64 addr, Int32 id, object obj)` | 执行 marshalIn(addr, id, obj)，行为详见源实现。 |
