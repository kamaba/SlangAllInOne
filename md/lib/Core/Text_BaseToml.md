# Text/BaseToml.sl

> 源文件：`Text/BaseToml.sl`

## class `BaseToml`

- **接口**：IDataStruct
- **说明**：TOML 配置数据结构的基类骨架：以 JSON 字符串初始化，toString 等方法留空实现，待具体派生类完成。

| 类型 | 签名 | 说明 |
|------|------|------|
| 方法 | `override _init_()` | 执行 _init_()。 |
| 方法 | `void _init_(string jsonstr)` | 执行 _init_(jsonstr)，行为详见源实现。 |
| 方法 | `string toString()` | 转换为 Stringundefined 类型（toString）。 |
