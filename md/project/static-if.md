# global.macro 宏与编译期条件

> 适用范围：`Front` 工程，`*.sp` / `*.sl` 源码 + `<ProjectName>.jsonc` 工程配置
>
> **`static if` / `static elif` / `static else` 编译期条件编译已恢复**（基于 `global.macro` 宏数据面，仿 D 语言 static if）：条件在编译期求值，只把选中分支接入语句链，未选中分支不参与语义分析与 IR（不进 runtime）。用法见第 2 节。
>
> `global.macro` 宏数据面全套（jsonc 定义 / `_before_()` 钩子编译期修改 / CLI `--macro` / 环境变量 `SL_MACRO_*` / 宿主 API / 运行期只读访问）照常可用，本文第 3\~6 节仍有效。

***

## 1. 概述

`global.macro` 是一套**编译期宏数据面**：宏值在编译期定稿，注入为 Project 静态成员 `macro`，运行期可只读访问（`global.macro.X`）。

与 `global.data` 的区别：

|         | `global.data`                | `global.macro`                               |
| ------- | ---------------------------- | -------------------------------------------- |
| 注入形式    | Project 数据成员 `global.<name>` | Project 宏成员 `global.macro.<name>`            |
| 源码内修改入口 | 无（只读）                        | `.sp` Project 类的 `_before_(){}`（编译期，唯一合法修改点） |
| 编译前外部注入 | 无                            | CLI `--macro` / 环境变量 `SL_MACRO_*` / 宿主 API   |
| 运行期     | 只读                           | 只读（值是编译定稿后的最终值）                              |

***

## 2. static if

`static if` 是编译期条件编译：条件表达式只允许**宏引用**（`global.macro.X`）与**常量**（布尔/数值/字符串）的比较和逻辑运算，在 MetaCore 层求值，选中的分支子语句按原顺序平铺接入语句链——不引入运行时作用域，未选中分支完全不参与编译。

`static if` 是**语句级**构造，写在函数体内（不能用于类成员层的裁剪；成员级无条件隔离用 `@Exclude` attribute）：

```python
Project
{
    _main_()
    {
        static if global.macro.platform == "Win32"
        {
            SystemPrintln( "windows branch selected" )
        }
        static elif global.macro.platform == "Linux"
        {
            SystemPrintln( "linux branch selected" )
        }
        static else
        {
            SystemPrintln( "other branch selected" )
        }
    }
}
```

支持的语法：

| 类别   | 形式                                                                                                     |
| ---- | ------------------------------------------------------------------------------------------------------ |
| 比较运算 | `==` `!=` `<` `<=` `>` `>=`（`<` 系仅限数值操作数）                                                              |
| 逻辑运算 | `&&` `\|\|` `!`（`!` 仅一元前缀）                                                                              |
| 操作数  | `global.macro.X` 宏引用（裸引用，不带调用/下标/模板）、布尔/数值/字符串常量、括号                                                    |
| 条件整体 | 求值结果必须为布尔；布尔宏可直接作条件：`static if global.macro.useFastMath`                                                |

规则与限制：

- `static if` 的 `elif` / `else` **必须同样带 `static` 修饰**；普通 `if` 的分支不允许带 `static` 修饰（违者报 **LID 23008**）。
- 比较两侧操作数类型必须一致（布尔对布尔、数值对数值、字符串对字符串），违者报 **LID 23004**；`< <= > >=` 只允许数值比较，违者报 **LID 23003**。
- 引用未定义宏报 **LID 23001**；条件出现宏引用之外的语法（函数调用、算术运算等）报 **LID 23002**。
- 求值失败时该 `static if` 整体不接入任何语句（错误已由 MacroManager 记录，编译以 Error 终止）。
- 未选中分支里的代码**不参与语义分析与 IR**——里面的符号未定义也不会报错，这正是"按平台裁剪"的用法。

`@Exclude` attribute 与 `static if` 的分工：`@Exclude` 是**无条件**的编译前隔离（标注即跳过，PreCompile 时点，标准库 `Lib/Core/Exclude.sl`）；需要**按宏条件**裁剪时用 `static if`。

