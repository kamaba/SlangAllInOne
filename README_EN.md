# SLang — The All-in-One Toolchain (SlangAllInOne)

English | **[中文](README.md)**

## Meet SLang

**SLang** is a statically typed language built from scratch: the compiler front end (C#/.NET 8) compiles `.sl` sources into SLIR module packages, and a C99 virtual machine executes them. This repository is the unified host and distribution package gluing both together — inside a single process, `slang` performs "Front in-process compile → SLIR in-memory handoff → C VM execution"; a bare project path **compiles and runs in one command**:

```
.sl source ──► Front compiler (C#, simple_language) ──► SLIR module package (json / slb) ──► C99 VM execution
                                  ▲
                unified host `slang` (this repo) chains it all: compile → in-memory handoff → run
```

Core language capabilities: classes / inheritance / interfaces / generic templates / attribute annotations; coroutines (`spawn` / `await` / `yield`) and isolates; closures, inline lambdas, string interpolation, `data` dynamic objects, exceptions; `Float8` / `Float16` low-precision floats; compile-time conditional compilation with `static if`.

## About This Repo

This repository carries: the unified host `slang` (compile / run / publish / scaffolding / LSP) + the standalone package manager `spm` + the C VM runtime (shipped as binaries in `bin\`) + standard library sources + test suites + all user docs.

| Repository | Role |
|------|------|
| **SlangAllInOne** (this repo) | All-in-one package: host slang + stdlib + tests + docs + build scripts (C#/.NET 8) |
| [kamaba/simple_language](https://github.com/kamaba/simple_language) | Front-end compiler: lexer/parser/semantics/IR/SLIR export (C#/.NET 8) |
| csimple_lang | C99 virtual machine (shipped as runtime binaries in `bin\` of release packages) |

Standard library (`SLangCore\Lib\`): **Core** (containers / serialization / codecs), **Math** (three-precision math / vectors & matrices / big numbers), **Std** (IO / networking / Sqlite / Redis / isolates), **HttpServer / WebUI** (service framework / UI), Tensora (tensors, work in progress), and more.

## Installation

**Option 1: Release package (zero dependencies on the target machine)** — download and unpack from [Releases](https://github.com/kamaba/SlangAllInOne/releases); both platforms ship per version (Windows x64 zip / Linux x64 tar.gz). `slang` is a self-contained Native AOT binary — no .NET runtime required:

```
slang_release_<v>/
├── slang[.exe]     # Unified host (single AOT file)
├── bin\            # C VM runtime + sqlite
├── lib\            # System stdlib Core/Math/Std *.module.slb
├── modules\ / plugins\   # spm user packages / plugins
├── test\RefProbe\  # Out-of-the-box sample project
└── md\             # All user docs
```

```powershell
slang.exe test\RefProbe\RefProbe      # Run it right away (Linux is symmetric: ./slang test/RefProbe/RefProbe)
```

Project `references` use bare official library names (`Core` / `Std` / `Math`) — both the compiler and the runtime look them up by name in `lib\`, no fragile relative paths.

**Option 2: Build from source** — prerequisites: .NET SDK 8 / CMake ≥ 3.18 / clang / MSVC (Linux builds go through WSL). This repo and simple_language must sit as **siblings under the same parent directory** (cross-repo project references):

```powershell
powershell -File SlangAllInOne\scripts\build-vm-win.ps1 -Config Debug        # 1. Build the C VM runtime
dotnet run --project SlangAllInOne\SlangAllInOne.csproj -- <project path>     # 2. Compile-and-run
powershell -File SlangAllInOne\scripts\build-all.ps1 -Run                    # 3. Full pipeline (VM → stdlib → tests)
```

Visual Studio development entry = [SlangAllInOne.sln](SlangAllInOne.sln); project inventory in [PROJECTS.md](PROJECTS.md).

## A Quick Example

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
            Console.println( "n = $n" );     # string interpolation
        }

        Task task = spawn add2( 20, 22 );    # coroutine
        int sum = await task as int;
        Console.println( "20 + 22 = $sum" );
    }
}
```

Project file trio: `.sp` (entry, `Project{}` + `_main_`) + same-name `.jsonc` (config) + `.sl` (sources). Scaffold in one command: `slang new project MyApp`.

## Extensions

| Capability | Entry / Notes |
|------|------|
| FFI external calls | `@DllImport` declarations + direct native library calls; `slang ffi-check` validates contracts → [md/project/ffi.md](md/project/ffi.md) |
| System-method pushdown | Hot functions bound to native C VM implementations (e.g. matrix ops calling straight into `math_lib.dll`) → [md/project/project-system-method-call-guide.md](md/project/project-system-method-call-guide.md) |
| Plugin system | `@csharp_mono(){}` inline C# (Mono interop) and more → [md/plugins/CSharp_Mono.md](md/plugins/CSharp_Mono.md), [PLUGIN_TEMPLATE.md](md/plugins/PLUGIN_TEMPLATE.md) |
| Compile-time conditionals | `global.macro` macros + `static if`; injected via jsonc / CLI / env vars / `_before_()` → [md/project/static-if.md](md/project/static-if.md) |
| spm package/plugin manager | Standalone `spm.exe`: install / search / plugin / registry → [md/project/spm-registry.md](md/project/spm-registry.md) |
| LSP language server | Embedded LSP 3.17 (diagnostics / completion / go-to-def / formatting / rename), consumed by the VSCode extension → [md/project/lsp-code-index.md](md/project/lsp-code-index.md) |
| AOT export | IR → LLVM IR `.ll` → [md/project/exporter.md](md/project/exporter.md) |
| Publishing | `slang publish` (runnable exe / module.slb) → [md/project/publish-guide.md](md/project/publish-guide.md) |

## Documentation Map

The most complete master index for all docs is **[md/INDEX.md](md/INDEX.md)** (lists every doc per-topic); this map groups them by category for quick navigation.

### Getting Started & Overview

| Doc | Contents |
|------|------|
| [README.md](README.md) / [README_EN.md](README_EN.md) | Language & ecosystem overview (zh / en) |
| [PROJECTS.md](PROJECTS.md) | Project composition / version coordination / repo layout |
| [RELEASE.md](RELEASE.md) | Release & distribution package flow |
| [code.md](md/code.md) | Coding conventions |
| [CLI.md](md/CLI.md) | CLI reference (slang / spm / csimple_lang) |
| [SL语法与编码规范总表.md](md/SL语法与编码规范总表.md) | Single-reference syntax & coding conventions table |

### Project & Ecosystem (md/project, 17 docs)

| Doc | Contents |
|------|------|
| [project.md](md/project/project.md) | Project overview |
| [project-config-jsonc-guide.md](md/project/project-config-jsonc-guide.md) | Full `jsonc` config (project / source / compile / references / macro …) |
| [project_sp-guide.md](md/project/project_sp-guide.md) | `.sp` project file guide |
| [project-module.md](md/project/project-module.md) | Project / module structure |
| [project_arguments.md](md/project/project_arguments.md) | Program arguments (`--` passthrough & `_inputArgs`) |
| [project-system-method-call-guide.md](md/project/project-system-method-call-guide.md) | System-method call guide |
| [static-if.md](md/project/static-if.md) | `global.macro` + `static if` conditional compilation + `_before_` hook |
| [environment-guide.md](md/project/environment-guide.md) | Environment runtime / platform branching |
| [exporter.md](md/project/exporter.md) | Exporter (module.json / SLB) |
| [publish-guide.md](md/project/publish-guide.md) | `slang publish` guide |
| [package-layout.md](md/project/package-layout.md) | Distribution package layout |
| [spm-registry.md](md/project/spm-registry.md) | spm package/plugin manager & registry |
| [ffi.md](md/project/ffi.md) | FFI contract (`.slffi.json` / `ffi-check`) |
| [lsp-code-index.md](md/project/lsp-code-index.md) | LSP code index |
| [docs-web.md](md/project/docs-web.md) | Docs site (official site deployment) |
| [optimization.md](md/project/optimization.md) | Optimization guide |
| [test-guide.md](md/project/test-guide.md) | Test guide (suite ↔ host mapping) |

### Language Syntax (md/syntax, 37 docs)

Getting-started & lexer: [introduction](md/syntax/introduction.md) · [keywords](md/syntax/keywords.md) · [marco](md/syntax/marco.md) · [attribute](md/syntax/attribute.md) · [namespace](md/syntax/namespace.md)

Variables & scope: [variable](md/syntax/variable.md) · [local](md/syntax/local.md) · [global](md/syntax/global.md) · [typealias](md/syntax/typealias.md) · [float8_16](md/syntax/float8_16.md)

Types: [type](md/syntax/type.md) · [number](md/syntax/number.md) · [string](md/syntax/string.md) · [object](md/syntax/object.md) · [array](md/syntax/array.md) · [range](md/syntax/range.md) · [data](md/syntax/data.md) · [class](md/syntax/class.md) · [interface](md/syntax/interface.md) · [enum](md/syntax/enum.md) · [cast](md/syntax/cast.md)

Expressions & operators: [express](md/syntax/express.md) · [operator](md/syntax/operator.md) · [bind](md/syntax/bind.md)

Control flow: [if](md/syntax/if.md) · [switch](md/syntax/switch.md) · [try](md/syntax/try.md) · [forwhiledowhile](md/syntax/forwhiledowhile.md) · [labelgoto](md/syntax/labelgoto.md)

Functions & advanced features: [function](md/syntax/function.md) · [template](md/syntax/template.md) · [inline_lambda](md/syntax/inline_lambda.md) · [coroutine](md/syntax/coroutine.md) · [isolate](md/syntax/isolate.md) · [extend](md/syntax/extend.md) · [result](md/syntax/result.md) · [system_method](md/syntax/system_method.md)

### Standard Library API (md/lib)

Read each module's `README.md` first (responsibilities & dependency order); per-API docs in **[md/INDEX.md](md/INDEX.md) §3.3**.

- **[lib/Core](md/lib/Core/README.md)** — built-in & core runtime (numeric / String / Array / containers / IO / text / Data / Coroutine …, 79 docs)
- **[lib/Math](md/lib/Math/README.md)** — math library (scalar / big-number / vectors & matrices / Rect, 27 docs)
- **[lib/Std](md/lib/Std/README.md)** — system & ecosystem (IO / text / networking / DB / cache / GPU / Isolate / OS, 53 docs)
- **[lib/HttpServer](md/lib/HttpServer/README.md)** — built-in HTTP server framework (18 docs)
- **[lib/WebUI](md/lib/WebUI/README.md)** — SLangWebUI UI package (separate module)

### Logging (md/log)

| Doc | Contents |
|------|------|
| [log-system-guide.md](md/log/log-system-guide.md) | Logging system guide |
| [log-debug-usage.md](md/log/log-debug-usage.md) | Logging debug usage |

### AI Collaboration (internal, md/ai)

| Doc | Contents |
|------|------|
| [AI_GUIDE.md](md/ai/AI_GUIDE.md) | AI collaboration entry |
| [INDEX.md](md/ai/INDEX.md) | AI doc index |
| [PROJECT_MAP.md](md/ai/PROJECT_MAP.md) | Code map |
| [EXPORT_PATHS.md](md/ai/EXPORT_PATHS.md) | Export paths |
| [DEBUG_WORKFLOW.md](md/ai/DEBUG_WORKFLOW.md) | Debug workflow |
| [故障排查流程.md](md/ai/故障排查流程.md) | Troubleshooting SOP |
| [CONTRIBUTING_GUIDE.md](md/ai/CONTRIBUTING_GUIDE.md) | Contributing guide |
| [troubleshooting/](md/ai/troubleshooting/) (8 docs) | Scenario-based troubleshooting (compile / crash / runtime / concurrency / plugin-FFI / build / stdlib / methodology) |

### Unity3D Ecosystem (md/unity3d + unity/)

| Doc | Contents |
|------|------|
| [unity/README.md](../unity/README.md) | U3D landing example (HelloCube) |
| [00-INDEX.md](md/unity3d/00-INDEX.md) | Series master index |
| [01-架构总览.md](md/unity3d/01-架构总览.md) ~ [14-实例落地记录.md](md/unity3d/14-实例落地记录.md) | architecture / local build / C# bridge / module hot-reload / Unity API mapping / lifecycle / debugging / JIT·IL2CPP / build pipeline / cross-platform deploy / security sandbox / examples / known issues |

### External Project Docs (csimple_lang / simple_language)

| Doc | Contents |
|------|------|
| [SLB_DESIGN.md](../csimple_lang/md/design/SLB_DESIGN.md) | SLB module package format design |
| [ATTRIBUTE_DESIGN.md](../csimple_lang/md/design/ATTRIBUTE_DESIGN.md) | attribute system design |
| [PROCESS_DESIGN.md](../csimple_lang/md/design/PROCESS_DESIGN.md) | Compilation flow design |
| [NET_DESIGN.md](../csimple_lang/md/design/NET_DESIGN.md) | C VM network stack design |
| [DEBUG_PROTOCOL_DESIGN.md](../csimple_lang/md/design/DEBUG_PROTOCOL_DESIGN.md) | SLDP debug protocol design |
| [X86_ASM_FASTPATH_DESIGN.md](../csimple_lang/md/design/X86_ASM_FASTPATH_DESIGN.md) | x86 ASM fast-path design |
| [MONO_DESIGN.md](../csimple_lang/md/design/MONO_DESIGN.md) | Mono interop design |
| [MLIR_AOT_实现与待办.md](../simple_language/source/Export/MLIR/MLIR_AOT_实现与待办.md) | MLIR AOT backend |

## License

[Apache-2.0](LICENSE). Full license texts for third-party components statically linked into the C VM live in the repo at [`csimple_lang/third_party/LICENSES/`](../csimple_lang/third_party/LICENSES/); `sl_mysql_lib` (GPL-2.0 static link) is not distributed in official release packages.
