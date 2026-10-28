# SLang 语言发展规划与优先级建议

> 基于 2026-10-27 对全仓的现状调研（README / PROJECTS.md / AGENTS.md / 未解决问题.txt / target.md / Tensora / Render / 官网 doc 系列），对语言后续发展方向给出的完整评估与优先级排序。
> 版本基线：四端 `0.0.45`（Front / C VM / AllInOne / VSCode）。

---

## 一、现状总评

### 1.1 已具备的能力盘点

| 领域 | 现状 | 成熟度 |
|------|------|--------|
| 语言内核 | 静态类型 / 类 / 继承 / 接口 / 枚举 / 泛型模板 / 类型别名 / attribute 四时点注解 | ✅ 完整 |
| 并发模型 | 协程（spawn/await/yield + Task/Channel）、isolate 隔离岛（跨堆并行 + 端口消息 + 零拷贝转移） | ✅ 完整 |
| 表达能力 | 闭包、内联 lambda、Range、字符串插值、data 动态对象、异常、Float8/Float16 | ✅ 完整 |
| 虚拟机 | C99 VM + JIT（Release 默认开，x86-64）+ GC + TLSF/mimalloc | ✅ 可用，性能持续优化中 |
| 多目标 | SLIR JSON / SLB 二进制（约 JSON 的 2%）/ AOT 导出 LLVM IR `.ll` / WASM | 🔄 AOT 为原型态 |
| 工具链 | 统合宿主 `slang`（编译即运行、内存直传）、LSP 3.17（诊断/补全/悬停/跳转/格式化/重命名）、DAP 调试器（断点/单步/变量树/求值）、VSCode 插件 0.0.45 | ✅ 完整 |
| 标准库 Core | 容器（List/Map/Set/Queue/Stack/LinkedList/Tuple/Channel）、JSON/XML/YAML/TOML/CSV、ByteBuffer/Codec、Lz4、Protobuf、Stream | ✅ 完整 |
| 标准库 Math | 三精度数学（FFI 直调 math_lib.dll）、9 向量 + 6 矩阵值类型、BigNumber/BigDecimal/Factor | ✅ 完整 |
| 标准库 Std | IO（File/Directory/Console）、Net（TCP/UDP/TLS/HTTP/WS/MQTT 协程化）、Sqlite、Redis、Log/Profiling/Trace/Monitor、GZip/Zip、DateTime/Process/Timer | ✅ 完整 |
| 服务框架 | SLang.HttpServer / WebSocketServer：P0–P10（前缀树路由 / `{param}` / multipart 流式上传 / 中间件管道 / SSE / Range / rateLimit / Jwt / OpenAPI + SwaggerUI 自研 / @InstanceAttr 单例） | ✅ 完整，缺真实项目锤炼 |
| 数据库 | SLang.Mysql（FFI 直调，GPL-2.0 静链不随官方包分发）、Sqlite、Redis | ✅ 可用 |
| 跨语言互操作 | FFI（@DllImport / @DllStaticImport）、系统方法下沉、插件系统（csharp_mono / java_hotspot，原生 C DLL 三导出 ABI，AOT 可用） | 🔄 FFI 类型覆盖不全 |
| 官网 | Astro 前端 + 若依 admin（csharp-server .NET 版）+ 完整 doc 设计稿（00–18） | ✅ 框架就绪 |
| 发布流水线 | AOT-only 双平台同发、加固构建（LTO + 反调试）、release-slang.ps1 一键发布、spm 设计稿（doc/18） | ✅ 完整 |

### 1.2 综合判断

**内核成熟度已经很高**，基础设施（编译器 / VM / JIT / 调试器 / IDE 插件 / 发布流水线）大部分自研语言数年都未必齐备。当前真正的短板不在"缺大功能"，而集中在三处：

1. **FFI 类型系统不完整** —— 卡住所有第三方 C 库绑定；
2. **缺少真实项目锤炼** —— 服务框架、数据库层都已就绪但没有一个完整产品级应用验证过它们；
3. **生态地基（spm）未落地** —— 第三方无法便捷分发库，语言无法形成生态循环。

