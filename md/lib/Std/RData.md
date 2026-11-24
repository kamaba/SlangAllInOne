# Std · RData 统计数据结构

> 面向读者：要在 SLang 里做数据整合、描述统计、时间序列与预测结果处理的人。
> 本文只讲「怎么用」：规则、签名、示例、注意事项（R21 纯用法）。
> 引用：`import Std;`，类型前缀 `RData.`；纯 SL、零原生依赖。

---

## 1. 一分钟上手

```sl
import Std;

# CSV 文本 → 列式数据表
string csv = "city,sales\n1,10\n2,20\n1,15\n"
RData.RTable t = RData.RTable.fromCsvText( csv )

Int32 rows = t.rowCount()                     # 3
RData.RVector sales = t.columnByName( "sales" )  # 数值列
Float32 total = sales.sum()                   # 45

RData.RFactor city = t.factorByName( "city" )  # 分类列
Int32 n1 = city.countOf( 0 )                   # 2

# 时间序列 → 一阶差分
RData.RTimeSeries ts = RData.RTimeSeries.fromList( sales.values(), 2024.0f, 4.0f )
RData.RTimeSeries d = ts.diff()

# 预测结果（点预测 + 上下界）
RData.RForecast fc = RData.RForecast.fromLists( muVals, loVals, hiVals )
Float32 m1 = fc.meanAt( 1 )
```

---

## 2. 五个数据结构

每类另有一篇「签名 + 示例 + 注意事项」的详解：

- [RData.RVector](RData/RVector.md) · [RData.RFactor](RData/RFactor.md) ·
  [RData.RTable](RData/RTable.md) · [RData.RTimeSeries](RData/RTimeSeries.md) ·
  [RData.RForecast](RData/RForecast.md)（[总索引](RData/README.md)）

### 2.1 `RData.RVector` — 数值向量

R 向量的数值载体，带**名称**与 **NA（缺失）**语义。NA 位置读出来为 `0.0f`，用 `isNA()` 判别。

| 方法 | 说明 |
|---|---|
| `create(List<Float32>)` / `createNamed(values, names)` | 构造；后者带名称 |
| `fromCsvColumn(csvText, columnName)` | 直接从 CSV 文本取一列（带名称） |
| `length()` / `at(i)` / `isNA(i)` / `setNA(i,on)` / `countNA()` | 取值与缺失标记 |
| `nameAt(i)` / `hasNames()` | 名称（无名称返回 `""`） |
| `values()` | 导出普通 `List<Float32>`（跨模块边界用） |
| `slice(from,count)` / `diff()` | 子序列 / 一阶差分 |
| `sum()` / `mean()` / `minValue()` / `maxValue()` | 统计；自动跳过 NA |

### 2.2 `RData.RFactor` — 分类变量

R `factor`：把字符串标签编码为整数 code，levels 按**首次出现顺序**。

| 方法 | 说明 |
|---|---|
| `fromStrings(List<string>)` | 从标签列表构造 |
| `fromCodes(codes, levels)` | 从已有编码与水平构造 |
| `length()` / `levelCount()` | 样本数 / 水平数 |
| `codeAt(i)` / `levelAt(i)` / `labelAt(i)` | 编码 / 第 i 个水平 / 第 i 个样本的标签 |
| `countOf(level)` / `counts()` / `levels()` | 频数 / 各水平频数列表 / 水平列表 |

### 2.3 `RData.RTable` — 列式数据表

R `data.frame` 风格；底层复用 Core 的 CSV 解析，**只支持数值列的统计**，分类列通过 `factor*()` 拿。

| 方法 | 说明 |
|---|---|
| `fromCsvText(text)` / `fromCsvFile(path)` | CSV 文本 / 文件构造（首行为表头，逗号分隔） |
| `create(names)` | 空表（先建列名，再 `setNumericColumn`） |
| `rowCount()` / `columnCount()` / `nameAt(i)` | 形状与列名 |
| `columnIndex(name)` / `has(name)` | 列查找 |
| `column(i)` / `columnByName(name)` | 取 `RVector`；找不到返回 `null` |
| `stringAt(col,row)` / `stringsOf(col)` | 原始字符串值 |
| `factor(i)` / `factorByName(name)` | 分类列 → `RFactor` |
| `setNumericColumn(i, values)` / `head(n)` | 替换列 / 前 n 行 |

### 2.4 `RData.RTimeSeries` — 时间序列

R `ts`：值 + 起点 + 采样频率。

| 方法 | 说明 |
|---|---|
| `fromList(values, start, frequency)` / `create(RVector, start, frequency)` | 构造；frequency<=0 时按 1 处理 |
| `length()` / `at(i)` / `values()` | 取值 |
| `start()` / `frequency()` / `timeAt(i)` | 时间轴：`start + i / frequency` |
| `lag(k)` / `diff()` / `window(from,count)` | 滞后（前 k 项补 0）/ 差分 / 子窗口 |

### 2.5 `RData.RForecast` — 预测结果

点预测 + 上下置信界，对齐 R `forecast` / 常见回归输出。

| 方法 | 说明 |
|---|---|
| `fromLists(mean, lower, upper)` / `create(mv, lv, uv)` | 构造（三条等长序列） |
| `count()` / `meanAt(i)` / `lowerAt(i)` / `upperAt(i)` | 取值 |
| `meanValues()` / `lowerValues()` / `upperValues()` | 导出 `RVector` |
| `coverageWidth(i)` | 上界 − 下界 |
| `residuals(actualTs)` | 实际值 − 预测均值，按较短长度截断 |

---

## 3. 注意事项

| 事项 | 说明 |
|---|---|
| 统计列必须数值化 | CSV 中的分类列请用 `factor*`；非数值会成为 0 |
| NA 读数为 0 | 需要区分「真的 0」和缺失时，必须配 `isNA()` |
| 名称可选 | `create()` 无名称，`nameAt()` 返回 `""` |
| 分类水平顺序 | 按首次出现顺序，不按字典序 |
| CSV 文件读取 | `fromCsvFile` 用系统文件接口读取，路径按当前工作目录解析 |
| 跨模块传参 | 引擎侧接口接 `List<Float32>`/`List<string>`；先把结构用 `values()`/`counts()`/`levels()` 导出再传 |
| 精度 | 全部 Float32；超大数量级累加会丢精度 |
| 内存 | 结构本身是普通对象，画布等原生块用毕仍需 `free()` |

---

## 4. 配套渲染

这些结构可直接经 SimGameEngine 的 `RDataChart` 映射成图表并上屏，见
`../SimGameEngine/rdata-chart.md`；QT 示例工程在 `SLangCore/samples/GameTest/RDataGallery/`。
