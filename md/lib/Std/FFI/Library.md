# FFI/Library.sl

> 源文件：`FFI/Library.sl`

## class `FFI`

- **说明**：SLang 标准库类型 FFI（详见源文件）。

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `Int64 _handle = 0` | 字段 _handle（类型见签名）。 |
| 方法 | `void _init_()` | 执行 _init_()。 |
| 方法 | `void _init_(string path)` | 执行 _init_(path)，行为详见源实现。 |
| 方法 | `void _init_(Int64 handle)` | 执行 _init_(handle)，行为详见源实现。 |
| 属性 | `get Int64 handle()` | 获取 handle 的值。 |
| 属性 | `get bool isValid()` | 获取 isValid 的值。 |
| 方法 | `Int64 getSymbol(string name)` | 执行 getSymbol(name)，行为详见源实现。 |
| 方法 | `Function getFunction(string name, string sig)` | 执行 getFunction(name, sig)，行为详见源实现。 |
| 方法 | `Int32 addRef()` | 执行 addRef()。 |
| 方法 | `Int32 refcount()` | 执行 refcount()。 |
| 方法 | `bool release()` | 执行 release()。 |

## class `FFI`

- **说明**：SLang 标准库类型 FFI（详见源文件）。

| 类型 | 签名 | 说明 |
|------|------|------|
| 方法 | `void _init_()` | 执行 _init_()。 |
| 方法 | `Int32 libraryCount()` | 执行 libraryCount()。 |
| 方法 | `Library GetStaticLib(string name)` | 执行 GetStaticLib(name)，行为详见源实现。 |
| 方法 | `Int64 createCallback(string method, string sig)` | 初始化 / 创建（createCallback）。 |
| 方法 | `bool freeCallback(Int64 addr)` | 执行 freeCallback(addr)，行为详见源实现。 |
| 方法 | `Function bindFunction(string path, string symbol, string sig)` | 执行 bindFunction(path, symbol, sig)，行为详见源实现。 |
