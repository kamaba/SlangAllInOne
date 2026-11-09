# 05 · 脚本绑定与 Unity API 映射

> SL 脚本如何**访问 / 操作 Unity 引擎对象**（GameObject / Transform / Component / 输入 / 日志…）。
> 这是 `MONO_INTEGRATION_DESIGN.md` 的**反向版**：那里 SL 调独立 Mono 的 C#；这里 SL 调**宿主 Unity 自己的 C#**。
>
> 🔥 **落地口径（2026-11-09，用户定稿）**：第一版实例采用本文 §2.2「FFI 直调」——SL 经 `@DllImport`
> 直调 C++ 原生插件，**未采用 §2.1 的 systemCall → C# host 回调**，C# 侧零 API 映射。
> 见 `14-实例落地记录.md` §1 与使用文档 `SlangAllInOne/unity/README.md`。

---

## 1. 绑定方向：SL → Unity（反向桥）

```
SL 代码:  transform.position = vec3(0, 5, 0);  print("hello unity");
   │  （编译为 systemCall：SL → Unity 引擎调用）
   ▼
C VM system_method_call/*  （SL VM 内 systemCall 分派，R7）
   │  经 host function table 回调
   ▼
Unity C# 宿主回调 (SlangHostCallbacks)
   │  （托管侧把请求映射到真正的 UnityEngine API）
   ▼
Unity 引擎: gameObject.transform.position = new Vector3(0,5,0); Debug.Log("hello unity");
```

对照 `MONO_INTEGRATION_DESIGN.md`：
- 那边 `mono_bridge` 把 SL 调用**推给外部 Mono 运行时**（`mono_runtime_invoke`）。
- 这边把 SL 调用**拉回宿主 Unity C#**（宿主回调），因为 Unity 的 C# 就是「当前进程的托管运行时」，无需再起一个 Mono。

---

## 2. 绑定层的三种实现形态（推荐分级）

### 2.1 systemCall 直桥（推荐起步，R7 四端同步）
SL 经 VM 的 systemCall 机制调 Unity。需**四处同步**（AGENTS R7）：
1. `.sl` 声明（SL 侧可调用签名）
2. `SlangAllInOne/SLangCore/Lib/Core/Core.jsonc` 的 `systemCalls[].cvmFunction`
3. C VM `src/vm/system_method_call/*.c` 实现（把调用经 host 回调转给 Unity）
4. Front `Define.cs` 的 `ESystemMethodCall` 枚举

- C VM 侧实现**不直连 Unity**（R3：VM 核心禁平台代码），而是经 `03` §4 的 host function table 回调到 Unity C#。
- 例如 `SystemUnity.Log(string)` → VM 侧 `sl_unity_log` → host callback `Host_UnityLog` → `Debug.Log`。

### 2.2 FFI 直调（对标 `ffi-design.md`）
若 Unity 把某些引擎入口以 C 函数暴露（或自写 C++ 薄层），可走 C VM 的 FFI（`SlangAllInOne/md/project/ffi.md`、`csimple_lang/md/design/ffi-design.md`），
经 `sl_ffi_call.c` 127 调用形状 + 原生块。适合「高频、低延迟」的引擎调用（如逐帧 Transform 写）。

### 2.3 代理对象桥（进阶，类 MonoBehaviour 体验）
让 SL 能写「类 Unity 组件」语义：
```sl
class Spin : UnityBehaviour {
    void Start() { print("spin start"); }
    void Update() { self.transform.Rotate(0, 1, 0); }
}
```
- SL 侧 `UnityBehaviour` 由 Front 识别（类比 `AtSignLabel` / 插件 capability，`PLUGIN_SYSTEM_DESIGN.md`）。
- C VM 侧为每个 SL 行为实例在 Unity 侧建一个「薄 Component 壳」，把 `Update` 经 host 回调喂回 SL。
- 本期**列为进阶待办**（`13`），起步用 2.1 即可驱动逻辑。

---

## 3. 类型映射与编组（Marshalling）

复用 `MONO_INTEGRATION_DESIGN.md` §7 的编组思路，目标换成 Unity 类型：

