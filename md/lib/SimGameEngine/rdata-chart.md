# SimGameEngine · Std.RData 数据映射与图表

> 面向读者：已用 Std 的 `RData`  structures 整理好数据，想画成图表、生成纹理并显示在 QT 窗口的人。
> 本文只讲「怎么用」；设计取舍见 `SimGameEngine/doc/26-RData映射与图表.md`。
> 引用：`import Std;` + `import SimGameEngine;`。

---

## 1. 核心流程

```sl
import Std;
import SimGameEngine;

# 1) Std 侧准备数据
RData.RTable t = RData.RTable.fromCsvText( "month,sales\n1,10\n2,20\n3,15\n" )
RData.RVector sales = t.columnByName( "sales" )

# 2) 用取值器导出基础列表（跨模块边界）
List<Float32> vals = sales.values()

# 3) 引擎映射成图表画布
DrawCanvas chart = RDataChart.plotVector( vals, "Sales" )

# 4a) QT 上屏（CPU 像素镜像）
label.setPixmapRgba( chart.pixelPtr(), chart.width(), chart.height() )

# 4b) GPU 纹理（同一画布）
var tex = chart.toTexture()

# 5) 用完释放
chart.free()
```

> 关键点：`RenderTexture` 没有 `readPixels`，QT 上屏走的是**同一画布的 CPU 像素块**，
> 不是从 GPU 纹理读回。两者来自同一份数据。

---

## 2. 映射接口总表

| 方法 | 输入 | 产物 |
|---|---|---|
| `RDataChart.plotVector(values, title)` | `List<Float32>`（由 `RVector.values()` 得到） | 480×320 折线/点图 |
| `RDataChart.barFactor(counts, levels, title)` | `List<Float32>` + `List<string>`（由 `RFactor.counts()/levels()` 得到） | 480×320 条形图 |
| `RDataChart.plotSeries(values, start, frequency, title)` | `RTimeSeries` 的三个取值 | 折线图，标题带时间轴参数 |
| `RDataChart.plotCsvColumn(values, columnName, title)` | `RTable` 列取值 + 列名 | 列图表；`values == null` 返回提示画布 |
| `RDataChart.plotForecast(mean, lower, upper, title)` | `RForecast` 三条序列 | **560×360 置信带预测图** |

所有接口返回 `DrawCanvas`，用毕调 `free()`。

---

## 3. 预测图示例

```sl
RData.RForecast fc = RData.RForecast.fromLists( mu, lo, hi )
List<Float32> m = fc.meanValues()
List<Float32> l = fc.lowerValues()
List<Float32> u = fc.upperValues()
DrawCanvas c = RDataChart.plotForecast( m, l, u, "Demand forecast" )
```

图中：灰色竖条 = 上下界之间的置信带，实线 = 点预测，虚线 = 上下界，左侧带刻度。

---

## 4. RenderTexture → QT 窗体

要让 `toTexture()` 成功，消费工程必须做两件事：

**4.1 工程 jsonc 声明渲染库**（模块引用不透传 dllImports）：

```jsonc
"dllImports": [
  { "path": "sl_render_lib.dll", "name": "sl_render_lib", "alias": "sl_render_lib", "static": "sl_render_lib" }
],
"references": [
  // Core / Std / Math
  { "path": "<...>/SimGameEngine.module.slb", "name": "SimGameEngine" },
  { "path": "<...>/SLangRender.module.slb", "name": "SLangRender" },
  { "path": "<...>/SLangQT.module.json", "name": "SLangQT" }
]
```

**4.2 入口初始化渲染库**：

```sl
SLang.Render.initialize()
```

**4.3 同一画布双取并用**：

```sl
DrawCanvas c = RDataChart.plotForecast( m, l, u, "forecast" )
var tex = c.toTexture()                       # GPU 纹理
bool ok = label.setPixmapRgba( c.pixelPtr(), c.width(), c.height() )  # QT 上屏
c.free()                                      # QPixmap 已拷贝，可安全释放
```

`label.setPixmapRgba` 由 `SLangQT` 提供（stub 后端恒返回 false，真 Qt 后端返回 true），
调用后 label 开启 `scaledContents`，图像随控件尺寸缩放。

---

## 5. 注意事项

| 事项 | 说明 |
|---|---|
| 不能直接把 texture handle 传给 QLabel | `setPixmapRgba` 要 CPU 地址；`tex.handle` 是 GPU 注册表句柄 |
| 方法调用不能直接作实参 | 先 `List<Float32> v = obj.values()` 再传 `v` |
| `null` 字面量不能直接作实参 | 用 `List<Float32> v = null` 变量 |
| 只从 GPU 侧看尺寸 | 尺寸从画布 `width()/height()` 取，不要从 `var tex` 读成员 |
| 画布释放时机 | 必须在 `toTexture()` 与 `setPixmapRgba()` 都完成后 |
| 双 namespace 冲突 | QT 句柄封装单独放一个文件，只 import SLangQT、只存 Int64 |
| 字体 | 画布文字为内置 3×5 位图，不支持中文；QT 标题栏文字可用中文 |

---

## 6. 可运行示例

`SLangCore/samples/GameTest/RDataGallery/`：3×2 六视图，最后一格演示
`DrawCanvas.toTexture()` + `QLabel.setPixmapRgba()` 同源双取。

```powershell
cd SlangAllInOne
slang compile SLangCore\samples\GameTest\RDataGallery\RDataGallery.jsonc --format binary --no-banner
slang publish SLangCore\samples\GameTest\RDataGallery\RDataGallery.sp --mode both --cvm Release
```
