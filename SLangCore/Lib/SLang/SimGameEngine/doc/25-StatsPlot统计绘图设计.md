# 25 · StatsPlot 合并入引擎：统计与绘图设计说明

> 状态：【已落盘】原独立模块 `SLang.StatsPlot` 五件源码整建制迁入 `SimGameEngine/stats/`，
> 保留 `namespace StatsPlot`，零源码改动；第 24 套 `SimStatsPlotTest` 66/66。
> 使用文档（R21 纯用法）：`md/lib/SimGameEngine/statsplot.md`。
> 本文面向实现者与评审；使用者直接看使用文档。

- 版本：v2.22（2026-11-23 合并入引擎；原模块 v0.1 起于 2026-11-21）
- 本文面向**模块实现者与评审**：R 特性映射、架构分层、关键设计决策 D1-D8、API 一览、测试策略、落地分期。
  使用者请直接看 `02-Usage.md`。

---

## 1. 目标与非目标

### 1.1 目标

| 目标 | 说明 |
|---|---|
| R 式数据整合 | `DataFrame` 列式数据表（R `data.frame`）：构造（列/行/CSV）、取列、切片、筛选、排序、分组聚合、频数表、`summary` 描述统计 |
| R 式描述统计 | `Stats` 基元函数：`mean/median/sum/min/max/sd/var/range/quantile/cor/cov/order/table/hist`（对齐 R base） |
| 多种图形显示 | `Plot` 工厂生成六种图表：柱状、折线、散点、直方图、饼图、箱线图（对齐 R base 图形族） |
| 无头可用 | `PlotIo.ascii` 终端预览 + 画布像素断言，全程 CI/无窗体可验证 |
| 复用既有显示通道 | RGBA8 像素块直接喂 slQT `QLabel.setPixmapRgba`（RenderTest Phase B 已验证路径），不新造 GUI 机制 |
| 零原生依赖 | 纯 SL 实现，仅引用 Core/Std/Math；不动 C VM / Front 一行 |

### 1.2 非目标（明确不做）

- **不做 R 解释器/翻译器**：不解析 R 语法、不做 `$`/`[i,]` 切片语法糖——SLang 里一律方法调用（`df.column("x")`）
- **不做 ggplot2 语法**：v0.1 为单一图表工厂（一次一图），不做图形对象层叠（`+ layer`）
- **不做交互式绘图**：无缩放/悬停提示；SVG/HTML 导出留待后续
- **不做字符串列**：v0.1 DataFrame 仅数值列（Float32）；分组键用数值列（类别数据可按值编码，或将字符串分组留待 v1）
- **不接 C VM 绘图后端**：本模块像素级软光栅自给自足，与 `SLangRender`（3D 管线）无耦合

---

## 2. R 特性映射表（本模块的设计参照系）

| R 概念 | R 示例 | SLang StatsPlot 形态 |
|---|---|---|
| 数据框 | `df <- data.frame(a=c(1,2), b=c(3,4))` | `DataFrame.fromColumns(names, cols)` |
| 读 CSV | `read.csv("x.csv")` | `DataFrame.fromCsv(text)` |
| 取列 | `df$a` / `df[["a"]]` | `df.column("a")` |
| 行数/列数 | `nrow(df)` / `ncol(df)` | `df.rowCount()` / `df.colCount()` |
| 头部/尾部 | `head(df, n)` / `tail(df, n)` | `df.head(n)` / `df.tail(n)` |
| 逻辑下标筛选 | `df[df$a > 1, ]` | `df.filter(which)`（which = List<bool>，与列等长） |
| 排序 | `df[order(df$a), ]` | `df.sortBy("a", desc)` |
| 描述统计 | `summary(df)` | `df.summary()`（返回 DataFrame：行=统计量） |
| 分组键 | `split(df, df$g)` | `df.groupBy("g")` → `StatsGroup` |
| 聚合 | `aggregate(df$v, list(df$g), mean)` | `StatsGroup.summarise("v", "mean")` → DataFrame |
| 频数表 | `table(x)` | `Stats.table(v)` / `DataFrame.tableOf("col")` → DataFrame |
| 统计函数 | `mean/median/sd/var/range/quantile/cor/cov` | `Stats.*` 同名静态函数 |
| 排序索引 | `order(x)` | `Stats.order(v, desc)` → List<Int32> |
| 直方图分箱 | `hist(x, breaks=n)$counts` | `Stats.histBreaks(v, n)` / `Stats.histCounts(v, n)` |
| 柱状图 | `barplot(v, names.arg=n)` | `Plot.barplot(values, labels, title)` |
| 折线图 | `plot(x, y, type="l")` | `Plot.lineplotXY(xs, ys, title)` / `Plot.lineplot(ys, title)` |
| 散点图 | `plot(x, y)` / `abline(lm(y~x))` | `Plot.scatter(xs, ys, title)`（默认带最小二乘拟合线） |
| 直方图 | `hist(x)` | `Plot.histogram(values, bins, title)` |
| 饼图 | `pie(x, labels=n)` | `Plot.pie(values, labels, title)` |
| 箱线图 | `boxplot(groups)` | `Plot.boxplot(groups, labels, title)` |
| 调色板 | `palette()` | `PlotCanvas.palette(i)`（R 默认 8 色） |

