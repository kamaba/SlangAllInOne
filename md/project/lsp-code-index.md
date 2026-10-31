# LSP 代码关联索引（IR code index）

> 适用范围：Front `slang lsp-compile` 导出 → `slang lsp` 消费 → VSCode 插件呈现
>
> 🔥 **2026-10-23 用户定稿：数据源整体由 MetaCore 语义树切换为 IR 生成数据**——像 `变量.后边的方法/成员` 这类链式访问，只有 IR 生成期的解析绑定完整可靠，编辑器侧代码关联数据一律读 IR。本文即该核心逻辑的记忆载体。

## 1. 链路总览（FrontEnd 为 VSCode 提供编译接口）

```
Ctrl+S（VSCode didSave）
  → slang lsp（内嵌 LSP 服务器，防抖 400ms）
  → spawn 子进程 slang lsp-compile <工程.sp>        ← FrontEnd 对 VSCode 暴露的接口
      Front 全量编译（Code→Token→Node→File→MetaCore→IR→Export memory）
      └─ 编译完成后直接读 IRManager（IR 生成数据）：
         ├─ diagnostics        编译诊断
         ├─ packageJson       SLIR 符号源（补全/悬停）
         └─ index             ★ 代码关联索引（本文，全部出自 IR）：
              ├─ files/ignoredFiles/excluded   文件关联 + 灰区
              ├─ symbols      定义锚点（IRMetaClass/IRMethod/IRMetaVariable）
              └─ refs         引用关联（IR 指令流逐指令导出，
                              原 callSites 通道已并入 kind=method）
  → LspServer 装载：
      index.refs   → 调用点表 → definition/hover 光标命中即精确跳转
      index.symbols→ 定义锚点表 → 本工程目标优先解析
      index.excluded + index.ignoredFiles → slang/publishInactiveRegions 推送
  → VSCode 插件 InactiveRegionController → 裁剪代码灰显
```

**为什么必须读 IR**：MetaCore 的 `MetaCallLink.visitNodeList` 语义沉淀在模板实例、ref module、链式返回值等场景存在缺口；IR 生成期每条指令都携带解析完成的绑定（目标方法 IRMethod、目标字段 owner+index）与访问点 token（`debugInfo`），是指令级完整真源。RefModule 侧同理——`ProjectReferenceModuleLoader` / `IRMetaModule` 正是**从 SLIR 包直接构建 IRMetaClass/IRMethod/IRMetaVariable**（`isRefModulePreBuilt`，不经过 Meta 重建）供编译消费，本索引导出器对"本地编译类"与"ref module 导入类"用**同一套 IR 结构读法**（irName / index / id 反查），参考即此。

## 2. index 数据结构（lsp-compile stdout JSON 的 `index` 字段）

编译**成功**才导出（失败时缺 `index`，LSP 侧保留最近一次成功编译的旧表——灰区/跳转不闪烁）；`f/tf` 为相对工程目录路径，与 diagnostics 同源；`l/el` 1-based，`c/ec` 0-based。

| 键 | 内容 | 用途 |
|----|------|------|
| `files` | 本轮编译纳入的源文件清单（`fileParseList`；语法层来源） | 文件关联 |
| `ignoredFiles` | jsonc `compileFiles` 未纳入的文件（`ignore` 或 group/tag 过滤） | 整文件灰显 |
| `excluded[]` | `@Exclude` 等 PreCompile attribute 裁剪的类/成员/local/global 函数灰区：`{f,l,c,el,ec,k("class"\|"field"\|"method"\|"func"),n}` | 灰显 |
| `symbols[]` | 类型定义锚点 + 成员：`{k("class"\|"interface"\|"enum"\|"data"),n,fn,f,l,c,ext,m[{k("method"\|"field"\|"enumMember"),n,t,st,cn,f,l,c}]}` | 转到定义锚点 |
| `refs[]` | 引用点→目标关联：`{k("method"\|"field"\|"enumMember"\|"type"),f,l,c,ec,n,tn,tc,tm,tf,tl,tc2}` | 转到定义 / 悬停 |

`refs` 各键：`f/l/c/ec` = 引用点 token 区间；`n` = 引用处词元；`tc/tm` = 目标类 irName + 成员名（查表键）；`tf/tl/tc2` = 目标定义位置（**仅本地编译目标非空**；ref module 目标为空——其源码属编译产物/加密侧，不做定义跳转，仅剩查表键供 hover）。

## 3. refs 数据映射（IR 指令 → 引用条目）

导出器遍历**全部 IRMethod 指令流**（`IRManager.IRMethodDict` = 成员/全局/local/动态闭包登记簿；ref module 方法只导入签名、指令流为空，天然只导出本地站点）+ **类级字段初始化 IR**（`IRMetaVariable.irDataList`，经 `CreateStaticMetaMetaVariableIRList` / `FinalizeFieldIRData` 收口）：

