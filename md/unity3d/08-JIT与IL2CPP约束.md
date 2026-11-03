# 08 · JIT 与 IL2CPP 约束（关键硬性约束）

> **Unity IL2CPP / iOS 禁止运行时生成代码，C VM 的 JIT 在这些平台必须关闭。**
> 本文件是整合的**强制约束清单**，第一次编译 Unity 插件就得落实（`02` 联动）。

---

## 1. 为什么必须关 JIT

`csimple_lang/md/design/JIT_DESIGN.md` 要点：
- JIT 把热点 SL 方法编译为 **x86-64 机器码**（`VirtualAlloc(PAGE_EXECUTE_*)` / `mmap(PROT_EXEC)`）。
- **iOS 内核禁止运行时分配可执行内存**（苹果强制 AOT）→ JIT 不可用。
- **Unity IL2CPP** 把 C# 转 C++ 再 AOT 编译，运行环境同样无 JIT 能力（且 Unity 自身也不 JIT）。
- JIT 能力开关 `VM_JIT_ENABLE` 默认 = `Release + x86-64 + 非 wasm → ON`（`JIT_DESIGN.md` §6.1 L1）；但 **iOS / 32 位 / wasm 默认 OFF**。

结论：**面向 Unity 的 C VM 插件构建，在 IL2CPP / iOS / Android-IL2CPP / WebGL 目标上，JIT 必须强制 OFF。**

---

## 2. 关闭手段（三层，优先级见 JIT_DESIGN §6.1）

| 层 | 手段 | 适用 |
|----|------|------|
| **L1 构建期** | `cmake -DVM_JIT_ENABLE=OFF` / vcxproj 不注入 `VM_JIT_ENABLE` | Unity 插件的 iOS/IL2CPP 构建树 |
| **L2 运行期** | 环境变量 `SL_JIT=0`（或 `false`） | **dll 宿主（Unity）首选关闭手段**（`JIT_DESIGN` §6.1 规则 4） |
| L2 运行期 | CLI `--no-jit` | 仅当走 `cli_main` argv 时可用；Unity 内存 API 不走 argv → 用 `SL_JIT=0` |

> 推荐组合：**Unity 插件构建树 `VM_JIT_ENABLE=OFF`（L1）** + **运行时设 `SL_JIT=0`（L2 兜底）**，双保险。
> Editor（Mono）开发期若平台是 x86-64 可开 JIT 提速，但为一致性建议统一关，避免「Editor 快、真机崩」错配。

---

## 3. Unity 平台能力矩阵

| Unity 目标 | 后端 | C VM JIT | 说明 |
|------------|------|----------|------|
| Editor (Win/Mac) | Mono | 可开（x86-64） | 开发期可加速；建议统一关以对齐真机 |
| Standalone Win/Linux/Mac | **IL2CPP** 或 Mono | IL2CPP=关；Mono x64=可开 | 以 IL2CPP 发布为准 → 关 |
| **iOS** | 强制 AOT | **必须关** | 苹果禁运行时可执行内存 |
| Android | IL2CPP / Mono | IL2CPP=关 | arm64 后端 JIT 在 `JIT_DESIGN` 列 P5，当前 OFF |
| **WebGL** | wasm (Emscripten) | **关**（`JIT_DESIGN`：wasm 明确不支持） | 复用 `csimple_lang/md/WASM_BUILD.md` |
| 主机 (PS/Xbox/Switch) | 厂商 AOT | 关 | 主机均 AOT，无 JIT |

> 一句话：**凡是 Unity 的 IL2CPP / AOT / wasm 目标，JIT 一律关；只有 Editor Mono x64 与 Standalone Mono x64 可开。**

---

## 4. `--debug` 自动关 JIT（已内置，善加利用）

`JIT_DESIGN.md` §6.1 规则 3：`--debug`（`vm->is_debug==1`）时 JIT **强制禁用**（保证调试器逐指令语义）。
- Unity 侧接 SLDP 调试器（`07`）时传 `SLVM_MEM_FLAG_DEBUG` → 自动关 JIT，无需额外处理。
- 这也意味着「调试态」与「真机态」行为一致（都解释执行），避免 JIT/解释器语义差（`JIT_DESIGN` 已知 Monitor 9 等已知差异仅限两平台同败场景，与 Unity 无关）。

---

## 5. 解释执行的性能预期

关 JIT = 走解释器（每指令 ~几十 ns 量级，`JIT_DESIGN` 背景段）。对**热更逻辑**（游戏脚本、UI、玩法）通常足够：
- 避免 SL 在 `Update` 里做超高频纯计算（那种应下沉 C#/C++ 或走 `05` §2.2 FFI 直调）。
- 先把热点逻辑用 Unity C# 写好、SL 只做编排，是稳妥的起步姿态。

---

## 6. 验收清单（本步交付判据）

- [ ] iOS 构建 `VM_JIT_ENABLE=OFF`，Archive 无 `PAGE_EXECUTE`/JIT 符号。
- [ ] Android IL2CPP 运行 `SL_JIT=0`，VM 走解释执行无崩溃。
- [ ] WebGL 走 wasm 通道，无 JIT 调用。
- [ ] 设 `SL_JIT=0` 后 `csimple_lang version` / 运行 SL 模块行为正常（解释执行）。
- [ ] Unity 接调试器时确认 JIT 已自动关（`--debug` 规则 3）。
