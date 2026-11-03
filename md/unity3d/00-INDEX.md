# Unity3D 热更整合设计集（SlangUnity）

> 目标：把 **SimpleLanguage（SL / Slang）** 作为一种 **Unity3D 热更新脚本语言** 整合进 Unity 工程。
> 整合方式：将 C VM（`csimple_lang`，C99 可当 C++ 编译）编译为 **Unity 原生插件（C++ 库）**，
> 由 Unity C# 侧通过宿主桥接层加载并运行 SL 编译产物（SLB / 内存 JSON），实现「改 `.sl` → 重编译 → 热重载」的开发闭环。
>
> 本文集只承载**设计与整合路径**，不写最终实现代码（参照 `csimple_lang/md/design/MONO_INTEGRATION_DESIGN.md` 的设计风格）。
>
> 版本号：与全仓统一锚定 `0.0.59`（AGENTS.md R17）。本整合落地时四端版本号须同步 +1。

---

## 1. 这套设计解决什么

| 诉求 | 本文集给出的方案 |
|------|------------------|
| 用 SL 当 Unity 热更代码 | SL 编译为 SLB，Unity 启动时/热更时装载运行（`04-模块装载与热更新机制.md`） |
| 用 Unity 的 C++ 库（原生插件） | C VM 编译为 Unity 原生插件，平台目录对齐 `lib\{windows,linux,macos,ios,android}`（`02-本地插件编译与平台布局.md`） |
| C# 侧如何驱动 VM | P/Invoke / IL2CPP `extern "C"` 调 `csimple_lang_dll` 的 `cli_main` / `cli_run_module_in_memory`（`03-CSharp宿主桥接层.md`） |
| SL 怎么调 Unity API | 反向桥：Unity C# 经宿主回调把引擎对象暴露给 SL（`05-脚本绑定与Unity API映射.md`，类比 `MONO_INTEGRATION_DESIGN.md`） |
| 生命周期 / 域重载 / AOT | Unity 回调 ↔ SL 模块加载时机、热重载状态策略（`06-热更生命周期与Unity回调.md`） |
| IL2CPP / iOS 不能 JIT | 强制 `SL_JIT=0` / `--no-jit`（`08-JIT与IL2CPP约束.md`） |
| 调试 | 复用 SLDP `--debug-server=<port>`（`07-调试与诊断.md`） |
| 构建 / 部署 / 安全 | `09-构建管线集成.md` / `10-跨平台与部署.md` / `11-安全与沙箱.md` |
| 上手 | `12-示例与最佳实践.md`、`13-已知问题与设计待办.md` |

---

## 2. 文档清单

| # | 文件 | 主题 |
|---|------|------|
| 00 | `00-INDEX.md` | 本文件：导航、定位、与现有设计的关系 |
| 01 | `01-架构总览.md` | 总体架构、数据流、与 Mono/IL2CPP 的关系 |
| 02 | `02-本地插件编译与平台布局.md` | C VM → Unity 原生插件；CMake/vcxproj 登记（R6）；平台目录 |
| 03 | `03-CSharp宿主桥接层.md` | Unity C# 调 `csimple_lang_dll` 宿主 API；flags / UTF-8 约定 |
| 04 | `04-模块装载与热更新机制.md` | SLB + 「读取优先 SLB」mtime 守卫 = 热更核心；文件监视触发重编译 |
| 05 | `05-脚本绑定与Unity API映射.md` | SL↔Unity 引擎对象绑定；handle 表防 GC 悬垂；systemCalls 注册（R7） |
| 06 | `06-热更生命周期与Unity回调.md` | Unity 生命周期 / Domain Reload / IL2CPP AOT 与 SL 模块加载时机 |
| 07 | `07-调试与诊断.md` | SLDP 调试器接入 Unity Editor；日志桥接 |
| 08 | `08-JIT与IL2CPP约束.md` | 关键约束：IL2CPP / iOS 必须关 JIT；平台能力矩阵 |
| 09 | `09-构建管线集成.md` | Unity 构建事件把 `.sl` 编译进包；StreamingAssets / Addressables |
| 10 | `10-跨平台与部署.md` | Win/Mac/iOS/Android/WebGL 部署清单；原生插件 .meta |
| 11 | `11-安全与沙箱.md` | 热更代码沙箱、系统方法白名单、isolate 隔离 |
| 12 | `12-示例与最佳实践.md` | HelloCube + 热更改色最小示例；目录约定 |
| 13 | `13-已知问题与设计待办.md` | 关联现有 known issues；分阶段落地（类比 MONO 四阶段） |

---

## 3. 与现有设计的关系（必读，避免重复造轮子）

本整合**不是从零**，而是复用已落地的机制：

- **宿主 API**（`csimple_lang/src/cli/cli.h`）：`cli_main` / `cli_run_module_in_memory` —— Unity 宿主直接复用，无需新写 VM 入口。详见 `csimple_lang/md/cli.md`。
- **SLB 二进制包 + 读取优先 SLB**（`csimple_lang/md/design/SLB_DESIGN.md` §7.4）：mtime 新鲜度守卫（2s 容差）天然就是热更触发点。
- **插件平台目录约定**（`csimple_lang/md/design/PLUGIN_SYSTEM_DESIGN.md`）：`lib\{windows,linux,macos,ios,android}` 与 Unity 原生插件目录一一对应，可直接复用。
- **Mono 桥接设计**（`csimple_lang/md/design/MONO_INTEGRATION_DESIGN.md`）：SL↔C# 的编组、GCHandle 句柄表、异常映射，本整合的 `05` 是它的「Unity 反向版」。
- **JIT 设计**（`csimple_lang/md/design/JIT_DESIGN.md` §6.1）：Unity IL2CPP / iOS 必须关 JIT（`SL_JIT=0`）。
- **调试协议**（`csimple_lang/md/design/DEBUG_PROTOCOL_DESIGN.md`）：SLDP `--debug-server=<port>` NDJSON over TCP，Unity Editor 扩展可直连。
- **GC 设计**（`csimple_lang/md/design/GC_DESIGN.md`）：SL VM 手动内存 + 引用计数，跨边界对象需 handle 表（见 `05` §6）。

---

## 4. 硬规则挂钩（AGENTS.md）

| 规则 | 本整合的落点 |
|------|--------------|
| R6 新增 .c 两链登记 | `02`：C VM 作为 Unity 插件编译时，新 .c 必须登记 CMake + vcxproj |
| R7 系统方法四端同步 | `05`：SL 调 Unity API 经 systemCall，需 `.sl` 声明 + `Core.jsonc` + C VM `.c` + Front `ESystemMethodCall` |
| R15 读取优先 SLB | `04`：热更核心机制 |
| R16 UTF-8 新文件 | 所有 `.sl`/`.jsonc`/`.md` 统一 UTF-8 |
| R17 四端版本统一 | 本整合落地时版本号 +1 |
| R14 改动必配文档 | 本文集即承载；实现期改动须同步回本文集 |

---

## 5. 术语

| 词 | 含义 |
|----|------|
| C VM | `csimple_lang` 的 C99 运行时，即 SL 的执行引擎 |
| SLB | SL 模块的二进制包（`*.module.slb`），`SLB_DESIGN.md` |
| 宿主桥接层 | Unity C# 侧封装 `csimple_lang_dll` 的代码（P/Invoke 或 IL2CPP `extern "C"`） |
| 绑定层 | SL 侧访问 Unity 引擎对象（GameObject/Transform…）的桥（反向 csharp_mono） |
| 热重载 | 不重启 Unity 播放模式 / 不重打包，替换 SLB 让新逻辑生效 |
