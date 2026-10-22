# LSP 代码关联索引（MetaCore code index）

> 适用范围：Front `slang lsp-compile` 导出 → `slang lsp` 消费 → VSCode 插件呈现
>
> 2026-10-22 交付：编辑器侧「代码关联」机制——**Ctrl+S 保存 → Frontend 编译 → MetaCore 层导出一份 VSCode 可直接消费的数据结构**，覆盖文件关联、enum/class/data 定义、编译期裁剪灰区、方法/成员引用关联与转到定义。

## 1. 链路总览

```
Ctrl+S（VSCode didSave）
  → slang lsp（内嵌 LSP 服务器，防抖 400ms）
  → spawn 子进程 slang lsp-compile <工程.sp>
      Front 全量编译（Code→Token→Node→File→MetaCore→IR→Export memory）
      ├─ diagnostics        编译诊断（原有）
      ├─ packageJson       SLIR 符号源（原有）
      ├─ callSites         IR 指令流方法调用关联（原有，2026-10-21）
      └─ index             ★ 新增：MetaCore 代码关联索引（本文）
  → LspServer 装载：
      index.refs   并入调用点表 → definition/hover 光标命中即精确跳转
      index.symbols→ 定义锚点表 → 本工程目标优先解析
      index.excluded + index.ignoredFiles → slang/publishInactiveRegions 推送
  → VSCode 插件 InactiveRegionController → 裁剪代码灰显
```

## 2. index 数据结构（lsp-compile stdout JSON 的 `index` 字段）

编译**成功**才导出（失败时缺 `index`，LSP 侧保留最近一次成功编译的旧表——灰区/跳转不闪烁）；`f/tf` 为相对工程目录路径，与 diagnostics 同源；`l/el` 1-based，`c/ec` 0-based。

| 键 | 内容 | 用途 |
|----|------|------|
| `files` | 本轮编译纳入的源文件清单（`fileParseList`） | 文件关联 |
| `ignoredFiles` | jsonc `compileFiles` 未纳入的文件（`ignore` 或 group/tag 过滤） | 整文件灰显 |
| `excluded[]` | `@Exclude` 等 PreCompile attribute 裁剪的类/成员/local/global 函数灰区：`{f,l,c,el,ec,k("class"\|"field"\|"method"\|"func"),n}` | 灰显 |
| `symbols[]` | 类型定义锚点 + 成员：`{k("class"\|"interface"\|"enum"\|"data"),n,fn,f,l,c,ext,m[{k("method"\|"field"\|"enumMember"),n,t,st,cn,f,l,c}]}`（`fn`=类全名；`f/l/c`=名字 token 位置） | 转到定义（比 SLIR instruction 锚点更准） |
| `refs[]` | 引用点→目标关联：`{k("method"\|"field"\|"enumMember"\|"type"),f,l,c,ec,n,tn,tc,tm,tf,tl,tc2}` | 转到定义 / 悬停 |

`refs` 各键：`f/l/c/ec` = 引用点 token 区间；`n` = 引用处符号名；`tc/tm` = 目标类全名 + 成员名（查表键）；`tf/tl/tc2` = 目标定义位置（**仅本地编译目标非空**；ref module 目标为空——其源码属编译产物/加密侧，不做定义跳转，仅剩查表键供 hover）。

## 3. 灰区语义（"static if 提前处理显示灰"）

SL 的编译期裁剪（原 static if 已废弃，见 [static-if.md](./static-if.md)）有两个**确定性**面，全部导出灰显：

| 裁剪面 | 机制 | 灰显形态 |
|--------|------|----------|
| `@Exclude` attribute | PreCompile 时点命中即跳过（类/成员变量/成员函数/local/global 函数，不进 module.json） | 声明区灰显（attribute 行首 → 成员行末/块体闭合） |
| jsonc `compileFiles.files[].ignore` | 工程级整文件剔除（连 FileParse 都不创建） | 整文件灰显 |

**运行期动态分支（普通 `if` + `Environment.current` 等）判不出来的不导出、不灰显**——灰区只表达编译期确定性裁剪，绝不误灰。

