# SlangAllInOne — FrontEnd + Backend 统合宿主

一个 .NET 8 进程内完成「Front 编译 → SLIR 包内存直传 → C VM 运行」：
`slang run <工程>` 即**编译即运行**，`module.json` 不落盘。

## 定位与结构

```
SlangAllInOne/
├── SlangAllInOne.csproj          net8.0 Exe；ProjectReference → simple_language\source\Front\SimpleLanguageFront.csproj
├── Program.cs                    统合 CLI（命令解析 + help）
├── FrontEnd/FrontendService.cs   进程内调用 Front CommandExecutor（compile -e ir [--in-memory]）
└── Backend/
    ├── CvmInterop.cs             P/Invoke：cli_main / cli_run_module_in_memory + SLVM_MEM_FLAG_* 常量 + 手动 UTF-8 组参
    └── CvmBackend.cs             定位 C VM 运行时（发布包 bin\ 优先，回退构建树）+ RunInMemory / RunCli
```

- **FrontEnd**：不派生 `dotnet run SimpleLanguageFront.csproj` 子进程，直接进程内调 `CommandExecutor.Execute`；
  `--in-memory` 时导出阶段只产 JSON 文本（`SLModulePackageWriter.BuildPackageJson`），不写 module.json。
- **Backend**：P/Invoke 加载 `csimple_lang_dll.dll`；`run` 走内存入口，`run-disk`/`info` 走经典 `cli_main`。

## 内存直传链路（run 命令）

```
.sl 源码
  → Front 进程内编译（compile -e ir --in-memory）
  → BuildPackageJson：SLIR 包 JSON 文本（与磁盘写出字节级一致）
  → P/Invoke cli_run_module_in_memory(json, baseDir, flags, programArgs)
  → slir_json_read_packages_in_execution_order_from_memory（根包以 @memory:root 伪路径入 visited 去重）
  → slir_json_parse_package_text 解析 + sl_load_references 装载引用包（引用仍从磁盘按绝对路径递归装载）
  → C VM 执行，print 直写控制台
```

直传三要素：

| 要素 | 内容 |
|------|------|
| 包 JSON 文本 | 宿主持有；引用包（Core 等）不在文本里——Front 已把它们解析为**绝对路径**写入 `moduleReferences` |
| baseDir | = module.json 本应写出的 outDir；`moduleReferences` / 插件 lib **相对它**解析；`NULL`/空回退 CWD |
| flags + program args | `SLVM_MEM_FLAG_*` 位或（对齐 `csimple_lang/src/cli/cli.h`）；`--` 后参数填 `Project._inputArgs`（源码 `global._inputArgs` 读取） |

执行语义与磁盘路径完全一致：`entryMethodId`、引用递归装载、平台校验、program args 行为均不变，只是省掉一次写盘 + 一次读盘。

## 命令

