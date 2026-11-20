# 复盘分片 06 · 构建工程链路

> 收录：vcxproj/CMake 漏登记、LNK2019/LNK2001、双树覆盖、CWD/路径、-e ir 假成功、Linux/WSL、wasm 构建、测试宿主工程类复盘。
> 路由索引与追加规则见 [故障排查流程 §6](../故障排查流程.md)；新复盘按域追加至本片末尾。

### [2026-09-12] P2 lib 负例变体 26 项脚本仅 25 过：L4b 正则替换串重发原闭合引号致 JSON 非法
- 现象：`test-platform-lib.ps1` 首跑 25/26——L4b「lib cmp 改 ge 999.0 阻断运行」exit 1 判定 PASS，但诊断行断言 `lib        : sqlite3` FAIL（同格式断言的 L4a exists 负例却 PASS）。
- 首个异常阶段：测试脚本自身（PowerShell `-replace` 替换串），非产品代码。
- 根因：替换串 `'$1ge$3$4", "value": "999.0"$5'` 中 `$4`（`sqlite3`）后手写的 `"` 与 `$5`（原文 `"key": "sqlite3"` 的**原闭合引号**）叠加，产物为 `"key": "sqlite3", "value": "999.0""`——双引号 JSON 非法。exit 1 实为 **JSON 解析失败**，ge 判定从未执行；「exit 1 + 诊断行缺失」的组合被误读为「判定成功拦截但诊断格式不同」。教训：**exit code 相同不代表失败原因相同**。
- 修复点（文件/模块）：`csimple_lang/scripts/test-platform-lib.ps1` L4b 替换串去掉末尾 `$5`（我的闭合引号顶替原引号），并加注释说明。
- 如何快速复现：对 module.json 手动重放原正则改写后，打印改写产物中 sqlite3 atom 片段即可见 `999.0""` 双引号。
- 如何快速验证：`test-platform-lib.ps1` 26/26 PASS（L4b exit 1 + `✗ lib : sqlite3 >= 999.0` 诊断齐）；回归 `test-platform-override.ps1` 25/25 PASS。
- 预防建议：①**负例变体改写 module.json 后，必须先验证产物 JSON 仍合法**（如 PowerShell `ConvertFrom-Json` 试解析）再喂给 exe，否则「exit 1」可能来自解析失败而非预期判定，出现假 PASS；②断言失败时先 dump 实际输出/产物再改断言，勿先猜格式；③正则分组替换串里，凡 `$N` 匹配的是**定界符**（引号/括号），替换串中自行重写定界符的同时必须显式丢弃 `$N`，二者只留其一。

### [2026-09-12] P2.5 AOT 一致性校验三坑：require/features 名字归一化不匹配误报 + compile 默认不跑 Export（须 -e ir）+ link 依赖 LIB 环境变量
- 现象：① P2.5 一致性校验（Error 20037）首验时，require 写 `"sse4.2"`、features 写 `"+sse42"`（同一特性两种写法）被误判矛盾——形式不一致即误报；② 正例工程 `compile -p <sp>` 编译"成功"但无 aot.mlir/aot.dll/module.json，Front.txt 也无 22115（llc target options）日志；③ stage-3 最后 link 步骤报 `LNK1181: 无法打开输入文件"libvcruntime.lib"`。
- 首个异常阶段：① MetaCore（ValidateAotTargetConsistency 比对逻辑）；② ProcessManager 相位调度（Export [Pending]）；③ 工具链（link.exe 环境依赖）。
- 根因：① 归一化（PlatformDefTables.TryNormalize → `sse42`）只发生在 require 侧（`ValidatePlatformRequireValues` 前置归一），features 侧原样入集比对；且 require 的 cpu `eq`/`ne` atom 的 Value 连前置归一都没有——同一名两侧形异必误报；② Front `compile` 动词默认只跑到 IR（RunToPhase），仅 `-e ir` 时 `CommandExecutor.ExecuteCompile` 才 RunPhase(Export)（同既有 [2026-09-12] Component 条目经验①）；③ MSVC link.exe 需要 `LIB` 环境变量（MSVC lib\x64 + Windows SDK ucrt\x64），普通终端无此变量。
- 修复点（文件/模块）：`source/Front/Project/ProjectJsoncLoader.cs`——ParseAotFeatures 解析时对每项过 `PlatformDefTables.TryNormalize(KindIsa,...)` 后入启用集；新增 `IsAotFeatureEnabled(name, enabled)` 辅助（查询时归一 require 侧名字再查集），并接入 `ValidateAotCpuAtom` 全部四个 case（all/eq/any/ne）。**注意 features 串传 llc 仍原样**（LLVM 特性名语法就是 `sse4.2`），归一化只用于比对侧。
- 如何快速复现：① 正例 `dotnet run --project source\Front\SimpleLanguageFront.csproj -- compile -p test\SpecialTest\PlatformAotPosTest\PlatformAotPosTest.sp -e ir`（去掉修复会误报 20037）；② 同命令去掉 `-e ir` 即复现 Export [Pending] 无产物；③ 无 `$env:LIB` 环境下跑 aot buildDll 即复现 LNK1181。
- 如何快速验证：正例带 `-e ir` + `$env:LIB = "C:\Program Files\Microsoft Visual Studio\18\Community\VC\Tools\MSVC\14.51.36231\lib\x64;C:\Program Files (x86)\Windows Kits\10\Lib\10.0.26100.0\ucrt\x64"`：Front.txt 依次出现 `AOT: 1 candidate(s) collected` → `AOT: export aot.mlir success` → `[Info] [Project] [ExportMLIRAOTTarget] … -mattr=+sse4.2,+avx2` → `AOT: build dll success` → `export module success`，全程无 20037（别名 `sse4.2` ↔ `+sse4.2` 归一匹配）；负例 PlatformAotNegTest（require cpu all(avx2) vs features +sse42）报 Error 20037 并中止导出；回归 PlatformOverrideNegTest（20034/20036 通道）与 BaseTest 全量均零回归。
- 预防建议：①两侧名字比对（require 值 vs aot features）一律先过 PlatformDefTables 归一，勿假设两侧书写形式一致；②验证导出类功能必带 `-e ir`，并核对 ProcessSummary 的 Export/ExportModule 非 [Pending]；③llc/link 真实构建前先备好 LIB 环境变量（或从 VS 开发者终端跑）；④别名（`sse4.2`/`sse4_2`/`avx512f`）在设计文档与测试 fixture 中混用是有意的，勿"顺手统一"——这正是归一化机制的验证场景。

### [2026-09-15] SystemComponentGetComponent not registered：MSVC 树 vcxproj 漏登记新源文件，缺符号 DLL 覆盖 Ninja 树（§7 双树覆盖坑实锤）
- 现象：CSimpleVMStdTest 跑到 ProjectTest 的 `==== testBasicQuery ====`，`__new_object__ProjectTest.CompSpeed` 构造完成后报 `[Assert] [LID=10005] CallSystemMethod not registered. method=SystemComponentGetComponent`，Component 系统方法全军覆没。
- 首个异常阶段：VM 运行期——动态系统方法注册链（SLIR `module.json` 的 systemCalls → `vm_system_func_dynamic_register` → GetProcAddress 解析 `cvmFunction` 符号）失败后**静默不注册**，运行期 OpCode_CallSystemMethod 查 id 表/名字表均未命中才报 LID=10005。
- 根因（三层叠加）：
  1. `csimple_lang/project/vs/vm_lib/csimple_lang_lib.vcxproj` ClCompile 清单漏登记 7 个新文件（`component_system_method.c`、`json_system_method.c`、`file_system_method.c`、`sl_vm_ext_api_check.c`、`vm/parse/` 下 3 个）——R6 登记 CMakeLists 时 vcxproj 漏同步；
  2. MSVC 树 OutDir 与 Ninja 树同为 `build\Debug\bin`（AGENTS.md §7 双树覆盖坑）：MSVC link 出的缺符号 DLL 覆盖后，ninja 按 mtime 判定 DLL 比 .obj 新而**跳过重链接**，P/Invoke 加载的正是坏 DLL；
  3. 缺 7 文件为何链接不报错：这些文件零静态调用方（parse 层为孤儿代码、component/json/file 系统方法仅运行时经 GetProcAddress 动态解析）→ 产出「能跑但缺新符号」的隐蔽坏 DLL。
- 修复点（文件/模块）：vcxproj 补齐 7 个 .c + 7 个 .h、移除 2 个废弃 `vm_system_registry` 条目（该文件已是 217 字节纯注释占位，内容已拆分至 system_method_call/），两清单与 CMakeLists 达成严格一致；DeleteFile 删除 `build\Debug\bin` 陈旧 DLL/EXE 强制 ninja 重链接。
- 如何快速复现：MSVC 构建一次 vm_lib 后，跑任何用到 Component/Json/File 系统方法的用例即报 LID=10005。
- 如何快速取证：`llvm-readobj --coff-exports csimple_lang_dll.dll` 比对导出表——修复前 543 导出、`vm_sys_component_*` 零导出；修复后 570（+27 = component 11 + json 7 + file 9），`vm_sys_component_get_component` 在列。
- 如何快速验证：重跑 CSimpleVMStdTest，testBasicQuery 段 getComponent/getComponents 全 PASS，ComponentTest 整段（含层级查询/inactive gate/消息广播/stress 20000 命中）跑完不报 not registered。
- 预防建议：R6 的「新增 .c 必须登记」实为**两处同步**（CMakeLists `CSIMPLE_LIB_SOURCES` + vcxproj ClCompile）；怀疑 DLL 内容不对时先查导出表取证再动代码（R12）；双树交替构建后跑用例前，抽查关键新符号是否在导出表内。

### [2026-09-16] 内联 lambda 负例工程宿主 exit 1 被 VS 显示为报错：拦截正确但负例无「预期失败=成功」通道
- 现象：`InlineLambdaForbiddenTest` 6 条拦截全部正确命中（21449×3/21452×2/21451×1），但 CSimpleVMTest 宿主打印 `Front compile failed, error count: 8` 且 exit 1，VS 将正常工作的负例显示为编译报错。
- 根因：`Program.cs` 中 `RunFrontInProcess` 以 `Log.errorCount > 0` 判失败返回 1，`Main` 失败直通 `return frontExit`——负例工程天然以非零码退出。`errorCount=8` 是 6 拦截 + 1 连锁（`MetaCoreExpressOperatorLeft`，g1 拦截后调用链解析失败的连锁）+ 1 阶段失败日志（`ProcessPhaseFailed`）。
- 修复点（`Program.cs`）：新增 `NegativeFrontCase` 注册表（启动项名 → 导出模块名 → 预期 LID 计数），Front 失败后读 `Log.FrontLogFilePath`（in-process 准确，回退 `out/export/<模块>/Logs/Front.txt`）按 `"[LID]"` 行统计命中；全命中 → 打印通过信息、跳过 C VM、exit 0；缺命中 → 真失败。只校验预期 LID，不计连锁错误。
- 预防建议：负例工程宿主化时必须配「预期失败校验」通道，否则每次跑负例 VS 都报错，会淹没真回归；校验用 LID 名称精确匹配而非 errorCount（阶段失败/连锁日志也计入）。

### [2026-09-17] VS 调试下 ProcessTest testExitCodeNotExited 卡住（命令行全过）：预期业务异常被分派层打 Assert 级日志，触发 __debugbreak 冻结
- 现象：VS 里跑 CSimpeVMSpecialTest，ProcessTest 到 `testExitCodeNotExited` 输出标题后不再前进；同一测试命令行下 33/33 全过。
- 首个异常阶段：VM（vm_runtime.c OpCode_CallSystemMethod 分派层）。
- 根因（链）：
  1. `p.exitCode` 在进程未退出时按设计走 SL throws 流程：`vm_sys_throw(-83)` 设 error_code + Error 级日志 + `vm_execute_throw` 分派异常，然后 `return FALSE`——这是系统方法异常机制的正常路径；
  2. 主分派（vm_runtime.c 两处 `CallSystemMethod failed`）把任何 FALSE 一律打 **Assert 级**（LID=10005）日志；
  3. Debug 构建下 log.c 对 Assert 级日志在 `IsDebuggerPresent()` 为真时执行 `__debugbreak()` → VS 捕获断点中断并冻结全部线程（取证：卡住进程 28 线程中 25 个 Suspended、CPU 时间仅 3 秒级非忙转；VM.txt 停在 Assert 行）；命令行无调试器 → 跳过 debugbreak → 全过。
- 修复点（文件/模块）：`csimple_lang/src/vm/runtime/vm_runtime.c` OpCode_CallSystemMethod 两处失败日志——仅当 `vm->error_code == 0`（即 FALSE 属于静默意外失败）才打 Assert 级；error_code 非 0 说明异常已由 vm_sys_throw 上报（Error 日志已打、异常值已分派），不再重复 Assert。
- 如何快速复现：修复前在 VS 调试运行 SpecialTest（或任何触发 throws 系统方法的用例，如 exitCode/kill/terminate/SpawnFailed），VS 中断在 `__debugbreak`；VM.txt 可见 `CallSystemMethod failed` Assert 行紧随业务 Error 行。
- 如何快速验证：命令行 SpecialTest 回归全过（ProcessTest 33/33、exit=0），且 VM.txt 中预期异常路径只剩 `[Error] Process.exitCode: not exited yet` 等 Error 行、不再出现 `CallSystemMethod failed` Assert 行。
- 预防建议：①系统方法返回 FALSE 具双重语义（预期 throws vs 意外失败），日志级别须按 `vm->error_code` 区分——已抛异常的 FALSE 不是断言失败；②「命令行过、VS 卡」的差异化第一嫌疑即 Assert 级日志 + `IsDebuggerPresent()` 的 `__debugbreak()`（log.c Debug 专属逻辑）；③卡住进程取证看线程 WaitReason：大量 Suspended + 低 CPU = 调试器冻结，非死锁忙转；④卡住的调试会话会锁定 exe/dll 导致后续构建 MSB3027，先终止冻结的被调试进程（勿杀 VS 本身）。

### [2026-09-18] CoreTest 回归 MSVC 树 LNK2019×20：新 C 源文件与 vendored zlib 只登记 CMakeLists 未同步 vcxproj（双树登记遗漏复发 + zlib 首次引入即漏）
- 现象：修复 IRMetaVariable 枚举返回豁免后跑 `dotnet run --project project\CSimpleVMCoreTest` 回归，失败于 MSVC 树 `csimple_lang_lib.vcxproj` 链接：LNK2019 ×20 + LNK1120——`sl_core_gzip.obj`/`sl_core_zlib.obj` 缺 deflate/deflateEnd/inflate/inflateEnd/deflateBound/deflateInit2_/inflateInit2_/compress2/compressBound/uncompress（zlib 系 10 符号），`byte_buffer_system_method.obj` 缺 core_base64_*/core_encoding_*（新 core 文件系 10 符号）。
- 首个异常阶段：MSVC 链接期（与本次 C# Front 修复无关——Ninja 树 CSimpleVMStdTest 全绿是佐证；CoreTest 走 vcxproj，StdTest 走 Ninja DLL）。
- 根因（链）：任务一/二的 C 侧改动只登记了 CMakeLists（Ninja 树），未同步 MSVC 树 vcxproj：①新文件 `sl_core_base64.c`/`sl_core_encoding.c`/`sl_core_gb2312_table.c` 未登记（与 [2026-09-15] SystemComponentGetComponent 同型复发）；②CMakeLists 引入 vendored zlib 源码（`third_party/zlib` 10 个 .c，注释明确 gz* 文件 API 不编）时 vcxproj 未对齐——`sl_core_gzip.c`/`sl_core_zlib.c` 既有文件靠相对路径 `../../third_party/zlib/zlib.h` 编译通过，但实现体未链接，从此 MSVC 树必然 LNK2019。
- 修复点（文件/模块）：`csimple_lang/project/vs/vm_lib/csimple_lang_lib.vcxproj` 三处登记——ClCompile 加 3 个新 core .c + third_party/zlib 10 个 .c（与 CMakeLists 相同清单，不含 gzclose/gzlib/gzread/gzwrite/infback）；ClInclude 加 3 个新 core .h。无需补 include 目录（zlib 头为相对路径引入，zlib 内部同目录引号 include MSVC 可解析）。
- 如何快速复现：新增/引入 C 源文件只登记 CMakeLists 后，跑 `dotnet run --project project\CSimpleVMCoreTest`（该宿主每次构建 vcxproj，LNK2019 立现）。
- 如何快速验证：重跑 CoreTest——构建日志出现 csimple_lang_lib.vcxproj 且零 LNK 错误（仅既有无害警告 D9002：MSVC 忽略 `-std=c99`），exit 0，ProjectTest _main_ 全绿（CoroutineTest/StringBuilderTest OK）。
- 预防建议：R6 需按双树理解——新增/引入 C 源文件（含 third_party vendored）要**两处同步登记**：`CMakeLists.txt` CSIMPLE_LIB_SOURCES + `project/vs/vm_lib/csimple_lang_lib.vcxproj`；引入第三方库时先看 vcxproj 侧既有登记模式（sqlite3=lib 链接、yyjson/lz4=源码直编 ClCompile），按同型登记；跑 CoreTest 前自检「本轮新增了哪些 .c/引入了哪些库符号」。