```python
class Foo
{
    @Exclude
    static winOnlyFun()
    {
        # 无条件隔离：该方法不参与编译，不进 module.json
    }
}
```

***

## 3. jsonc 配置：global.data 与 global.macro

`data` 的结构放在 `global` 下边（根级 `"data"` 已废弃：不再被读取，检测到即告警 LID 20041），`macro` 用来存放编译期宏数据。两者字段定义方式完全一样，值支持**布尔 / 数值 / 字符串**：

```jsonc
{
  "global": {
    "imports": [ "Std.Console" ],
    "replace": { "DEBUG": "true" },
    "data": {
      "greeting": "hello-macro",
      "baseCount": 42
    },
    "macro": {
      "platform": "Win32",
      "useFastMath": true,
      "maxThreads": 8
    }
  }
}
```

区别：

- `global.data`：注入为 Project 的数据成员，**运行期可读**（`global.greeting`），用于普通数据。
- `global.macro`：注入为 Project 的宏成员 `global.macro`，**编译期由 `_before_()` 钩子求值消费**（不进 runtime 语句流）；运行期也可以只读访问 `global.macro.platform`（值是编译定稿后的最终值）。

***

## 4. 在 .sp（Project）里修改宏值：_before_() 钩子

宏的初始值来自 jsonc。如果需要变化，**只能写在 `.sp` 工程文件 Project 类的 `_before_(){}` 钩子里**，其它任何地方都不允许对 `global.macro` 赋值：

```python
Project
{
    _main_()
    {
        global.println(global.macro.platform)
    }
    _before_()
    {
        # 编译期把 platform 从 jsonc 里的 "Win32" 改为 "Linux"
        global.macro.platform = "Linux"
    }
}
```

规则：

- 只允许 `global.macro.X = <常量>` 形式（`==` 不是赋值；复合赋值、`++`/`--` 均不支持）。
- 右值仅限**常量字面量**（布尔/数值/字符串）与**裸宏引用** `global.macro.Y`：带下标/调用/模板参数的宏引用报 **LID 23002**，运算表达式（如 `1 + 2`）报 **LID 23007**。
- 已知限制：数字一元负号（如 `-1`）在表达式路径解析为符号节点树而非常量项，同样落入 23007——负数宏值请直接写在 jsonc `global.macro` 初值里（jsonc 路径支持负数，如 `"retryLimit": -1`）。
- `_before_()` 钩子内的宏赋值在编译期被求值并**消费掉**——不会出现在最终代码里（不进 runtime）。
- 求值失败的赋值语句**不会被移除**，幸存至 Meta 层后连锁报 **LID 23006**（钩子外修改守卫），编译失败。
- 在 `_before_()` 之外（任何 `.sl`、`.sp` 的其它函数里）对 `global.macro` 赋值，编译直接报错：**LID 23006**（"global.macro 只能在 Project 的 _before_() 钩子中修改"）。

**可执行验证用例**（`test/Other/` 下，2026-10-12 全部实测通过）：

- 正例探针 [HookProbe](../../test/Other/HookProbe/HookProbe.md)：jsonc 初值 + `_before_` 覆盖（含宏引用右值按预扫描顺序读到已覆盖值）+ `_after_` 体存活 + `_main_` 运行期读取定稿值，含 Front 编译与 C VM 运行全链路预期输出。
- 配套负例（编译必失败，勿注册进任何用例集 jsonc；预期错误与复现命令见各工程 `.sp` 头注释与 `.md`）：
  - [HookBeforeUndefNegTest](../../test/Other/HookBeforeUndefNegTest/HookBeforeUndefNegTest.md)：右值引用未定义宏 → 23001，连锁 23006；
  - [HookBeforeSubscriptNegTest](../../test/Other/HookBeforeSubscriptNegTest/HookBeforeSubscriptNegTest.md)：宏引用带下标 → 23002，连锁 23006；
  - [HookBeforeExprNegTest](../../test/Other/HookBeforeExprNegTest/HookBeforeExprNegTest.md)：右值表达式 `1 + 2` → 23007，连锁 23006（`-1` 一元负号同根因）；
  - [HookMacroOutsideNegTest](../../test/Other/HookMacroOutsideNegTest/HookMacroOutsideNegTest.md)：`_main_` 内宏赋值 → 23006 单错。

