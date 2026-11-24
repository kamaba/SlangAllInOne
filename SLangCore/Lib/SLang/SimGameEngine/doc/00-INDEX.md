# SimGameEngine 文档索引

> 版本：v2.23（26 章设计稿，2026-11-23；v2.23 新增 Std.RData 数据结构 → 引擎映射 chart → RenderTexture/QT 回绘链路，doc/26；前序 v2.22 将独立模块 StatsPlot 整建制合并入引擎 `stats/`（namespace StatsPlot 不变、66 项断言并入第 24 套），并新增 QT 图库示例展示全部绘图接口，doc/25；前序 v2.21 新增第 24 章基础绘图与 R 风格图表（纯 SL 软光栅：DrawCanvas 图元 + PlotParams + DrawChart 图表工厂），第 23 套 SimDrawingTest 59/59；前序 v2.20 新增第 23 章 Windows 系统 GDI 绘图（render CVM/C 层 `slr_gdi_*` + `SLangRender.GdiCanvas` 门面）/ 字库动态图集 / 文本网格 / GameManager，第 22 套 SimTextDrawTest 54/54；前序 v2.19 新增第 22 章 Prefab 机制——GameObject 子树 JSON，与 scene.json 同构共用读写代码，SceneManager 七个门面，导出侧补 Light/Volume，第 21 套 SimPrefabTest；前序 v2.18 新增第 21 章编辑器 Gizmo——GizmoTypes/GizmoGeometry/GizmoSystem 三件套：三轴箭头 / 旋转环 / 缩放手柄 + 相机·光 2D/3D 图标，纯 SL 几何走 MeshRef 烘焙路径零 C 改动，SceneDemo 接入 G 键循环模式，第 20 套 SimGizmoTest；前序 v2.17 新增第 20 章 ECS 系统——GameObject 渲染数据拔离 + 只挂 Data + 逻辑集中调度 + 自动分层合并 + 渲染层整体提交，第 19 套 SimEcsTest；前序 v2.16 新增 Camera/Light 实体（extends GameObject + CameraData/LightData 组件）+ Camera 四类矩阵方法，第 18 套 SimCameraLightTest；前序 v2.15 doc/08 §8 UI 画布两模式 + 引擎层图层叠加；v2.12 新增第 19 章「场景导出与 SceneManager」：SceneExporter 落盘 scene.json + SceneManager 按路径加载/脚本挂载/帧循环 + SceneImporter 脚本扩展；P0~P7 全部落盘（P2 Submit 烘焙段收尾：C `sle_ortho_bake` 正交投影 → uploadMesh MESH_CUSTOM）+ **Transform/RectTransform 统一合并入 SLangRender** + **P8 Volume v1（C 核心）** + **P8 完整 SceneImporter v1** + **Mesh GJK+MTV 精化 v1（C 核心，mesh-mesh 物理闭环）** + **P9 固定形状库 v1（C 核心，11 形状）** + **统一时间同步 v1（TimeService/EngineTime，域时钟挂接音频/视频）** + system/ 系统层 + test/ 统一测试入口（Test.sl，十四套 656 项）+ C99 原生库 sl_sim_engine_lib）
> 定位：SLang 游戏引擎「场景 / 节点 / 组件」层的设计与使用契约。
> 配套渲染文档：`../Render/doc/01-Overview.md` 起（Render 只负责「可见物 + 相机 + 光源 → 像素」）。

---

## 1. 这套文档解决什么

`SLangRender` 已经能把一组 RenderObject、相机、光源变成一帧像素（`Render/doc/01-Overview.md` §1.2 明确：Render 不做 GameObject、不做脚本生命周期、不做场景图）。
`SimGameEngine`（本目录）补的是它**明确不做的那一半**：

- 用树型结构管理所有游戏对象（Unity 的 GameObject）；
- 用组件把 Transform / Mesh / Material / Shader / Animation / Effect 绑到节点上（Unity 的 Component）；
- 用 Behaviour 钩子驱动脚本生命周期（Unity 的 MonoBehaviour）；
- 按 Shader + Material 把 Mesh 归组、合并，再写进 RenderObject 提交给 Render；
- 可选 ECS 模式：节点只挂数据、逻辑集中调度、渲染数据由世界分层合并后整体提交（第 20 章）；
- 用节点类型区分 Camera / Light / Probe / UI 等特殊对象；
- 用碰撞体与固定步长物理处理重叠、接触与刚体运动（第 11/12 章）；
- 用天空盒、环境光与 Volume 参数栈组织画面氛围（第 13/14 章）；
- 用 QUAD / 动态网格承接 2D 精灵与 Tilemap（第 15 章）；
- 用 Unity Editor 导出器输出独立 JSON 资源，供引擎导入建场景（第 16 章）；
- 用 FBX SDK 转换器把通用模型文件汇入同一格式，材质 shader 用通用 HLSL 源文件（第 16 章）。

一句话：**SimGameEngine 管「scene 里有什么、谁更新谁、谁该被合并」，Render 管「怎么画出来」。**

---

## 2. 文档清单（26 章 + 索引）

| 编号 | 文件 | 内容 | 读者 |
|---|---|---|---|
| 01 | `01-总体架构与边界.md` | 目标 / 非目标、四层架构、一帧数据流、Unity 概念对照、已落盘与待建清单 | 全员必读 |
| 02 | `02-GameObject与组件模型.md` | GameObject、Component、Behaviour 生命周期、组件增删改查 | 写游戏逻辑的人 |
| 03 | `03-场景树与变换层级.md` | Scene、父子层级、local/world 变换、激活态、Bounds/Plane/Ray 空间工具 | 写场景组织的人 |
| 04 | `04-渲染资源模型.md` | Mesh / Material / Shader / Texture 与 Render 门面的对应、资源生命周期 | 写渲染逻辑的人 |
| 05 | `05-合批与RenderObject提交.md` | 合批键、批次生成、RenderObject 字段映射、与 13 阶段管线的对接 | 写渲染逻辑的人（核心章） |
| 06 | `06-相机光照与探针.md` | Camera / Light / Probe 节点、cullMask / layer、多相机 | 写场景与画面的人 |
| 07 | `07-动画与特效.md` | Animation 采样、Effect 挂接、与 setAnimated 内置效果的分工 | 写表现层的人 |
| 08 | `08-UI节点与事件.md` | UIBehaviour、RectTransform、射线命中、UI 合批路径 | 写 UI 的人 |
| 09 | `09-运行时与帧循环.md` | 引擎主循环、帧序、QT 计时器接入、暂停 / 销毁 | 写主程序的人 |
| 10 | `10-接入示例与差距路线.md` | 工程接入、可运行示例、API 签名总表、差距与路线、坑汇总 | 全员收口 |
| 11 | `11-碰撞与触发器.md` | Collider 类型、宽相 / 窄相、碰撞矩阵、触发器与 Enter/Stay/Exit 事件 | 写玩法的人 |
| 12 | `12-物理引擎.md` | Rigidbody、固定步长积分、接触求解、休眠、CCD、与 Transform 同步 | 写玩法的人 |
| 13 | `13-天空盒与环境.md` | cubemap 天空盒、`setAmbient` 环境光、雾效、过渡方案 | 写画面的人 |
| 14 | `14-Volume效果处理.md` | VolumeProfile / 参数栈 / 混合、局部范围、与后处理阶段对接 | 写画面的人 |
| 15 | `15-2D渲染.md` | SpriteRenderer、排序层、图集合批、正交相机、Tilemap、2D 物理；§9 游戏类型与宽高比适配（CameraRig2D/ParallaxLayer/TileColliderBaker） | 写 2D 游戏的人 |
| 16 | `16-Unity资源导入与导出.md` | Unity 原生格式解析判定、Editor 导出器、FBX SDK 转换器（ufbx 选型）、JSON schema、通用 HLSL shader 与 DXC 编译链、引擎导入器、坐标约定 | 做资源管线的人 |
| 17 | `17-固定形状库.md` | P9 固定形状库（11 形状 / C 两段式构建 / 消费出口 / 坑） | 用形状生成网格的人 |
| 18 | `18-时间同步.md` | TimeService / EngineTime / 域时钟 / Application 帧序接入 | 写主循环的人 |
| 19 | `19-场景导出与SceneManager.md` | Scene→scene.json 导出、按路径加载场景、脚本挂载、帧循环门面、round-trip 与坑 | 写场景/关卡逻辑的人 |
| 20 | `20-ECS系统.md` | opt-in ECS 模式：渲染数据拔离 / 只挂 Data / 逻辑集中调度 / 自动分层合并 / 渲染层整体提交 | 写批量实体与渲染管线的人 |
| 21 | `21-编辑器Gizmo.md` | GizmoTypes / GizmoGeometry / GizmoSystem：三轴箭头 / 旋转环 / 缩放手柄 / 相机·光 2D·3D 图标，纯 SL 几何 + 帧生命周期 + 状态机 | 写编辑器/调试可视化的人 |
| 22 | `22-Prefab机制.md` | GameObject 子树 JSON（与 scene.json 同构）：共用读取/写入层、SceneManager 实例化门面、Light/Volume 导出对称 | 写场景内容复用/关卡装配的人 |
| 23 | `23-Windows绘图与文本.md` | Windows 系统 GDI（render CVM 原生层）/ TTF 字库按需烘焙 / TextMesh 网格 / GameManager 主控 | 写 2D 表现与主控流程的人 |
| 24 | `24-基础绘图与图表.md` | 跨平台 RGBA8 软光栅：DrawCanvas 图元（线/虚线/圆/椭圆/弧/扇形/多边形/文字）+ PlotParams（par）+ DrawChart（plot/hist/barplot/boxplot/pie/abline/legend） | 写数据可视化与离屏绘图的人 |
| 25 | `25-StatsPlot统计绘图设计.md` | 原独立模块 StatsPlot 合并入引擎：DataFrame / Stats / PlotCanvas / Plot / PlotIo 的设计与 API 一览（namespace 与源码不变） | 实现者与评审 |
| 26 | `26-RData映射与图表.md` | Std.RData 五类结构 → RDataChart 映射/chart → RenderTexture 与 QT 同源回绘；边界取舍与实证坑 | 实现者与评审 |

