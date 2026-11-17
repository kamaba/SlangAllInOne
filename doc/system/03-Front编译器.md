# Front 编译器（simple_language）

> 项目定位：SLang 的**编译前端与语义真源**。把 `.sl` 源码 + `.jsonc` 工程配置编译为 SLIR 包（`.module.slb` / `.module.json`）。
> 工程：`d:/project/lang/simple_language/source/SimpleLanguageFront.csproj`（net8.0，Exe，StartupObject `SimpleLanguage.Program`）。
> ⚠ opcode 枚举真源 `IROpEnum.cs` 必须与 C VM 的 `vm.h :: EIROpCode` 逐项对齐（见根 `AGENTS.md` R2）。

---

## 1. 目录职责

| 目录 | 职责 | 代表文件 |
|------|------|---------|
| 根目录 | 入口与全局定义 | `Program.cs`、`Common.cs`、`Define.cs`、`Token.cs`、`IROpEnum.cs`、`FrontJsonContext.cs` |
| `CLI/` | 命令解析与执行分发 | `CommandExecutor.cs`、`CommandInputArgs.cs` |
| `Project/` | 工程加载、jsonc 解析、引用模块、输出环境 | `ProjectCompile.cs`、`ProjectJsoncLoader.cs`、`ProjectConfig.cs`、`ProjectReferenceModuleLoader.cs`、`ProjectModuleDependency.cs`、`ProjectOutputEnvironment.cs` |
| `Process/` | 五阶段编译过程状态机 | `ProcessManager.cs`、`CompilePhaseDefine.cs`、`CompilePhaseState.cs` |
| `Parse/` | 词法/语法：字符→Token→Node→AST | `LexerParseToToken.cs`、`TokenParseToNode.cs`、`StructParseFrame.cs`、`StructParseToSyntax.cs`、`Node.cs`、`FileParse.cs` |
| `FileMeta/` | 单文件语义树 | `FileMeta.cs`、`FileMetaClass.cs`、`FileMetaSyntax.cs`、`FileMetaExpress.cs` |
| `Core/` | 语义分析（全工程符号整合、类型/类/成员/语句、插件前端承载） | `ClassManager.cs`、`TypeManager.cs`、`MethodManager.cs`、`ImportManager.cs`、`PluginFrontendParser.cs`、`PluginFrontendWorkflow.cs`、`SlPluginMessageCodec.cs` |
| `IR/` | IR 生成与优化 | `IRManager.cs`、`IRMethod.cs`、`IRData.cs`、`IRStatements/`、`Core/IRMetaClass.cs` |
| `Export/` | 导出：SLIR JSON/SLB、MLIR AOT、插件/DLL 打包 | `ExportLangManager.cs`、`SLIR/SLModulePackageWriter.cs`、`SLIR/Binary/SLBWriter.cs`、`SLIR/Binary/SLBFormat.cs`、`MLIR/MLIRExportManager.cs`、`PluginManager.cs`、`VmDllBuildManager.cs` |
| `Log/` / `Util/` | 日志与错误码 / 工具 | `ErrorDefinitions.csv`、`LID.cs` |

---

## 2. 编译管线（五阶段）

阶段顺序 `RefModule → File → MetaCore → IR → Export`，由 `ProcessManager.cs` 驱动，步骤注册在 `ProjectCompile.InitCompileProcess()`。各阶段细节见 [01-全链路流程](01-全链路流程.md) §2，此处只列骨架：

```
CommandExecutor.ExecuteCompile → ProjectManager.Run → ProjectCompile.Compile
  ├─ ① RefModule   ProjectReferenceModuleLoader.LoadReferences（NotifyOnly）
  ├─ ② File        LexerParse → TokenParse → StructParse（文件级隔离）
  ├─ ③ MetaCore    ExpandBind → CombineFileMeta → ParseMetaClassLink → ParseStatements → AutoInlineMark（AbortPhase）
  ├─ ④ IR          IRManager.TranslateIR（ParseClass → 逐函数 TranslateIRByFunction → 优化）
  └─ ⑤ Export      ExportLangManager.Export（MLIR → vmDll → 插件 → 包构建 → 三态写出）
```

**导出三态**（`export.format`）：`binary`（必产 `.slb`）、`json`（`.module.json`）、`binary+json`（两者皆产）；另有 `memory` 导出模式（宿主编译即运行时零落盘直传字节，格式仍是 SLB）。

**SLB 段布局**（`SLBFormat.cs`）：`POOL / META / NS / CLASS / GLOBAL / METHOD / CODE / IRSTRING / DEBUG` 九段；DEBUG 段由 `FlagDebugInfo`(bit2) 控制，供 DAP 调试使用。

---

## 3. 命令面

Front 命令（`CLI/CommandExecutor.cs`，版本常量 `VersionString`）：

| 命令 | 别名 | 作用 |
|------|------|------|
| `compile` | c / build / b | 编译工程（`-p` 工程、`-e ir`、`--export-mode`、`--format`、`-O0..3`、`--macro` 等） |
| `export` | e | 仅导出 IR |
| `clean` | — | 清理产物 |
| `version` | v | 版本 |
| `help` | h | 帮助 |