---

## 3. 架构分层

```
SL 应用（SLang 脚本）
   │  import StatsPlot
   ▼
L3 图表层  Plot（六种图表工厂，纯静态函数：数据 → PlotCanvas）
   │
L2 画布层  PlotCanvas（RGBA8 软光栅：fillRect/line/polygon/circle/drawText）
   │         内置 3×5 位图字体（数字/大写字母/符号，免字体依赖）
   │
L1 统计层  Stats（描述统计/分布/相关，纯函数）
   │         跨整 DataFrame：summary / filter / sortBy / groupBy+summarise
   ▼
L0 数据层  DataFrame（列式存储：List<string> 列名 + List<List<Float32>> 列数据）
   │
输出通道  PlotIo.ascii（终端）│ pixelPtr() → slQT QLabel.setPixmapRgba（GUI，v1 演进）
         │（演进）→ SLangImage save（PNG/JPEG 落盘）
```

依赖规则：仅上层引用下层、层间静态方法调用；`Plot` → `PlotCanvas` →（无）→ `Stats`/`DataFrame`。
`Plot.sl` 因饼图/椭圆需三角函数而 `import Math`（`Mathf.cos/sin`）；其余文件只 `import Core/Std`。

**数据流**：`原始数据 → DataFrame（整合/筛选/分组） → 数值向量 → Plot.* 采样布局 → PlotCanvas
（绘制图元+坐标轴+刻度+标题） → 输出（ASCII 预览 / RGBA8 像素块上屏）`。

---

## 4. 关键设计决策

- **D1 纯 SL 实现，零原生依赖（v0.1 硬约束）**。统计与绘图均为计算密集但结构简单的纯函数，
  无跨语言收益；保持模块可单文件编译、无 dllImports/vmDlls（R6 新 .c 登记链完全回避）、
  任意平台可构建运行（wasm/无头同样可用）。代价：无抗锯齿、无系统字体，由 D4 内置字体兜底。
- **D2 画布 = Memory 原生缓冲（RGBA8 top-down，alpha=255）**。`Memory.alloc` 分配、
  `Memory.writeI8/readUInt8` 逐字节读写；`pixelPtr()` 直接返回缓冲地址——与史已验证的
  `QLabel.setPixmapRgba(ptr, w, h)` 契约（RenderTest Phase B）完全一致，上屏零拷贝。
  测试侧经 `nonWhiteCount(x0,y0,x1,y1)` 区域统计断言绘图结果。
- **D3 内置 3×5 位图字体**。字号小（轴标签/图例足够清晰）、数据体积小（48 字形 × 5 行 × 3 bit /
  字母表），免系统字体依赖，平台一致性最好。标签渲染时小写字母自动大写。
- **D4 图表布局常量集中化**（`Plot` 私有静态常量：边距 left=56/right=14/top=30/bottom=34，
  刻度 5 档、调色板 8 色与 R `palette()` 对齐：black/red/green3/blue/cyan/magenta/yellow/gray）。
  `fmtNum` 数值标签格式器：整数值不补小数、非整精确到 2 位小数。
- **D5 一律静态工厂 + 返回实体**。`Plot.*`、`DataFrame.from*`、`Stats.*` 全是
  `public static` 函数，不保留内部可变全局状态——可重入、可断言、可并行调用。
- **D6 统计语义对齐 R base**：样本标准差/方差（`n-1` 分母）、`quantile p ∈ [0,1]` 用 R type-7
  线性插值（p=0.5 即中位数）、`table` 按值升序、分组键按出现序排列。
- **D7 DataFrame 数值列一律 `List<Float32>`**：SL 主数值型，泛型容器支持已实证
  （`List<Float32>` 用于 Tensora Trainer）。数值输入统一经 `SystemConvertFloat32` 归一。
- **D8 边界防御从简**：空列/行列计数为 0 → 统计返回 0、绘图返回空白画布；不抛异常。
  绘制坐标越界钳制到画布（含负坐标安全写）。

---

## 5. API 一览（v0.1 全量）

### 5.1 `StatsPlot.Stats`（R base 统计函数，全静态）

