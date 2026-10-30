# Guid.sl

> 源文件：`Guid.sl`

## class `Guid`

- **说明**：Guid - Globally Unique Identifier. Inspired by: CLR  : System.Guid (NewGuid, ToString) Rust : uuid::Uuid (new_v4, to_string) Go   : google/uuid (New, String) Represents a 128-bit unique identifier stored as a string in standard format: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `private string _value = null` | 字段 string（类型见签名）。 |
| 方法 | `override _init_()` | Constructors Default constructor: generate a new GUID. |
| 构造 | `_init_(string value)` | Construct from an existing GUID string. |
| 方法 | `string newGuid()` | Static factory Generate a new GUID string and return it. |
| 属性 | `get string value()` | Instance accessors The GUID string value. |
| 方法 | `string toString(string format)` | Formatting Format the GUID using a format specifier (mirrors C# Guid.ToString(format)): "N" - 32 digits, no hyphens:        00000000000000000000000000000000 "D" - 32 digits with hyphens:       00000000-0000-0000-0000-000000000000  (default) "B" - hyphens, braces:              {00000000-0000-0000-0000-000000000000} "P" - hyphens, parentheses:        (00000000-0000-0000-0000-000000000000) Any other value falls back to "D". |
| 方法 | `string toString()` | Object overrides |
