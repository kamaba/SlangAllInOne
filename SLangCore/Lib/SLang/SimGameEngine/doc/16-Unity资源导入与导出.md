# SimGameEngine · 16 Unity 资源导入与导出（含 FBX 与通用 HLSL）

> 状态：Unity 导出器【已落盘，端到端已验证】；JSON schema【有参考实现】；FBX 转换器 / 通用 HLSL 链路【设计稿】；**引擎侧完整 SceneImporter v1【已落盘 2026-11-17】**（manifest/scene.json → 建树挂组件，`SimImportTest` 34 项；mesh.bin 深解析仍走 SimSceneTest 最小消费路径）。
> 前置阅读：`01-总体架构与边界.md`、`04-渲染资源模型.md`、`05-合批与RenderObject提交.md`。
> 关联实现：`SlangAllInOne/unity/package/com.slang.unity/Editor/SlangSceneExporter.cs`（导出器）、`SlangAllInOne/SLangCore/test/Other/SimSceneTest/`（引擎侧消费工程）、`SlangAllInOne/unity/README.md`、`SlangAllInOne/md/unity3d/`、`../Render/doc/03-Module-Design.md` §4.4（Hlsl 层）、`../Render/doc/08-RHI-Backends.md`（四后端着色语言）。

---

## 1. 资源来源总览：三条路径汇入同一格式

```
路径 A：Unity Editor 导出器（本章 §3）          ┐
路径 B：FBX 转换器（本章 §2，FBX SDK 引入）      ├─→ 统一 JSON schema（§4）─→ 引擎 SceneImporter（§5）
路径 C：贴图 PNG/JPG 源文件直用（SLangImage）   ┘
```

设计原则：**引擎只认一套自建 schema**。无论资源来自 Unity、Blender 还是纯 FBX 文件，导入器不需要知道出处；以后换 DCC 工具不用改引擎。

## 2. Unity 原生格式能否直接解析？（判定）

| Unity 数据 | 原生形态 | 直接解析可行性 | 原因 |
|---|---|---|---|
| Scene（`.unity`） | YAML 文本 | ⚠ 理论可读，不建议 | 引用靠 GUID + fileID，跨文件追引用极易断；版本升级格式漂移 |
| Prefab（`.prefab`） | YAML 文本 | ⚠ 同上 | 嵌套 prefab、override 修改链，语义还原成本高 |
| Material（`.mat`） | YAML 文本 | ⚠ 同上 | 属性表依赖具体 shader 实现 |
| Mesh | 在 FBX / 模型资产内，**二进制** | ❌ 原生不可行 → ✅ **经 FBX SDK 转换可行**（§3） | 需 FBX 解析库 |
| Shader | ShaderLab / 编译产物 | ❌ 不可行 | 资产 shader 统一改用 **HLSL 源文件**（§4.2），Unity 只导「shader 引用名」 |
| Texture | 源文件 PNG/JPG + `.meta` | ✅ 可直接用 | 引擎经 `SLangImage` 加载（第 04 章） |
| Animation Clip | YAML | ⚠ 可读但坑多 | 曲线压缩 / humanoid 重定向 / easing 语义复杂 |

## 3. FBX SDK 引入：模型转换工具【设计稿】

### 3.1 形态与落点

FBX 解析做成**离线转换器 CLI**（不进运行时、不进游戏包）：

```
SimGameEngine/tools/AssetConverter/        # C/C++ 工程（vcxproj + CMake 双登记，R6）
   输入：xxx.fbx / obj / gltf
   输出：mesh_<id>.json + mesh_<id>.bin + material_<id>.json 草稿 + manifest 片段
```

- 运行时引擎不背 FBX 依赖，出问题不影响游戏包；
- 转换产物与 Unity 导出器产物**同一 schema**（§4），引擎无差别消费；
- 产物只写 `out/`（R9），再由业务侧拷入导出目录。

### 3.2 SDK 选型（建议，未实施）

| 选项 | 形态 | 许可 | 优点 | 顾虑 |
|---|---|---|---|---|
| **ufbx（推荐起步）** | 单头文件 C11 | MIT | 零依赖、贴合项目 C 工具链、直接出顶点缓冲、支持二进制/ASCII FBX | 骨骼蒙皮 / BlendShape 支持有限 |
| Autodesk FBX SDK 2020.x | C++ 静态/动态库 | 免费闭源 | 全功能（骨骼 / 动画 / 混合形状 / 相机） | 需分发运行库、体积大、编译配置重 |
| Assimp | C++ 多格式库 | BSD | FBX/OBJ/glTF 一把梭 | 体积与依赖最重，FBX 支持非官方实现 |