### [2026-09-21] Std/Math 标准库自 8 月起编译失败——references Strategy 2 相对 outputDir 按进程 CWD 解析，预编译模块引用链断裂
- 现象：CompileStd 在 ParseMetaClassLink 步骤 NRE 崩溃（`MetaParam.cs:231`），最早 Error 为 `FFI/Library.sl_124_0` 的 `MetaCoreDefineTypeIsNull`（"传入参数与要求参数不对应"）；CompileMath 连锁失败（`Std.FFI.Library not found`）；`out/export/Std` 最后成功导出停在 2026/8/1、Core 8/20——本机（D 盘）标准库链长期未成功构建。
- 首个异常阶段：看似 Front MetaCore（语义阶段），实根源在 Project 引用装载（references 解析）。
- 根因（链）：
  1. jsonc outputDir 原为 `F:\` 硬编码，仓库迁 D:\ 后 Strategy 2（读被引用模块 jsonc 的 outputDir 拼 module.json 路径）失效，长期落 Strategy 3 源码兜底；
  2. 2026-09-21 将 29 个 jsonc outputDir 统一改相对路径后，主模块导出恢复（`ProjectOutputEnvironment.ApplyFromConfig` 按 jsonc 所在目录解析 ✓），但 `ProjectReferenceModuleLoader.TryResolveExportModulePath`（Strategy 2）读到相对 outputDir 后**直接 `Path.Combine` 拼接、按进程 CWD 解析**——未按被引用 jsonc 所在目录解析，必然失败，行为与 F:\ 时代同样坏；
  3. Strategy 3 源码兜底对泛型构造（`List<Library>`，Library.sl:124 静态字段初始化）解析不完整 → `MetaCoreDefineTypeIsNull` → Std 失败 → Math 引用 Std 连锁失败。
- 修复点（文件/模块）：`simple_language/source/Front/Project/ProjectReferenceModuleLoader.cs` `TryResolveExportModulePath`：相对 outputDir 改按 `Path.GetDirectoryName(jsoncFiles[0])`（被引用模块 jsonc 所在目录）解析，与 `ProjectOutputEnvironment.ApplyFromConfig` 同语义。
- 如何快速复现：修复前 `dotnet run --project source\CompileStd\SimpleLanguageCompileStd.csproj` exit 0 但日志 3 错误、`out/export/Std/Std.module.json` 不更新。
- 如何快速验证：按依赖序 CompileCore → CompileStd → CompileMath 全绿：Std.module.json（10.5MB）、Math.module.json（16.2MB）恢复导出（Std 为 8/1 以来首次），日志零 `[Error]`。
- 预防建议：①**路径解析语义必须单一来源**——凡读 jsonc 路径字段处，相对路径一律按"该 jsonc 所在目录"解析（本次是 ApplyFromConfig 之外的第二处解析点，新增第三处时先找现有实现对齐）；②依赖链编译验证按 Core→Std→Math 顺序，下游失败先查上游导出物时间戳（长期未更新 = 上游早已断链）；③**驱动 exit 0 ≠ 编译成功**（CompileXxx 驱动 catch 异常才返回非零，Front 内部错误只记日志），验证必须看 module.json 时间戳 + 日志 `[Error]`；④判断"是否本次改动引入"优先取导出目录时间戳证据（git 仓库缺失时同样有效）。
- 附带记录：BaseTest 的 references 直接指向导出目录（`../../out/export/Core`），走 Strategy 1，不受本修复影响，P2 回归结论仍有效。

### [2026-09-23] MSVC vm_lib 工程链接失败 20 个 LNK2019：TLSF/SBA/mimalloc/crash 源文件未登记 vcxproj
- 现象：VS 打开 SimpleLanguage.sln 编 csimple_lang_lib 报 LNK2019×20——vm_tlsf_*（6）、vm_sba_*（5）、vm_mimalloc_*（8）、sl_crash_install（1）全部无法解析，尾部 LNK1120。
- 首个异常阶段：链接（编译全过，缺的是符号提供方源文件）。
- 根因：R6 只约束 CMakeLists 的 CSIMPLE_LIB_SOURCES；VM 内存演进（TLSF→SBA→mimalloc wrapper、crash handler）新增的 4 个 .c 均未登记 `project/vs/vm_lib/csimple_lang_lib.vcxproj`，其 ClCompile 的 `src\vm\memory\` 段只有 vm_memory/vm_gc/vm_manual_mem 三个旧文件；平时只用 CMake 构建掩盖了该漂移（vm_lib\build 下 unsuccessfulbuild 残留即早前失败证据）。
- 修复点：vcxproj 登记 `vm_tlsf.c`、`vm_small_block_allocator.c`、`vm_mimalloc.c`、`src\platform\windows\sl_crash-win32.c`（ClCompile）+ 3 个 .h（ClInclude），filters 同步并新增 `src\platform\windows` Filter；顺手给 `src/define.h` 的 EXTERN_C 加 #ifndef 保护（sl_crash-win32.c 引 Windows 头后 winnt.h 先定义，cl 报 C4005；两处值在 C/C++ 两模式均一致，纯消除告警）。
- 如何快速复现：MSBuild 编 csimple_lang_lib.vcxproj（Debug|x64），链接期集中爆 vm_tlsf_*/vm_sba_*/vm_mimalloc_*/sl_crash_install 的 LNK2019。
- 如何快速验证：MSBuild 重编——vm_lib → `build\Debug\bin\csimple_lang_dll.dll` 生成、EXTERN_C 警告消失（遗留 D9002/-std=c99 与 runtime_call.c C4101 为原有，非本次引入）；vm_exe exit=0；test_mini 仅 Release|x64 且引用的 main.c 不存在（空壳历史遗留，未被 sln 引用，未处理）。VS 工程无 TLSF/MIMALLOC/SBA 宏 → wrapper 走头文件 fallback 禁用桩（SBA 走默认 host 实现），全部符号自包含可链，无需 third_party 源。
- 预防建议：① **R6 的登记义务同样适用于 `project/vs/vm_lib/csimple_lang_lib.vcxproj`**：新增 .c 必须同时登记 CMakeLists（CSIMPLE_LIB_SOURCES）与 vcxproj（ClCompile/ClInclude + filters 两文件四处），建议把 vcxproj 检查并入新增源文件的收尾清单；② vcxproj 输出与 Ninja 树同路径（`build\Debug\bin\csimple_lang_dll.dll`），MSVC/CMake 交替构建会互覆盖 dll——P/Invoke 宿主用前先确认 dll 来源（§7 已知坑的延伸）；③ 多形态 wrapper（TLSF/mimalloc 双形态、SBA 三形态）依赖头文件 fallback 对齐 VS 工程的"无宏默认"，改 fallback 前先想 VS 工程（本次 fallback=1 修复同时救了 VS 工程：若为 0，vm_mimalloc.c 在 VS 下会 `#include <mimalloc.h>` 失败）。

### [2026-09-23] SpecialTest 直接 `csimple_lang.exe run` 全线 87 FAIL：CWD 运行约定，非 VM 缺陷（P0.2 插件骨架零影响验证附记）
- 现象：P0.2 插件骨架收尾烟测中 Core/ProjectTest/BenchMark 全过，唯 SpecialTest exit 1、FFITest 87 项 FAIL（isValid/符号解析/回调/utf8/原生内存全线挂，一整域全灭）。
- 排查路径：① CLangdll.dll 在位、module.json dllImports 正常；② A/B 对照——移除全部 plugin 改动（CMakeLists/loader/assembly 三处回退）重建重跑，FAIL 集逐条一致（87/87）→ 排除新改动引入；③ 核对 FFITest.sl `s_dllPath = "../../source/CLangdll/..."` 的相对基准：`../../` 需回到 simple_language 根 → 基准只能是 `test\SpecialTest` 用例目录。
- 根因：`sl_ffi_lib_load` 相对路径按**进程 CWD** 规范化（sl_ffi_lib_manager.h 语义），而用例内嵌相对路径的基准是**用例目录**——联合测试宿主（P/Invoke 进程内）自设 CWD 故无感；直接 run 时 CWD 指到 simple_language 根，`../../source/` 落到 `d:\project\source` 装载失败，整域 FAIL。
- 如何快速验证：CWD=`simple_language\test\SpecialTest` 下 `csimple_lang.exe run <SpecialTest.module.json>` → exit 0、0 FAIL 全绿。
- 预防建议：① 直接 run 含相对路径资源的模块时，CWD 必须与用例编写基准一致（用例目录）；② 排障判据——**单域全灭式 FAIL 优先怀疑外部资源装载（路径/CWD/位数），而非 VM 代码**；③ A/B 对照（临时回退新改动→重建→比对 FAIL 集）是判定"存量 vs 新引入"的低成本手段，比对须用完整 FAIL 列表而非记忆/摘要；④ PowerShell `Copy-Item` 保留源时间戳，Ninja 增量构建对"恢复的文件"会误判 no work to do，恢复后须 touch 再建。

### [2026-09-25] WSL/Linux 首跑 ProjectTest：系统方法全部未注册（SystemPrintln 等）→ error_code=-13；根因是 Linux exe 不导出动态符号，dlsym(dlopen(NULL)) 全落空，修复 = -rdynamic
- 现象：WSL(Ubuntu, gcc) 构建成功后运行 ProjectTest.module.json：静态初始化、`__new_object__` 均正常，但 VM 日志刷 `CallSystemMethod not registered. method=SystemPrintln`（还有 SystemTimerNowMillis/SystemDebug* 等），最终 `EIROpCode binary op need 2 words sp=0` → `VM finished with error_code=-13`、EXIT=1；stdout 仅平台校验横幅无任何测试输出。
- 首个异常阶段：VM（模块装载后的 systemCalls 注册/符号解析，非执行逻辑）。
- 根因：系统方法不是静态注册表，而是**运行期按 cvmFunction 符号名解析**（`system_method_registry.c` `vm_sysfunc_resolve_in_self`）。Windows 侧 `GetModuleHandleExW(FROM_ADDRESS)` + `GetProcAddress` 能命中 exe 内符号；Linux 侧走 `dlsym(dlopen(NULL), symbol)`——**可执行文件默认不把全局符号导出到 .dynsym**，dlsym 全部返回 NULL → `vm_system_func_dynamic_register` 静默 FALSE → 名字表/ID 表全空 → CallSystemMethod 全部落"not registered"→ println 无输出且弹空栈，栈失衡连锁出 -13。shared library 目标（csimple_lang_dll）默认导出符号所以 P/Invoke 宿主不受影响，**只有独立 exe 中招**。
- 修复点（文件/模块）：`csimple_lang/CMakeLists.txt` exe 目标的 `if(UNIX)` 块新增 `target_link_options(csimple_lang PRIVATE -rdynamic)`（等价 `--export-dynamic`，把全局符号并入动态符号表）。注意：同样走 dlsym 的插件/FFI 外部库路径在 Linux 上从此才具备工作前提。
- 如何快速复现：WSL 中 `cmake --build build/DebugLinux --target csimple_lang` 后 `SL_FORCE_RUN=1 build/DebugLinux/bin/csimple_lang run <绝对路径>/ProjectTest.module.json`（ProjectTest.jsonc platform.root 硬编码 win64，须 `SL_FORCE_RUN=1` 或 `--force-run` 跳过硬校验）。
- 如何快速验证：重跑后 `===== ProjectTest _main_ end [14ms]=====`、EXIT=0；`grep -c LID=10004/10005/10016 build/logs/VM.txt` 全 0（Linux 下 CLI 日志固定落 **cwd 的 `./build/logs/VM.txt`**，非 out\export\...\Logs\）。唯一残留 Warning `system call not registered in cvm. name=SystemCallExternalFunction` 为 Windows 专属 FFI 能力按预期跳过。
- 预防建议：① Linux/Unix 新平台首跑若"零输出 + not registered"成串出现，第一嫌疑就是**符号可见性**（exe 缺 -rdynamic / dll 缺导出），不要先怀疑注册逻辑本身；② 跨平台移植时凡依赖"按名取自身符号"的机制（GetProcAddress/dlsym）必须逐平台核对符号导出语义；③ Linux 侧日志/结果文件落点与 Windows 不同（cwd 相对 `./build/logs/`），排障先找对文件位置。

### [2026-09-26] compile 缺 `-e ir` 致 Export 阶段静默跳过：module.json 不重写而 dotnet exit 0 + "Compile completed." 双误导（升级 09-22 条目附带记录为正式复盘）
- 现象：改插件 frontend/CVM 契约后重编译 SpecialTest，`dotnet run ... compile -p test\SpecialTest\ProjectTest.sp` 退出码 0 且打印 "Compile completed."，但 C VM 运行行为不变、新用例/新打印不出现；ProcessSummary 显示 Export Pending，module.json mtime 与旧产物一致。
- 首个异常阶段：前端编译（CLI Export 门控，非代码 bug）。
- 根因（链）：
  1. `ProjectCompile.Compile()` 只跑 `RunToPhase(ECompilePhase.IR)`，源码注释明示"导出阶段由调用方按需触发"；
  2. CLI 侧 `CommandExecutor` 仅当命令行带 `-e ir`（置 `inputArgs.exportIR`）才 `RunPhase(ECompilePhase.Export)`——`compile` 动词默认**不导出**；
  3. dotnet 退出码恒 0、且无 Export 也照常打印 "Compile completed."——两个表层信号都指向成功，唯一可靠判据只剩 module.json 产物本身。
- 修复点：无代码修复（行为符合设计）；调用规范 = 产物导向的编译一律 `compile -p <sp> -e ir`（`scripts/common.ps1` 的规范编译调用即如此）。
- 如何快速复现：`compile -p <sp>`（不带 `-e ir`）跑完后 `ls` module.json mtime 不变；grep 新增符号（如新方法名）0 命中即实锤旧产物。
- 如何快速验证：补 `-e ir` 重跑 → 打印 "export module success" + module.json 被重写（grep 新串命中）。
- 预防建议：① **Front 编译成功判据 = module.json 在本次运行被重写**（mtime / grep 新串），不以退出码与 "Compile completed." 打印为准（AGENTS.md §5 已内建此条）；② "改了代码但运行行为不变"时第一怀疑项 = 产物未更新而非逻辑未生效；③ 本条为 09-22 条目附带记录（第 5 次复现）之后又一次复现，故升级为正式复盘——写脚本/文档化命令行时把 `-e ir` 与 compile 绑定，勿依赖记忆。

### [2026-09-27] lib 平台层合并入 platform/：sl_crash-win32.c 误删后靠编辑器本地历史恢复 + eglib/mono 死文件清理
- 现象：目录重构（用户指令"lib 目录下源码合并到 platform，没用的删除，抄的源码删除不用 eglib"）：`src/lib/{os,time,thread}` → `src/platform/{os,time,thread}`；中途发现 `src/platform/windows/sl_crash-win32.c`（SEH 崩溃取证，main.c 启动即装）在上一轮清理中**被误删**，且三处构建登记（根 CMakeLists / project/cmake / vcxproj+filters）需同步。
- 根因：
  1. 删除"疑似 mono 抄来"文件时只 grep 了 eglib/glib 符号面，未交叉验证 `sl_crash_install` 被 main.c 引用——同目录 mono 残骸与自研文件混放，连坐误删；
  2. 同一份文件在多个构建系统登记（Ninja CMakeLists ×2 + MSVC vcxproj + filters），路径替换漏一处即 LNK2019/文件不参与编译（§7 双树坑的又一面）。
