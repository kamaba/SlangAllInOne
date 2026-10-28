# SlangAllInOne — The All-in-One Toolchain for the SLang Language

English | **[中文](README.md)**

**SLang** is a statically typed language built from scratch: the compiler front end (C#/.NET 8) compiles `.sl` sources into SLIR module packages, and a C99 virtual machine executes them. This repository is the unified host and distribution package gluing both together.

```
.sl source ──► Front compiler (C#, simple_language) ──► SLIR module package (json / slb) ──► C99 VM execution
                                  ▲
                unified host `slang` (this repo) chains it all: compile → in-memory handoff → run
```

The unified host **`slang`** in this repository performs "Front in-process compile → SLIR in-memory handoff → C VM P/Invoke execution" inside a single .NET 8 process: the bare project path `slang <project>` compiles and runs in one command, with no intermediate files written to disk.

## Related Open-Source Repositories

| Repository | Role | Tech |
|------|------|------|
| **SlangAllInOne** (this repo) | All-in-one package: unified host `slang` + standard library sources + test suites + user docs + build/release scripts | C#/.NET 8 |
| [kamaba/simple_language](https://github.com/kamaba/simple_language) — **FrontEnd compiler** | Lexer/parser, semantics and type system, IR generation, SLIR export, CLI; opcode enum kept in strict lockstep with the C VM | C#/.NET 8 |

The Front compiles SLIR, the C VM executes SLIR, and this repo glues both into a single command while carrying the standard library, tests, and documentation (the C VM ships as runtime binaries in `bin\` of the release packages). **When building from source, this repo and simple_language must sit as siblings under the same parent directory** (project references use cross-repo relative paths) — see [Build from Source](#build-from-source).

## Language Features

- **Static type system**: classes / inheritance / interfaces / enums / generic templates (`template`) / type aliases / an attribute annotation system (four phases: PreCompile / Compiling / Preload / Runtime)
- **Modern concurrency**: coroutines (`spawn` / `await` / `yield` keywords + `Task` / `Channel`) and isolates (cross-heap parallelism + port-based messaging with zero-copy transfer)
- **Expressiveness**: closures, inline lambdas (`=>` expanded at the call site), `Range`, string interpolation `$x`, `data` dynamic objects, exceptions (`try / catch / throws`)
- **Low-precision floats**: `Float8` / `Float8_E5M2` / `Float16` / `Float16_Brain` with native literals and arithmetic semantics
- **Cross-language interop**: FFI external calls (`@DllImport`), system-method pushdown (hot functions bound to native C VM implementations, e.g. matrix ops calling straight into `math_lib.dll`), plugin system (`@csharp_mono(){}` inline C#, Java Hotspot, …)
- **Multiple targets**: SLIR JSON / SLB binary module packages (~2% of the JSON size), AOT export (LLVM IR `.ll`), WebAssembly (in-browser playground)

## Standard Library at a Glance

| Module | Contents |
|------|------|
| **Core** | Containers (List / Map / Set / Queue / Stack / LinkedList / Tuple / Channel), JSON / XML / YAML / TOML / CSV, ByteBuffer / Codec / LengthPrefix, Lz4 compression, protobuf, Stream element streams |
| **Math** | Three-precision math (Mathd / Mathf / Mathh, FFI direct calls into a native lib), vectors & matrices (9 vector + 6 matrix value types across three precisions), dynamic matrices, BigNumber / BigDecimal / Factor |
| **Std** | IO (File / Directory / Console), Net (TCP / UDP / TLS / HTTP/1.1 / WebSocket / MQTT with coroutine-suspending IO), Sqlite, Redis, Log / Profiling / Trace / Monitor, isolates, Base64 / Sha1, GZip / Zip, DateTime / Process / Timer |
| **SLang.HttpServer / SLang.WebSocketServer** | HTTP / WebSocket service framework (HttpServer: routing / request / response chaining / BodyParser / Jwt; WebSocketServer: upgrade-router / standalone-port dual forms) |
| **SLang.Render** | Rendering types (Mesh / Material / Texture / Shader / Camera…) |
| **Tensora** | Tensors / tensor ops / autograd / optimizers / Transformer (work in progress) |
| **SLang.Mysql** | MySQL client (`SLangMysql` module; ⚠ statically links GPL-2.0 MySQL Connector/C, **not shipped** in official release packages) |

## Getting Started

### 1. Get a Release (zero dependencies on the target machine)

Download and unpack the latest version from [Releases](https://github.com/kamaba/SlangAllInOne/releases) (each version ships both platforms):

- `slang_release_<v>_win-x64.zip` (Windows x64)
- `slang_release_<v>_linux-x64.tar.gz` (Linux x64, glibc ≥ 2.43)

The `slang` binary is a **self-contained Native AOT executable** — no .NET runtime required. Package layout:

```
slang_release_<v>/
├── slang[.exe]         # Unified host: Front compile + C VM run (single AOT file)
├── bin\                # C VM runtime (hardened Release: LTO + anti-debug) + sqlite
├── lib\                # System built-in stdlib Core/Math/Std *.module.slb (flat directory)
├── modules\            # (future) user package dir for spm.exe, the package manager - created on demand
├── plugins\            # Plugin directory: install & management home for plugins (distinct from plain packages)
├── test\RefProbe\      # Out-of-the-box example: minimal project with bare-name references
└── md\                 # ~93 user docs (syntax / libraries / project / logging / plugins)
```

> The directory scheme's decision record lives in [md/project/package-layout.md](md/project/package-layout.md) (`lib` = system built-in libraries, `modules` = future spm.exe package management, `plugins` = plugins).

### 2. Run It Right Away

```powershell
# Windows (Linux is symmetric: ./slang test/RefProbe/RefProbe)
slang.exe test\RefProbe\RefProbe
```

User projects can reference official libraries by bare name (`Core` / `Std` / `Math`) — both the Front at compile time and the C VM at run time look them up in `<slang dir>\lib\` (slb first; packages installed by the future spm are found the same way under `modules\`). No fragile relative paths.

### 3. What SLang Looks Like

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

        # Containers
        List<int> nums = new();
        nums.add( 1 );
        nums.add( 2 );
        nums.add( 3 );
        for n in nums
        {
            SystemPrintln( "n = $n" );
        }

        # Coroutines
        Task task = spawn add2( 20, 22 );
        int sum = await task as int;
        SystemPrintln( "20 + 22 = $sum" );
    }
}
```

### Build from Source

Prerequisites: .NET SDK 8, CMake ≥ 3.18, clang (the script can auto-install cmake/ninja), MSVC (for native projects); Linux builds go through WSL.

```powershell
# Place this repo and the Front compiler repo side by side (the host project references Front sources cross-repo)
#   <root>/SlangAllInOne
#   <root>/simple_language
cd <root>

# 1. Build the C VM runtime (→ csimple_lang_dll.dll; the script locates the workspace automatically)
powershell -File SlangAllInOne\scripts\build-vm-win.ps1 -Config Debug

# 2. Compile-and-run: Front in-process compile → SLIR in-memory handoff → C VM execution (bare project path, no subcommand)
dotnet run --project SlangAllInOne\SlangAllInOne.csproj -- SlangAllInOne\SLangCore\test\BaseTest\ProjectTest --no-banner

# 3. One-command full pipeline: dual-platform VM build → stdlib → 6 test suites compiled and run
powershell -File SlangAllInOne\scripts\build-all.ps1 -Run
```

The workspace-wide development entry point is [SlangAllInOne.sln](SlangAllInOne.sln) (open one solution in Visual Studio to build everything: host / Front / compilers / test hosts / native libs / plugins / tools; see [PROJECTS.md](PROJECTS.md) for the project inventory and path mapping).

## The `slang` CLI

| Command | Description |
|------|------|
| `compile <project>` | Front in-process compile; disk export by default; `--export-mode <output\|temp\|memory>` export tri-state (output = configured dir / temp = `_temp\<module>\` / memory = SLB stays in memory, uncompressed) |
| `<project path>` | **Compile-and-run in one step** (bare project path, no subcommand; replaces the former `run <project>` as of 2026-10-22): defaults to `--export-mode memory` (uncompressed SLB in-memory transfer) → C VM in-memory entry, module never hits disk; with `--export-mode output\|temp` it exports to disk first, then runs from disk |
| `<module.slb\|module.json>` | Run a bare module package file directly (equivalent to `run <module>`, both formats, magic auto-detected) |
| `run <module.slb\|module.json>` | **Run an already-compiled module artifact only** (no compile, via C VM cli_main; passing a project path errors with a hint to use `slang <project>`) |
| `run-disk <module>` | Compatibility alias of `run` (equivalent to `run`) |
| `info <module.slb\|module.json>` | Show module metadata |
| `version` | Front version + C VM DLL path / config |
| `pack-modules` | Compile the stdlib trio and pack them flat into `lib\` (invoked automatically on publish) |
| `pack-docs` | Pack user docs into `md\` (invoked automatically on publish) |

Common options: `-p, --project <path>` | `-O0..-O3` (optimize level) | `--format json|binary|binary+json` (binary = SLB; binary+json = slb main artifact + json debug copy) | `--export-mode <output|temp|memory>` (export tri-state, 2026-10-20) | `--debug` (C VM instruction trace) | `--force-run` (skip platform check) | `--cvm Debug|Release` (pick the C VM build tree) | `-- <args…>` (everything after goes into `Project._inputArgs`, read from source via `global._inputArgs`).

Exit codes: `0` success; `1` Front compile failure or bad arguments; `4` C VM DLL not found (run step 1 first); any other non-zero is passed through from the C VM.

## Repository Layout

```
SlangAllInOne/
├── SlangAllInOne.sln / .csproj / Program.cs   # Unified host `slang` (workspace dev entry)
├── FrontEnd/   # In-process invocation of the Front CommandExecutor (compile -e ir, --export-mode tri-state)
├── Backend/    # C VM P/Invoke (in-memory entry + DLL discovery)
├── Pack/       # pack-modules / pack-docs commands (self-bootstrapped on publish)
├── Project/    # Stdlib compile driver (CompileStdlib: core/math/std presets), test hosts (CSimpleVM*Test, Test, Test2), native libs (cvm_math_lib…)
├── SLangCore/
│   ├── Lib/    # Standard library sources (Core / Math / Std / SLang: Server, Render, Mysql, Tensora)
│   ├── test/   # Test suites (BaseTest / ExpendTest / MathTest / SpecialTest / BenchMark / RenderTest / TensoraTest…)
│   └── samples/# Samples (HelloWorld / GUI / Fibonacci…)
├── md/         # All user docs (syntax / lib / project / log / plugins + internal ai docs)
├── scripts/    # One-command scripts (build-all / build-vm-win|linux / compile-* / run-tests-* / release-slang)
├── tools/      # ExtractLogs / LidIndexer / SLBRoundTrip (slb↔json round-trip verification)
└── out/export/ # Compile output root (*.module.json / *.module.slb + Logs; DebugCode snapshots live under each project's export/DebugCode/)
```

Front compile pipeline (troubleshooting backbone): `Code → Token → Node → File → Meta → IR → module.json`. Stage snapshots land in the **project directory** under `export/DebugCode/`, logs in `out/export/<module>/Logs/` (always start from the earliest Error).

## Documentation Map

Master index: [md/INDEX.md](md/INDEX.md). Summary by group below. (Docs are written in Chinese.)

### Syntax (md/syntax/)

| Group | Docs |
|------|------|
| Basics | [introduction](md/syntax/introduction.md), [keywords](md/syntax/keywords.md) (keyword & sugar master table), [namespace](md/syntax/namespace.md), [variable](md/syntax/variable.md), [local](md/syntax/local.md), [global](md/syntax/global.md) |
| Types & operators | [number](md/syntax/number.md), [float8_16](md/syntax/float8_16.md) (Float8/Float16), [string](md/syntax/string.md), [data](md/syntax/data.md), [array](md/syntax/array.md), [type](md/syntax/type.md), [typealias](md/syntax/typealias.md), [express](md/syntax/express.md), [operator](md/syntax/operator.md), [cast](md/syntax/cast.md) |
| Control flow | [if](md/syntax/if.md), [switch](md/syntax/switch.md), [forwhiledowhile](md/syntax/forwhiledowhile.md), [range](md/syntax/range.md), [labelgoto](md/syntax/labelgoto.md), [try](md/syntax/try.md) (exceptions) |
| OOP | [class](md/syntax/class.md), [object](md/syntax/object.md), [interface](md/syntax/interface.md), [extend](md/syntax/extend.md) (inheritance), [function](md/syntax/function.md), [enum](md/syntax/enum.md), [attribute](md/syntax/attribute.md), [bind](md/syntax/bind.md) |
| Advanced | [template](md/syntax/template.md) (generics), [marco](md/syntax/marco.md) (macros), [coroutine](md/syntax/coroutine.md) (authoritative), [isolate](md/syntax/isolate.md), [inline_lambda](md/syntax/inline_lambda.md), [system_method](md/syntax/system_method.md), [result](md/syntax/result.md) |

### Libraries (md/lib/)

| Group | Docs |
|------|------|
| Containers | [List](md/lib/Std/Contraint/List.md), [Map](md/lib/Std/Contraint/Map.md), [HasSet](md/lib/Std/Contraint/HasSet.md) (Set), [Tuple](md/lib/Std/Contraint/Tuple.md), [Queue](md/lib/Std/Contraint/Queue.md), [Stack](md/lib/Std/Contraint/Stack.md), [LinkedList](md/lib/Std/Contraint/LinkedList.md) |
| Core | [Lz4](md/lib/Core/Lz4.md), [ProtocalBuffers](md/lib/Core/ProtocalBuffers.md) (protobuf), [Stream](md/lib/Core/Stream.md) (element streams) |
| Math | [overview](md/lib/Math/Math.md), [functions](md/lib/Math/Math-Functions.md), [big numbers](md/lib/Math/Math-BigNumbers.md), [vectors](md/lib/Math/Math-Vectors.md), [matrices](md/lib/Math/Math-Matrices.md), [dynamic matrix](md/lib/Math/Matrix.md) |
| Std | [Env](md/lib/Std/Env.md), [Component](md/lib/Std/Component.md), [Sqlite](md/lib/Std/Sqlite.md) |
| Networking (md/lib/Std/net/) | [Net overview](md/lib/Std/net/Net.md), [Tcp](md/lib/Std/net/Tcp.md), [Udp](md/lib/Std/net/Udp.md), [StreamImplent](md/lib/Std/net/StreamImplent.md), [Http](md/lib/Std/net/Http.md), [Websocket](md/lib/Std/net/Websocket.md), [Mqtt](md/lib/Std/net/Mqtt.md) |
| Service framework | [Server](md/lib/Server.md) (HTTP/WS service framework) |

### Project (md/project/)

| Doc | Contents |
|------|------|
| [project.md](md/project/project.md) | Project concepts: compile file lists, entries, global variables |
| [project-config-jsonc-guide.md](md/project/project-config-jsonc-guide.md) | **Authoritative `.jsonc` project config guide** (compileFiles / systemCalls / export…) |
| [project_sp-guide.md](md/project/project_sp-guide.md) | `.sp` entry: `_main_` / `_test_`, `Project{}`, `global.data` |
| [project-module.md](md/project/project-module.md) | Modules and class organization |
| [project_arguments.md](md/project/project_arguments.md) | CLI program arguments via `global._inputArgs` |
| [static-if.md](md/project/static-if.md) | `global.macro` macro data plane and injection priority chain |
| [optimization.md](md/project/optimization.md) | Optimization levels `-O0..-O3` |
| [environment-guide.md](md/project/environment-guide.md) | `Environment.*` platform environment and the jsonc `platform` section |
| [ffi.md](md/project/ffi.md) | **FFI** (`@DllImport` / `FFI.Library` / `dllImports`) |
| [project-system-method-call-guide.md](md/project/project-system-method-call-guide.md) | Full chain of pushing system methods down into the C VM |
| [exporter.md](md/project/exporter.md) | AOT exporter: IR → LLVM IR `.ll` |
| [test-guide.md](md/project/test-guide.md) | **Test guide**: suite ↔ host project mapping and how to run |

### Logging / Plugins / Root

| Doc | Contents |
|------|------|
| [log/log-system-guide.md](md/log/log-system-guide.md), [log/log-debug-usage.md](md/log/log-debug-usage.md) | Logging system and `Log / Logger / Profiling / Trace / Monitor` usage |
| [plugins/CSharp_Mono.md](md/plugins/CSharp_Mono.md) | `@csharp_mono(){}` inline C# |
| [plugins/PLUGIN_TEMPLATE.md](md/plugins/PLUGIN_TEMPLATE.md) | Standard plugin template |
| [CLI.md](md/CLI.md), [GUIDE.md](md/GUIDE.md) | `cx` command system / doc guide |
| [SL语法与编码规范总表.md](md/SL语法与编码规范总表.md) | Single-reference syntax & coding conventions table (distilled from 48 syntax docs) |
| [PROJECTS.md](PROJECTS.md) | **Project inventory & old→new path mapping** (read before touching projects) |
| [RELEASE.md](RELEASE.md) | **Release policy** (sole authority, AOT-only dual platform) |

## Testing

| Suite | Coverage | Host entry (single host `CSimpleVMTest`, merged 2026-10-18) |
|--------|------|----------------------|
| BaseTest | Core language (classes/generics/coroutines/containers/Float8…, 60+ `.sl`) | `-- BaseTest` |
| ExpendTest | Stdlib / extensions (Json/Xml/File/Sqlite/Isolate/Attribute/Server…) | default, no args (`-- ExpendTest`) |
| MathTest | Math library (FFI math / matrices / big numbers) | `-- MathTest` |
| SpecialTest | FFI / cross-language / AOT / process execution | `-- SpecialTest` |
| BenchMark | Benchmarks (Fibonacci/Levenshtein/Loop…) | `-- BenchMark` |
| RenderTest / TensoraTest / MysqlTest | Rendering / tensors / MySQL | `-- RenderTest` / pass an explicit project path |
| Named cases (probes/negative) | NullFast/JsonTest/Platform*/Inline*/GC probes/GameTank… | `-- <name>` (full table in the host `Program.cs`) |

The joint test host = C# Front compiles the suite → C VM executes it (Debug = in-process P/Invoke, debuggable in one process; Release = standalone process); in VS, suites are selected via launchSettings.json profiles. Full details in [md/project/test-guide.md](md/project/test-guide.md).

```powershell
powershell -File scripts\compile-tests.ps1          # compile test suites
powershell -File scripts\run-tests-win.ps1          # run on Windows + exit-code summary
powershell -File scripts\build-all.ps1 -Run         # full pipeline in one command
```

## Releases

Release policy (see [RELEASE.md](RELEASE.md), the sole authority): **Native AOT packages only, both platforms per version** — one GitHub Release carries both `slang_release_<v>_win-x64.zip` and `slang_release_<v>_linux-x64.tar.gz`; no .NET runtime needed on target machines. Classic .NET-dependent packages are for local development only. One-command release (maintainer machine):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\release-slang.ps1 -Version <x.y.z> [-Draft] [-SkipBuild] [-NoCommit] [-NoPush]
```

The pipeline is fully automated: preflight checks → Windows AOT package → Linux AOT package (WSL) → dual-platform smoke tests → packaging → git commit + tag + push → GitHub Release with both assets. C VM Release builds are hardened by default (LTO + symbol stripping + startup anti-debug) with the JIT compiled in and on by default.

## Debugging

- **VS F5 mixed debugging (recommended)**: open `SlangAllInOne.csproj` and pick the `run MiniSmoke (C# + C VM mixed)` profile from launchSettings — set C# breakpoints anywhere under `simple_language\source\**` and C breakpoints directly in the C VM sources (P/Invoke loads the DLL in-process, so symbols line up naturally).
- **Wrong runtime output**: check `out/export/<module>/Logs/Result.txt` (print mirror) first → `VM.txt` → `Front.txt` (earliest Error) → `DebugCode/` stage snapshots.

## License

[Apache-2.0](LICENSE). Full license texts and NOTICE for the third-party components statically linked into the C VM (yyjson / LZ4 / zlib / mimalloc / TLSF / Mbed TLS / SQLite) live in the repo at [`csimple_lang/third_party/LICENSES/`](../csimple_lang/third_party/LICENSES/) (as of 2026-10-18 release packages no longer carry a `licenses\` bundle - fetch from the repo when needed); `sl_mysql_lib` (GPL-2.0 static link) is not distributed in official release packages.