阅读顺序：`01 → 02 → 03 → 04 → 05 → 06/07/08 → 09 → 10 → 11/12 → 13/14 → 15 → 16 → 17/18 → 19 → 20 → 21 → 22 → 23 → 24 → 25 → 26`。只关心接入的可直接读 `10`，只关心场景数据化可读 `19`，只关心 Prefab 可读 `22`，只关心 UI 两模式/相机叠加可读 `08 §8`，只关心编辑器辅助渲染可读 `21`，只关心离屏绘图/图表可读 `24`。

---

## 3. 状态图例（全文通用）

本套文档混有「已经能调用」与「尚在设计中」两类内容，所有 API 与类均按下列标记区分，请勿把设计稿当成现成接口：

| 标记 | 含义 | 判定依据 |
|---|---|---|
| 【已落盘】 | 源码已存在，签名可直接核对 | `SimGameEngine/*.sl`、`Render/SLangRender/*.sl` |
| 【设计稿】 | 本文提出的目标形态，尚未落盘 | 只有本文描述，无对应 `.sl` |
| 【依赖待建】 | 两侧都已存在，但工程引用 / 绑定关系尚未建立 | 如 `UIBehaviour` → `RectTransform` |

现状一句话（2026-11-16，P0~P5 端到端 + C99 原生库 + P7 引擎层 v1）：模块已是可编译、可导出、可运行的库模块（`SimGameEngine.sp/.jsonc`，产物 `out/export/SimGameEngine/`）。【已落盘】= 场景核心五件（`Transform` / `GameObject` / `Scene` / `Application` / `Behaviour`）+ 空间工具三件（`Bounds` / `Plane` / `Ray`）+ P2 渲染资源五件（`MaterialData` / `MeshRef` / `MaterialRef` / `BatchGroup` / `Batcher` 合批数据层）+ P3 碰撞六件（`ContactInfo` / `ContactPair` / `BoxCollider` / `SphereCollider` / `CapsuleCollider` / `CollisionSystem`）+ P4 物理两件（`Rigidbody` / `PhysicsSystem`：半隐式欧拉 + 顺序冲量 + 休眠）+ P5 动画/UI 六件（`AnimationClip` / `Animation` / `Effect` / `LightProbe` / `ReflectionProbe` / `UIBehaviour` + `RectTransform`（自 SLangRender 迁入）+ `AnimSystem` / `UISystem`）+ **P7 2D 三件（`SortingLayers` / `SpriteRenderer` / `Tilemap` + `RenderSystem.collect2D/sync2D`，doc/15 §0）** + C99 原生库三件（`EngineClock` / `Timer` / `NodeRegistry`，底层 `sl_sim_engine_lib.dll`）+ 五个 C VM 系统调用（`SystemSimEngineCallHook` / `CallHook1` / `CallHook2` / `SetEnabled` / `GetEnabled`）；九套测试 343 项全绿（`SimEngineTest` 60 / `SimBatchTest` 28 / `SimCollisionTest` 52 / `SimModuleTest` 11 / `SimSystemsTest` 14 / `SimFfiTest` 24 / `SimPhysicsTest` 33 / `SimAnimTest` 66 / `Sim2DTest` 55，统一入口 `test/Test.sl`）。仍为【设计稿】：Mesh GJK/BVH 精确碰撞、cubemap 天空盒全链路、Probe 采样/混合、Volume、2D 的翻转 UV / 图集 UV / uploadMesh 合批提交（P6~P8 剩余段）。Render 侧仍是【已落盘】的可运行模块。

补充（v2.17）：【已落盘】新增 ECS 模式五件（`EcsData` / `EcsLogic` / `EcsLogicSystem` / `EcsLayer` / `EcsWorld`，doc/20）——opt-in 启用后节点只留数据、逻辑集中调度、渲染数据由世界分层合并后整体提交；第 19 套 `SimEcsTest` 48 项绿，统一入口累计 928 PASS / 33 FAIL（33 为 v2.11 既有 fixedDt 回归）。

补充（v2.18）：【已落盘】新增编辑器 Gizmo 三件（`GizmoTypes` 常量+调色板 / `GizmoGeometry` 纯几何生成 / `GizmoSystem` 状态机+六色槽提交，doc/21）——三轴箭头 / 旋转环 / 缩放手柄 + 相机·光 2D/3D 图标，纯 SL 三角形几何走既有 `MeshRef` 烘焙渲染路径（零 C 库改动）；SceneDemo 接入（G 键循环 move→rotate→scale→none，信息条显示模式，替换原手工三色轴缓冲）；第 20 套 `SimGizmoTest` 35 项绿，统一入口累计 963 PASS / 33 FAIL（33 为 v2.11 既有 fixedDt 回归），SceneDemo 冒烟 50/50。

补充（v2.20）：【已落盘】新增 Windows 系统 GDI 绘图（render CVM 层 `slr_gdi_*` 18 导出 + `SLangRender.GdiCanvas` 薄门面，非纯 SL 软光栅）+ 字库文本五件（`Font` / `Glyph` / `FontAtlas` / `TextMesh` / `GameManager`，doc/23）——GDI 真画布 + `.ttf` 字形解析 + 按需动态图集 + quad 文本网格 + 全局主控门面；第 22 套 `SimTextDrawTest` 54 项绿，统一入口累计 **1063 PASS / 33 FAIL**（33 为 v2.11 既有 fixedDt 回归，无新增），RenderTest EXIT=0。

