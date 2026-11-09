# SLang Unity · C++ Native Binding

把 SLang 作为 Unity 的附属脚本语言：**SL 直接调用 C++**，C++ 直接调用 Unity 引擎原生接口。
C# 只是极薄宿主，不做任何 Unity API 映射、不做日志转发、不做逐帧回调表。

---

## 1. 能力边界

- SL 脚本编译为 `*.module.slb`，在 Unity 里装载执行；改脚本后可热更（不用重启 Play Mode）。
- SL 通过 `@DllImport` 直调 C++ 原生插件；C++ 通过 `UnityPluginLoad` 拿到引擎的日志与图形接口，日志直接进 Unity Console，渲染回调由引擎在渲染线程直接调用 C++。
- Unity 不导出 GameObject / Transform 的 C 接口，因此物体状态只能由 C# 写入引擎对象；这部分被压到**每帧 1 次原生调用 + 1 次引擎写入**。
- 当前仅 Windows x64（Editor / Standalone）；JIT 关闭，IL2CPP 构建可用。

---

## 2. 安装

- **UPM（推荐）**：把 `com.slang.unity` 放到工程的 `Packages/com.slang.unity/`，Unity 会自动识别；也可在 `Packages/manifest.json` 里加 `"com.slang.unity": "file:com.slang.unity"`。
- **.unitypackage**：菜单 `Tools > SlangUnity > Export .unitypackage` 导出，再双击导入其它工程。
- 安装示例数据：菜单 `Tools > SlangUnity > Install HelloCube Sample`，会把 SLB 与标准库模块放进 `Assets/StreamingAssets/Slang/`。

导入后确认 `Packages/com.slang.unity/Plugins/x86_64/` 下有三个原生库，且 Unity 的插件平台设置为 Windows x86_64。

---

## 3. 快速开始

1. 菜单 `Tools > SlangUnity > Enter Play Mode`（或直接点 Play）。
2. 组件会自动创建 `SlangCube`：自转 + 上下浮动，橙色；Console 出现 `[SL->C++]` 开头的日志（由 C++ 直接发出）。
3. 菜单 `Tools > SlangUnity > Verify (Editor)` 验证一次，结果写到工程 `Logs/slang-unity-verify.txt`。
4. Play Mode 中菜单 `Tools > SlangUnity > Report (Play Mode)` 查看引擎渲染回调计数与原生帧计数，结果写到 `Logs/slang-unity-report.txt`。

也可以把 `SlangUnityDriver` 挂到任意 GameObject，调用 `Attach(Transform)` 指向自己的物体，并把 `Module Relative Path` 改成自己的 SLB。

---

## 4. 改 SL 脚本与热更

1. 改 `.sl`（示例的源码在 `Samples~/HelloCube/`，运行时副本在 `Assets/StreamingAssets/Slang/`）。
2. 重新编译出新的 `HelloCube.module.slb`，覆盖 `Assets/StreamingAssets/Slang/HelloCube.module.slb`。
   - 在 SLang 仓库里可用 `SlangAllInOne/unity/build-unity-package.ps1 -SlOnly` 一条命令完成。
3. C++ 每 30 帧检查一次 SLB 时间戳，变化时把重载标志随帧一起返回，C# 收到后才重新执行 SL 模块。整个过程不重启 Play Mode，物体位置/角度不跳变。

Unity 运行时不要覆盖原生 DLL（被进程占用）；只换 SLB 是安全的。

---

## 5. 可用方法与签名

### 5.1 SL 侧（C++ 导出，声明后直接调用）

在 `.sl` 里以 `@DllImport( "slang_unity", "符号", "sig" )` 声明静态函数：

| SL 函数 | 签名 | 作用 |
|---|---|---|
| `SluProbe()` | `->i32` | 绑定自检，成功返回 `20261109` |
| `SluBindTarget(string)` | `utf8->i32` | 记录目标名字 |
| `SluSetBasePosition(double,double,double)` | `f64,f64,f64->i32` | 基准位置 |
| `SluSetSpin(double)` | `f64->i32` | 每秒自转角度 |
| `SluSetColor(double,double,double)` | `f64,f64,f64->i32` | 颜色 RGB（0~1） |
| `SluSetBob(double,double)` | `f64,f64->i32` | 浮动幅度与速度 |
| `SluLog(string)` | `utf8->i32` | 写一条日志（Unity 内直进 Console） |
| `SluTarget()` | `->utf8` | 读回目标名字 |

