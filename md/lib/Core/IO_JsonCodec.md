# IO/JsonCodec.sl

> 源文件：`IO/JsonCodec.sl`

## class `JsonCodec<T>`

- **说明**：JsonCodec<T> — T ↔ string（对象 ↔ JSON 文本） S = T（业务对象），T = string（文本，分块单位）

| 类型 | 签名 | 说明 |
|------|------|------|
| 属性 | `get Converter&lt;T, string&gt; encoder()` | ── Codec 契约：encoder / decoder 为 BaseJson 适配的 Converter ── |
| 属性 | `get Converter&lt;string, T&gt; decoder()` | 获取 get Converter&lt;string, T&gt; decoder() 的值。 |