灰区区间由导出器**源文本扫描定界**（`ScanDeclarationEnd`）：method/func/class 从 attribute 行扫到块体 `{` 括号配对闭合（接口式 `;` 声明取分号）；field 在深度 0 换行处终止（多行 data 初始化器 `{…}`/`[…]` 不受影响），行首 `{`/`}` 视为下一成员/类体边界。

## 4. 引用关联（refs）覆盖

数据源 = MetaCore 语义分析的沉淀（非 IR 指令流）：

- **遍历范围**：全部方法体（`MethodManager` 登记簿：成员/全局/local/动态闭包函数）的语句树 `metaBlockStatements`——if/elif/else、for、while/dowhile、try/catch/finally、switch/case/default、赋值左右值、return、throw、闭包体、表达式位 if/switch（`MetaExecuteStatementsNode`）；加类字段/枚举成员的初始化表达式。
- **表达式树**：调用链（`MetaCallLinkExpressNode`）、运算/一元/三目、常量字符串插值段、数组字面量、new 实参与花括号初始化、as/is、checked、try 表达式、空 return 三目。
- **关联类型**：`MetaCallLink.visitNodeList` 按 visitType 分流——`MethodCall/SystemCall`→方法（`methodCall.function`）；`Variable`→字段（仅类成员/全局，局部变量跳过）与枚举成员（`EnumMember` 包装变量归一到登记原实例）；`MetaClass/MetaData`→类型名引用（声明处类型名跳转）。

与既有 `callSites`（IR 指令流）互补：callSites 覆盖全部方法调用（含 ref module），index.refs 补齐字段/枚举成员/类型名引用并精化本工程定义锚点；两者在 LSP 侧合并进同一查询表（`CallSiteEntry.Kind` 区分）。

## 5. LSP/插件侧行为

- **定义跳转**（`textDocument/definition`）：调用点表命中优先——`tf` 直用 → 本工程定义锚点表（`index.symbols`，名字 token 位置）→ `MergedTable` 回查（含 ref module 源根推断）。IR 层自身代码不参与跳转（加密侧，不处理）。
- **灰显推送**：自定义通知 `slang/publishInactiveRegions {uri, ranges[]}`——每次成功编译后全量替换（空数组=清除）；didOpen/didSave 时若旧表在先按旧表即时推送（无灰显空窗）。
- **插件设置**：`slang.editor.fadeInactiveCode`（默认开）——低透明度装饰呈现，可关。
- 转到定义失败返回空（LSP 允许）；ref module 目标源码在开发布局命中时仍可跳（`ResolveSourcePath` 源根索引兜底）。

## 6. 相关源码

| 功能 | 文件 |
|------|------|
| 索引导出器（files/ignored/excluded/symbols/refs + 语句/表达式遍历器） | `SlangAllInOne\Lsp\LspMetaIndexExporter.cs` |
| lsp-compile 接入（index 字段） | `SlangAllInOne\Lsp\LspCompileCommand.cs` |
| LSP 装载/灰区推送/跳转解析 | `SlangAllInOne\Lsp\LspServer.cs`（`LoadCodeIndex`/`SendInactiveRegions`/`ResolveCallSiteTarget`） |
| 表达式位 if/switch 访问器（新增） | `simple_language\source\Core\MetaExpressNode\MetaExecuteStatementsNode.cs` |
| MethodManager 可见性（internal→public，索引导出需要） | `simple_language\source\Core\MethodManager.cs` |
| 灰显控制器 | `slang_vscode_plugin\src\inactiveRegions.ts` |
| LSP 客户端接线 | `slang_vscode_plugin\src\lsp.ts`、`src\extension.ts` |

验证工程：`tmp_lang_work\LspIndexProbe\`（@Exclude 类/字段/方法、ignore 文件、enum/data/class、方法/字段/枚举成员引用）；端到端冒烟脚本 `tmp_lang_work\lsp-index-smoke.js`（4 类引用精确跳转 + 三类灰区推送，全部 PASS）。
