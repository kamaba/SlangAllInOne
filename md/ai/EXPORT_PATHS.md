# SLIR 导出路径（约定）

**调试时各文件含义与阅读顺序**：见同目录 **`DEBUG_WORKFLOW.md`**。

在 `jsonc` 的 **`export.outputDir`** 下再建一层 **`export.moduleName`**（未填则用 `project.name` / `.sp` 主名），得到模块根目录：

`{export.outputDir}/{moduleName}/`

该目录下固定包含：

- **`Logs/`**：`Front.txt`（Front 固定文本日志）、`VM.txt`（VM 固定文本日志）、`Result.txt`（`print`/`println` 镜像）。
- **VM 包**：**`{project.name}.module.json`**（如 `Core.module.json`），与 Logs 同级，由 `ExportLangManager` → `SLModulePackageWriter.Write` 写入该模块目录。

**`DebugCode/`**（Front 各阶段调试文本 `Code.txt`、`Token.txt`、…，按源文件相对路径分子目录，`Common.GetDebugCodeDir`）**不在此目录下**：🔥 2026-10-19 起固定落在**工程目录**（`.sp`/`.jsonc` 所在目录）：

`{工程目录}/export/DebugCode/{源文件相对路径}/`

例如编译 `SLangCore\test\Other\MyTest` 工程时，快照写到 `…\MyTest\export\DebugCode\MyTest1\IR.txt`。

## 环境变量（外部只读手动覆盖入口）

正常路径**不依赖环境变量**：`LoadProject` 加载 `.jsonc` 后由 `ProjectOutputEnvironment.ApplyFromConfig`
把上述三个目录**派生为进程内静态状态**（`CurrentExportOutDir` / `CurrentLogsDir` / `CurrentDebugCodeRoot`），
Front 内部与测试宿主统一经 `ProjectOutputEnvironment.GetEffective*()` 读取
（外部环境变量优先 → 进程内状态兜底）；**Front 不再写入任何 `SIMPLELANG_*` 进程环境变量**。

以下三个变量仅保留为**外部手动覆盖入口**（运行前在外部设置，编译器只读）：

- **`SIMPLELANG_EXPORT_OUTDIR`**：上述模块根目录（`*.module.json` 所在目录）。
- **`SIMPLELANG_LOGS_DIR`**：`{export.outputDir}/{moduleName}/Logs/`。
- **`SIMPLELANG_DEBUGCODE_ROOT`**：DebugCode 根目录（缺省派生为 `{工程目录}/export/DebugCode/`）。

未走 `LoadProject`（或 `export.outputDir` 缺失）时可设置它们手动指定落点。`export.debugText.outputDir` 不再作为调试文本根路径；**`debugText` 块以各阶段开关为主**（`code`/`token`/…）。

## 导出三态（Front CLI 旗标 `--export-mode <output|temp|memory>`，2026-10-20）

Front `compile` 的导出阶段往哪里送产物，由 `--export-mode` 三态控制（`ExportLangManager.ExportMode`，缺省 output；原 `--in-memory` 旗标并入 memory 态）：

