# RData.RForecast —— 预测结果与置信区间

一条点预测（`mean`）加上下界（`lower`/`upper`）三条等长序列，可直接画
“预测线 + 置信带”，也支持与实际时间序列求残差。

## 构造

| 方法 | 签名 | 说明 |
|------|------|------|
| `create` | `static RForecast create(RVector mean, RVector lower, RVector upper)` | 由三条向量构造。 |
| `fromLists` | `static RForecast fromLists(List<Float32> mean, List<Float32> lower, List<Float32> upper)` | 由三个列表构造。 |

```slang
import Std;

List<Float32> mu = List<Float32>()
List<Float32> lo = List<Float32>()
List<Float32> hi = List<Float32>()
mu.add( 12.0f ); lo.add( 10.0f ); hi.add( 14.0f )

RData.RForecast fc = RData.RForecast.fromLists( mu, lo, hi )
Float32 center = fc.meanAt( 0 )       // 12
Float32 width = fc.coverageWidth( 0 ) // 4
```

## 读取

| 方法 | 签名 | 说明 |
|------|------|------|
| `count` | `Int32 count()` | 预测点数（取 mean 长度）。 |
| `meanAt` | `Float32 meanAt(Int32 index)` | 点预测值。 |
| `lowerAt` | `Float32 lowerAt(Int32 index)` | 置信下界。 |
| `upperAt` | `Float32 upperAt(Int32 index)` | 置信上界。 |
| `meanValues` | `RVector meanValues()` | 点预测向量。 |
| `lowerValues` | `RVector lowerValues()` | 下界向量。 |
| `upperValues` | `RVector upperValues()` | 上界向量。 |

## 误差与区间

| 方法 | 签名 | 说明 |
|------|------|------|
| `residuals` | `RVector residuals(RTimeSeries actual)` | 残差 = actual − mean，按两者较短长度计算。 |
| `coverageWidth` | `Float32 coverageWidth(Int32 index)` | 上下界差 = `upperAt - lowerAt`。 |

## 使用技巧 / 注意事项

- 三条序列没有自动做长度校验；长度不一致时 `count()` 以 `mean` 为准，
  访问 `lower/upper` 越界会由 `RVector` 返回 0。
- `residuals` 按**较短者**截断，适合预测区间比历史数据短的场景；若想
  严格对齐，请先自行截取 `RTimeSeries.window`。
- 画置信带时把 `lowerValues()` 与 `upperValues()` 作为两条边界，
  `meanValues()` 作为中心线；三者下标一一对应。
