# RData.RVector —— 带名称与 NA 的数值向量

R 风格数值序列，是 `RTable`、`RTimeSeries`、`RForecast` 的公共列载体。
`Float32` 存储，支持逐元素 NA 标记和可选名称。

## 构造

| 方法 | 签名 | 说明 |
|------|------|------|
| `create` | `static RVector create(List<Float32> values)` | 由数值列表创建，全部非 NA、无名称。 |
| `createNamed` | `static RVector createNamed(List<Float32> values, List<string> names)` | 带元素名称。 |
| `fromCsvColumn` | `static RVector fromCsvColumn(string csvText, string columnName)` | 从 CSV 文本取一列；元素名取同一行的首列文本。 |

```slang
import Std;

List<Float32> xs = List<Float32>()
xs.add( 1.0f )
xs.add( 2.0f )
xs.add( 3.0f )

RData.RVector v = RData.RVector.create( xs )
```

## 读取与 NA

| 方法 | 签名 | 说明 |
|------|------|------|
| `length` | `Int32 length()` | 元素个数。 |
| `at` | `Float32 at(Int32 index)` | 取值；越界或 NA 返回 0。 |
| `isNA` | `bool isNA(Int32 index)` | 是否缺失；越界视为 NA。 |
| `setNA` | `void setNA(Int32 index, bool on)` | 设置/清除 NA 标记。 |
| `countNA` | `Int32 countNA()` | NA 个数。 |
| `nameAt` | `string nameAt(Int32 index)` | 元素名；无名称或越界返回空串。 |
| `hasNames` | `bool hasNames()` | 是否带名称。 |
| `values` | `List<Float32> values()` | 导出新列表，NA 位置为 0。 |

## 运算与切片

| 方法 | 签名 | 说明 |
|------|------|------|
| `slice` | `RVector slice(Int32 from, Int32 count)` | 截取新向量，自动截断到末尾。 |
| `diff` | `RVector diff()` | 相邻差分，长度 n-1。 |
| `sum` | `Float32 sum()` | 跳过 NA 求和。 |
| `mean` | `Float32 mean()` | 跳过 NA 求均值；无有效值返回 0。 |
| `minValue` | `Float32 minValue()` | 最小值（跳 NA）。 |
| `maxValue` | `Float32 maxValue()` | 最大值（跳 NA）。 |

## 使用技巧 / 注意事项

- NA 位置读出来是 `0`，但 `sum/mean/minValue/maxValue` 会跳过它们；
  画图前如果想要“缺失断开”，请先判 `isNA()` 再决定如何提交顶点。
- `slice` 不保留名称与 NA 标记，得到的是干净的纯数值向量。
- `createNamed` 不检查名称个数与数值个数是否一致；`nameAt` 越界返回空串。
