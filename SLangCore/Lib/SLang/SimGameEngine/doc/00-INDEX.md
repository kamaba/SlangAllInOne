# SimGameEngine 文档索引

> 版本：v0.7（16 章设计稿，2026-11-16；P0/P1/P2 数据层已端到端落盘并验证）
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
- 用节点类型区分 Camera / Light / Probe / UI 等特殊对象；
- 用碰撞体与固定步长物理处理重叠、接触与刚体运动（第 11/12 章）；
- 用天空盒、环境光与 Volume 参数栈组织画面氛围（第 13/14 章）；
- 用 QUAD / 动态网格承接 2D 精灵与 Tilemap（第 15 章）；
- 用 Unity Editor 导出器输出独立 JSON 资源，供引擎导入建场景（第 16 章）；
- 用 FBX SDK 转换器把通用模型文件汇入同一格式，材质 shader 用通用 HLSL 源文件（第 16 章）。

一句话：**SimGameEngine 管「scene 里有什么、谁更新谁、谁该被合并」，Render 管「怎么画出来」。**

---

## 2. 文档清单（16 章 + 索引）

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
| 15 | `15-2D渲染.md` | SpriteRenderer、排序层、图集合批、正交相机、Tilemap、2D 物理 | 写 2D 游戏的人 |
| 16 | `16-Unity资源导入与导出.md` | Unity 原生格式解析判定、Editor 导出器、FBX SDK 转换器（ufbx 选型）、JSON schema、通用 HLSL shader 与 DXC 编译链、引擎导入器、坐标约定 | 做资源管线的人 |

阅读顺序：`01 → 02 → 03 → 04 → 05 → 06/07/08 → 09 → 10 → 11/12 → 13/14 → 15 → 16`。只关心接入的可直接读 `10`。

---

## 3. 状态图例（全文通用）

本套文档混有「已经能调用」与「尚在设计中」两类内容，所有 API 与类均按下列标记区分，请勿把设计稿当成现成接口：

| 标记 | 含义 | 判定依据 |
|---|---|---|
| 【已落盘】 | 源码已存在，签名可直接核对 | `SimGameEngine/*.sl`、`Render/SLangRender/*.sl` |
| 【设计稿】 | 本文提出的目标形态，尚未落盘 | 只有本文描述，无对应 `.sl` |
| 【依赖待建】 | 两侧都已存在，但工程引用 / 绑定关系尚未建立 | 如 `UIBehaviour` → `RectTransform` |

现状一句话（2026-11-16，P0/P1/P2 数据层端到端）：模块已是可编译、可导出、可运行的库模块（`SimGameEngine.sp/.jsonc`，产物 `out/export/SimGameEngine/`）。【已落盘】= 场景核心五件（`Transform` / `GameObject` / `Scene` / `Application` / `Behaviour`）+ 空间工具三件（`Bounds` / `Plane` / `Ray`）+ P2 渲染资源五件（`MaterialData` / `MeshRef` / `MaterialRef` / `BatchGroup` / `Batcher` 合批数据层）+ 三个 C VM 系统调用（`SystemSimEngineCallHook` / `SetEnabled` / `GetEnabled`，见 §6 缺陷说明）；`SimEngineTest` 60 项与 `SimBatchTest` 28 项断言全绿。仍为【设计稿】：合批 Submit 段（随双模块同名专项）、Animation/Effect/Probe、碰撞、物理、天空盒、Volume、2D 精灵、`UIBehaviour` 的 RectTransform 接线（P3~P8）。Render 侧仍是【已落盘】的可运行模块。

---

## 4. 术语对照（Unity ↔ SimGameEngine ↔ SLangRender）

| Unity | SimGameEngine | SLangRender 侧对应 | 状态 |
|---|---|---|---|
| GameObject | GameObject（本文定义） | 无（Render 不持有此概念） | 设计稿 |
| Transform | Transform / RectTransform | `RenderTransform`（数据） | 设计稿 / Render 已有数据类 |
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
| Collider / Rigidbody | Collider / Rigidbody 组件 | 无（Render 不处理物理） | 设计稿 |
| Skybox / Environment | Skybox 组件 + `setAmbient` | Skybox shader 素材有 bug、Pass 未接入 13 阶段；`setAmbient` 已落盘 | 部分落盘 |
| Volume / VolumeProfile | Volume 组件 + 参数栈 | PostProcessPass 已落盘（亮度/饱和度/暗角）；Volume 参数栈 P2 未开始 | 设计稿 |
| SpriteRenderer / Tilemap | SpriteRenderer / Tilemap + 排序层 | `MESH_QUAD` / `uploadMesh` / 正交 `setCamera` 已落盘 | 部分落盘 |
| AssetDatabase / 编辑器资源管线 | 第 16 章导出器 + `SceneImporter` | 无（纯资源层，不进渲染） | 导出器落点已核实 / 本体设计稿 |

---

## 5. 变更记录

| 日期 | 版本 | 变更 |
|---|---|---|
| 2026-11-16 | v0.1 | 初版 10 章：按 Render 的「纯渲染引擎」边界切出宿主引擎职责，完成节点树 / 组件 / 合批 / 相机光照 / 动画特效 / UI / 帧循环的整体设计整合 |
| 2026-11-16 | v0.2 | 补 5 篇独立文档：碰撞与触发器、物理引擎、天空盒与环境、Volume 效果处理、2D 渲染；同步总纲 / 路线 / 术语对照 |
| 2026-11-16 | v0.3 | 补第 16 章：Unity 原生格式解析判定（不可行 → 自建导出系统）、Editor 导出器落点与 JSON schema、引擎侧 SceneImporter 与坐标约定 |
| 2026-11-16 | v0.4 | 第 16 章扩充：FBX SDK 转换器路径（ufbx 起步选型、离线 CLI、烘焙单位轴向）；材质 shader 升级为通用 HLSL 源文件（三态映射、DXC 编译链、跨后端如实边界、编译缓存） |
| 2026-11-16 | v0.5 | **端到端落地**：Unity 导出器 `SlangSceneExporter.cs` 落盘（flag `export-scene`/`export-cube`），引擎侧 `test/Other/SimSceneTest` 验证 Unity CubeDemo → SLangRender 渲染 PASS（24 顶点 / 937 帧 @15s）；第 16 章状态升级为「已落盘，端到端已验证」 |
| 2026-11-16 | v0.6 | **P0/P1 端到端落盘**：模块工程（`.sp`/`.jsonc`）+ `Transform`/`GameObject`/`Scene`/`Application` + 3 个 C VM 系统调用（钩子动态派发 / isEnabled 读写）；`SimEngineTest` 60 项全绿；跨模块 slb 基类虚分发 / 泛型构造两处 VM 缺陷实证并登记（doc/10 §6）；`UIBehaviour` 因双模块根级同名风险暂不入编译集 |
| 2026-11-16 | v0.7 | **P2 数据层端到端落盘**：`MaterialData`/`MeshRef`/`MaterialRef`/`BatchGroup`/`Batcher`（可见收集显式栈遍历 + 键一次读全 + 稳定排序 + 聚组烘焙）；`SimBatchTest` 28 项全绿；跨模块缺陷面大幅扩容实证并登记（List 表达式下标 / 下标写 / 返回值容器 / 递归字段读 / Int32 字段读垃圾 / `_init_` 静态自增 / 跨模块静态方法 / `>=`），规避形态已内置引擎（doc/05 §7、doc/10 §6） |