---

## 二、语言内核待完善清单

来源：`SlangAllInOne\SLangCore\test\未解决问题.txt`、`target.md`、排障文档。

| # | 问题 | 现状证据 | 影响范围 | 建议处理时机 |
|---|------|----------|----------|--------------|
| 1 | **FFI 静态绑定参数类型不全** | char / char* / short / ushort / ptr* 等类型未处理；现有匹配机制逐类型手写，扩展成本线性增长 | 所有 C 库绑定（QT / curl / ffmpeg / webview / python） | **P0 立即** |
| 2 | **AOT 的 llvm.struct ↔ VMObject 映射缺失** | hashCode 概念缺失（现为指针 hash，跨边界不可靠）；GC 托管边界未定；MLIR 结构体需携带类 id / 名称 / 模板成员指针等元信息 | AOT 从"能导出 .ll"到"完整原生可执行" | P5 前置设计题 |
| 3 | **Front 进程内重入未根治** | LSP 靠每轮 spawn `lsp-compile` 子进程规避；`ProjectCompile.ResetForNewSession()` 为备用口未启用 | LSP 响应速度、增量编译、未来 IDE/spm 集成 | P4 伴随 |
| 4 | **旧测试用例未迁移** | `SLangCore\test\Other\` 下 NullFastTest / JsonTest / Platform* / InlineLambda* / CoroGCProbe / OOMProbe 等具名用例 CSimpleVMTest 找不到 | 回归覆盖缩水 | P0 伴随（半天量级） |
| 5 | **spm CLI 未落地** | 官网 doc/18 诚实标注"指引形态"，`modules\` 目录与查找链已预留 | 生态循环 | P2 |
| 6 | **Tensora 无 BLAS 支撑** | 纯 SL 扁平 Array<Float32> 实现，行主序，广播已支持 | 只能教学演示，跑不动真实模型 | P6（CPython 插件可短期替代） |
| 7 | **测试广度不足** | 未解决问题.txt 自述"写更多的使用用例测试 cvm 功能点" | 稳定性 | 持续 + CI 兜底 |

---

## 三、发展路线优先级（P0 → P6）

> 总原则：**先用"能用的后端全栈 + 包管理"证明语言实用性，再投入 torch / 渲染这类无法独立变现的超大工程。**
> 优先级判定维度：① 是否为其他项的前置 ② 投入产出比 ③ 是否形成"展示橱窗" ④ 单人可维护性。

---

### P0 · FFI 参数类型扩展 + 匹配机制重构

**定位**：用户计划中 7 项里 5 项（QT / libcurl / ffmpeg / webview / python 插件）的共同前置。

**目标**
- 支持完整的 C 基本类型编解码：char / char* / short / ushort / int / uint / long / ulong / float / double / ptr* / 结构体指针 / 回调函数指针。
- 把"逐类型手写匹配"重构为**签名驱动的通用编解码**。

**制作要点**
1. **类型表驱动**：建立一张 `SL 类型 ↔ C 类型 ↔ marshalling 策略` 的静态映射表（类似 Python ctypes / Dart dart:ffi 的 `StructLayout` 思路），新增类型只改表、不改逻辑。
2. **编解码器分层**：
   - 一层：值拷贝类（int/float 系，直接位模式转换）；
   - 二层：引用类（char* ↔ string：进向拷贝到临时缓冲、出向按编码转换并交 GC 托管；ptr* ↔ Ptr/T 对象）；
   - 三层：复合类（struct 指针：内存布局描述符 + 逐字段 marshal）。
3. **调用约定归一**：x64 前四个参数寄存器规则（Windows RCX/RDX/R8/R9 vs SysV RDI/RSI/RDX/RCX）封装在 VM 侧 FFI 桥（`csimple_lang\src\lib\ffi\`），上层无感。
4. **回调支持**：函数指针参数需要 VM 侧生成 trampoline（把 C 调用转回 VM 方法帧），这是 libcurl（写回调）/ ffmpeg（AVIOContext）绑定的硬前置。
5. **`.slffi.json` 契约升级**：现有 `CLangdll.dll.slffi.json` 模式扩展为完整签名描述，Front 侧做签名校验（类型不匹配编译期报错，而不是运行时崩）。

**验收标准**
- 用纯 C 写一个覆盖全类型的 echo 测试库，SL 侧逐类型断言往返一致；
- 回调：C 库调用 SL 传入的闭包并拿到返回值；
- 后续绑定任何新库不再改 FFI 内核代码。

**工作量**：约 1–2 周专注开发。**伴随任务**：迁移 `test\Other\` 旧用例（半天）。

---

### P1 · 若依系统用 SLang 重写 + 官网完善（最优先大项）

**定位**：吃自己的狗粮（dogfooding）—— 打磨语言最快的手段 + 语言实力的展示橱窗。

**理由**
- **资产已 90% 就绪**：HttpServer P0–P10（路由 / 上传 / 中间件 / 流式 / Jwt / OpenAPI / SwaggerUI）+ Mysql 全绿（`MysqlTest.sl` 31 项断言）+ Sqlite / Redis / Log，正好是完整后端技术栈。
- **暴露真实问题**：若依体量（RBAC 权限、定时任务、代码生成、操作监控、多数据源）会把字符串处理、JSON 深度、ORM 缺口、并发模型全部暴露，每个 bug 都是真实改进清单。
- **官网叙事闭环**："本管理后台由 SLang 编写" + 实测 QPS / 内存数据，比任何宣传文案有效。官网框架已就绪（Astro 前端 + doc 设计稿 00–18），csharp-server 版若依可直接作为移植对照。

**制作要点**
1. **分层推进**（每层都可独立验收）：
   - 阶段 A：登录 / JWT 鉴权 / 用户管理 CRUD（HttpServer + Jwt 已有，纯组装）；
   - 阶段 B：RBAC 三表模型（用户–角色–菜单权限）+ 部门树；
   - 阶段 C：操作日志 / 登录日志（中间件管道已有，挂 AOP 式记录）；
   - 阶段 D：定时任务（Timer + isolate 并行执行）、代码生成器（读表结构生成 .sl 代码——顺带验证 SLang 自举字符串/模板能力）。
2. **持久层先薄后厚**：先手写 SQL + Mysql cursor（现成），跑通后再抽象轻量 query builder；**不要一上来做完整 ORM**。
3. **过程产出反哺语言**：建立"若依发现的缺陷清单"工作流，按 R10 追加到 troubleshooting 分片。
4. **性能基线**：ServerBench M1/M2 矩阵已有（SERVER_DESIGN §25），若依版跑同一矩阵与 csharp-server 版对比，形成官方对比数据。
5. **官网完善**：运行页接入现成 WASM Playground（`csimple_lang\wasm\playground.html`，浏览器写 SL → 编译 → 执行，几乎零成本）；若依系统部署一套做在线 Demo。

**验收标准**
- 若依核心功能（登录 / RBAC / 用户角色菜单管理 / 日志 / 定时任务）全部 SLang 实现；
- 与 csharp-server 版功能对齐、性能对比数据公布；
- 过程中发现的每个语言缺陷有 issue 化记录与修复。

---

### P2 · spm 包管理 MVP

**定位**：生态地基。时机刚好——若依写完正好拆成第一个真实包验证 spm；官网 doc/18 的 P2 期（registry 联动）就等它。

**制作要点**
1. **MVP 命令集**：`spm install <name>` / `spm remove` / `spm list` / `spm publish` / `spm update`（doc/18 草案已有），实现为 `slang spm …` 子命令或独立 spm.exe。
2. **分发通道不建服务端起步**：GitHub 仓库 + raw 索引（`packages.json`）即可，crates.io 早期同模式；官网后管包管理模块（doc §10）后期再接。
3. **`.spkg` 容器**（doc/18 P3 草案提前落一部分）：spm.json（name/version/依赖/平台矩阵）+ `*.module.slb` + 可选 `lib\<平台>\` 原生库——**原生库多平台随包分发**正是 libcurl / ffmpeg 这类绑定的必需形态。
4. **装载链已就绪**：`modules\` 目录 + 查找链 `lib\ → modules\`（PROJECTS.md §4.4）不用动，spm 只做"解包到 modules\ + 依赖递归安装"。
5. **依赖解析**：MVP 用线性解析（无版本 SAT 求解），语义化版本约束先支持精确版本 + `^` 兼容区间。
6. **第一个包**：若依系统（或其拆出的 auth / rbac 子包）+ 官方示例包（doc/18 P2 上线判据）。

**验收标准**：`spm install <官方示例包>` 官网命令块与 CLI 实测一致；若依可整体作为包被安装运行。

---

### P3 · webview 轻量 GUI（替代 QT 作为短期 GUI 方案）

**定位**：用最小成本获得"能做桌面应用"的能力。要的是能力，不是 QT 本身。

**QT 暂缓的理由**：moc 元对象系统、signal/slot、QString/QList 全套类型转换、部署体积——绑定工作量大一个数量级且单人难以维护；且 QT 绑定本质依赖 P0 的 FFI 完成 + clang 自动生成绑定脚手架才可控。

**制作要点**
1. **选型**：webview（单 DLL，EdgeWebView2 / WKWebView / gtk-webkit 三平台后端）或 webview_duktape 变体；P0 完成后 FFI 直调。
2. **架构**：SLang 写后端逻辑 + HTTP/WebSocket 服务（现成）→ HTML/JS 写前端 → webview 壳加载本地页面，SL–JS 双向通信走 WS 或原生 JSBridge 注入。
3. **API 面收敛**：只暴露 `Window.open / setSize / navigate / evalJS / onClose` 十个以内函数，避免重蹈 QT 大而全。
4. **与 spm 联动**：作为第一个带原生库的官方包（`.spkg` 含 `lib\windows\webview.dll`）分发，正好验证 P2 的多平台原生库容器。
5. **演示项目**：一个桌面版"若依管理终端"（复用 P1 后端），形成完整故事线。

**后续 QT 路径预留**：FFI 类型表 + struct 描述符就绪后，写 clang libclang 绑定解析 QT 头文件自动生成绑定脚手架（P4 的 clang 插件正好服务于此）。

---

### P4 · CPython 插件（用生态换时间，替代自研 torch 的短期路径）

**定位**：关键改道——自己写 torch 是数年级工程且生态无法竞争；CPython 互操作 = 直接用 numpy / pytorch / pandas。

**制作要点**
1. **复制已验证模式**：插件机制已跑通两轮（csharp_mono / java_hotspot 均为原生 C DLL 三导出 ABI `sl_frontend_*`，PLUGIN_TEMPLATE.md 为标准模板），CPython 的 C API 比 JVM / Mono 更简单稳定。
2. **三工程结构**：`frontend/`（AtSignLabel 承载 `@python(){}` 内联块）+ `cvm/`（嵌入 CPython：`Py_Initialize` / GIL 管理 / PyObject ↔ SL 值转换）+ `slang/`（ref module 声明）。
3. **值转换边界**（核心难点）：
   - SL int/float/string ↔ PyLong/PyFloat/PyUnicode（简单）；
   - SL Tensor ↔ numpy ndarray（P6 Tensora 落地后走缓冲区协议零拷贝）；
   - GIL 与 SL isolate 的线程模型对齐（isolate 线程进 Python 前必须 `PyGILState_Ensure`）。
4. **内联块形态**：`@python(){ import torch; … }` 编译期由 frontend 段包装为字符串、运行期 cvm 段执行，结果经约定变量回传 SL。
5. **quickjs / node.js 排后**：JS 生态对当前定位增益小；**clang 插件单列**——对普通用户价值低，但对生成 QT / libcurl 绑定脚手架有价值，与 P3/P6 的绑定工作合并做。

**验收标准**：SLang 脚本内 `@python(){}` 调 PyTorch 训练一个小模型并回传指标；GIL 多 isolate 并发调用无死锁。

---

### P5 · 完整 AOT 系统（MLIR / LLVM 全链路）

**定位**：性能敏感场景（渲染 / Tensora 真实跑分 / 嵌入式 ESP32-P4）的基建。JIT 已默认开启，日常够用，故不挡在若依 / spm 之前。

**制作要点**（先定稿三道设计题——均来自未解决问题.txt）：
1. **hashCode 设计**：LLVM 侧生成的对象需有稳定 id 概念；`Object.sl` 增加 `int _hashCode` 还是沿用指针 hash 需定稿——指针 hash 在跨边界（AOT 数据 ↔ VMObject）不可靠。
2. **GC 边界**：AOT 侧对象（如 `sl_aot_skeleton_new_inner` 产物）不进 VM GC 托管、member_data 复用转换类结构——"AOT 内存属 AOT，VM 内存属 VM"的分界线要成文。
3. **MLIR 结构体元信息**：class / data / enum → `llvm.struct` 转换时携带类 id / 名称 / 模板成员指针（Int64）+ 描述字段，使 VM 装配期能反查类型。
4. **里程碑切分**：
   - M1：单文件无依赖工程 → 独立 `.exe`（工具链已在发布包 `bin\`：llc / mlir-opt / mlir-translate）；
   - M2：整库标准库可 AOT（Core 容器 + GC 接口桩）；
   - M3：AOT ↔ VM 混跑（jsonc `AOT / Mix / PureCVM` 三态——未解决问题.txt 已有此规划）。
5. **基准**：BenchMark 套件（Fibonacci / Levenshtein / Mandelbrot / MatrixMul）AOT vs JIT vs 纯 VM 三方数据，进官网。

---

### P6 · 渲染引擎 / SLangQT / Tensora 完整版（长期主线）

**定位**：展示型大工程。等语言稳定 + spm 生态地基 + 若依标杆完成后再全力投入。

**渲染引擎制作要点**
1. **不从零写 OpenGL / Vulkan / DX12**：先绑定 **bgfx 或 sokol**（单头 / 单库、跨三 API、FFI 友好）；Render/ 目录 52 个类型文件（Mesh/Material/Texture/Shader/Camera/Pipeline）正好做上层封装层。
2. **切分三层**：RHI 绑定层（bgfx/sokol FFI）→ 渲染管线层（已有 Pipeline/RenderPass/URP 骨架）→ 场景/UI 层（Camera/Light/RectTransform/Behaviour 已有）。
3. **第一屏里程碑**：软件光栅先行（Ray.sl 已有，Canvas 绘图示例已有）出 2D Demo，再上硬件加速三角形 → 完整 URP 一帧。
4. **SLangQT**：待 P0 FFI + clang 脚手架 + webview 验证 GUI 需求真实存在后再立项。

**Tensora 制作要点**
1. **短期**：CPU 完善版（现有 30 文件：Tensor/Shape/Autograd/Optimizer/Transformer）+ **FFI 绑 OpenBLAS**（P0 完成即可做），matmul 走 `cblas_sgemm`，性能立刻上一个数量级。
2. **中期**：numpy 数组缓冲区协议互通（与 P4 CPython 插件联动，Tensor 底层 ArrayBuffer 直接进 numpy）。
3. **长期**：GPU 后端走 AOT（P5）编译 kernel，或绑定现有推理框架。
4. **定位建议**：教学 / 嵌入式推理优先，训练端短期不与 PyTorch 竞争（P4 已提供逃生通道）。

---

## 四、补充建议（原计划未列，强烈建议纳入）

### 4.1 CI 自动化（最紧急的便宜事）

- **做法**：GitHub Actions 两个 workflow——① push 触发 `build-all.ps1`（VM 双平台 + 标准库 + 用例集编译）；② 运行 `run-tests-win.ps1` / `run-tests-linux.ps1` + 退出码汇总。
- **理由**：单人维护四端 16 个工程 + opcode 逐项对齐（R2）这种脆约束，回归测试是生命线；成本一天，收益覆盖所有后续开发。
- **配套**：把 `test\Other\` 未迁移用例恢复进套件（P0 伴随）。

### 4.2 WASM Playground 上官网（几乎零成本）

- `csimple_lang\wasm\playground.html` 已实现"浏览器写 SL → 服务端编译 → wasm 执行"，接到官网"运行页"（doc/06 已有设计）即成。
- 这是**别人评估语言的第一入口**——无需安装即可跑 Hello World，转化率远高于下载页。

### 4.3 Front 重入根治 + 增量编译

- 启用 `ProjectCompile.ResetForNewSession()` 或彻底清理静态状态（isLoaded / fileParseList / ProcessManager），使 LSP 不再每轮 spawn 子进程。
- 这是 LSP 响应速度、未来 IDE 深度集成、spm 增量编译的共同前置，与 P4 的 IDE 体验投资合并做。

### 4.4 文档站

- md/ 已有 93 篇用户文档，缺统一的在线文档站（官网 doc/14 i18n 方案已设计）。P1 官网完善时用 Astro 顺手挂上即可。

---

## 五、执行顺序总览

```
阶段一（近期，1~2 个月）
  P0 FFI 类型表重构 ──┬──► P3 webview 绑定（GUI 短期方案）
  CI 搭建（伴随）      └──► OpenBLAS 绑定（Tensora 性能急救）