### 5.2 C# 侧（只有驱动）

| 方法 | 作用 |
|---|---|
| `slu_boot(pathUtf8)` | 装载并执行 SL 模块 |
| `slu_frame(dt, out9)` | **每帧唯一一次跨边界调用**：推进一帧 + 取 9 个 double（位置 xyz / 旋转 xyz / 颜色 rgb）+ 返回热更/颜色脏标志 |
| `slu_get_render_event_func()` | 取渲染回调指针，注册一次后由引擎逐帧调用 C++ |
| `slu_diag(out6)` | 引擎接口挂载、渲染器、设备、渲染回调次数、原生帧数等诊断数据 |

`slu_frame` 返回标志：`0x01` 需要热重载、`0x02` 颜色变化、`0x04` 已装载、`0x08` 引擎日志接口已挂载。

---

## 6. 速度设计（为什么这样最快）

| 环节 | 每帧次数 | 说明 |
|---|---|---|
| SL → C++ | 0 | SL 只在装载/热更时执行一次，运行时数值推进全在 C++ |
| C# → C++ | **1** | 帧推进、状态读取、热更检查合并为一次 `slu_frame`；状态数组固定为原始指针，无封送复制 |
| C++ → Unity 日志 | 0 | `IUnityLog` 直发 Console，C# 不再转印 |
| 引擎 → C++ 渲染回调 | 1 | `CommandBuffer.IssuePluginEvent` 注册一次，之后由引擎在渲染线程直接调用 |
| C# → 引擎对象 | **1** | `Transform.SetPositionAndRotation` 一次写入位置+旋转；颜色仅在脏标志出现时用 `MaterialPropertyBlock` 写入 |

一次原生调用在本机实测约 10 ns；稳态每帧跨边界成本约几十纳秒。打成 IL2CPP 后，C# 被编译为原生代码，边界进一步退化成普通函数调用。

---

## 7. 使用技巧、注意事项与已知坑

- **Unity 运行时只换 SLB，不要重编原生 DLL**；确需改 C++，先退出 Play Mode 或关闭编辑器。
- `HelloCube.jsonc` 的 `dllImports.path` 写的是本机绝对路径；工程移动或换机器后要改这一行再重新编译 SL 模块，否则 FFI 会静默走 fallback（SL 里用 `SluProbe()` 自检，出现 `NOT active` 就是路径不对）。
- 标准库模块 `Core.module.slb` / `Std.module.slb` 必须在 SLB 同目录的 `lib/` 下，否则模块装载会失败。
- `UnityPluginLoad` 只在 Unity 进程里被触发；在 Unity 外用命令行跑同一个 DLL 时，日志回退到 stdout/调试输出，功能不变。
- 渲染回调通过 `CameraEvent.AfterForwardOpaque` 注册；若项目用不触发该事件的自定义渲染管线，`Report` 里的 `renderEventCount` 会是 0，需要改用其它渲染事件点。
- `MaterialPropertyBlock` 同时写了 `_Color`（Built-in/Standard）与 `_BaseColor`（URP/Lit），自定义 Shader 若用别的属性名请自行调整。
- SL 注释用 `#`，不是 `//`；所有文本文件保持 UTF-8。
- `.unitypackage` 只包含包本体（Unity 会忽略 `Samples~` 目录）；用它导入别的工程时，需手动把 `HelloCube.module.slb` 与 `lib/` 放到 `Assets/StreamingAssets/Slang/`。用 UPM 安装则可直接用 `Install HelloCube Sample` 菜单。
- 从旧版（Assets 散装）升级时，`Assets/Plugins/x86_64/` 里的旧 DLL 可能被运行中的 Unity 占用而删不掉；关闭编辑器后手动删除即可，它与包内 DLL 不同名，不影响运行。
- 原生调用限定主线程（渲染回调除外）；跨平台需要重新编译对应平台的插件，本包只带 Windows x64。
- 包内 `UnityPluginAPI` 头文件来自 Unity 安装目录，遵循 Unity Companion License（见其 `LICENSE.md`）。

---

## 8. 包内目录

| 位置 | 内容 |
|---|---|
| `Runtime/` | C# 极薄宿主（`SlangUnityDriver` + P/Invoke 声明） |
| `Editor/` | 示例安装、验证、Play Mode 报告、`.unitypackage` 导出菜单 |
| `Plugins/x86_64/` | C++ 绑定插件、C VM 与依赖库 |
| `Samples~/HelloCube/` | SL 源码、SLB 与标准库模块 |
