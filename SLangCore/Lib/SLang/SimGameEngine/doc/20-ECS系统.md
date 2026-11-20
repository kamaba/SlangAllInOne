# SimGameEngine · 20 ECS 系统（opt-in）

> 状态：【已落盘】（v2.17，2026-11-20）。`SimEcsTest` 48 项全绿，十八套 + ECS 共 928 PASS / 33 FAIL（33 项为 v2.11 已登记的 fixedDt 既有回归，无新增）。
> 前置阅读：`02-GameObject与组件模型.md`、`05-合批与RenderObject提交.md`。

---

## 1. 它解决什么

传统模式下 `GameObject` 同时持有数据组件与 `Behaviour` 脚本：渲染组件挂在节点上、逻辑逐节点回调、合批器每帧重新遍历整棵树。ECS 模式把这条链路拆成四段：

```
GameObject（只挂 Data + Transform）
      │  注册时把 MeshRef / MaterialRef 拔离到 EcsWorld
      ▼
EcsWorld（实体表 + 数据仓 + 分层结果）
      │  EcsLogicSystem 集中跑全部逻辑（一次调度，不逐节点回调）
      ▼
逻辑终态 → buildLayers()：按合批键自动分层、同键合并
      ▼
RenderSystem.sync()：把分层结果整体提交为 RenderObject
```

一句话：**节点只留数据，逻辑统一处理，渲染由世界分层合并后整体提交。**

---

## 2. 怎么启用（使用契约）

### 2.1 三步接线

```sl
Application app = Application()
app.init()
EcsWorld world = EcsWorld()
Systems sys = Systems()
sys.bindEcs( app, world )     # 一步完成：world 挂 app + 设为 render.ecsSource
sys.init( 480, 360 )          # 渲染/音频后端照旧
```

不调用 `bindEcs`（或 `app.ecsWorld == null`）时，引擎行为与 v2.16 完全一致，旧工程零影响。

### 2.2 节点与组件规则

| 挂载对象 | ECS 模式行为 |
|---|---|
| `EcsData` 子类 | 进 `world` 数据仓，按实体 + `kind` 标签唯一；不进节点组件表 |
| `MeshRef` / `MaterialRef` | 渲染数据拔离到 `world`，由 `meshOf/materialOf` 读取 |
| `EcsLogic` 子类 | 进 `world.logic` 集中调度，不进节点组件表 |
| `Transform` | 仍留在节点（层级与世界变换照旧） |
| 其它 `Behaviour` | **拒绝挂载**，`go.lastEcsReject` 记下类型名 |

注册前已挂在节点上的 `MeshRef` / `MaterialRef` 会在 `world.register(go)` 时自动拔离；`unregister(go)` 时归还节点。

```sl
GameObject go = app.activeScene.createObject( "Enemy" )
world.register( go )          # 开启该节点的 ECS 模式

MeshRef mesh = MeshRef()      # 渲染数据
mesh.meshKind = 1
mesh.useQuad( 1.0f )
go.addComponent( mesh )

MaterialRef matRef = MaterialRef()
matRef.material = sharedMat
go.addComponent( matRef )

SpeedData speed = SpeedData() # 纯数据组件（extends EcsData）
speed.kind = "speed"
speed.speed = 2.5f
go.addComponent( speed )

ChaseLogic chase = ChaseLogic()  # 逻辑组件（extends EcsLogic）
chase.order = 10
world.addLogic( chase, go )   # 等价 go.addComponent(chase)
```

### 2.3 逻辑组件写法

`EcsLogic` 提供 `awake/start/update/lateUpdate/fixedUpdate` 钩子，写法与 `Behaviour` 子类相同（`override void update()`）；`entity` 字段指向关联实体，数据通过 `world.dataOf(entity, kind)` 读。`order` 小的先执行，相同则保持登记顺序。

```sl
public class ChaseLogic extends EcsLogic
{
    override void update()
    {
        GameObject target = this.entity
        SpeedData sd = EcsWorld.active.dataOf( target, "speed" ) as SpeedData
        if sd != null
        {
            Transform t = target.transform
            t.setPosition( Float32_3( t.worldPosition.x + sd.speed * 0.016f, 0.0f, 0.0f ) )
        }
    }
}
```

