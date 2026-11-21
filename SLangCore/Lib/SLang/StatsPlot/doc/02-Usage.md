# StatsPlot · 02 使用文档

- 所属文档集：`SLangCore/Lib/SLang/StatsPlot/doc/`（00 索引 · 01 设计 · **02 用法**）
- 面向读者：写 SL 代码做数据分析/图表的人。本文只讲「怎么用」，不涉及内部实现。
- 模块名：`SLang.StatsPlot`（引用时 `import StatsPlot;`，类名带 `StatsPlot.` 前缀）。

---

## 1. 快速上手

```sl
import Std;
import StatsPlot;

# ── 1) 整合数据（R data.frame 等价物；v0.1 仅数值列）──────
StatsPlot.DataFrame df = StatsPlot.DataFrame.fromCsv(
    "city,sales,profit\n" +
    "1,10,2.5\n" +
    "2,20,3.0\n" +
    "1,15,4.5\n" )

# ── 2) 描述统计（R summary）────────────────────────────
StatsPlot.DataFrame s = df.summary()          # 6 行 = min/q1/median/mean/q3/max

# ── 3) 分组聚合（R aggregate / dplyr summarise）────────
StatsPlot.DataFrame g = df.groupBy( "city" ).summarise( "sales", "sum" )

# ── 4) 绘图（R barplot）────────────────────────────────
StatsPlot.PlotCanvas c = StatsPlot.Plot.barplot( df.column( "sales" ), null, "Sales by city" )

# ── 5) 输出 ────────────────────────────────────────────
string txt = StatsPlot.PlotIo.ascii( c )       # 终端/日志预览
# 窗口显示（接入 slQT 工程后）：
# SLang.QLabel label = ...;  label.setPixmapRgba( c.pixelPtr(), c.width(), c.height() )
c.free()
```

---

## 2. 数据整合（DataFrame）

### 2.1 三种构造方式

```sl
# 方式一：CSV 文本（首行是列名，分隔符可指定，默认逗号）
StatsPlot.DataFrame df3 = StatsPlot.DataFrame.fromCsv( "a,b\n1,2\n3,4\n" )

# 方式二：列式构造（R data.frame；create + addColumn）
List<string> names = List<string>()
names.add( "x" )
names.add( "y" )
StatsPlot.DataFrame df = StatsPlot.DataFrame.create( names )
List<Float32> cx = List<Float32>()
cx.add( 1.0f ).add( 2.0f ).add( 3.0f )
List<Float32> cy = List<Float32>()
cy.add( 10.0f ).add( 20.0f ).add( 30.0f )
df.addColumn( "x", cx )
df.addColumn( "y", cy )
# df.rowCount() == 3, df.colCount() == 2
```

- CSV 数值按 Float32 解析；空行跳过；每列必须等长（否则多出的行丢弃）。
- 全部**数值列**，无字符串列（v0.1）。
- `fromColumns/fromRows` 为模块内部工具：嵌套泛型参数在跨模块调用时 IR 链接不可解析（见 01-Design §5.2），列式构造请用 `create+addColumn`；`List.add` 返回 void 不能链式。
- `List[i]` 下标在部分上下文受限，跨模块数据读取请先取局部列再 `_getItem_( i )`（示例见 2.3）。

### 2.2 读取与切片

```sl
Int32 nrow    = df.rowCount()                 # R nrow
Int32 ncol    = df.colCount()                 # R ncol
List<string> nms = df.names()                 # R names(df)
List<Float32> xs = df.column( "x" )           # R df$x
List<Float32> x0 = df.columnAt( 0 )           # R df[[1]]
bool ok = df.has( "x" )                       # 列是否存在
StatsPlot.DataFrame h2 = df.head( 2 )         # 前 2 行（默认 6）
StatsPlot.DataFrame tl = df.tail( 2 )         # 后 2 行
List<Float32> row0 = df.rowValues( 0 )        # 第 0 行各列值
```

### 2.3 筛选与排序