| SL 类型 | C VM 表示 | Unity 侧类型 | 编组 |
|---------|-----------|--------------|------|
| `int` | `int32_t` | `int` | 值直传 |
| `float`/`double` | `double` | `float`/`double` | 值直传（注意 float↔double 精度） |
| `bool` | int | `bool` | 值直传 |
| `string` | UTF-8 `char*` | `string` | UTF-8 ↔ UTF-16（R16） |
| `Vec3` | SL 结构体/数组 | `UnityEngine.Vector3` | 逐分量拷贝（x,y,z） |
| `object`/`class` | SL 对象（持有不透明 id） | `UnityEngine.Object` 子类 | **handle 表**持有（§6） |

要点：
- 值类型（int/float/bool/Vec3）直接按值编组，无 GC 负担。
- 引用类型（GameObject/Component/Texture…）**不能**把裸指针长期存 C 侧 → 必须走 handle 表（`06`/`MONO_INTEGRATION_DESIGN.md` §8）。

---

## 4. host function table 注册（复用 VM 既有机制）

C VM 已有 `SLVmExtVm` / `SLPluginHost` 前缀镜像 ABI（`JIT_DESIGN.md` F9、`MONO_INTEGRATION_DESIGN.md` §4.3 V7/V8）。
绑定层应：
1. 在 VM 初始化时把一组 `Host_Unity*` 函数指针注册进 host 表（类比 `mono_bridge_init` 挂 `mono_runtime_invoke`）。
2. C VM systemCall 实现内调 host 表对应项，把 SL 值编组为 Unity 参数。
3. **新增 host 字段只能追加到结构体尾部**（F9 纪律），保证跨版本 ABI 兼容。

---

## 5. 异常映射

复用 `MONO_INTEGRATION_DESIGN.md` §9：
- Unity C# 抛 `Exception` → host 回调捕获 → 经 `host->throw_error`（V8）抛为 **SL 运行时异常** → SL `try/catch` 捕获。
- 反向：SL 抛异常冒泡到 Unity 侧时，桥接层转 `Debug.LogError` + 可选吞掉防止卡帧。
- 失败码可参照 `MONO_INTEGRATION_DESIGN.md` 的 `-9x` 系列（ASM_LOAD/NOT_FOUND/MARSHAL/MANAGED_EXC）。

---

## 6. 跨边界对象生命周期（handle 表，防 GC 悬垂）

SL VM 用**手动内存 + 引用计数**（`GC_DESIGN.md`），Unity 用 **Boehm/sgen GC**。
若 SL 侧长期持有 Unity 对象（如 `GameObject` 引用），Unity GC 看不到 C 侧引用 → 误回收 → 悬垂。

方案（类比 `MONO_INTEGRATION_DESIGN.md` §8 的 GCHandle）：
- SL 创建/获取 Unity 对象时，Unity 侧 `GCHandle` / 字典登记该 `UnityEngine.Object`，把 **不透明 id** 回传 SL（作为 SL 对象的字段）。
- SL 每次调该对象的方法前，Unity 侧用 id 取回 `UnityEngine.Object`。
- SL 对象被 SL GC 回收时，回调 Unity 侧 `FreeHandle(id)` 释放登记。
- **绝不**把 `UnityEngine.Object*` 裸指针长期存 C 堆。

> 注意：Unity 的 `Object` 还有「场景卸载即 Destroy」语义——handle 表需对「对象已被 Unity 销毁」做空检查，避免访问已失效对象。

---

## 7. 验收清单（本步交付判据）

- [ ] SL 能调 `Unity.Log(string)` 并出现在 Unity Console（UTF-8 中文正常，R16）。
- [ ] SL 能读写 `transform.position`（Vec3 编组正确）。
- [ ] SL 持有 GameObject 引用跨多帧不悬垂（handle 表生效）。
- [ ] Unity 侧异常被 SL `try/catch` 捕获；SL 异常不卡 Unity 帧。
- [ ] R7 四处同步无遗漏（`.sl` + `Core.jsonc` + C VM `.c` + Front `ESystemMethodCall`）。