逻辑资格：组件启用 + 实体未待销毁 + 层级激活，任一项不满足即跳过该帧（与 `Behaviour` 一致）。

### 2.4 一帧时序

`Application.tick` 中 ECS 插入点：

1. 固定步：物理/碰撞之后调 `world.fixedLogic()`；
2. `start/update/lateUpdate` 全部跑完后调 `world.updateLogic(dt)` + `world.lateLogic(dt)`；
3. `updateTransforms()` 之后调 `world.buildLayers()`（分层合并读到的是本帧世界变换终态）；
4. 渲染帧 `sys.sync(scene, time)` 发现 `render.ecsSource != null`，直接提交第 3 步的分层结果。

---

## 3. 可用 API 签名

### EcsWorld

```sl
static EcsWorld active                          # 当前世界（Godot 式上下文；由 attach 设置）
void   attach( Application app )                # app.ecsWorld = this + active = this
void   detach()
bool   register( GameObject go )                # 开启 ECS 模式并拔离渲染数据
bool   unregister( GameObject go )              # 归还渲染数据、清数据项
void   clear()
Int32  entityCount()
GameObject entityAt( Int32 idx )
void   setRenderData( GameObject go, MeshRef mesh, MaterialRef mat )
MeshRef    meshOf( GameObject go )
MaterialRef materialOf( GameObject go )
void   addData( GameObject go, EcsData value )
EcsData dataOf( GameObject go, string typeName )
Int32  dataCount( GameObject go )
void   addLogic( EcsLogic item, GameObject go )
void   fixedLogic()
void   updateLogic( Float32 dt )
void   lateLogic( Float32 dt )
Int32  buildLayers()                            # 返回层数；结果在 layerAt()
Int32  layerCount()
EcsLayer layerAt( Int32 idx )
```

`EcsLayer`（继承 `BatchGroup`，渲染层按 `BatchGroup` 消费）：`layerIndex` / `merged` / `mergedCount` / `finish(idx)`；合批键与 `05` 章完全相同（材质实例、program、贴图、网格、layer、renderQueue、实例色等），同键合并、异键拆层。

### Systems / RenderSystem

```sl
void bindEcs( Application app, EcsWorld world )  # 一键接线
EcsWorld ecsSource                               # RenderSystem 的 ECS 提交源（null=旧路径）
```

---

## 4. 已知边界与坑

| 项 | 说明 |
|---|---|
| 只拔离 3D 渲染数据 | 当前接管 `MeshRef` / `MaterialRef`；`LightData` / `SpriteRenderer` / UI 仍走各自系统从场景收集（与 ECS 分层并行，互不冲突） |
| 分层键固定 | 合批键沿用 `Batcher.keyEquals` 的字段集，新增渲染组件需扩键才会影响合批 |
| 顶点上限 | 烘焙组合并后仍受单组 4096 顶点 / 256 对象上限约束（与旧路径同） |
| 字段与局部变量同名 | `GameObject` 的 ECS 世界字段名为 `ecsWorld` 而非 `world`：SLang 会把子类局部变量 `world`（如 `Camera.worldToCameraMatrix`）当字段解析，连锁污染调用链 |
| 保留字 | 数据绑定方法名 `attachTo`（`bind` 是保留字）；数据仓内部标签变量用 `kindName`（`label` 是保留字） |
| 下标读 | 跨模块读 `List` 下标结果必须先赋局部变量再比较/参与表达式 |
| 重复构建 | `Application.tick` 与 `RenderSystem.sync` 都可能触发 `buildLayers()`；后者按相机 `cullMask` 覆盖重建，结果一致，仅多一次 CPU 分组 |

---

## 5. 变更记录

| 日期 | 版本 | 变更 |
|---|---|---|
| 2026-11-20 | v2.17 | ECS 模式首版：Data 组件 / 世界数据仓 / 集中逻辑系统 / 分层合并 / 渲染统一提交；`SimEcsTest` 48 项；本文件 + `00-INDEX` 同步 |