建议路线：v1 用 **ufbx** 覆盖静态网格（顶点 / 法线 / UV / 颜色 / 子网格），骨骼动画需求出现后再评估官方 SDK（做成可替换的后端，转换器内部隔离）。

### 3.3 转换规则

- **单位与轴向**：FBX 常见 cm 与 Z-up（Maya 系）或 Y-up（Max 系）；转换器读 `UnitScaleFactor` / `UpAxis` 后统一烘焙成引擎约定（米、Y-up、左手 +Z 前方，§6），顶点与包围盒同步换算；
- **三角化**：FBX 多边形统一三角化后写索引；
- **子网格**：按材质分组写 `submeshes`，与 `material_<id>.json` 一一对应；
- **烘焙节点变换**：模型层级展平，`scaleFactor` / 旋转修正烘焙进顶点（与 Unity 导出器同一原则）；
- **不做**：骨骼蒙皮、BlendShape、UV2+、嵌套相机灯光（引擎需要的 Camera/Light 由场景文件给，不由模型文件给）。

## 4. Unity 导出器与导出格式

### 4.1 导出器落点【已确认可挂载】

UPM 包 `com.slang.unity` 已具备所需基础设施（源码核实）：

| 已有 | 位置 | 导出器如何复用 |
|---|---|---|
| Editor asmdef | `Editor/SlangUnity.Editor.asmdef` | 新导出器 `.cs` 放进 `Editor/` 即自动编译 |
| 菜单入口先例 | `SlangUnityEditor.cs` 的 `[MenuItem("Tools/SlangUnity/...")]` | 增加「Export Scene」菜单 |
| 命令行驱动先例 | `Logs/slang-unity-cmd.flag` 标记文件轮询 | 增加 `export-scene` / `export-all` 命令 |
| 报告落盘先例 | `WriteReport()` 写 `Logs/*.txt`（UTF-8 无 BOM） | 导出结果写 `Logs/slang-export-report.txt` |
| StreamingAssets 约定 | `Assets/StreamingAssets/Slang/` | 产物放 `Assets/StreamingAssets/SlangExport/<场景名>/` |

约定：仅 Editor 域执行（不进 Runtime asmdef）；输出全 UTF-8（R16）；幂等覆盖并重写 manifest；二进制小端、4 字节对齐、带 magic（`SLMESH`）+ 版本号。

### 4.2 目录与文件

```
Assets/StreamingAssets/SlangExport/<SceneName>/
├─ manifest.json                 # 版本、清单、md5、导出时间、来源（unity/fbx）
├─ scene.json                    # 节点树 + 组件描述
├─ shadermap.json                # Unity shader → 引擎效果/HLSL 映射表
├─ mesh_<id>.json / mesh_<id>.bin
├─ material_<id>.json            # shader 引用（固化名或 HLSL 文件）+ 参数 + 贴图
├─ texture_<id>.json
├─ textures/<id>.png
├─ shaders/<name>.hlsl           # ★ 通用 HLSL 着色器源（§4.4）
├─ shaders/shadercache.json      # 编译缓存索引（§4.5）
├─ anim_<id>.json
└─ prefab_<id>.json              # 预制体实例参数（可选）
```

### 4.3 scene.json（节点树）

```json
{
  "version": 1,
  "scene": "SampleScene",
  "nodes": [
    {
      "id": 1, "parent": 0, "name": "Player",
      "tag": "Player", "layer": 3, "active": true,
      "transform": {
        "localPosition": [0, 0, 0],
        "localRotation": [0, 0, 0, 1],
        "localScale":    [1, 1, 1]
      },
      "components": [
        { "type": "MeshFilter", "mesh": "mesh_1001" },
        { "type": "MeshRenderer", "material": "mat_2001", "castShadow": true, "renderQueue": 2000 },
        { "type": "Rigidbody", "mass": 1.0, "useGravity": true },
        { "type": "BoxCollider", "center": [0,0,0], "size": [1,1,1], "isTrigger": false }
      ]
    }
  ]
}
```

