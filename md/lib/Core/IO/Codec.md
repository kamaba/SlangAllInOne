# IO/Codec.sl

> 源文件：`IO/Codec.sl`

## class `_FusedConverter<S,T,M>`

- **说明**：_FusedConverter<S,T,M> — fuse 的组合实现（内部辅助类）

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `Converter&lt;S,T&gt; _first = null` | 字段 _first（类型见签名）。 |
| 字段 | `Converter&lt;T,M&gt; _second = null` | 字段 _second（类型见签名）。 |
| 构造 | `_init_(Converter&lt;S,T&gt; first, Converter&lt;T,M&gt; second)` | 构造方法，初始化本类型实例。 |
| 方法 | `M convert(S input)` | 转换 / 序列化 / 格式化（convert）。 |
| 方法 | `ChunkedConversionSink&lt;S&gt; startChunkedConversion(ChunkedConversionSink&lt;M&gt; sink)` | 运行 / 调用（startChunkedConversion）。 |

## class `_FusedCodec<S,T,M>`

- **说明**：_FusedCodec<S,T,M> — fuseCodec 的组合实现（内部辅助类）

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `Codec&lt;S,T&gt; _first = null` | 字段 _first（类型见签名）。 |
| 字段 | `Codec&lt;T,M&gt; _second = null` | 字段 _second（类型见签名）。 |
| 构造 | `_init_(Codec&lt;S,T&gt; first, Codec&lt;T,M&gt; second)` | 构造方法，初始化本类型实例。 |
| 属性 | `get Converter&lt;S,M&gt; encoder()` | encoder 顺向：S -&gt; T -&gt; M 注：getter 返回值上直接链式调用模板方法（fuse&lt;M&gt;）时，Front 泛型 实例化的 owner 类回溯不到 MetaVariable/MetaClass（getter 调用节点两者 皆空），会 NRE；先落局部变量再调用（既有库先例均为变量前缀形式）。 |
| 属性 | `get Converter&lt;M,S&gt; decoder()` | decoder 逆向：M -&gt; T -&gt; S |
| 方法 | `ChunkedConversionSink&lt;S&gt; startChunkedConversion(ChunkedConversionSink&lt;M&gt; sink)` | Converter 契约：分块转换顺向串接（与 _FusedConverter 同构， _first: Codec&lt;S,T&gt; 即 Converter&lt;S,T&gt;，_second 同理） |