| 命令 | 说明 |
|------|------|
| `compile <project>` | Front 进程内编译；默认磁盘导出，`--in-memory` 时包（JSON 文本或 SLB 字节，按 `--format`）留在内存 |
| `run <project>` | **编译即运行**：内存编译 → C VM 内存入口（不写 module.json；`--format binary` 时 SLB 字节直传 `cli_run_module_in_memory_binary`） |
| `run-disk <module.json\|module.slb>` | 经典路径：对已导出的包走 `cli_main run`（两种格式，magic 自动探测） |
| `info <module.json\|module.slb>` | 模块元数据（`cli_main info`） |
| `pack-modules` | 编译标准库三件套（Core → Math → Std）并平铺打进 `module\`（slb 直排单目录，无按模块子树；`--dest <dir>` 默认 exe 目录；`--config Debug` = slb + json，`Release` = 仅 slb + math_lib.dll）；`dotnet publish` 自动调起（见「正式发布包」） |
| `pack-docs` | 把 FrontEnd 用户文档拷进 `md\`（根入口 5 篇 + `syntax/lib/project/log/plugins` 目录镜像 + `source\Front\Lib` 各库说明 → `md\src-lib\`；排除内部 `md\ai\`、`md\vm\` 与 `cvm_*` C 侧工程，共 ~92 篇）；`dotnet publish` 自动调起 |
| `version` | Front 版本 + C VM DLL 路径/配置 |

## 选项

| 选项 | 说明 |
|------|------|
| `-p, --project <path>` | 工程路径（目录或 .sp 文件） |
| `-O0..-O3` | Front 优化级别 |
| `--format <json\|binary>` | 导出格式二选一（透传 Front `--format`；binary = SLB `.module.slb`，规范见 `csimple_lang/md/design/SLB_DESIGN.md`）。`run --in-memory --format binary` 为 SLB 内存直传链路（P2） |
| `--export-json` / `--no-export-json` | compile 磁盘导出：是否附带 `.module.json` 调试副本（覆盖 jsonc `export.binary.exportJson`，仅 `--format binary` 时生效） |
| `--in-memory` | compile：包 JSON 留内存（隐含 `-e ir`） |
| `-t, --test` | 向 C VM 传 `-test`（⚠ 当前为占位，见下） |
| `--no-banner` | 抑制 banner |
| `--debug` | C VM 调试模式（指令追踪） |
| `--force-run` | 跳过 C VM 平台硬校验 |
| `--strict-plugins` | 插件 disable 视为 C VM 错误 |
| `--cvm <Debug\|Release>` | 选 C VM 构建树（默认 Debug；找不到回退另一配置） |
| `-- <args...>` | 之后所有参数进 `Project._inputArgs` |

## 退出码

| 码 | 含义 |
|----|------|
| 0 | 成功 |
| 1 | Front 编译失败（`Log.errorCount > 0` 或执行返回 false）或参数错误 |
| 4 | 找不到 `csimple_lang_dll.dll`（先构建 C VM） |
| 非 0（其他） | C VM 运行失败，原样透传 |

## 构建 / 运行

前置：C VM 已构建出 `csimple_lang\build\{Debug,Release}\bin\csimple_lang_dll.dll`
（构建方式见根 `AGENTS.md` §5，如 `powershell scripts\build-vm-win.ps1 -Config Debug`）。

```powershell
cd d:\project\lang
# 编译即运行（module.json 不落盘）
dotnet run --project SlangAllInOne\SlangAllInOne.csproj -- run simple_language\test\BaseTest\ProjectTest
# 传参：-- 之后进 global._inputArgs
dotnet run --project SlangAllInOne\SlangAllInOne.csproj -- run simple_language\test\Other\MiniSmoke\MiniSmoke -- hello 42 world
# 经典磁盘路径
dotnet run --project SlangAllInOne\SlangAllInOne.csproj -- run-disk simple_language\out\export\ProjectTest\ProjectTest.module.json
```

注意：`run` 在进 C VM 前把 CWD 切到工程目录（用例含 `Resources/` 等相对路径，与 CSimpleVMTest 宿主行为一致）；编译阶段沿用启动 CWD。

## 正式发布包（package\debug | package\release）

`dotnet publish` **一条命令**产出自包含发布包。publish 过程全自动四步：
① 增量构建对应配置的 C VM（Ninja，无变化秒过）→ ② 拷 C VM 运行时到 `bin\` →
③ **编译标准库三件套并打进包内**（`PackStdModules` target 调起刚发布的 exe 执行
`pack-modules`，制作逻辑全部在工程代码 `Pack/PackModulesCommand.cs` 里，无手工脚本）→
④ **拷 FrontEnd 用户文档进包内 `md\`**（`PackDocs` target 调起 `pack-docs`，
清单在 `Pack/PackDocsCommand.cs`：根入口 5 篇 + `syntax/lib/project/log/plugins`
目录镜像 + `source\Front\Lib` 各库说明 → `md\src-lib\`，排除 `md\ai\`、`md\vm\`
内部文档与 `cvm_*` C 侧工程）：

```powershell
cd d:\project\lang
dotnet publish SlangAllInOne\SlangAllInOne.csproj -c Release -o SlangAllInOne\package\release
dotnet publish SlangAllInOne\SlangAllInOne.csproj -c Debug   -o SlangAllInOne\package\debug
```

**产物名 `slang`**：csproj 设 `<AssemblyName>slang</AssemblyName>`，发布包主程序为
`slang.exe` / `slang.dll`（工程目录与命名空间仍是 SlangAllInOne；publish target 用
`$(AssemblyName)` 自举，pack-modules / pack-docs 自动跟随）。

任一步失败 publish 即失败（不打缺运行时/缺模块的坏包）。包内容对比：

| 目录 | Debug 包 | Release 包 |
|------|----------|------------|
| `slang.exe + *.dll` | .NET 应用 + Front 编译器（发布产物名 `slang`，见下） | 同左 |
| `bin\` | csimple_lang_dll.dll（~3MB 带边界检查）+ sqlite3.dll + pdb | csimple_lang_dll.dll（~1.6MB）+ sqlite3.dll |
| `module\` | `*.module.slb` **+ `*.module.json` 调试副本**，**平铺单目录**（无按模块子树） | **仅必须的 `*.module.slb`**，平铺单目录 |
| `module\math_lib.dll` | ✓（FFI 原生库，vmDllImports 预载 + 静态绑定） | ✓ |
| `md\` | ✓ 用户文档 ~92 篇（语法/库/工程/日志/插件 + 各库说明） | ✓ 同左 |
| 定位 | 编译 + 运行 + 调试全功能 | 运行包（跑已编译 slb） |

**平铺布局**：包内模块不再镜像仓库 `out\export\<模块>\` 子树，`module\` 单目录直排
`<模块>.module.slb`（Debug 另有 `.module.json` 调试副本）+ `math_lib.dll`。模块间
引用（`moduleReferences`，基准 = 主包所在目录）由 C VM 装载器回退解析：原样相对
路径落空时按 basename 回退 `<主包目录>\<名>.module.json`（json 或 slb 任一存在即
尝试，SLB 优先重定向）；FFI `dllImports` 同理按 `<主包目录>\<basename>` 直查。
仓库开发布局（`out\export\<模块>\` 深层路径）不受影响，仍走原路径直接装载。

**包内使用**（整包拷到任意位置，脱离仓库运行）：

```powershell
# Release 包：跑已编译模块 —— 用户 slb 放包内 module\ 即可
slang.exe run-disk module\MyProj.module.slb

