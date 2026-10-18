# PROJECTS.md — 全仓工程清单与路径记忆（2026-10-17 仓库重组后）

> 🔥 本文件是**重组后工程布局的权威记忆**（AI 排障/改工程先读这里）：
> 目录职责、24 个 sln 工程、新旧路径映射、关键机制锚点、构建命令。
> 上游入口：[AGENTS.md](../AGENTS.md) §1；开发入口：[SlangAllInOne.sln](SlangAllInOne.sln)。

## 1. 顶层目录职责

| 目录 | 职责 | 备注 |
|------|------|------|
| `simple_language\` | **纯 FrontEnd 编译器**（C#/.NET 8） | `source\` 平铺（CLI/Core/Export/FileMeta/IR/Log/Parse/Process/Project/Util + Common/Define/IROpEnum/Token/FrontJsonContext.cs）；csproj = `source\SimpleLanguageFront.csproj`。**不含**库/测试/文档/产物 |
| `csimple_lang\` | **C99 虚拟机**（exe + P/Invoke dll） | vcxproj：`project\vs\vm_lib\csimple_lang_lib.vcxproj`（→dll）、`project\vs\vm_exe\csimple_lang_exe\csimple_lang_exe.vcxproj`（→exe）；CMake 主构建见 AGENTS.md §5 |
| `SlangAllInOne\` | **总包 + 全仓入口 sln** | 宿主（slang）+ `Project\`（编译/测试/native 工程）+ `SLangCore\Lib`（标准库源码）+ `SLangCore\test`（用例集）+ `SLangCore\samples` + `md\`（全部文档）+ `tools\`；**产物导出根 = `SlangAllInOne\out\export\`** |
| `simple_language_plugins\` | 插件根 | csharp_mono、java_hotspot（各含 `cvm\`（vcxproj）+ `frontend\`（csproj）+ `slang\`） |
| `slang_vscode_plugin\` | VS Code 插件 | 独立，未接入构建 |
| `gosimple_lang\` | Go 实验前端 | 独立，无构建依赖 |
| `scripts\` | 一键脚本（build-all / build-vm-win|linux / release-slang…） | 见 AGENTS.md §5 |

## 2. SlangAllInOne.sln 工程（24 个，7 分组）

| 分组 | 工程 | 路径 | 类型 | 说明 |
|------|------|------|------|------|
| host | **SlangAllInOne** | `SlangAllInOne.csproj` | csproj/Exe | 统合宿主 `slang`：Front 进程内编译 + C VM P/Invoke；publish 自举 pack-modules/pack-docs |
| front | **SimpleLanguageFront** | `..\simple_language\source\SimpleLanguageFront.csproj` | csproj/Exe | Front 编译器（opcode 真源 `IROpEnum.cs`） |
| compile | **SimpleLanguageCompileCore / Math / Std** | `Project\Compile*\SimpleLanguageCompile*.csproj` | csproj/Exe | 标准库三驱动（仅引用 Front）；编译产物 → `SlangAllInOne\out\export\` |
| test | **CSimpleVMCoreTest / StdTest / MathTest / SpecialTest / BenchMarkTest / Test / RenderTest** | `Project\CSimpleVM*\*.csproj`、`Project\CSimpleVMRenderTest\RenderTest.csproj` | csproj/Exe | 联合测试宿主（Front 编译用例 → C VM 执行）；Debug=P/Invoke 进程内，Release=独立进程 |
| native-cvm | **csimple_lang_lib / csimple_lang_exe** | `..\csimple_lang\project\vs\vm_lib\…`、`..\csimple_lang\project\vs\vm_exe\…` | vcxproj | C VM DLL（宿主 P/Invoke 载的就是它）与独立 CLI exe |
| native-libs | **cvm_math_lib / cvm_sl_mysql_lib / CLangdll** | `Project\*\*.vcxproj` | vcxproj | Math FFI（Math.jsonc `vmDlls` 构建它 → `math_lib.dll`）、Mysql FFI、CLangdll |
| plugins | **SLCSharpMonoFrontend / SLJavaHotspotFrontend**（csproj）+ **cvm_csharp_mono / cvm_java_hotspot**（vcxproj） | `..\simple_language_plugins\…` | 混合 | 插件 Front 层（Front 反射转调）与 CVM 层 |
| tools | **ExtractLogs / LidIndexer / SLBRoundTrip** | `tools\*\*.csproj` | csproj | 日志工具 / LID 索引 / SLB 往返测试（引用 Front，验证 slb/json 双向一致） |

✅ **`Project\Test`、`Project\Test2`（C VM 轻量宿主）**：2026-10-18 复活改造——原 C# VM 宿主（引用已删除的 `..\VM\SimpleLanuageVM.csproj`），VM 段改走 C VM（Debug P/Invoke / Release 进程模式），已收录 sln（test 文件夹）。⛔ **`Project\StdNativeImpl`、`Project\MathNativeImpl` 已于 2026-10-18 删除**——旧 C# VM `ISLExternalFunctionModule` 外部函数机制示例，机制随 C# VM 废弃（C VM 等价物 = C DLL + jsonc `systemCalls.cvmFunction`，`CLangdll`/`cvm_math_lib` 已覆盖；删除留档见 `md/ai/troubleshooting/06-build-engineering.md` 2026-10-18 条）。
⛔ **废弃 sln**：`simple_language\SimpleLanguage.sln`（引用大量已迁移路径）；`csimple_lang\csimple_lang.sln`（引用不存在工程）。

## 3. 路径映射（旧 → 新，排障反查用）

| 旧路径（重组前） | 新路径（现状） |
|------|------|
| `simple_language\source\Front\` | `simple_language\source\`（Front 子层拍平） |
| `simple_language\source\Front\Lib\` | `SlangAllInOne\SLangCore\Lib\`（Core/Math/Std/SLang：Server、Render、Mysql、Tensora） |
| `simple_language\source\CompileCore|CompileMath|CompileStd\` | `SlangAllInOne\Project\Compile*\` |
| `simple_language\source\MathNativeImpl|StdNativeImpl|CLangdll\` | `SlangAllInOne\Project\`（前两个已删除——旧 C# VM 外部函数机制） |
| `simple_language\project\CSimpleVM*Test\` | `SlangAllInOne\Project\CSimpleVM*Test\` |
| `simple_language\project\cvm_math_lib\` | `SlangAllInOne\Project\cvm_math_lib\`（Math.jsonc `vmDlls[].project` 现指向 `../../../Project/cvm_math_lib/…`） |
| `simple_language\test\` | `SlangAllInOne\SLangCore\test\` |
| `simple_language\samples\` | `SlangAllInOne\SLangCore\samples\` |
| `simple_language\md\` | `SlangAllInOne\md\` |
| `simple_language\tools\` | `SlangAllInOne\tools\` |
| `simple_language\out\export\` | `SlangAllInOne\out\export\`（**全仓唯一产物根**；库/测试 jsonc `export.outputDir` 均指此） |
| `Front\Lib\Math\cvm_math_lib\`（C 源） | `SLangCore\Lib\Math\cvm_math_lib\` |
| `Front\Lib\SLMysql\cvm_sl_mysql_lib\` | `SLangCore\Lib\SLang\Mysql\cvm_sl_mysql_lib\` |
| 测试 jsonc 引用 `"../../out/export/…"` | `"../../../out/export/…"`（多上溯一层） |

## 4. 关键机制锚点（改路径/加工程必读）

1. **repoRoot 探测锚点**：宿主/测试宿主 `Program.cs` 的 `GetRepoRoot()` 上溯找 **`SlangAllInOne.csproj`**（旧锚点 SimpleLanguage.sln 已失效）。`Program.GetRepoRoot()`（宿主）另按 `csimple_lang\CMakeLists.txt` 找工作区根。
2. **导出根单一真源**：库 jsonc `export.outputDir`（三段 `..\..\..\out\export`）↔ `PackModulesCommand.exportRoot` ↔ 测试 jsonc references，三方都指 `SlangAllInOne\out\export\`；改其一必须同步其余。
3. **宿主 csproj glob 排除**：[SlangAllInOne.csproj](SlangAllInOne.csproj) 排除 `Project\**`、`tools\**`、`SLangCore\**`、`examples\**`、`md\**`（Compile/None/EmbeddedResource 三通道）——迁入子树各有独立工程，不排除则多份 `Program.cs` 互撞（CS0111）。
4. **官方库直查（2026-10-17）**：Front `ProjectReferenceModuleLoader.TryResolveRuntimeModuleDirPath`（Strategy 4）与 C VM `sl_load_references` ④ 都直查 `<exe 目录>\module\<名>.module.slb|json`（C VM 侧 exe 目录 util = `sl_exe_dir_join_name`，`csimple_lang\src\lib\ffi\sl_ffi_lib_manager.*`）；发布包内 references 写纯名 `Core`/`Std`/`Math` 即可。
5. **引用装载 slb 优先**：`SLModulePackageWriter.ReadPackageForReference`（.slb → SLBReader，json → Read；统一归一后剥指令）。
6. **SLB 反序列化**：`SLBReader`（`simple_language\source\Export\SLIR\Binary\`）+ round-trip 测试 `tools\SLBRoundTrip`。
7. **新增 .c 文件三处登记**（R6）、**新增系统方法四处同步**（R7）不变，见 AGENTS.md §2。

## 5. 构建命令速查

```powershell
# Front 编译（.sl → module.json）
dotnet run --project simple_language\source\SimpleLanguageFront.csproj -- compile -p <.sp> -e ir

