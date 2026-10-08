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
    └── CvmBackend.cs             定位 C VM 构建树（build\{Debug,Release}\bin）+ RunInMemory / RunCli
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
| `compile <project>` | Front 进程内编译；默认磁盘导出，`--in-memory` 时包 JSON 留在内存 |
| `run <project>` | **编译即运行**：内存编译 → C VM 内存入口（不写 module.json） |
| `run-disk <module.json>` | 经典路径：对已导出的 module.json 走 `cli_main run` |
| `info <module.json>` | 模块元数据（`cli_main info`） |
| `version` | Front 版本 + C VM DLL 路径/配置 |

## 选项

| 选项 | 说明 |
|------|------|
| `-p, --project <path>` | 工程路径（目录或 .sp 文件） |
| `-O0..-O3` | Front 优化级别 |
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

相关文档：C VM 宿主 API 见 `csimple_lang\md\cli.md`；Front 内存导出模式见 `simple_language\md\ai\EXPORT_PATHS.md`。
