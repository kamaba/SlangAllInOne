# SimGameEngine · 05 合批与 RenderObject 提交（核心章）

> 状态：RenderObject 字段写入【已落盘】；引擎侧合批器【已落盘 2026-11-16，数据层（CollectVisible/BuildBatches/排序/烘焙）端到端验证，Submit 段由调用方按 §4 映射表驱动 SLangRender】。
> 前置阅读：`04-渲染资源模型.md`。
> 参考：`../Render/doc/01-Overview.md` §0.1（C 层 PerDraw std140 分组批）、`../Render/doc/05-Roadmap-And-Conventions.md`（M7 不承诺项）、`../Render/doc/13-Usage-Guide.md` §2。

---

## 1. 要解决的问题

Unity 里一个场景有几千个 GameObject，但 draw call 只有几百个——因为相同 Shader + 相同 Material 的 Mesh 被聚合成批次提交。

本模块用同一思路，但分工不同：

| 层次 | 谁做 | 做什么 |
|---|---|---|
| 引擎层合批（本文） | SimGameEngine | 把 N 个可见 Renderer 归并成 M 个 RenderObject（M ≤ N），烘焙变换、合并顶点 |
| 渲染层分组（已有） | `sl_render_lib.dll` | 13 阶段中的 prepareMaterials / assembleLayerData / renderShaderChunks，按 shader 段与 PerDraw std140 UBO 分组批渲染 |

两层不冲突：**引擎层减少 RenderObject 数量，渲染层减少 GPU 状态切换和 draw**。Render 的 M7 把 SRP Batcher 式合批 / RenderGraph / GPU driven culling 列为不承诺项，因此 CPU 侧批次组织必须由本模块承担。

## 2. 合批键（BatchKey）【已落盘】

只有键完全相同的可见对象才能进同一批。键分量按优先级排序：

| # | 键分量 | 取值来源 | 不放进键会怎样 |
|---|---|---|---|
| 1 | `shaderProgram` | `Material.resolveProgram()` | 不同 program 的顶点/片元语义不同，混批直接画错 |
| 2 | `materialInstance` | Material 对象身份（不是名字） | 共享材质的参数会被某个节点覆盖，影响其他节点 |
| 3 | `meshKind / meshSlot` | `MeshRef.meshSlot` 或内置网格枚举 | 顶点布局 / 拓扑不同，无法合并到同一槽 |
| 4 | `layer` | GameObject.layer | 相机的 `cullMask` 以 layer 为单位剔除，混批会让位掩码失效 |
| 5 | `renderQueue` | `MaterialRef.renderQueue` | 不透明段（<2500）与透明段（≥2500）的排序/混合语义不同 |
| 6 | `specular` / `shadow` | `MaterialRef.specular` / `castShadow` | RenderObject 有独立字段，参数不同必须分批 |
| 7 | `texture` | Material 的贴图句柄 | 不同贴图无法同批（除非先用图集统一） |
| 8 | `animatedMode / speed` | Animation 组件输出（P5 前为 `MaterialRef.animatedMode/animatedSpeed`） | `setAnimated` 是批次级参数，相位不同会一起动 |
| 9（补强） | `实例色` | `MaterialRef.instanceColor`（`instanceColorOverride` 时） | `setColor` 是 RenderObject 级字段，合批后作用于整批——不同实例色必须拆批 |
| 身份 | `材质实例` | `MaterialData` 对象引用（`assetId` 自增仅调试用） | 共享材质的参数会被某个节点覆盖，影响其他节点 |

实现（`Batcher.sl`，已落盘）：候选键值在 collect 时一次性读入平行数组（跨模块字段读只在收集上下文做一次，见 §7 坑 8），排序为「新列表 + insert」稳定插入法（renderQueue 升序），聚组为线性扫同键组，组内对象数达 `maxObjectsPerBatch`（默认 256）开新批。

### 2.1 明确不合批的情况

- 透明对象：`renderQueue >= 2500` 需要按深度排序，不能与不透明对象合并；
- 有独立动画相位的对象：进键分量 8；
- Shader 不同、材质实例不同、贴图不同：进键分量 1/2/7；
- 节点激活态不同：禁用节点压根不进可见候选；
- 被不同相机剔除的对象：layer 不同（键分量 4）。

## 3. 批次生成流程【已落盘（CollectVisible/BuildBatches）；Submit 段调用方驱动】