- **output（缺省）**：导出到指定目录——jsonc `export.outputDir` 派生目录（本文 §1 的常规路径）。
- **temp**：导出到临时目录——`<Frontend 运行目录>\_temp\<模块名>\`（模块名 = `export.moduleName` → `project.name` → "module"，非法字符替换 '_'），内部结构与正式导出完全相同，用完可整体删除。
- **memory**：不导出——SLB 二进制**不压缩**存内存（`SLBWriter.WriteToBytes(pkg, compressed: false)`），由宿主直传 C VM `cli_run_module_in_memory_binary`，不解压直接读取；json 系（`json`/`binary+json`）另产 JSON 内存文本（`LastMemoryPackageJson`，LSP 消费）。

通用规则：

- 磁盘两态（output/temp）：**slb 恒导出**（默认必须导出二进制）；json 副本仅 format 为 json 系（`json`/`binary+json`，缺省 json）时落盘；压缩开关 `export.binary.compressed` 仅磁盘两态生效（缺省 true）。
- memory 态：恒不压缩、不落盘；产物读取 = `ExportLangManager.LastMemoryPackageBytes`（SLB 字节）/ `LastMemoryPackageJson`（json 系时的 JSON 文本）；调用前 `ResetExportState()` 清上一次残留。
- `--export-mode` 显式指定即隐含 `-e ir`（`exportIR=true`）；`Front.txt` 仍打导出成功日志（维持脚本成功判据）。
- `Logs/`、`DebugCode/` 调试产物**不受三态影响**，照旧落 jsonc 派生目录。

典型宿主：根目录 `SlangAllInOne/`——`slang run` 缺省 memory（编译即运行：SLB 经 P/Invoke 直传 C VM，见 `csimple_lang/md/cli.md` 宿主 API 与 `csimple_lang/md/design/SLB_DESIGN.md` §8.2 导出三态）；`slang compile` 缺省 output。

## `module.package.json` 根结构（当前约定）

根对象仅两个字段：

- `entryModule`：字符串，指向 `moduleList` 中入口模块的 `moduleName`。
- `moduleList`：数组，每项为完整模块对象（与原先单模块时的结构一致：`moduleName`、`irStringDict`、`classList`、`methodList` 等）。

## 字段/全局 express IR 整理链（IR 层收口，2026-10-21 重构）

**架构原则**：IR 层把所有 IRCode 数据整合好（`IRMetaVariable.irDataList` 为最终形态），json/binary 导出层（`SLModulePackageWriter` / `SLBWriter`）只做纯序列化，不再处理 IR 整理逻辑。

**整理入口**（`SLModulePackageWriter.Build` 开头、类过滤后统一预跑一次，幂等守卫防重复）：

- `IRMetaClass.FinalizeFieldIRData()`：逐类整理实例/静态字段 IR（整理范围 = `ShouldExportClass` 导出范围）；
- `IRManager.FinalizeGlobalStaticVariableIRData()`：全局静态变量 IR（须在各类之后跑，二者可能共享同一 `IRMetaVariable` 实例）。

**字段 express 取值回退链**（`FinalizeFieldIRData` 内逐字段执行；实例字段 `irDataList` 为空时）：

1. `IRMetaVariable.irDataList`（IR 层已生成的数据，常规来源）；
2. **enum 成员直查**：字段类型宿主为 `MetaEnum`（经 `IRMetaClass.OwnerMetaEnum` 判定）时，按字段名在 `metaMemberEnumDict` 查同名枚举成员并导出其 `express`。🔥 该分支原为反射实现（`GetType().Name == "MetaEnum"` + 反射调用不存在的 `GetMemberEnumByName`），双重落空从未生效；2026-10-21 改直连代码后正式激活；
3. `globalStaticVariableList` 中同 `id` 全局静态变量的 `express`；
4. 字段自身 `v.express`（`IRExpressManager.CreateExpress` 生成）。

**整理管线**（方法族已自 SLModulePackageWriter 前移至 IR 层）：表达式合成 → `Append*StoreIfNeeded` 补尾 Store 指令（静态=`StoreStaticField`/实例=`StoreNotStaticField1`/全局=`StoreGlobal`）→ `TryRewriteArrayStaticInitializer` Array 字面量展开 → O3 `TryFuseConst*` 常数融合（`-O3` 才启用）。`TryBuildConstValuePayload`（O3 载荷提取）落在 `IRMetaClass`（internal static，IRManager 全局融合复用）。

**已迁移方法归属**：`MetaType.ToSystemCallTypeString`（systemCalls 签名串）、`MetaType.NormalizeTypeName`（泛型段折叠）→ `Core/MetaType.cs`；`FinalizeFieldIRData` + 字段整理方法族 → `IR/Core/IRMetaClass.cs`；`FinalizeGlobalStaticVariableIRData` + 全局整理 → `IR/IRManager.cs`；`SLModulePackageWriter` 仅保留 `ShouldExportClass` 过滤与纯序列化。

**验证记录（2026-10-21，ProjectTest 全量）**：O1 导出 VM 执行输出与重构前基线逐行等价（8911 行，0 真实差异）；O3 输出与重构前旧代码逐行一致（frameCount FAIL / static_t 空为 O3 融合既有行为，非本次回归）。⚠ module.json 字节级 hash 本身逐次不稳定（`IRManager.TranslateIR` 并行翻译 + ConcurrentBag 装载 → 字符串池 ID 顺序非确定），等价性判定以 VM 执行输出为准。

