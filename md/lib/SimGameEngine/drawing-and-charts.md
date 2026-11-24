# SimGameEngine · 基础绘图与图表

> 面向读者：在 SLang 工程里需要画圆、画线、虚线、柱状图、饼图、散点图、函数曲线等图形的人。
> 本文只讲「怎么用」：可用接口、示例、参数与注意事项。
> 引用模块：`import SimGameEngine;`，类直接用类名调用（无需前缀）。
> 平台：跨平台、离屏可用；不需要窗口、不需要额外原生库。

---

## 1. 一分钟上手

```sl
import SimGameEngine;
import Std;

# 1) 建一张画布（RGBA8，顶行在前，默认白色）
DrawCanvas canvas = DrawCanvas.create( 640, 480 )

# 2) 画基础图元
canvas.line( 20, 20, 200, 20, DrawTypes.red() )
canvas.dashedLine( 20, 40, 200, 40, DrawTypes.black(), 10, 6 )
canvas.circle( 120, 140, 50, DrawTypes.blue() )
canvas.fillCircle( 260, 140, 40, DrawTypes.palette( 2 ) )

# 3) 画图表（返回新画布）
List<Float32> v = List<Float32>()
v.add( 3.0f )
v.add( 7.0f )
v.add( 5.0f )
List<string> labels = List<string>()
labels.add( "A" )
labels.add( "B" )
labels.add( "C" )
DrawCanvas chart = DrawChart.barplot( v, labels, DrawChart.par() )

# 4) 输出：窗口上屏 / 转纹理 / 维护原生像素块
# label.setPixmapRgba( chart.pixelPtr(), chart.width(), chart.height() )
# SLang.RenderTexture tex = chart.toTexture()

# 5) 用完释放
canvas.free()
chart.free()
```

---

## 2. 画布 DrawCanvas

### 2.1 生命周期

| 方法 | 说明 |
|---|---|
| `DrawCanvas.create(w, h)` | 创建 w×h 的 RGBA8 画布，初值白色；尺寸<=0 返回未就绪画布 |
| `width()` / `height()` | 画布像素尺寸 |
| `pixelPtr()` | 原生像素块地址（给上屏接口用） |
| `isReady()` | 像素缓冲是否有效 |
| `free()` | 释放像素缓冲；**用毕必须调用一次** |
| `toTexture()` | 转成 SLang.RenderTexture（top-down RGBA8），失败返回 null |

### 2.2 像素与整块

| 方法 | 说明 |
|---|---|
| `setPixel(x, y, color)` | 写单像素（越界静默忽略） |
| `pixelAt(x, y)` | 读打包颜色；越界返回 -1 |
| `pixelIs(x, y, color)` | 单点颜色断言 |
| `nonWhiteCount(x0,y0,x1,y1)` | 区域内非白像素数（自测常用） |
| `fill(color)` | 整块填色 |

### 2.3 图元

| 方法 | 说明 |
|---|---|
| `line(x0,y0,x1,y1,color)` | Bresenham 直线，含两端 |
| `lineEx(x0,y0,x1,y1,color,style,width)` | 带线型与线宽（style 见 §5） |
| `dashedLine(x0,y0,x1,y1,color,dash,gap)` | 虚线；dash=实段像素，gap=空段像素 |
| `polyline(xs,ys,color)` | 折线；两个 Float32 列表等长 |
| `rect(x,y,w,h,color)` / `fillRect(...)` | 空心 / 实心矩形 |
| `circle(cx,cy,r,color)` / `fillCircle(...)` | 空心 / 实心圆 |
| `ellipse(cx,cy,rx,ry,color)` / `fillEllipse(...)` | 空心 / 实心椭圆 |
| `arc(cx,cy,r,a0,a1,color)` | 圆弧；角度为**弧度**，a1<a0 时反向绘制 |
| `pieSlice(cx,cy,r,a0,a1,color)` | 扇形填充（饼图切片） |
| `polygon(xs,ys,color)` / `fillPolygon(...)` | 空心 / 实心多边形 |
| `text(x,y,str,color)` | 3×5 位图文字；支持数字、大写字母与 `-.%:+/,()=#`，小写自动转大写 |

示例：

