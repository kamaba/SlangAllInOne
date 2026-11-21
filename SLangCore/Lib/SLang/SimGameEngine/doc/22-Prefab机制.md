# SimGameEngine · 22 Prefab 机制

> 状态：**v2.19 已落盘（2026-11-20）**：Prefab = GameObject 子树 JSON，与 scene.json 同构；读取直接复用 `SceneImporter.parseCore`、写入复用 `SceneExporter.collect/nodeOf/nodesToJson`（零重复解析/序列化代码）；`SceneManager` 增加 `prefabToJson/prefabSave/prefabLoad/prefabLoadText/prefabInstantiate/instantiate/instantiateText` 七个门面；导出侧补齐 Light/Volume，使组件 round-trip 对称；SimPrefabTest 46/0，全套件 1009 PASS / 33 FAIL（33 = 既有 fixedDt 存量，零新增）。

## 1. 设计约束（用户定案）

- Prefab 内容 = 「保存 GameObject 节点及其上每个节点的内容（组件）」。
- 与 Scene 内容形态相近，**读取代码必须共用**。

由此定案：Prefab 文件就是 scene.json 同构的 `{version:1, scene:<名>, nodes:[...]}`，只是根节点通常只有一个。共用边界：

| 能力 | 共用落点 | Prefab 侧无需重写 |
|---|---|---|
| JSON → 节点树 | `SceneImporter.parseCore(1, text)` | 两遍建树、变换、层级、属性、全部组件映射、脚本工厂、资源登记 |
| 节点树 → JSON | `SceneExporter.collect` + `nodeOf` + 新增 `nodesToJson` | DFS 扁平化、字符串转义、组件序列化 |
| 实例化场景归属 | `SceneManager._rewalkScene` | 子树 `_scene` 重指（与 additive 子场景同款） |

## 2. 实现要点

### 2.1 写入侧

- `SceneExporter.nodesToJson(name, order, parents)`：从「DFS 顺序 + 父 id 平行表」生成完整 JSON —— `toJson(Scene)` 与 `toJsonRoot(GameObject, name)` 共用此核心。
- `toJsonRoot(root, prefabName)`：`collect(root, 0, ...)` 把 Prefab 内部根写成 `parent=0`；名字缺省取根节点名。

### 2.2 读取侧

- `prefabLoadText(json)` / `prefabLoad(path)`：`File.readAllText` → `parseCore(1, text)` → 未并入 activeScene 的模板 Scene（复用 ImportReport 统计与错误）。
- `prefabInstantiate(template, parent)`：`template.roots()` 逐个搬移——
  - `parent != null`：`setParent(parent)` 自动从模板根列表摘除并挂父；
  - `parent == null`：`template.removeRoot(r)` + `target.addRoot(r)`；
  - 然后 `_rewalkScene(r, target)` 重指整棵子树 `_scene`。
- 每次 `instantiate*` 都重新 `parseCore` 生成新对象树：JSON id 自动重映射，NodeRegistry 节点随对象走（按名哈希，同名实例的运行时 id 相同是设计）。

### 2.3 导出对称性补齐

`SceneExporter.componentOf` 原先没有 LightData / Volume 分支，二者会落进 `Behaviour` 兜底被写成 `{"type":"Script","script":"Volume"}`，而导入器无对应工厂 → round-trip 丢组件。现补：

- `LightData` → `{type:Light, lightType, color, intensity, dirX/Y, posX/Y, spotAngle, range, shadow*}`（与 SceneImporter 的 Light 分支逐字段对称）。
- `Volume` → `{type:Volume, isGlobal, priority, weight, blendDistance, ...profile 字段}`；只写 `hasXxx` 为真的字段，与导入器 `select()` 判空 = 不改写的缺省语义对称。
- 新增 `SceneExporter.f(Float32)` 统一走 `String.toFormat`，规避 Release JIT 高频标量 `toString()` 返回 null 的既有坑。

## 3. 测试与验证

`SimPrefabTest`（第 21 套，已登记 `Test.jsonc` priority 9 + `Test.sl` `runPrefab()`）：

- P2 序列化 JSON 结构（version/name/双节点/parent/组件/tag）；
- P3 文件往返 + 模板层级 + 挂父实例化；
- P4 多次实例化独立（对象/变换不同，tag 改动互不干扰）；
- P5 Light/Volume 组件 round-trip（导出类型正确 + 字段/掩码恢复）；
- P6 错误路径（空根、空文本、缺文件、空节点表）。

结果：单套 46/0；全套件 1009 PASS / 33 FAIL（33 为 v2.11 既有 fixedDt 回归族，无新增）。

## 4. 坑与边界

1. `SceneManager.prefabInstantiate` 中 `parent` 可能是独立节点（`_scene == null`）——目标场景回退到 `activeScene`，否则误报 "no target scene"。
2. `File.writeAllText` 不创建目录——测试路径与用户路径都必须预先存在目录。
3. 测试里 `root.transform.setPosition(...)` 触发跨模块链式调用解析失败（`MetaCoreParseCallNodeNotFoundInClass`）——先落 `Transform` 局部变量再调。
4. `string` 无 `contains`——JSON 结构断言统一用 `JsonValue.parse(...).select(path)` + `asXxx(default)`。
5. Script 自定义参数、CameraRig2D、Volume.influenceBounds 目前不在通用序列化清单内（与 Scene 导出边界一致）。