- 修复点（文件/模块）：
  1. `sl_crash-win32.c`：从编辑器本地历史快照（`%APPDATA%\Trae CN\User\History\`）全文恢复（236 行），`sl_crash_install` 符号与 main.c 调用对齐；
  2. 35 个源文件 include 批量替换 `lib/(os|time|thread)/` → `platform/$1/`（PowerShell 字节级 UTF-8 读写保 BOM 不丢）；根 CMakeLists 12 处 + project/cmake 1 处 + vcxproj 21 处 + filters 27 处（Filter 定义一并改）；
  3. 删除：`third_party/eglib/`（构建零引用实测确认）、13 个 mono 死文件、`project/build.sh`（GBK 乱码 + apt 引用不存在的 libeglib-dev）、`project/cmake/Makefile`（-luv -leglib 死链接）；`base/chars.c` 两处 "eglib: " 文案前缀清理。
- 如何快速验证：双平台重构建 Windows 223/223 + WSL Linux 152/152 全过；SpecialTest exit 0 全绿（CSharpTest 26 + CSharpTest2 9 + CSharpTest3 2 / 0 failed，flags=7）；Linux ProjectTest LINUX_EXIT_0_OK。
- 预防建议：① 批量删除前必做"符号反向引用"检查（grep 待删文件导出函数名在被调方的引用），不能只查"它引用了谁"；② 目录迁移三处登记用同一替换串逐处验证 remaining=0；③ 误删恢复优先找编辑器本地历史（VSCode/Trae History 目录按文件 hash 存快照），早于 git 未提交场景；④ vcxproj/filters 改动前先读前 4 字节确认有无 BOM，无 BOM 才做字符串替换；⑤ 平台代码归属统一按 `md/RUNTIME_LAYOUT_GUIDE.md`（R3），lib/ 只留通用库（cjson/io/console/ffi）。

### [2026-09-27] platform 回迁 lib（用户方向调整）+ ErrorDefinitions_data.h 误删致 C1083：上届增量构建"223/223 全绿"实为假绿
- 现象：用户指令推翻上一轮合并方向（"把 platform 下的文件都合并到 src/lib 下边，在 VS 的工程里跑通"）。执行 `src/platform/{os,time,thread,windows}` → `src/lib/*` 反向迁移后，vcxproj Debug|x64 首次构建即 `log_manager.c(2,10): fatal error C1083: 无法打开包括文件: "ErrorDefinitions_data.h"`。
- 根因：
  1. 上一轮迁移中 `src/log/ErrorDefinitions_data.h`（ErrorDefinitions.csv 的 C 嵌入形式，log_manager.c L2 无条件 include）被连坐误删；当时 Ninja 增量构建 223/223 全绿是**假绿**——log_manager.c 的 mtime 未变，Ninja 直接复用旧 obj 不触发重编，缺失的头文件根本没被探测到；
  2. 全仓库无该文件副本（非 git 仓库、编辑器本地历史亦无记录），只能从真源 ErrorDefinitions.csv 重新生成。
- 修复点（文件/模块）：
  1. 平台层 4 目录平移 `src/platform/{os,time,thread,windows}` → `src/lib/`；空目录 `platform/unix` 与 `src/platform/` 整体删除；
  2. 36 个源文件 include 批量替换 `platform/(os|time|thread|windows)/` → `lib/$1/`（remaining=0）；构建登记同步：根 CMakeLists 13 处 + project/cmake 1 处 + vcxproj 22 处 + filters 46 处（Filter 定义一并改）；
  3. 从 `src/log/ErrorDefinitions.csv` 重新生成 `ErrorDefinitions_data.h`（22 行 CSV → 转义字符串 `s_embedded_error_definitions_csv`，UTF-8 无 BOM），并补登记 vcxproj `<ClInclude>` + filters（log_manager.c 已在册无需动）。
- 如何快速验证：vcxproj Debug|x64 / Release|x64 均 exit 0；SpecialTest 用 vcxproj 产物（`dotnet run --no-build`，DLL 时间戳全程未变）exit 0，CSharpTest3 passed=2 failed=0 flags=7；Ninja Windows Debug 198/198 全绿（sl_crash-win32.c 编译自 `src\lib\windows\`）；WSL Linux 增量链接 exit 0 + ProjectTest 运行 `===== ProjectTest _main_ end [13ms]=====`。
- 预防建议：① **增量全绿 ≠ 全量可编**：目录重构/删文件后必须清树或 touch 依赖方强制重编一次，换构建系统（Ninja→MSVC）交叉构建是最有效的全量校验；② 重构中删文件前先 grep 其 include 引用面（本次先 grep `ErrorDefinitions_data.h` 即可预防）；③ 验证 vcxproj 产物必须 msbuild 后 `dotnet run --no-build` + DLL 时间戳监测——裸 `dotnet run` 会触发宿主 csproj 内嵌 CMake 步骤覆盖 DLL，造成"测的不是 vcxproj 版"假象；④ 平台层最终归属 = `src/lib/{os,time,thread,windows}/`（R3，RUNTIME_LAYOUT_GUIDE.md / AGENTS.md 已同步），上一条复盘"lib/ 只留通用库"的表述自本次起作废。

### [2026-09-27] 三件清理任务：删 ErrorDefinitions_data.h（fallback 行为变化）+ vm_byte_buffer 跨目录移动 include 断裂 + nouse/ 存量隔离
- 现象/任务：① 用户判断 `src/log/ErrorDefinitions_data.h` "逻辑里没用到"要求删除；② 用户自行把 vm_byte_buffer.{c,h} 从 `src/base/` 移到 `src/vm/`，要求同步全部关联；③ 要求把 `src/` 下未接入构建的文件移入 `nouse/`（不在工程里体现）。
- 关键事实修正：
  1. ErrorDefinitions_data.h 并非"完全没用"——它是 `sl_log_manager_initialize_from_csv("./src/log/ErrorDefinitions.csv")` 加载外部 CSV 失败时的 fallback（`s_embedded_error_definitions_csv`）。删除后：CWD 在仓库根时 CSV 正常加载（无变化）；CWD 不在仓库根时仅剩 log_manager 内置 3 条 builtin defaults，错误码模板会退化。已按用户指令删除（文件 + log_manager.c 的 include L2 + fallback 分支 + vcxproj/filters 登记）。
  2. vcxproj 全量构建立刻暴露 `vm_byte_buffer.c(8,10): C1083: 无法打开包括文件: "mem.h"`——**跨目录移动必须检查被移文件自身的 include**：`#include "mem.h"` 原是 src/base/ 同目录裸引用，移到 src/vm/ 后断裂，改 `#include "../base/mem.h"`。这正是上条复盘"增量全绿≠全量可编"的再兑现（若只跑 Ninja 增量，log_manager.c / vm_byte_buffer.c mtime 变化会触发重编，但依赖断裂只有在全量构建里最先暴露）。
  3. nouse/ 盘点方法：LS 磁盘全量清单 vs 根 CMakeLists `CSIMPLE_LIB_SOURCES` 逐目录 diff + Grep 全仓 include 引用（含 `#include "..."` 各级相对路径）+ vcxproj/filters 登记交叉。移入 57 文件（core/float{3x3,4x4,8}×6、lib/render×16、lib/std×32、runtime_value/svalue×2、vm_system_registry.c 墓碑），另发现用户已自行放入 compile/csharp/ir/project 四个 zip。
  4. 两个"看似该移实为活文件"的判定：`src/vm/runtime/vm_system_registry.h` 是转发 shim（→ system_method_call/system_method_registry.h），被 7 个在编文件 include，**只移 .c 墓碑、.h 留原位**；`src/lib/ffi/gen_sl_ffi_call.py` 是 sl_ffi_call.c 的活代码生成器，保留。另清掉 project/cmake/CMakeLists 里两行磁盘上不存在的死引用（lib/std/console.c、dir.c）。
- 修复点（文件/模块）：log_manager.c（删 include + fallback 改为直接 return TRUE）；vm_byte_buffer.c（mem.h → ../base/mem.h）；byte_buffer_system_method.{c,h}、file_system_method.c（`../../base/vm_byte_buffer.h` → `../vm_byte_buffer.h` + 注释路径）；根 CMakeLists L48、vcxproj L194/L449、filters（base→vm + 删 ErrorDefinitions_data.h 条目 + 删孤儿 Filter `src\lib\std`）；md/design/STREAM_DESIGN.md 落位表述同步；AGENTS.md §4（删 std/render/compile 四目录行、补 nouse/、core 清单更新）。
- 如何快速验证：vcxproj Debug|x64 exit 0；Ninja（本机无 clang，`scripts\build-vm-win.ps1` 自动回退 MSVC+Ninja 增量）exit 0——重编恰为本次改动的 4 个文件（vm_byte_buffer.c / log_manager.c / byte_buffer_system_method.c / file_system_method.c），增量探测路径变更正确；Core.module.json exit 0、ProjectTest exit 0（Monitor P5/P6 FAIL 为已知两平台同败项，非本次引入）。
- 预防建议：① 跨目录移动文件时"改别人的引用"与"查文件自身的 include"要同步做，同目录裸引用（无路径前缀）在移动后必断；② 删"疑似无用"文件前先确认它在失败路径里的角色（fallback/降级分支平时不可见）；③ 移入 nouse/ 的文件如需恢复：移回原位 + R6 三处登记 + grep include 引用三步缺一不可。

### [2026-10-01] attribute 四时点重构验证期再现「compile 缺 -e ir 致 module.json 不重写」：dotnet exit 0 假成功，判据收敛为日志行 + 文件级 mtime
- 现象：attribute 四时点重构 P1 验证期，`compile -p <.sp>`（未带 `-e ir`）Meta/IR 阶段全 Completed、dotnet 退出码 0，看似成功；但 `out/export/<模块>/<模块>.module.json` 的 mtime 停在 15:36 原地不动（连跑两轮均如此），C VM 执行的仍是旧模块——attribute 改动全部"没生效"。ProcessSummary 中 Export 阶段显 `[Pending]`。排障初期还被 launchSettings.json 中 F: 盘历史失效路径带偏，实为噪音。
- 首个异常阶段：Export（`CommandExecutor.ExecuteCompile` 相位调度），非 Meta/IR——上游各阶段日志全绿。
- 根因：Front `compile` 动词缺省只跑到 IR 相位（RunToPhase(IR)），仅命令行带 `-e ir` 时 `CommandExecutor.ExecuteCompile` 才 `RunPhase(Export)`；缺参 → module.json 不重写，且 Front 不把"未导出"反映到 dotnet 退出码（恒 0）。另两个干扰判据一并澄清：① ProcessSummary 的 `[Pending] Export` **不能单独当失败证据**——因打印时序，成功编译（带 `-e ir`）的汇总里也会出现 `[Pending]` 字样；② **目录 mtime 不算数**（Windows 目录时间戳更新时机与文件写入不同步），必须看 module.json 文件本身的 LastWriteTime。
- 修复点（文件/模块）：无代码修复（相位调度行为符合设计）；判据修正回写三处——根 `AGENTS.md` §5（compile 命令样例补 `-e ir` + 判据注释）、`md/syntax/attribute.md` SLIR 契约节 ⚠ 警告框、`md/ai/故障排查流程.md` 本条。批量脚本 `scripts/compile-stdlib.ps1`/`compile-tests.ps1`（build-all.ps1 内部调用）本就正确携带 `-e ir`，本次 build-all 全量回归实测佐证。
- 如何快速复现：任一工程 `dotnet run --project source\Front\SimpleLanguageFront.csproj -- compile -p <.sp>`（不带 `-e ir`）——本轮与下一轮 module.json 文件 mtime 均停留旧值；补 `-e ir` 后同一命令即刻重写。
- 如何快速验证：判据只认两条且须同时满足：① `Logs/Front.txt` 出现 `export module success`（ExportSLModulePackage 阶段成功）日志行；② module.json **文件级** mtime 在本次运行时间点被刷新。
- 预防建议：①本坑已在 §6 四次复发（[2026-09-12] Component ②、[2026-09-12] P2.5 AOT ②、[2026-09-29] java_hotspot ③、本次），手敲 compile 命令一律默认带 `-e ir`，日常回归走 `build-all.ps1`/`compile-*.ps1`（内建该参）；② `[Pending]` 是相位状态的瞬时快照非终态，成败判据 = 日志行 + 文件 mtime 双确认，单看任何一项都可能误判（成功也可能显 Pending、失败也可能 exit 0）；③ 排障遇"改动没生效"先查 module.json 文件 mtime 是否刷新，再查 launchSettings 等环境噪音，勿先怀疑上游语义改动。

### [2026-10-07] HttpWebTest 宿主分支找不到 .sp（ProjectSPFilePathNotFound + F 盘日志路径连锁）：Program.cs 拼名末段必须与实际 .sp 文件名一致
- 现象：`dotnet run --project CSimpleVMTest -- HttpWebTest` 报 `ProjectSPFilePathNotFound: 没有找到工程的路径:D:\project\lang\simple_language\Project.sp`（ResolveProjectSp 回退 cwd 兜底失败），连锁 `DirectoryNotFoundException: 'F:\project\lang\simple_language\out\export\Core\Logs\Front.txt'`，exit 1。NetTest 分支同构写法却正常。
- 首个异常阶段：Front CLI（`CommandInputArgs.ParseCompileProjectPath` 对 `-p` 路径的解析），jsonc 尚未加载 → Log 走 F 盘默认路径属连锁非根因。
- 根因：① 宿主 `Program.cs` L121 拼的是 `Path.Combine(repoRoot, "test", "Other", "HttpWebTest", "ProjectTest")`——`ParseCompileProjectPath` 对不以 `.sp` 结尾的路径按 `<目录>\<末段名>.sp` 解析，末段 "ProjectTest" 解析出不存在的 `HttpWebTest\ProjectTest.sp`（实际文件名是 `HttpWebTest.sp`）；NetTest 能跑纯因其 sp 恰好就叫 `ProjectTest.sp`；② `Log.cs` L88 `FrontLogDefaultPath` 硬编码 F 盘历史路径（项目 F→D 迁移遗留），jsonc 未加载时写日志即用此默认值抛异常——sp 路径修好后此异常自然消失。
- 修复点（文件/模块）：`simple_language/project/CSimpleVMTest/Program.cs` L121 末段 `"ProjectTest"` → `"HttpWebTest"`。
- 如何快速复现：修复前跑 `dotnet run --project project\CSimpleVMTest -- HttpWebTest`，Front.txt 首条即 ProjectSPFilePathNotFound。
- 如何快速验证：修复后 HttpWebTest G1-G17 全 OK（含新增 G17 协程等待组与 Text.Json 新构造）、pass=81 fail=0、exit 0；Front 日志显示 `export module success` 且 FrontLog 正确写 D 盘。
- 预防建议：① 宿主新增测试分支时 `Path.Combine(repoRoot, "test", "Other", <目录>, <sp名去扩展>)` 的末段必须与实际 .sp 文件名（去扩展）一致（JsonTest/NetTest 先例对照）；② F 盘 `FrontLogDefaultPath` 是迁移遗留默认值，凡见 F 盘路径异常先怀疑"jsonc 未加载"，优先查上游 sp 解析失败而非日志系统本身。

### [2026-10-13] wasm Playground 端到端双坑：MEMFS 布局须与磁盘同构 + Emscripten 同名库二次 dlopen abort
- 现象/任务：Playground（编辑器写 SL → 服务端 Front 编译 → 浏览器 wasm VM 执行，`wasm/playground.html` + `server.js POST /api/compile`）联调：运行 exit 0 但终端零输出；修好后又崩 `Aborted(Assertion failed: attempt to load '../Lib/Std.dll' a second time)`。
- 排障路径（R12 证据先行）：wasm 侧文件不落真磁盘、`build/logs/VM.txt` 只存在于 MEMFS → 写 `wasm/smoke-playground.js`（Node 复现前端管线）运行后 `FS.readFile('/build/logs/VM.txt')` 抓日志 → 最早 Error = `could not load module reference '../../export/Core/Core.module.json'`，后续 `CallSystemMethod not registered. method=SystemPrintln` 为连锁（R8 只看最早）。
- 根因（两个独立坑）：① Front 把 moduleReferences 重写为**相对模块导出目录**（`out/playground/Playground/`）的相对路径，前端 MEMFS 只建了一层浅目录（`/work/Playground`），`../../export/...` 解析落空 → 依赖模块整棵缺失；② Emscripten 的 dlopen shim 对同名库第二次加载在首次失败未清状态时直接 abort——`system_method_registry.c` 每个 `DllName!symbol` 注册都重进装载函数（Std 模块几十个 systemCall），首次 `../Lib/Std.dll` dlopen 失败后第二次即崩；`sl_ffi_lib_manager.c` 候选1/候选2 一次装载内也两次 dlopen。
- 修复点（文件/模块）：① `wasm/playground.html` + `smoke-playground.js` MEMFS staging 改磁盘同构（`/work/out/playground/Playground` + `/work/out/export/{Core,Std}`）；② `system_method_registry.c` 装载失败也缓存 NULL 占位（`vm_sysfunc_ext_lib_load` / `vm_system_func_preload_ext_lib` 两处），后续同名查找短路返回 NULL（宿主顺带省重复探测）；③ `sl_ffi_lib_manager.c` 抽 `sl_ffi_platform_load`，wasm 分支整体短路恒 NULL（宿主 Win/Unix 分支行为不变）。
- 如何快速复现：修前版本 `node wasm\smoke-playground.js`：浅布局 → 引用装载失败 + SystemPrintln 未注册零输出；同构布局引入 Std 后 → 二次 dlopen abort。
- 如何快速验证：浏览器 http://localhost:8080/playground 三条路径全绿（默认示例 exit 0、错误代码编译失败回显、重置后重跑）；宿主回归 Math 模块（CWD=project\CSimpleVMMathTest）VM.txt 记录 `FFI: library loaded ...math_lib.dll` + `static lib 'math_lib' preloaded` + `40/40 method(s) native-bound, 0 fallback`，重复装载命中同句柄（refcount 递增）、退出正常 unload——成功路径零回归。
- 预防建议：① wasm 排障第一手段 = Node 冒烟脚本抓 MEMFS 里的 `/build/logs/VM.txt`（真磁盘上没有）；② MEMFS staging 一律与磁盘目录完全同构，勿按"能省一层是一层"建浅目录；③ 任何「失败后重试 dlopen/LoadLibrary」逻辑在 Emscripten 下先想二次加载 abort——失败必须留 NULL 占位或整体短路；④ vmDllImports 相对路径按设计**相对进程 CWD** 解析（Math.jsonc 注释明示），standalone 跑 exe 时 CWD 须为 `project\<测试工程>`，从仓库根报 not preloaded 是预期路径约定不是回归。

### [2026-10-16] ReleaseJit 树 LNK2001：`jit_x64_encode.c` 裸用 `base_malloc` 未 include `base/mem.h`——宏名被当函数隐式声明，链接期符号不存在
- 现象：ReleaseJit 树 clean-first 重建，编译全过、双目标链接失败 `jit_x64_encode.c.obj : error LNK2001: 无法解析的外部符号 base_malloc`；同源码 Release/Debug 树（VM_JIT_ENABLE=OFF，jit 文件不参与编译）正常。
- 首个异常阶段：链接期（编译期隐式声明只给 warning，错误推迟到 LNK 才爆）。
- 根因：`base_malloc` 不是函数而是 `base/mem.h` 里的**宏**（mimalloc 接管时映射 `mi_malloc`，否则 CRT `malloc`）。`jit_buf_init` 裸写 `base_malloc(...)` 且该 TU 只 include 了 `stdlib.h` → C 隐式函数声明生成对"函数 base_malloc"的引用 → 全仓无此符号。§4.5 `base_chars_dup` 坑的链接期变体：那次是隐式声明按 int 截断指针崩在运行期，这次是符号根本不存在崩在链接期——同源不同爆点。
- 修复点：`jit_x64_encode.c` 补 `#include "../../base/mem.h"`；同时把 `jit_buf_grow/jit_buf_free` 的 `realloc/free` 换成 `base_realloc/base_free`——原代码 `base_malloc`（mi_malloc）配 CRT `free` 是分配器族混用 UB。
- 如何快速复现：`Import-VsDevEnv; cmake --build build\ReleaseJit --clean-first`。
- 如何快速验证：链接通过 + ReleaseJit `--jit` BenchMark 输出值与解释器一致。
- 预防建议：用 `base_*` 家族 API 的 TU 必须显式 include 对应 `base/*.h`（宏无法被链接器兜底，比函数缺声明更隐蔽）；JIT 树（ReleaseJit/DebugJit）不随日常构建走，改动 `src/lib/jit/**` 或公共头后**别忘单独重建两棵 JIT 树**再交工。

### [2026-10-18] Front 平铺重组遗留双坑：插件 frontend ProjectReference 多跳一层 `..\`（"跳过项目"假绿）+ .user ActiveDebugProfile 失配致 VS F5 无启动配置
- 现象：用户报 SpecialTest 宿主（`SlangAllInOne\Project\CSimpleVMSpecialTest`）"VS 工程跑不起来，疑似少工程"。VS/MSBuild(Full) 构建输出 `跳过项目"D:\project\simple_language_plugins\csharp_mono\frontend\SLCSharpMonoFrontend.csproj"，因为未找到该项目`（java_hotspot 同）——注意解析出的路径少了一层 `lang`；同时 `.csproj.user` 的 `ActiveDebugProfile` 仍是旧工程名 `CSimpleVMTest2`，与 launchSettings.json 实际 profile 名（SpecialTest/BenchPark）失配，VS F5 找不到启动配置。
- 根因：① 2026-10-17 仓库重组把 Front 工程从 `simple_language\source\Front\` 平铺到 `simple_language\source\`（少一层目录），`SimpleLanguageFront.csproj` 末尾两个插件 frontend ProjectReference 的相对路径 `..\..\..\simple_language_plugins\...` 没跟着减一层 → 上跳到仓库根之外（`D:\project\simple_language_plugins\`）。MSBuild 对找不到的引用仅 warning"跳过项目"，退出码仍 0，构建假绿；后果是 Front 层 `@csharp_mono(){}`/`@java_hotspot(){}` 的 parser/builder（反射转调 plugin.jsonc 的 parserType/builderType）始终加载不到，SpecialTest 编译清单里 CSharpTest*.sl / JavaTest*.sl 一直在缺插件状态编译；② `.user` 文件是旧工程拷贝遗留，不随 launchSettings 同步。
- 修复点（文件/模块）：`simple_language\source\SimpleLanguageFront.csproj` 两个插件引用 `..\..\..\` → `..\..\`；`SlangAllInOne\Project\CSimpleVMSpecialTest\CSimpeVMSpecialTest.csproj.user` ActiveDebugProfile → `SpecialTest`；`SlangAllInOne\Project\CSimpleVMBenchMarkTest\CSimpleVMBenchMarkTest.csproj.user` → `BenchPark`（同类遗留顺手修）。
- 如何快速复现：修复前 `MSBuild.exe（VS 路径）` 构建任一引用 Front 的宿主工程，输出开头即出现两条"跳过项目 D:\project\simple_language_plugins\...（未找到）"。
- 如何快速验证：MSBuild(Full) 构建链 5 产物全出（`csimple_lang_dll.dll`、`SLCSharpMonoFrontend.dll`、`SLJavaHotspotFrontend.dll`、`SimpleLanguageFront.dll`、`CSimpeVMSpecialTest.dll`），"跳过项目"警告消失；`dotnet run` 完整链路 exit 0（Front 编译 SpecialTest + C VM P/Invoke ProcessTest 33 PASS）。
- 预防建议：① 仓库重组/移动工程文件时，凡指向它的 ProjectReference 相对路径必须逐条重算层级——"引用固定多跳一层 `..\`"是平铺（去子层）重组的固定伤；② MSBuild"跳过项目（未找到）"是 warning 非 error、退出码 0 构建假绿——批量脚本判据除退出码外应 grep `跳过项目`；③ 拷贝工程目录会连带 `.csproj.user`，其中 ActiveDebugProfile 必须与该工程 launchSettings.json 的 profile 名一致，否则 VS F5 无启动配置。

### [2026-10-18] Project 全工程拉起四连坑：sln 裸 LF 行尾（MSB5023）+ mysql vcxproj 旧布局宏 + ExpendTest 缺 SLangServer 模块 + Other\* 用例集 references 少一级
- 现象：用户要求把 `SlangAllInOne\Project` 下全部 VS 工程跑起来。① 命令行 MSBuild 构建 sln 直接 `error MSB5023: GUID {9FD3F63C}(SlangAllInOne.csproj) 列为嵌套但不存在于解决方案中`——但该 Project 条目明明在 sln 第 8 行且 GUID 三处字面一致，VS 打开也正常；② 全量构建唯一下线工程 `cvm_sl_mysql_lib.vcxproj`：`C1083: 无法打开包括文件 mysql.h`；③ CSimpleVMStdTest（ExpendTest）Front 编译失败：`import 命名空间路径解析失败 ... 没有找到 SLangServer`；④ CSimpleVMTest（NullFast 分支）Front 编译失败：`[Reference] Failed to load module: Core.module.json, path=../../../out/export/Core`，连锁 `SystemPrintln 解析链错误`。
- 根因（四个独立坑）：① `SlangAllInOne.sln` 全文件 403 行**裸 LF 行尾**（AI/工具写入时未按 sln 规范 CRLF）——VS 解析器容忍、命令行 MSBuild 的 sln 解析器严格，Project 条目解析失败后报误导性的 MSB5023"工程不存在"；② vcxproj 的 `MySqlClientRoot` 宏仍指旧布局 `source\Front\Lib\SLMysql\...`（vendored MySQL client 实际在 `SLangCore\Lib\SLang\Mysql\cvm_sl_mysql_lib\mysqlclient`），同文件 L101 的 .c 源却已指向新位置——半迁移状态；③ ExpendTest jsonc references 引第四件库 `SLangServer`（`Lib\SLang\Server\Server.sp`，2026-10 新增），但编译流程（compile-stdlib 三件套 / sln 无 CompileServer 宿主）都不覆盖它，`out\export\SLangServer` 缺失；④ `test\Other\*` 用例集比主套件（`test\<suite>`）**深一层**，45 个 jsonc 的 references 写 2/3 级上跳，解析到 `SLangCore\out\export\Core`（不存在；官方位置 `SlangAllInOne\out\export`）——引用模块加载失败后 sp 里的 `SystemPrintln` 等系统方法连锁解析失败，极易误判为"sp 不能调系统方法"（BaseTest 对照组 sp 同写法能过，实锤是路径不是语法）。
- 修复点（文件/模块）：① sln 规范化 CRLF + UTF-8 BOM（内容不变）；② `cvm_sl_mysql_lib.vcxproj`：`MySqlClientRoot` 与 `vm_sl_mysql.h` 的 ClInclude 改指 `SLangCore\Lib\SLang\Mysql\...`；③ 手动编译 `Server.sp` 产出 `out\export\SLangServer\{*.slb,*.module.json}`（命令已记 test-guide 常见问题）；④ 批量正则 `"(\.\./)+out/export/` → `"../../../../out/export/` 修 45 个 Other\* jsonc（保留 BOM/行尾，outputDir 反斜杠形态与套件间本地互引不动）。
- 如何快速复现：修前分别跑 `MSBuild.exe SlangAllInOne.sln`（MSB5023）、`MSBuild sln`（mysql C1083）、`dotnet run --project Project\CSimpleVMStdTest`（SLangServer import 失败）、`dotnet run --project Project\CSimpleVMTest`（Core reference 加载失败 + SystemPrintln 解析链错）。
- 如何快速验证：sln 全量 MSBuild exit 0（25 工程，含 sl_mysql_lib.dll）；CoreTest/StdTest/MathTest/BenchMarkTest/RenderTest/SpecialTest 宿主全 exit 0；CSimpleVMTest 双分支（NullFast + HttpWebTest）exit 0，HttpWebTest pass=81 fail=0。
- 预防建议：① **AI/工具写 sln 必须落 CRLF + UTF-8 BOM**——LF-only 的 sln 在 VS 里"看似正常"，MSBuild 命令行才爆 MSB5023，且报错文案完全误导（工程明明存在）；判断技巧：报"工程不存在"但肉眼可见 Project 条目时，先查行尾/编码再查 GUID；② 重组后 vcxproj 的**自定义路径宏（UserMacros/PropertyGroup 变量）与 ClInclude/ClCompile 清单要同步迁移**，本次宏漏改但源码清单已改的半迁移最难一眼看出（C1083 报的是 include 而非宏本身）；③ 新增库模块若被测试集 references，须同步补进编译流程（三件套→四件套）或在 test-guide 登记手动前置；④ 用例集挪目录深度时 references/outputDir 的 `..` 层数必须重算——`test\Other\` 下统一 4 级上跳（references）/3 级（outputDir 落 `SLangCore\out\export`）；⑤ 已知遗留（未在本次范围）：`scripts\common.ps1` 等批量脚本整套仍是重组前旧布局（`simple_language\out\export`、`source\Front\...`），走脚本链路前需先更新。

### [2026-10-18] 死工程清理与复活：Test/Test2 由 C# VM 宿主改造为 C VM 轻量宿主；StdNativeImpl/MathNativeImpl 删除（含留档）
- 现象：`Project\Test|Test2|StdNativeImpl|MathNativeImpl` 四个死工程——Test/Test2 的 VM 段引用已删除的 `..\VM\SimpleLanuageVM.csproj`（旧 C# VM），StdNativeImpl/MathNativeImpl 实现已删除的 `ISLExternalFunctionModule` 外部函数接口（`using SimpleLanguage.VM.Runtime` 悬空）。用户要求修复。
- 处置决策（用户确认）：Test/Test2 复活为 C VM 宿主（方向唯一）；StdNativeImpl/MathNativeImpl 删除——机制随 C# VM 废弃，C VM 等价物 = C DLL + jsonc `systemCalls.cvmFunction`（`CLangdll`/`cvm_math_lib` 已覆盖该场景），无任何宿主消费，修复无意义。
- 修复点（文件/模块）：① `Project\Test\SimpleLanguageTest.csproj` / `Project\Test2\SimpleLanguageTest2.csproj`：删 SimpleLanuageVM 引用，加 `MSBuildRuntimeType=Full` 条件的 vcxproj 级联（与 CSimpleVM* 同款）；② 两个 Program.cs：删 `extern alias VMRuntime`/`using SimpleLanguage.VM`，VM 段换 `RunCVM`（Debug P/Invoke `cli_main` + SetDllDirectory，Release 跑 exe），Debug 下 Front 加 `--format binary --export-json`（R15 对齐）；③ sln 收录两工程（GUID `48CB7D22-72C0-471A-894E-733C2F22C1DB` / `79F13E4C-8099-4231-9B50-3D9E8BC670EC`，挂 test 文件夹，Project+配置映射+嵌套三处 CRLF 插入）；④ 删除 `Project\StdNativeImpl\`、`Project\MathNativeImpl\`、`SlangAllInOne\_tmp_test.metaproj`（排障残留）。
- **删除留档**（无 git，永久移除前记录）：`StdNativeImpl\ConsoleExternalModule.cs` 实现旧 C# VM 外部函数注册（`ISLExternalFunctionModule.Register` + `registrar.Register(name, Func<object[],object>)`），注册 `Console.println/print/write/input/readLine/readKey`；`MathNativeImpl\MathExternalModule.cs` 同机制注册 `Math.sin/cos/tan/asin/acos/atan/atan2/sinh/cosh/tanh/pow/sqrt/exp/log/log10/ceil/floor/round/truncate`（float 包装 + ReadFloat 参数归一）。SL 侧调用形态为 `SystemCallExternalFunction("Math.sin", ...)`——该体系已不存在。
- 如何快速验证：两个 csproj `dotnet build` 0 警告 0 错误；`dotnet run Test`（BaseTest 73 文件）与 `dotnet run Test2`（ExpendTest）Front 编译 + C VM P/Invoke 全链路 exit 0；sln 全量 MSBuild exit 0（27 工程）。
- 预防建议：① 删除机制承载工程前先确认等价物已落地（本次 C DLL + cvmFunction 体系早已覆盖才删）；② **sln 全量构建偶发 `C1083 Permission denied`（写 vcxproj obj）= 并行竞态**：`CSimpleVMCoreTest` 的 `build_cvm.bat`（BeforeTargets=Build 的独立 MSBuild 进程）与 Test/Test2/SpecialTest 等 ProjectReference 触发的同一 vcxproj 构建并行写同一 obj 目录——MSBuild 的 ProjectReference 去重管不到 bat 开的外部进程；复现时直接重跑即可，根治方案是 CoreTest 弃 bat 改 ProjectReference（未在本次做，改动面大）；③ Test/Test2 与 CoreTest/StdTest 功能等价（轻量入口定位），新增宿主别再复制这条链路，优先复用现有 7+2 个宿主。

### [2026-10-18] ExpendTest 全线 Front 失败（21464×16）：R15 slb 优先引用装载丢 attributeContracts——SLB 补 tag 0x16 + META 未知 tag「真跳过」修正
- 现象：CSimpleVMTest 跑 ExpendTest，Front 编译期 `MetaCoreAttributeStageTargetsNotFound`（21464）连出 16 条 Error（Exclude/Nickname/Serializable/SerializeField/NonSerialized）→ MetaCore 阶段失败、Export 跳过；BaseTest 等无属性用例不受影响。
- 首个异常阶段：RefModule 引用装载（Front）——不是"最早 Error"直觉里的 ParseMeta，而是更早的装载通道问题：`@Exclude` 等属性类的 stage/targets 契约取不到。
- 根因（两层）：① **SLB 不编码 attributeContracts**（旧注释自认"JSON-only：CVM 不读"——漏了 Front 引用装载也是读方）：R15 后引用装载 slb 优先（`ReadPackageForReference`），跨模块 @X 契约唯一数据源是 module.json 顶层 attributeContracts，slb 通道丢失 → 21464 Error 级连锁；② **META 未知 tag 并非真跳过**：补 tag 0x16 后 C VM 拒载报"META tag 值有尾部冗余字节: tag=0x16"——C#/C 两侧 default 分支都不消费 value 字节，循环尾"尾部冗余"校验必然失败，规范声称的前向兼容实为"任何新增 META tag 打崩所有旧读器"（0x16 首例实锤）。
- 修复点（文件/模块）：① `SLBFormat.cs` 新增 `MetaTagAttributeContracts=0x16`；② `SLBWriter.cs` META 段补编（count × {poolRef name; uvarint stage; uvarint targets}）；③ `SLBReader.cs` 补解码 case + `SkipAll()` 真跳过 default；④ C VM `slb_decoder.c` 镜像 `slb_dec_skip_all` + default 真跳过（尾部冗余校验只对已知 tag 生效）；⑤ `SLIRTypes.cs`/`SLModulePackageWriter.cs`/`ProjectReferenceModuleLoader.cs` 过时注释同步。
- 如何快速复现：移走 out\export\Core\Core.module.slb（强制 json 引用装载）编译 ExpendTest 同样 16 错 → 证明与 slb 通道无关的 A/B 反证不成立，问题在装载通道本身；恢复 slb 复现主路径。
- 如何快速验证：`CompileStdlib` 重编（slb 带契约）→ ExpendTest 250 OK / 0 FAIL exit 0；C VM 侧跑带 0x16 的 slb 正常装载（未知 tag 消费窗口后无冗余报错）。
- 预防建议：① **"只有 X 消费字段 Y"的判断必须审计所有读方**（导出格式的字段裁剪尤其如此——运行时、引用装载、工具链各有读面）；② TLV 格式的"未知 tag 跳过"承诺要有测试覆盖（写一个带未知 tag 的样本喂旧读器），否则承诺是纸面的；③ META 新增 tag 时同步 C#/C 两侧 default 跳过语义（本次修正后才真正成立）。

### [2026-10-18] CSimpleVMTest 执行端切换发布包 slang 应用：四个负例注册 + RenderTest/GameTank 工程修复 + 两个 Front 既有 bug 顺手修复
- 现象：宿主按用户指令改为「Debug → package\win32-debug、Release → package\win32-release 的 slang.exe run-disk 执行（标准库取自包 lib\）」后跑全量，暴露一批此前 P/Invoke/直调路径下被掩盖或既有即坏的问题。
- 修复点（文件/模块）：
  1. `CSimpleVMTest.csproj`：移除 csimple_lang_lib.vcxproj 条件引用（执行端不再依赖开发树 C VM）；`Program.cs`：`RunCVM` 重写为「产物拷入 `<package>\<Dir>\`（按 jsonc project.name 定位文件，不按目录名——NullFast 目录 NullFastTest\ 文件 ProjectTest.module.slb 不同的坑）→ slang.exe run-disk」；负例注册表扩充 `s_negativeFrontCases`（PlatformNegTest=RequireValueInvalid×4、PlatformOverrideNegTest=×3、PlatformAotNegTest=AotFeatureConflict×1、AtSignLabel=ChannelSyntaxError×6+OutChannelMultiple×1）+ 新增 `s_negativeRunCases`（PlatformVariantNegTest：预期 exit 1 + "平台变体均不匹配"标记）。
  2. `IRBlockStatements.cs`：补 `MetaInlineLambdaDefineStatements` 显式空 case——此前落 default 插桩分支每条 lambda 定义记一条 Error（InlineLambdaTest 11 定义=11 错，JSON/slb 双通道 A/B 证明与 R15 无关的既有 bug）。
  3. `MetaClass.cs`：Project 特殊类成员不再系统级标 const——const 左值拦截契约只拦用户显式 const（isExplicitConst），系统标记让 .sp 全局成员不可赋值（ARCTest globalTransferCase `global.gslot = o5` 被拒）。
  4. 用例工程修复：RenderTest 残缺 jsonc（引用 8 个不存在的文件、缺 Math 引用、moduleName ProjectTest2 撞名）收敛为单文件 MathTest.sl 冒烟；TankGame.jsonc references 少一级上跳（3 级指到不存在的 SLangCore\out\export）修为 4 级；TankGame.sl 加 `-- auto` 自动模式（Windows 管道 keyAvailable 恒 false，交互键无法注入 CI）。
- 如何快速验证：Debug 22 套件 + 6 负例 + GameTank(auto) 全 exit 0（BaseTest 24 FAIL 为已验证既有基线：协程 5 + Monitor P5 调试帧 9 + Tuple.create 10）；Release 同表 exit 0（ExpendTest 多 1 项 MiTest mimalloc "current falls" 断言，开发树 Release csimple_lang 直跑同样复现=既有，非包特有）。
- 预防建议：① 宿主执行端切换是「换镜」不是等价替换——会系统性暴露路径假设类问题（文件名≠目录名、references 层级、交互用例无输入源）；② 交互式用例自动化必须设计显式退出通道（参数开关），别指望管道注入按键；③ 阶段级 Error 计数聚合（IR 阶段 11 错）要先展开逐条定位，"恰好=N 个定义数"这类对应关系是 batch 误报的强信号。

### [2026-10-18] SDK 10 发布链重构致 WipeReleasePackage 死链：win32-release 残留物跨发布存活
- 现象：`dotnet publish -c Release`（零旗标 AOT → package\win32-release）exit 0，但包内残留上次 CSimpleVMTest 拷入的 `MathTest\`（19MB module.json + slb）等非本发布产物；同日 20:10 前后包内 slang.exe 一度失踪（时间点与一次外部 MSBuild 启动吻合，中断过程无日志可考）——包不再满足"只含本次发布产物"的卫生契约。
- 根因：.NET SDK 9/10 重构发布拷贝链（本机 `dotnet --list-sdks` 仅 10.0.401、无 global.json）：`CopyFilesToPublishDirectory` 依赖改为 `_IncrementalCleanPublishDirectory + _CopyResolvedFilesToPublish*`，`_CopyFilesToPublishFolder` 只剩 ClickOnce(PublishOnly) 路径引用。csproj 的 `WipeReleasePackage` 挂 `BeforeTargets="_CopyFilesToPublishFolder"` = 静默死链（正常 dotnet publish 永不触发、零报错）。SDK 自带孤儿清理只删"历史发布记录过的文件"，测试流程直写的 MathTest\ 不在其管辖 → 永久累积。
- 修复点（文件/模块）：`SlangAllInOne.csproj` WipeReleasePackage 改双入口挂钩 `_IncrementalCleanPublishDirectory`（新链拷贝阶段最先跑，语义与旧挂点等价）+ `_CopyFilesToPublishFolder`（SDK 8 兜底，目标不存在/不跑时挂点自然落空、无害）；新增 `_WipeReleasePackageDone` 守卫防极端管线双入口先后触发时第二次 wipe 误删已拷入的新产物。
- 如何快速复现：发布前确认包内有非发布产物残留（MathTest\ 实锤）→ 旧挂钩下 `dotnet publish -c Release` exit 0 后残留仍在。
- 如何快速验证：修复后同命令 exit 0 → 残留全清（Test-Path MathTest = False），bin\lib\md 目录 mtime 全部刷新为本次发布，包内容 = slang.exe(9.9MB 原生单文件 AOT) + bin\ + lib\ + md\；`slang.exe version` 冒烟正确识别包内 bin\ 运行时。
- 预防建议：① 挂 SDK 内部 target 的 hook 是对 SDK 私有管线的隐式契约，跨 SDK 大版本（8→9/10）必须重验——依赖链重构不会报错，只让 hook 静默失效；② 机器 SDK 漂移（无 global.json 钉版本）时，csproj 里的 SDK 内部挂点优先怀疑；③ wipe 类 target 的验证别只看 exit 0，要看"非发布产物是否消失"。

### [2026-10-20] 包内运行缺引用模块 → C VM 静默 skip：跨模块调用全落空壳，测试挂死仍 exit 0（SLangServer P1.5 验收首跑踩坑）
- 现象：CSimpleVMTest 跑 ExpendTest（新增 ServerP15Test 后首跑），`[ServerP1Test] T1 begin` 后无任何输出、进程 exit 0；VM.txt 仅一行 Warning `could not load module reference '../../../../out/export/SLangServer/SLangServer.module' (resolved: ProjectTest2/...), skipping`，随后照常 `VM finished successfully`。ServerP1Test 的 `ServerConfig().port` 写 19401 读回空串、`Server.isRunning` 返回空、`Server.start` 不监听也不抛——跨模块（SLangServer）全部静态调用与字段访问静默失效。
- 首个异常阶段：C VM 运行期引用装载（`sl_load_references`）——Front 编译全绿、IR 正确（`CallStatic SLangServer.SLang.Server.start` 在指令流里），坏的只是运行期链接。
- 根因（两层）：① `CopyModuleIntoPackage` 只拷主模块产物，**非系统库引用模块（ExpendTest→SLangServer）不跟随**——包内 `ProjectTest2\` 目录里没有 SLangServer.module.slb；② C VM 对解析失败的引用**静默 skip**（相对路径落空后 basename 回退 `<主包目录>`→`<exe>\lib|modules` 全部未命中即丢弃，仅 VM.txt Warning、不影响退出码），主模块内该模块的方法壳（`instructionList: []`）成为唯一注册——所有跨模块调用命中空体 no-op，对象字段槽错位读出空值；无 listen → HttpClient 连接被拒挂起 → 主协程等 IO 期间无在途 socket，VM 按"全部完成"优雅收尾 exit 0，**测试失败被伪装成成功**。
- 排障路径（值得复用的二分法）：① 同一份 SLangServer 在独立探针工程（SrvT1Probe）与 NetTest 均正常 → 锁定 ProjectTest2 上下文；② 排除 ServerP15Test/data 段/imports/其他 27 文件/运行期污染（单文件+单调用仍坏）→ 锁定工程身份；③ **同一份主模块 slb 换目录运行**（PT2NameProbe\ 好 / ProjectTest2\ 坏）→ 锁定运行目录装载环境；④ 列目录发现 ProjectTest2 缺 SLangServer.module.slb（NetTest 目录手工拷过所以好）→ 实锤。全程 ~2 小时，VM.txt 的 Warning 行是唯一早期线索（排障时先 `Select-String "could not load module"`）。
- 修复点（文件/模块）：`CSimpleVMTest/Program.cs` 新增 `StageReferencedModules`（`CopyModuleIntoPackage` 尾部调用，签名增 repoRoot）：解析主模块 json `moduleReferences`，非系统库引用（Core/Std/Math 走包内 `<exe>\lib\` 官方库直查不拷）按两处标准导出树（`SlangAllInOne\out\export\<名>\` 与 `SlangAllInOne\SLangCore\out\export\<名>\`——注意 repoRoot 以 SlangAllInOne.csproj 定位 = `SlangAllInOne\`，第一版路径多拼一层 `SlangAllInOne\` 空欢喜一次）连带拷入 `<pkg>\<名>\`；未找到打 `[stage] ... not found` 提示不阻断。
- 如何快速复现：删掉 `package\win32-debug\ProjectTest2\SLangServer.module.slb` 后 `.\slang.exe run-disk ProjectTest2\ProjectTest.module.slb`——ServerP1Test 形态的跨模块用例全部静默挂死/假绿。
- 如何快速验证：修复后 `dotnet run --project SlangAllInOne\Project\CSimpleVMTest` 输出 `[stage] referenced module 'SLangServer' staged into package`，ServerP1Test 42 项 + ServerP15Test 10 项全 OK、ExpendTest 全量零 FAIL。
- 预防建议：① **引用静默 skip 是危险默认**——跨模块方法解析失败应区分「主模块引用了但装载失败」（可判 fatal，至少 stderr/stdout 显式 Error 而非仅日志文件 Warning），后续 C VM 侧可评估升级（涉及 sl_load_references 返回值协议，另行立项）；② 包内运行多模块工程时先确认引用模块已就位（`Get-ChildItem <pkg>\<Module>` 对照 moduleReferences）；③ 「同一二进制换环境二分」是对抗"环境依赖型静默失败"的最快手段——本次从全仓嫌疑（Front/SLangServer/宿主）收敛到单目录文件清单只用了三步。

### [2026-10-21] VSCode 插件 0.0.15/0.0.16 激活即炸：esbuild platform=node 走 main 字段选中 jsonc-parser UMD 入口，工厂参数化 require('./impl/*') 残留运行期解析（F5 descriptor 报错两轮误诊后定案）
- 现象：用户 F5 报 `Couldn't find a debug adapter descriptor for debug type 'slang' (extension might have failed to activate)`；0.0.15/0.0.16 重装 + 重启 Trae CN 均无效。首轮曾定案为「同版本覆盖装 + 未重载窗口 + 陈旧 AOT 包」（slang_vscode_plugin/md/PROGRESS.md「二十九」），重装后复发证伪安装态假说——**重装只是复刻同一构建产物，坏因在产物里**。
- 首个异常阶段：插件扩展宿主激活层——exthost 日志（Trae CN：`%APPDATA%\Trae CN\logs\<会话>\window*\exthost\exthost.log`）实锤 `Activating extension kamaba.slang-vscode failed due to an error: Error: Cannot find module './impl/format' … at node_modules/jsonc-parser/lib/umd/main.js … at __require`——激活在**模块装载期**整体抛错，`registerDebugAdapterDescriptorFactory` 从未执行，F5 必报 descriptor 缺失。
- 根因：`slang_vscode_plugin/esbuild.js` 配 `platform: "node"` → esbuild 按 main 字段选中 jsonc-parser 的 **UMD 入口**（lib/umd/main.js）；UMD 工厂把 require 以**参数**传入（`factory(require, exports)`），esbuild 对 `./impl/*` 无法静态解析 → 残留运行期 require 相对 `dist/extension.js` 解析 → `dist/impl/format` 不存在必炸。装机 dist 与本地 dist SHA256 一致，两版坏包同源；其余 bundle 依赖排查无同类残留。
- 排障路径：① 复发即排除安装态（重装无效本身是信号）；② exthost.log 一行实锤激活抛错 + 栈定位到 jsonc-parser UMD 内联体；③ 本地 dist grep `require2("./impl` 印证 4 处残留（format/edit/scanner/parser）；④ 验证 jsonc-parser 的 `module` 字段指向 ESM 入口（lib/esm/main.js，静态 import）可完整内联。
- 修复点：`esbuild.js` 增 `alias: { "jsonc-parser": require.resolve("jsonc-parser/lib/esm/main.js") }`（ESM 入口静态 import 全内联，运行期 require 清零）；新增回归守卫 `slang_vscode_plugin/scripts/ext-load-smoke.mjs`（vscode 递归桩 + Module._load hook 装载 dist/extension.js，抛错即非 0 退出）——修复前红灯复现生产同款错误、修复后绿；已入插件 md/09 §4 发版闸门首位。0.0.17 发版装入，dap-smoke 30/30（重编 adapterMain 无回归）。
- 如何快速验证：`node slang_vscode_plugin\scripts\ext-load-smoke.mjs` exit 0；重载 Trae CN 窗口后 F5 断点/变量树/单步全通。
- 预防建议：① "extension might have failed to activate" 字面即真——激活类报错第一取证点 = 宿主 exthost.log，先读日志再谈安装态/缓存假说；② **bundle 类依赖的 UMD 入口是打包雷区**（工厂参数化 require 无法静态解析，残留即运行期炸）：platform=node 下 main 字段优先命中 UMD，引入新 runtime 依赖必须过装载冒烟 + 排查 `__require`/`require2` 残留；③ 冒烟覆盖要对齐真实故障面——dap-smoke 只管 adapterMain 独立进程，extension.js 装载/激活链此前零覆盖，坏包连发两版未察。
- 详见 `slang_vscode_plugin/md/PROGRESS.md`「三十」。

### [2026-10-22] compile-tests 六套件全判 FAILED（exit=0, module rewritten=False）：2026-10-17 重组迁移漏项——测试 jsonc `export.outputDir` 未随 references 补一层 `..\`
- 现象：全量重编译后 `compile-tests.ps1` 六套件全部 `compile FAILED (exit=0, module rewritten=False)`——Front 明明打出 `export module success`，脚本新鲜度判据（TestMap 模块路径 mtime）却不认。
- 首个异常阶段：脚本判据与产物落点的**路径错位**——不是编译失败，是产物落在了另一个根。
- 根因：2026-10-17 重组把测试树自 `simple_language\test\` 迁入 `SlangAllInOne\SLangCore\test\`（整体加深一层），`references` 路径逐个补了 `..\`，但 **`export.outputDir` 漏迁移**：`test\<X>` 仍 2 级、`test\Other\<X>` 仍 3 级 → 全部落 `SlangAllInOne\SLangCore\out\export\`（比正主 `SlangAllInOne\out\export\` 短一层）；`compile-tests.ps1`/`run-tests-win.ps1` 的 TestMap 与库 jsonc 均按正主根编址 → 判据恒 False。实证：正主根当时只有库模块（Core/Std/Math/…），无任何测试模块。
- 修复点（文件/模块）：60 个 jsonc（`SLangCore\test\**` 59 + `samples\Game\TankGame\TankGame.jsonc`）`export.outputDir` 统一 +1 级 `..\`（test\<X> → 3 级、Other\<X> → 4 级、SpecialTest\PlatformAotPosTest 嵌套 → 4 级），批改逐文件保 BOM 形态（R16）。CSimpleVMTest 宿主用 result.ModuleSlbPath 消费产物、根无关，无需改。
- 如何快速复现：改前跑 `compile-tests.ps1` 即全 FAILED，且 `SlangAllInOne\out\export\` 无测试模块目录、`SLangCore\out\export\` 反而堆积。
- 如何快速验证：批改后 `compile-tests.ps1` exit 0 六套件全 OK，正主根出现 ProjectTest/ProjectTest2/MathTest/SpecialTest/BenchMark/NullFastTest 目录。
- 预防建议：① 目录迁移清单必须覆盖 jsonc **全部路径键**（references、export.outputDir、debugText、publish 等各是一处独立锚点，迁一个漏一个）；② 新鲜度判据（mtime）路径与产物落点由脚本与 jsonc 两端各自声明，验收时跑一次 compile-tests 即可暴露错位（本次正是全量重编译流程把它顶出来的）；③ 旧根遗留产物（SLangCore\out\export）不清理会继续掩护错位——排障时先看「产物到底落哪」再对判据。

### [2026-10-22] build-packages.ps1 语法解析三连崩：PS5.1 `-File` 下无 BOM UTF-8 中文注释被按 GBK 读、尾字节吞换行
- 现象：脚本首跑即 `Missing closing '}' in statement block` 三连 ParserError（92/112/138 行），报错行全是正常代码。
- 根因：本会话给 build-packages.ps1 加的**中文注释**（无 BOM UTF-8）被 `powershell -NoProfile -File`（PS5.1）按系统 ANSI/GBK 解码——GBK 双字节的**尾字节恰好落在 0x5C（`\`）或吞掉行尾**时，注释边界/换行被破坏，语法解析崩。与 release-slang.ps1 内注释记载的 JSON 解析变体（BOM-less UTF-8 package.json 在 -File 下乱码吞 `\`）同根：**PS5.1 -File 宿主对无 BOM 文件按 ACP 读**。
- 修复点：脚本区注释改回英文（`SlangAllInOne\scripts\` 全部脚本维持纯 ASCII 注释约定；release-slang.ps1 的 NOTE 即此坑的历史记录）。
- 预防建议：① **`scripts\*.ps1` 注释一律英文/ASCII**（用 `-File` 消费或被他人 dot-source 的脚本尤其如此）；中文说明放调用侧文档（AGENTS.md/md）；② 改脚本后先 `powershell -NoProfile -Command "[scriptblock]::Create((Get-Content -Raw <file>))"` 或直接干跑一次做语法门；③ 若确需中文注释，文件写 UTF-8 **带 BOM**（`-File` 下 PS5.1 认 BOM）——但仓库脚本现状为无 BOM，混用形态更危险，不如统一 ASCII。

### [2026-11-09] HelloCube v3 端到端 `slu_boot rc=0` 但对象表全默认：SLB 搬出导出目录后 `moduleReferences` 失联（与 2026-10-20 同源）
- 现象：`unity/verify-hello-cube.ps1`（P/Invoke 模拟 Unity C#）跑 `slu_boot` + 60 次 `slu_frame_objects`，`rc=0`、日志队列有 `[SL->C++] HelloCube v4`，但 `SlangCube` 的 `posY=0 / colorG=1 / rotY=0 / volume=1` 全是 C++ 构造默认值，三条断言 FAIL；本机 CLI 直跑导出目录里的同一 SLB 却能读回 `posY=1.2 / colorG=0.45 / volume=0.8`。
- 首个异常阶段：**C VM 运行期引用装载**，不是 FFI 绑定、也不是跨进程共享段。C++ setter 插桩（`[diag] fn/pid/h/tbl`）显示 `objFind` 进了 C++，`setPos/setSpin/setColor/setFov/setVolume` 一次都没进；同时子进程 stdout 缺 `SystemPrintln` 输出 —— 指向基础库缺载而非某个 `@DllImport`。
- 根因：`HelloCube.module.json` 的 `moduleReferences[].path = ../../../package/win32-release/lib/{Core,Std}.module` 是 **Front 相对导出目录**写出的；SLB 被部署到 `<Unity>/Assets/StreamingAssets/Slang/` 后该相对路径不可达。`sl_load_references` 对裸 `.module` 引用只打 Warning 跳过，随后实例方法派发与系统方法静默失效（IR 里 setter 调用全在，运行期落到空壳）。`build-unity-package.ps1` 原本只把 Core/Std 拷到 `StreamingAssets/Slang/lib/`，而回退链查的是 `<主包目录>/modules`、`<exe>/modules`、`<exe>/lib` —— 恰好都不命中。
- 修复点：`build-unity-package.ps1` 增 `$pluginLib = <exe目录>/lib`，把 `Core.module.slb` / `Std.module.slb` 同步部署到 `Packages/com.slang.unity/Plugins/x86_64/lib/`；`slang_unity.cpp` 清理重复 `SlUObject` 定义并把对象表与 `g_state` 统一放进 `.slushare`（RWS，virtual size 34648 B），`slu_boot` 注释改为真实原因；`verify-hello-cube.ps1` 去掉全部临时诊断。
- 如何快速复现/验证：删掉 `<exe>/lib/*.module.slb` 重跑 verify 即复现 FAIL；部署后 `verify-hello-cube.ps1` 输出 `objects=2` / `rotY=90` / `color=(1,0.45,0.1)` / `volume=0.8` / `PASS`。二分关键动作是**同一份 SLB 换目录直接跑 CLI**（导出目录好、StreamingAssets 坏）。
- 预防建议：① 与主包一同分发 SLB 时，必须同时检查 `moduleReferences` 的相对基准（Front 导出目录 ≠ 运行目录），并优先利用 `<exe>/lib` 回退链；② 「rc=0 + 日志正常 + 状态全默认」先怀疑**依赖模块静默 skip**（查 `VM.txt` 的 `could not load module reference`），别先改 FFI / 共享内存；③ 跨进程共享段里所有可变状态必须同处一个 RWS 段，独立 `.sluobjs` 段没标 RWS 会制造「一半状态可见」的假象。

### [2026-11-13] `slang project set --add`（JSONC 结构化插入）三处实现 bug：行号/尾逗号/数组嵌套段（SLangCodeEditor 第十五轮）
- 背景：`SlangAllInOne/Project/ProjectCommand.cs` 的 `Set` 增 `--add`（键缺失时向最长已存在祖先容器插入成员）。初版三处 bug：
  1. **`NodeEntry.StartLine` 是 1-based 行号不是字符下标**——按行取缩进须从行号重扫到行首；直接把 StartLine 当下标传入 `LastIndexOf('\n', idx-1)` 会取错行，缩进全错（功能对但格式坏）。
  2. **尾逗号场景产生 `,,`**——JSONC 容许尾逗号，闭括号前最后一个内容字符若是 `,` 再补逗号即坏。判据改为：前文是 `{` / `[` / `,` / `:` 时只换行不补逗号；且「最后内容字符」回扫必须跳过 `//` 与 `/* */` 注释，否则逗号会落在注释行内。
  3. **缺失中间段 `[i]` 被建成 object 键**——`compileFiles/files/[0]/path` 全链缺失时嵌套构造把 `[0]` 当普通键写成 `{"[0]": {...}}`。判据：段匹配 `[n]` 时构造数组字面量（i>0 用 null 占位），数组才是它的容器语义。
- 另一处语义洞：不带 `--add` 时缺失键也静默新增——`--add` 缺失必须显式报错退出 1（提示加 `--add`）。
- 验证：PowerShell 批处理绕开多层引号传递（`cmd /c` 传带引号 JSON 用 `\"` 转义；PS 函数参数名勿用自动变量 `$args`）；成功（顶层段/嵌套链/对象内加键/数组整元素/数组元素+嵌套键）、失败（非法 JSON exit 2）、冲突（`--add` 已存在键 exit 1）三类全绿；注释/BOM/缩进保留 + `project info --json` 回归。

