# SLang StatsPlot · 数据整合与统计绘图设计文档集

- 模块：`SLang.StatsPlot`（namespace `StatsPlot`，标准库形态模块）
- 代码根：`SlangAllInOne/SLangCore/Lib/SLang/StatsPlot/`
- 一句话目标：**让 SLang 像 R 一样整合数据、描述统计，并把聚合结果以多种图形显示出来**
  —— `DataFrame`（等价 R `data.frame`）承载列式数据 → `Stats`（等价 R 基元统计函数）做描述统计与分组聚合
  → `Plot`（等价 R 基元绘图 `barplot/hist/pie/boxplot/plot` 家族）绘制 6 种图表 → `PlotIo` 输出
  （ASCII 预览 / RGBA 像素块，复用 slQT 的 `QLabel.setPixmapRgba` 上屏，未来接 SLangImage 存 PNG）。
- 版本：v0.1（2026-11-21 起；模块自身版本见 `StatsPlot.jsonc`，R17 独立演进）
- 状态：✅ 已落地（数据层 + 统计层 + 6 图表 + headless 测试）；GUI 上屏与 PNG 落盘为演进项（见 01 设计 §7）

---

## 0. 文档集索引

| 编号 | 文件 | 内容 | 主要读者 |
|---|---|---|---|
| 00 | `00-Index.md`（本文） | 文档集索引、一句话目标、状态、阅读顺序 | 全员必读 |
| 01 | `01-Design.md` | R 特性映射、架构分层、关键设计决策、API 一览、落地分期 | 架构 / 实现 |
| 02 | `02-Usage.md` | **使用文档**：数据整合、统计函数、六图表、输出通道、已知限制（R21 纯用法） | SL 使用者 |

阅读顺序：**00 → 02（先用起来）→ 01（想了解内部再读）**。

## 1. 与仓库既有模块的关系

| 相关物 | 关系 |
|---|---|
| `slQT`（`Lib/SLang/QT/`） | 图表上屏显示通道：`StatsPlot.PlotCanvas.pixelPtr()` 产出的 RGBA8 像素块可直接喂 `SLang.QLabel.setPixmapRgba(ptr, w, h)`（RenderTest Phase B 同款已验证通道）。StatsPlot 自身**不 import slQT**，保持零 GUI 依赖 |
| `SLangImage`（`Lib/SLang/Image/`） | 演进项：v1 之后把 `PlotCanvas` 落盘 PNG/JPEG（`Image.ImageIO.save` 消费 RGBA8 像素） |
| `Math` | 绘图椭圆/饼图切片的三角函数来自 `Mathf.cos/sin`；统计计算本身纯 SL |
| `R` / Python `pandas+matplotlib` | 本模块的参照系：**API 与语义对齐 R 基元**（`data.frame`、`mean/median/sd/quantile/table`、`barplot/hist/pie/boxplot/plot`），命名遵循 SLang 既有 camelCase 风格 |

## 2. 快速上手（详见 02-Usage.md）

```sl
import Std;
import StatsPlot;

# 1) 整合数据（等价 R data.frame；v0.1 仅数值列）
StatsPlot.DataFrame df = StatsPlot.DataFrame.fromCsv(
    "city,sales,profit\n" +
    "1,10,2.5\n" +
    "2,20,3.0\n" +
    "1,15,4.5\n" )

# 2) 描述统计（等价 R summary(df)）
StatsPlot.DataFrame s = df.summary()

# 3) 分组聚合（等价 R aggregate / dplyr summarise）
StatsPlot.DataFrame g = df.groupBy( "city" ).summarise( "sales", "sum" )

# 4) 绘图（等价 R barplot(df$sales)）
StatsPlot.PlotCanvas c = StatsPlot.Plot.barplot( df.column( "sales" ), null, "Sales by city" )

# 5) 输出：终端 ASCII 预览（无头测试/CI）/ GUI 上屏
string txt = StatsPlot.PlotIo.ascii( c )
# label.setPixmapRgba( c.pixelPtr(), c.width(), c.height() )   # slQT 窗口显示
```

## 3. 目录结构

```
StatsPlot/
├── StatsPlot.jsonc            # 编译清单（compileFiles + references + struct 登记）
├── StatsPlot.sp               # 模块工程入口（同 Image/SimGameEngine 形态）
├── Stats.sl                   # 描述统计与分布（mean/median/sd/quantile/cor/table…）
├── DataFrame.sl               # 列式数据表 + 分组聚合（DataFrame / StatsGroup）
├── PlotCanvas.sl              # RGBA8 软光栅画布 + 图元 + 内置 3×5 位图字体
├── Plot.sl                    # 六种图表工厂（barplot/lineplot/scatter/histogram/pie/boxplot）
├── PlotIo.sl                  # 输出与预览（ascii / pixelPtr / nonWhite 统计）
├── doc/                       # 本文档集
└── （使用测试在 SLangCore/test/Other/StatsPlotTest/）
```

## 4. 关键数字

- **零原生依赖**：模块全部为纯 SL（仅引用 Core/Std/Math），无需新增 C 源码、无需 dllImports/vmDlls
- **默认画布** 720×480，RGBA8 top-down，alpha 恒 255（与 `QLabel.setPixmapRgba` 契约一致）
- **内置字体** 3×5 位图（ASCII 48 字形：数字 + 大写字母 + `-.%:/+,()=#`；小写自动大写）
- **统计函数** Float32 输入输出（SL 主数值型），分位数为 R type-7 线性插值