| 方法 | 签名 | 对应 R |
|---|---|---|
| `sum` | `Float32(List<Float32>)` | `sum` |
| `mean` | `Float32(List<Float32>)` | `mean` |
| `minValue` | `Float32(List<Float32>)` | `min` |
| `maxValue` | `Float32(List<Float32>)` | `max` |
| `median` | `Float32(List<Float32>)` | `median` |
| `variance` | `Float32(List<Float32>)` | `var`（样本，n-1） |
| `sd` | `Float32(List<Float32>)` | `sd` |
| `quantile` | `Float32(List<Float32>, Float32 p)` | `quantile(x, p, type=7)` |
| `quantiles` | `List<Float32>(List<Float32>, List<Float32> ps)` | `quantile(x, probs)` |
| `covariance` | `Float32(x, y)` | `cov` |
| `correlation` | `Float32(x, y)` | `cor` |
| `order` | `List<Int32>(List<Float32>, bool desc)` | `order`（升/降序索引） |
| `histBreaks` | `List<Float32>(List<Float32>, Int32 bins)` | `hist$breaks` |
| `histCounts` | `List<Int32>(List<Float32>, Int32 bins)` | `hist$counts` |
| `toFloats` | `List<Float32>(List<Int32>)` | —（Int32 向量归一） |

### 5.2 `StatsPlot.DataFrame`（R data.frame）

| 方法 | 签名 | 对应 R |
|---|---|---|
| `fromCsv` | `DataFrame(string text)` / `DataFrame(string text, string sep)` | `read.csv`（首行表头） |
| `create` | `DataFrame(List<string> names)` | 空表（列名），配 `addColumn` 列式构造 |
| `addColumn` | `void(string name, List<Float32> values)` | 列追加 |
| `fromColumns` | `DataFrame(List<string>, List<List<Float32>>)` | **模块内部工具**：嵌套泛型参数跨模块 IR 链接不可解析，消费方用 `create+addColumn` 或 `fromCsv` |
| `fromRows` | `同 fromColumns 形态` | 同上（内部） |
| `names` | `List<string>()` | `names(df)` |
| `nameAt` | `string(Int32 i)` | — |
| `column` | `List<Float32>(string name)` | `df$name` |
| `columnAt` | `List<Float32>(Int32 i)` | `df[[i]]` |
| `has` | `bool(string name)` | `name %in% names(df)` |
| `rowCount` / `colCount` | `Int32()` | `nrow` / `ncol` |
| `head` / `tail` | `DataFrame(Int32 n)` | `head` / `tail` |
| `filter` | `DataFrame(List<bool> which)` | `df[which, ]` |
| `sortBy` | `DataFrame(string name, bool desc)` | `df[order(df$name), ]` |
| `summary` | `DataFrame()` | `summary(df)`（行：min/Q1/median/mean/Q3/max） |
| `groupBy` | `StatsGroup(string name)` | `split` |
| `tableOf` | `DataFrame(string name)` | `table(df$name)` |
| `rowValues` | `List<Float32>(Int32 r)` | `df[r, ]` |

### 5.3 `StatsPlot.StatsGroup`（分组聚合，R aggregate）

| 方法 | 签名 | 说明 |
|---|---|---|
| `keyCount` | `Int32()` | 分组数 |
| `keyAt` | `Float32(Int32 ki)` | 第 ki 组键值 |
| `sizeOf` | `Int32(Int32 ki)` | 该组行数 |
| `sum` / `mean` / `minValue` / `maxValue` / `median` | `Float32(Int32 ki, string colName)` | 组内聚合原语 |
| `summarise` | `DataFrame(string valueCol, string func)` | func ∈ count/sum/mean/min/max/median/sd；返回 DataFrame（列：key + result） |

### 5.4 `StatsPlot.PlotCanvas`（软光栅画布）

| 方法 | 签名 | 说明 |
|---|---|---|
| `create` | `PlotCanvas(Int32 w, Int32 h)` | 白底 RGBA8 缓冲 |
| `width` / `height` | `Int32()` | — |
| `pixelPtr` | `Int64()` | RGBA8 缓冲地址（上屏/落盘通道） |
| `free` | `void()` | 释放原生缓冲（用毕调用） |
| `rgb` | `Int32(Int32 r, Int32 g, Int32 b)` | 打包色 0xRRGGBB |
| `redOf` / `greenOf` / `blueOf` | `Int32(Int32 c)` | 解包 |
| `palette` | `Int32(Int32 i)` | R 默认 8 色（i%8） |
| `setPixel` | `void(Int32 x, Int32 y, Int32 c)` | 单点（越界钳制） |
| `pixelAt` | `Int32(Int32 x, Int32 y)` | 读打包色（越界返回 -1） |
| `pixelIs` | `bool(Int32 x, Int32 y, Int32 c)` | 断言单点 |
| `nonWhiteCount` | `Int32(Int32 x0, Int32 y0, Int32 x1, Int32 y1)` | 区域非白像素计数（测试断言主通道） |
| `fill` | `void(Int32 c)` | 全画布填充 |
| `fillRect` | `void(Int32 x, Int32 y, Int32 w, Int32 h, Int32 c)` | 实心矩形 |
| `rectBorder` | `void(Int32 x, Int32 y, Int32 w, Int32 h, Int32 c)` | 边框矩形 |
| `line` | `void(Int32 x0, Int32 y0, Int32 x1, Int32 y1, Int32 c)` | Bresenham |
| `polyline` | `void(List<Float32> xs, List<Float32> ys, Int32 c)` | 多段线（坐标取整） |
| `polygonFilled` | `void(List<Float32> xs, List<Float32> ys, Int32 c)` | 扫描线多边形填充（饼图切片/箱体） |
| `circleFilled` | `void(Int32 cx, Int32 cy, Int32 r, Int32 c)` | 实心圆 |
| `text` | `void(Int32 x, Int32 y, string s, Int32 c)` | 3×5 位图文本（小写自动大写） |

