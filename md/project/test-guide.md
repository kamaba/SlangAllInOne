# 测试引导：测试用例与测试工程对照

> 面向三个问题：**测试用例源码在哪里？每个测试工程测什么？想测某个功能该跑哪个工程？**

仓库测试分两层：

- **测试用例集**：[`test/`](../../test/) 下的 SimpleLanguage 源码，每个子目录一个主题（`ProjectTest.sp` + `ProjectTest.jsonc` + 若干 `.sl`）。
- **测试宿主工程**：[`project/`](../../project/) 下的 **唯一** C# 控制台工程 `CSimpleVMTest`（2026-10-18 八合一：原 `CSimpleVMCore/Std/Math/Special/BenchMark/RenderTest` 与 `Test`/`Test2` 均已并入），负责「调用 C# 前端编译测试集 → 导出模块包 → **拷入发布包经包内 slang 应用 run-disk 执行**（2026-10-18 晚起：Debug → `package\win32-debug`、Release → `package\win32-release`，标准库取自包内 `lib\`）」；用例集经命令行参数或 VS launchSettings.json profile 分流。

---

## 1. 测试用例集（`test/`）

| 目录 | 测什么 | 代表用例 | 宿主入口（`CSimpleVMTest -- <选择器>`） |
|------|--------|----------|--------------|
| `BaseTest/` | 语言核心语法：变量/作用域、类/继承/接口、泛型与模板、enum/data、闭包、协程、控制流、容器（List/Map/Set/Queue/Stack/Tuple）、Float8/16、指针/引用、Result、goto 等（60+ 个 `.sl`） | `GlobalTest.sl`、`StringTest.sl`、`GenClass.sl`、`ClosureTest.sl`、`CoroutineTest.sl`、`TryTest.sl`、`Float8Test.sl` | `BaseTest` |
| `NullFastTest/` | Null 相关快速回归（单文件，`Other/` 下） | `NullFastTest.sl` | `NullFast` |
| `ExpendTest/` | 标准库与扩展库：IO（Console/File/Directory/DateTime）、数据格式（Json/Xml/Yaml/Toml/Csv）、嵌入式数据库（Sqlite3）、容器（List/Map/LinkedList/Sort）、Isolate、宏、Attribute、模块与跨语言调用 | `JsonTest.sl`、`FileTest.sl`、`Sqlite3Test.sl`、`ListTest.sl`、`IsolateTest.sl`、`AttributeTest.sl` | 无参默认（`ExpendTest`） |
| `MathTest/` | 数学库：内置 Math 成员函数、MathVMLib 系统方法、运算符分派、矩阵（3x3/4x4/任意尺寸）、FFI 数学、大数（BigNumber/BigDecimal）、因数分解 | `MathTest.sl`、`FFIMathTest.sl`、`Matrix4x4Test.sl`、`MatrixBigTest.sl` | `MathTest` |
| `SpecialTest/` | FFI 与跨语言互操作、MLIR AOT 实验、外部进程执行（Std.OS.Process） | `FFITest.sl`、`CSharpCall.sl`、`CPythonCall.sl`、`JavascriptCall.sl`、`LuaCall.sl`、`AOTTest.sl`、`ProcessTest.sl` | `SpecialTest` |
| `BenchMark/` | 性能基准 | `Fibonacci.sl`、`Loop.sl`、`Levenshtein.sl`、`StringBench.sl` | `BenchMark` |
| `MysqlTest/` | MySQL 库（需本机数据库环境） | `MysqlTest.sl`、`MysqlApiTest.sl` | 传显式工程路径 |
| `RenderTest/` | 渲染相关（进行中） | `MathTest.sl` | `RenderTest` |
| `TensoraTest/` | 张量与机器学习库：张量、自动微分、CNN/NN、经典 ML、TTS | `TensorTest.sl`、`AutogradTest.sl`、`CnnTest.sl` | 传显式工程路径 |
| `Other/*`（探针/负例等） | JsonTest、Platform*×6、InlineLambda*、AutoInline、InlineMethod、ARC/GC 探针（CoroGC/Mi/NestedGC/OOM/SBA/TLSF）、AtSignLabel、NetTest、HttpWebTest、MyTest、SFRepro… | — | `-- <命名用例>`（全表见宿主 `Program.cs` `Presets`） |

---

