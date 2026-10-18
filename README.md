# SlangAllInOne — SLang 语言一体化工具链

**中文** | [English](README_EN.md)

**SLang** 是一门从零构建的静态类型语言：编译器前端（C#/.NET 8）把 `.sl` 源码编译为 SLIR 模块包，C99 虚拟机负责执行；本仓库是统合两者的宿主与分发总包。

```
.sl 源码 ──► Front 编译器（C#，simple_language）──► SLIR 模块包（json / slb）──► C99 虚拟机执行
                                  ▲
               本仓库统合宿主 slang 串起全链路：编译 → 内存直传 → 运行
```

本仓库的统合宿主 **`slang`** 在单个 .NET 8 进程内完成「Front 进程内编译 → SLIR 包内存直传 → C VM P/Invoke 执行」：`slang run <工程>` 即**编译即运行**，中间产物不落盘。

## 相关开源仓库

| 仓库 | 定位 | 技术栈 |
|------|------|--------|
| **SlangAllInOne**（本仓库） | 一体化总包：统合宿主 `slang` + 标准库源码 + 测试用例集 + 用户文档 + 构建/发布脚本 | C#/.NET 8 |
| [kamaba/simple_language](https://github.com/kamaba/simple_language) — **FrontEnd 编译器** | 词法/结构解析、语义与类型系统、IR 生成、SLIR 导出、CLI；opcode 枚举与 C VM 逐项对齐 | C#/.NET 8 |

Front 编译产出 SLIR，C VM 执行 SLIR，本仓库把两者粘合为一条命令，并承载标准库、测试与文档（C VM 以运行时二进制随发布包 `bin\` 分发）。**从源码构建时本仓库与 simple_language 需放在同一父目录下平级摆放**（工程引用为跨仓库相对路径），见[「从源码构建」](#从源码构建)。

## 语言特性

- **静态类型系统**：类 / 继承 / 接口 / 枚举 / 泛型模板（`template`）/ 类型别名 / attribute 注解系统（PreCompile / Compiling / Preload / Runtime 四时点）
- **现代并发**：协程（`spawn` / `await` / `yield` 关键字 + `Task` / `Channel`），isolate 隔离岛（跨堆并行 + 端口消息通信，支持零拷贝转移）
- **表达式能力**：闭包、内联 lambda（`=>` 调用点编译期展开）、`Range`、字符串插值 `$x`、`data` 动态对象、异常（`try / catch / throws`）
- **低精度浮点**：`Float8` / `Float8_E5M2` / `Float16` / `Float16_Brain` 原生字面量与运算语义
- **跨语言互操作**：FFI 外部函数调用（`@DllImport`）、系统方法下沉（热点函数绑定 C VM 原生实现，如矩阵运算直调 `math_lib.dll`）、插件系统（`@csharp_mono(){}` 内联 C#、Java Hotspot 等）
- **多目标形态**：SLIR JSON / SLB 二进制模块包（体积约 JSON 的 2%）、AOT 导出（LLVM IR `.ll`）、WebAssembly（浏览器 Playground）

## 标准库一览

| 模块 | 内容 |
|------|------|
| **Core** | 容器（List / Map / Set / Queue / Stack / LinkedList / Tuple / Channel）、JSON / XML / YAML / TOML / CSV、ByteBuffer / Codec / LengthPrefix、Lz4 压缩、Protobuf 编解码、Stream 元素流 |
| **Math** | 三精度数学（Mathd / Mathf / Mathh，FFI 直调原生库）、向量与矩阵（三精度 9 向量 + 6 矩阵值类型）、动态矩阵、BigNumber / BigDecimal / Factor 大数与数论 |
| **Std** | IO（File / Directory / Console）、Net（TCP / UDP / TLS / HTTP/1.1 / WebSocket / MQTT，协程化挂起读写）、Sqlite、Redis、Log / Profiling / Trace / Monitor、isolate、Base64 / Sha1、GZip / Zip、DateTime / Process / Timer |
| **SLang.Server** | HTTP / WebSocket 服务框架（路由 / 请求 / 响应链式 / BodyParser） |
| **SLang.Render** | 渲染类型（Mesh / Material / Texture / Shader / Camera…） |
| **Tensora** | 张量 / 张量算子 / 自动微分 / 优化器 / Transformer（建设中） |
| **SLMysql** | MySQL 客户端（⚠ 静态链接 GPL-2.0 的 MySQL Connector/C，**不随官方发布包分发**） |

## 快速开始

### 1. 从 Release 获取（目标机零依赖）

从 [Releases](https://github.com/kamaba/SlangAllInOne/releases) 下载最新版并解压（每版双平台同发）：

- `slang_release_<v>_win-x64.zip`（Windows x64）
- `slang_release_<v>_linux-x64.tar.gz`（Linux x64，glibc ≥ 2.43）

`slang` 主程序为 **Native AOT 自包含原生二进制**，无需安装 .NET 运行时。包内容：

```
slang_release_<v>/
├── slang[.exe]         # 统合宿主：Front 编译 + C VM 运行（AOT 单文件）
├── bin\                # C VM 运行时（hardened Release：LTO + 启动反调试）+ sqlite
├── lib\                # 系统自带标准库 Core/Math/Std *.module.slb（平铺单目录）
├── modules\            # （未来）spm.exe 包管理器的用户包目录——按需创建
├── plugins\            # 插件目录：插件安装与管理位（区别于普通包）
├── test\RefProbe\      # 开箱示例：纯名引用官方库的最小工程
└── md\                 # ~93 篇用户文档（语法 / 库 / 工程 / 日志 / 插件）
```

> 目录方案决策记录见 [md/project/package-layout.md](md/project/package-layout.md)（`lib` = 系统自带库、`modules` = 未来 spm.exe 包管理、`plugins` = 插件）。

### 2. 开箱即跑

```powershell
# Windows（Linux 同构：./slang run test/RefProbe/RefProbe）
slang.exe run test\RefProbe\RefProbe
```

用户工程的 `references` 直接写官方库名（`Core` / `Std` / `Math`）即可——Front 编译期与 C VM 运行期都会在 `<slang 目录>\lib\` 下按名直查（slb 优先；未来 spm 安装的包在 `modules\` 下同链查找），零相对路径配置。

### 3. SLang 代码长这样

```sl
import Core;
import Std;

class Greeter
{
    string name = "";

    _init_( string name )
    {
        this.name = name;
    }

    string hello()
    {
        ret "Hello, " + this.name + "!";
    }
}

Project
{
    int add2( int a, int b )
    {
        ret a + b;
    }

    _main_()
    {
        greeter = Greeter( "SLang" );
        SystemPrintln( greeter.hello() );

        # 容器
        List<int> nums = new();
        nums.add( 1 );
        nums.add( 2 );
        nums.add( 3 );
        for n in nums
        {
            SystemPrintln( "n = $n" );
        }

        # 协程
        Task task = spawn add2( 20, 22 );
        int sum = await task as int;
        SystemPrintln( "20 + 22 = $sum" );
    }
}
```

### 从源码构建

前置：.NET SDK 8、CMake ≥ 3.18、clang（脚本可自动补装 cmake/ninja）、MSVC（native 工程）；Linux 侧走 WSL。

```powershell
# 本仓库与 Front 编译器仓库平级摆放（宿主工程跨仓库引用 Front 源码）
#   <root>/SlangAllInOne
#   <root>/simple_language
cd <root>

# 1. 构建 C VM 运行时（→ csimple_lang_dll.dll，脚本自动定位工作区）
powershell -File SlangAllInOne\scripts\build-vm-win.ps1 -Config Debug

# 2. 编译即运行：Front 进程内编译 → SLIR 内存直传 → C VM 执行
dotnet run --project SlangAllInOne\SlangAllInOne.csproj -- run SlangAllInOne\SLangCore\test\BaseTest\ProjectTest --no-banner

# 3. 一键全流程：VM 双平台构建 → 标准库 → 6 用例集编译 + 运行
powershell -File SlangAllInOne\scripts\build-all.ps1 -Run
```

全仓开发入口 = [SlangAllInOne.sln](SlangAllInOne.sln)（VS 打开一个 sln 构建全部：宿主 / Front / 编译器 / 测试宿主 / native 库 / 插件 / 工具；工程清单与路径映射见 [PROJECTS.md](PROJECTS.md)）。

## slang 命令

| 命令 | 说明 |
|------|------|
| `compile <工程>` | Front 进程内编译，默认磁盘导出；`--in-memory` 时包留在内存 |
| `run <工程>` | **编译即运行**：内存编译 → C VM 内存入口，模块不落盘 |
| `run-disk <module.slb\|module.json>` | 运行已导出的模块包（两种格式，magic 自动探测） |
| `info <module.slb\|module.json>` | 查看模块元数据 |
| `version` | Front 版本 + C VM DLL 路径 / 配置 |
| `pack-modules` | 编译标准库三件套并平铺打进 `lib\`（发布包自动调起） |
| `pack-docs` | 打包用户文档进 `md\`（发布包自动调起） |

常用选项：`-p, --project <路径>`｜`-O0..-O3`（优化级别）｜`--format json|binary`（SLB 二进制导出）｜`--in-memory`｜`--debug`（C VM 指令追踪）｜`--force-run`（跳过平台校验）｜`--cvm Debug|Release`（选 C VM 构建树）｜`-- <args…>`（之后参数进 `Project._inputArgs`，源码经 `global._inputArgs` 读取）。

退出码：`0` 成功；`1` Front 编译失败或参数错误；`4` 找不到 C VM DLL（先跑步骤 1）；其他非 0 为 C VM 运行失败原样透传。

## 仓库结构

```
SlangAllInOne/
├── SlangAllInOne.sln / .csproj / Program.cs   # 统合宿主 slang（全仓开发入口）
├── FrontEnd/   # 进程内调 Front CommandExecutor（compile -e ir --in-memory）
├── Backend/    # C VM P/Invoke（内存直传入口 + DLL 定位）
├── Pack/       # pack-modules / pack-docs 打包命令（publish 自举）
├── Project/    # 标准库编译驱动（CompileStdlib：core/math/std 分流）、测试宿主（CSimpleVM*Test、Test、Test2）、native 库（cvm_math_lib…）
├── SLangCore/
│   ├── Lib/    # 标准库源码（Core / Math / Std / SLang：Server、Render、Mysql、Tensora）
│   ├── test/   # 测试用例集（BaseTest / ExpendTest / MathTest / SpecialTest / BenchMark / RenderTest / TensoraTest…）
│   └── samples/# 示例（HelloWorld / GUI / 斐波那契…）
├── md/         # 全部用户文档（syntax / lib / project / log / plugins + ai 内部文档）
├── scripts/    # 一键脚本（build-all / build-vm-win|linux / compile-* / run-tests-* / release-slang）
├── tools/      # ExtractLogs / LidIndexer / SLBRoundTrip（slb↔json 往返验证）
└── out/export/ # 编译产物根（*.module.json / *.module.slb + Logs / DebugCode 调试快照）
```

Front 编译流水线（排障主干）：`Code → Token → Node → File → Meta → IR → module.json`，各阶段快照落在 `out/export/<模块>/DebugCode/`，日志在 `Logs/`（看最早一条 Error）。

## 文档导航

总入口：[md/INDEX.md](md/INDEX.md)（全仓 md 总索引）。各分组摘要如下。

### 语法（md/syntax/）

| 分组 | 文档 |
|------|------|
| 基础 | [introduction](md/syntax/introduction.md)（总述）、[keywords](md/syntax/keywords.md)（关键字与语法糖总表）、[namespace](md/syntax/namespace.md)、[variable](md/syntax/variable.md)、[local](md/syntax/local.md)、[global](md/syntax/global.md) |
| 类型与运算 | [number](md/syntax/number.md)、[float8_16](md/syntax/float8_16.md)（Float8/Float16）、[string](md/syntax/string.md)、[data](md/syntax/data.md)、[array](md/syntax/array.md)、[type](md/syntax/type.md)、[typealias](md/syntax/typealias.md)、[express](md/syntax/express.md)、[operator](md/syntax/operator.md)、[cast](md/syntax/cast.md) |
| 控制流 | [if](md/syntax/if.md)、[switch](md/syntax/switch.md)、[forwhiledowhile](md/syntax/forwhiledowhile.md)、[range](md/syntax/range.md)、[labelgoto](md/syntax/labelgoto.md)、[try](md/syntax/try.md)（异常） |
| 面向对象 | [class](md/syntax/class.md)、[object](md/syntax/object.md)、[interface](md/syntax/interface.md)、[extend](md/syntax/extend.md)（继承）、[function](md/syntax/function.md)、[enum](md/syntax/enum.md)、[attribute](md/syntax/attribute.md)（注解）、[bind](md/syntax/bind.md) |
| 高级机制 | [template](md/syntax/template.md)（泛型）、[marco](md/syntax/marco.md)（宏）、[coroutine](md/syntax/coroutine.md)（协程权威）、[isolate](md/syntax/isolate.md)、[inline_lambda](md/syntax/inline_lambda.md)、[system_method](md/syntax/system_method.md)、[result](md/syntax/result.md) |

### 库（md/lib/）

| 分组 | 文档 |
|------|------|
| 容器 | [List](md/lib/Std/Contraint/List.md)、[Map](md/lib/Std/Contraint/Map.md)、[HasSet](md/lib/Std/Contraint/HasSet.md)（Set）、[Tuple](md/lib/Std/Contraint/Tuple.md)、[Queue](md/lib/Std/Contraint/Queue.md)、[Stack](md/lib/Std/Contraint/Stack.md)、[LinkedList](md/lib/Std/Contraint/LinkedList.md) |
| Core | [Lz4](md/lib/Core/Lz4.md)、[ProtocalBuffers](md/lib/Core/ProtocalBuffers.md)（protobuf）、[Stream](md/lib/Core/Stream.md)（元素流） |
| Math | [总览](md/lib/Math/Math.md)、[数学函数](md/lib/Math/Math-Functions.md)、[大数](md/lib/Math/Math-BigNumbers.md)、[向量](md/lib/Math/Math-Vectors.md)、[矩阵](md/lib/Math/Math-Matrices.md)、[动态矩阵](md/lib/Math/Matrix.md) |
| Std | [Env](md/lib/Std/Env.md)、[Component](md/lib/Std/Component.md)、[Sqlite](md/lib/Std/Sqlite.md) |
| 网络（md/lib/Std/net/） | [Net 总览](md/lib/Std/net/Net.md)、[Tcp](md/lib/Std/net/Tcp.md)、[Udp](md/lib/Std/net/Udp.md)、[StreamImplent](md/lib/Std/net/StreamImplent.md)（流实现）、[Http](md/lib/Std/net/Http.md)、[Websocket](md/lib/Std/net/Websocket.md)、[Mqtt](md/lib/Std/net/Mqtt.md) |
| 服务框架 | [Server](md/lib/Server.md)（HTTP/WS 服务框架） |

### 工程（md/project/）

| 文档 | 内容 |
|------|------|
| [project.md](md/project/project.md) | 工程概念：编译文件列表、入口与全局变量 |
| [project-config-jsonc-guide.md](md/project/project-config-jsonc-guide.md) | **`.jsonc` 工程配置权威说明**（compileFiles / systemCalls / export…） |
| [project_sp-guide.md](md/project/project_sp-guide.md) | `.sp` 入口：`_main_` / `_test_`、`Project{}`、`global.data` |
| [project-module.md](md/project/project-module.md) | 模块与类组织方式 |
| [project_arguments.md](md/project/project_arguments.md) | CLI 程序入参 `global._inputArgs` |
| [static-if.md](md/project/static-if.md) | `global.macro` 宏数据面与注入优先级链 |
| [optimization.md](md/project/optimization.md) | 编译优化等级 `-O0..-O3` |
| [environment-guide.md](md/project/environment-guide.md) | `Environment.*` 平台环境与 jsonc `platform` 段 |
| [ffi.md](md/project/ffi.md) | **FFI 外部函数接口**（`@DllImport` / `FFI.Library` / `dllImports`） |
| [project-system-method-call-guide.md](md/project/project-system-method-call-guide.md) | 系统方法下沉 C VM 的完整链路 |
| [exporter.md](md/project/exporter.md) | AOT Exporter：IR → LLVM IR `.ll` |
| [test-guide.md](md/project/test-guide.md) | **测试引导**：用例集 ↔ 宿主工程对照与运行方式 |

### 日志 / 插件 / 根级

| 文档 | 内容 |
|------|------|
| [log/log-system-guide.md](md/log/log-system-guide.md)、[log/log-debug-usage.md](md/log/log-debug-usage.md) | 日志系统与 `Log / Logger / Profiling / Trace / Monitor` 使用 |
| [plugins/CSharp_Mono.md](md/plugins/CSharp_Mono.md) | `@csharp_mono(){}` 内联 C# |
| [plugins/PLUGIN_TEMPLATE.md](md/plugins/PLUGIN_TEMPLATE.md) | 插件开发标准模板 |
| [CLI.md](md/CLI.md)、[GUIDE.md](md/GUIDE.md) | `cx` 命令体系 / 文档引导 |
| [SL语法与编码规范总表.md](md/SL语法与编码规范总表.md) | 语法与编码规范单点引用总表（48 篇语法提炼） |
| [PROJECTS.md](PROJECTS.md) | **工程清单与新旧路径映射**（改工程先读） |
| [RELEASE.md](RELEASE.md) | **发布策略唯一权威**（AOT-only 双平台） |

## 测试

| 用例集 | 覆盖 | 宿主入口（唯一宿主 `CSimpleVMTest`，2026-10-18 八合一） |
|--------|------|----------------------|
| BaseTest | 语言核心语法（类/泛型/协程/容器/Float8…，60+ `.sl`） | `-- BaseTest` |
| ExpendTest | 标准库/扩展库（Json/Xml/File/Sqlite/Isolate/Attribute/Server…） | 无参默认（`-- ExpendTest`） |
| MathTest | 数学库（FFI 数学/矩阵/大数） | `-- MathTest` |
| SpecialTest | FFI/跨语言/AOT/进程执行 | `-- SpecialTest` |
| BenchMark | 性能基准（Fibonacci/Levenshtein/Loop…） | `-- BenchMark` |
| RenderTest / TensoraTest / MysqlTest | 渲染 / 张量 / MySQL | `-- RenderTest` / 传显式工程路径 |
| 探针/负例等命名用例 | NullFast/JsonTest/Platform*/Inline*/GC 探针/GameTank… | `-- <名>`（全表见宿主 `Program.cs`） |

联合测试宿主 = C# Front 编译用例 → C VM 执行（Debug = P/Invoke 进程内可同进程调试，Release = 独立进程）；VS 内经 launchSettings.json profile 分流。完整说明见 [md/project/test-guide.md](md/project/test-guide.md)。

```powershell
powershell -File scripts\compile-tests.ps1          # 编译用例集
powershell -File scripts\run-tests-win.ps1          # Windows 运行 + 退出码汇总
powershell -File scripts\build-all.ps1 -Run         # 一键全流程
```

## 发布

发布策略（[RELEASE.md](RELEASE.md) 唯一权威）：**只发 Native AOT 包，每版双平台同发**——同一 GitHub Release 挂 `slang_release_<v>_win-x64.zip` 与 `slang_release_<v>_linux-x64.tar.gz`，目标机无需 .NET 运行时；框架依赖的 Debug 包仅本地开发用。一键发布（维护机）：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File SlangAllInOne\scripts\release-slang.ps1 -Version <x.y.z> [-Draft] [-SkipBuild] [-NoCommit] [-NoPush]
```

流程全自动：preflight 查重 → Windows AOT 包 → Linux AOT 包（WSL）→ 双平台冒烟 → 压缩 → git 提交 + tag + push → GitHub Release 附双资产。C VM Release 构建默认加固（LTO + 符号剥离 + 启动反调试）且 **JIT 默认开启**。

### 本地发布包（package\ 目录）

`dotnet publish SlangAllInOne\SlangAllInOne.csproj -c Debug` / `-c Release` **零旗标**直接生成到 `SlangAllInOne\package\` 下对应平台包目录（平台 = 宿主 OS：Windows 出 win32-*，WSL/Linux 出 linux-*）：

| 目录 | 形态 |
|------|------|
| `win32-debug` / `linux-debug` | Front（.NET Debug + pdb）+ C VM Debug（+pdb）——**双端可源码级调试**（目标机需 .NET 8 运行时）；`lib\` 默认附带 `*.module.json` 调试副本（slb 主产物 + json 对照） |
| `win32-release` / `linux-release` | **Native AOT 一体化原生二进制**（零 .NET 依赖）+ 加固 C VM（**JIT 默认开启**）；`lib\` 仅 `*.module.slb` |

双平台四包一键同建（linux 包自动经 WSL 构建并复用 Windows 包的 `lib\`+`md\`，含布局校验与冒烟）：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File SlangAllInOne\scripts\build-packages.ps1 [-Packages win32-debug,linux-release] [-NoSmoke]
```

详见 [RELEASE.md](RELEASE.md)「本地发布包目录方案」。

## 调试

- **VS F5 混合调试（主推）**：打开 `SlangAllInOne.csproj`，选 launchSettings 的 `run MiniSmoke (C# + C VM mixed)` profile——C# 断点打在 `simple_language\source\**`，C 断点可直接打在 C VM 源码（P/Invoke 进程内加载，符号天然对上）。
- **运行输出不对**：先看 `out/export/<模块>/Logs/Result.txt`（print 镜像）→ `VM.txt` → `Front.txt`（最早一条 Error）→ `DebugCode/` 各阶段快照反查。

## 许可证

[Apache-2.0](LICENSE)。C VM 静态链接的第三方组件（yyjson / LZ4 / zlib / mimalloc / TLSF / Mbed TLS / SQLite）协议全文与 NOTICE 见仓库 [`csimple_lang/third_party/LICENSES/`](../csimple_lang/third_party/LICENSES/)（2026-10-18 起不再随发布包分发 `licenses\`，需要时从仓库获取）；`sl_mysql_lib`（GPL-2.0 静链）不随官方发布包分发。
