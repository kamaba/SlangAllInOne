# Environment/Platform_Defs.sl

> 源文件：`Environment/Platform_Defs.sl`

## class `DefItem`

- **说明**：Single definition member descriptor.

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `public Int32 value = 0` | Enum value (must match CVM sl_platform_def.h). |
| 字段 | `public string name = ""` | Member name (== jsonc key), e.g. "linux". |
| 字段 | `public string describe = ""` | Human readable description (diagnostics). |

## class `defs`

- **说明**：★ Registry — table data provided by C side (sl_platform_def.c).

| 类型 | 签名 | 说明 |
|------|------|------|
| 方法 | `DefItem lookup(DefKind kind, string name)` | Look up a definition by kind + member name. Returns the DefItem, or null when the name is unknown. |
| 方法 | `bool contains(DefKind kind, string name)` | Whether the definition table of the given kind contains name. |
| 方法 | `Array&lt;string&gt; names(DefKind kind)` | All member names (jsonc keys) of the given kind, in enum order. |
