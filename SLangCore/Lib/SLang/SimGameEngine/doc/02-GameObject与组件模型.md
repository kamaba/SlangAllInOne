# SimGameEngine · 02 GameObject 与组件模型

> 状态：Behaviour 部分【已落盘】（`../Behaviour.sl`）；GameObject / Component 容器 API 为【设计稿】。
> 前置阅读：`01-总体架构与边界.md`。

---

## 1. 模型总览

```
Scene
 └─ GameObject                       ← 树节点、容器、身份
     ├─ Transform                    ← 必有且仅有一个（创建时自动挂）
     ├─ Behaviour 子类               ← 脚本逻辑：awake/update/...
     ├─ Renderer + Mesh/Material     ← 渲染数据（第 04 章）
     ├─ Camera / Light / Probe       ← 特殊组件（第 06 章）
     ├─ Animation / Effect           ← 表现层（第 07 章）
     └─ UIBehaviour 子类             ← UI 节点（第 08 章）
```

三条硬规则：

1. **每个 GameObject 必带 Transform**，不允许手动移除；
2. **同类组件只能挂一个**（按类型去重），需要多个同类实体时建子节点；
3. **组件不能跨 GameObject 共享实例**：每个组件实例只属于一个宿主节点（Material / Mesh 等资源可以共享，组件不行）。

## 2. GameObject【设计稿】

### 2.1 字段

| 字段 | 类型 | 说明 |
|---|---|---|
| `name` | string | 显示名，同父下允许重名，但 `findByName` 返回第一个命中 |
| `tag` | string | 逻辑分类标签，用于批量查找 |
| `layer` | int | 0..31，与 Render 相机的 `cullMask` 位对应 |
| `activeSelf` | bool | 自身激活开关；实际可见 / 可更新看 `activeInHierarchy` |
| `transform` | Transform | 只读引用，创建时自动生成 |
| `parent` | GameObject | 只读引用，根节点为 null |
| `childCount` | int | 直接子节点数 |

### 2.2 方法签名（拟定）

```sl
public static GameObject create( string name )
public static GameObject create( string name, GameObject parent )

public void setActive( bool value )                  # 切换 activeSelf，触发子树 onEnable/onDisable
public bool getActiveInHierarchy()                   # 自身及所有祖先均 activeSelf 才为 true

public T addComponent<T>() where T : Component       # 同类已存在则返回既有实例
public T getComponent<T>()                           # 不存在返回 null
public bool removeComponent<T>()                     # 帧尾延迟销毁，见 §5
public Array<Component> components()

public void setParent( GameObject parent )           # null = 移到根；保持世界变换由调用方决定
public GameObject getChild( int index )
public GameObject find( string path )                # "Root/Child/Leaf"，相对当前节点

public void destroy()                                # 标记销毁，帧尾统一 dispose
```

> 说明：上述签名为**目标形态**，尚未落盘。落地时以实际 `.sl` 为准，本文提供的是调用侧契约与语义。

### 2.3 生命周期与激活

- `create()` 后立即调用所有组件的 `awake()`（子树按父先子后）；
- 首次进入帧循环、且节点处于激活态时，组件 `start()` 调用一次；
- `activeSelf = false` 时：`update / lateUpdate / fixedUpdate` 全部跳过，组件 `onDisable()` 触发；恢复时 `onEnable()` 触发；
- 父节点禁用会让整棵子树 `activeInHierarchy = false`，但**不改变**子节点自身的 `activeSelf`（与 Unity 一致）；
- 重新启用父节点后，子节点的启用态恢复原状。

## 3. Component【设计稿】

`Component` 基类来自 **Std 根级**（Render 的 `Renderer` / `Camera` / `Light` 都 `extends Component`），因此使用本模块必须 `import Std;`。引擎侧的组件容器行为约定：

| 约定 | 说明 |
|---|---|
| 宿主唯一 | `owner` 指向所属 GameObject，组件不得手工改 |
| 类型唯一 | 同一 GameObject 上 `getComponent<T>()` 最多一个实例 |
| 创建期 | `awake()` 在组件挂载后立即调用；此时其他组件可能尚未挂载，跨组件查找放到 `start()` |
| 销毁期 | `dispose()` 由宿主在帧尾调用，组件内部只做资源释放，不主动删节点 |

