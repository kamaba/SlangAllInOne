# Result.sl

> 源文件：`Result.sl`

## class `Result`

- **说明**：通用返回结果封装：value 携带业务数据，code 携带状态码（0=成功），message 携带提示信息。 与 Core.Result<T> 配对（泛型版 value 为强类型 T）。 配套语言特性：函数返回类型声明为 Result / Result<T> 时，编译器自动注入局部变量 result， 函数体内直接写 result.code / result.message / result.value，ret expr 会被改写为 result.value = expr。

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `public Object value = null` | 字段 Object（类型见签名）。 |
| 字段 | `public int code = 0` | 字段 int（类型见签名）。 |
| 字段 | `public String message = ""` | 字段 String（类型见签名）。 |
| 方法 | `override _init_()` | 执行 _init_()。 |

## class `Result<T>`

- **说明**：泛型版返回结果封装（语义同 Result，value 强类型 T）。

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `public T value = null` | 字段 T（类型见签名）。 |
| 字段 | `public int code = 0` | 字段 int（类型见签名）。 |
| 字段 | `public String message = ""` | 字段 String（类型见签名）。 |
| 方法 | `override _init_()` | 执行 _init_()。 |