```
Batcher.collect( scene, cullMask )            # 【已落盘】
   ├─ 显式栈先序遍历（父先子后；未激活节点整棵剪枝——不用递归，§7 坑 8）
   ├─ 过滤 activeInHierarchy / (1<<layer) & cullMask / MeshRef.visible / 材质就绪
   └─ 键数据一次性读入平行数组（queue/program/texture/kind/slot/layer/
      animMode/specular/animSpeed/shadow/colorOv/color/材质引用）

Batcher.sortCandidates()                       # 【已落盘】稳定插入排序（queue 升序）

Batcher.build()                                # 【已落盘】按键聚组（线性扫同键组）
   ├─ 成员无顶点数据（hasVertexData=false）→ 单对象直通组（§3.1 例外路径）
   ├─ 成员有顶点数据 → 同键聚组，满 256 开新组
   └─ 组访问用 bt.groupAt(i)（跨模块返回 List 容器不可靠）

BatchGroup.bakeVerticesInto( outList )         # 【已落盘】顶点烘焙（调用方传容器）
   └─ local 顶点 × worldMatrix → 世界空间顶点（提交方 uploadMesh 槽位）

Submit(pipe, batches, camera, lights)          # 【调用方按 §4 映射表驱动】
   ├─ pipe.setCamera( cullMask, l, r, b, t )
   ├─ 灯光 applyTo( pipe, slot )
   └─ pipe.renderFrame( time, dstPtr )  /  pipe.runStages( time, dstPtr )

Recycle()
   └─ 本批未复用的 RenderObject → destroy()，归还池
```

### 3.1 变换烘焙：必须处理的设计约束

RenderObject 只有**一组** position / rotation / scale 字段，而一个批次里通常有多个世界变换不同的 GameObject。因此：

- **默认策略**：合并顶点时把每个节点的 `localToWorld` 乘进顶点坐标，合并后的动态网格已是世界空间；对应 RenderObject 的 transform 保持单位值；
- **例外**：若某批只有一个对象，可把变换写进 RenderObject（`setPosition/setRotationZ/setScale`），顶点保持模型空间，便于运行时移动；
- **不要**把多个不同世界变换的对象塞进一个 RenderObject 却只写其中一个的 transform——其余对象会全部错位。

这是「合批」与「可单独移动的物体」之间的根本权衡：合批越激进，单对象自由度越低。需要频繁独立移动的对象应留在例外路径或单独分批。

## 4. RenderObject 字段映射【已落盘】

RenderObject 是 C 句柄门面，以下方法返回 bool（成功与否），建议检查返回值定位无效句柄。

| 批次 / 节点数据 | RenderObject 写入 | 说明 |
|---|---|---|
| 可见开关 | `setVisible(bool)` | 与 Renderer.setVisible 同步 |
| layer | `setLayer(int)` / `.layer` | 示例：`quad.layer = 1`；与相机 `cullMask` 配合 |
| renderQueue | `setQueue(int)` | ≥2500 走透明段 |
| 世界位置 | `setPosition(...)` | 仅单对象批使用（§3.1） |
| 世界 Z 旋转 | `setRotationZ(...)` | 当前 RPC 只提供绕 Z 轴旋转；复杂旋转需烘焙进顶点 |
| 世界缩放 | `setScale(...)` | 同上 |
| 实例颜色 | `setColor(...)` | 需 shader 支持 |
| 贴图 | `setTexture(RenderTexture)` | 也可由 Material 带入 |
| 内置动画 | `setAnimated(mode, speed)` | 例：`tri.setAnimated(pipe.ANIM_HUE_CYCLE, 0.05f)`；mode 由管线提供 |
| 高光 | `setSpecular(...)` | 进合批键 |
| 阴影 | `setShadow(...)` | 进合批键 |
| 材质槽 | `setMaterial(int)` | int 为 Render 侧材质槽位 |
| 网格 | `pipe.addObject(meshKind)` / `pipe.uploadMesh(slot, ptr, n)` | 前者取对象句柄，后者写动态网格数据 |
| 销毁 | `destroy()` | 帧尾回收，不要跨帧持有已销毁句柄 |

### 4.1 最小提交样例（Render 现有 API）

```sl
import SLangRender;

SLang.RenderPipeline pipe = SLang.RenderPipeline.create( 256, 256 )

# 一个批次 = 一个 RenderObject
SLang.RenderObject tri = pipe.addObject( pipe.MESH_TRIANGLE )
tri.setAnimated( pipe.ANIM_HUE_CYCLE, 0.05f )   # layer 0 不透明，动画参数按批设置

SLang.RenderObject quad = pipe.addObject( pipe.MESH_QUAD )
quad.layer = 1                                   # queue >= 2500 走透明段

pipe.setCamera( cullMask, l, r, b, t )            # 由 Camera 组件提供
pipe.renderFrame( t, pixels )
tri.destroy()
quad.destroy()
pipe.destroy()
```

引擎侧的合批器就是把这段手写流程自动化：为每个 BatchGroup 重复 `addObject + set* + uploadMesh`，并管理句柄生命周期。

## 5. 与 13 阶段管线的协作

Render 的 `renderFrame` / `runStages` 内部按固定阶段执行（`../Render/doc/01-Overview.md` §0.1、09 文档）：

