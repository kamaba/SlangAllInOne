# 19 · 场景导出与 SceneManager（v2.12，2026-11-18）

> 定位：给「场景数据化」补上闭环——运行时 Scene → JSON 落盘（SceneExporter），
> JSON 按路径 → Scene + 脚本挂载 + 帧循环（SceneManager）。与第 16 章的资源导入
> （Unity Editor 导出器 → SceneImporter）共用同一份 scene.json schema。
> 状态：`SceneExporter` / `SceneManager` / `ScriptResult` / `SceneImporter` 脚本扩展
> 均【已落盘】，示例见 `gameExample/Test/`。

---

## 1. 能做什么

| 能力 | 入口 | 说明 |
|---|---|---|
| 导出场景 | `SceneExporter.toJson(scene)` / `SceneExporter.save(scene, path)` | 把节点树、层级、变换、组件、脚本写成 scene.json 文本/文件 |
| 按路径加载 | `SceneManager.load(path)` | 读 scene.json → 建树 → 挂组件/脚本 → 设为激活场景 |
| 内存加载 | `SceneManager.loadText(text)` | 网络下发 / 单测对照，不落盘 |
| 脚本挂载 | `SceneManager.registerScript(name, factory)` | scene.json 的 `Script` 组件按短名找到工厂，创建 Behaviour 挂到节点 |
| 运行场景逻辑 | `SceneManager.tick(rawDt)` | 转发 `Application.tick`，脚本 awake/start/update/lateUpdate/fixedUpdate 自动驱动 |
| 导出回读 | `SceneManager.save(path, scene)` / `toJson(scene)` | 导出后可再次 `load`/`loadText`，形成 round-trip |

与 `Application` 的关系：每个 `SceneManager` 自带一个 `Application`（`sm.app`），
`load` 成功后自动 `app.loadScene`。不绑定窗口与渲染后端——画面仍由消费方用
`RenderSystem.sync + frame` 驱动（与 Application「引擎不绑定窗口系统」一致）。

---

## 2. scene.json 格式

沿用第 16 章 schema，并补一个 `Script` 组件类型：

```json
{
  "version": 1,
  "scene": "MaterialBall",
  "nodes": [
    {
      "id": 1, "parent": 0, "name": "Ball_Red", "tag": "Ball", "layer": 0, "active": true,
      "transform": {
        "localPosition": [-6, 0, 0],
        "localRotation": [0, 0, 0, 1],
        "localScale": [1, 1, 1]
      },
      "components": [
        { "type": "MeshFilter", "mesh": "mesh_sphere", "meshKind": 4, "meshSlot": 0 },
        { "type": "MeshRenderer", "material": "mat_red", "color": [0.92, 0.2, 0.18],
          "renderQueue": 2000, "castShadow": false },
        { "type": "Script", "script": "SphereMeshScript", "radius": 2.0, "segU": 12, "segV": 8 },
        { "type": "Script", "script": "SpinScript", "speed": 0.7, "bob": 0.5 }
      ]
    }
  ]
}
```

字段约定：

- `id` 稳定正整数，`parent=0` 表示根节点；导入器两遍建树（先全建节点再修正层级）。
- `Transform` 是节点自带组件，不写进 `components`。
- 组件 `type` 取值：`MeshFilter` / `MeshRenderer` / `Rigidbody` / `BoxCollider` /
  `SphereCollider` / `CapsuleCollider` / `SpriteRenderer` / `Script`；
  另有 `Camera` / `Light` 只计数登记（引擎无对应组件）。
- `MeshFilter.vertices` 可选：数组形式为 `[[x,y,z], ...]`，存在时走烘焙网格路径；
  缺省则走内置网格直通。导出器会把构建好的顶点一并写回。
- `Script.script` = 脚本类短名；其余键是自定义参数，工厂从 `cfg` 里读取。
- 未注册的脚本名与未识别组件类型计入 `ImportReport.skippedCount`，不中止加载。

---

## 3. API 速查

### SceneManager

