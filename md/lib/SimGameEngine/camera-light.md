# Camera 与 Light 实体

SimGameEngine 提供 Unity 风格的相机与光源实体：`Camera`、`Light` 都是场景节点（继承 `GameObject`，自带 Transform / layer / 父子层级），各自持有一个数据组件（`CameraData` / `LightData`）承载参数。方法命名贴合 Unity3D。

> 当前版本只提供节点结构、参数与矩阵/坐标计算；这些实体**尚未接入渲染系统的相机/光照消费链路**。要让场景画面真正响应 Camera/Light，仍由 `RenderSystem` 的相机状态与 `LightData.applyTo` 负责。

## 一、Camera

### 创建与绑定

```sl
import SimGameEngine;

Camera cam = Camera( "MainCamera" )       // 或 Camera.create("MainCamera")
CameraData cd = cam.getComponent<CameraData>()   // 取回数据组件
```

`Camera` 构造时自动挂一个 `CameraData` 组件，可用 `cam.cameraData` 字段或 `getComponent<CameraData>()` 访问，两者指向同一实例。相机节点自带 Transform，可像普通 GameObject 一样 `setParent`、设置 `layer`。

### 参数（经 CameraData）

| 方法 | 说明 |
|---|---|
| `setOrthographic(bool)` | 正交 / 透视切换 |
| `setFieldOfView(float)` | 透视垂直 FOV（角度），自动修正裁剪面 |
| `setOrthographicSize(float)` | 正交半高（Unity orthographicSize） |
| `setClipPlanes(near, far)` | 近远裁剪面，自动修正（near≥0.01，far>near） |
| `setAspect(float)` | 宽高比（宽/高） |
| `setPixelRect(int w, int h)` | 由像素尺寸设置宽高比 |
| `setCullingMask(int)` | 渲染层掩码（默认 -1 全部） |
| `setDepth(int)` | 深度排序 |
| `setClearFlags(int)` | 清屏标志（0 无 / 1 纯色 / 2 深度 / 3 全部） |
| `setBackgroundColor(r,g,b)` | 背景色 |

常量 `CameraData.CLEAR_NONE/CLEAR_SOLID_COLOR/CLEAR_DEPTH/CLEAR_ALL`。作实参时先落局部变量（`Int32 f = CameraData.CLEAR_ALL`）。

### 矩阵与坐标

四类能力：

```
// 投影 / 视图
projectionMatrix()          // 投影矩阵（透视/正交）
cameraToWorldMatrix()       // 相机本地 -> 世界
worldToCameraMatrix()       // 世界 -> 相机（视图矩阵）
viewProjectionMatrix()      // 视图 * 投影

// 坐标转换
worldToViewportPoint(p)     // 世界 -> NDC(-1..1)，w<=0 返回 null
viewportToWorldPoint(p)     // NDC -> 世界
worldToScreenPoint(p, w, h) // 世界 -> 屏幕像素（原点左上）
screenPointToRay(x, y, w, h)// 屏幕像素 -> 世界射线 Ray

// TRS 变换
transformPoint(p) / transformDirection(d)
worldToLocal(p) / localToWorld(p)
inverseTransformPoint(p) / inverseTransformDirection(d)

// 裁剪面 / 辅助
clampClipping() / nearClipPlane() / farClipPlane()
orthographicHalfWidth()     // orthographicSize * aspect
position() / up() / forward()
```

示例：把世界点投到屏幕并生成拾取射线。

```sl
Float32_3 ndc = cam.worldToViewportPoint( worldPos )
if ndc != null
{
    Float32_3 screen = cam.worldToScreenPoint( worldPos, 1280, 400 )
    Ray ray = cam.screenPointToRay( screen.x, screen.y, 1280, 400 )
    // ray.origin / ray.direction 可用
}
```

## 二、Light

### 创建与工厂

```sl
Light sun = Light.directional( "Sun" )
Light lamp = Light.point( "Lamp" )
Light torch = Light.spot( "Torch" )
// 也可 Light("Name")，默认平行光
LightData ld = sun.getComponent<LightData>()
```

`Light` 构造时自动挂一个 `LightData` 组件（与 `Camera` 同款绑定）。工厂会同时设定类型：directional=0 / point=1 / spot=2。

### 参数与计算

| 方法 | 说明 |
|---|---|
| `setType(int)` | 0 平行 / 1 点 / 2 聚光（越界忽略） |
| `setColor(r,g,b)` | 颜色 |
| `setIntensity(float)` | 强度 |
| `setDirection(dx, dy)` | 2D 光照方向（写入 LightData.dirX/dirY） |
| `setPosition2D(px, py)` | 2D 位置（聚光用） |
| `setSpotAngle(deg)` | 聚光半角（度） |
| `setRange(float)` | 有效范围（负数忽略） |
| `setShadows(q, bias, strength)` | 阴影参数 |
| `setSwing(x, intensity)` | 脚本摆动写入口 |
| `direction()` / `worldPosition()` | 经 Transform 的世界方向 / 位置 |
| `attenuation(distance)` | 距离衰减 `1 - clamp(d/range,0,1)`；range≤0 返回 1 |
| `spotAttenuation(cosAngle)` | 聚光锥角衰减；非聚光返回 1 |

## 三、注意事项 / 已知坑

1. **`data` 与 `range` 是词法保留字**：不能作字段名或局部变量名。数据组件字段用 `cameraData` / `lightData`，范围变量用 `rangeVal`。
2. **static 常量不作实参**：`cam.setClearFlags(CameraData.CLEAR_ALL)` 触发解析错误，先落局部变量 `Int32 f = CameraData.CLEAR_ALL; cam.setClearFlags(f)`。
3. **跨模块字段链先落局部**：`cam.transform.position = ...` 这类写法不被支持，先 `Transform t = cam.transform; t.position = ...`。
4. **字段链/嵌套调用拆单步**：`this.transform.worldMatrix().transformPoint(...)` 要拆成两步（引擎内部已按此实现）。
5. **未接入渲染**：本轮 Camera 不影响画面视角、Light 不参与实际照明；实际渲染仍用 `RenderSystem` 现有相机状态与光源收集逻辑。