## 2. 测试宿主工程（`project\CSimpleVMTest`，唯一）

2026-10-18 八合一后仅此一个宿主；用例集由「第一个非 `-` 开头参数」选择（VS 内对应 `Properties\launchSettings.json` 的 profile）：

| 选择器 | 测试集 | 等价旧宿主 | 说明 |
|--------|--------|-----------|------|
| 无参（缺省） | `test\ExpendTest\ProjectTest` | CSimpleVMTest / CSimpleVMStdTest / Test2 | 通用回归 / 标准库扩展库 |
| `BaseTest` | `test\BaseTest\ProjectTest` | CSimpleVMCoreTest / Test | 语言核心语法 |
| `MathTest` | `test\MathTest\ProjectTest` | CSimpleVMMathTest | 数学库 |
| `SpecialTest` | `test\SpecialTest\ProjectTest` | CSimpleVMSpecialTest | FFI / 互操作 / AOT |
| `BenchMark` | `test\BenchMark\BenchMark` | CSimpleVMBenchMarkTest | 性能基准 |
| `RenderTest` | `test\RenderTest\ProjectTest` | CSimpleVMRenderTest（原传参入口） | 渲染 |
| `NullFast` 等命名用例 | `test\Other\<名>\…`、`samples\Game\TankGame` | （原 CSimpleVMTest 专属） | 探针/负例/示例，全表见宿主 `Program.cs` `Presets` |
| 显式路径 | 任意（相对仓库根或绝对，可不带 `.sp`） | （各宿主通用能力） | 如 `test\MysqlTest\ProjectTest` |

其余选项：`-test`（跑 `_test_` 入口）、`-start=false`（跳过前端编译直接运行上次导出模块）、`-debug`（Release 进程模式启动前暂停挂调试器）、`-O0..-O3`（转发 Front）、`--` 之后 token 透传 `Project._inputArgs`；负例工程（如 `InlineLambdaForbiddenTest`）Front 编译预期失败时按预期 LID 命中数判定通过。

### C VM / 发布包构建方式

- **主路径（推荐）**：`scripts\build-vm-win.ps1 -Configuration Debug`（CMake + Ninja/clang 树，`csimple_lang\build\Debug\bin\` 同时产出 `csimple_lang.exe` 与 `csimple_lang_dll.dll`），与命令行开发共用同一棵树。
- **发布包（宿主执行端依赖）**：`scripts\build-packages.ps1` 一键四包；宿主 csproj 已不再引用 `csimple_lang_lib.vcxproj`（2026-10-18 晚随执行端切换移除），C VM 运行时由发布包 `bin\` 提供。

---

## 3. 一个测试集长什么样

每个测试集是「三件套」+ 若干用例文件，以 `test/BaseTest/` 为例：

```
test/BaseTest/
├── ProjectTest.sp      # 入口：_main_ 里逐个调用 XxxTest.fun()
├── ProjectTest.jsonc   # 工程配置：compileFiles.files 列出参与编译的 .sl
├── ObjectTest.sl       # 用例：一个类，提供 fun() 测试入口
├── StringTest.sl
└── ...（60+ 个 .sl）
```

**新增一个用例**（三步）：

1. 在测试集目录新建 `XxxTest.sl`，写一个类并提供 `fun()`（或带断言的测试方法）；
2. 在 `ProjectTest.jsonc` 的 `compileFiles.files` 里注册该文件；
3. 在 `ProjectTest.sp` 的 `_main_` 中追加 `XxxTest.fun();`。

---

## 4. 怎么跑

### Visual Studio

打开 `CSimpleVMTest`（或解决方案）在 launchSettings.json 里选好 profile（`ExpendTest (default)` / `BaseTest` / `MathTest` / `SpecialTest` / `BenchMark` / `RenderTest` / `NullFast`…）后 **F5 调试 / Ctrl+F5 运行**。VS(Full MSBuild) 构建时会先自动触发 C VM 构建（见上节）。宿主运行前会把工作目录切到测试集目录，因此用例里的相对路径资源（如 `Sqlite3Test` 的 `Resources/`）在 VS 与命令行下行为一致。

### VSCode（运行与调试，SLang 工程级）

仓库根 `.vscode\launch.json` 已为**全部测试工程**预置 SLang DAP 调试配置（2026-10-20 起，62 项，`type: "slang"`，`program` = 各工程 `.sp` 入口）：调试面板下拉选「**调试 SLang: \<名\>**」→ **F5 调试 / Ctrl+F5 运行**。断点打在 `.sl` 源文件（slang_vscode_plugin P3-1 DAP：断点/单步/变量树/表达式求值；调试会话即禁 JIT）。

- **覆盖清单**：六大用例集 + TensoraTest、`test\Other\*` 全部探针与功能用例（Json/Yaml/Xml/Websocket/Net/HttpWeb/Inline*×3/ARC·GC 探针×6/Const*·Final*·Hook 系/MiniSmoke/WasmDemo/GlobalSlot/ExportPerm/Crawler/Ref·Return·ReDebug·MemberInit 等）、NaNBench/EqBench、负例工程（名称带「负例」标注，F5 即走查预期 LID 拦截或平台拒跑）、示例 GameTank（默认 `args: ["auto"]` 自动化）。
- **通用入口**：「调试 SLang: 当前工程」随活动编辑器自动定位（活动文件是 `.module.json` 用它，否则取当前 `.sp` 工程）；各配置可加 `"stopOnEntry": true` / `"args": ["…"]`（程序参数，透传 `Project._inputArgs`）。
- **前提**：安装 slang_vscode_plugin（提供 `slang` DAP 类型）；`settings.json` 的 `slang.executable.path` 指向的宿主已构建（现为 `SlangAllInOne\package\win32-release\slang.exe`，产品层 = AOT Front + Release 加固 cvm，改 Front/VM 代码后 `dotnet publish SlangAllInOne -c Release` 刷新；`--debug`/调试会话为 SL 语言级调试且自动禁 JIT，Debug/Release 两层语义见根 AGENTS.md §5）。
- （宿主 C# 侧调试仍走 VS：打开 `SlangAllInOne.sln` 选 `CSimpleVMTest` 的 launchSettings profile。）

### 命令行（dotnet）

```powershell
# 默认测试集（ExpendTest，Debug 配置）
dotnet run --project Project\CSimpleVMTest\CSimpleVMTest.csproj -c Debug