```sl
# 筛选：给定与行数等长的布尔列表（R 逻辑下标）
List<Float32> col = df.column( "x" )          # 先取局部列（跨模块下标访问须用 _getItem_）
List<bool> which = List<bool>()
for i = 0, i < df.rowCount(), i = i + 1
{
    which.add( col._getItem_( i ) > 1.5f )
}
StatsPlot.DataFrame big = df.filter( which )

# 排序：按某列升/降序重排行
StatsPlot.DataFrame asc = df.sortBy( "x", false )
StatsPlot.DataFrame des = df.sortBy( "x", true )
```

> 注意（SLang 语言规则）：`list[i]` 的索引必须是局部变量，字段/表达式下标在部分场景解析失败——
> 上面循环里先取列存局部 `List<Float32> col = df.column("x")` 再 `col[i]` 是最稳写法。

### 2.4 描述统计 summary（R summary）

```sl
StatsPlot.DataFrame s = df.summary()
# 返回 6 行 × (1 + 列数) 表：行名为 statistic（min/q1/median/mean/q3/max），
# 每数据列一列。可继续用 s.column("sales") 等取数值。
```

### 2.5 分组聚合（R aggregate）

```sl
StatsPlot.StatsGroup g = df.groupBy( "city" )     # 按列分组（键按出现序）
Int32 k = g.keyCount()                            # 分组数
Float32 k0 = g.keyAt( 0 )                         # 第 0 组键值
Int32  n  = g.sizeOf( 0 )                         # 第 0 组行数
Float32 m0 = g.mean( 0, "sales" )                 # 第 0 组 sales 均值

# 一键产出新表（列：key + result）；func ∈ count/sum/mean/min/max/median/sd
StatsPlot.DataFrame gs = df.groupBy( "city" ).summarise( "sales", "mean" )
```

### 2.6 频数表（R table）

```sl
# 向量频数（值升序）
StatsPlot.DataFrame t1 = StatsPlot.Stats.table( df.column( "city" ) )
# DataFrame 列直接出表（内部同 table）
StatsPlot.DataFrame t2 = df.tableOf( "city" )
# 返回 DataFrame：列 "value"（键）+ "count"（频数）
```

---

## 3. 统计函数（Stats）

全部输入输出 Float32；空列表返回 0；`quantile` 的 p 取 [0,1]，线性插值（R type-7）。

```sl
List<Float32> v = List<Float32>()
v.add( 2.0f ).add( 4.0f ).add( 4.0f ).add( 4.0f ).add( 5.0f ).add( 5.0f ).add( 7.0f ).add( 9.0f )

Float32 mu  = StatsPlot.Stats.mean( v )        # 5.0
Float32 med = StatsPlot.Stats.median( v )      # 4.5
Float32 sdv = StatsPlot.Stats.sd( v )          # ≈ 2.138（样本标准差 n-1）
Float32 q1  = StatsPlot.Stats.quantile( v, 0.25f )   # 4.0
Float32 q3  = StatsPlot.Stats.quantile( v, 0.75f )   # 6.5

List<Float32> ps = List<Float32>()
ps.add( 0.25f ).add( 0.5f ).add( 0.75f )
List<Float32> qs = StatsPlot.Stats.quantiles( v, ps )

Float32 r = StatsPlot.Stats.correlation( x, y )     # cor(x,y)，Pearson
List<Int32> idx = StatsPlot.Stats.order( v, false ) # R order：升序索引

List<Float32> brk = StatsPlot.Stats.histBreaks( v, 0 )  # bins=0 → Sturges 自动分箱
List<Int32> cnt  = StatsPlot.Stats.histCounts( v, 0 )
```

---

## 4. 六种图表（Plot）

- 默认画布 720×480；`title` 可传空串省略标题。
- 坐标轴自动取数据范围 + 5 档刻度；数值标签整形不补小数、非整显示 2 位小数。
- 颜色自动走 R 默认调色板（black/red/green3/blue/cyan/magenta/yellow/gray，循环）。
- 返回的 `PlotCanvas` 用毕调 `free()` 释放原生像素缓冲。

