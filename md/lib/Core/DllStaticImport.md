# DllStaticImport.sl

> 源文件：`DllStaticImport.sl`

## class `DllStaticImport`

- **说明**：SLang 标准库类型 DllStaticImport（详见源文件）。

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `private string _library = ""` | 运行前（Preload）生效: Front 只导出 attribute 数据（lib, symbol, sig），cvm 装配期 注册表按名+stage 发现并绑定，把命中调用点改写为 CallFFIStatic(77)+绑定索引 （与 DllImport 同款机制，ATTRIBUTE_DESIGN P10）；绑定失败运行期回退 SL 函数体 与 DllImport 的区别: 库只按 jsonc dllImports "static" 静态注册名预载解析（不走路径/dllImports 兜底链） 用法: @DllStaticImport("CLangdll", "sl_mul2", "i64-&gt;i64")（sig 可省略，导出层从函数签名补全） |
| 字段 | `private string _entryName = ""` | 字段 string（类型见签名）。 |
| 字段 | `private string _signature = ""` | 字段 string（类型见签名）。 |
| 构造 | `_init_(string library, string entryName, string signature)` | 构造方法，初始化本类型实例。 |
| 属性 | `get string library()` | 获取 library 的值。 |
| 属性 | `get string entryName()` | 获取 entryName 的值。 |
| 属性 | `get string signature()` | 获取 signature 的值。 |