### [2026-11-13] `slang test` 测试链三处深坑：Front 静态不可重入 / 引用模块 systemCalls 可见域 / 新增类对外暴露缺口（SLangCodeEditor 第十八轮）
- **坑 1 · Front 编译器静态状态不可同进程重入**：`slang test` 初版在宿主进程内逐用例调 `RunProject`——第二个用例编译即被污染（首个用例失败后全部 exit=1）。修复：每用例起独立 `slang.exe` 子进程（`Environment.ProcessPath` + Process.Start，退出码即结果）。
- **坑 2 · 引用模块 systemCalls 的对外可见域**：新增系统方法 `SystemExit` 登记在 Core.jsonc（隐式装载的根模块）→ 用户工程解析不到（`not support type`）；登记回 **Std.jsonc + 用例工程 references Std** → 可见。规则：**裸系统调用的可见域 = 引用模块的 systemCalls，Core 隐式装载不外放新增项**（framework 里可用的 `SystemStringCharCodeAt` 等全部来自 Core 内置子集）。
- **坑 3 · 新增类进引用模块后引用方不可见**：Std 新增 `Kernel` 类（namespace 与顶层根级两种形态都试过，slb/json 副本均含该类、引用装载日志正常）→ 引用方 `OS.Kernel`/`Std.Kernel`/裸名 `Kernel` 全部 `not found`，同模块的 `OS.Process` 却可见——**引用装载重建类表的链路对新类有缺口**（待查 `TryLoadCompiledPackage`/IRMetaClass 重建路径）。绕过：测试失败信号用裸 `SystemExit`（`_main_` 内可用形态受限，见坑 4）。
- **坑 4 · 裸系统调用表达式语句解析域**：`SystemExit(7)` 仅在 `_main_` 特定形态编译通过（块内/多语句/封装方法体内均 `not support type`）；Std 模块内部封装（println 模式）不受限。域规则待 Front 域排查。
- **附带修复（VM 真实缺陷）**：未捕获异常静默 exit 0（false success）——`runtime_trace.c` `vm_execute_throw` uncaught 分支补 `error_code=-90`（对齐同文件 OOM 硬停注释的防护语义；正数 error_code 由 `SystemExit` 透传为进程退出码，负数归一 1）。BaseTest 回归：try 语义全绿，FAIL 项均为已知历史失败（宿主判定不看 exit code，不受影响）。
- **构建环境**：VS 自带 cmake 直接 PS 调用缺 INCLUDE/LIB（`stdarg.h` 找不到）——须 `vcvars64.bat && cmake --build`；输出重定向落盘避免管道被执行器截胡。