```
beginFrame → prepareMaterials → earlyUpdate → cullLayers → assembleLayerData
→ uploadRenderData → renderShaderChunks → updateCoreTime → renderShaderSegments
→ assembleRenderedLayers → postProcess → integrateLayers → renderTexture 输出
```

引擎侧要做的事对应到阶段边界：

| 阶段 | 引擎侧动作 |
|---|---|
| `beginFrame` 之前 | 完成 §3 的 Collect / Build / Write，所有 RenderObject 已就绪 |
| `cullLayers` | 由 `setCamera(cullMask, ...)` 给出 layer 掩码，与合批键分量 4 一致 |
| `prepareMaterials` | 材质槽已由 `setMaterial(int)` 固定；不要在阶段中途改材质 |
| `uploadRenderData` | 动态网格在 `uploadMesh` 时已写入，本阶段消费 |
| `renderShaderChunks` / `renderShaderSegments` | 按 program 分段渲染，合批键分量 1 决定分段归属 |
| `postProcess` | Effect 组件若要挂后处理，参数在本阶段前写入（第 07 章） |
| 帧尾 | 统计 `pipe.stat(pipe.STAT_DRAW_CALLS)` 验证合批效果，然后回收句柄 |

调试时可用 `pipe.runStages(t, pixels)` 逐阶段驱动，观察批次在哪一段被拆开。

## 6. 验证与调参

| 指标 | 获取方式 | 期望 |
|---|---|---|
| draw call 数 | `pipe.stat(pipe.STAT_DRAW_CALLS)` | 合批后明显低于 RenderObject 数量增长 |
| 批次数 | 合批器自己的 `batches.length` | 远小于可见 Renderer 数 |
| 单批顶点数 | `uploadMesh` 的 n 累计 | 不超过设计上限（256 对象） |
| 视觉一致性 | 开 / 关合批对比同一帧 | 位置、颜色、动画相位一致 |

建议先做「单对象直通」路径（每对象一个 RenderObject，变换写字段），跑通后再开合批，用对照帧排查错位；不要一开始合并全部节点。

## 7. 已知坑与注意

1. **`Renderer.render()` 不可用**：恒返回 false，旧 `Render.drawMesh` 已移除；一切提交走本章路径。
2. **layer 位必须一致**：节点 layer N 与相机 `cullMask` 的 `1<<N` 对不上，对象会「明明可见却没画」。
3. **`setRotationZ` 只有 Z 轴**：需要 X/Y 旋转时把旋转烘焙进合并顶点，不要指望字段表达。
4. **后端切换作废旧句柄**：切换 gl/d3d11/vk/gles 后必须销毁并重建全部 RenderObject / Material / Texture，再重建批次。
5. **透明批次别合并**：`renderQueue >= 2500` 的对象排序敏感，合并会破坏透明叠加顺序。
6. **动画相位是批次级参数**：`setAnimated(mode, speed)` 作用于整个 RenderObject；一个批次里放不同相位的动画对象会同步运动。
7. **合批器【已落盘】**：数据层（collect/sort/build/bakeVerticesInto）可用（`SimBatchTest` 28 项全绿）；Submit 段由调用方按 §4 映射表驱动 SLangRender——注意引擎与 Render 双模块根级 `Transform`/`Ray` 同名，同工程引用两模块需专项验证（doc/10 §6）。
8. **跨模块对象字段读的上下文依赖（VM 缺陷，SimBatchTest 实证）**：Behaviour 子类实例的 Int32 字段（如 `MaterialRef.renderQueue`）跨模块读可能返回垃圾且 `== 常量` 比较失效；同一读取代码在递归方法内失效、非递归上下文可靠。规避（引擎已内置）：① collect 用显式栈遍历（不用递归）；② 「跟随材质」判定用 `< 1` 形态（勿 `== 0`/`== -1`）；③ 键值在收集上下文一次读入平行数组，sort/build 只消费标量；④ 材质身份用对象引用比较（`!=` 引用语义可靠，同 List.indexOf 先例）；⑤ `_init_` 内静态字段自增会破坏后续字段读——身份分配放静态工厂。
9. **List 容器跨模块陷阱**：① 表达式下标 `list[i - 1]` 解析失败（报 not array and no _getItem_），下标先落局部变量；② 下标写（`_setItem_` override）跨模块静默失效——交换/排序用 `insert`/`removeAt` 等普通方法；③ 方法返回值形态的 List 容器（如 `roots()`）跨模块读出坏值——用 `rootCount/getRoot` 单对象返回；④ `List<Int32>`/`List<Float32>` 值类型泛型声明曾经编译失败（现 `List<Int32>` 可用），struct 泛型（`List<Float32_3>`）可靠；⑤ 循环条件 `>=` 不生效——用 `> 0 - 1` 等价替换。
10. **跨模块静态方法不可用**：`MeshRef.create(...)` 等静态工厂经 IR 签名错位（`create_1_Core.Object` not found）——消费方用构造器 + 实例方法（`useTriangle/useQuad/useCube`）。