***

## 5. 外部宏注入接口（编译前由外部环境设置）

jsonc 里的 `global.macro` 只是**初值**。编译前，外部环境（不同编译机器 / CI 流水线 / IDE 构建配置）可以通过三个入口设置宏值：

### 5.1 CLI 参数（推荐）

```
SimpleLanguageFront.exe <Project.sp> --macro platform=Linux --macro useFastMath=false
# 或简写 -m，可重复出现，后者覆盖前者；compile/run/export 命令同样支持
SimpleLanguageFront.exe compile -p <Project.sp> -m maxThreads=2
```

### 5.2 环境变量

```
# SL_MACRO_<宏名>=<值>，优先级低于 CLI --macro
set SL_MACRO_platform=Linux
SimpleLanguageFront.exe <Project.sp>
```

### 5.3 宿主程序 API

IDE / 构建脚本等直接嵌入 Front 库时，在 `ProjectManager.Run` 之前调用：

```csharp
// SimpleLanguage.Project 命名空间
CompileBeforeManager.ClearExternalMacros();   // 每次编译前重置
CompileBeforeManager.SetExternalMacro("platform", "Linux");
CompileBeforeManager.SetExternalMacro("maxThreads", "2");
ProjectManager.Run(spPath, inputArgs);
```

### 5.4 值类型推断

外部传入的都是字符串，按以下规则推断类型：

| 传入值                       | 推断类型                       |
| ------------------------- | -------------------------- |
| `true` / `false`          | 布尔（注意：必须小写，`True` 会被当作字符串） |
| `8` / `2` / `1.5`         | 数值                         |
| 其它（如 `Linux`、`x86_64-pc`） | 字符串（原样保留）                  |

### 5.5 优先级链（从低到高）

```
jsonc global.macro 初值  <  环境变量 SL_MACRO_*  <  CLI --macro / 宿主 SetExternalMacro  <  _before_() 钩子编译期修改
```

- 外部注入可以覆盖 jsonc 里已定义的宏，也可以**追加 jsonc 中没有的新宏**。
- `_before_()` 钩子依然是最高优先级——即使外部传了 `platform=Mac`，`.sp` 里 `_before_()` 的 `global.macro.platform = "Linux"` 仍会生效。
- 每次应用外部宏时会输出 Info 日志（LID 23009），标注来源（env / cli），便于 CI 排查。

### 5.6 验证示例

jsonc 初值：`platform="Win32", useFastMath=true, maxThreads=8`，`.sp` 的 `_before_()` 把 platform 改为 `"Linux"`：

```
SimpleLanguageFront.exe ProjectTest.sp --macro useFastMath=false --macro maxThreads=2
```

日志（LID 23009）：

```
macro: 外部设置已应用: useFastMath = false (cli)
macro: 外部设置已应用: maxThreads = 2 (cli)
```

运行期读取定稿值：`global.println(global.macro.platform)` 输出 `Linux`（_before_ 钩子优先级高于外部注入）。

***

## 6. 编译流程（宏在哪一层生效）

```
CLI --macro / 宿主 SetExternalMacro ──┐
环境变量 SL_MACRO_* ──────────────────┤
jsonc global.macro ───────────────────┼→ InjectProjectData 步骤：
                                          LoadFromConfig 装载 jsonc 初值 → 应用外部宏（env 先、cli 后）
.sp _before_ ─────────────────────────┘    → 预扫描 _before_ 内的 global.macro.X = 常量 赋值，
                                            编译期求值写入 CompileBeforeManager，并把该赋值语句从语句流中移除
                                         → 把定稿后的宏值注入为 Project 静态成员（运行期只读可见）
```