- `id` / `parent` 用稳定 id（路径 + 名字哈希，不用 GUID）；`parent = 0` 表示根；
- 组件 `type` 与本引擎第 02/11/12/15 章组件名一一对应；Unity 未识别组件记入 manifest `skipped`；
- `Camera` / `Light` 导出参数（类型 / 强度 / 颜色 / 正交尺寸），映射为第 06 章组件。

### 4.4 通用 HLSL：材质的 shader 表达

目标：材质不再只能用固化 5 效果，**资产可携带 HLSL 源文件**，任意 DCC 出的材质经映射都能用（「通用」）。

`material_<id>.json` 的 shader 字段扩展为三态：

```json
{ "id": "mat_2001", "name": "M_Player",
  "shader": "Standard",
  "mapped": "phong",                       // 三态之一
  "hlsl": null,                            // 或 "shaders/player.hlsl"
  "props": { "_Color": [0.8, 0.2, 0.2, 1] },
  "textures": { "_MainTex": "tex_3001" } }
```

| `mapped` 取值 | 含义 | 引擎行为 |
|---|---|---|
| `lambert / phong / blinn-phong / normalmap / toon / unlit` | Render 固化效果（已落盘，`Render/doc/09` §5） | 直接用固化槽，零编译成本 |
| `hlsl` + `hlsl` 字段非空 | 资产自定义 HLSL | 走 §4.5 编译链 |
| 映射失败 | 降级 | `unlit` 兜底 + manifest 计 `degraded`（与第 14 章「静默忽略并统计」同原则） |

**HLSL 源文件约定**（与 Render 的 HLSL 规范对齐）：

- 入口：`VSMain` / `PSMain`；语义用 `SV_POSITION` / `SV_Target0`；
- **源文件内禁止 `#include`**——Render 编码规范明确 DXC 会报错，模块拼接由工厂/导入器完成（`Render/doc/05` 规范 #20、`03` §4.4 的已知 bug `#include Common` 就是前车之鉴）；
- cbuffer 布局对齐 `Render/doc/03` 附录 B（float4 成员 16B 对齐、附加光数组定长 8）；
- 材质参数经 ConstantBuffer 下发（Render D2：矩阵等复杂参数不进命令流）。

### 4.5 HLSL 编译链与跨后端现状（如实边界）

Render 四后端的着色语言现状（`Render/doc/08` §表）：

| 后端 | 着色语言现状 | 资产 HLSL 支持度 |
|---|---|---|
| `d3d11` | 运行时 HLSL | ✅ 首选路径：DXC 编译 FXC 语义一致 |
| `vk` | SPIR-V 固化（构建期） | ⚠ 规划中：HLSL 经 DXC 转 SPIR-V（`Render/doc/04` §393 行） |
| `gl` / `gles` | 运行时 GLSL（内建源各自翻译） | ❌ 外部 HLSL→GLSL 跨编译未落地 |

因此 v1 策略：**HLSL 资产先在 d3d11 后端生效；gl/gles/vk 后端对未编译成功的 HLSL 材质自动降级固化效果**。编译产物缓存（`shadercache.json`：源 md5 → 编译字节码 + 参数反射表），避免每次启动重编。这条链路依赖 Render 侧完成 `HlslLibrary` 的 include bug 修复与 `Shader.sl`/`Hlsl.sl` 双轨统一（`Render/doc/03` §4.4、`05` §2.1-#10），在其落地前 HLSL 字段只存不用。

### 4.6 mesh / animation / texture

- `mesh_<id>.json`：`layout`（`position:float3 / normal:float3 / uv:float2 / color:ubyte4`）、`vertexStride`、`submeshes`、`bounds`；`.bin` 按 layout 紧排顶点 + u32 索引；
- `anim_<id>.json`：轨道 keyframe，easing 导出侧线性化采样；
- 贴图导 PNG 原文件 + 元数据；Unity 内 DXT/ASTC 压缩不影响导出。

## 5. 引擎侧导入器【已落盘 v1（2026-11-17），`SceneImporter.sl` + `ImportReport.sl`】

```sl
SceneImporter imp = SceneImporter()
ImportReport rep = imp.loadDir( exportDir )          # manifest + scene.json → 建树
ImportReport rep2 = imp.parseCore( 1, sceneText )    # 核心：文本直解析（可脱离文件测试）
```

v1 落盘形态：