```
SceneManager()                                   // 自带 Application（已 init）
void registerScript(string name, Function factory)
Int32 scriptTypeCount()
Scene load(string path)                          // 失败返回 null，原因在 lastError
Scene loadText(string text)
bool  save(string path, Scene scene)             // scene=null 表示 activeScene
string toJson(Scene scene)
void  tick(Float32 rawDt)                        // -1 = 引擎单调钟实测帧间隔
void  unload()
```

字段：`app`、`activeScene`、`lastError`、`ok`、`nodeCount`、`scriptCount`。

### SceneExporter

```
static string toJson(Scene scene)
static bool   save(Scene scene, string path)
```

### 脚本工厂（固定形态）

工厂签名必须是 `void(JsonValue cfg, ScriptResult sink)`：从 `cfg` 读参数，
把创建好的 Behaviour 写入 `sink.value`。`Function` 是可以放进 `List` 的委托形态，
`Func<>` 字段/泛型实参在本编译链不可用。

```
public static void makeSpin( JsonValue cfg, ScriptResult sink )
{
    SpinScript s = SpinScript()
    JsonValue n = cfg.select("speed")
    s.speed = n.asFloat32( 0.5f )
    sink.value = s
}
```

注册（传类名限定的静态方法，不要只传裸方法名）：

```
SceneManager sm = SceneManager()
sm.registerScript( "SpinScript", SceneScriptFactories.makeSpin )
Scene s = sm.load( "assets/scenes/MaterialBall.scene.json" )
sm.tick( -1.0f )
```

---

## 4. 使用技巧与已知坑

1. **先注册再加载**：脚本工厂必须在 `load` 之前注册；晚注册的脚本在已加载场景里
   不会出现（重新 `load` 才会挂载）。
2. **短名一致**：`Script.script` 必须与 `registerScript` 的名字逐字一致（大小写敏感）。
   导出器写的是类的短名（不含模块前缀）。
3. **脚本实例是新建的**：每个 `Script` 组件都调用一次工厂，实例独立，不共享。
4. **参数先落局部变量**：`cfg.select(...)` 的返回值先存 `JsonValue` 再 `asXxx()`；
   方法调用表达式直接作实参在本编译链不稳定。
5. **`label` 是保留字**：脚本字段名不要用 `label`（词法器关键字），改名如 `probeName`。
   同类保留字还有 `local`/`next`/`half`/`as`/`tr`/`dynamic`/`base`/`out`/`global`/
   `def`/`params`/`result`。
6. **导出顶点会变大**：`toJson` 会把已构建的网格顶点写进 `vertices`，场景越复杂文本
   越大；只想要轻量配置时可在导出前清空脚本生成的顶点。
7. **rawDt 正数兼容**：`tick(0.016f)` 走固定 dt 形态；宿主推荐 `tick(-1.0f)`（C 单调钟
   实测帧间隔，贯穿逻辑/物理/渲染）。
8. **脚本钩子按名派发**：Behaviour 的 `override` 生命周期方法经引擎按名调用；
   跨模块 slb 基类虚表不派发消费方 override 的问题已被该机制绕开。
9. **数值写法别改成标量 `toString()`**：导出器内部用 `String.toFormat` 输出
   数字。Release JIT 下高频调用的标量 `toString()` 会返回 null（现象：连续导出
   多个场景后，后几个场景的 `localPosition`/`color`/`vertices` 只剩 `]`，
   回读报 `scene.json parse failed`；`SL_JIT=0` 即消失）。自定义序列化器请沿用
   `toFormat` 通道。

---

## 4.1 光源组件与材质扩展（v2.13）

**Light 组件**（引擎新增 `LightData extends Behaviour`，jsonc 需登记）：

```json
{ "type": "Light", "lightType": 0, "color": [1, 0.96, 0.88], "intensity": 1.0,
  "dirX": 0.55, "dirY": 0.8,
  "shadowQuality": 1, "shadowBias": 0.002, "shadowStrength": 0.45 }
```

- `lightType`：0 = 平行光 / 1 = 点光（预留，着色器未消费）/ 2 = 聚光。
- `dirX/dirY`：2D 光照方向（平行光 = 表面 → 光源方向；聚光 = 光轴方向）；
  聚光另用 `posX/posY`（世界位置）、`spotAngle`（半角度数）、`range`。
