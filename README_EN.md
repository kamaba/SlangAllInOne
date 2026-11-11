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

Master index for all docs: **[md/INDEX.md](md/INDEX.md)**. Common entries:

| Doc | Contents |
|------|------|
| [md/syntax/introduction.md](md/syntax/introduction.md) | Syntax primer (gateway to the 37 per-topic syntax docs) |
| [md/SL语法与编码规范总表.md](md/SL语法与编码规范总表.md) | Single-reference syntax & coding conventions table |
| [md/CLI.md](md/CLI.md) | CLI reference (slang / spm / csimple_lang) |
| [md/code.md](md/code.md) | Coding conventions |
| [md/project/project-config-jsonc-guide.md](md/project/project-config-jsonc-guide.md) | Authoritative `.jsonc` project config guide |
| [md/project/project_sp-guide.md](md/project/project_sp-guide.md) | `.sp` project file guide |
| [md/project/test-guide.md](md/project/test-guide.md) | Test guide (suite ↔ host mapping) |
| [md/log/log-system-guide.md](md/log/log-system-guide.md) | Logging system |
| [md/lib/Core/README.md](md/lib/Core/README.md) (plus Math / Std / HttpServer / WebUI) | Standard library API doc entries |
| [PROJECTS.md](PROJECTS.md) / [RELEASE.md](RELEASE.md) | Project inventory / release policy |

## License

[Apache-2.0](LICENSE). Full license texts for third-party components statically linked into the C VM live in the repo at [`csimple_lang/third_party/LICENSES/`](../csimple_lang/third_party/LICENSES/); `sl_mysql_lib` (GPL-2.0 static link) is not distributed in official release packages.
