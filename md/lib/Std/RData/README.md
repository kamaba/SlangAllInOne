# RData（Std）类与方法索引

`Std` 库中的 `RData` 命名空间提供 R 风格的数据容器：**数值向量（带 NA）、
分类因子、列式数据表、时间序列、预测结果（含置信区间）**。全部为纯 SL
实现，无需额外原生库，可直接喂给图形 API 做统计图表。

```slang
import Std;

RData.RVector v = RData.RVector.create( List<Float32>() )
RData.RTable t = RData.RTable.fromCsvFile( "data/sales.csv" )
RData.RFactor f = t.factorByName( "city" )
```

| 类型 | 种类 | 文档 | 说明 |
|------|------|------|------|
| `RData.RVector` | class | [RVector.md](RVector.md) | 数值向量：名称、NA 缺失标记、切片/差分/均值/极值。 |
| `RData.RFactor` | class | [RFactor.md](RFactor.md) | 分类变量：levels + 整数编码、标签还原、频数统计。 |
| `RData.RTable` | class | [RTable.md](RTable.md) | data.frame 风格列式表：CSV 文本/文件入口、列访问、分类列转换、head。 |
| `RData.RTimeSeries` | class | [RTimeSeries.md](RTimeSeries.md) | 时间序列：起点+频率、时间轴换算、lag/diff/window。 |
| `RData.RForecast` | class | [RForecast.md](RForecast.md) | 预测结果：点预测 + 上下界三条序列、残差、区间宽度。 |

## 选用建议

- 只有一列数值 → `RVector`；带缺失值或元素名也用它。
- CSV 多列 → `RTable.fromCsvText` / `fromCsvFile`；数值列用 `columnByName`，
  分类列用 `factorByName`。
- 按时间采样的数据 → `RTimeSeries`，需要 lag/窗口时不用自己写下标。
- 回归/预测输出 → `RForecast`，三条等长序列可直接画置信带。

## 通用注意事项

- 这些容器用 `Float32`；需要 `Float64` 高精度计算时先转型，或直接用
  Math 库的 `MathStats` / `MathDist`。
- `RVector` 标成 NA 的位置读值为 `0`，请用 `isNA()` 区分“真的是 0”
  和“缺失”。
- `RTable` 保存原始 CSV 文本以按需解析文本列；`fromCsvText` 的数值列
  使用 CSV 解析器的浮点转换，无法解析的单元格按 0 处理。
- 所有 `slice/head/lag/diff/window` 都返回新对象，不修改原数据。