| IR 指令族 | kind | 目标解析 |
|-----------|------|----------|
| `CallStatic/CallVirt/CallDynamic/CallClosure/NewMethodRef` | method | `opValue = IRMethodCall.irMethod`（IR id/owner/短名/定义 token） |
| `LoadStaticField/StoreStaticField`(+O3 ConstValue) | field/enumMember | owner=声明类 + `index` → `staticIRMetaVariableList` 反查（owner 见 §4；enum 的成员存静态字段表） |
| `LoadNotStaticField/StoreNotStaticField1/2`(+O3 ConstValue) | field | `debugMemberOwnerIrClass` + `index` → `localIRMetaVariableList` 反查 |
| `LoadGlobal/StoreGlobal`(+O3 ConstValue) | field | `index`(=MetaVariable 哈希 id) → `globalStaticVariableList` 反查（const 静态成员 / .sp Project / jsonc global.data；纯 global{} 变量无登记表**不导出**） |
| `NewObject/NewTemplateObject/NewArray` | type | opValue=classId/IRMetaType → `IRMetaClass`；**词元须匹配目标类型名**（滤合成 IR 噪音，如 enum 生成 values 数组打到声明 token） |
| `LoadConstType/CastClass` | type | opValue=`IRMetaType` → `IRMetaClass`（类型字面量 / as / is） |
| `LoadConst*`（const 成员直载） | field | 常量内联后无字段指令：靠发射点写入的 `debugMemberOwnerIrClass` + 站点词元按名反查静态成员表 |

**实例/静态两个 index 空间独立**（各自从 0 编号）——与 RefModule 导入侧（`IRMetaModule.BuildFields`）约定一致，反查须按 `isStatic` 选表。

不导出（宁缺勿错）：`CallSystemMethod`（debugInfo 落系统方法声明 token，站点不可用）；`CallFFIStatic`/`CallAtSignLabel`（绑定表索引语义，无 SL 目标）；指令流外链（编译器合成、无 token）。

## 4. IR 发射点配套（Front 侧为索引补齐的目标信息）

IR 指令流原生只携带**运行时**必需信息，部分访问形态的目标声明类在指令上不可见，2026-10-23 在发射点补齐（仅编译期索引用途，不进 Payload 序列化、不影响运行时）：

| 发射点 | 补齐内容 |
|--------|----------|
| `IRData.debugMemberOwnerIrClass`（新属性） | 成员访问指令的目标**声明类** IRMetaClass 引用 |
| `IRVariable.CreateLoadVariable/CreateIRStoreVariable` 成员分支 | 实例字段 Load/Store、const 成员直载、全局槽静态成员的指令列表统一 `SetMemberOwner`（`IRBase` 新增辅助） |
| `IRExpress` new{} 初始化器成员 store | 携带新对象类型的声明类 |
| `IRAssignStatements.SetStoreDebugInfoByAssignToken` | 成员目标（字段/枚举成员）store 的**站点 token 改用最后访问节点（成员名词元）**——链首 token（`st`/`this`/类名）会让站点词元错位、hover/跳转词匹配失准；非成员目标（局部/参数/数组下标）保持链首 token 语义（SLDP 断点行语义不变） |

静态字段访问无需 `debugMemberOwnerIrClass`：其 `opValue` 本就是声明类 `IRMetaType`（IR.txt 的 `fieldTypeIrmt`/`staticOwner` 调试用字段即此形态的文本化）。

## 5. 灰区语义（"static if 提前处理显示灰"）

SL 的编译期裁剪（原 static if 已废弃，见 [static-if.md](./static-if.md)）有两个**确定性**面，全部导出灰显：

| 裁剪面 | 机制 | 灰显形态 |
|--------|------|----------|
| `@Exclude` attribute | PreCompile 时点命中即跳过（类/成员变量/成员函数/local/global 函数，不进 IR） | 声明区灰显（attribute 行首 → 成员行末/块体闭合） |
| jsonc `compileFiles.files[].ignore` | 工程级整文件剔除（连 FileParse 都不创建） | 整文件灰显 |

**运行期动态分支（普通 `if` + `Environment.current` 等）判不出来的不导出、不灰显**——灰区只表达编译期确定性裁剪，绝不误灰。

灰区区间由导出器**源文本扫描定界**（`ScanDeclarationEnd`）：method/func/class 从 attribute 行扫到块体 `{` 括号配对闭合（接口式 `;` 声明取分号）；field 在深度 0 换行处终止（多行 data 初始化器 `{…}`/`[…]` 不受影响），行首 `{`/`}` 视为下一成员/类体边界。