补充（v2.21）：【已落盘】新增基础绘图四件（`DrawTypes` / `DrawCanvas` / `PlotParams` / `DrawChart`，doc/24）——跨平台 RGBA8 软光栅画布 + 11 类图元（含虚线/圆弧/扇形）+ R `par()` 参数对象 + 8 种图表工厂与 abline/legend 叠加，零 C 改动、零新模块依赖；第 23 套 `SimDrawingTest` 59 项绿，23 套统一入口本轮实测 **1155 PASS / 0 FAIL**。

---

## 4. 术语对照（Unity ↔ SimGameEngine ↔ SLangRender）

| Unity | SimGameEngine | SLangRender 侧对应 | 状态 |
|---|---|---|---|
| GameObject | GameObject（本文定义） | 无（Render 不持有此概念） | 设计稿 |
| Transform | Transform / RectTransform | **`Transform` / `RectTransform`（统一版，2026-11-17 合并入 SLangRender，引擎复用）** | 已落盘 / Render 已落盘 |
| Component / MonoBehaviour | Component / Behaviour | — | Behaviour 已落盘 |
| Mesh / MeshFilter | Mesh 组件 | `Mesh.cube(size)` / `getTriangles()` | Render 已落盘 |
| MeshRenderer | Renderer | `Renderer extends Component`（提交已改走命令缓冲） | Render 已落盘 |
| Material / Shader | Material / Shader 组件 | `Material` / `Shader` 门面、`resolveProgram()` | Render 已落盘 |
| Camera | Camera 组件 | `Camera extends Component`、`pipe.setCamera/addCamera` | Render 已落盘 |
| Light | Light 组件 | `static directional/point/spot`、`applyTo(pipe,slot)` | Render 已落盘 |
| ReflectionProbe / LightProbe | Probe 组件 | 无对应能力 | 设计稿 |
| Animator / Animation | Animation 组件 | `RenderObject.setAnimated(mode,speed)`（内置模式） | 设计稿 / Render 内置模式已落盘 |
| ParticleSystem / VFX | Effect 组件 | shader 效果 + 13 阶段 `postProcess` | 设计稿 |
| UI / Canvas / RectTransform | UIBehaviour + RectTransform | `RectTransform.sl`（在 Render 模块内） | 部分落盘 / 依赖待建 |
| Bounds / Plane / Ray | Bounds / Plane / Ray | — | 已落盘 |
| SRP Batcher | 合批器（第 05 章） | C 层 PerDraw std140 分组批已落盘；SRP Batcher 式合批未承诺 | 设计稿 |
| ECS（DOTS 式） | EcsWorld / EcsData / EcsLogic（第 20 章） | 无（Render 只收 RenderObject） | 已落盘（opt-in） |
| Collider / Rigidbody | Collider / Rigidbody 组件 | 无（Render 不处理物理） | 设计稿 |
| Skybox / Environment | Skybox 组件 + `setAmbient` | Skybox shader 素材有 bug、Pass 未接入 13 阶段；`setAmbient` 已落盘 | 部分落盘 |
| Volume / VolumeProfile | Volume 组件 + 参数栈 | PostProcessPass 已落盘（亮度/饱和度/暗角）；Volume 参数栈 P2 未开始 | 设计稿 |
| SpriteRenderer / Tilemap | SpriteRenderer / Tilemap + 排序层 | `MESH_QUAD` / `uploadMesh` / 正交 `setCamera` 已落盘 | 部分落盘 |
| AssetDatabase / 编辑器资源管线 | 第 16 章导出器 + `SceneImporter` | 无（纯资源层，不进渲染） | 导出器落点已核实 / 本体设计稿 |
| Editor Gizmos / Handles（编辑态渲染） | GizmoSystem / GizmoGeometry / GizmoTypes（第 21 章） | 走既有 `MeshRef` 顶点烘焙 → RenderObject，无专用图元 | 已落盘（纯显示，无拾取） |
| Windows GDI 画布（Unity 无同名类） | `GdiCanvas`（第 23 章，Render CVM 原生层） | DIB → RGBA8 → 既有纹理通道 | 已落盘（仅 Windows） |
| 2D 画布 / 统计图表（Unity 无内置同名类；参考 R base graphics） | `DrawCanvas` / `PlotParams` / `DrawChart`（第 24 章） | `pixelPtr()` 上屏 / `toTexture()` 转纹理 | 已落盘（纯 SL 跨平台） |
| Font / TextMesh / FontAtlas（Unity 文本） | `Font` / `TextMesh` / `FontAtlas`（第 23 章） | `RenderTexture` 图集 + `submitUiMeshTex` 透明 UI 网格 | 已落盘（二值 alpha，无 kerning） |
| 全局主控（Unity 无内置同名类） | `GameManager`（第 23 章） | 持有 `Application` + `Systems`，自身不渲染 | 已落盘 |

---

## 5. 变更记录

