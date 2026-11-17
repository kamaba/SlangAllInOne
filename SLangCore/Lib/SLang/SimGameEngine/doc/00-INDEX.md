# SimGameEngine 文档索引

> 版本：v2.1（16 章设计稿，2026-11-17；P0~P7 落盘 + **Transform/RectTransform 统一合并入 SLangRender（引擎自有类删除，全仓复用）** + **P8 Volume 参数栈 v1（混合数学核心在 C：sle_volume_blend）** + system/ 系统层 + test/ 统一测试入口（Test.sl，十套 373 项）+ C99 原生库 sl_sim_engine_lib）
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

现状一句话（2026-11-16，P0~P5 端到端 + C99 原生库 + P7 引擎层 v1）：模块已是可编译、可导出、可运行的库模块（`SimGameEngine.sp/.jsonc`，产物 `out/export/SimGameEngine/`）。【已落盘】= 场景核心五件（`Transform` / `GameObject` / `Scene` / `Application` / `Behaviour`）+ 空间工具三件（`Bounds` / `Plane` / `Ray`）+ P2 渲染资源五件（`MaterialData` / `MeshRef` / `MaterialRef` / `BatchGroup` / `Batcher` 合批数据层）+ P3 碰撞六件（`ContactInfo` / `ContactPair` / `BoxCollider` / `SphereCollider` / `CapsuleCollider` / `CollisionSystem`）+ P4 物理两件（`Rigidbody` / `PhysicsSystem`：半隐式欧拉 + 顺序冲量 + 休眠）+ P5 动画/UI 六件（`AnimationClip` / `Animation` / `Effect` / `LightProbe` / `ReflectionProbe` / `UIBehaviour` + `RectTransform`（自 SLangRender 迁入）+ `AnimSystem` / `UISystem`）+ **P7 2D 三件（`SortingLayers` / `SpriteRenderer` / `Tilemap` + `RenderSystem.collect2D/sync2D`，doc/15 §0）** + C99 原生库三件（`EngineClock` / `Timer` / `NodeRegistry`，底层 `sl_sim_engine_lib.dll`）+ 五个 C VM 系统调用（`SystemSimEngineCallHook` / `CallHook1` / `CallHook2` / `SetEnabled` / `GetEnabled`）；九套测试 343 项全绿（`SimEngineTest` 60 / `SimBatchTest` 28 / `SimCollisionTest` 52 / `SimModuleTest` 11 / `SimSystemsTest` 14 / `SimFfiTest` 24 / `SimPhysicsTest` 33 / `SimAnimTest` 66 / `Sim2DTest` 55，统一入口 `test/Test.sl`）。仍为【设计稿】：Mesh GJK/BVH 精确碰撞、cubemap 天空盒全链路、Probe 采样/混合、Volume、2D 的翻转 UV / 图集 UV / uploadMesh 合批提交（P6~P8 剩余段）。Render 侧仍是【已落盘】的可运行模块。

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