要点：

- 宏赋值/求值在编译后台 **MetaCore 层之前**（InjectProjectData 步骤）完成，不进 IR、不进 runtime。
- 语句流中的宏赋值语句被**移除**；其余语句照常编译。
- 运行期只能通过 `global.macro.<name>` 只读访问定稿值。

***

## 7. 错误码

| LID   | 名称                                                | 含义                                                  |
| ----- | ------------------------------------------------- | --------------------------------------------------- |
| 23000 | ProjectMacroManagerIssue                          | MacroManager 内部状态异常                                 |
| 23001 | ProjectMacroManagerMacroUndefined                 | `static if` / `_before_` 钩子引用了未在 `global.macro` 中定义的宏 |
| 23002 | ProjectMacroManagerNotSupportExpress              | `static if` / `_before_` 钩子宏表达式不支持该语法               |
| 23003 | ProjectMacroManagerNotSupportOperate              | `static if` 条件使用了不支持的运算符（`<` 系运算用于非数值等）             |
| 23004 | ProjectMacroManagerTypeMismatch                   | `static if` 条件操作数类型不一致，或条件整体不是布尔                    |
| 23005 | ProjectMacroManagerMacroValueInvalid              | 宏值不是布尔/数值/字符串                                       |
| 23006 | ProjectMacroManagerMacroOnlyModifyInCompileBefore | 在 `_before_()` 之外对 `global.macro` 赋值                |
| 23007 | ProjectMacroManagerMacroNotConst                  | 宏赋值右侧不是常量表达式                                        |
| 23008 | FileMetaSyntaxStaticIfFollowKey                   | `static if` 与 `elif`/`else` 的 `static` 修饰不一致        |
| 23009 | ProjectMacroManagerExternalMacroApplied           | 外部宏注入已应用（Info 日志，标注来源 env/cli，非错误）                  |

***

## 8. 相关源码位置

| 功能                                  | 文件                                                                                                                                       |
| ----------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| jsonc 解析 global.data / global.macro | `source/Front/Project/ProjectJsoncLoader.cs`                                                                                             |
| 宏值存储、_before_ 钩子赋值求值、static if 条件求值 | `source/Front/Project/CompileBeforeManager.cs`（`EvaluateStaticCondition` 及其求值链）                                                         |
| 宏成员注入 + _before_ 预扫描                | `source/Front/Project/PorjectClass.cs`（`InjectProjectMacroMember` / `PreScanCompileBeforeMacroAssign`）                                   |
| `static if` 解析（Parse 层）             | `source/Front/Parse/StructParseToSyntax.cs`（`isStaticModifier` / follow 一致性校验 LID 23008）                                                 |
| `static if` 类型定义（FileMeta 层）        | `source/Front/FileMeta/FileMetaSyntax.cs`（`FileMetaKeyStaticIfSyntax`）                                                                   |
| `static if` 编译期分支接入（MetaCore 层）     | `source/Front/Core/MetaMemberFunction.cs`（`HandleMetaSyntax` 的 `FileMetaKeyStaticIfSyntax` 分支）                                           |
| 非 _before_ 钩子赋值检查                   | `source/Front/Core/Statements/MetaAssignStatements.cs`                                                                                   |
| CLI `--macro` / `-m` 参数解析           | `source/Front/CLI/CommandInputArgs.cs`（`macroDefines` / `TryAddMacroDefine`）                                                             |
| 外部宏接线（CLI → CompileBeforeManager）   | `source/Front/Project/ProjectManager.cs`（`Run`）                                                                                          |
| `@Exclude` 处理器（PreCompile 跳过）       | `source/Front/Core/AttributeManager.cs`（`RegisterPreCompileExcludeHandler` / `ShouldExcludeByPreCompileAttribute`）、`Lib/Core/Exclude.sl` |
| 错误码定义                               | `source/Front/Log/LID.cs`、`source/Front/Log/ErrorDefinitions.csv`                                                                        |