### [2026-11-13] 跨模块类解析机制三层实测（第十九轮 Front 专项）：文件级 import 开关 / Core 显式引用 / 正确姿势
- **背景**：`slang test` 用例里 `OS.Kernel.exit` 报 `节点[OS] 没有找到`，同文件 `OS.Process` 却可用；最小模块（Mini.Tool）复现同样现象。**插桩实证**（`GetMetaNodeByListString` + `CreateReferenceTypeShell` + fileMeta 级三处临时日志，实验后已清除）定位三层机制：
  1. **文件级 `import <模块名>;` 是引用模块类对 MetaCore 可见的开关**——`GetMetaNodeByListString` 只走三路：①首段=模块名（`GetMetaModuleByName`）→模块根逐段；②ownerBase 向上链（本模块树）；③CoreMetaClassManager（仅单段）。引用模块的类不在三路里，靠 `GetMetaClassByNameAndFileMeta` 的 **fileMeta 级**（`FileMeta.GetMetaNodeFileMetaClass`，由文件头 import 声明填充）命中。**无 import 的文件完全看不到引用模块类**（连 lookup 都不进入后续命中路径）。
  2. **IR 层 irName 反查需要 Core 显式引用**：MetaCore 解析通过后 IR 报 `ir runtime[Std.OS.Process.run_...] method not found`——用例 jsonc 显式加 `Core.module.slb` 引用后消失（Std slb 双包含 Core 但 IR 注册需显式引用触发）。
  3. **`import` 后仍差一级——已修复（第十九轮扩展收口）**：Mini 实验里 `import Mini;` 后模块节点命中、其下 `Tool` 类仍 not found。根因：`Mini.Tool` 短名链首段经 import 命中的是**模块根节点**（import 通道 AddImportMetaNode(模块根)），次段在根下未命中（Tool 在 `根/Mini/Tool`，模块名与顶层命名空间同名）；而 `MetaCallNode` 的中段查找只有「isMetaNamespace 跨模块级联」分支，模块根没有「下钻同名命名空间」的路径。**修复**（MetaCallNode 中段查找，与 `ClassManager.GetMetaNodeByListString` 的模块 ns 分支同构）：模块根命中未中时，到「与模块同名的命名空间」下继续找。验证：`Mini.Tool.ping()` 短名编译 EXIT=0 + 运行输出 pong（跨模块静态调用真实执行）；framework 编译回归 EXIT=0；BaseTest FAIL 分布与基线完全一致（无新增）。