## 4. Behaviour【已落盘】

源码：`../Behaviour.sl`。继承 `Component`，是全部游戏脚本的基类。

### 4.1 字段与签名

| 签名 | 作用 |
|---|---|
| `bool isEnabled` | 组件启用标记，初值 `true` |
| `void awake()` | 创建后立即调用一次（子类 override） |
| `void start()` | 第一帧更新前调用一次（子类 override） |
| `void update()` | 每帧调用（子类 override） |
| `void lateUpdate()` | 每帧所有 `update()` 之后调用（子类 override） |
| `void fixedUpdate()` | 固定步长调用，用于物理 / 稳定逻辑（子类 override） |
| `void onEnable()` | 由禁用变启用时触发 |
| `void onDisable()` | 由启用变禁用时触发 |
| `void dispose()` | 销毁前清理 |
| `void setEnabled(bool value)` | 启用 / 禁用；状态没变时直接返回，变了才触发 onEnable/onDisable |
| `bool getEnabled()` | 读取启用标记 |
| `string toString()` | `Behaviour(enabled=...)` |

### 4.2 最小示例

```sl
import Std;

public class Spin extends Behaviour
{
    public Float32 speed = 90.0f

    override void start()
    {
        Console.println( "spin start" )
    }

    override void update()
    {
        # 每帧转一点；实际写法以 Transform 落盘后的 API 为准
        this.owner.transform.rotateZ( this.speed * Time.deltaTime )
    }
}

# 挂载：
# GameObject go = GameObject.create( "Cube" )
# go.addComponent<Spin>()
```

### 4.3 钩子使用规则

| 场景 | 推荐钩子 | 原因 |
|---|---|---|
| 初始化自身状态 | `awake()` | 最早执行，只一次 |
| 访问其它组件 / 其它节点 | `start()` | 此时场景挂载基本完成 |
| 逐帧游戏逻辑 | `update()` | 标准帧驱动 |
| 相机跟随、后处理参数写入 | `lateUpdate()` | 保证目标已在本帧更新完毕 |
| 物理积分、固定步长模拟 | `fixedUpdate()` | 与帧率解耦 |
| 注册 / 注销事件、开关特效 | `onEnable/onDisable` | 与启用态同步，避免遗忘清理 |
| 释放句柄、注销监听 | `dispose()` | 帧尾统一调用，避免半销毁状态被访问 |

## 5. 销毁与延迟回收

`destroy()` 不立即释放对象，而是标记后等到帧尾（第 09 章的帧序第 11 步）统一处理：

```
go.destroy()
  → 标记 pendingDestroy
  → 组件 onDisable() 立即触发
  → 本帧剩余逻辑仍可安全读该节点
  → 帧尾：各组件 dispose() → 从父节点摘除 → 回收 RenderObject 句柄
```

**不要**在 `update()` 中销毁正在遍历的子节点集合成员后再继续迭代该集合：先收集待删列表，遍历结束统一 `destroy()`（这是容器迭代的通用原则，不是 SLang 专属坑）。

## 6. 已知坑与注意

1. `setEnabled()` 在状态未变化时**不触发**钩子（C 侧 `vm_sys_component_set_enabled` 同值短路），不要依赖反复 `setEnabled(true)` 来刷新状态。
2. `isEnabled` 是组件级开关，`activeSelf` 是节点级开关；两者任一为 false，更新都会被跳过。
3. `UIBehaviour extends Behaviour`（`../UIBehaviour.sl`），因此 UI 脚本同时具备本节全部生命周期；不要重复实现一套启用逻辑。
4. `toString()` 已被重写，调试打印组件时输出 `Behaviour(enabled=...)` 而非默认对象串。
5. 【2026-11-16 落盘】`GameObject`/`Transform`/`Scene`/`Application` 已可编译运行（`SimEngineTest` 60 项全绿）。两处硬约束：① 组件挂载用 `go.addComponent( Probe() )`（方法级泛型构造 `T()` 触发编译器崩溃，已登记）；② 跨模块钩子经 `SystemSimEngineCallHook` 按名派发（slb 基类 CallVirt 不派发消费方 override，已登记），用户代码调 `setEnabled` 建议改走 `SystemSimEngineSetEnabled`——详见 doc/10 §6。