```sl
# 柱状图（R barplot，自带数值标签）
List<string> labels = List<string>()
labels.add( "A" )
labels.add( "B" )
labels.add( "C" )
StatsPlot.PlotCanvas c1 = StatsPlot.Plot.barplot( df.column( "sales" ), labels, "Sales" )

# 折线图（R plot(type="l")）
StatsPlot.PlotCanvas c2 = StatsPlot.Plot.lineplot( df.column( "sales" ), "Sales trend" )

# 散点图 + 最小二乘拟合线（R plot + abline(lm(y~x))，拟合线红色细线）
StatsPlot.PlotCanvas c3 = StatsPlot.Plot.scatter( xs, ys, "xy" )

# 直方图（R hist；bins=0 自动 Sturges）
StatsPlot.PlotCanvas c4 = StatsPlot.Plot.histogram( df.column( "age" ), 0, "Age" )

# 饼图（R pie；右侧图例列标签，无标签时显示百分占比）
StatsPlot.PlotCanvas c5 = StatsPlot.Plot.pie( df.column( "sales" ), labels, "Share" )

# 箱线图（R boxplot；每组一箱：min~max 须线 + Q1~Q3 箱 + 中位线）
# 组数据以“扁平向量 + 分组计数”传入（嵌套泛型参数跨模块调用受限）
List<Float32> flat = List<Float32>()
# ... 把各组数值顺序 append 进 flat ...
List<Int32> sizes = List<Int32>()
sizes.add( g1n )   # 第 1 组长度
sizes.add( g2n )   # 第 2 组长度
List<string> glabels = List<string>()
glabels.add( "A" )
glabels.add( "B" )
StatsPlot.PlotCanvas c6 = StatsPlot.Plot.boxplot( flat, sizes, glabels, "Groups" )
```

---

## 5. 输出通道

### 5.1 终端 ASCII 预览（无头/CI 主力）

```sl
string txt = StatsPlot.PlotIo.ascii( c )
Console.println( txt )     # 每列取“自底部首个非白像素”高度，映射 ` .:-=+*#%@` 10 级
```

### 5.2 窗口显示（接入 slQT 的工程）

```sl
# PlotCanvas 的 RGBA8 像素块直接上屏（与 RenderTest 同款通道，Qt 后端有效）
label.setPixmapRgba( c.pixelPtr(), c.width(), c.height() )
```

- 需要先有 slQT 窗口（`SLang.QApplication` + `QLabel`），且 `slang_qt.dll` 为真实 Qt 后端
  （stub 后端 `setPixmapRgba` 返回 false）。

### 5.3 测试断言辅助

```sl
Int32 n = c.nonWhiteCount( 0, 0, c.width(), c.height() )   # 非白像素总数
bool  b = c.pixelIs( 100, 200, c.rgb( 255, 0, 0 ) )        # 单点颜色断言
Int32 col = c.palette( 0 )                                  # 调色板取色
```

---

## 6. 已知限制与注意事项

| 限制 | 说明/规避 |
|---|---|
| 仅数值列 | DataFrame 暂不支持字符串列；类别数据先按值编码，字符串分组留待 v1 |
| Float32 精度 | 统计结果 Float32；超大数量级累加可能丢精度，常规分析无碍 |
| 内存 | 画布像素缓冲为原生内存，**用毕必须 `free()`**（如后续不再显示/保存） |
| 字体 | 内置 3×5 位图：数字/大写字母（小写自动转大写）/符号 `-.%:/+,()=#`；不支持中文与其它字符 |
| 分组键排序 | `tableOf` 频数表按键值升序；`groupBy` 键按出现顺序 |
| 箱线图离群点 | v0.1 不绘制离群点（须线覆盖全数据范围） |
| 无交互 | 图表为静态位图，无缩放/悬停 |

## 7. 构建与测试

```powershell
# 编译模块（产物 → out/export/StatsPlot/）
dotnet run --no-launch-profile --project simple_language\source\SimpleLanguageFront.csproj -- `
  compile -p SlangAllInOne\SLangCore\Lib\SLang\StatsPlot\StatsPlot.jsonc -e ir --no-banner --format binary+json

# 无头端到端测试（断言型，全平台可跑）
dotnet run --no-launch-profile --project SlangAllInOne\Project\CSimpleVMTest\CSimpleVMTest.csproj -- `
  SlangAllInOne\SLangCore\test\Other\StatsPlotTest\ProjectTest.jsonc
```