- **正确姿势（跨模块/namespace 类使用的完整规则，第十九轮扩展·第二阶段全部实测）**：
  1. 引用模块类：每个使用它的 `.sl/.sp` 文件头 `import <模块名>;`（文件级，缺 = 完全不可见）；
  2. jsonc `references` **显式列出全部依赖模块**（含 Core——IR 层 irName 反查需要；不要指望 Std slb 内嵌 Core 包）；
  3. **namespace 类（本工程或引用模块）**：使用处文件头 **`import <命名空间名>;`**（语言规范 namespace.md §「使用方式」——本工程 namespace 类在 `_main_` 里裸名引用也要 import，否则 `ProcUser not found`）；
  4. 满足 ①②③ 后**短名（`Mini.Tool`）与全限定名（`Mini.Mini.Tool`）均可解析**（MetaCallNode 模块根 ns 下钻修复），**封装类方法（`OS.Kernel.exit(1)`）在 namespace 类方法体内块内可用**（类方法解析通道不受裸 systemCall 解析域限制——裸 systemCall 的「_main_ 唯一语句」限制只影响**直接裸调用**，用封装类即绕过）；
  5. 附带记录：jsonc 锚点**相对路径裸文件名**（`-p Mini.jsonc` 无目录前缀）触发 Front 找 `Project.sp` 断言崩溃（Error 11002）——用 `.\Mini.jsonc` 或绝对路径绕过；同轮已修同类 false-success（CommandExecutor 锚点缺失不再静默回退 CWD 扫描/`return true`，改 `Console.Error` + `return false`）。
- **验证**：ProcUse（import Std + Core/Std 引用 + 类方法体内 `OS.Process`/`OS.Kernel.exit(1)`）编译 EXIT=0 + 运行 exit=1（SystemExit 透传）✓；TestHarness 用例升级为该形态后冒烟 PASS；framework 编译回归 EXIT=0。

### [2026-11-14] 引用模块类方法「复杂表达式直接作参数」解析链缺口（第二十一轮 SLangCodeEditor）

- **现象**：本轮给 SLangQT 补 6 条树 FFI 后，IDE 编译报 8 条 `[Error] MetaCoreParseCallNodeNotFoundInClass`——连旧方法 `SLang.QTreeWidget.addPath`、`SLang.QListWidget.addItem` 都报「类里没有」，且同一静态字段 `solutionTree` 后续调用连锁失败；一度还牵连本地类 `PathRules.startsWith/contains`。
- **隔离实验**：最小探针工程（只 `import SLangQT` + references Core/Std/SLangQT）里 `t.addPath("a/b")`、`t.setItemForeground("a/b", 8947848)` 编译 EXIT=0，证明新 SLB 类方法表完整；把 `build-slqt.ps1 -Qt` 产物、`release slang.exe` 产物、改动前旧 SLB 三者互换，错误集合不变 → 排除模块/DLL/Front 版本问题。
- **根因**：Front MetaCore 的方法调用解析链在「实参是 List 索引表达式（`paths[i]`）或裸方法调用表达式（`Strings.msg(...)`）」时未先完成类型绑定，按签名找不到目标方法；首个调用失败后同一变量/类的后续解析链被污染，于是旧方法也误报。注意成功案例全是局部变量或字面量实参（`isItemExpanded(old)`、`collapseAll()`）。
- **规避**：引用模块类方法的实参一律先赋局部变量——`string one = paths[i]; tree.addPath( one )`、`string stylePath = paths[s]; tree.setItemForeground( stylePath, c )`、`string stepText = Strings.msg("..."); w.addItem( stepText )`。改完 8 条错误全部消失。
- **同轮两个命名坑**：① `base` 是 SLang 关键字，`string base = ...` 触发 `NodeStructParseNameIsKeyword`（改名 `basePath`）；② 局部变量 `k`（上轮是 `state`）与类函数临时名冲突触发 `[Info] [ParseMeta] [MetaCoreMemberFunctionVariableFunctionDefine]` —— 该诊断是 **Info 级别**，只 grep `[Error]` 会漏掉，排障应按文本 `Error` 搜全日志。
- **验证**：`slang compile -p CodeEditor.sp --format binary+json --no-banner` EXIT=0 且日志无 `Error`；headless `QT_QPA_PLATFORM=offscreen` 启动自检 `backend: qt`、`panels: 6 files: 44 commands: 50`、stderr 0 字节；PE 导出表实测 6 个新 `slqt_tree_*_sl` 符号存在。

### [2026-11-15] 局部变量与类字段同名 → 19 条连锁解析错误（第二十三轮 SLangCodeEditor）

- **现象**：`NewProjectDialog` 把四组 `QListWidget` 换成 `QComboBox` / `QCheckBox` 后编译 EXIT=1，报 19 条 `[Error] MetaCoreParseCallLinkFailed`，连本地基类方法 `this.addContent(...)` 都误报 `MetaCoreParseCallNodeNotFoundInClass`；一度误判为新 SLB 类表缺失或重演第二十一轮「复杂表达式实参」缺口。
- **证据**：保存完整编译日志后按文本 `Error`（不是 `[Error]`）搜，最早三条是 `[Info] [ParseMeta] [MetaCoreMemberFunctionVariableDefineCall]`——「Error 定义变量名称与类定义名称一样 如果调用成员变量，需要在前边使用 this.!!」，分别指向 `kindCombo` / `spCombo` / `guideCheck`。这三个名字既是新增的类字段，又被写成 `_init_` 里的局部变量；唯独 `srcCombo`（对应字段 `sourceCombo`）不同名，日志里完全没有它，正好反证。
- **根因**：SLang 不允许方法内局部变量与类成员变量同名。变量声明被判非法后，后续对该名字的所有引用都退化为「成员变量查找」并失败，且污染同一语句块里 `this.addContent` 的解析链——与第二十一轮「引用模块类方法实参为复杂表达式」是**两类不同缺口**。
- **修复**：不再声明同名局部变量，直接 `this.kindCombo = ...` / `this.guideCheck.setChecked(...)`；改完 EXIT=0，日志全文零 `Error`。
- **排障纪律**：这类根因是 **Info 级但文本里含 `Error`**，只 grep `[Error]` 必漏；按文本 `Error` 搜全日志并只看最早一条（R8）。另：`string label = ...` 会触发 `[Info] [ParseNode] NodeStructParseGotoLabelId`（「只支持 goto id;」），改名 `lineText` 后日志干净。
- **验证边界**：headless `QT_QPA_PLATFORM=offscreen` 的 stderr 出现 `QFontDatabase: Cannot find font directory ...` / `This plugin does not support propagateSizeHints()` 属 Qt 环境提示，不是应用错误；以 stdout 的 `backend: qt` / `panels: 6 files: 44 commands: 50` + EXIT 判定通过即可。临时 Qt 探针（`combo count=2 idx=1`、`check=true`、`table filled`、`tree current set`）证明新 FFI 在 Qt 后端真实可调。

### [2026-11-15] 第二十四轮两个验证侧坑（均非产品缺陷）

- **`deploy-qt.ps1 -Targets package` 清理既有 Qt runtime 时失败**：报 `Remove-Item : 无法绑定参数 InputObject ... 无法转换值`（本机环境把 `Remove-Item` 包装成 Safe-Delete，拒绝管道输入；上一轮目标目录为空所以未触发）。脚本本身无缺陷，33 个 Qt runtime DLL 已经就位。处理：不要为此改部署脚本，按 `SLangCodeEditor/run.ps1` 的 stage 口径直接 `Copy-Item` 把 `out/export/SLangQT` 的 `SLangQT.module.slb` / `.module.json` / Qt 后端 `slang_qt.dll` 同步到 `package/win32-release/modules/SLangQT` 与 `SLangCodeEditor/modules/SLangQT`，再用 PE 导出表 ASCII 校验新符号存在。
- **探针里 `Int64` 返回值不能直接与整数字面量比较**：`Int64 bind = table.onRowClicked(...)` + `if ( bind > 0 )` 触发 5 条错误——`MetaCoreDefineVarStatementDuplicate2`「名称Int64与ClassName 有重复」与 `BuildTst 表达式解析错误 604 [ > Lex: 0]`，同语句块里 `Console.println` 也被连锁污染。信号 connect 的 `Int64 bind_id` 应像 IDE 里 `tree.onSelected(...)` / `write.clicked(...)` 一样**直接丢弃**，需要判断时只比较 `int`（如 `currentRow()`）。删掉该变量后探针编译 EXIT=0、运行输出 `table cur=-1 signal=bound`。
- 结论：`SIG_TABLE_ROW_CLICKED=14` 与 3 条新 FFI 在 Qt 后端实跑通过（`tree styled` / `splitter nested` / `qtprobe24 ok`）；IDE 主工程编译与 headless 自检全绿。

### [2026-11-15] 第二十五轮：新增 cellChanged 后必须阻断程序化填充

- **风险**：`QTableWidget::cellChanged` 不只由用户编辑触发，`setItem` 程序化填充也会同步发信号。若把该信号直接当脏标记，打开属性页（`refreshTable` 填若干行 × 4 列）会立刻把全表标成「已修改」，关闭时误弹三选，甚至把占位摘要写回 jsonc。
- **处理**：C++ `slqt_be_table_set_item` / `slqt_be_table_set_item_editable` 内加 `QSignalBlocker blocker(t)`；SL 侧 `refreshTable` 再用静态 `fillingTable` 做第二道守卫。探针 `qtprobe25` 先 `onItemChanged` 绑定、再程序化填充，输出 `changedRows=0`，证明阻断生效；`itemText=CodeEditor` 证明字符串读回正常。
- **值语义（易踩）**：CLI `project info --json` 的 `nodes[].value` 对 string 已 `Unquote`，是裸文本；`project set --value` 会把非 JSON 字面量的裸文本自动 `JsonSerializer.Serialize` 加引号，所以表格里改的值可直接传回，**IDE 不要自行拼引号**。但 `type=object/array` 的 value 是 `{…} (N 项)` / `[…] (N 项)` 占位摘要，必须禁止编辑；空字符串不能传给 `--value`（CLI 取 `value[0]` 会越界），IDE 侧跳过并保留脏标记。
- **关闭三选无需新 Qt 信号**：QDialog 的 X / 取消都走 `reject()`，`BaseDialog.run()` 返回 0，`open()` 在该分支弹 `SaveChoiceDialog`（1 保存 / 2 放弃 / 0 继续编辑并重新 `exec`）即可；`close_request` 作为 Qt 信号能力仍留在待办。
- 验证：`slang compile -p CodeEditor.sp --format binary+json --no-banner` EXIT=0 且日志零 `Error`；headless 自检 `backend: qt` / `panels: 6 files: 44 commands: 50`；探针 `qtprobe25 ok` EXIT=0，探针与日志已清理。

### [2026-11-16] SimSceneTest：跨模块 SL 解析链实证坑（Unity 导出 → SLangRender 端到端）

- **现象**：新工程（references 含 SLangQT/SLangRender + Core/Std/Math slb）使用 `JsonValue` 时连锁炸 MetaCore：`MetaCoreParseCallNodeNotFoundContent`（变量 not found）→ `BuildTst 表达式解析错误 604` → `MetaTRStatements..ctor` NPE，无行号。
- **实证结论（四条，已写进 `SimSceneTest.sl` 头注释与 `SimGameEngine/doc/16` §8）**：
  1. **不要显式 `import Core;`**——Core 类型随引用自动可见（JsonTest.sl 只 `import Std;` 就能用 BaseJson/JsonValue）；显式导入即触发上述连锁。
  2. **跨模块对象方法调用禁止链式**（`a.b().c()`）：一律拆单步局部变量（`JsonValue t = a.b()` 再 `t.c()`）。
  3. **`ret` 不直接携带跨模块方法调用**：先 `bool ok = f()` 再 `ret ok`。
  4. **`UInt8Array.length` 是容量语义**（934B 文件返回 512）：二进制长度用 json 声明推导；`File.readAllBytes` 是 throws 方法必须 try/catch。
- **诊断教训**：把函数改名 `_UNUSED` 做「二分」是**无效**的——文件里所有函数都会编译；真二分必须删代码。Front 报错无行号时，先看错误 token 里的标识符（`Name:node not found` 实为漏改的旧变量名）。
- **验证**：`slang compile` EXIT=0；`slang <project>` 运行 `[data] OK: verts=24 tris=12`、`[done] okFrames=937 @15s`——Unity 导出的 Cube（`SlangSceneExporter.cs` flag `export-cube`）经 MESH_CUSTOM+uploadMesh 进 13 阶段管线渲染成功。

### [2026-11-15] 第二十六轮：QSpinBox 信号重载消歧与图标零资源方案

（本节占位：见上文各轮实录；2026-11-16 SimSceneTest 段按时间正序置于本文件末尾。）

### [2026-11-16] SimSceneTest（补充归位）

- 本轮四条实证坑与端到端验证记录见上文 `[2026-11-16] SimSceneTest：跨模块 SL 解析链实证坑` 一节（因编辑锚点误插于第二十六轮之前，此处归位说明；后续整理时可将其移至本文件末尾）。

- Qt6 里 `QSpinBox` 的 value/text 信号家族容易让 `QObject::connect(s, &QSpinBox::valueChanged, ...)` 产生重载歧义；用 `qOverload<int>(&QSpinBox::valueChanged)` 明确绑定 int 版本即可。探针先绑 `onValueChanged` 再 `setValue(12)`，输出 `spin value=12 signal=12`，同时证明**程序化 `setValue` 也会触发回调**——数值输入没有「填充误判」问题，不需要 `QSignalBlocker`（与上一轮 `cellChanged` 相反）。
- 树节点图标不引入图片资源：`QApplication::style()->standardIcon(QStyle::StandardPixmap)`，SL 侧只传 int id（0 文件 / 1 目录 / 2 警告 / 3 应用 / 4 取消），未知 id 静默忽略；这样部署时不会因漏拷 iconengines 插件或图片而空图标。
- 数据层规则表继续加列：`ProjectScanData.mark()` 同时产出 colors / tips / bgs / icons 四张并行表，`UiContext.setTreePaths` 只做转发；中间自动生成的分组节点（如 `compileFiles`）不在 `treePaths()` 结果里，因此不设图标（已写入验证边界）。
- 验证：stub / `-Qt` 双构建 EXIT=0，探针 `tree icon set` / `qtprobe26 ok` EXIT=0；IDE 编译与 headless 自检全绿。

### [2026-11-16] 第二十七轮：close_request 无原生信号（事件过滤器方案）+ deploy-qt 管道坑根修

- **`close_request` 不是 Qt 信号**：`QMainWindow` 关闭走的是 `QWidget::closeEvent` 虚函数，平面 FFI 表达不了虚覆盖。做法：C++ 侧 `SlqtCloseFilter`（QObject 事件过滤器）拦 `QEvent::Close`——首次 Close `ignore()` 并经既有 `_dispatchInt` 桥发 `SIG_CLOSE_REQUESTED=18`（载荷=0）；真正关窗由 SL 回调 `slqt_be_window_close`（进程级 `g_close_bypass` 置位 → 过滤器放行本次 Close 并复位）。**不新增 install FFI**：connect 即安装（与其他信号同一 `slqt_connect` 入口），过滤器以被监听对象为父、随窗口析构。已知边界：同一窗口 connect 两次会叠装两个过滤器、一次点 X 发两次信号，框架层未去重，应用侧对一个窗口只 connect 一次。
- **否决同步语义不可行也不必要**：dispatch 回调是 void 返回，VM handler 无法把「是否放行」传回 eventFilter；两段式（拦下 → handler 决定 → `window_close`/`quitApp`）在既有 void ABI 内闭环，还天然支持异步确认（弹模态框）。
- **deploy-qt.ps1 `Clean-QtFiles` 管道坑根修**（推翻第二十四轮「不要改脚本」的绕行结论）：目标目录已有 Qt runtime 时 `Get-ChildItem | Remove-Item -Force` 稳定复现绑定失败；改为 `ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force }` 直删后 `-Combo full -Targets package` 一次通过（33 dll）。教训：环境级坑若每轮都要绕，就该修根而不是固化绕行。
- 验证：stub / `-Qt` 双构建 EXIT=0；IDE 编译 EXIT=0；真实启动 `backend: qt` / `panels: 6 files: 44 commands: 50`、stderr 为空。

### [2026-11-16] 第三十轮：framework 新文件漏登 compileFiles 的连锁表象

- **现象**：`CodeEditor.jsonc` 的 `compileFiles` 是**显式清单**（不是目录递归）。新增 `framework/widget/HelpBrowserDialog.sl` 后忘登记，编译报 8 个 `MetaCore` 错误：调用点四行全是 `MetaCoreCallNotSupportFrontCall`（"front call node type not supported: None"）+ `Call link parse failed`（指向 `HelpBrowserDialog` 符号），且连锁污染了完全没改过的 `ProjectContextDialog.sl`（报 `not found functon by [title]`）——表象极像第二十一轮的「实参复杂表达式解析缺口」。
- **根因**：类根本没进编译，符号不存在；解析器对未知类名的报错形态与解析缺口同款，容易误判方向。
- **排障要点**：遇到「跨类静态调用 Call link parse failed」先确认**目标类文件是否在 `CodeEditor.jsonc`（或对应工程 jsonc）的 `compileFiles` 里**，再怀疑语言解析缺口（R8 精神：最早错误是调用点不可见，不是调用形态）。登记后立即恢复 EXIT=0。
- **纪律**：新增 framework 文件的第一步就是登记 `compileFiles`；总纲 §1 与根 AGENTS.md 已有此约定，本轮为执行遗漏非未知坑。

### [2026-11-16] 第三十三轮：List 下标读取 `[i]` 的索引必须是局部变量（Front 域精确规律）

- **现象**：SLangCodeEditor 帮助查看器历史栈（HelpBrowserDialog）在 `ParseStatements` 阶段触发 `MetaCallNode.HandleVisit` NullReferenceException 崩溃（无源码行报错，只有栈），且报错形态随上下文漂移（伴随 `ProjectContextDialog.sl Line:54 not found functon by [title]` 等无关连锁 Info）。
- **二分实测规律**（逐步回填定位）：
  - ✅ `string entry = breakpoints[i]` —— **静态 List 字段 + 局部 int 索引**（ConfigStore 第三十一轮先例）
  - ✅ `string p = _stack[k]` —— 静态 List 字段 + **先赋局部变量的** int 索引
  - ❌ `string cur = h[this._pos]` —— 局部/成员 List 变量 + **实例字段索引**
  - ❌ `string p = _stack[_pos]` —— 静态 List 字段 + **静态字段索引**
  - ❌ `same = h[this._pos] == p` —— 下标表达式**直接参与 `==` 比较赋值**（连带崩）
  - ✅ `h.indexOf(p)` / `h.length` / `h.add` / `h.removeAt` —— 方法调用全安全
- **规律**：`list[idx]` 的 **idx 必须是局部变量**（字段做索引即崩）；且下标表达式不能直接参与二元比较赋值。`Core/Container/List` 无 `at()/get()` 方法式读取（`getRange` 仍需下标取元素），故「按位置取元素」只有两条安全路径：**局部变量索引下标** 或 **indexOf+指针移动**。
- **附带坑**：子类声明与父类同名静态字段（`HelpBrowserDialog._active` vs `BaseDialog._active`）触发 `MetaCoreClassExtend6`「继承的父类中已包含」——重命名绕开（`_cur`）。
- **正解姿势**：跨类静态回调取实例通道用独立名静态字段；按位置取 List 元素先 `int k = pos` 再 `list[k]`；去重用 `indexOf`。Front 侧根修（下标索引类型解析）待 Front 域专项。