| 项 | 说明 |
|---|---|
| 建树 | 两遍法：Pass A 全量 `scene.createObject`（顺序无关），Pass B `setParent` 修正层级（parent=0 根；父 id miss → skipped 计数） |
| Transform | `localPosition/localScale` + `localRotation` 四元数经统一版 `setPositionAndRotation` 直传（Merge 版支持非纯 Z 旋转）；缺省 [0,0,0,1]/[1,1,1] |
| 组件映射 | MeshFilter→MeshRef(MESH_CUSTOM，slot 4..7 轮转 + meshIds 登记)；MeshRenderer→MaterialData(name=mat id)+MaterialRef(renderQueue/castShadow)；Rigidbody(mass/useGravity)；BoxCollider(center/size/isTrigger)；SphereCollider(center/radius/isTrigger)；SpriteRenderer；Camera/Light 引擎无对应组件 → 计数登记；未识别 type → skippedCount |
| version 守卫 | manifest 与 scene 双重校验，非 1 明确报错不猜（§5 原则） |
| 计数统计 | ImportReport：node/root/mesh/material/collider/rigidbody/camera/light/sprite/skipped + meshIdAt(i) |

- JSON 解析用标准库 Json（`JsonValue.parse/select/children/asXxx(默认值)`，用例 `SLangCore/test/Other/JsonTest`）；
- 导入器不依赖 Unity 与 FBX——转换与导出都发生在资产侧；
- mesh `<id>.bin` 顶点深解析仍走 SimSceneTest 最小消费路径（uploadMesh 通道），导入器只登记 meshIds（资源管线 v2 接管）。

## 6. 坐标系与单位约定

**引擎世界约定与 Unity 同构**：左手系、Y 向上、+Z 前方、米为单位。FBX 转换器与 Unity 导出器都把各自源格式**烘焙到这套约定**：

| 数据 | 换算 |
|---|---|
| Position / Rotation / Scale | Unity 直传；FBX 经 UnitScaleFactor / UpAxis 烘焙 |
| 顶点 | 双路径都烘焙缩放与轴向修正 |
| 相机 | 正交边界由 orthographic size 推导（第 15 章 `setCamera`） |

若 Render 管线未来出现右手系需求，在**导入器统一转换**，schema 不变。

## 7. 验证与自动化

### 7.1 已落盘命令（flag 通道）

| flag 值 | 行为 | 输出 |
|---|---|---|
| `export-scene` | 导出当前活动场景 | `Assets/StreamingAssets/SlangExport/<场景名>/` |
| `export-cube` | 临时 Additive 场景建 Cube + 方向光后导出（不碰已打开场景） | `Assets/StreamingAssets/SlangExport/CubeDemo/` |
| `-slangExportOut <dir>`（batchmode） | `ExportSceneFromCommandLine` 指定输出目录 | 同上 |

两侧报告：Unity 侧 `Logs/slang-export-report.txt`；编辑器菜单 `Tools/SlangUnity/Export Scene (Slang JSON)` / `Export Cube Demo`。
注意：编辑器失焦时脚本不会重编译——改完导出器代码先激活一次 Unity 窗口再发 flag。

### 7.2 首次端到端实测（2026-11-16，PASS）

```
Unity 2023.2.20f1（HDRP 工程）export-cube →
  CubeDemo：nodes=2 (Cube+Sun) / mesh=1 / verts=24 / indices=36 / RESULT=PASS
引擎侧 SimSceneTest（slang compile EXIT=0 → slang run）：
  [data] node mesh=mesh_1 pos=0,0,0 queue=2225     ← scene.json 解析
  [data] OK: verts=24 tris=12                      ← mesh_1.bin 完整解析
  [done] okFrames=937 (expect ~900 @15s)           ← 15s 每帧渲染上屏成功
```

即：**Unity 导出的 Cube 顶点 / UV / 索引 / Transform，已在 SLangRender 13 阶段管线里渲染成旋转 Cube**（QT 窗口 ~60fps）。当前消费方式是「最小消费」（直接喂 MESH_CUSTOM + uploadMesh），完整 SceneImporter 等 P0-P2 的 GameObject/Scene 落地后接入。

## 8. 已知坑与注意

