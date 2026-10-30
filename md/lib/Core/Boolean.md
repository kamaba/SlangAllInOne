# Boolean.sl

> 源文件：`Boolean.sl`

## class `Boolean`

- **说明**：布尔包装类型：将原始 bool 封装为对象，便于在需要 Object 的场合（集合、反射等）传递布尔值。

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `bool _value = false` | 内部布尔值（true / false）。 |
| 构造 | `_init_(bool b)` | 用给定布尔值构造包装对象。 |
| 方法 | `string toString()` | 返回 "True" 或 "False" 字符串表示。 |