> `run` / `new` 不在 Front，归宿主 `SlangAllInOne`（`CommandExecutor.cs` 注释）。
> 标准库编译由宿主侧 `Project/CompileStdlib` 驱动（预设 core/std/math/all），见 [06-标准库与模块系统](06-标准库与模块系统.md)。

---

## 4. JSONC 配置字段速查

模型 `ProjectConfig.cs`，解析 `ProjectJsoncLoader.cs`。完整字段语义见 [01-全链路流程](01-全链路流程.md) §4；此处列出前端最常打交道的：

- `project` / `source`：工程身份与源码根/入口（`.sp` 存在才进主编译管线；缺失按库工程处理）。
- `compileFiles.files[]`（path/group/tag/ignore/priority）+ `compileFilter`：编译清单。
- `compile`（optimize/target/语法开关）：优化级别与语法特性。
- `references[]`：引用模块（导出为 `moduleReferences`）；`type=module` 走 spm。
- `global`（imports/replace/data/macro）：注入与宏（`_before_()`）。
- `dllImports[]` / `vmDlls[]` / `systemCalls[]` / `plugins`：互操作声明。
- `export`（moduleName/outputDir/format/binary/aot/debugText/nativeDll/publicExport）：产物控制。
- `platform` / `publish` / `spm.registry`：平台条件校验、发布、包管理。

---

## 5. 扩展机制

### 5.1 插件前端（SLPF v3 ABI）
- 清单 `plugin.jsonc` 的 `abi.frontend`（当前 3）与 `frontendNative{lib,parseFn,buildFn,freeFn}` 由 `PluginFrontendParser.ReadManifest` 解析。
- `NativeLibrary.Load` + `GetExport` 绑定 `sl_frontend_parse/build/free`；校验 `abi.frontend>=3`。
- 调用管线 `PluginFrontendWorkflow.RunParse/RunBuild` 五阶段：Prepare→Encode→Invoke→Decode→Complete；编解码由 `SlPluginMessageCodec` 负责，数据格式 `[Header][结构体][变长][TLV]`（契约头 `plugin/cplus_clang/frontend/src/sl_frontend_abi.h`）。
- 导出期 `PluginManager.Run(outDir)` 构建插件产物并关联 `plugins[].lib` 平台库。详见 [07-插件系统](07-插件系统.md)。

### 5.2 MLIR AOT
- `MLIRExportManager.Instance.Run`（`Export/MLIR/MLIRExportManager.cs`）：stage1 候选收集 → stage2 `MLIRExporter.ExportModuleToFile` 产 `aot.mlir` → stage3 `MLIRToolchain.TryBuildAotDll` 产 `aot.dll`（失败回落 CVM）→ stage3.5 manifest 并入 module.json。
- AOT 工具链探测 `<exe>/bin/` 优先（发布包 `PackMlirTools` 就位），开发树回落 `simple_language/tools/llvm`。

### 5.3 模块引用
- `ProjectReferenceModuleLoader.LoadReferences`：先 `EnsureModuleReferences`（版本检查/下载），再加载 `.module.json`/`.slb`，直接构建 IR 元数据（`isRefModulePreBuilt`，不经 Meta 重建）。
- `ModuleManager` / `IRMetaModule` 维护 self/core/ref 模块；导出时 `moduleReferences[].path` 写实际加载包路径。

---

## 6. LSP / DAP 输出通道

- **LSP 索引**：`slang lsp` spawn `lsp-compile` → `FrontendService.Compile(..., Memory, format:json)` → `LspIRIndexExporter` 从 IR 指令流导出 `files/ignoredFiles/excluded/symbols/refs`，stdout 结构化 JSON（`success/diagnostics/packageJson/index`）。索引不随 module 包落盘。
- **DAP 调试信息**：随 SLB DEBUG 段产出（`export.binary.includeDebugInfo`）；`export.debugText` 另产 Code/Token/Node/File/Meta/IR 文本。

---

## 7. 关键文件索引

| 主题 | 文件（相对 `simple_language/source/`） |
|------|----------------------------------------|
| 命令分发 | `CLI/CommandExecutor.cs` |
| 编译总控 | `Project/ProjectCompile.cs`、`Project/ProjectManager.cs` |
| 配置模型/解析 | `Project/ProjectConfig.cs`、`Project/ProjectJsoncLoader.cs` |
| 引用装载 | `Project/ProjectReferenceModuleLoader.cs`、`Project/ProjectModuleDependency.cs` |
| 词法/语法 | `Parse/LexerParseToToken.cs`、`Parse/TokenParseToNode.cs`、`Parse/StructParseFrame.cs`、`Parse/FileParse.cs` |
| 语义 | `Core/ClassManager.cs`、`Core/TypeManager.cs`、`Core/MethodManager.cs`、`Core/PluginFrontendParser.cs` |
| IR | `IR/IRManager.cs`、`IROpEnum.cs` |
| 导出 | `Export/ExportLangManager.cs`、`Export/SLIR/SLModulePackageWriter.cs`、`Export/SLIR/Binary/SLBWriter.cs`、`Export/SLIR/Binary/SLBFormat.cs` |
| AOT | `Export/MLIR/MLIRExportManager.cs` |
| 插件/库 | `Export/PluginManager.cs`、`Export/VmDllBuildManager.cs` |