阶段二（1~2 个季度）
  P1 若依系统 SLang 重写 ──► 官网完善 + WASM Playground + 性能对比数据
  P2 spm MVP ──► 若依拆包验证 ──► 官网 P2 registry 期

阶段三（并行推进）
  P4 CPython 插件（ML 能力展示）──► quickjs / clang 脚手架按需
  P5 AOT 三道设计题定稿 ──► M1/M2/M3 里程碑

阶段四（长期主线）
  P6 渲染引擎（bgfx/sokol 绑定起步）／ SLangQT ／ Tensora GPU 后端
  ESP32-P4 移植 + SDK（依赖 P5 AOT 成熟）
```

依赖关系要点：
- **P0 是几乎所有绑定类工作的根前置**；
- **P1 不依赖任何新功能**（技术栈现成），可与 P0 并行；
- **P2 依赖 P1 提供第一个真实包**；
- **P5 依赖三道设计题定稿**，是 P6 性能上限的前置；
- **P4 与 P6 互为逃生通道**（自己写 vs 借生态），先 P4 后 P6 深耕。

---

## 六、风险与原则

| 风险 | 应对 |
|------|------|
| 若依移植暴露大量语言缺陷导致工期失控 | 按阶段 A→D 切分，每阶段独立可验收；缺陷按严重度分级，非阻塞项记录不立即修 |
| 单人维护多线并行失焦 | 严格串行：同一时间只有一个 P 级大项在主线，其余为伴随小项 |
| 自研 torch / 渲染投入无回报 | P4 CPython 插件 + bgfx 绑定作为借力通道，把自研留给长期差异化 |
| 生态冷启动（spm 无包） | 官方带头：若依拆包 + 官方示例包 + webview / OpenBLAS 绑定全走 spm 分发 |
| AOT 设计反复 | 三道设计题（hashCode / GC 边界 / struct 元信息）先出 RFC 定稿再动手，避免返工 |

**三条原则**：
1. 每个大项必须产出"可对外展示的东西"（Demo / 对比数据 / 在线体验）；
2. 每次真实使用暴露的缺陷优先于新功能（dogfooding 优先）；
3. 能借生态的不自研（BLAS / webview / CPython / bgfx），自研火力集中在语言内核与工具链的差异化上。

---

*本文档为规划建议，与 `未解决问题.txt`（原始问题池）、`target.md`（长期愿望池）、官网 `doc/16-开发路线图`（官网侧路线）互补参照。*
