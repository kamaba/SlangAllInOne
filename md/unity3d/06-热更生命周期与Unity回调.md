# 06 · 热更生命周期与 Unity 回调

> SL 模块的**加载时机**、**如何对接 Unity 生命周期**（Awake/Start/Update/FixedUpdate/OnDestroy），
> 以及 **Domain Reload / IL2CPP AOT** 对热更的影响。

---

## 1. Unity 生命周期 ↔ SL 回调映射

| Unity 阶段 | SL 侧对应 | 桥接动作（`SlangLifecycle`） |
|------------|-----------|------------------------------|
| `Awake` | 模块装载 + 注册回调 | 首次 `cli_run_module_in_memory`；收集 SL 中声明为 lifecycle 的方法 |
| `Start` | `SL_Start()` | 调 SL 入口 / 已注册 Start 回调 |
| `Update` | `SL_Update(dt)` | 每帧主线程调（注意频率） |
| `FixedUpdate` | `SL_FixedUpdate(dt)` | 物理步调 |
| `OnDestroy` / 场景卸载 | `SL_OnDestroy()` | 干净退出 SL 执行域（isolate） |
| 应用暂停/聚焦 | `SL_OnPause/OnFocus` | 可选 |

- **起步形态**（见 `05` §2.1）：Unity 侧主动轮询式调用 SL 函数（每帧 `SlangLifecycle.Tick()` → `cli` 进入某 SL 方法）。
- **进阶形态**（`05` §2.3）：SL 写 `UnityBehaviour`，由 Unity Component 壳把回调喂回 SL。

---

## 2. 模块加载时机

| 时机 | 做法 | 适用 |
|------|------|------|
| `Awake` 一次性装载 | 游戏启动装载所有 SL 模块 | 包内运行、稳定逻辑 |
| 按需懒装载 | 进入某场景才装载对应 slb | 大工程、分模块热更 |
| 热更重装载 | 见 `04` 文件监视 → 主线程重装载 | 开发期 / 真机热更 |

> 关键：**所有 VM 调用必须在 Unity 主线程**（IL2CPP 下原生线程回调 C# 受限；见 `03` §3）。
> 文件监视线程收到事件后，用 `UnitySynchronizationContext` / `MainThreadDispatcher` 派发回主线程再重装载。

---

## 3. Domain Reload（域重载）的影响

Unity Editor 进/出 Play Mode 会 **重载脚本域（Domain Reload）**，导致：
- 所有静态字段重置、单例失效。
- **SlangUnityBridge 的 VM 句柄 / host 表 / handle 表必须重建**（不能在 `[RuntimeInitializeOnLoadMethod]` 之外缓存裸句柄跨域）。

应对：
- VM 实例与桥接状态挂在**非静态容器**或「域重载后重建」的初始化钩子（`RuntimeInitializeLoadType.AfterSceneLoad` / `BeforeSceneLoad`）。
- 热更状态若需跨域保留，按 `04` §4.2 序列化策略，不依赖静态字段。
- 可在 Player Settings 关闭 Domain Reload（开发期便利），但真机不受影响（真机无域重载）。

---

## 4. IL2CPP / AOT 对生命周期的影响

- **IL2CPP/iOS 不能 JIT**（见 `08`）：C VM 走解释执行，不影响「每帧调 SL 方法」这种模式（解释执行本就是逐指令）。
- **AOT 泛型/反射限制**：Unity IL2CPP 对 C# 反射有限制，但 **C VM 是原生插件、自带解释器，不依赖 Unity 的 C# 反射**——SL 的类型系统独立于 IL2CPP，故无 AOT 泛型爆炸问题。
- iOS 后台/挂起：App 进后台时停 `Update`，SL 的协程/计时器应感知 `OnApplicationPause`，避免在后台空转（`csimple_lang` 协程见 `COROUTINE_DESIGN.md`）。

---

## 5. 热重载时的状态保留（接 `04` §4）

- 简单策略：热更 = 销毁旧 isolate + 新建 + 重跑入口；Unity 对象不重建，仅重挂 `SlangLifecycle` 回调。
- 进阶：跨热更保留 SL 状态（global slot / 宿主字典），见 `04` §4.2 与 `13` 待办。
- **务必**：旧域退出时清理 host 表的 Unity 句柄登记（§6 handle 表），否则 Unity 对象被错误钉住、内存泄漏。

---

## 6. 多线程与 isolate

C VM 的 isolate = 1:1 OS 线程真并行（`vm_isolate.h`）。Unity 侧若要用多线程跑 SL：
- 子线程**不能直接回调 Unity C# API**（Unity 限制）→ 子线程只跑纯 SL 计算，结果经主线程回写 Unity（`05` 绑定层）。
- 或全程单线程（主线程驱动 VM），最简单、最稳，起步推荐。

---

## 7. 验收清单（本步交付判据）

- [ ] `SlangLifecycle` 在 `Awake/Start/Update` 正确驱动 SL 逻辑，帧率无异常。
- [ ] Editor 进/出 Play Mode（Domain Reload）后 VM 句柄重建、无悬垂/崩溃。
- [ ] 热更重装载后 `Update` 自动切到新逻辑、旧域干净退出。
- [ ] iOS/IL2CPP 下每帧调 SL 方法正常（无 JIT 报错）。
