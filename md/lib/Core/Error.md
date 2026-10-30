# Error.sl

> 源文件：`Error.sl`

## class `Error`

- **说明**：SLang 标准库类型 Error（详见源文件）。

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `Int32 code = 0` | ── Core fields ── Numeric error code |
| 字段 | `string message = ""` | Human-readable error description |
| 方法 | `override _init_()` | ── Constructors ── |
| 构造 | `_init_(Int32 code)` | 构造方法，初始化本类型实例。 |
| 构造 | `_init_(Int32 code, string msg)` | 构造方法，初始化本类型实例。 |
| 属性 | `get Int32 getErrorCode()` | ── Property getters ── |
| 属性 | `get string getMessage()` | 获取 getMessage 的值。 |
| 方法 | `string toString()` | ── Methods ── |
