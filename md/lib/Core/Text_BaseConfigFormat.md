# Text/BaseConfigFormat.sl

> 源文件：`Text/BaseConfigFormat.sl`

## class `ConfitFormat`

- **说明**：配置格式基类（模板方法骨架）：以 JSON 字符串为输入构造，提供空实现的初始化 / 序列化方法， 供具体配置格式（如 TOML / YAML 等）派生并重写其解析与 toString 逻辑。

| 类型 | 签名 | 说明 |
|------|------|------|
| 方法 | `override _init_()` | 执行 _init_()。 |
| 方法 | `void _init_(string jsonstr)` | 执行 _init_(jsonstr)，行为详见源实现。 |
| 方法 | `string toString()` | 转换为 Stringundefined 类型（toString）。 |