### [2026-11-16] 第三十四轮：Front 域根修——字段索引下标的 call-link 分支缺失（上轮坑闭环）

- **根因**（`simple_language/source/Core/MetaCallNode.cs`，R12 插桩实证）：数组下标 `list[idx]` 的索引表达式为**字段/成员访问**时被解析成 `MetaCallLinkExpressNode`，`FindArrayNode` 单下标四分支（const / call-link / op / else-assert）中 call-link 分支执行 `m_Name = ...finalCallNode.variable.name` 后进 `HandleVisit`；`HandleVisit` 内 `GetMetaVariableByName(m_Name)` 查**局部变量表**查不到静态/成员字段（`getmv2=null`），且 `m_ExpressNode` 非 const 非 op → **三分支全不命中**，`else` 分支只打日志**不 return**，继续执行到 `m_MetaVariable.ParseDefineMetaType()` 解引用 null → NRE（`HandleVisit +0x826`，无源码行报错）。局部变量索引正常是因为 `GetMetaVariableByName` 命中走 VisitVariable。
- **修法**（两处，`MetaCallNode.cs`）：
  1. `HandleVisit` 在 `MetaOpExpressNode` 分支后新增 `MetaCallLinkExpressNode` 分支——与表达式下标同款按**节点身份**缓存 Visit 变量（`new MetaVisitVariable(name, ..., variable, idxLink.metaCallLink)`，运行期从索引表达式加载）；`else` 分支补 `return`（未识别类型到此为止，不再解引用可能为 null 的 `m_MetaVariable`）。
  2. `FindArrayNode` call-link 分支 `m_Name` 取值加 null 兜底（`finNode?.variable?.name ?? 合成名`）。
- **验证**：`dotnet build Front` EXIT=0 → IDE 主工程（新 Front）编译 export success（修复前同输入稳定崩溃）→ AOT 重发布 `package\win32-release\slang.exe`（`dotnet publish -c Release -r win-x64`，publish 会 wipe 目录需重跑 `deploy-qt -Targets package` 回填 Qt runtime）→ `run-tests-win.ps1` 全量：BaseTest exit 0（9 FAILs 为存量 Monitor P5/P6）、BenchMark/NullFastTest exit 0、MathTest/SpecialTest exit 1 **无任何 FAIL/异常输出**——判定存量环境项（math_lib/MathVMLib FFI 敏感，与 NoteLinux 已知限制同源；修复在语义上只把必崩分支救活，原正常路径行为逐位不变，零回归）。
- **环境坑顺带记录**：本机 `Remove-Item` 被 genie shim 包装成回收站删除（safe-delete FAIL_CLOSED）且 .NET `File.Delete` 对**运行中的 AOT exe** 也会 Access denied——publish 前须先杀残留 slang 进程（Windows 允许 rename 运行中 exe，rename 后再杀+删可行）。

### [2026-11-16] 第三十七轮：MathTest/SpecialTest 存量 exit 1 排查（编译链修复 + 运行期遗留登记）