# Debug 包：编译 + 运行用户工程 —— 工程 jsonc 的 references 指向包内 module\
# （例：工程放 <pkg>\test\MyProj\，references 写 { "path": "../../module", "name": "Core.module.json" }）
slang.exe run test\MyProj\MyProj
```

注意：**用户模块必须与包内标准库同源编译**（引用装载有 uuid 校验，旧模块配新
标准库仅 Warning 但类装配可能错位）；标准库更新后用户模块需重新 compile。

| 项 | 说明 |
|----|------|
| C VM 配置联动 | `-c Debug` → 打包 Debug 树 C VM；`-c Release` → Release 树；显式 `-p:CvmBuildConfig=<cfg>` 最优先；`pack-modules --config` 随之联动 |
| 标准库编译模型 | Core → Math → Std，每模块一个干净子进程（publish 出的 exe 自举 `compile -O3 --format binary --export-json`，R15）；成功判据 = exit 0 + slb mtime fresh（对齐 scripts\compile-stdlib.ps1） |
| Math 的 vmDlls | 编译 Math 时 Front 自动 MSBuild 构建 `cvm_math_lib.vcxproj` 并拷出 math_lib.dll（MSBuild 缺失仅跳过并复用已有 dll，缺失则打包失败） |
| DLL 定位优先级 | `<exe 目录>\bin\csimple_lang_dll.dll`（打包布局，优先）→ `csimple_lang\build\{Debug,Release}\bin`（开发布局，回退） |
| 手动重打模块 | `slang.exe pack-modules [--dest <dir>] [--config Debug|Release]`（默认 dest = exe 目录） |
| 手动重打文档 | `slang.exe pack-docs [--dest <dir>]`（默认 dest = exe 目录；不在仓库内运行时报错跳过） |

## 调试（Frontend C# + C VM C 同进程混合）

**VS F5（主推）**：用 VS 打开 `SlangAllInOne\SlangAllInOne.csproj`，选 `Properties\launchSettings.json` 里的
`run MiniSmoke (C# + C VM mixed)` profile（`nativeDebugging: true`）按 F5：

- **Frontend**：直接在 `simple_language\source\Front\**` 打 C# 断点；
- **C VM**：直接在 `csimple_lang\src\**` 打 C 断点（P/Invoke 进程内加载 `build\Debug\bin\csimple_lang_dll.dll`，
  同目录 `.pdb` 源码路径与本仓库一致，符号天然对上）；
- 换调试用例：改 launchSettings 的 `commandLineArgs`，或命令行 `dotnet run --project SlangAllInOne\SlangAllInOne.csproj -- run <工程>`；
- 命令行裸 `dotnet run`（不带 `--`）即走默认 profile 的参数。

**调试发布包**：`package\debug\bin\` 已含 `csimple_lang_dll.pdb`（publish 自动打包，Debug 树产物），
VS「调试 → 附加到进程」选 `slang.exe`（或在包目录直接用 VS 打开 exe 调试）即可在
C VM 源码断点；`.NET` 侧 Debug 包带自身 pdb，Frontend 断点同样可用。
`package\release` 无 pdb（Release 树不产出），只用于运行不发调试。

已知噪音：Front 编译失败写日志时可能触发 `Log.cs` 的 F: 盘硬编码路径异常（独立已知问题，与本链路无关）。

## 已知限制：`-t` 是占位

C VM `-test` 目前只解析不生效（`opts.test` 全源码只写不读，`cli_command.h` 注释 "currently same entry"），
且 Front 导出包只带 `_main_` 的 `entryMethodId`（`SLModulePackageWriter` 只认 `_main_` 入口）。
因此磁盘与内存路径都实际执行 `_main_`。切换 `_test_` 入口需改 SLIR 协议（Front 写入口 + C VM 选入口两侧）。

## 验证记录（2026-10-08）

| 项 | 结果 |
|----|------|
| `run BaseTest\ProjectTest`（编译→内存→运行） | ✅ `_main_` 跑通，exit 0 |
| 内存模式不落盘 | ✅ module.json mtime 保持不变 |
| `compile` 磁盘导出对照 | ✅ mtime 更新 |
| `run-disk` / `info` | ✅ |
| `-- a b c` → `global._inputArgs` | ✅ args count = 3 |
| 负例（ConstProbe 等故意报错探针） | ✅ exit 1 正确传播 |
| 自包含发布包（2026-10-09） | ✅ package\release 内 JsonTest/ExportPermTest exit 0，DLL 来自包内 lib\；整包拷 %TEMP% 脱离仓库运行同样通过（`DLL: ...\lib\csimple_lang_dll.dll (package)`） |
| 正式发布包·平铺布局（2026-10-13） | ✅ publish 全自动（`bin\` 运行时 + `module\` slb 直排单目录 + math_lib.dll）：Release 包 run-disk Std（packageCount=2）、Math（packageCount=3 + math_lib FFI 预载 40/40）exit 0；Debug 包（slb + json）包内 `run` 用户工程（references 写 `{ "path": "../../module", "name": "Core.module.json" }`）：Front 装载 `module\Core.module.json`、C VM SLB 优先直指 `module\Core.module.slb`、packageCount=2，exit 0；仓库开发布局（`out\export\` 深层路径）回归无退化 |
| 用户文档打包（2026-10-13） | ✅ `pack-docs` 随 publish 自动执行，双包各 92 篇：根 5 + syntax 38 + lib 26 + project 12 + log 2 + plugins 2 + src-lib 7；`cvm_sl_mysql_lib` 等 C 侧工程与 `md\ai\`、`md\vm\` 正确排除；`--dest` 手动模式抽查通过 |
| 产物名改为 slang（2026-10-13） | ✅ `<AssemblyName>slang</AssemblyName>`：双包产出 `slang.exe`/`slang.dll`，publish 自举 targets（pack-modules / pack-docs，走 `$(AssemblyName)`）正常；Release `slang.exe version` 与 Debug `slang.exe run-disk Core.module.slb` 均 exit 0 |

相关文档：C VM 宿主 API 见 `csimple_lang\md\cli.md`；Front 内存导出模式见 `simple_language\md\ai\EXPORT_PATHS.md`。