1. **GUID 不稳定**：资源 id 用「路径 + 名字」稳定哈希，不用 `.meta` guid。
2. **嵌套 Prefab 展开**：实例展平进节点树，记录 `prefabSource` 追溯；不导出「引用 + override」结构。
3. **动画曲线压缩**：Unity Keyframe Reduction 会丢精度；需精确轨迹时关压缩再导。
4. **FBX 单位 / 轴向不统一**：cm、Z-up、负缩放都常见；转换器必须读并烘焙 `UnitScaleFactor` / `UpAxis`，否则模型忽大忽小或镜像。
5. **FBX SDK 依赖**：ufbx 单头零依赖；若换 Autodesk 官方 SDK，运行库分发与编译配置是额外工程项（R6 两活跃链登记）。
6. **多材质子网格**：submesh 表保留，引擎按材质拆 Renderer / 批次（第 05 章合批键天然处理）。
7. **HLSL 源内禁止 `#include`**：DXC 直接报错；拼接由导入器 / 工厂完成，源文件保持扁平。
8. **HLSL 跨后端不对称**：d3d11 先行，gl/gles/vk 未编译成功的材质降级固化效果；不要假设一份 HLSL 四后端通吃（§4.5）。
9. **明确不导出**：光照贴图、Probe 烘焙、ShaderGraph、VFX、Terrain、NavMesh；manifest `skipped` 记录并继续。
10. **导出器仅 Editor 域**；`SlangUnity.Editor.asmdef` 只包 Editor 目录，勿引 Runtime。
11. **本章 schema / 转换器 / 完整导入器仍在演进**；`Renderer.render()` 不可用等既有约束（第 04 章）对导入节点同样生效。
12. **SL 侧：不要显式 `import Core;`**——Core 类型（JsonValue 等）随引用自动可见，显式导入会触发 MetaCore 解析链异常（节点 not found / 表达式 604 连锁）。
13. **SL 侧：跨模块对象方法不要链式调用**（`a.b().c()` 会炸 MetaCore），一律拆单步局部变量；`ret` 不要直接携带跨模块方法调用。
14. **SL 侧：`UInt8Array.length` 返回容量语义**（实测 512，文件实际 934B）——二进制长度以 json 声明推导，不要信 `.length`；`File.readAllBytes` 是 throws 方法必须 try/catch。
15. **`tr` 是 Transience 保留字且引发元崩溃**（2026-11-17 SceneImporter 实证，第 5 次踩）：变量名 `tr` → Transience 语句 → `MetaTRStatements` ctor null 引用（`root is Null` + ParseStatements 失败，无文件行号指向，极难定位）——命名避让 `tr`（keywords.md 总表）。
16. **`error`/`errmsg` 是 Result 保留成员名**（`error` 字段编译报 MetaCoreMemberNameReserved）——改名 `lastError`（RenderSystem 先例）；`def` 也是不支持关键字（Python 词，lexer 报 TokenLexerUnsupportedKeyword）。
17. **`ret` 不携带内联构造表达式 / 跨模块调用；方法调用表达式不作实参；跨模块链拆单步**（§8.13 家族在导入器全量复现：`node.select("x").asString()` 链、`jsonVec3(node.select(...))` 嵌套实参、`ret Float32_3(...)` 构造——一律先落局部变量）；文件存在性用 `File.exists` 预检 + 直读（try/catch 形态见 §8.14 / SimSceneTest）。

## 9. 变更记录

| 日期 | 版本 | 变更 |
|---|---|---|
| 2026-11-16 | v0.1 | 初版：Unity 原生格式解析判定、Editor 导出器落点、JSON schema、引擎导入器 |
| 2026-11-16 | v0.2 | 引入 FBX SDK 转换器路径（ufbx 起步，官方 SDK 备选，统一 schema）；shader 升级为通用 HLSL 源文件（三态映射 + DXC 编译链 + 跨后端如实边界 + 编译缓存） |
| 2026-11-16 | v0.3 | 导出器落地（`SlangSceneExporter.cs` + flag `export-scene`/`export-cube`），SimSceneTest 端到端验证 PASS（Unity Cube → SLangRender 渲染 937 帧）；记录 SL 侧解析链实证坑（§8.12-8.14） |
| 2026-11-17 | v0.4 | **引擎侧完整 SceneImporter v1 落盘**（§5）：`SceneImporter`（loadDir/parseCore 两入口，两遍建树 + 组件映射 + version 双守卫）+ `ImportReport`（统计 + meshIds 登记）；`SimImportTest` 34 项（第 11 套），十一套 **407 项全绿**；实证坑落 §8.15-8.17（`tr` Transience 元崩溃 / `error`/`def` 保留名 / 链式与嵌套实参全量规避形态） |