| 日期 | 版本 | 变更 |
|---|---|---|
| 2026-11-23 | v2.23 | **Std.RData 数据结构 → chart → RenderTexture/QT 链路**：Std 新增 `RData/` 五类（`RVector/RFactor/RTable/RTimeSeries/RForecast`，namespace RData，compileFiles+struct 登记，Std buildVersion→1）；引擎新增 `r/RDataChart.sl` 五个映射接口（含置信带预测图 plotForecast），登记 priority 59 + struct，buildVersion→8；第 25 套 `SimRDataTest` 52/52；QT 示例 `samples/GameTest/RDataGallery/` 6 视图，离屏实证 RenderTexture 创建 + QLabel 回绘；全套件 25 套 **1273 PASS / 0 FAIL**。因 Front 不支持跨模块带点命名空间类型作形参，边界定为基础列表（Std 取值器导出）。文档 doc/26 + `md/lib/Std/RData.md` + `md/lib/SimGameEngine/rdata-chart.md` |
| 2026-11-23 | v2.22 | **StatsPlot 合并入引擎 + QT 图库示例**：原独立模块五件源码（`Stats/DataFrame/PlotCanvas/Plot/PlotIo`）整建制迁入 `SimGameEngine/stats/`，保留 `namespace StatsPlot` 与全部公开 API（消费方改 `import SimGameEngine;` 即可），登记 priority 54..58 + struct 命名空间；原 66 项断言并入统一测试入口第 24 套 `SimStatsPlotTest`（`import SimGameEngine;` 后 `StatsPlot.*` 照用）；新增 `samples/GameTest/StatsGallery/` QT 图库（4×4 共 16 视图：DrawCanvas 图元 + DrawChart 八接口 + StatsPlot 七接口 + DataFrame/Stats/PlotIo 链路），离屏验证 16 视图全渲染、事件循环稳定；全套件 24 套 **1221 PASS / 0 FAIL**。旧独立模块源码与旧测试已删除。文档：doc/25 设计 + `md/lib/SimGameEngine/statsplot.md` 使用 |
| 2026-11-23 | v2.21 | **基础绘图 + R 风格图表落盘（doc/24，零 C 改动）**：新增 `drawing/` 四件——`DrawTypes`（线型/点符号/调色板/绘图自带三角与 log2）/ `DrawCanvas`（RGBA8 软光栅：点/线/虚线/点线/矩形/圆/椭圆/弧/扇形/多边形/3×5 文字 + 上屏与纹理输出）/ `PlotParams`（R `par()` 参数对象）/ `DrawChart`（统计辅助 + plot/scatter/curve/plotY/hist/barplot/boxplot/pie + abline/legend 叠加）；全部登记 `SimGameEngine.jsonc`（priority 50..53 + struct）；第 23 套 `SimDrawingTest` 59/59，全套件 23 套 **1155 PASS / 0 FAIL**（本轮实测全绿，v2.11 登记的 33 项 fixedDt 回归未复现）。坑：`half` 保留字再证 / `List.add` 不可链式 / 循环变量漏自增死循环 / `as Int32` 与乘除混写优先级异常（先落 Float32 局部再 cast）/ 引擎内跨模块 `Mathf.cos/sin` 返回 0 → 绘图自带三角；使用文档 `md/lib/SimGameEngine/drawing-and-charts.md` |
| 2026-11-23 | v2.20 | **Windows 系统 GDI + 字库 / 文本落盘（doc/23）**：① 绘图走**渲染 CVM 原生层**——`cvm_render_lib/Platform/sl_gdi.c` 新增 18 个 `slr_gdi_*` 导出（`CreateDIBSection` + HDC + GDI 笔刷 / `Polygon` / `BitBlt` / `TextOutW`），`vm_sl_render.h` 登记、`RenderFFI.sl` 静态绑定、`SLangRender/GdiCanvas.sl` 薄门面；旧纯 SL `WinDraw.sl` 已删除（层次错误）；DIB 为 BGRA 顶行，对外 `toRgba`/`*_texture` 转库统一 RGBA8。② 字库文本五件（`Font` sfnt-cmap-glyf 解析 / `Glyph` / `FontAtlas` 按需动态图集 / `TextMesh` quad 网格 / `GameManager` 主控）保持纯 SL；先筛出文本用到的字再烘焙 256×256 图集。第 22 套 `SimTextDrawTest` 54/54（含 GDI 真画布 + 测试内现场构造 352B 最小 TTF），全量 22 套 **1063 PASS / 33 FAIL**（33 为既有 fixedDt 回归，无新增），RenderTest EXIT=0。坑：`GetPixel` 丢 alpha 改直读 DIB；C 改动后须同步 sl_render_lib.dll 全槽位（含调试 zip）；`bind`/`data`/`half` 保留字与 `num` 类名冲突、跨行 `ret a + b`、`ret list[i]`、跨模块 `tex.handle` 先落局部；使用文档 `md/lib/SimGameEngine/windows-draw-text.md` |
| 2026-11-20 | v2.18 | **编辑器 Gizmo 落盘（doc/21，零 C 改动）**：新增 `gizmo/` 三件——`GizmoTypes`（模式/轴/图标常量 + 调色板方法）、`GizmoGeometry`（纯 SL 三角形几何：方向箭头/旋转圆环/缩放手柄/相机 2D·3D 图标/平行光·点光·聚光图标，细长四边形模拟线段）、`GizmoSystem`（六色槽状态机 + 帧生命周期 begin/draw/end + 相机·光图标 + 诊断 getters），几何经 `MeshRef.setVertices` 走既有 Batcher/sync 烘焙路径；`SimGizmoTest` 35 项（第 20 套），二十套 **963 PASS / 33 FAIL**（33 为既有 fixedDt 回归）。SceneDemo 接入：手工三色轴缓冲改为 GizmoSystem 委托，G 键循环 move→rotate→scale→none、信息条显示模式、场景锚点画相机/光图标；**Ctrl+Home 顶部菜单栏（QMenuBar 子控件形态）+「辅助 Gizmo」菜单下「显示辅助 Gizmo」action 切 showAxes 全局开关**（QTHost.startHost 增 toggleGizmoHandler 无参回调，SIG_TRIGGERED 连接）；GUI 实跑验证：窗口正常渲染、数字键切场景、Ctrl+Home 弹出菜单、点 action 后 objs=7→2（gizmo 网格节点从提交链移除）确认开关生效、进程稳定无崩溃；冒烟 50/50。坑：`half` 是词法保留字（参数改名 `hh`）；跨模块 static 几何函数有签名风险，SceneDemo 与测试一律走 GizmoSystem 实例方法消费；冒烟测试原引用已删的 `SceneDemo.vertsX` 同步改为 `gs.vertexCountAt(0)` |
| 2026-11-20 | v2.17 | **ECS 模式落盘（doc/20）**：新增 `ecs/` 五件（EcsData 纯数据 / EcsLogic 逻辑组件 / EcsLogicSystem 集中调度 / EcsLayer 分层结果 / EcsWorld 实体+数据仓+分层）；GameObject 的 MeshRef/MaterialRef 在注册时拔离到世界 ECS 模式只挂 Data（其它 Behaviour 拒绝），逻辑统一由 world.logic 按 order 调度；Batcher 增 collectEcs + EcsLayer 分层收口，RenderSystem 增 ecsSource 直接提交分层结果（零 C 库改动）；Systems.bindEcs 一键接线；Application 固定步/帧逻辑/变换后分层三处接入；`SimEcsTest` 48 项（第 19 套），十九套 928 PASS / 33 FAIL（33 为既有 fixedDt 回归）。坑：`bind`/`label` 保留字；GameObject 新字段名避开 `world`（与 Camera 局部同名会污染解析链）；跨模块 List 下标先落局部变量；顺手修 `SimSystemsTest` 重复变量声明 |
| 2026-11-16 | v0.1 | 初版 10 章：按 Render 的「纯渲染引擎」边界切出宿主引擎职责，完成节点树 / 组件 / 合批 / 相机光照 / 动画特效 / UI / 帧循环的整体设计整合 |
| 2026-11-16 | v0.2 | 补 5 篇独立文档：碰撞与触发器、物理引擎、天空盒与环境、Volume 效果处理、2D 渲染；同步总纲 / 路线 / 术语对照 |
| 2026-11-16 | v0.3 | 补第 16 章：Unity 原生格式解析判定（不可行 → 自建导出系统）、Editor 导出器落点与 JSON schema、引擎侧 SceneImporter 与坐标约定 |
| 2026-11-16 | v0.4 | 第 16 章扩充：FBX SDK 转换器路径（ufbx 起步选型、离线 CLI、烘焙单位轴向）；材质 shader 升级为通用 HLSL 源文件（三态映射、DXC 编译链、跨后端如实边界、编译缓存） |
| 2026-11-16 | v0.5 | **端到端落地**：Unity 导出器 `SlangSceneExporter.cs` 落盘（flag `export-scene`/`export-cube`），引擎侧 `test/Other/SimSceneTest` 验证 Unity CubeDemo → SLangRender 渲染 PASS（24 顶点 / 937 帧 @15s）；第 16 章状态升级为「已落盘，端到端已验证」 |
| 2026-11-16 | v0.6 | **P0/P1 端到端落盘**：模块工程（`.sp`/`.jsonc`）+ `Transform`/`GameObject`/`Scene`/`Application` + 3 个 C VM 系统调用（钩子动态派发 / isEnabled 读写）；`SimEngineTest` 60 项全绿；跨模块 slb 基类虚分发 / 泛型构造两处 VM 缺陷实证并登记（doc/10 §6）；`UIBehaviour` 因双模块根级同名风险暂不入编译集 |
| 2026-11-16 | v0.7 | **P2 数据层端到端落盘**：`MaterialData`/`MeshRef`/`MaterialRef`/`BatchGroup`/`Batcher`（可见收集显式栈遍历 + 键一次读全 + 稳定排序 + 聚组烘焙）；`SimBatchTest` 28 项全绿；跨模块缺陷面大幅扩容实证并登记（List 表达式下标 / 下标写 / 返回值容器 / 递归字段读 / Int32 字段读垃圾 / `_init_` 静态自增 / 跨模块静态方法 / `>=`），规避形态已内置引擎（doc/05 §7、doc/10 §6） |
| 2026-11-16 | v0.8 | **P3 碰撞检测端到端落盘（Box/Sphere）**：`ContactInfo`/`ContactPair`/`BoxCollider`/`SphereCollider`/`CollisionSystem` + Application 固定步自动 step + C VM `CallHook1/2`（带参钩子按名派发）；`SimCollisionTest` 24 项全绿；不做 Collider 基类（字段读规避，doc/11 §2 偏离说明）；碰撞矩阵对称 AND 语义（Array 存储） |
| 2026-11-16 | v0.9 | **双模块同名专项解决**：引擎引用 SLangRender/SLangAudio slb 编译零冲突；**引用顺序规则**（Core/Std/Math 必须最前——坑⑦跨模块静态 mangle 根因修正）；`SimModuleTest` 11 项全绿（Render.Vertex × 引擎 worldMatrix 交叉复用 / Audio.AudioIO 消费 / 同名裸名解析边界）；P2 坑⑦真根因修正（引用顺序而非导出缺陷），引擎消费形态落 doc/10 §1.3 |
| 2026-11-16 | v1.0 | **目录重组 + system/ 系统层落盘**：`system/`（仿 Unity 系统总管：`RenderSystem`——SLang.RenderPipeline 门面 + Batcher 直通组→RenderObject（正交相机 NDC 映射）+ frame 出帧到 RGBA8 原生块；`AudioSystem`——SLangAudio 封装（ensureReady/loadClip/createSource/playSource/probeFile）；`Systems`——三系统总注册门面）；`test/` 收编五套测试（SimEngineTest 60 / SimBatchTest 28 / SimCollisionTest 24 / SimModuleTest 11 / SimSystemsTest 9，共 132 项全绿）；`SimSystemsTest` 实证真实 GL 离屏出帧 + 像素差断言 + 音频加载（无声卡优雅 SKIP）；烘焙组 uploadMesh 全量路径随相机投影专项 |
| 2026-11-16 | v1.1 | **C99 原生库 sl_sim_engine_lib 落盘**：`cvm_sim_engine_lib/`（时间周期：QPC/clock_gettime 单调时钟 + mark 帧标记 + 定时器句柄表；节点管理：FNV-1a 哈希按名注册表，id=句柄复用语义）+ `EngineFfi`/`EngineClock`/`Timer`/`NodeRegistry` SL 封装；GameObject/Scene/Application 接线（nodeId 自动注册注销 / find 裸名 C 哈希 / 帧尾 mark）；jsonc 增 `dllImports` static 预载 + `vmDlls` 构建拷贝；实证坑（dll 必须显式导出 / readUtf8 槽语义 / id 错位 / busy 带上限）落 doc/10 §4.1.1 |
| 2026-11-16 | v1.2 | **test/ 收编为单工程统一入口**：原六套独立工程（.sp/.jsonc/export 各自一套）合并为 `Test.sp/.jsonc` + `Test.sl` 调度入口——套件源码在 `test/suites/`，选套 = `Test.runSuite` 常量（0=全部/1..6=单套）或注释 runAll 分支；各套不再单独 exit，入口汇总 TOTAL 统一退出码；六套 156 项单进程全绿（仍须 Release VM） |
| 2026-11-16 | v1.3 | **P4 轻量物理落盘**（doc/12）：`Rigidbody` + `system/PhysicsSystem`（半隐式欧拉积分 → 驱动 CollisionSystem.step → 位置修正 slop/percent + 法向冲量 + 切向摩擦 4 轮顺序求解 → 休眠管理；`app.physicsSystem` 接入）；CollisionSystem 增实体接触留存接口；`SimPhysicsTest` 25 项新增（第 7 套），七套 **181 项全绿**；两项验收直接覆盖（小球落地稳定入睡 / 每 tick 1/2/4 步帧率一致性终态差 <0.01）；实证坑：ContactInfo.normal **B→A** 约定下照搬 Unity A→B 伪码接近判定反相（接触加速穿透）、休眠判定须在接触求解后、`continue` 未验证避开——落 doc/12 §4/§4.4 与 doc/10 §6 |
| 2026-11-16 | v1.4 | **P5 动画/特效/UI/探针落盘**（doc/06/07/08）：`AnimationClip`（Keyframe/AnimationTrack，写入式 `sample(t, outValue)`）+ `Animation`（play/pause/stop/advance/evaluate，binding 写回 Transform/MaterialRef）+ `system/AnimSystem`（`app.animSystem` 接入，帧序=先采样再 update）+ `Effect`（时间线 + autoDestroy 延迟销毁）+ `LightProbe`/`ReflectionProbe`（数据结构 + 场景收集）+ `UIBehaviour`/`system/UISystem`（pick 后绘制优先 + Enter/Exit/Down/Up/Click/Drag/Scroll 按名派发）；**`RectTransform` 自 SLangRender 迁入本模块**（双模块同名 Transform 继承链致跨模块成员解析失败，Render.jsonc 同步移除、SLangRender 重导出）；`SimAnimTest` 66 项新增（第 8 套），八套 **247 项全绿**；实证坑落 doc/10 §6（文件缺 `import Math` 致 Float32_2 参数方法注册失败、`this._list[0]`/`[i-1]` 初始化局部变量 NotArray、事件计数语义 Exit+Enter=2 / Deselect 不门控） |
| 2026-11-16 | v1.5 | **P3 补全：CapsuleCollider 落盘**（doc/11）：`CapsuleCollider`（center/radius/height，线段沿节点 local +Y）+ 三对窄相（cap/sphere 线段最近点、cap/cap Ericson 5.1.4、cap/box 三候选近似）；CollisionSystem 窄相扩 kind 3×3；胶囊刚体经通用接触接口直接进 PhysicsSystem 求解（落地/休眠验证）；`SimCollisionTest` 24→45 项，八套 **268 项全绿**；实证坑：窄相委托的法线双重约定（方法级 other→self vs 配对级 B→A，B 侧委托须取反——漏取反物理往接触面里压）落 doc/11 §2 与 doc/10 §6 |
| 2026-11-16 | v1.6 | **P4 补全：选择性 CCD 落盘**（doc/12 §6 方案二）：`Rigidbody` 增 `ccdEnabled/ccdMotionThreshold/ccdRadius` + `PhysicsSystem.ccdClip`（离散检测后、求解前：步内位移超阈值经 `CollisionSystem.sweepDistance` 新增公共 AABB 射线扫掠查询钳位到命中面外 + 清速度法向分量保留切向）；`SimPhysicsTest` 25→33 项（穿墙复现/钳位/慢速不受影响/切向保留），八套 **276 项全绿**；v0.1 边界（穿透步事件错拍、钳位余量手动对齐）落 doc/12 §6 |
| 2026-11-16 | v1.7 | **P3 补全：MeshCollider 退化盒 + Render HlslLibrary include 修复**：① `MeshCollider extends BoxCollider`（v0.1 退化形态，doc/11 §2）——`convex` 标记 + 全量继承复用，gather 收 kind=0（窄相 `as BoxCollider` 多态兼容），凸包 GJK/BVH 远期；`SimCollisionTest` 45→52 项，八套 **283 项全绿**；② **Render `HlslLibrary` 9 处非法 `#include Common/Lighting` 首行全删**（doc/05 Roadmap #10 ✅）——拼接由工厂完成，DXC 编译阻塞解除（P6 天空盒 shader 源码就绪，Pass 接线与 cubemap 资源路径待 Render 专项） |
| 2026-11-16 | v1.8 | **P6 第一片：渐变天空背景层落盘**（doc/13 §2.0）：C 管线 `SLR_PROG_SKY` + `draw_sky` vtable 槽（GL/GLES 实现，D3D11/VK 判空）+ `slr_pipeline_set_sky_top/bottom/on` + 阶段 7 相机清屏后插画；SL/引擎侧 `setSkyColor/setSkyEnabled` 全链路转发；`SimSystemsTest` 9→14 项（离屏像素断言），八套 **288 项全绿**；实证坑：C 导出须 vm_sl_render.h 声明表登记、SL FFI 7 参绑定失败（5 参封顶）、RHI 四后端含 .cpp 两文件——doc/13 §2.0 |
| 2026-11-16 | v1.9 | **P7 2D 渲染落盘（引擎层 v1，doc/15 §0）**：`SortingLayers`（排序层→queue 基值映射）+ `SpriteRenderer` + `Tilemap`（数据 + 可见格裁剪顶点烘焙）+ `RenderSystem.collect2D/sync2D`（queue 升序稳定排序 + MESH_QUAD 直通提交）；`Sim2DTest` 55 项新增（第 9 套），九套 **343 项全绿**；实证坑：Behaviour 子类方法含 while 循环时自身字段读失效（循环算法移 static 承载）、循环内常量表达式比较恒真（比较两侧局部变量）、`base`/`out` 保留字——doc/10 §6 / doc/15 §8 |
| 2026-11-17 | v2.0 | **Transform/RectTransform 统一合并入 SLangRender**（复用专项）：引擎自有 `Transform.sl`/`RectTransform.sl` 删除；`Render/Transform.sl` 升级为统一版（Quaternion 全 3D 原语义 + 引擎 Z 轴 TRS 快捷 API 面 `setPosition/setRotationZ/setScale/rotateZ/localMatrix/worldMatrix/worldRotationZ/worldScale/localPosition 别名`；**纯 Z 旋转走 euler 直算逐位精确**——Quaternion 三角 roundtrip 有末位漂移；`worldToLocalMatrix` 升级为 TRS 解析逆含缩放）；`RectTransform` 迁回 Render（同模块 extends Transform，P5 同名继承链断点随引擎侧同名类删除而消失）；引擎 GameObject 层级经 `transform.parentNode` 同步（`_init_/setParent/_detachToRoot/_disposeNow` + `Scene.createObject`）；引擎 16 个文件 + 八套套件补 `import SLangRender`；**`Render.jsonc` 导出坑：binary 格式只写 slb，`.module.json` 需 `--format json` 再导一次**（测试引用 json 元数据，漏导 = 方法 not found）；Render 三件套同步 5 槽位；验证：九套 343 全绿 + RenderTest 全阶段 PASS（GL/D3D11/VK 同效果像素断言）+ SimSceneTest 端到端 PASS（24 顶点/937 帧） |
| 2026-11-17 | v2.1 | **P8 Volume 参数栈 v1 落盘**（doc/14 §0；**计算核心下沉 C FFI**——复用专项约定：重计算一律进 `cvm_sim_engine_lib`，SL 只放类与接口）：`VolumeProfile`（post 三参 + 掩码「缺省=不修改」+ 未支持效果存参数不下发 + unsupportedCount）/`Volume`（weightAt：范围内满权重、blendDistance 外扩段线性衰减、范围外 0）/`VolumeStack`/`system/VolumeSystem.compute`（显式栈收集 → Memory 组块 11 float/Volume → **C `sle_volume_blend`**：稳定插入排序（全局优先→priority 升序→距离升序）+ 掩码 lerp 自中性 (1,1,1) → 解块；绑定失败 <0 → SL 线性兜底）+ `RenderSystem.applyPost` → `setPostEffect`；`SimVolumeTest` 30 项（第 10 套），十套 **373 项全绿**；实证坑：C 插入排序比较方向写反得降序（W4）、`global` 保留字（新踩）、测试 slb 与重导出引擎元数据错位致跨模块 getComponent 静默 miss（编译失败跑旧 slb 假象，重编即消） |
| 2026-11-17 | v2.2 | **P8 完整 SceneImporter v1 落盘**（doc/16 §5）：`SceneImporter`（loadDir/parseCore——两遍建树 + 组件映射 + version 双守卫 + meshIds 登记）+ `ImportReport`（统计）；`SimImportTest` 34 项（第 11 套），十一套 **407 项全绿**；**重大新坑：`tr` 是 Transience 保留字，作变量名触发 `MetaTRStatements` ctor 元崩溃（root is Null、无行号指向，靠 Front 源码 LexerParseToToken.cs `case "tr"` 定位）**——保留字累计 10 个（local/next/half/as/tr/dynamic/base/out/global/def），另 `error`/`errmsg` 是 Result 保留成员名（→lastError）；§8.13 链式/嵌套实参/ret 构造规避形态全量内置 |
| 2026-11-17 | v2.3 | **Mesh GJK 精化 v1 落盘**（doc/11 远期项；**计算核心下沉 C FFI**）：C `sle_points_transform`（行主序 4x4 × float3 点集）+ `sle_gjk_intersect`（标准 GJK 布尔：Minkowski 差支撑扫描 + 单纯形线/三角/四面体最近点与包含判定 + 支撑重复死判，32 迭代上限；EPA 法线远期）；SL `MeshCollider.setMeshVertices/meshVertCount/meshIntersects`（Memory 块缓存一次组块终身持有）+ CollisionSystem 盒-盒窄相 GJK 复核（false 撤销包围盒误报对，无点集走退化盒）；`SimGjkTest` 14 项（第 12 套），十二套 **421 项全绿**；**实证坑：GJK 支撑函数 B 侧漏取反方向**（`argmax_B dot(p,-d)` 误用 `d`——分离用例恰好碰对掩蔽，中段用例全错；独立 C 自测（VsDevCmd + cl 编译 sle_engine.c + 单步 trace 打印）定位——FFI 用例「部分过部分错」优先怀疑 C 侧而非绑定） |
| 2026-11-17 | v2.4 | **GJK/MTV 接触法线与穿透落盘（mesh-mesh 物理闭环）**：C `sle_gjk_mtv`（26 方向采样：6 轴+12 棱+8 角，轴对齐精确/旋转保守近似——规避全量 EPA 复杂度）+ `MeshCollider.meshContact`（覆写 ContactInfo.normal B→A/penetration/point）+ CollisionSystem 窄相精化改 meshContact；`SimGjkTest` 14→22 项（MTV 精确断言 + mesh 刚体落 mesh 地面静置），十二套 **429 项全绿**；EPA 精确法线仍远期 |
| 2026-11-17 | v2.5 | **P7 烘焙组提交收尾（相机投影专项 v1；计算下沉 C FFI）**：C `sle_ortho_bake`（世界→NDC pos2+uv2 仿射，uv=0）+ EngineFfi.libOrthoBake + RenderSystem.sync 烘焙组分支（bakeVerticesInto → 组块 → C 投影 → uploadMesh MESH_CUSTOM slot 0..3 轮转 4096 上限 → 染色/queue；alloc 失败回退 bakedSkipped）；`SimSystemsTest` S10~S14（烘焙三角像素断言），十二套 **434 项全绿**；v1 边界：正交仿射投影（透视 MVP 随相机专项）、烘焙 UV 恒 0（贴图/图集随资源管线）、三连 && 坑再证 |
| 2026-11-17 | v2.6 | **P9 固定形状库 v1 落盘（doc/17；计算核心下沉 C FFI）**：C `sle_shape_counts`/`sle_shape_build`（两段式 counts→build；dst = pos3V+3V+2V 平铺，tris 3T；V/T 规模单一真源 `sle_shape_dims` + 内部计数漂移守卫 -4）+ SL `ShapeTypes`（形状号常量）/`ShapeMesh`（数据容器）/`ShapeFactory`（门面 + 11 个便捷方法）——参考 Unity ProBuilder ShapeGenerator 形状集（Cube/Plane/Sprite/Sphere/Cylinder/Cone/Torus/Prism/Pipe/Arch/Stair，中心原点/Y 上/CCW）；`SimShapeTest` 136 项（第 13 套），十三套 **570 项全绿**；实证坑：**`params` 是保留字**（可变参数关键字，第 11 个保留字）——参数名改 shapeParams；环状形状顶点必须按环独立循环推入（交错推入 + 块状基址引用 = 索引错位）；共享顶点端面（Arch 盖）顶点法线 ⊥ 面法线 dot≈0 属正常（绕序判坏阈值取 dot < -1e-4）——doc/17 §4 |
| 2026-11-17 | v2.7 | **统一时间同步 v1 落盘（doc/18）**：`time/TimeService.sl`（推进状态机：advanceFrame——rawDt<0 = C 单调钟自动实测（推荐宿主形态）、maxDeltaTime 裁剪/暂停/timeScale、固定步长累加器+步数上限防螺旋、EMA smoothDeltaTime、scaled/unscaled 双轨累计）+ `time/EngineTime.sl`（static 快照门面全模块只读：dt/smooth/fixedAlpha/frameCount/elapsed + 域时钟便捷查询 audioNowUs/videoNowUs 等每域一方法——static 常量不作实参）+ `Application.tick` 全链路接入（rawDt=-1 推荐、旧字段全部保留为真源/镜像零破坏、帧尾 updateFixedAlpha）；**域时钟**（render/physics/logic/audio/video，域号 0..5）：域 now = C 单调钟 + 每域 offset（Int64 微秒），音频/视频播放头 snapDomain（seek 一步对齐）/nudgeDomain（渐变 maxNudgeUs=2000/次防爆音）/domainDriftUs（漂移查询）；`SimTimeTest` 71 项（第 14 套），十四套 **641 项全绿**；测试坑：多步断言被 maxDeltaTime 裁剪干扰（上限要随用例调大）、Behaviour 计数探针断言基线要随帧序累加——doc/18 §4 |
| 2026-11-17 | v2.8 | **cubemap 专项第一步（RHI cube 纹理上传，doc/13 §2.1）**：vtable 尾追加 `texture_create_cube(w,h,faces6)`（四后端初始化列表顺序同步——GL/GLES 实现 `gl_texture_create_cube`：GL_TEXTURE_CUBE_MAP 六面 TexImage2D（+X,-X,+Y,-Y,+Z,-Z）+ LINEAR + CLAMP_TO_EDGE 三轴；GL/GLES 常量手写文件补 CUBE_MAP/POSITIVE_X/WRAP_R；D3D11/VK 槽 NULL 判空，P6 draw_sky 同款）+ 注册表 `slr_texture_create_cube`（6 面 RGBA8 top-down 连续块逐面翻行 + `SlrTexRes.is_cube` + 后端不支持 SLR_E_BACKEND）+ vm_sl_render.h 导出 + 门面 `SLang.RenderTexture.createCubeTexture`（d3d11/vk 返 null）；`SimSystemsTest` S15a~S15e（六面组块→创建→句柄→帧不破坏→destroy），十四套 **646 项全绿**；剩余缺口：cube 采样着色器变体（gen 头）/描述符槽/HDR 六面解码/Skybox 组件/GpuTexture.dimension；坑：`base` 保留字第 6 次（S15 变量名） |
| 2026-11-17 | v2.9 | **cubemap 专项第二步（天空采样链路，doc/13 §2.1）+ RenderSystem 对象池泄漏根修**：vtable 尾追加 `draw_sky_cube(void* tex)`（GL/GLES 实现 + D3D11/VK NULL）+ `SLR_PROG_SKY_CUBE` 程序（GLSL330/ESSL300 视线采样 cube；程序枚举尾追加、GEN 检查宏三文件 +1 同步）+ C `slr_pipeline_set_sky_cube` + 阶段 7 分派（cube→渐变回退）+ 诊断导出 `slr_sky_last_mode/slr_sky_draw_diag/slr_sky_prog_handle`（C printf 跨 VM 不可靠 → 状态通道）+ 门面 `setSkyCube/skyLastMode/skyDrawDiag/skyProgHandle` + 引擎 `RenderSystem.setSkyCube`；**S16o 顺带根修（重大）：跨模块 RenderObject 实例入 SL List 污染 _pipe/_id → destroy 静默失败 → 管线对象自 P1 起从未回收（永久泄漏）——对象池改 `List<Int64>` 句柄 + `RenderObject.destroyById` 静态销毁，S16o 断言 objectCount==0**；`SimSystemsTest` S16a~S16g（9 项），十四套 **655 项全绿**；登记待查：SKY_CUBE 程序像素出图（prog=34 有效/无 GL 错/同函数体换 SKY 程序可出图——二分实证；诊断编码 20000+px.r+err）；坑：零参 DllStaticImport 无先例会静默丢成员（诊断导出带 pipe 形参规避）、跨模块 a.b().c() 链拆单步 |
| 2026-11-17 | v2.11 | **透视相机专项（C 核心落盘 + SL 集成暂回退；doc/13 §2.1）**：C `sle_camera_project`（cam9=eye/yaw/pitch/tanHalfFovY/aspect/near/far → 每点 8 float 透视除+线性深度+near/far 裁剪）+ `slr_pipeline_set_sky_cube_cam`（sky_cam 11 float 基向量，FS `uCamFwd/uCamRight/uCamUp/uCamTan` 默认=旧公式向后兼容）+ `draw_sky_cube` vtable 签名带 `cam11` + 门面 `setSkyCubeCam`/绑定 `libCameraProject`；**SL 集成（RenderSystem.setPerspective/syncPersp/updateSkyCamera + S17 测试 14 项）差分验证后回退**——C 直测数值全对（S17g 探针 ndc/depth 精确）、cubemap 多面覆盖像素验证通过（yaw=180° 中心命中 +Z 面蓝色）——但伴随 **Physics 24/Collision 3/Anim 1/Gjk 4 共 33 项回归**（`Application.fixedDt`/`velocity`/CCD dt 系统性失效，回退透视后依旧、失败集随套件执行序漂移）——**根因待查：疑 `Application.fixedDt` ↔ `TimeService.fixedDt` 镜像同步断裂 + VM 跨套件跨模块绑定状态污染（时间同步 v2.7 交互），与透视实现无关**；实现差分记录完整保留 doc/13 §2.1；另：`LOAD_GL(glUniform2f)` 缺失→调用 NULL 挂死（运行时加载表手写——新 proc 必须声明+加载两处同步，proc 声明表 sl_gl_procs.h）；排查期间教训：jsonc 批量编辑 PowerShell scriptblock 回调不支持 `-replace`（会损坏 jsonc→ProjectParseConfigFailed） |
| 2026-11-17 | v2.10 | **cubemap 天空盒像素级出图打通（差分定位 + 懒创建修复，doc/13 §2.1）**：`draw_sky_cube` 改懒创建 SKY_CUBE 程序（首次 draw 在渲染上下文内编译链接 + sampler 设置）——**init 期 `gl_make_shared` 创建的同源码程序渲染期不产出片段**（差分实证链：同函数体换 SKY 程序出图 → 现场重建程序出图 px.r=120 → init 程序 px.r=15=清屏色；全程无 GL 错误、句柄有效——根因细节存疑，规避形态固化）；`SLR_PROG_SKY_CUBE` 移出内建槽（`SLR_PROG_COUNT` 回 GEN_BASE+10、GEN 检查宏三文件去 +1、`s_uni` 相应收敛）；像素断言恢复：中心/角落均命中 -Z 面（**正交视线恒朝 -Z——多面覆盖需透视相机**，边界登记）；`SimSystemsTest` S16e/f/g/h 像素+分派断言，十四套 **656 项全绿** + RenderTest 全阶段 PASS（GL/D3D11/VK 无回归）+ 三件套 5 槽位同步 |
| 2026-11-18 | v2.13 | **材质展厅 + 光源组件落地（doc/19 §4.1）**：新增 `LightData` 引擎光源组件（平行光/点光/聚光 + shadow map 参数 + `setSwing` 脚本写入口；`RenderSystem.applyLights` 每帧收集写管线槽 0..7，固化着色器消费首个平行光+聚光）+ `MaterialData` 扩展 `materialModel`(0..4 固化 HLSL 槽路由)/`shininess`/`texture`（`RenderTexture.loadFile` WIC 解码）+ `RenderSystem.sync` 消费材质（setMaterial/setSpecular/setTexture/setShadow/setQueue）+ `uploadMeshXyz`（3D 顶点→pos2+uv2 自定义槽）；`SceneImporter` 支持 Light 组件与 materialModel/shininess/texture 键 + `ImportReport.textureCount`；示例新增 `MaterialGallery.scene.json`（27 材质球 9×3 共用自定义槽 0 单位圆网格 + 地面 quad + 双灯阴影 + three.js MIT 贴图 3 球；**脚本动效 = 27×SpinScript 浮动相位差 + LightSwingScript 聚光摆走 setSwing 方法**）+ 键 4 切换 + 信息条 nodes/scripts/lights/objs；`assets/shaders/` 存 BasicHLSL11(MIT) 对照——新 HLSL 上线需固化编译链重生成；冒烟 32/32 PASS，引擎十四套回归 623/33（既有项）不变 |
| 2026-11-18 | v2.12 | **场景导出与 SceneManager 落盘（doc/19）**：新增 `SceneExporter`（Scene→scene.json，节点/层级/变换/组件/脚本 + 顶点回写）与 `SceneManager`（按路径 load/loadText、脚本工厂注册表、持有 Application 驱动帧循环、save/toJson round-trip）；`SceneImporter` 扩展 `loadFile` + `Script` 组件挂载 + MeshFilter 顶点/材质颜色/CapsuleCollider 还原；`ScriptResult` 回填槽（工厂形态 `void(JsonValue,ScriptResult)`，`Func<>` 字段/泛型实参触发 MetaCoreCallIssue13，改用已验证的 `List<Function>`）；`gameExample/Test` 落三场景（MaterialBall/ShapeGallery/PureTest）+ 单工程 SceneDemo 双模式（无参数=QT 窗口 1/2/3 切场景、S 导出；`-- smoke`=无窗口冒烟 24/24 PASS，经 `global._inputArgs` 分流）；引擎十四套回归维持 623/33（33 项为 v2.11 已登记既有回归，SimImportTest 34/0 未受影响）；坑：`label` 是词法保留字、`ret` 表达式跨行 `+` 触发解析失败、`Func<>` 不能作 List 元素（MetaCoreCallIssue13）、Release JIT 下高频标量 `toString()` 返回 null（导出改走 `String.toFormat` 通道）、`write_to_file` 超长内容可能静默未落盘（需落盘后核验） |
| 2026-11-19 | v2.16 | **Camera / Light 实体落盘（Unity 形态：extends GameObject + Data 组件）**：① `CameraData`（`CameraData.sl`，`extends Behaviour`）——相机数据组件，常量/默认值 + setter（正交/FOV/orthographicSize/clip/aspect/cullingMask/depth/clearFlags/背景色）+ 裁剪面修正 + 投影矩阵（透视/正交）+ 正交半宽；② `Camera`（`Camera.sl`，`extends GameObject`）——构造期挂 CameraData 组件（`getComponent<CameraData>()` 可查）+ 参数转发 + 四类矩阵能力：**投影/视图**（projectionMatrix/cameraToWorldMatrix/worldToCameraMatrix/viewProjectionMatrix）、**坐标转换**（worldToViewportPoint/viewportToWorldPoint/worldToScreenPoint/screenPointToRay）、**TRS**（transformPoint/transformDirection/worldToLocal/localToWorld/inverse*）、**裁剪面**（clampClipping/near/far/orthographicHalfWidth）；③ `Light`（`Light.sl`，`extends GameObject`）——构造期挂 LightData 组件 + directional/point/spot 工厂 + 参数转发 + 世界方向/位置 + 距离/锥角衰减；④ GameObject 开放 `_children/_scene` 为 public（供子类 `_init_` 复制节点初始化——SLang 子类构造不自动调父类 `_init_`）；⑤ `SimCameraLightTest` 53 项（第 18 套）——十八套 **880/33**（33 为 v2.11 既有 fixedDt 回归，无新增）。命名遵循 R22（贴合 Unity3D）。**本轮只建结构 + 矩阵方法，未接 RenderSystem 相机/光照消费链路（by design）**。新踩坑：`data` 是词法保留字（字段改 cameraData/lightData）、`range` 保留字、`cam.transform.position=` 跨模块字段链需先落 Transform 局部变量 |
| 2026-11-19 | v2.15 | **UI 画布两模式 + 引擎层图层叠加落盘（doc/08 §8）**：① `UICanvas`（`ui/UICanvas.sl`）管理节点组件——`MODE_SCREEN_OVERLAY=0`（系统叠加，引擎自动挂 layer31/depth10/只清深度的 UI 相机，无需赋值相机）/ `MODE_CAMERA=1`（相机赋值，按 sortingOrder 编排相机栈 clearFlags=2 保留底图实现相机处理后图层叠加）/ `MODE_WORLD=2`（世界空间，extents 按 refW/refH÷scale 换算）+ 字段校验 setter；② `system/UICanvasSystem.sl`——`collect(scene)` 显式栈收集激活画布 + (mode,order,树序) 稳定插入排序 + `configure(rs)` 把模式落到管线相机 + `composite()` 引擎层 RGBA8 图层叠加；③ C 核心 `sle_layer_composite`（ALPHA/ADD/MULTIPLY，alpha 钳 [0,1]）+ `EngineFfi.libLayerComposite`；④ `Systems.setupCanvas/compositeLayer` 门面；⑤ `SimUICanvasTest` 50 项（第 17 套）——十七套 **827/33**（33 为 v2.11 既有 fixedDt 回归，无新增）|
| 2026-11-19 | v2.14 | **2D 游戏类型支撑 v1 落盘（doc/15 §9）**：① `CameraRig2D`——2D 正交相机适配器（非 Behaviour，每帧显式 `update(rs,dt)`）：宽高比三模式（0 MatchHeight 纵向恒定/1 MatchWidth 横向恒定/2 PixelPerfect `scale=floor(pixH/refPixelHeight)` 下限 1）+ 目标跟随（`smoothTime` 指数平滑 `f=1-exp(-dt/τ)`，首帧硬切）+ 地图边界钳制（视野大于地图自动居中，`snap()` 重置）；② `Tilemap` 网格语义补全——`cellXAtWorld/cellYAtWorld`（floor 换算，越界返回计算值）+ tile 属性表（`setTileFlag/tileFlag/isSolidAt`，按图集索引 bit0=solid，稀疏扩容静态承载）；③ `TileColliderBaker.bakeRowColliders`——同行连续实心格合并成段，每段一个子 GameObject + BoxCollider（横版/俯视通用，不逐格建节点）；④ `ParallaxLayer`——视差背景层组件（`pos = base + (cam-anchor)*(1-f)`，f=1 随世界/f=0 贴屏，首次 apply 自动 captureBase）；⑤ `RenderSystem.setPixelSize/pixelWidth/pixelHeight/aspectValue`——无头像素尺寸登记 + aspect 公开门面（无管线也可用）；`Sim2DTest` 55→104 项（D13 像素尺寸/D14 三模式/D15 跟随钳制平滑/D16 worldToCell/D17 tile 属性/D18 碰撞生成/D19 视差层），十四套 **715/32**（32 项 FAIL 全部为 v2.11 已登记 fixedDt 既有回归族 PH/CC/AN/G，无新增）；新文件四件均入 jsonc compileFiles + struct 根级 |
