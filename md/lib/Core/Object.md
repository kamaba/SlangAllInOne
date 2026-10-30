# Object.sl

> 源文件：`Object.sl`

## class `Object`

- **说明**：SLang 标准库类型 Object（详见源文件）。

| 类型 | 签名 | 说明 |
|------|------|------|
| 方法 | `bool refEquals(object objA, object objB)` | static helper: null-safe equality |
| 方法 | `void _init_()` | basic constructor |
| 方法 | `bool equals(object obj)` | equality: default delegates to runtime equality helper which may compare by reference |
| 方法 | `string toString()` | string representation |
