# DllImport.sl

> 源文件：`DllImport.sl`

## class `DllImport`

- **说明**：SLang 标准库类型 DllImport（详见源文件）。

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `private string _library = ""` | 运行前（Preload）生效: 装配期由 VM 原生 handler 将外部函数映射为 CVM 可调用入口 标注在 static 函数声明上, 带 fallback 函数体（绑定失败时回退执行 SL 实现） 用法: @DllImport("path.dll", "func") @DllImport("CLangdll", "sl_mul2", "i64-&gt;i64")   别名+签名 库路径或已注册库名（如 "CLangdll" 或相对路径） |
| 字段 | `private string _entryName = ""` | 导出函数名 |
| 字段 | `private string _signature = ""` | 签名串（如 "i64-&gt;i64"）, 空 = 按 fallback 体推导 |
| 构造 | `_init_(string library, string entryName)` | 构造方法，初始化本类型实例。 |
| 构造 | `_init_(string library, string entryName, string signature)` | 构造方法，初始化本类型实例。 |
| 属性 | `get string library()` | 获取 library 的值。 |
| 属性 | `get string entryName()` | 获取 entryName 的值。 |
| 属性 | `get string signature()` | 获取 signature 的值。 |