- `shadowQuality: 1` 启用 shadow map（512 深度图 + PCF，仅平行光、仅 GL/GLES；
  D3D11/VK 回退黑斑路径）。
- `RenderSystem.sync` 每帧先收集场景 LightData，按发现序写管线槽 0..7
  （固化着色器消费首个平行光 + 首个聚光；超出 8 盏计 `lightOverflow` 不提交）。

**MeshRenderer 组件新键**：

- `materialModel`：0 = Lambert / 1 = Phong / 2 = BlinnPhong / 3 = BlinnPhongNormalMap /
  4 = Toon（固化 HLSL 程序槽路由，越界 C 侧夹取 [0,4]）。
- `shininess`：高光锐度 1..256（配合 `specular` 高光强度 0..8）。
- `texture`：贴图文件路径（PNG/JPEG/BMP，WIC 解码；建议绝对路径）。装载失败
  保持纯色不中止导入，计数进 `ImportReport.textureCount`。

**MeshFilter `meshKind: 4`（自定义槽 0）**：`RenderSystem.uploadMeshXyz(slot, verts)`
上传 3D 顶点（xy 参与 + 平面 uv），27 材质球共用一个单位圆网格，各自经
节点变换/颜色独立显示。

**脚本动效（示例自带脚本，`gameExample/Test/SceneScripts.sl`）**：

- `SpinScript {speed, bob}`：绕 Z 自转 + 上下浮动（浮动按累计相位正弦）。
- `LightSwingScript {swing, speed}`：挂在 Light 节点上，按 `EngineTime.elapsedTime`
  正弦摆动聚光位置与强度；写回走 `LightData.setSwing(x, intensity)` 方法
  （跨模块字段直写不可靠，统一方法入口）。

**已知边界**：正交相机下光照 n·l 按对象常量（固化着色器 vWorld/vNrm 为 2D），
聚光锥与阴影为逐像素；从网上取新的 HLSL 需固化编译链（glslang → SPIR-V →
GLSL/DXBC，`sl_rhi_shaders_gen.h`）重生成——本仓库 `assets/shaders/` 存有
BasicHLSL11（MIT）供对照，运行时材质模型仍走已固化槽位。

---

## 5. 可运行示例

`gameExample/Test/` 提供三份场景与两个工程：

| 场景文件 | 内容 |
|---|---|
| `assets/scenes/MaterialBall.scene.json` | 4 个材质球，SphereMesh 脚本生成球网格 + SpinScript 自转/浮动 |
| `assets/scenes/ShapeGallery.scene.json` | 立方体/球/圆柱/圆环，ShapeMesh 脚本按 `shape` 号构建 |
| `assets/scenes/PureTest.scene.json` | 纯逻辑测试：父子两节点各挂 ProbeScript，验证生命周期被驱动 |
| `assets/scenes/MaterialGallery.scene.json` | 27 材质球展厅（v2.13）：9 列 × 3 行单位球（共用自定义槽 0 网格）+ 地面 quad + 双灯（平行光带 shadow map 阴影 + 聚光），材质覆盖 Lambert/Phong/BlinnPhong/Toon 四种固化 HLSL 模型 × 色相环 × 高光梯度，3 球挂贴图（three.js MIT 示例贴图，`assets/textures/`）；**脚本动效**：每球挂 `SpinScript`（浮动相位差），聚光灯挂 `LightSwingScript`（位置/强度正弦摆动） |

| 运行模式 | 用途 |
|---|---|
| `slang run SceneDemo.module.slb`（无参数） | QT 窗口展示；1/2/3/4 切场景（4 = 材质展厅），S 导出 JSON，Esc 退出；信息条显示 nodes/scripts/lights/objs |
| `slang run SceneDemo.module.slb -- smoke` | 无窗口冒烟：四场景加载 / 脚本挂载 / 跑帧 / 导出落盘回读，32 项全绿 |

模式分流在 `SceneDemo.sp` 的 `_main_()` 里读系统注入的 `global._inputArgs` 完成
（首个参数为 `smoke` 走冒烟，否则走窗口）。

构建与运行命令见 `gameExample/Test/README.md`。
