# SLang — SlangAllInOne 一体化工具链

**中文** | [English](README_EN.md)

## 初识 SLang

**SLang** 是一门从零构建的静态类型语言：编译器前端（C#/.NET 8）把 `.sl` 源码编译为 SLIR 模块包，C99 虚拟机负责执行。本仓库是统合两者的宿主与分发总包——`slang` 在单个进程内完成「Front 进程内编译 → SLIR 内存直传 → C VM 执行」，裸工程路径即**编译即运行**：

```
.sl 源码 ──► Front 编译器（C#，simple_language）──► SLIR 模块包（json / slb）──► C99 虚拟机执行
                                  ▲
               本仓库统合宿主 slang 串起全链路：编译 → 内存直传 → 运行
```

语言核心能力：类 / 继承 / 接口 / 泛型模板 / attribute 注解；协程（`spawn` / `await` / `yield`）与 isolate 隔离岛；闭包、内联 lambda、字符串插值、`data` 动态对象、异常；`Float8` / `Float16` 低精度浮点；编译期条件编译 `static if`。

## 说明

本仓库承载：统合宿主 `slang`（编译 / 运行 / 发布 / 脚手架 / LSP）+ 独立包管理器 `spm` + C VM 运行时（以二进制随包分发）+ 标准库源码 + 测试用例集 + 全部用户文档。