### 5.5 `StatsPlot.Plot`（图表工厂，全静态；默认画布 720×480）

| 方法 | 签名 | 对应 R |
|---|---|---|
| `barplot` | `PlotCanvas(List<Float32> values, List<string> labels, string title)` | `barplot` |
| `barplot` | `PlotCanvas(List<Float32> values)` | `barplot`（无标签） |
| `lineplot` | `PlotCanvas(List<Float32> values, string title)` | `plot(x, type="l")` |
| `lineplotXY` | `PlotCanvas(List<Float32> xs, List<Float32> ys, string title)` | `plot(x, y, type="l")` |
| `scatter` | `PlotCanvas(List<Float32> xs, List<Float32> ys, string title)` | `plot(x, y)` + `abline(lm(y~x))` |
| `histogram` | `PlotCanvas(List<Float32> values, Int32 bins, string title)` | `hist`（bins=0 走 Sturges） |
| `pie` | `PlotCanvas(List<Float32> values, List<string> labels, string title)` | `pie`（图例列表） |
| `boxplot` | `PlotCanvas(List<Float32> flat, List<Int32> sizes, List<string> labels, string title)` | `boxplot`（组数据扁平拼接 + 分组计数） |

### 5.6 `StatsPlot.PlotIo`（输出）

| 方法 | 签名 | 说明 |
|---|---|---|
| `ascii` | `string(PlotCanvas c)` | 终端预览：按列取「自底部到首个非白像素」的高度，映射 10 级灰度字符 ` .:-=+*#%@`；长画布自动抽列 |
| `heightProfile` | `List<Int32>(PlotCanvas c)` | 每列首个非白像素行号（测试/自绘用） |

---

## 6. 测试策略（`SLangCore/test/Other/StatsPlotTest/`）

- **统计断言**（固定样本手工算值）：[1,2,3,4] → mean 2.5、median 2.5；[2,4,4,4,5,5,7,9] →
  sd≈2.1379667；quantile(0.25/0.5/0.75) type-7 手算核对；cor(c(1,2,3), c(2,4,6))=1。
- **DataFrame 断言**：CSV 解析行数列数、取列值、filter/sortBy/head/tail、summary 六行、
  groupBy 各组 count/sum/mean、summarise 结果、tableOf 频数。
- **画布像素断言**：`nonWhiteCount` 区域内阈值（barplot 柱体存在、histogram 分箱柱、lineplot
  线轨迹、pie 中心非白 + 覆盖率、boxplot 箱体填充）；`pixelIs` 抽样点。
- **ascii 断言**：非空、含非空白字符。
- 全程**无头**（不依赖 Qt 后端/窗口），可在 `run-tests-win` / CI 全平台跑。

---

## 7. 落地分期

| 期 | 内容 | 状态 |
|---|---|---|
| v0.1（本文） | DataFrame 数值列 + 描述统计 + 分组聚合 + 6 图表 + ascii 预览 + headless 测试 | ✅ 已落地 |
| v1 | PNG/JPEG 落盘（接 `SLangImage.save`）；字符串列与字符串分组键；`merge/join` 两表合并 | 规划 |
| v2 | ggplot 式图形分层（base 图表 + layer 叠加）；热力图/相关矩阵图；QQ 图；SVG 导出 | 规划 |
| v3 | 交互：缩放/悬停提示；`Plot` 图形对象序列化（可回放/可传输） | 规划 |

> 实施约束回顾：本模块不动 `csimple_lang/` 与 `simple_language/` 任何源码；新增 `.sl` 文件只需
> 登记 `StatsPlot.jsonc` 的 `compileFiles`（模块内 jsonc 唯一登记点，不涉及 R6 C 源双链）。