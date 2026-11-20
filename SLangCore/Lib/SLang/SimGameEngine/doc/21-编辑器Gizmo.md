# 21 · 编辑器 Gizmo（Editor Gizmos / Handles）

> 【已落盘】v2.18。三件套 `GizmoTypes` / `GizmoGeometry` / `GizmoSystem`（均位于引擎模块根级，可直接引用）。
> 零原生库改动：几何由纯 SL 生成，走引擎既有的 `MeshRef` 顶点烘焙渲染路径，与场景物体同一套管线。

---

## 1. 它解决什么

仿 Unity 编辑器的「编辑态渲染」：在场景里叠加一组不参与游戏逻辑的可视化辅助图形——

- **三轴方向箭头**：红 = X、绿 = Y、蓝 = Z（move 模式）；
- **旋转圆环**：绕 X / Y / Z 三轴的彩色圆环（rotate 模式）；
- **缩放手柄**：轴末端带方形手柄（scale 模式）；
- **相机图标**：2D / 3D 两种编辑器形象（青色）；
- **光照图标**：平行光（太阳放射）/ 点光（多放射）/ 聚光（带光锥），2D / 3D 两形（黄色）。

它是纯「显示层」能力：不提供拾取与拖拽交互，只负责按给定位置与状态把图形画出来；交互（选中谁、键位、拖拽）由宿主/游戏逻辑决定。

---

## 2. 模式常量

`GizmoTypes` 提供全部常量与调色板：

| 常量 | 值 | 含义 |
|---|---|---|
| `MODE_NONE` / `MODE_MOVE` / `MODE_ROTATE` / `MODE_SCALE` | 0 / 1 / 2 / 3 | 变换 gizmo 的四种模式 |
| `AXIS_X` / `AXIS_Y` / `AXIS_Z` | 0 / 1 / 2 | 轴枚举 |
| `ICON_CAMERA_2D` / `ICON_CAMERA_3D` | 10 / 11 | 相机图标类型 |
| `ICON_LIGHT_DIR` / `ICON_LIGHT_POINT` / `ICON_LIGHT_SPOT` | 12 / 13 / 14 | 光照图标类型 |
| `LIGHT_DIRECTIONAL` / `LIGHT_POINT` / `LIGHT_SPOT` | 0 / 1 / 2 | 光源子类型（与 `Light` 的一致） |

调色板为方法：`colorX()` / `colorY()` / `colorZ()` / `colorNeutral()` / `colorHighlight()` / `colorCamera()` / `colorLight()`，均返回 `Float32_3`。

---

## 3. 核心 API（`GizmoSystem`）

### 配置字段

| 字段 | 类型 | 默认 | 说明 |
|---|---|---|---|
| `mode` | Int32 | `MODE_MOVE` | 当前变换模式（用 `setMode` 改） |
| `enabled` | bool | `true` | 关掉后所有绘制方法不再产生几何 |
| `size` | Float32 | `1.2` | gizmo 尺寸（世界单位），箭头长度 / 圆环半径 / 图标大小 |

### 生命周期方法

| 方法 | 说明 |
|---|---|
| `attach(Scene scene)` | 把六色 gizmo 节点挂到目标场景。切场景后需重新调用；同一场景重复调用无副作用 |
| `beginFrame()` | 帧首清空六色顶点缓冲 |
| `endFrame()` | 帧尾把缓冲写回网格，供本帧渲染提交 |

### 绘制方法（在 `beginFrame()` 与 `endFrame()` 之间调用）

| 方法 | 说明 |
|---|---|
| `drawTransform(Float32_3 center)` | 按 `mode` 在 `center` 处画变换 gizmo；`MODE_NONE` 不产几何。可多次调用，几何累加（适合多对象逐点绘制） |
| `drawCamera(Float32_3 center, bool is2D)` | 在 `center` 处画相机图标（`true`=2D，`false`=3D） |
| `drawLight(Float32_3 center, Int32 lightType, bool is2D)` | 在 `center` 处画光照图标，`lightType` 取 `LIGHT_*` |

### 状态与诊断

