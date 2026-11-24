# 26 · Std.RData 数据结构 → 图表 → RenderTexture（v2.23）

> 状态：【已落盘】第 25 套 `SimRDataTest` 52/52；QT 示例 `RDataGallery` 离屏验证
> 6 视图全渲染、RenderTexture 创建成功、QLabel 回绘无崩溃。
> 使用文档（R21 纯用法）：`md/lib/SimGameEngine/rdata-chart.md`。

---

## 1. 需求与边界

用户要的三段链路：

```
Std 侧 R 风格数据结构（CSV / 统计 / 预测）
  → GameEngine 侧映射成 chart
  → 产出 RenderTexture，并可回绘到 QT 窗体
```

实际落地形态：

| 段 | 落点 | 说明 |
|---|---|---|
| 数据结构 | `Std/RData/`（5 类，namespace RData） | `RVector/RFactor/RTable/RTimeSeries/RForecast`，纯 SL |
| 映射与图表 | `SimGameEngine/r/RDataChart.sl` | 5 个接口接基础列表 → DrawCanvas |
| 纹理与上屏 | `DrawCanvas.toTexture()` + `pixelPtr()` | 同一画布同时提供 GPU 句柄与 CPU RGBA8 镜像 |

---

## 2. 为什么不直接跨模块传 RData 对象

实测（Front）：引擎模块里 `RData.RVector` / `Std.RData.RVector` 作为方法形参均报
`MetaCoreNotFoundMetaTypeByFMClassDefine`；`import RData;` 也无法解析。
同模块内以 `RData.RVector` 声明局部/调用方法则可用（测试与 QT 示例已实证）。

因此把边界定在**基础列表**：Std 结构自己提供取值器，引擎接 `List<Float32>` / `List<string>`。
好处是边界稳定、无跨模块类型元数据依赖；代价是调用侧多一次显式取值。

| Std 结构 | 取值器 | 引擎接口 |
|---|---|---|
| `RVector` | `values()` | `RDataChart.plotVector(values, title)` |
| `RFactor` | `counts()` + `levels()` | `RDataChart.barFactor(counts, levels, title)` |
| `RTimeSeries` | `values()` + `start()` + `frequency()` | `RDataChart.plotSeries(values, start, frequency, title)` |
| `RTable` | `columnByName(name).values()` | `RDataChart.plotCsvColumn(values, columnName, title)` |
| `RForecast` | `meanValues()`/`lowerValues()`/`upperValues()` | `RDataChart.plotForecast(mean, lower, upper, title)` |

---

## 3. RDataChart 接口

| 方法 | 产物 |
|---|---|
| `plotVector(List<Float32>, string)` | 480×320 折线/点图（复用 `DrawChart.plotY`） |
| `barFactor(List<Float32> counts, List<string> levels, string)` | 480×320 条形图（复用 `DrawChart.barplot`） |
| `plotSeries(values, start, frequency, title)` | 折线图，标题附时间轴参数 |
| `plotCsvColumn(values, columnName, title)` | 指定列图表；`values == null` 时返回带提示的空白画布 |
| `plotForecast(mean, lower, upper, title)` | **560×360 置信带预测图**：灰色带 = lower~upper，实线 = mean，虚线 = 上下界 |

`plotForecast` 为本次新增图元组合：逐列 `fillRect` 铺置信带，`dashedLine` 画上下界，
`line` 画点预测均值；坐标映射走显式 Float32 局部变量后单独 cast（规避 `as Int32` 优先级坑）。

---

## 4. RenderTexture 与 QT 回绘的真实关系

`RenderTexture` 是 GPU 纹理薄壳（只有 handle/w/h），**没有 `readPixels`**。
`QLabel.setPixmapRgba(ptr,w,h)` 只接受 CPU 侧 RGBA8 top-down 指针。
因此「RenderTexture 直接回绘 QT」的正确实现是**同源双取**：

```
DrawCanvas c
  ├─ c.toTexture()       → SLang.RenderTexture（GPU 句柄；内部 createRgba 上传像素）
  └─ c.pixelPtr()        → CPU RGBA8 块 → SLang.QT.ffi_labelSetPixmapRgba → QLabel
  · C++ 侧 QPixmap::fromImage 会拷贝像素，故 blit 返回后即可 c.free()
```

消费模块必须自行声明 `dllImports`（模块引用不透传）：
`{ path: "sl_render_lib.dll", name/alias/static: "sl_render_lib" }`，并在入口调用
`SLang.Render.initialize()`；否则 `toTexture()` 返回 null。

---

## 5. QT 示例：RDataGallery

`SLangCore/samples/GameTest/RDataGallery/`（jsonc/sp/RDataHost.sl/RDataGallery.sl）：

- 3×2 共 6 格：RVector / RFactor / RTimeSeries / RTable 列 / RForecast / RenderTexture 回绘
- 第 6 格同时调用 `toTexture()` 与 `setPixmapRgba()`，标题栏显示 RT 是否创建成功
- `RDataHost.sl` 单独 import SLangQT、只存 Int64 句柄，规避双 `namespace SLang` 冲突
- 构建：`slang compile .../RDataGallery.jsonc --format binary --no-banner`
- 发布：`slang publish .../RDataGallery.sp --mode both --cvm Release`

---

## 6. 实证坑（本轮）

| 坑 | 现象 | 规避 |
|---|---|---|
| `out` 保留字 | `List<Float32> out = ...` 在 MetaCore 报 `MetaNode 重复` | 改 `res`（累计保留字 +1） |
| 嵌套泛型 `List<List<string>>` | File 阶段 `NodeAssetFrontListNodeIsZero` | RTable 只存原始 CSV 文本，分类列按需重解析 |
| `IO.File.readAllText` 不可见 | `readAllText` 未标 public | 直接用系统函数 `SystemFileReadAllText(path)` |
| 跨模块带点命名空间类型作形参 | `RData.RVector` 在引擎模块找不到定义 | 用基础列表作边界，Std 侧先 `values()` 导出 |
| 方法调用表达式作实参 | `plotCsvColumn(table.columnByName(...), ...)` 解析失败 | 先赋局部变量再传 |
| `null` 字面量作实参 | 重载解析失败 | 用 `List<Float32> v = null` 变量传入 |
| RenderTexture 为 null | 未初始化渲染库 / 未声明 dllImports | 消费模块声明 `sl_render_lib` + `SLang.Render.initialize()` |
| `var tex` 成 Core.Object | 跨模块不显式 import Render 时成员不可见 | 只判空、不直接读 `width/height`；尺寸由画布已知 |

---

## 7. 测试

`test/suites/SimRDataTest.sl`（第 25 套）52 项：五类 Std 结构的构造/取值/统计/边界 +
5 个映射接口的像素断言 + `toTexture()` 不破坏画布。运行方式同统一测试入口。
