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

全仓 md 总索引：**[md/INDEX.md](md/INDEX.md)**。常用入口：

| 文档 | 内容 |
|------|------|
| [md/syntax/introduction.md](md/syntax/introduction.md) | 语法入门（37 篇逐篇详解的总入口） |
| [md/SL语法与编码规范总表.md](md/SL语法与编码规范总表.md) | 语法与编码规范单点引用总表 |
| [md/CLI.md](md/CLI.md) | CLI 全集（slang / spm / csimple_lang） |
| [md/code.md](md/code.md) | 编码规范 |
| [md/project/project-config-jsonc-guide.md](md/project/project-config-jsonc-guide.md) | `.jsonc` 工程配置权威说明 |
| [md/project/project_sp-guide.md](md/project/project_sp-guide.md) | `.sp` 工程文件指南 |
| [md/project/test-guide.md](md/project/test-guide.md) | 测试指南（用例集 ↔ 宿主对照） |
| [md/log/log-system-guide.md](md/log/log-system-guide.md) | 日志系统 |
| [md/lib/Core/README.md](md/lib/Core/README.md)（及 Math / Std / HttpServer / WebUI） | 标准库 API 文档入口 |
| [PROJECTS.md](PROJECTS.md) / [RELEASE.md](RELEASE.md) | 工程清单 / 发布策略 |

## 许可证

[Apache-2.0](LICENSE)。C VM 静态链接的第三方组件协议全文见仓库 [`csimple_lang/third_party/LICENSES/`](../csimple_lang/third_party/LICENSES/)；`sl_mysql_lib`（GPL-2.0 静链）不随官方发布包分发。