```sl
DrawCanvas c = DrawCanvas.create( 300, 200 )
c.fill( DrawTypes.white() )
c.rect( 10, 10, 120, 80, DrawTypes.black() )
c.ellipse( 200, 50, 45, 30, DrawTypes.red() )
c.arc( 150, 140, 40, 0.0f, 1.5707963f, DrawTypes.blue() )
c.text( 10, 180, "DEMO 123", DrawTypes.black() )
```

---

## 3. 图形参数 PlotParams（等价 R par()）

`DrawChart` 的每个图表函数的最后一个参数都可传 `PlotParams`；传 `null` 表示全部取默认值。
`DrawChart.par()` 返回一个新的默认参数对象。

```sl
PlotParams p = DrawChart.par()
p.setSize( 500, 360 )
p.setMargins( 60, 36, 20, 40 )
p.setColors( DrawTypes.black(), DrawTypes.white(), DrawTypes.lightGray(), DrawTypes.palette( 1 ) )
p.setLine( DrawTypes.LTY_DASHED, 2 )
p.setPoint( DrawTypes.PCH_SQUARE, 2 )
p.setPlotType( DrawTypes.PLOT_BOTH )
p.setLabels( "SALES", "MONTH", "AMOUNT" )
p.setXlim( 0.0f, 10.0f )
p.setYlim( 0.0f, 100.0f )
p.setGrid( true, 5 )
p.setLegendPos( DrawTypes.LEGEND_TOPRIGHT )
```

| 方法 | 说明 |
|---|---|
| `setSize(w,h)` | 画布尺寸（64..8192，越界忽略） |
| `setMargins(left,top,right,bottom)` | 四边留白 |
| `setColors(fg,bg,grid,series)` | 前景 / 背景 / 网格 / 主系列色 |
| `setColor(c)` | 只改系列色 |
| `setLine(style,width)` | 线型（§5）与线宽 1..8 |
| `setPoint(symbol,scale)` | 点符号（§5）与大小 1..6 |
| `setPlotType(type)` | `plot()` 的图形类型（§5） |
| `setLabels(main,xlab,ylab)` | 标题与两轴标签 |
| `setXlim(lo,hi)` / `setYlim(lo,hi)` | 固定坐标范围；hi<=lo 会被拒绝并写 `lastError` |
| `autoScale()` | 恢复自动范围 |
| `setGrid(on,count)` | 网格开关与刻度数 2..12 |
| `setLegendPos(pos)` | 图例位置（四角） |

字段可直接读取：`width/height`、`foreground/background`、`main/xlab/ylab`、`grid/ticks`、`lastError` 等。

---

## 4. R 风格图表 DrawChart

### 4.1 统计辅助

```sl
Float32 s  = DrawChart.sum( v )
Float32 mu = DrawChart.mean( v )
Float32 md = DrawChart.median( v )
Float32 q1 = DrawChart.quantile( v, 0.25f )
List<Int32> cnt = DrawChart.histCounts( v, 0 )   # bins=0 自动分箱
```

可用：`sum / minValue / maxValue / mean / sorted / quantile(v,p) / median / histBreaks(v,bins) / histCounts(v,bins)`。
空列表返回 0；分位数为线性插值（R type-7）。

### 4.2 图表工厂（均返回新 DrawCanvas）

```sl
List<Float32> xs = List<Float32>()
xs.add( 0.0f )
xs.add( 1.0f )
xs.add( 2.0f )
List<Float32> ys = List<Float32>()
ys.add( 1.0f )
ys.add( 4.0f )
ys.add( 2.0f )

DrawCanvas a = DrawChart.plot( xs, ys, p )        # 类型由 p.plotType 决定
DrawCanvas b = DrawChart.scatter( xs, ys, p )     # 只画点
DrawCanvas c = DrawChart.curve( xs, ys, p )       # 只连线（函数曲线采样）
DrawCanvas d = DrawChart.plotY( ys, p )           # x = 0,1,2...
DrawCanvas e = DrawChart.hist( ys, 0, p )         # 直方图，0=自动分箱
DrawCanvas f = DrawChart.barplot( ys, labels, p ) # 条形图
DrawCanvas g = DrawChart.boxplot( flat, sizes, labels, p )
DrawCanvas h = DrawChart.pie( ys, labels, p )     # 饼图 + 右侧图例
```

