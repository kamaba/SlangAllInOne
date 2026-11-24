# SceneDemo — 场景管理示例（samples/GameTest）

演示 SimGameEngine 的场景数据化闭环：按路径读取 `scene.json` → 建节点树 →
挂载脚本 → 运行场景逻辑 → 再导出回 JSON。设计说明见 `../../doc/19-场景导出与SceneManager.md`。

## 五个场景

| 文件 | 内容 |
|---|---|
| `assets/scenes/MaterialBall.scene.json` | 4 个不同材质颜色的球；`SphereMeshScript` 用固定形状库生成球网格，`SpinScript` 自转与浮动 |
| `assets/scenes/ShapeGallery.scene.json` | 8 形状展厅（ProBuilder 全集 12 种对齐）：立方体 / 球 / 圆柱 / 圆锥 / 圆环 / 棱柱 / 圆管 / 门框（`ShapeMeshScript` 按 `shape` 号构建网格，形状号对应 `ShapeFactory` 0/3/4/5/6/7/8/11）+ 双灯（平行光带阴影 + 聚光）；每个形状挂 `SpinScript` 绕自身中心自转（部分带浮动） |
| `assets/scenes/PureTest.scene.json` | 纯逻辑测试：父子两节点各挂 `ProbeScript`，打印生命周期启动与存活计数 |
| `assets/scenes/MaterialGallery.scene.json` | 27 材质球展厅：9×3 球阵（Lambert/Phong/BlinnPhong/Toon 四种固化 HLSL 材质模型 × 色相环 × 高光梯度，3 球贴图）+ 地面 + 双灯（平行光带阴影 + 聚光）。键 `4` 切换查看。脚本动效：每球 `SpinScript` 浮动（带相位差），聚光灯 `LightSwingScript` 摆动 |
| `assets/scenes/RotateTest.scene.json` | 旋转测试：45° 俯视的地面 + 正方形 + 直射光（带阴影），挂 `AxisGizmoScript` 显示 XYZ 轴。键 `5` 切换查看，右键拖拽旋转视角 |

单工程 `SceneDemo`，两种运行模式由参数决定：

- 无参数（默认）— QT 窗口展示；窗口可自由拉伸缩放，渲染分辨率与显示内容
  随窗口同步变化（Unity OnResize 语义：`viewSize` = 视口纵向半高，横向随
  窗口宽高比自适应，内容不拉伸）。启动后是场景选择菜单，点其中一项进入；
  `M` 返回菜单，`1`~`5` 直接切换场景（`5` = RotateTest）。`WASD` 平移相机、
  左键拖拽移动视角（内容跟随鼠标）、右键拖拽旋转视角、滚轮缩放（半高 1.5~40）、
  `G` 切换坐标轴箭头、`U` 开关场景内 FairyGUI 覆盖层（默认关闭，避免遮挡
  3D 图形）、`F` 切换 FairyGUI 包格式（XML/`.fui`），`O` 把当前场景导出到
  `assets/scenes/exported.scene.json`，`Esc` 退出；信息条显示
  nodes/scripts/lights/objs 运行时计数。
- `-- smoke` — 无窗口冒烟；五场景加载、脚本挂载、跑 8 帧、导出落盘再回读，
  外加 FairyGUI XML/`.fui` 包解析断言，50 项全绿（退出码 0，失败退出码 1）。

## FairyGUI UI 示例

`assets/fairygui/Demo/` 是最小样例包：`package.xml`（图集 sprite 定义 + 九宫格
边距 + 设计分辨率）、`DemoUI.xml`（组层级、图片、九宫格、文本占位）、
`atlas@ui.png`（程序化图集）、`Demo.fui`（同内容的二进制包）。
`gen_atlas.py` / `gen_fui.py` 可重新生成后两个资源。

UI 由引擎的 FairyGUI 适配层读取后转成带 UV 的自定义网格，经独立的
UI 叠加相机渲染，显示在 3D 场景之上。场景内该覆盖层默认关闭（按 `U`
开启），菜单界面不受影响；默认加载 XML 包，按 `F` 切到 `.fui` 包，
两者共用同一套渲染层。文本用图集白块占位，暂不接字体。

资源目录：`assets/textures/`（three.js MIT 示例贴图 brick/grass/hardwood）、
`assets/shaders/`（DirectX-Graphics-Samples/MIT 的 BasicHLSL11 对照源；
运行时材质模型走引擎固化 HLSL 程序槽）。

## 构建与运行

先编译 SimGameEngine 与 SLangRender/SLangQT 模块（命令见 `SnakeGame/README.md`），
再在示例目录 `SlangAllInOne\SLangCore\samples\GameTest` 执行：