# 指定套件（套件预设选择器）
dotnet run --project Project\CSimpleVMTest\CSimpleVMTest.csproj -- MathTest -c Release

# 命名用例（NullFast 快速回归等）
dotnet run --project Project\CSimpleVMTest\CSimpleVMTest.csproj -- NullFast

# 任意工程路径（不带 .sp 也可）：MysqlTest / TensoraTest 等
dotnet run --project Project\CSimpleVMTest\CSimpleVMTest.csproj -- SLangCore\test\Other\MysqlTest\ProjectTest

# 程序参数透传（"--" 之后 token 进 Project._inputArgs）
dotnet run --project Project\CSimpleVMTest\CSimpleVMTest.csproj -- BenchMark -- -- w3
```

### Debug 与 Release 的行为差异（`CSimpleVMTest` 宿主）

2026-10-18 晚起执行端统一改为 **发布包 slang 应用**（用户指令，取代旧的 P/Invoke / csimple_lang.exe 直调）：宿主把编译产物拷入包内 `<package>\<Module>\`，再调用包内 `slang.exe run-disk` 执行；`moduleReferences` 相对解析在包内落空 → C VM 走官方库直查 `<slang.exe 目录>\lib\`，**标准库即取自包内 lib\ 目录**。子目录深度与 `out\export\<Module>` 一致，SpecialTest 等插件 lib 按相对路径回仓库原位加载。**非系统库引用模块联动拷贝**（2026-10-20 起）：宿主解析主模块 `moduleReferences`，把非 Core/Std/Math 的引用（如 ExpendTest→SLangServer）导出产物一并拷入 `<package>\<引用名>\`——此前引用不跟随会被 C VM 静默 skip（仅 VM.txt Warning、退出码 0），跨模块调用全落空壳致测试假绿/挂死（复盘见 `md/ai/troubleshooting/06-build-engineering.md` [2026-10-20]）。

| 配置 | 运行方式（包） | Front 导出参数 | 适合场景 |
|------|---------------|----------------|----------|
| Debug | `package\win32-debug\slang.exe`（框架依赖宿主 + bin\ 调试 C VM + lib\ slb+json 官方库） | `--format binary+json`（slb 主产物 + json 调试副本，两配置统一） | 验证 Debug 发布包；json 副本便于人工对照排查 |
| Release | `package\win32-release\slang.exe`（Native AOT 一体化 + bin\ 加固 C VM，**JIT 默认开**，`--no-jit`/`SL_JIT=0` 关闭） | 同上 | 性能 / 接近真实分发形态 |

包需先构建：`powershell -ExecutionPolicy Bypass -File SlangAllInOne\scripts\build-packages.ps1`（或分别 `dotnet publish SlangAllInOne\SlangAllInOne.csproj -c Debug|Release`）；改了 Front/C VM 后需重编标准库（`CompileStdlib` 自动同步四包 lib\）再发布。

**负例工程**（编译期预期失败 = 通过）：宿主内置注册表（`Program.cs` `s_negativeFrontCases` / `s_negativeRunCases`）校验预期 LID 全部命中 / 预期退出码+输出标记双命中——PlatformNegTest、PlatformOverrideNegTest、PlatformAotNegTest（Front LID 拦截）、AtSignLabel（@csharp_mono 通道负例）、InlineLambdaForbiddenTest、PlatformVariantNegTest（运行期 linux-only 变体在 windows 必拒跑）。**交互式用例**：GameTank 为键盘游戏，自动化回归传 `-- auto`（跑 60 帧自动退出；Windows 管道下 `keyAvailable` 恒 false，交互键无法注入）。

### 常用参数

| 参数 | 作用 |
|------|------|
| `<套件|命名用例|工程路径>` | 第一个非 `-` 开头参数：套件预设（BaseTest/ExpendTest/MathTest/SpecialTest/BenchMark/RenderTest）、命名用例（NullFast…）或显式工程路径（可不带 `.sp`） |
| `-test` | 运行工程入口的 `_test_` 而不是 `_main_` |
| `-start=false` | 跳过前端编译，直接运行上一次导出的模块 |
| `-debug` | Release 进程模式下启动 C VM 前暂停（挂调试器用） |
| `-O0..-O3` | 转发 Front 编译优化级别（缺省 = 编译器默认级别） |
| `-- <token…>` | 之后所有 token 透传给 C VM 作 `Project._inputArgs` 程序参数 |

---

## 5. 常见问题

- **`slang.exe not found in package`**：发布包尚未构建。执行：`powershell -ExecutionPolicy Bypass -File SlangAllInOne\scripts\build-packages.ps1`；改过 Front/C VM 后先重编标准库再发布（宿主不回退开发树——其意义即验证发布包形态）。
- **跑 ExpendTest 报 `SLangServer` 引用找不到（references 未命中，编译中止）**：ExpendTest 依赖第四件库模块 `SLangServer`（`SLangCore\Lib\SLang\Server\`，非 Core/Std/Math 系统库，不享受运行目录 lib\ 官方库回落）。`compile-stdlib` 三件套不覆盖它，需先手动编译一次：`dotnet run --project simple_language\source\SimpleLanguageFront.csproj -- compile -e ir -p SlangAllInOne\SLangCore\Lib\SLang\Server\Server.sp --format binary+json --no-banner`（产物落 `SlangAllInOne\out\export\SLangServer\`）。
- **`test\Other\*` 用例集 references 形态（2026-10-18 规则定稿）**：全部 53 个测试工程 jsonc 已统一为 `{ "path": "./lib/<名>.module.slb" }`（Core/Std/Math 系统库，工程内落空自动回落运行目录 lib\ 官方库直查，name/uuid 省略由导出侧自动回填）；非系统库引用（SLangServer/Tensora/SLMysql/ConstLib/FinalLib）path 直指产物文件 `<上跳>/out/export/<模块>/<模块>.module.json`，未命中即报错中止编译（2026-10-18 前的 `../../../../out/export/<X>` 全量旧路径已废弃）。
- **字符串错乱 / 断言随机失败**：通常是新旧两棵构建树互相覆盖 DLL 所致，坚持只用 `csimple_lang\build\Debug` 这棵 Ninja 树（见第 2 节构建方式说明）。
- **前端编译失败**：看 `out/export/<测试集名>/` 与 `build/logs/` 下的日志定位（详见 [`md/ai/DEBUG_WORKFLOW.md`](../ai/DEBUG_WORKFLOW.md)、[`md/ai/EXPORT_PATHS.md`](../ai/EXPORT_PATHS.md)）。