| 方法 | 说明 |
|---|---|
| `setMode(Int32 m)` | 设置模式，非法值忽略 |
| `currentMode()` / `isEnabled()` | 读回状态 |
| `vertexCountAt(Int32 slot)` | 某色缓冲顶点数（槽 0=X/1=Y/2=Z/3=中性/4=相机/5=光） |
| `totalVertexCount()` / `allFinite()` | 总顶点数 / 数值健康检查（诊断与测试用） |
| `appendTo(Int32 slot, Float32_3 v)` | 手动往某色缓冲追加一个顶点（扩展用） |

---

## 4. 接入用例

### 4.1 多对象逐点绘制（每帧）

```
GizmoSystem gs = GizmoSystem()
gs.mode = GizmoTypes.MODE_MOVE
gs.attach( scene )

# 每帧：
gs.beginFrame()
for each selectedOrAnchorPosition p:
    gs.drawTransform( p )          # 在 p 处画箭头/圆环/手柄
gs.drawCamera( camPos, false )     # 相机 3D 图标
gs.drawLight( lightPos, GizmoTypes.LIGHT_SPOT, false )
gs.endFrame()
renderSystem.sync( scene )         # 随后正常渲染场景
```

`drawTransform` 可逐节点累积：脚本在各自 `update()` 里调一次即可汇总全部节点的 gizmo（SceneDemo 的坐标轴脚本就是这个形态）。

### 4.2 模式切换（宿主键位）

```
# G 键按下时循环：none → move → rotate → scale → none
Int32 m = gs.currentMode()
if m == GizmoTypes.MODE_NONE:      m = GizmoTypes.MODE_MOVE
elif m == GizmoTypes.MODE_MOVE:    m = GizmoTypes.MODE_ROTATE
elif m == GizmoTypes.MODE_ROTATE:  m = GizmoTypes.MODE_SCALE
else:                              m = GizmoTypes.MODE_NONE
gs.setMode( m )
```

SceneDemo 已接入这套演示：G 键循环模式，顶部信息条显示 `gizmo=move/rotate/scale/none`；相机/光图标在每个有网格节点的场景锚点旁演示。

### 4.3 Ctrl+Home 菜单栏开关（SceneDemo）

SceneDemo 的 QT 宿主支持 `Ctrl+Home` 弹出顶部菜单栏（QMenuBar 作窗口子控件，非 QMainWindow 的 setMenuBar），首个菜单「辅助 Gizmo」下有 action「显示辅助 Gizmo」：

- `Ctrl+Home`（Home 按下沿 + Ctrl 处于按下）→ 显示/隐藏菜单栏；
- 点「显示辅助 Gizmo」→ 切换 `showAxes`，即全局显示/隐藏所有 Gizmo（含三轴箭头/圆环/手柄/相机·光图标）；
- 菜单栏默认隐藏；关掉 Gizmo 后按 G 键切模式会自动重新打开（G 键优先）。

接入形态（宿主侧）：`QTHost.startHost(frameHandler, toggleGizmoHandler)` 第二参是无参 void trampoline，菜单 action 经 `SIG_TRIGGERED` 连到它；`QTHost.toggleMenuBar()` 由场景逻辑在 Ctrl+Home 边沿调用。

---

## 5. 注意事项与已知边界

- **绘制时机固定**：`beginFrame → 若干 draw* → endFrame` 必须包在渲染 `sync` 之前；`endFrame` 之前缓冲只是内存数据，不会显示。
- **切场景要重新 `attach`**：gizmo 节点随场景走，换场景后不重新绑定则画不到新场景。
- **`enabled=false` 全局静默**：想临时全部隐藏，置 `enabled=false` 比逐个改模式更省事；此时 `beginFrame/endFrame` 仍可照常调用。
- **纯显示、无交互**：没有命中测试/拖拽；选中逻辑、手柄拾取需宿主自行实现（可按 `vertexCountAt` 之外的几何数据扩展）。
- **线段用细三角形模拟**：当前渲染库无线段图元，箭头杆/圆环/图标线框都由细长三角形构成，近看是「面」不是真正的线。
- **数值稳定**：几何计算对退化输入（零长度方向、平行向量）做了归一化保护；`allFinite()` 可用于断言没有 NaN。