# 标准库三件套（→ SlangAllInOne\out\export\）
dotnet run --project SlangAllInOne\Project\CompileCore\SimpleLanguageCompileCore.csproj   # 先 Core
dotnet run --project SlangAllInOne\Project\CompileMath\SimpleLanguageCompileMath.csproj  # 含 vmDll 构建 math_lib.dll
dotnet run --project SlangAllInOne\Project\CompileStd\SimpleLanguageCompileStd.csproj

# 编译即运行（Front → SLIR 内存直传 → C VM）
dotnet run --project SlangAllInOne\SlangAllInOne.csproj -- run SlangAllInOne\SLangCore\test\BaseTest\ProjectTest --no-banner

# C VM（CMake 主路径）/ 双平台 AOT 发布（win-x64 + WSL linux-x64）
powershell -File scripts\build-vm-win.ps1 -Config Release
powershell -File scripts\release-slang.ps1 -Version <x.y.z>   # 发布策略：AOT-only 双平台同发，见 RELEASE.md
```

## 6. 验证记录（2026-10-17 重组整合）

| 项 | 结果 |
|----|------|
| sln 解析（`dotnet sln list`） | ✅ 24 工程 |
| 标准库三件套编译 | ✅ Core/Math/Std → `SlangAllInOne\out\export\`（Math 含 cvm_math_lib 新路径构建 + math_lib.dll 落位） |
| 全链路 | ✅ `run SLangCore\test\BaseTest\ProjectTest` exit 0 |
| C# 工程构建回归 | ✅ 宿主 + 9 测试宿主（含 Test/Test2）+ Compile×3 + 插件 frontend×2 + tools×3 全过（2026-10-18 死工程清理后） |
| 文档路径残留 | ✅ AGENTS.md/README 旧路径零残留 |

⚠ 已知缺失：`SLangCore\test\Other\` 未随迁的旧用例子目录（NullFastTest、JsonTest、Platform*、InlineLambda*、CoroGCProbe、OOMProbe、SBAProbe、TLSFProbe 等）——`CSimpleVMTest` 具名用例运行会找不到，需要时从 git 历史恢复。