| 仓库 | 定位 |
|------|------|
| **SlangAllInOne**（本仓库） | 一体化总包：宿主 slang + 标准库 + 测试 + 文档 + 构建脚本（C#/.NET 8） |
| [kamaba/simple_language](https://github.com/kamaba/simple_language) | Front 编译器：词法/语法/语义/IR/SLIR 导出（C#/.NET 8） |
| csimple_lang | C99 虚拟机（以运行时二进制随发布包 `bin\` 分发） |

标准库（`SLangCore\Lib\`）：**Core**（容器 / 序列化 / 编解码）、**Math**（三精度数学 / 向量矩阵 / 大数）、**Std**（IO / 网络 / Sqlite / Redis / isolate）、**HttpServer / WebUI**（服务框架 / 界面）、Tensora（张量，建设中）等。

## 安装

**方式一：Release 包（目标机零依赖）** —— 从 [Releases](https://github.com/kamaba/SlangAllInOne/releases) 下载解压，双平台同发（Windows x64 zip / Linux x64 tar.gz）。`slang` 为 Native AOT 自包含二进制，无需 .NET 运行时：

```
slang_release_<v>/
├── slang[.exe]     # 统合宿主（AOT 单文件）
├── bin\            # C VM 运行时 + sqlite
├── lib\            # 系统标准库 Core/Math/Std *.module.slb
├── modules\ / plugins\   # spm 用户包 / 插件目录
├── test\RefProbe\  # 开箱示例工程
└── md\             # 全部用户文档
```

```powershell
slang.exe test\RefProbe\RefProbe      # 开箱即跑（Linux 同构：./slang test/RefProbe/RefProbe）
```

工程 `references` 直接写官方库名（`Core` / `Std` / `Math`），编译期与运行期都在 `lib\` 下按名直查，零相对路径配置。

**方式二：从源码构建** —— 前置 .NET SDK 8 / CMake ≥ 3.18 / clang / MSVC（Linux 侧走 WSL）。本仓库与 simple_language 需**同一父目录平级摆放**（跨仓库工程引用）：

```powershell
powershell -File SlangAllInOne\scripts\build-vm-win.ps1 -Config Debug        # 1. 构建 C VM 运行时
dotnet run --project SlangAllInOne\SlangAllInOne.csproj -- <工程路径>          # 2. 编译即运行
powershell -File SlangAllInOne\scripts\build-all.ps1 -Run                    # 3. 一键全流程（VM→标准库→测试）
```

VS 开发入口 = [SlangAllInOne.sln](SlangAllInOne.sln)，工程清单见 [PROJECTS.md](PROJECTS.md)。

## 代码简例

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
        Console.println( greeter.hello() );

        List<int> nums = new();
        nums.add( 1 );
        for n in nums
        {
            Console.println( "n = $n" );     # 字符串插值
        }

        Task task = spawn add2( 20, 22 );    # 协程
        int sum = await task as int;
        Console.println( "20 + 22 = $sum" );
    }
}
```

工程文件三件套：`.sp`（入口，`Project{}` + `_main_`）+ 同名 `.jsonc`（配置）+ `.sl`（源码）。脚手架一键生成：`slang new project MyApp`。

## 扩展功能

| 能力 | 入口 / 说明 |
|------|------|
| FFI 外部调用 | `@DllImport` 声明 + native 库直调，`slang ffi-check` 校验契约 → [md/project/ffi.md](md/project/ffi.md) |
| 系统方法下沉 | 热点函数绑定 C VM 原生实现（如矩阵运算直调 `math_lib.dll`）→ [md/project/project-system-method-call-guide.md](md/project/project-system-method-call-guide.md) |
| 插件系统 | `@csharp_mono(){}` 内联 C#（Mono 互操作）等 → [md/plugins/CSharp_Mono.md](md/plugins/CSharp_Mono.md)、[PLUGIN_TEMPLATE.md](md/plugins/PLUGIN_TEMPLATE.md) |
| 编译期条件编译 | `global.macro` 宏 + `static if`，jsonc / CLI / 环境变量 / `_before_()` 四路注入 → [md/project/static-if.md](md/project/static-if.md) |
| spm 包/插件管理 | 独立 `spm.exe`：install / search / plugin / registry → [md/project/spm-registry.md](md/project/spm-registry.md) |
| LSP 语言服务 | 内嵌 LSP 3.17（诊断 / 补全 / 跳转 / 格式化 / 重命名），VSCode 插件消费 → [md/project/lsp-code-index.md](md/project/lsp-code-index.md) |
| AOT 导出 | IR → LLVM IR `.ll` → [md/project/exporter.md](md/project/exporter.md) |
| 发布 | `slang publish`（可运行 exe / module.slb）→ [md/project/publish-guide.md](md/project/publish-guide.md) |

## 文档导航

全仓 md 文档最完整的总索引是 **[md/INDEX.md](md/INDEX.md)**（逐篇列出全部文档），本导航按类别汇总，便于快速定位。

### 入门与总览

| 文档 | 内容 |
|------|------|
| [README.md](README.md) / [README_EN.md](README_EN.md) | 语言与生态总览（中 / 英） |
| [PROJECTS.md](PROJECTS.md) | 工程构成 / 版本联动 / 仓库布局 |
| [RELEASE.md](RELEASE.md) | 发版与分发包流程 |
| [code.md](md/code.md) | 编码规范 |
| [CLI.md](md/CLI.md) | CLI 全集（slang / spm / csimple_lang） |
| [SL语法与编码规范总表.md](md/SL语法与编码规范总表.md) | 语法逐篇详解单点引用总表 |

### 工程与生态（md/project，17 篇）

| 文档 | 内容 |
|------|------|
| [project.md](md/project/project.md) | 工程总览 |
| [project-config-jsonc-guide.md](md/project/project-config-jsonc-guide.md) | jsonc 配置全解（project / source / compile / references / macro 等） |
| [project_sp-guide.md](md/project/project_sp-guide.md) | `.sp` 工程文件指南 |
| [project-module.md](md/project/project-module.md) | 工程 / 模块结构 |
| [project_arguments.md](md/project/project_arguments.md) | 程序参数（`--` 透传与 `_inputArgs`） |
| [project-system-method-call-guide.md](md/project/project-system-method-call-guide.md) | System 方法调用指南 |
| [static-if.md](md/project/static-if.md) | `global.macro` 宏 + `static if` 条件编译 + `_before_` 钩子 |
| [environment-guide.md](md/project/environment-guide.md) | Environment 运行环境 / 平台分支 |
| [exporter.md](md/project/exporter.md) | 导出器（module.json / SLB） |
| [publish-guide.md](md/project/publish-guide.md) | `slang publish` 发布指南 |
| [package-layout.md](md/project/package-layout.md) | 发行包目录布局 |
| [spm-registry.md](md/project/spm-registry.md) | spm 包/插件管理器与 registry |
| [ffi.md](md/project/ffi.md) | FFI 契约（`.slffi.json` / `ffi-check`） |
| [lsp-code-index.md](md/project/lsp-code-index.md) | LSP 代码索引 |
| [docs-web.md](md/project/docs-web.md) | 文档站（官网文档部署） |
| [optimization.md](md/project/optimization.md) | 优化指南 |
| [test-guide.md](md/project/test-guide.md) | 测试指南（用例集 ↔ 宿主对照） |

### 语言语法（md/syntax，37 篇）

入门与词法：[introduction](md/syntax/introduction.md) · [keywords](md/syntax/keywords.md) · [marco](md/syntax/marco.md) · [attribute](md/syntax/attribute.md) · [namespace](md/syntax/namespace.md)

变量与作用域：[variable](md/syntax/variable.md) · [local](md/syntax/local.md) · [global](md/syntax/global.md) · [typealias](md/syntax/typealias.md) · [float8_16](md/syntax/float8_16.md)

类型：[type](md/syntax/type.md) · [number](md/syntax/number.md) · [string](md/syntax/string.md) · [object](md/syntax/object.md) · [array](md/syntax/array.md) · [range](md/syntax/range.md) · [data](md/syntax/data.md) · [class](md/syntax/class.md) · [interface](md/syntax/interface.md) · [enum](md/syntax/enum.md) · [cast](md/syntax/cast.md)

表达式与运算：[express](md/syntax/express.md) · [operator](md/syntax/operator.md) · [bind](md/syntax/bind.md)

流程控制：[if](md/syntax/if.md) · [switch](md/syntax/switch.md) · [try](md/syntax/try.md) · [forwhiledowhile](md/syntax/forwhiledowhile.md) · [labelgoto](md/syntax/labelgoto.md)

函数与高级特性：[function](md/syntax/function.md) · [template](md/syntax/template.md) · [inline_lambda](md/syntax/inline_lambda.md) · [coroutine](md/syntax/coroutine.md) · [isolate](md/syntax/isolate.md) · [extend](md/syntax/extend.md) · [result](md/syntax/result.md) · [system_method](md/syntax/system_method.md)

### 标准库 API（md/lib）

每个模块先读 `README.md`（职责边界与依赖顺序）；逐 API 文档见 **[md/INDEX.md](md/INDEX.md) §3.3**。

- **[lib/Core](md/lib/Core/README.md)** —— 内建与核心运行库（数值 / String / Array / 容器 / IO / 文本 / Data / Coroutine 等，79 篇）
- **[lib/Math](md/lib/Math/README.md)** —— 数学库（标量 / 大数 / 向量矩阵 / Rect，27 篇）
- **[lib/Std](md/lib/Std/README.md)** —— 系统与生态库（IO / 文本 / 网络 / DB / 缓存 / GPU / Isolate / OS，53 篇）
- **[lib/HttpServer](md/lib/HttpServer/README.md)** —— 内置 HTTP 服务端框架（18 篇）
- **[lib/WebUI](md/lib/WebUI/README.md)** —— SLangWebUI 界面包（独立 module）

### 日志系统（md/log）

| 文档 | 内容 |
|------|------|
| [log-system-guide.md](md/log/log-system-guide.md) | 日志系统指南 |
| [log-debug-usage.md](md/log/log-debug-usage.md) | 日志调试用法 |

### AI 协作（内部，md/ai）

| 文档 | 内容 |
|------|------|
| [AI_GUIDE.md](md/ai/AI_GUIDE.md) | AI 协作总入口 |
| [INDEX.md](md/ai/INDEX.md) | AI 文档索引 |
| [PROJECT_MAP.md](md/ai/PROJECT_MAP.md) | 代码地图 |
| [EXPORT_PATHS.md](md/ai/EXPORT_PATHS.md) | 导出路径说明 |
| [DEBUG_WORKFLOW.md](md/ai/DEBUG_WORKFLOW.md) | 调试工作流 |
| [故障排查流程.md](md/ai/故障排查流程.md) | 故障排查 SOP |
| [CONTRIBUTING_GUIDE.md](md/ai/CONTRIBUTING_GUIDE.md) | 贡献指南 |
| [troubleshooting/](md/ai/troubleshooting/)（8 篇） | 分场景排查手册（编译 / 崩溃 / 运行时 / 并发 / 插件 FFI / 构建 / 标准库 / 方法论） |

### Unity3D 生态（md/unity3d + unity/）

| 文档 | 内容 |
|------|------|
| [unity/README.md](../unity/README.md) | U3D 落地实例（HelloCube） |
| [00-INDEX.md](md/unity3d/00-INDEX.md) | 系列总索引 |
| [01-架构总览.md](md/unity3d/01-架构总览.md) ~ [14-实例落地记录.md](md/unity3d/14-实例落地记录.md) | 架构 / 本地编译 / C# 桥接 / 模块装载热更 / Unity API 映射 / 生命周期 / 调试 / JIT·IL2CPP / 构建管线 / 跨平台部署 / 安全沙箱 / 示例 / 已知问题 |

### 外部工程文档（csimple_lang / simple_language）

| 文档 | 内容 |
|------|------|
| [SLB_DESIGN.md](../csimple_lang/md/design/SLB_DESIGN.md) | SLB 模块包格式设计 |
| [ATTRIBUTE_DESIGN.md](../csimple_lang/md/design/ATTRIBUTE_DESIGN.md) | attribute 系统设计 |
| [PROCESS_DESIGN.md](../csimple_lang/md/design/PROCESS_DESIGN.md) | 编译流程设计 |
| [NET_DESIGN.md](../csimple_lang/md/design/NET_DESIGN.md) | C VM 网络栈设计 |
| [DEBUG_PROTOCOL_DESIGN.md](../csimple_lang/md/design/DEBUG_PROTOCOL_DESIGN.md) | SLDP 调试协议设计 |
| [X86_ASM_FASTPATH_DESIGN.md](../csimple_lang/md/design/X86_ASM_FASTPATH_DESIGN.md) | x86 ASM 快路径设计 |
| [MONO_DESIGN.md](../csimple_lang/md/design/MONO_DESIGN.md) | Mono 互操作设计 |
| [MLIR_AOT_实现与待办.md](../simple_language/source/Export/MLIR/MLIR_AOT_实现与待办.md) | MLIR AOT 后端 |

## 许可证

[Apache-2.0](LICENSE)。C VM 静态链接的第三方组件协议全文见仓库 [`csimple_lang/third_party/LICENSES/`](../csimple_lang/third_party/LICENSES/)；`sl_mysql_lib`（GPL-2.0 静链）不随官方发布包分发。