| 函数 | 说明 |
|---|---|
| `plot(xs,ys,p)` | 散点 / 折线 / 点线同绘 / 阶梯，由 `p.plotType` 选择 |
| `plotY(ys,p)` | x 自动取 0..n-1 |
| `scatter(xs,ys,p)` | 强制散点 |
| `curve(xs,ys,p)` | 强制折线；把函数采样点传进来即函数曲线 |
| `hist(values,bins,p)` | 直方图；bins<=0 自动 Sturges 分箱 |
| `barplot(values,labels,p)` | 条形图；labels 可为 null |
| `boxplot(flat,sizes,labels,p)` | 箱线图；`flat` 是各组数据顺序拼接的扁平列表，`sizes[i]` 是第 i 组长度 |
| `pie(values,labels,p)` | 饼图，右侧图例显示标签与百分比 |

函数曲线示例（采样后交给 `curve`）：

```sl
List<Float32> fx = List<Float32>()
List<Float32> fy = List<Float32>()
Int32 i = 0
while i <= 100
{
    Float32 x = SystemConvertFloat32( i ) / 10.0f - 5.0f
    fx.add( x )
    fy.add( x * x )
    i = i + 1
}
DrawCanvas parabola = DrawChart.curve( fx, fy, p )
```

### 4.3 叠加：参考线与图例

在**已生成的图表画布**上继续画：

```sl
DrawCanvas ch = DrawChart.plot( xs, ys, p )
DrawChart.abline( ch, 1.0f, 0.0f, p )   # y = 1*x + 0
List<Int32> colors = List<Int32>()
colors.add( DrawTypes.red() )
colors.add( DrawTypes.blue() )
DrawChart.legend( ch, labels, colors, p )
```

两个函数成功返回 true；画布为 null 或未就绪时返回 false。

---

## 5. 常量速查（DrawTypes）

| 组 | 常量 |
|---|---|
| 线型 | `LTY_SOLID` / `LTY_DASHED` / `LTY_DOTTED` / `LTY_DASHDOT` |
| 点符号 | `PCH_NONE` / `PCH_CIRCLE` / `PCH_SQUARE` / `PCH_PIXEL` |
| plot 类型 | `PLOT_POINTS` / `PLOT_LINES` / `PLOT_BOTH` / `PLOT_STEPS` |
| 图例位置 | `LEGEND_TOPRIGHT` / `LEGEND_TOPLEFT` / `LEGEND_BOTTOMRIGHT` / `LEGEND_BOTTOMLEFT` |
| 常用色（方法） | `black()` / `white()` / `red()` / `green()` / `blue()` / `gray()` / `lightGray()` |
| 调色板 | `palette(i)` — R 默认 8 色循环 |
| 颜色构造 | `rgb(r,g,b)`（各分量自动钳到 0..255）、`redOf/blueOf/greenOf(c)` |

---

## 6. 注意事项与已知限制

| 事项 | 说明 |
|---|---|
| 必须释放画布 | 画布占原生内存；不再使用时对每个画布调一次 `free()`，重复释放安全 |
| `List.add` 不能链式 | `v.add(1.0f).add(2.0f)` 会报错；必须写成两行 |
| 角度单位 | `arc` / `pieSlice` 用弧度，不是角度；可用 `DrawTypes.PI` |
| 文字字形有限 | 内置 3×5 位图只覆盖数字 / 大写字母 / 少量符号，小写自动转大写，不支持中文 |
| 无抗锯齿 | 图元为逐像素软光栅，斜线/圆边缘有锯齿 |
| 浮点转整数 | 若要把计算出的浮点坐标转 Int32，先存成 Float32 局部变量再单独转换，不要把乘除表达式和转换写在同一行 |
| `boxplot` 数据形态 | 组数据必须扁平化传入（flat + sizes），不能直接传「列表的列表」 |
| 图表输出是新画布 | 每个图表函数都新建画布；叠加请用 `abline` / `legend` 在原画布上画 |
| 与 StatsPlot 的关系 | v2.22 起 StatsPlot 已合并入同一引擎（`stats/`），两套接口可混用：数据分析走 `StatsPlot.*`，直接绘图走本章接口 |