## 6. LSP/插件侧行为

- **定义跳转**（`textDocument/definition`）：调用点表命中优先（行 + 光标词 == 词元，token 列语义混杂靠词名匹配免疫；辅以区间容忍）——`tf` 直用 → 本工程定义锚点表（`index.symbols`）→ `MergedTable` 回查（含 ref module 源根推断）。IR 层自身代码不参与跳转（加密侧，不处理）。
- **悬停文档**（`textDocument/hover`）：方法/字段卡附带成员上方紧邻注释块（`ExtractDocComment`/`MemberDoc`）——声明行取自 `index.symbols` 定义锚点（成员名 token 行；instruction debugInfo 首条指向函数体首语句，不可用）。`#![md] ... !#` 块注释内容按 Markdown 直出（词法 SharpLevel 块内是原文，多行/空行/公共缩进去重支持），普通 `#` 行注释与 `#! ... !#` 块以 blockquote 呈现。覆盖调用点、使用点（`a.b` / `类.成员`）、成员声明处（类体内裸名，`FindEnclosingClass` 补齐）三类悬停位置。
- **装载**：`index.refs` 为唯一引用通道（原 callSites 已并入），每轮成功编译**整体替换**防跨轮残留。
- **灰显推送**：自定义通知 `slang/publishInactiveRegions {uri, ranges[]}`——每次成功编译后全量替换（空数组=清除）；didOpen/didSave 时若旧表在先按旧表即时推送（无灰显空窗）。
- **插件设置**：`slang.editor.fadeInactiveCode`（默认开）——低透明度装饰呈现，可关。
- 转到定义失败返回空（LSP 允许）；ref module 目标源码在开发布局命中时仍可跳（`ResolveSourcePath` 源根索引兜底）。

## 7. 相关源码

| 功能 | 文件 |
|------|------|
| 索引导出器（IR 数据源：files/ignored/excluded/symbols/refs） | `SlangAllInOne\Lsp\LspIRIndexExporter.cs` |
| IR 发射点目标信息补齐 | `simple_language\source\IR\IRVariable.cs`、`IRExpress.cs`、`IRStatements\IRAssignStatements.cs`、`IRData.cs`（`debugMemberOwnerIrClass`）、`IRBase.cs`（`SetMemberOwner`） |
| lsp-compile 接入（index 字段） | `SlangAllInOne\Lsp\LspCompileCommand.cs` |
| LSP 装载/灰区推送/跳转解析 | `SlangAllInOne\Lsp\LspServer.cs`（`LoadCodeIndex`/`SendInactiveRegions`/`ResolveCallSiteTarget`） |
| RefModule 的 IR 读取参考（同构读法） | `simple_language\source\Project\ProjectReferenceModuleLoader.cs`、`source\IR\IRMetaModule.cs`（SLClassPackage → IRMetaClass/IRMethod/IRMetaVariable） |
| 灰显控制器 | `slang_vscode_plugin\src\inactiveRegions.ts` |
| LSP 客户端接线 | `slang_vscode_plugin\src\lsp.ts`、`src\extension.ts` |

验证工程：`tmp_lang_work\LspIndexProbe\`（@Exclude 类/字段/方法、ignore 文件、enum/data/class、方法/字段/枚举成员引用）；端到端冒烟脚本 `tmp_lang_work\lsp-index-smoke.js`（4 类引用精确跳转 + 三类灰区推送，2026-10-23 IR 数据源切换后复验全部 PASS）。

## 8. 演进记录

| 日期 | 变更 |
|------|------|
| 2026-10-21 | callSites 通道落地（IR 指令流方法调用关联，`LspCallSiteExporter`） |
| 2026-10-22 | index 通道落地（时为 MetaCore 语义树数据源，`LspMetaIndexExporter`；symbols/excluded/ignoredFiles/refs） |
| 2026-10-23 | 🔥 **数据源整体切换为 IR 生成数据**（用户定稿）：symbols/refs 全部改读 IRManager，callSites 并入 refs（kind=method），`LspMetaIndexExporter`/`LspCallSiteExporter` 合并删除，统一为 `LspIRIndexExporter`；IR 发射点补 `debugMemberOwnerIrClass` 目标声明类、成员 store 站点 token 修正 |
| 2026-10-31 | 悬停文档注释落地：方法/字段卡附成员上方注释块（`#![md] ... !#` Markdown 直出 / `#` 与 `#!...!#` blockquote）；声明行改查 index.symbols 定义锚点（instruction 首条 debugInfo 指向函数体首语句不可用）；HandleHover 补成员声明处悬停（类体内裸名）与裸名唯一命中文档；冒烟脚本增 4 个 hover 探针全 PASS |