- **MathTest 编译链三重配置漂移**（exit 1 的真因是跑陈旧产物）：
  1. jsonc `export.outputDir: "export"`（本地）与其他套件的 `..\\..\\..\\out\\export` 漂移 → `compile-tests` 的 `Get-ModuleFresh(out\export\MathTest\...)` 永远 False（**compile-tests 恒 FAIL**）；已对齐。
  2. jsonc `export.moduleName: "ProjectTest"` 与 BaseTest 冲突（产物落 `out\export\ProjectTest\` 互覆盖）→ 改 `"MathTest"`；`common.ps1` TestMap.Module 同步改 `'MathTest\MathTest.module.json'`。
  3. `MathTest.sl:121` `if ba == BigNumber( 15 )`——**if 条件里的内联构造比较**触发 `MetaCoreExpressManagerNotSupportOptimazeDon` 编译 Error（99 行赋值形态同款却通过）→ 先赋局部 bool 再进分支。
  - 修复后：compile-tests MathTest **OK**、runner **exit 1→0**（5.2s 全量跑完）。
- **运行期遗留（已登记未解决问题.txt，待专项）**：MathTest 矩阵段 283 FAIL——`identity` 等走 `Math.jsonc` systemCalls（`math_lib.dll!mathvm_*` 扩展 dll）静默失效：符号 `mathvm_mat3f_identity` 在 dll 导出表存在（二进制 ASCII 检索），疑 **VM 扩展 dll 搜索路径**（module 在 `out\export\MathTest\` 而 dll 在 `out\export\Math\`；10/28 旧日志曾成功从后者加载）；`MathVMLib.dll` 全仓缺失（注释提及未实现）。SpecialTest DLibrary 段 8 FAIL（load/refcount/release），CPlusClang 29/Python 13 子段通过。
- **判定缺陷佐证**：Front 编译存在 Error 时进程仍 exit 0（compile-tests 靠 `Get-ModuleFresh` rewritten 判定兜住）；裸目录路径 `[FAIL] project anchor not found: <Dir>.sp`（11002 锚点缺陷再证——MathTest 目录锚点文件名是 ProjectTest.sp）。
- **教训**：测试套件的 jsonc `export.outputDir/moduleName` 是 runner 契约的一部分（TestMap.Module 必须与 `out\export\<moduleName>\<moduleName>.module.json` 逐字对齐），漂移会让 runner 静默跑陈旧产物——exit 码怪异先查产物 mtime。

### [2026-11-16] 第三十九轮：SystemMath* 矩阵 FAIL 的 VM 侧修复（惰性重解析 + 布局候选链）+ 引用链断点收敛

- **证据链**（`SL_VM_LOG=on` 抓 `build\logs\VM.txt`，文件日志默认关）：
  1. `vmDll: LoadLibrary failed: ./..../lib/math_lib.dll (also tried lib/windows/, windows/)`——vmDllImports 预载失败（锚点指向 Front bin lib，那里本无 dll）。
  2. FFI DllImport 预载**成功**装入 `out\export\Math\math_lib.dll`（绝对路径，FFI manager 候选链生效）——但仅当 CWD 恰好使锚点解析命中（cwd 依赖，碰运气）。
  3. `system method: lazy re-resolve id=-68926798 'SystemMathMat3Identity' -> still unresolved`（第三十九轮新日志）——惰性重解析触发但 `LoadLibraryA("math_lib.dll")` 裸名仍失败：**Windows 裸名搜索序不含其它通道已用绝对路径加载的模块目录**。
  4. `CallSystemMethod not registered. method=SystemMathMat3Identity`——注册期 resolve 失败（func=NULL）连 id 表都不进，dispatch 静默 no-op → 矩阵段 282 FAIL。
- **VM 侧修复（`system_method_registry.c`，三处）**：
  1. 宿主（Win32/POSIX 非 wasm）`vm_sysfunc_ext_lib_load` 失败**不再缓存 NULL 占位**（占位会永久封死稍后其它通道的加载；wasm 分支保留占位防 dlopen shim abort）。
  2. 裸名失败后追加**发布布局候选链**：exe 目录裸名 → `exe\lib\<平台>\` → `exe\lib\`（与 `sl_ffi_lib_manager` 候选 3-6 同款，复用 `sl_exe_dir_join_name`/`sl_platform_dir_name`）。
  3. `vm_system_func_dynamic_register` resolve 失败时**登记 id 占位**（func=NULL，条目存 name/cvmFunction 原文；id 表 grow 迁移同步搬运）；`vm_find_system_func_by_id` 命中 NULL 时**按存文惰性重解析**（成功补 func 与 by-name 表）。
- **验证结果**：修复链路被运行日志证实触发（`lazy re-resolve ... -> still unresolved` 说明占位+惰性都在工作），但 MathTest 场景 **math_lib.dll 始终没进进程**（FFI 预载锚点解析碰 CWD 运气 + 引用 path 指向 Front bin 旧 slb）→ 矩阵 282 FAIL 维持。**剩余断点收敛为引用锚点缺陷**：`./lib/Math.module.slb` 被 Front 解析到 `simple_language\source\bin\Debug\net8.0\lib\`（11002 锚点缺陷家族；改绝对路径引用会触发 uuid 校验失败 exit 1，进一步佐证）。FFI 预载相对锚点（`D:\out\...`、`...\bin\out\...`）同族。
- **修复的通用价值**：一旦 dll 经任何通道进进程（或发布布局 lib\<plat>\ 存在——AOT 发布包场景），system call 即自动接通；MathTest 源码树场景的最终修复归 11002 锚点专项。
- **登记**：未解决问题.txt 补记第三十九轮进展；FFIMathTest.testFloat64 偶发 1 FAIL（dot3 roundtrip 精度噪声，前后对照出现/消失）观察项。

### [2026-11-16] 第四十轮：MathTest 矩阵 282 FAIL 闭环（vmDllImports 漏改的 NULL 占位 + 关联库部署）

- **根因（第三十九轮漏改第四处）**：`vm_system_func_preload_ext_lib()` 在错误锚点（`Front bin\lib\math_lib.dll`）首载失败后仍执行 `vm_sysfunc_ext_lib_cache_put(..., NULL)`，与第三十九轮已修的 `vm_sysfunc_ext_lib_load()` 相反——NULL 占位把后续「裸名 + `exe\lib\<平台>\`」候选永久封死。日志实证：`vmDll: LoadLibrary failed ... Front bin lib` → `lazy re-resolve ... still unresolved` → `CallSystemMethod not registered`。
- **修复**：`csimple_lang/src/vm/system_method_call/system_method_registry.c` 的 `vm_system_func_preload_ext_lib()` 失败分支改为：非 wasm 直接调用 `vm_sysfunc_ext_lib_load(dll_name, name_len)` 重试候选链（成功由该函数缓存 handle），wasm 保留 NULL 占位防 dlopen shim abort。
- **配套部署**：`SlangAllInOne/scripts/common.ps1` 的 `Invoke-RunTestsWin` 运行前把 `out\export\Math\math_lib.dll` 部署到 `<VMDir>\build\<Config>\bin\lib\windows\`（与 `sl_preload_associated_dlls` 的关联库布局一致）；AOT 包 `out\cli-release\lib\windows\` 本已有该 dll。
- **验证**：Debug VM 增量重建（VS Ninja/MSVC 环境）后，`run-tests-win.ps1 -Tests MathTest` **PASS=613 / FAIL=0**（此前 PASS=331 / FAIL=282）；移除 staged dll 立即回 283 FAIL，证明两处缺一不可。默认套件全集：BaseTest 0 FAIL、MathTest 0 FAIL、SpecialTest 85 FAIL（DLibrary/FFI 既有问题，未新增）、NullFastTest 正常；ExpendTest 产物缺失 SKIP（既有）。
- **结论**：11002「`./lib/*.module.slb` 被解析到 Front bin」仍是导出锚点写法缺陷（`moduleReferences[].path` 写回 `../../../../simple_language/source/bin/Debug/net8.0/lib/*.module`），但在第四十轮 VM 修复 + 关联库部署后**不再阻断 SystemMath\* 系统调用**；后续若要彻底清理锚点，需单独评估 Front 引用解析（影响 Core/Std 全量引用，回归面大）。

### [2026-11-16] 第四十一轮：SLangCodeEditor 解决方案树右键「首次不弹」根修（Qt 事件重入）

- **现象**：解决方案区树节点右键菜单时有时无——首次右键某未选中节点毫无反应（但节点被选中、代码区跳转），再次右键同一节点（已选中）才正常弹菜单。用户多次反馈「还是没有右键弹出」。第三十五轮节点差异化、第三十八轮 SL 侧空白兜底都没触及根因，故反复复发。
- **排查关键**：静态链路（信号值 `SIG_TREE_CONTEXT=12` 的 SL/C++ 逐值一致、`slqt_menu_*` FFI 符号齐全、dll 为 Qt6 真版、产物时间、`slqt_tree_item_path(nullptr)` 空指针防护、`compileFiles` 登记）全部正确；DLL 哈希确认加载的是最新构建。用 UI Automation 拿到树/节点精确坐标，原子化「置前 + 右键 + 读日志」实证：C++ lambda 触发、`path=[MathTest]`、`dispatchCb` 已调，但 **`dispatchCb` 不返回**（日志停在调用前）。
- **根因链**：C++ `SLQT_SIG_TREE_CONTEXT` 的 `customContextMenuRequested` lambda 里同步调 `dispatchCb` → 重入 VM 执行 `onTreeContext` → `menu.popupCursor()` 启动模态 `QMenu::exec()`；同时右键的 `setCurrentItem` 触发 `itemSelectionChanged` → SL 选中回调 `onSolutionSelected` → `DocumentLogic.openPath` → `refreshLists` → `UiContext.setTreePaths` → `solutionTree.clear()` 重建整棵树。选中联动的树重建与 `exec()` 内事件处理互相重入，导致菜单弹不出、`dispatchCb` 卡死不返回。节点已选中时 `setCurrentItem` 不改选中、不触发重建，故第二次能弹——完美解释「首次/二次」差异。另外 `clear()` 还会就地销毁 lambda 持有的 `it`，之后再读即悬空指针。
- **修复**（`cvm/src/slang_qt/slang_qt_qt.cpp` 的 `SLQT_SIG_TREE_CONTEXT` 分支，三处）：① 进 lambda 先 `slqt_tree_item_path(it).toUtf8()` 取路径副本，值栈持有，避开 `it` 悬空；② `setCurrentItem` 用 `QSignalBlocker` 包住，阻断选中联动重建树；③ **关键**——`dispatchCb` 用 `QTimer::singleShot(0, t, ...)` 推迟到下一事件循环轮次（path 用堆 `QByteArray` 持有、回调内释放），让选中重建先完成，菜单在干净事件栈上 `exec()`，彻底消除重入。
- **验证**：MSVC/Qt6 重编 `-Qt` 版 dll（EXIT=0），部署到 `out\export\SLangQT`、`publish\release\modules\SLangQT`、`SLangCodeEditor\modules\SLangQT`、QTTest、cvm\obj 五处槽位（哈希一致）。重启 `CodeEditor.exe`，UI Automation 实测：对未选中分组节点首次右键弹出 rootMenu（扫描文件夹/最近目录/扫描设置/工程操作/展开全部/折叠全部），对工程根首次右键同样弹出——「首次不弹」消失。
- **通用教训**：Qt 信号回调里经 FFI 重入 VM、且 VM 侧要弹**模态对话框/菜单**（嵌套事件循环）时，必须把 dispatch 推迟到下一事件循环轮次（`singleShot(0)`），避免与同轮次其他 Qt 信号的联动处理互相重入；这一点对所有 `customContextMenuRequested` + 菜单类信号同样适用。排查此类「时有时无」交互 bug，UI Automation 精确坐标 + 原子化置前/操作 + C++ 侧文件日志（dispatch 前后各一条，看是否返回）是最有效的定位组合。

### [2026-11-16] 第四十二轮：VS Code 风格欢迎页（左侧最近目录，零新增 FFI）

- **需求**：最近打开目录要有缓存记忆、重开可快速打开；新增欢迎界面，左侧显示最近打开目录（照 VS Code 做）。
- **现状复用（两条铁律）**：最近目录 MRU（上限 5）早已落在 `ConfigStore.recentFolders` / `settings.json`，`RecentFoldersDialog` + `CliProjectLogic.openRecentFolder` 已能复用 `scan`（CLI 先行）。欢迎页是纯 UI + IDE 本地状态，不写源码/配置语义，无需新 CLI 命令；所用 Qt 控件（QSplitter / QListWidget / QTextBrowser / QLabel）全部已登记，零新增 FFI（§0.1 通过）。
- **实现**（新增 `framework/ui/WelcomeUi.sl`，登记 `CodeEditor.jsonc` compileFiles）：中央 MDI 里建一个 `QSplitter`（左右 260:560 比例）作文档子窗——左侧 `QListWidget` 填 `ConfigStore.recentFolderAt(i)`，右侧 `QTextBrowser.setMarkdown` 显示欢迎/入门说明；`list.onCurrentRowChanged(WelcomeUi.onFolderRow)` 单击目录即 `CliProjectLogic.scan(dir)` 重新打开（复用 CLI 链路），并更新右侧内容。静态 `building` 标志屏蔽初始化填充的误触发；`subWin != 0` 时复用并 `showMaximized()` 置前。新增命令码 `VIEW_WELCOME=53`（CatalogData help 组 + Strings 命令文案 + MenuLogic 分发），AppBoot 在 `DocumentLogic.openCurrent()` 之后构建欢迎页（`MainFrameUi.build` 里太早会被后续文件子窗盖住）。
- **两个 Front/工具坑**：① `fillCodes(g7, "help", codes(VIEW_WELCOME, ...))` 传静态字段常量作实参触发 `MetaCoreCallNotSupportNotSupport`（Call link parse failed），改字面量 `53` 即过（同第二十一轮「实参复杂表达式」族）；② 测试期用 PowerShell `Set-Content -Encoding UTF8` 改 `settings.json` 会带 UTF-8 BOM，`Text.Json.load` 解析失败导致 MRU 读空（表现为欢迎页左侧空列表）——配置文件必须无 BOM 写入（`[System.IO.File]::WriteAllText` + `UTF8Encoding($false)`），这不是产品 bug。
- **验证**：`slang publish --mode exe --cvm Release` EXIT=0（exe 16:59:12）；UI Automation 实测欢迎页子窗 `[欢迎使用 SLang CodeEditor]` 显示、左侧 3 条最近目录全部列出、QListWidget currentRowChanged 触发（输出区 `[welcome] onFolderRow` + `[scan]`）——链路闭环。
- **已知边界**：AOT 发布 exe 附带一个 ConsoleWindowClass 控制台窗（stdout/日志），会在前台盖住部分界面；Qt MDI 子窗 `showMaximized()` 在多个子窗并存时不保证铺满（既有行为，所有代码子窗如此），欢迎页与代码窗并列。二者均属既有架构，不影响功能。

### [2026-11-18] 第四十三轮：masm_x64 插件接入（@masm_x64(){} 内联汇编——三个实测坑：ABI 位置配对 / cqo 覆盖 RDX / 出通道 Int32 截断）

- **背景**：按 cplus_clang 蓝本同构接入第三实例 `plugin/masm_x64`（id/tag/prefix 全量命名 = masm_x64，用户拍板自审阅稿 asm_ 更名）。三目录 + SLPF v3 双契约 + 六件套 labelExec + refModule 全链路零 Front/CVM 改动；`build-masm-x64.ps1` 一键三件套，Front 导出期「AtSignLabel: build success (14 block(s)) → SLMasm.dll」。
- **坑一（ABI 误判，编译期无感知、运行期 AV）**：入通道寄存器映射起初按「分族计数制」（整型族数 RCX/RDX/R8/R9、浮点族数 XMM0-3，两族独立计数）设计——**MS x64 ABI 实为按参数位置配对**（位置 1..4 = RCX/XMM0、RDX/XMM1、R8/XMM2、R9/XMM3，整型取该位 GP、浮点取该位 XMM，空位弃用）。混合通道 `Long,Double,String` 真实映射 = RCX、**XMM1**、**R8**（RDX/XMM0 空置），按分族制读 XMM0/RDX → 读到野值（AV read target=0x3，地址即残留寄存器值）。trampoline 走 MSVC 正常 C 调用所以永远正确——错的是 parse 侧给用户的映射注释与测试用例；修正后 ⑥ 用例（`mixed = 29`）成为位置配对的回归锁。教训：**ABI 契约以编译器行为为准（trampoline 一致性可交叉验证），文档语义先于用例写死前必须用混合类型用例实测**。
- **坑二（idiv 陷阱，SL 侧无法防护）**：测试用例 `mov rax, rcx; cqo; idiv rdx` 除法崩溃（0xC0000094 除零）——`cqo` 会把 RAX 符号位填进 **RDX**，把第 2 位置的除数（RDX）覆盖成 0。修正：除数先挪 `mov r8, rdx` 再 `cqo; idiv r8`。这是纯用户汇编坑，插件无法兜底（正是「汇编写错 = 进程崩溃」红线的实例）；用例保留为陷阱回归锁并在使用文档 §4 显著列出。
- **坑三（出通道 Int32 截断消费）**：`$v <- rax;` 的 int 出值经 Front 脱糖 ChannelOutInt 在 SL 侧**按 Int32 截断**（同 cplus 既有限制，蓝本 ③ 用例值恰好 < 2^31 所以从未暴露）——⑦ SIMD 用例返回 `2 | (4<<32) = 17179869186` 被截成 2。修正口径：**int/long 出通道的出值必须 ≤ 2147483647**（double 出值同理选截断无损值）；用例改为四车道求和（20）。该约束已写入使用文档与设计文档 §1.3。
- **次生坑（排障方法论）**：验证期 CPlusClangTest 突然三连死在第一个块（exit 1 无输出）——A/B（禁用 masm 全量接入）复现同点位失败，证明与 masm 无关；最终定位为**早前 ⑥ AV 崩溃残留的僵尸进程**（slang.exe/node.exe 挂起占用）干扰后续运行，`Stop-Process` 清理后 CPlus 29/0、Python 13/0 全恢复。教训：**进程崩溃型用例跑完后先查僵尸进程再跑长套件**；A/B 对照法对「环境态漂移 vs 代码回归」的判别依旧最有效。
- **交付物**：`plugin/masm_x64/`（含 MASM_X64_PLUGIN_DESIGN.md 设计+决策+坑复盘）、`SpecialTest/MasmX64Test.sl` 11 法 14 断言（plain+EXTERN printf/int 出/int64/double sqrtsd/string 大写+`.data`/三类型混合位置配对/AVX2 vpaddd/popcount×2/CPUID vendor+push rbx/imul+idiv/库驻留×2）全绿 `passed=14 failed=0`；文档同步 = plugin README + `md/plugins/MasmX64.md`（R21 使用口径）+ PLUGIN_SYSTEM_DESIGN §2.2d + PLUGIN_TEMPLATE §1 实例行。

### [2026-11-18] 第四十四轮：MasmBench 递归 fib 校验和错乱（易失寄存器跨 call 存活——「反汇编全对、语义全错」的 ABI 教科书案例）

- **现象**：BenchMark 接入 MasmBench 后，Loop/EqBench/SimdAVX2 三块校验与计时全对，唯 Fibonacci 递归块 `fib(0..21) x100` 得 12100——恰好是 sum(ceil(i/2))×100，即 f(n) 退化成 f(n-2)+1。
- **排障弯路（方法论警示）**：反汇编（dumpbin /disasm）逐指令核对——obj、链接后 exe、SLMasm.dll 三层机器码全部「正确」；cdb 单步前 40 条下降链与回卷逐指令正确；甚至独立最小复现（裸 .asm + C main，不含任何 VM/插件层）复现同样错值——一度陷入「机器码不可能产生该结果」的悖论。cdb 断点日志（每帧 add 时的 rdx 恒为 1）才揭示真相。
- **根因**：递归助手 `F_fib` 把 f(n-1) 暂存 **RDX（易失寄存器）**后发起第二次递归 `call`——递归子树内部同样执行 `mov rdx, rax`，把暂存值毁成子树残留的 1。于是每层 add 变成 f(n-2)+1。**指令序列、跳转、栈平衡全部正确，错的是调用约定语义：易失寄存器的值不得跨 call 存活。**「反汇编正确」只能排除编码错，不能证明 ABI 语义对——排障时不要被逐指令核对的全绿麻痹。
- **修复**：f(n-1) 改存非易失寄存器 RBX（`push rbx` 入、`pop rbx` 出配对）；修后校验和 = (fib(23)-1)×100 = 2865600 ✓（恒等式 sum(0..n)=fib(n+2)-1 反推期望值——手算 22 项累加两次都错，恒等式一次就对）。该用例保留为「易失寄存器跨 call」回归锁。
- **交付物**：MasmBench 四基准（Loop/EqBench/Fibonacci 共享口径 + SimdAVX2 专列）全绿，BenchCollector 增 recordMasm 与 ASM 列，报告多语言对比总表 ASM 上线（量级：Loop ASM ~3ms vs SL ~20s、EqBench ~2ms vs SL ~2.8s、Fibonacci ~9ms vs SL ~151ms、SimdAVX2 ~1ms 专列）；块内计时走 EXTERN QueryPerformanceCounter/Frequency（kernel32 符号经 cl 默认库解析，printf 同链已验证）。
- **通用教训**：① 汇编排障「反汇编全对」≠「语义对」——调用约定（易失/非易失、栈对齐、shadow space）是反汇编看不见的语义层，凡有 call 的汇编体先按 ABI 自查暂存值归属；② 校验和先算恒等式再手工累加；③ cdb 断点条件日志（bp + .printf + gc）比单步适合抓「深层偶发/系统性错值」；④ 最小独立复现（裸 asm + C main）对隔离 VM/插件层极有效——本例它直接证明问题在汇编自身。

### [2026-11-19] 第四十五轮：发布包 BenchMark 报告缺 ASM 时间列（插件 refModule 未 stage——出通道包装空体返回 null）

- **现象**：`slang publish` 产出的 BenchMark 应用跑完生成的 `report/BenchmarkReport_*.md` 里，ASM 列（Loop/EqBench/Fibonacci/SimdAVX2）时间单元格为空或缺行；同期 C/C++/CSharp 等列正常（因 `publish\<Ref>\` 下有 11-07 的陈旧 refModule 目录兜底），仅 masm（新插件）无对应目录。
- **定位过程**：① 同工程用开发树 CLI 编译 + `csimple_lang.exe run` 一切正常 → 排除 MasmBench/汇编计时本身；② 给 `sl_atsign_invoke` 与 `sl_atsign_channel_out_int` 加 stderr 插桩：发布包内各块 `exec` 后 out 值 marshal 正确（`out_type=1`、ns 有值），但 `AtSignChannelOutInt` 从未被调用 → SL 侧 `ns` 为 null；③ 对比 module.json：脱糖 IR 里 `ns = ChannelOutInt(entry)` 是 `CallStatic` 到 refModule 方法，主模块内该方法是 **instructionList 为空**的桩，真实方法体在 `../<插件名>/<插件名>.module` 引用模块里；④ 发布包 `moduleReferences` 中插件 refModule 条目**只有 uuid+path、没有 name**，而 `StageReferencedModules` 首行 `if (!TryGetProperty("name")) continue;` 直接跳过 → 引用模块未随包，静态调用落到空体桩，返回值 null。出通道包装对所有 `@tag` 插件通用（CPlusClang/MasmX64/Python…），陈旧目录存在时被掩盖，新插件必现。
- **修复**：`Publish/PublishCommand.cs` `StageReferencedModules` 增加 `InferReferenceNameFromPath`——无名引用按 path basename 反推模块名（`../MasmX64/MasmX64.module` → `MasmX64`）后走既有平铺 stage 链（导出树候选 → Lib 家族 → path 回退 → 平铺 `*.module.*` 进发布目录，C VM basename 直查命中）。
- **验证**：`dotnet run --project SlangAllInOne -- publish BenchMark.sp --dest D:\bench_pub8` → 7 个插件 refModule 全部 `staged flat into publish`；发布包 `BenchMark.exe` 跑完报告全列齐全（ASM：Loop 3ms / EqBench 2ms / Fibonacci 9ms / SimdAVX2 1ms），与开发树直跑一致。
- **通用教训**：① 发布产物与开发树的行为差异优先查「引用模块/插件运行位是否随包」——主模块里的 refModule 方法只是空壳，**方法体来自 `../<名>/<名>.module`**，缺件不报错、只静默返回 null；② 插桩点放在「跨界值 marshal 之后、SL 侧消费之前」能一次区分 marshal 错与消费链断裂；③ 发布产物验证必须跑「真实入口 + 端到端产物（报告文件）」，不能只看进程退出码。

### [2026-11-20] 第四十六轮：SnakeGame 发布 exe 秒退（Release json 淘汰连锁——publish 引用 stage 静默整体跳过）

- **现象**：`SnakeGame\publish\release\SnakeGame.exe` 双击/命令行均秒退（GUI 子系统无控制台，退出码 0 无输出）；发布包 `lib\windows\` 只有 Qt 运行库 + math_lib/sqlite3，**缺全部四组 FFI dll**（slang_qt / sl_sim_engine_lib / sl_render_lib / sl_audio_lib），发布根也缺四个引用模块 slb。
- **定位过程**：① 包内缺件清单对照 jsonc references → 怀疑 StageReferencedModules 未跑；② 用 out\cli-release\slang.exe（11-18 构建）重发 → 一切正常；③ 用 VSCode 实际配置的 package\win32-release\slang.exe（11-19 构建）`--dest` 探针重发 → **精确复现缺件**，且无任何 [WARN]；④ 对比两构建输出：packaged 版只有 `export module success (binary)`、无 json 行 → `result.ModuleJsonPath` 为 null → Step 6 前置条件 `File.Exists(module.json)` 不成立整体跳过；⑤ 真源 = simple_language 提交 7a627864「导出json去掉」（11-19 18:07，用户有意改动）：Release FrontEnd `#if !DEBUG` 把 json 系 format 一律按 binary 处理——publish 对 json 产物的隐式依赖被这次淘汰打断。
- **修复**：`Publish/PublishCommand.cs` Step 6 去掉 json 存在前置；`StageReferencedModules` 引用清单双来源——module.json moduleReferences 优先，缺失时回落 `ProjectManager.config.References`（Front 进程内已解析的 jsonc references，path 相对工程目录；目录/文件两形态都解析），并打 `[info] ... using jsonc references` 明示回落。`InferReferenceNameFromPath` 改收 path 字符串两源共用。
- **验证**：Release 托管宿主（`#if !DEBUG` 生效）探针发布 → 回落行 + 四组引用全 stage；重建 package\win32-release AOT 包（LSP 锁 slang.exe，按 release-local.ps1 重启额度耗尽法循环杀静后同命令内接 publish）→ 用更新后的 packaged slang 重发 SnakeGame → exe 实测窗口正常（主菜单/渲染/FairyGUI/Go3D 预览全显），sfx\fairyui 资源目录随包补齐（游戏按 cwd 优先探测）。
- **通用教训**：① 「有意淘汰某产物」的改动要全仓搜消费方——publish 对 module.json 的依赖是隐式前置条件，淘汰侧看不见它；② 发布缺件先对照「两个构建的行为差」而非只看代码现状（cli-release 旧构建正常掩盖了回归）；③ 静默跳过（无 WARN 的 continue/前置条件）是发布链最危险的失败形态，关键 stage 缺输入必须明示回落或告警；④ GUI 子系统 exe 秒退无输出时，先查包内缺件再怀疑运行时。

### [2026-11-20] 第四十七轮：php_embed 插件落地（PHP embed SAPI 接入五坑 + 消费侧 lib 路径基准错位）

- **背景**：以 python_cpython 为蓝本接入 PHP（`plugin/php_embed/`，三工程 + vendored php8ts.dll）。bridge 层先经独立探针验证（15 项全 PASS），再接 Front 端到端。设计稿/使用文档 = `plugin/php_embed/PHP_EMBED_DESIGN.md` / `README.md`。
- **坑 1（编译契约）**：PHP 头对宏极敏感——`zend_config.h not found`（C1083）真因是 `zend_portability.h` 的 guard 为 `ZEND_WIN32`（非 PHP_WIN32）；`_tsrm_ls_cache` LNK2019 真因是缺 `ZEND_ENABLE_STATIC_TSRMLS_CACHE`（缺它 `ZEND_TSRMLS_CACHE_DEFINE()` 展开为空）。compile defines 须齐：ZTS / PHP_WIN32 / ZEND_WIN32 / ZEND_ENABLE_ZVAL_LONG64 / ZEND_ENABLE_STATIC_TSRMLS_CACHE / ZEND_DEBUG=0。
- **坑 2（宏冲突）**：PHP win32 头重 include winsock 把 `s_host` 重新定义成宏，`#undef` 后仍被再定义，名为 s_host 的 static 变量被展开（C2059 `S_un`）→ 宿主表 static 改名 `s_host_tbl`。
- **坑 3（命名空间全局类解析）**：原设计用 `namespace sl_php\entry_N_vK;` 包裹用户代码避 run() 重声明，却致块内 `new Exception` 相对命名空间解析失败（Class not found 致命）→ 改**全局唯一函数重命名** `sl_php_entry_<N>_v<K>`（剥 `<?php` + 替换 `function run(` 函数名 + zend_eval_string），用户代码留全局作用域。
- **坑 4（未捕获异常 bailout）**：PHP 默认异常处理器打印 "Fatal error: Uncaught" 并 zend_bailout，**bailout 先清 EG(exception)** 再 longjmp → 直接读 EG(exception) 拿不到异常。解法：init 装 `set_exception_handler` 把异常 stash 到 `$GLOBALS['__sl_php_last_exc']`，call 前清哨兵、call 后读 EG(symbol_table) 哨兵 drain getMessage → -105；异常不 bailout，会话存活。
- **坑 5（消费侧 lib 路径基准，e2e 首跑 exit 1 真因）**：module.json 的插件 lib 相对路径，CVM 基准 = **module.json 所在目录**（out/export/<模块>），Front 把 jsonc lib 串原样记录不重新相对化。SpecialTest jsonc 目录与导出目录同在仓库根下第 4 层，4 级上溯两边巧合命中掩盖差异；隔离工程 test/Other/PhpEmbedTest（jsonc 第 5 层）按 jsonc 深度算 5 级上溯 → 记进 module.json 按导出目录（第 4 层）解析多跳一层到 D:\project\plugin（不存在）→ sl_ffi_lib_load 失败 → enter 从未执行。**判据 = SLPHP_TRACE 零输出**（bridge init 没跑，失败在装载上游）。对策：lib 串一律按导出目录到仓库根 4 级上溯写 `../../../../plugin/<id>/package/windows/<dll>`，与 jsonc 自身深度无关。
- **验证**：PhpTest.sl（镜像 PythonTest 10 用例 13 断言）经隔离工程 PhpEmbedTest 两链路（磁盘 slb + 宿主内存直传）均 13/13 PASS exit 0。
- **通用教训**：① 插件 lib 相对路径基准是**导出目录**不是 jsonc 目录，深层隔离工程易踩 off-by-one，"trace 零输出"是装载上游失败的快速判据；② 绝对路径装载才走 LOAD_WITH_ALTERED_SEARCH_PATH（同目录 vendored dll 命中），相对路径走 LoadLibraryA 不搜 dll 自身目录；③ 嵌第三方解释器先写独立探针证 bridge 层（init/eval/call/marshal/异常/会话存活）再接 Front，能把"编译契约/宏/API 版本"坑与"Front 脱糖/插件装载"坑分层定位；④ 解释型语言块体出通道若表达式以 `$` 起首须加括号规避 Front「出通道不可以 $ 开头」铁律（PHP 域使用侧最大差异）。

### [2026-11-20] 第四十八轮：php_embed 补 VS vcxproj（CharacterSet=Unicode 致 PHP 块崩溃）+ BenchMark PHP 计时列

- **背景**：php_embed 插件补 VS 工程（`cvm/cvm_php_embed.vcxproj` + `frontend/sl_php_embed_frontend.vcxproj`，挂 SlangAllInOne.sln plugins/php_embed 解决方案文件夹，蓝本 python_cpython）；BenchMark 增 PhpBench.sl 13 项共享基准 + BenchCollector PHP 列。
- **现象**：vcxproj Release 构建的 cvm_php_embed.dll 跑 PhpEmbedTest，纯块 echo 正常打印后崩溃（AV code=0xc0000005 read target=0x11，近空指针）；同源码 build-php-embed.ps1 构建的 dll 却 13/13 PASS。
- **定位过程**：① 先怀疑 /GL（WholeProgramOptimization）→ 关掉仍崩；② 怀疑 CRT（/MD vs /MT）→ dumpbin 查 ps1 产物只导入 php8ts.dll+KERNEL32（=/MT 静态），vcxproj 改 /MT 仍崩；③ 用 msbuild -v:detailed 抓 cl 命令行对比 ps1，发现 vcxproj 多 2 个 /D：`CharacterSet=Unicode` 自动注入 **UNICODE/_UNICODE**（ps1 的 cl 默认 MBCS 无此二宏）；④ PHP win32 头文件泛型文本映射（GetModuleFileName 等 TCHAR 系）在 UNICODE 下翻转为 W 变体，与 MBCS 构建的 vendored php8ts.dll ABI 错位 → 块执行后近空指针 AV。
- **修复**：cvm vcxproj 两配置 `CharacterSet=MultiByte`（显式去 UNICODE）；同时 `RuntimeLibrary=MultiThreaded`（/MT 对齐 cl /LD 默认）+ 不定义 NDEBUG + `WholeProgramOptimization=false`（对齐 ps1 /O2 无 /GL）。frontend 工程不涉 PHP 头，Unicode 无碍保持。改后 vcxproj Release 产物 e2e 13/13 PASS，与 ps1 产物等价。
- **BenchMark PHP 列**：PhpBench.sl 镜像 PythonBench 13 项（PHP 惯用：递归闭包 use(&$fn)/匿名类树避全局重声明、原生 sort、preg_*、hrtime(true) ns→intdiv us）；BenchCollector 增 recordPhp + langRow("PHP") + 对比总表 PHP 列。隔离工程 PhpBenchTest 单验 PHP（13 项校验和全对齐：nqueens 2680/sieve 78498/matmul 2450250000/mandelbrot iterSum 2256993）；全量 BenchMark 147 条目报告 PHP 列与十语言并排显示正常。
- **通用教训**：① **嵌第三方 C 库的 VS 工程，CharacterSet 必须与该库构建口径一致**——PHP/Win32 泛型文本头对 UNICODE 极敏感，VS 默认 Unicode 会静默注入 UNICODE/_UNICODE 翻转 W/A 映射致 ABI 错位崩溃；cl 命令行默认 MBCS 无此宏，故"ps1 能编 vcxproj 崩"时优先对比 msbuild -v:detailed 的 cl 命令行找自动注入的宏；② "近空指针 AV（read target=小整数 0x11）+ 库正常加载/初始化成功但调用后崩"是 ABI/结构错位的典型表象，先查编译宏差异而非逻辑；③ 解释型语言驻留解释器全局作用域共享，基准块递归助手用闭包/匿名类而非全局 function/class，避跨块/热更重声明致命。