```powershell
$slang = 'D:\project\lang\SlangAllInOne\out\cli-release\slang.exe'
$demo  = 'D:\project\lang\SlangAllInOne\SLangCore\samples\GameTest'

# 编译（一次编译两种模式共用）
& $slang compile "$demo\SceneDemo.jsonc" --format binary+json --no-banner

# 无窗口冒烟（CI / 快速验证场景/脚本/导出链路）
& $slang run 'SlangAllInOne\out\export\SceneDemo\SceneDemo.module.slb' -- smoke --no-banner
# 期望：=== SceneManager smoke PASS=50 FAIL=0 ===，EXIT=0

# H5 网页版（两层 UI：总入口菜单 + 场景内按钮菜单）
& $slang run 'SlangAllInOne\out\export\SceneDemo\SceneDemo.module.slb' -- web --no-banner
# 默认浏览器自动打开 out\scene_webui\index.html，两层 UI：
#   ① 总入口菜单：居中的 UI 菜单，列出可配置的多个场景，点一项进入对应场景。
#      场景配置集中在 SceneDemoWebUI.sl 的 sceneCount / sceneLabel
#      （与 SceneDemo.loadScene 的 idx→文件映射一一对应，改两处即可增删场景）；
#      菜单项与场景内按钮条由同一张表生成，始终一致。
#   ② 场景内顶部一排按钮菜单：Menu（返回入口）+ 场景切换按钮（当前项高亮）
#      + 分辨率下拉框（默认 640x360 + 常用手机/平板/HD 9 档，选中即时调整
#      H5 canvas 与引擎渲染目标尺寸）+ 当前尺寸标签 + FPS 标签（真实刷新帧数）。
# 帧由引擎原生 D3D11 渲染 → JPEG → 8 槽落盘 → 浏览器 canvas 显示。
# 注意：H5 版只渲染核心场景，编辑器辅助层（gizmo 箭头 / FairyGUI 叠加）
# 在 WebUI 事件线程渲染会崩溃，故 H5 路径不绘制这两层。

# QT 窗口示例
& $slang run 'SlangAllInOne\out\export\SceneDemo\SceneDemo.module.slb' --no-banner
```

QT 窗口程序需要 `slang_qt.dll` 与 Qt6 运行库；可用 `slang publish SceneDemo.jsonc`
按 jsonc 的 `qtRuntime` 段一并打包。

## RExamples — R 风格图表示例（12 格 QT 图库）

`RExamples/` 仿菜鸟教程 R 绘图/回归页写了 12 个示例，每格都是真实图表：
散点+回归线、均值/中位数直方图、彩色条形图、分组条形图、班级箱线图、
市场份额饼图、`plot(type=n+h+o)` 气温图、`par(mfrow=c(2,2))` 四联图、
三产品折线图例、`abline` 参考线、`lm` 预测 170cm 体重，以及 Math 库
`MathDist.dnorm/rnorm` 密度曲线叠加直方图。

```powershell
& $slang compile "$demo\RExamples\RExamples.jsonc" --format binary+json --no-banner
& $slang run 'SlangAllInOne\out\export\RExamples\RExamples.module.slb' -- smoke --no-banner
# 期望：===== RExamples smoke PASS=12 FAIL=0 =====，EXIT=0
& $slang run 'SlangAllInOne\out\export\RExamples\RExamples.module.slb' --no-banner
# QT 4×3 图库窗口；发布用 slang publish RExamples.sp
```

示例只依赖 Math 库新增的 `MathRBasic/MathStats/MathDist/MathVec` 与引擎
`DrawChart`，数据在 `RExamples.sl` 的各 `exNN()` 方法中，改数值即可复用。

## 场景数据与脚本约定

- scene.json 沿用第 16 章 schema；脚本组件写作
  `{ "type": "Script", "script": "<短名>", ...自定义参数 }`。
- 脚本是 `Behaviour` 子类，其 `awake/start/update/lateUpdate/fixedUpdate` 由
  `SceneManager.tick()` 经 Application 帧循环驱动。
- 脚本工厂形态固定为 `void(JsonValue cfg, ScriptResult sink)`，在 `SceneDemo.run()`
  中先 `registerScript` 再 `load`。可用工厂集中在 `SceneScripts.sl` 的
  `SceneScriptFactories` 类。
- 加载失败原因在 `SceneManager.lastError`；未注册的脚本计入
  `ImportReport.skippedCount`，不中止加载。

## 注意事项

- 场景路径按「当前目录 → 工作区根 → 内置绝对路径」三级探测，换机器时把
  `SceneDemo.findSceneDir()` 的兜底路径改成实际位置即可。
- 导出会把脚本生成的网格顶点写进 `vertices`，`exported.scene.json` 会比源场景大。
- 脚本字段名不要用 `label`（SLang 保留字）。
