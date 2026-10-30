# IO/BinaryCodec.sl

> 源文件：`IO/BinaryCodec.sl`

## class `BinaryCodec`

- **说明**：Core/IO/BinaryCodec.sl — 二进制编解码器（STREAM_DESIGN.md §8.6） P2 范围：闭包注入版 Codec<object, ByteBuffer>。encode/decode 逻辑由调用方 提供（System.Buffer 风格的字段序读写由调用方手写，与 ProtoBuf 共用 varint 原语走 ByteBuffer system method）。 已知偏差（详见设计文档 §17 实现注记）： - 设计稿 of(Type t)（按字段声明顺序反射读写）依赖运行时反射， SL 无运行时反射；P2 改为 of(Function encoder, Function decoder) 闭包注入（与 ProtoCodec 同一降级方式）。反射式 of(Type) 待 P3 反射 syscall 落地后补。 - 设计稿 extends Codec<object, ByteBuffer>：object/ByteBuffer 均为具体类 形态（全具体实参），直接 extends 可物化（Utf8Codec 先例）， 无需中间基类。 - 设计稿落位 Std/Text/BinaryCodec.sl；因 Front 跨模块 extends 模板 类不支持（引用模块类装载时不重建模板映射字典， HandleExtendClassTemplateMapRelation 查 Core.Converter<S,T> 失败）， P2 落位 Core/IO（Codec 机制家族同址）；待 Front 支持跨模块模板 继承后迁移。

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `Function _encoderFn = null` | encode 闭包：object → ByteBuffer（字段序字节布局由调用方手写） |
| 字段 | `Function _decoderFn = null` | decode 闭包：ByteBuffer → object |
| 构造 | `_init_(Function encoderFn, Function decoderFn)` | 构造方法，初始化本类型实例。 |
| 方法 | `BinaryCodec of(Function encoderFn, Function decoderFn)` | 闭包注入工厂（反射式 of(Type) 见文件头偏差注记） |
| 方法 | `ChunkedConversionSink&lt;object&gt; startChunkedConversion(ChunkedConversionSink&lt;ByteBuffer&gt; sink)` | ── Codec 契约 ── Converter 契约：分块编码方向（逐块独立 encode 后转发下游 sink） |
| 属性 | `get Converter&lt;object, ByteBuffer&gt; encoder()` | 获取 get Converter&lt;object, ByteBuffer&gt; encoder() 的值。 |
| 属性 | `get Converter&lt;ByteBuffer, object&gt; decoder()` | 获取 get Converter&lt;ByteBuffer, object&gt; decoder() 的值。 |
