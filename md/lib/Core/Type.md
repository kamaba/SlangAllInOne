# Type.sl

> 源文件：`Type.sl`

## class `MetaClass`

- **说明**：元类：承载类型的命名空间与类名等元信息，供反射读取类型标识。

| 类型 | 签名 | 说明 |
|------|------|------|
| 属性 | `get string className()` | 获取 className 的值。 |

## class `Type`

- **说明**：类型对象：运行时类型的统一表示，封装底层类型枚举（eType）与元类（MetaClass），用于反射判断与类型信息读取。

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `byte _eType = 0` | 字段 _eType（类型见签名）。 |
| 字段 | `MetaClass _metaClass = null` | 字段 _metaClass（类型见签名）。 |
| 属性 | `get MetaClass metaClass()` | runtime accessors filled by RuntimeTypeManager.CreateTypeObject |
| 属性 | `get int eType()` | 获取 eType 的值。 |
| 方法 | `string toString()` | 转换为 Stringundefined 类型（toString）。 |
