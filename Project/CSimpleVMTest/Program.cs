using System.Diagnostics;
using System.Linq;
using System.Text;
using System.Text.Json;
using SimpleLanguage.Logging;
using SimpleLanguage.Project;

namespace CSimpleVMTest;

/// <summary>
/// 联合测试宿主（2026-10-18 由 CSimpleVMCore/Std/Math/Special/BenchMark/RenderTest
/// 与 Test/Test2 八个宿主工程合一）：
/// Front 进程内编译（-start=false 走 dotnet 子进程）→ 解析 module 包 → 发布包
/// slang 应用执行（2026-10-18 用户指令，取代旧的 csimple_lang 直调/P-Invoke）：
///   Debug   -> package\win32-debug\slang.exe（框架依赖宿主 + bin\ 调试 C VM，
///              标准库取包内 lib\，slb + json 调试副本齐备）；
///   Release -> package\win32-release\slang.exe（Native AOT 一体化 + bin\ 加固
///              C VM（JIT 默认开），标准库取包内 lib\ 仅 slb）。
/// 模块产物先拷入包内 &lt;package&gt;\&lt;Module&gt;\ 再 slang run（运行编译结果）：
/// moduleReferences 的相对解析在包内落空 → 走官方库直查 &lt;exe&gt;\lib\（sl_exe_dir = slang.exe
/// 所在目录），标准库即来自包内 lib\；子目录深度与 out\export\&lt;Module&gt;
/// 一致，插件 lib 按 module.json 所在目录回仓库的相对路径保持可达。
///
/// Front 编译期官方库直查布防（2026-10-18）：进程内编译的直查终点是宿主
/// bin\lib\（AppContext.BaseDirectory 下），Main 第一步先把发布包 lib\
/// 镜像进来（StagePackageLibForFrontCompile，与 RunCVM 同款包目录选择）——
/// 显式后缀 references（如 MyTest 的 "Core.module.slb"）在工程内 path 拼接
/// 落空时靠这里命中，否则严格语义直接硬报错中止编译；包不存在时静默跳过。
///
/// 用例选择（第一个非 - 开头参数；IDE 里对应 Properties\launchSettings.json 各 profile）：
///   BaseTest | ExpendTest（缺省） | MathTest | SpecialTest | BenchMark | RenderTest
///       —— 六大用例集预设（合并自八个旧宿主的默认入口）；
///   NullFast | JsonTest | … | GameTank —— 原 CSimpleVMTest 的命名用例（Other/ 探针、
///       负例与 samples 等，全表见 Presets）；
///   其他 —— 视为显式工程路径（相对/绝对均可）。
/// 其余选项：-test（跑 _test_ 入口）、-start true/false（false 走 dotnet 子进程编译）、
/// -debug（启动 slang 前暂停，便于挂调试器到子进程）、-O0..-O3（转发 Front）、
/// "--" 之后的 token 原样透传给 C VM 作 Project._inputArgs 程序参数。
/// </summary>
internal static class Program
{
    /// <summary>用例预设：名称 → 工程路径（相对 SlangAllInOne 根）；缺省 = ExpendTest。</summary>
    static readonly (string Name, string Path)[] Presets =
    {
        // 六大用例集（合并自八个旧宿主）
        ("BaseTest",    Path.Combine("SLangCore", "test", "BaseTest", "ProjectTest")),
        ("ExpendTest",  Path.Combine("SLangCore", "test", "ExpendTest", "ProjectTest")),
        ("MathTest",    Path.Combine("SLangCore", "test", "MathTest", "ProjectTest")),
        ("SpecialTest", Path.Combine("SLangCore", "test", "SpecialTest", "ProjectTest")),
        ("BenchMark",   Path.Combine("SLangCore", "test", "BenchMark", "BenchMark")),
        ("RenderTest",  Path.Combine("SLangCore", "test", "RenderTest", "ProjectTest")),
        // 命名用例（原 CSimpleVMTest）
        ("NullFast",                   Path.Combine("SLangCore", "test", "Other", "NullFastTest", "ProjectTest")),
        ("JsonTest",                   Path.Combine("SLangCore", "test", "Other", "JsonTest", "JsonTest")),
        ("CommentSpaceNegTest",        Path.Combine("SLangCore", "test", "Other", "CommentSpaceNegTest", "CommentSpaceNegTest")),
        ("PlatformAotNegTest",         Path.Combine("SLangCore", "test", "Other", "PlatformAotNegTest", "PlatformAotNegTest")),
        ("PlatformNegTest",            Path.Combine("SLangCore", "test", "Other", "PlatformNegTest", "PlatformNegTest")),
        ("PlatformOverrideNegTest",    Path.Combine("SLangCore", "test", "Other", "PlatformOverrideNegTest", "PlatformOverrideNegTest")),
        ("PlatformVariantNegTest",     Path.Combine("SLangCore", "test", "Other", "PlatformVariantNegTest", "PlatformVariantNegTest")),
        ("PlatformVariantTest",        Path.Combine("SLangCore", "test", "Other", "PlatformVariantTest", "PlatformVariantTest")),
        ("InlineLambdaTest",           Path.Combine("SLangCore", "test", "Other", "InlineLambdaTest", "ProjectTest")),
        ("InlineLambdaForbiddenTest",  Path.Combine("SLangCore", "test", "Other", "InlineLambdaForbiddenTest", "ProjectTest")),
        ("AutoInlineTest",             Path.Combine("SLangCore", "test", "Other", "AutoInlineTest", "ProjectTest")),
        ("InlineMethodTest",           Path.Combine("SLangCore", "test", "Other", "InlineMethodTest", "ProjectTest")),
        ("ARCTest",                    Path.Combine("SLangCore", "test", "Other", "ARCTest", "ArcProbe")),
        ("CoroGCProbe",                Path.Combine("SLangCore", "test", "Other", "CoroGCProbe", "CoroGCProbe")),
        ("MiProbe",                    Path.Combine("SLangCore", "test", "Other", "MiProbe", "MiProbe")),
        ("NestedGCProbe",              Path.Combine("SLangCore", "test", "Other", "NestedGCProbe", "NestedGCProbe")),
        ("OOMProbe",                   Path.Combine("SLangCore", "test", "Other", "OOMProbe", "OOMProbe")),
        ("SBAProbe",                   Path.Combine("SLangCore", "test", "Other", "SBAProbe", "SBAProbe")),
        ("SFRepro",                    Path.Combine("SLangCore", "test", "Other", "SFRepro", "SFRepro")),
        ("TLSFProbe",                  Path.Combine("SLangCore", "test", "Other", "TLSFProbe", "TLSFProbe")),
        ("AtSignLabel",                Path.Combine("SLangCore", "test", "Other", "AtSignLabel", "AtSignNegativeTest")),
        ("NetTest",                    Path.Combine("SLangCore", "test", "Other", "NetTest", "ProjectTest")),
        ("ServerTest",                  Path.Combine("SLangCore", "test", "Other", "ServerTest", "ServerTest")),
        ("HttpWebTest",                Path.Combine("SLangCore", "test", "Other", "HttpWebTest", "HttpWebTest")),
        ("MyTest",                     Path.Combine("SLangCore", "test", "Other", "MyTest", "MyTest")),
        ("CoreAutoProbe",              Path.Combine("SLangCore", "test", "Other", "CoreAutoProbe", "CoreAutoProbe")),
        ("GameTank",                   Path.Combine("SLangCore", "samples", "Game", "TankGame", "TankGame")),
    };

    static int Main(string[] args)
    {
        Console.OutputEncoding = Encoding.UTF8;
        Console.InputEncoding = Encoding.UTF8;

        string repoRoot = GetRepoRoot();

        if (args.Length >= 1 && (args[0] == "-h" || args[0] == "--help" || args[0] == "/?"))
        {
            PrintUsage();
            return 0;
        }

        // 用例选择：第一个非 - 开头参数（"--" 之后的 token 是程序参数，不参与解析）。
        string? selector = GetProjectPathArg(args);
        string projectPath = ResolvePreset(selector, repoRoot)
            ?? selector
            ?? Path.Combine(repoRoot, "SLangCore", "test", "ExpendTest", "ProjectTest");

        bool runTestEntry = args.Any(a => string.Equals(a, "-test", StringComparison.OrdinalIgnoreCase));
        bool start = TryGetBoolArg(args, "start", defaultValue: true);
        bool debug = args.Any(a => string.Equals(a, "-debug", StringComparison.OrdinalIgnoreCase));
        // -O0..-O3 / -o0..-o3 forwarded to the Front compile step (absent = compiler default level)
        string? optLevelArg = GetOptimizeLevelArg(args);
        // 程序参数（Project._inputArgs）："--" 之后所有 token 原样透传给 C VM
        // 例：dotnet run --project ... -- BenchMark -- -- w3   ->   C VM 收到 "-- w3"
        List<string> programArgs = GetProgramArgs(args);

        if (selector == null)
        {
            Console.WriteLine("No args provided, using defaults:");
            Console.WriteLine($"  projectPath = {projectPath}");
        }

        // Front 编译期官方库直查需要宿主 bin\lib\（显式后缀 references 严格装载的
        // 回退链终点），先把发布包 lib\ 镜像进来（与 RunCVM 同款包目录选择）
        StagePackageLibForFrontCompile(repoRoot);

        // Step 1: Compile with Front (in-process or via dotnet run)
        var dotnetFrontArgs = new List<string>
        {
            "run", "--project", Quote(Path.Combine(repoRoot, "..", "simple_language", "source", "SimpleLanguageFront.csproj")), "--",
            "compile", "-e", "ir", "-p", projectPath
        };
        if (optLevelArg != null)
            dotnetFrontArgs.Add(optLevelArg);
        dotnetFrontArgs.Add("--no-banner");
        // R15：供运行的模块一律二进制导出（slb 主产物 + json 调试副本），
        // 包内 run 优先装载 slb
        dotnetFrontArgs.Add("--format");
        dotnetFrontArgs.Add("binary+json");

        int frontExit = start
            ? RunFrontInProcess(projectPath, optLevelArg)
            : RunDotnet(dotnetFrontArgs, "Front compile", repoRoot);
        if (frontExit != 0)
        {
            Console.WriteLine($"Front compile failed, exit code: {frontExit}");
            // 负例工程: 前端编译失败是预期结果, 校验预期拦截 LID 全部命中则视为通过 (exit 0)
            var neg = TryGetNegativeFrontCase(args);
            if (neg != null)
                return VerifyNegativeFrontCase(neg, repoRoot, frontExit);
            return frontExit;
        }

        // Step 2: Resolve compiled module package path
        string packagePath = ResolveModulePackagePath(repoRoot, projectPath);
        if (!File.Exists(packagePath))
        {
            Console.WriteLine("Compile succeeded but module package not found:");
            Console.WriteLine(packagePath);
            return 3;
        }

        Console.WriteLine($"Package: {packagePath}");

        // Step 3: run the module via the packaged slang app (2026-10-18 用户指令：
        // Debug -> package\win32-debug / Release -> package\win32-release)。
        // C VM 测试用例使用相对路径（如 Sqlite3Test 的 Resources/ttest），
        // VS 启动时 CWD 是 bin\Debug\net8.0，需切到测试工程目录，与命令行运行环境一致
        string? projectDir = Path.GetDirectoryName(Path.GetFullPath(projectPath));
        if (Directory.Exists(projectDir))
        {
            Environment.CurrentDirectory = projectDir;
        }
        int cvmExit = RunCVM(packagePath, runTestEntry, repoRoot, debug, programArgs, out string? runOutput);
        if (cvmExit != 0)
        {
            // 运行期负例：预期退出码 + 输出标记双命中 = 通过（如 PlatformVariantNegTest
            // 的 linux-only 变体在 windows 宿主必然拒跑）
            var negRun = TryGetNegativeRunCase(args);
            if (negRun != null && cvmExit == negRun.ExpectedExitCode
                && runOutput != null && runOutput.Contains(negRun.OutputContains))
            {
                Console.WriteLine($"Negative runtime test passed: slang exited {negRun.ExpectedExitCode} as expected (marker hit).");
                return 0;
            }
            Console.WriteLine($"C VM run failed, exit code: {cvmExit}");
            return cvmExit;
        }

        Console.WriteLine("Front compile + C VM run completed.");
        return 0;
    }

    static void PrintUsage()
    {
        Console.WriteLine("Usage:");
        Console.WriteLine("  dotnet run --project Project/CSimpleVMTest/CSimpleVMTest.csproj -- [suite|case|projectPath] [options] [-- programArgs]");
        Console.WriteLine("Suites    : " + string.Join(", ", Presets.Take(6).Select(p => p.Name)));
        Console.WriteLine("Named     : " + string.Join(", ", Presets.Skip(6).Select(p => p.Name)));
        Console.WriteLine("Options   : -test | -start true/false | -debug | -O0..-O3");
        Console.WriteLine("Runtime   : packaged slang app (Debug -> package\\win32-debug, Release -> package\\win32-release);");
        Console.WriteLine("            module staged into <package>\\<Module>\\, stdlib resolved from <package>\\lib\\");
        Console.WriteLine("Default   : ExpendTest");
        Console.WriteLine("Example:");
        Console.WriteLine("  ... -- MathTest -test          (compile MathTest and run _test_ entry)");
        Console.WriteLine("  ... -- BenchMark -- -- w3      (pass program args to Project._inputArgs)");
    }

    /// <summary>预设名 → 绝对路径；未命中返回 null（selector 本身作为工程路径）。</summary>
    static string? ResolvePreset(string? selector, string repoRoot)
    {
        if (string.IsNullOrEmpty(selector))
            return null;
        foreach (var p in Presets)
        {
            if (selector.Equals(p.Name, StringComparison.OrdinalIgnoreCase))
                return Path.Combine(repoRoot, p.Path);
        }
        return null;
    }

    static int RunCVM(string packagePath, bool runTestEntry, string repoRoot, bool debug, List<string>? programArgs, out string? runOutput)
    {
        runOutput = null;
        // 发布包布局（2026-10-18 package\{win32|linux}-{debug|release}）：
        //   Debug   -> package\win32-debug  ：框架依赖 slang.exe + bin\ 调试 C VM
        //              （pdb 侧车）+ lib\ slb+json 官方库 + plugin\ 前端插件程序集；
        //   Release -> package\win32-release：Native AOT slang.exe + bin\ 加固 C VM
        //              （JIT 默认开）+ lib\ 仅 slb 官方库。
        // 包不存在时提示先跑 build-packages.ps1（不回退 dev 树——本宿主的意义即验证发布包）。
#if DEBUG
        string pkgDir = Path.Combine(repoRoot, "package", "win32-debug");
#else
        string pkgDir = Path.Combine(repoRoot, "package", "win32-release");
#endif
        string slangExe = Path.Combine(pkgDir, "slang.exe");
        if (!File.Exists(slangExe))
        {
            Console.WriteLine($"slang.exe not found in package: {pkgDir}");
            Console.WriteLine("Build the packages first:");
            Console.WriteLine("  powershell -ExecutionPolicy Bypass -File SlangAllInOne\\scripts\\build-packages.ps1");
            return 4;
        }

        // 模块产物先拷入包内 <pkg>\<Module>\ 再跑（三重目的）：
        //  1) moduleReferences 的 "../Core/Core.module" 相对解析在包内落空，
        //     C VM 走官方库直查 <exe_dir>\lib\（sl_exe_dir_join_name 取
        //     slang.exe 所在目录），标准库即取自包内 lib\ 目录；
        //  2) 子目录深度与 out\export\<Module> 一致（lang 根下第 4 层），
        //     SpecialTest 等插件 lib "../../../../plugin/..." 这类按
        //     module.json 所在目录回仓库的相对路径保持可达；
        //  3) 非系统库引用（如 ExpendTest -> SLangServer）连带拷入包内
        //     <pkg>\<RefModule>\（2026-10-20 修复）：此前引用模块不跟随，
        //     C VM 对落空引用静默 skip（仅 VM.txt Warning），跨模块调用全部
        //     落到空壳方法 → ServerConfig 字段全空 / start no-op / 测试挂死
        //     退出码仍 0（复盘见 md/ai/troubleshooting/06-build-engineering.md）。
        string? runModule = CopyModuleIntoPackage(packagePath, pkgDir, repoRoot);
        if (runModule == null)
        {
            Console.WriteLine($"Failed to stage module package into: {pkgDir}");
            return 4;
        }

        // 🔥 2026-10-22 CLI 语义：run = 只运行编译结果（产物已拷入包内，无编译步）
        var slangArgs = new List<string> { "run", Quote(runModule) };
        if (runTestEntry)
        {
            slangArgs.Add("-t");
        }
        // 程序参数（Project._inputArgs）：仅透传宿主命令行 "--" 之后的 token，
        // 无 "--" 时不注入（_inputArgs 为空数组，全量回归不受影响）。
        // InputArgsTest 三参数路径：dotnet run --project ... -- -- hello 42 world
        if (programArgs != null && programArgs.Count > 0)
        {
            slangArgs.Add("--");
            slangArgs.AddRange(programArgs);
        }

        Console.WriteLine($"Package dir: {pkgDir}");
        if (debug)
        {
            Console.WriteLine("=== slang run (package, debug pause) ===");
            Console.WriteLine($"{slangExe} {string.Join(' ', slangArgs)}");
            Console.WriteLine("Press Enter to start slang...");
            Console.ReadLine();
            return RunProcessDirect(slangExe, slangArgs, Environment.CurrentDirectory);
        }
        return RunProcess(slangExe, slangArgs, "slang run (package)", null, out runOutput);
    }

    /// <summary>把发布包 lib\（官方标准库 slb/json）镜像进宿主 bin\lib\，供 Front
    /// 进程内编译的官方库直查（ProjectReferenceModuleLoader 探测 AppContext.BaseDirectory
    /// 下 lib\|modules\）——显式后缀 references（如 MyTest 的 "Core.module.slb"）在工程内
    /// path 拼接落空时靠这里命中，否则严格语义直接硬报错中止编译。包不存在时静默跳过
    /// （RunCVM 阶段自会提示先跑 build-packages.ps1）。</summary>
    static void StagePackageLibForFrontCompile(string repoRoot)
    {
#if DEBUG
        string pkgDir = Path.Combine(repoRoot, "package", "win32-debug");
#else
        string pkgDir = Path.Combine(repoRoot, "package", "win32-release");
#endif
        string srcLib = Path.Combine(pkgDir, "lib");
        if (!Directory.Exists(srcLib))
            return;
        try
        {
            string dstLib = Path.Combine(AppContext.BaseDirectory, "lib");
            Directory.CreateDirectory(dstLib);
            foreach (string f in Directory.GetFiles(srcLib))
                File.Copy(f, Path.Combine(dstLib, Path.GetFileName(f)), overwrite: true);
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Warn: stage package lib for Front compile failed: {ex.Message}");
        }
    }

    /// <summary>把 out\export\&lt;Dir&gt;\ 的运行产物（*.module.json / *.module.slb +
    /// plugin\ 载荷，不含 Logs\DebugCode 调试快照）拷入发布包 &lt;pkgDir&gt;\&lt;Dir&gt;\，
    /// 返回包内模块文件路径（优先与传入 json 同名的 .slb 主产物，无则 .json）；失败返回 null。
    /// 产物文件名以 jsonc project.name 为准（≠ export.moduleName 时目录名与文件名不同，
    /// 如 NullFast：目录 NullFastTest\ 文件 ProjectTest.module.slb），故按实际文件名定位，
    /// 不能按目录名推导。</summary>
    static string? CopyModuleIntoPackage(string moduleJsonPath, string pkgDir, string repoRoot)
    {
        try
        {
            string moduleDir = Path.GetDirectoryName(Path.GetFullPath(moduleJsonPath))
                ?? throw new InvalidOperationException("module path has no directory");
            string dirName = Path.GetFileName(moduleDir.TrimEnd('\\', '/'));
            if (dirName.Length == 0)
                throw new InvalidOperationException("cannot derive module dir name from: " + moduleDir);
            string destDir = Path.Combine(pkgDir, dirName);
            Directory.CreateDirectory(destDir);

            foreach (string f in Directory.GetFiles(moduleDir, "*.module.*"))
                File.Copy(f, Path.Combine(destDir, Path.GetFileName(f)), overwrite: true);

            // 插件载荷子树（如 echo 插件 lib 由 Front 拷入 out\export\<Module>\plugin\）
            string pluginsSrc = Path.Combine(moduleDir, "plugin");
            if (Directory.Exists(pluginsSrc))
                CopyDirectoryRecursive(pluginsSrc, Path.Combine(destDir, "plugin"));

            // 非系统库引用模块联动拷贝（2026-10-20；见 RunCVM 注释第 3 点）
            StageReferencedModules(moduleJsonPath, pkgDir, repoRoot);

            string jsonName = Path.GetFileName(moduleJsonPath);
            string slbName = Path.GetFileNameWithoutExtension(jsonName) + ".slb";
            string slb = Path.Combine(destDir, slbName);
            if (File.Exists(slb))
                return slb;
            string json = Path.Combine(destDir, jsonName);
            return File.Exists(json) ? json : null;
        }
        catch (Exception ex)
        {
            Console.WriteLine(ex);
            return null;
        }
    }

    /// <summary>官方库集合：包内 &lt;exe&gt;\lib\ 直查（sl_exe_dir_join_name），无需跟随拷贝。</summary>
    static readonly HashSet<string> SystemModuleNames = new(StringComparer.OrdinalIgnoreCase)
    { "Core", "Std", "Math" };

    /// <summary>
    /// 解析主模块 moduleReferences，把非系统库引用（如 ExpendTest -> SLangServer）
    /// 的导出产物（*.module.slb + json 副本）一并拷入 <paramref name="pkgDir"/>\&lt;name&gt;\。
    /// 搜索两处标准导出树（repoRoot = SlangAllInOne\）：out\export\&lt;name&gt;\（标准库/
    /// SLangServer 同款 outputDir 落位）与 SLangCore\out\export\&lt;name&gt;\（用例集
    /// outputDir "..\..\out\export" 落位）。未找到仅打印提示不阻断（保持旧行为可诊断）。
    /// </summary>
    static void StageReferencedModules(string moduleJsonPath, string pkgDir, string repoRoot)
    {
        try
        {
            using JsonDocument doc = JsonDocument.Parse(File.ReadAllText(moduleJsonPath));
            if (!doc.RootElement.TryGetProperty("moduleReferences", out JsonElement refsEl))
                return;
            foreach (JsonElement r in refsEl.EnumerateArray())
            {
                if (!r.TryGetProperty("name", out JsonElement nameEl))
                    continue;
                string name = nameEl.GetString() ?? "";
                if (name.Length == 0 || SystemModuleNames.Contains(name))
                    continue;
                // repoRoot = SlangAllInOne\（GetRepoRoot 以 SlangAllInOne.csproj 定位）：
                // 两处标准导出树——out\export\（标准库/SLangServer 同款 outputDir
                // 落位）与 SLangCore\out\export\（用例集 "..\..\out\export" 落位）
                string[] exportRoots =
                {
                    Path.Combine(repoRoot, "out", "export", name),
                    Path.Combine(repoRoot, "SLangCore", "out", "export", name),
                };
                string? srcDir = exportRoots.FirstOrDefault(Directory.Exists);
                if (srcDir == null)
                {
                    Console.WriteLine($"[stage] referenced module '{name}' export dir not found, skipped");
                    continue;
                }
                string refDest = Path.Combine(pkgDir, name);
                Directory.CreateDirectory(refDest);
                bool any = false;
                foreach (string f in Directory.GetFiles(srcDir, "*.module.*"))
                {
                    File.Copy(f, Path.Combine(refDest, Path.GetFileName(f)), overwrite: true);
                    any = true;
                }
                string refPlugins = Path.Combine(srcDir, "plugin");
                if (Directory.Exists(refPlugins))
                    CopyDirectoryRecursive(refPlugins, Path.Combine(refDest, "plugin"));
                StageNativeDlls(name, srcDir, refDest);
                if (any)
                    Console.WriteLine($"[stage] referenced module '{name}' staged into package");
            }
        }
        catch (Exception ex)
        {
            // 引用联动拷贝失败不阻断主流程（C VM 装载期自会按回退链解析）
            Console.WriteLine("[stage] reference staging failed: " + ex.Message);
        }
    }

    /// <summary>
    /// 补拷引用模块关联的原生 DLL（如 SLangMysql -&gt; sl_mysql_lib.dll）到 staged 目录。
    /// 清单取自模块 json：dllImports[].path（FFI 绑定库，@DllStaticImport 静态预载用，
    /// "static" 非空时 cvm 装配期按 &lt;模块目录&gt;\&lt;basename&gt; 平铺回退查找）与
    /// vmDllImports[].name（cvm 扩展 DLL 预载，同样平落模块目录）。*.module.* 通配
    /// 不匹配 DLL，漏拷即预载落空 → SL 兜底函数体生效（clientVersion 返回 0）。
    /// staged 目录即该模块装载后的包目录（sl_dirname_from_path），与 cvm 查找位一致。
    /// 单文件失败仅提示不阻断（与 stage 整体语义一致）。
    /// </summary>
    static void StageNativeDlls(string name, string srcDir, string refDest)
    {
        string? manifest = Path.Combine(refDest, name + ".module.json");
        if (!File.Exists(manifest))
            manifest = Path.Combine(srcDir, name + ".module.json");
        if (!File.Exists(manifest))
            return;
        try
        {
            var dlls = new SortedSet<string>(StringComparer.OrdinalIgnoreCase);
            using JsonDocument doc = JsonDocument.Parse(File.ReadAllText(manifest));
            if (doc.RootElement.TryGetProperty("dllImports", out JsonElement imports))
            {
                foreach (JsonElement di in imports.EnumerateArray())
                {
                    // 只认 "static" 非空条目（cvm vm_sys_ffi_static_lib_register 同语义；
                    // static 空的是普通 SL 模块引用（如 ../Lib/Std.dll），非原生库
                    if (!di.TryGetProperty("path", out JsonElement p) ||
                        !di.TryGetProperty("static", out JsonElement s))
                        continue;
                    if (string.IsNullOrEmpty(s.GetString()))
                        continue;
                    string path = p.GetString() ?? "";
                    if (path.Length > 0)
                        dlls.Add(Path.GetFileName(path));
                }
            }
            if (doc.RootElement.TryGetProperty("vmDllImports", out JsonElement vmDlls))
            {
                foreach (JsonElement vm in vmDlls.EnumerateArray())
                {
                    string? n = vm.ValueKind == JsonValueKind.Object
                        ? (vm.TryGetProperty("name", out JsonElement ne) ? ne.GetString() : null)
                        : vm.GetString();
                    if (!string.IsNullOrEmpty(n))
                        dlls.Add(Path.GetFileName(n));
                }
            }
            foreach (string dll in dlls)
            {
                string dllSrc = Path.Combine(srcDir, dll);
                if (!File.Exists(dllSrc))
                {
                    Console.WriteLine($"[stage] native dll not found in export dir, skipped: {dll}");
                    continue;
                }
                File.Copy(dllSrc, Path.Combine(refDest, dll), overwrite: true);
                Console.WriteLine($"[stage] native dll staged: {name}\\{dll}");
            }
        }
        catch (Exception ex)
        {
            Console.WriteLine("[stage] native dll staging failed: " + ex.Message);
        }
    }

    static void CopyDirectoryRecursive(string srcDir, string destDir)
    {
        Directory.CreateDirectory(destDir);
        foreach (string f in Directory.GetFiles(srcDir))
            File.Copy(f, Path.Combine(destDir, Path.GetFileName(f)), overwrite: true);
        foreach (string d in Directory.GetDirectories(srcDir))
            CopyDirectoryRecursive(d, Path.Combine(destDir, Path.GetFileName(d)));
    }

    static int RunProcessDirect(string fileName, List<string> args, string workingDirectory)
    {
        var psi = new ProcessStartInfo
        {
            FileName = fileName,
            Arguments = string.Join(" ", args),
            WorkingDirectory = workingDirectory,
            UseShellExecute = false,
            RedirectStandardOutput = false,
            RedirectStandardError = false,
            CreateNoWindow = false
        };
        using var p = new Process { StartInfo = psi };
        p.Start();
        p.WaitForExit();
        return p.ExitCode;
    }

    static int RunProcess(string fileName, List<string> args, string stepName, string? workingDirectory, out string? captureOutput)
    {
        captureOutput = null;
        var capture = new StringBuilder();
        var psi = new ProcessStartInfo
        {
            FileName = fileName,
            Arguments = string.Join(" ", args),
            WorkingDirectory = string.IsNullOrWhiteSpace(workingDirectory) ? Environment.CurrentDirectory : workingDirectory,
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            StandardOutputEncoding = Encoding.UTF8,
            StandardErrorEncoding = Encoding.UTF8,
            CreateNoWindow = true
        };

        using var p = new Process { StartInfo = psi };

        p.OutputDataReceived += (_, e) =>
        {
            if (e.Data == null) return;
            Console.WriteLine(e.Data);
            capture.AppendLine(e.Data);
        };
        p.ErrorDataReceived += (_, e) =>
        {
            if (e.Data == null) return;
            Console.Error.WriteLine(e.Data);
            capture.AppendLine(e.Data);
        };

        Console.WriteLine($"=== {stepName} ===");
        Console.WriteLine($"{psi.FileName} {psi.Arguments}");

        p.Start();
        p.BeginOutputReadLine();
        p.BeginErrorReadLine();
        p.WaitForExit();

        captureOutput = capture.ToString();
        return p.ExitCode;
    }

    static int RunDotnet(List<string> args, string stepName, string? workingDirectory = null)
    {
        return RunProcess("dotnet", args, stepName, workingDirectory, out _);
    }
    static int RunFrontInProcess(string projectPath, string? optLevelArg = null)
    {
        try
        {
            Console.WriteLine("=== Front compile (in-process) ===");
            var frontArgs = new List<string> { "compile", "-e", "ir", "-p", projectPath };
            if (optLevelArg != null)
                frontArgs.Add(optLevelArg);
            frontArgs.Add("--no-banner");
            // R15：供运行的模块一律二进制导出（slb 主产物 + json 调试副本）
            frontArgs.Add("--format");
            frontArgs.Add("binary+json");
            Console.WriteLine("Front: " + string.Join(' ', frontArgs));
            var inputArgs = new CommandInputArgs(frontArgs.ToArray());
            bool ok = CommandExecutor.Execute(inputArgs);
            if (!ok || Log.errorCount > 0)
            {
                Console.WriteLine($"Front compile failed, error count: {Log.errorCount}");
                return 1;
            }
            return 0;
        }
        catch (Exception ex)
        {
            Console.WriteLine(ex);
            return 1;
        }
    }

    // ==== 负例工程支持: 前端编译「预期失败 = 成功」====
    // 负例工程的拦截命中会让 Front 以非零码退出, 这里读 Front.txt 校验
    // 预期拦截 LID 是否全部命中: 全命中 = 负例通过 (exit 0, 跳过 C VM 运行),
    // 有缺命中 = 真失败。只看预期 LID 命中数, 不计连锁产生的其他日志。

    private sealed class NegativeFrontCase
    {
        public string ArgName = "";          // 命令行启动项名 (args[0])
        public string ExportModuleName = ""; // 导出模块名: out/export/<名>/Logs/Front.txt
        public (string Lid, int Count)[] ExpectedLids = Array.Empty<(string, int)>();
    }

    private static readonly NegativeFrontCase[] s_negativeFrontCases = new[]
    {
        new NegativeFrontCase
        {
            ArgName = "CommentSpaceNegTest",
            ExportModuleName = "CommentSpaceNegTest",
            // compile.isForceSpaceAfterSharp=true: 3 个无空格行注释
            // (文件级独立 / _main_ 内独立 / 语句后尾随) 各拦截一次；
            // 块注释 #!...!# 与合规的 "# 注释" 不产生 20120
            ExpectedLids = new[]
            {
                ("TokenLexerCommentSpaceRequired", 3),
            }
        },
        new NegativeFrontCase
        {
            ArgName = "InlineLambdaForbiddenTest",
            ExportModuleName = "InlineLambdaForbiddenTest",
            // 6 个负例: 协程拦截 3 (spawn/await/isolate) + 自引用/互递归 2 + try? 1
            ExpectedLids = new[]
            {
                ("MetaCoreInlineLambdaBodyForbiddenCoroutine", 3),
                ("MetaCoreInlineLambdaBodyForbiddenSelfReference", 2),
                ("MetaCoreInlineLambdaBodyForbiddenExceptionFrame", 1),
            }
        },
        new NegativeFrontCase
        {
            ArgName = "PlatformNegTest",
            ExportModuleName = "PlatformNegTest",
            // 4 个非法平台值 (linuxx/arm65/sse5/vulkn) 各拦截一次
            ExpectedLids = new[]
            {
                ("ProjectPlatformRequireValueInvalid", 4),
            }
        },
        new NegativeFrontCase
        {
            ArgName = "PlatformOverrideNegTest",
            ExportModuleName = "PlatformOverrideNegTest",
            // 3 个非法 override 平台值各拦截一次
            ExpectedLids = new[]
            {
                ("ProjectPlatformRequireValueInvalid", 3),
            }
        },
        new NegativeFrontCase
        {
            ArgName = "PlatformAotNegTest",
            ExportModuleName = "PlatformAotNegTest",
            // aot 与 platform 声明冲突拦截
            ExpectedLids = new[]
            {
                ("ProjectPlatformAotFeatureConflict", 1),
            }
        },
        new NegativeFrontCase
        {
            ArgName = "AtSignLabel",   // → AtSignNegativeTest：@csharp_mono 块通道负例
            ExportModuleName = "AtSignNegativeTest",
            // sp 注释自明：编译期必失败（驱动只断言 LID 计数，不运行 VM）。
            // 6 处通道语法负例（var 入通道×4 / 中段通道行 / 未知类型）+ 1 处双出通道冲突
            ExpectedLids = new[]
            {
                ("ProcessAtSignLabelChannelSyntaxError", 6),
                ("ProcessAtSignLabelOutChannelMultiple", 1),
            }
        },
    };

    /// <summary>运行期负例：Front 编译成功，C VM 装载/校验层预期拒跑
    /// （退出码 + 输出标记双判据，命中即视为通过）。</summary>
    private sealed class NegativeRunCase
    {
        public string ArgName = "";        // 命令行启动项名 (args[0])
        public int ExpectedExitCode = 1;   // C VM 预期退出码
        public string OutputContains = ""; // 输出必须包含的标记片段
    }

    private static readonly NegativeRunCase[] s_negativeRunCases = new[]
    {
        new NegativeRunCase
        {
            ArgName = "PlatformVariantNegTest",
            ExpectedExitCode = 1,
            // linux-only 平台变体在 windows 宿主必然不匹配（--force-run 才可跳过）
            OutputContains = "平台变体均不匹配",
        },
    };

    static NegativeFrontCase? TryGetNegativeFrontCase(string[] args)
    {
        if (args.Length == 0)
            return null;
        return s_negativeFrontCases.FirstOrDefault(c => c.ArgName == args[0]);
    }

    static NegativeRunCase? TryGetNegativeRunCase(string[] args)
    {
        if (args.Length == 0)
            return null;
        return s_negativeRunCases.FirstOrDefault(c => c.ArgName == args[0]);
    }

    // 校验负例: 按行统计 Front.txt 中 "[LID]" 出现次数, 预期全部达标 = 通过
    static int VerifyNegativeFrontCase(NegativeFrontCase neg, string repoRoot, int frontExit)
    {
        // 优先用 Front 写入的日志路径 (in-process 模式下最准确), 回退到按模块名推导
        string? logPath = Log.FrontLogFilePath;
        if (string.IsNullOrWhiteSpace(logPath) || !File.Exists(logPath))
            logPath = Path.Combine(repoRoot, "out", "export", neg.ExportModuleName, "Logs", "Front.txt");
        if (!File.Exists(logPath))
        {
            Console.WriteLine($"Negative case '{neg.ArgName}': Front log not found: {logPath}");
            return frontExit;
        }

        var lines = File.ReadAllLines(logPath);
        bool allHit = true;
        Console.WriteLine($"=== Negative front case '{neg.ArgName}': verify expected LID hits ===");
        foreach (var (lid, expected) in neg.ExpectedLids)
        {
            int actual = lines.Count(l => l.Contains("[" + lid + "]"));
            bool hit = actual >= expected;
            Console.WriteLine($"  [{(hit ? "OK" : "MISS")}] {lid}: expect >= {expected}, actual {actual}");
            if (!hit)
                allHit = false;
        }
        if (allHit)
        {
            Console.WriteLine($"Negative test passed: all expected LID interceptions hit, skip C VM run.");
            return 0;
        }
        Console.WriteLine("Negative test FAILED: some expected LID interceptions missing.");
        return frontExit;
    }

    static string ResolveModulePackagePath(string repoRoot, string projectPath)
    {
        /* 编译同进程完成后从 jsonc 派生的进程内状态取导出目录
         *（SIMPLELANG_EXPORT_OUTDIR 仅保留为外部手动覆盖入口）。 */
        var exportDir = ProjectOutputEnvironment.GetEffectiveExportOutDir();
        if (!string.IsNullOrWhiteSpace(exportDir))
        {
            var d = Path.GetFullPath(exportDir.Trim());
            if (Directory.Exists(d))
            {
                var found = Directory.GetFiles(d, "*.module.json");
                if (found.Length == 1)
                    return found[0];
                if (found.Length > 1)
                    return found.OrderByDescending(File.GetLastWriteTimeUtc).First();
            }
        }

        // Derive module name from project path
        var moduleName = !string.IsNullOrWhiteSpace(projectPath)
            ? Path.GetFileName(projectPath.TrimEnd('\\', '/'))
            : "Core";
        var fallback = Path.Combine(repoRoot, "out", "export", moduleName, moduleName + ".module.json");
        if (File.Exists(fallback))
            return fallback;

        // Final fallback: search export dir for any module.json
        var exportRoot = Path.Combine(repoRoot, "out", "export");
        if (Directory.Exists(exportRoot))
        {
            var found = Directory.GetFiles(exportRoot, "*.module.json", SearchOption.AllDirectories);
            if (found.Length >= 1)
                return found.OrderByDescending(File.GetLastWriteTimeUtc).First();
        }

        return Path.Combine(repoRoot, "out", "export", "Core", "Core.module.json");
    }

    static string? GetProjectPathArg(string[] args)
    {
        for (int i = 0; i < args.Length; i++)
        {
            var a = args[i];
            // "--" 之后的 token 属于程序参数（透传给 C VM），不参与本宿主选项解析
            if (a == "--")
                break;
            if (string.IsNullOrEmpty(a) || a.StartsWith('-'))
                continue;
            // "-start true/false" takes the next token as its value, not a project path
            if (i > 0 && string.Equals(args[i - 1], "-start", StringComparison.OrdinalIgnoreCase))
                continue;
            return a;
        }
        return null;
    }

    static List<string> GetProgramArgs(string[] args)
    {
        var result = new List<string>();
        int idx = Array.IndexOf(args, "--");
        if (idx >= 0)
        {
            for (int i = idx + 1; i < args.Length; i++)
                result.Add(args[i]);
        }
        return result;
    }

    static string? GetOptimizeLevelArg(string[] args)
    {
        // Same -O0..-O3 / -o0..-o3 pattern as CommandInputArgs
        foreach (var a in args)
        {
            if (a.Length == 3 && a[0] == '-'
                && (a[1] == 'O' || a[1] == 'o')
                && a[2] >= '0' && a[2] <= '3')
                return a;
        }
        return null;
    }

    static string GetRepoRoot()
    {
        string dir = AppContext.BaseDirectory;
        var d = new DirectoryInfo(dir);
        while (d != null && !File.Exists(Path.Combine(d.FullName, "SlangAllInOne.csproj")))
        {
            d = d.Parent;
        }
        if (d == null)
            throw new DirectoryNotFoundException("Cannot locate repo root (SlangAllInOne.csproj).");
        return d.FullName;
    }

    static string Quote(string s)
    {
        if (string.IsNullOrEmpty(s)) return "\"\"";
        if (s.Contains(' ') || s.Contains('\t') || s.Contains('"'))
            return "\"" + s.Replace("\"", "\\\"") + "\"";
        return s;
    }

    static bool TryGetBoolArg(string[] args, string key, bool defaultValue)
    {
        if (args == null || args.Length == 0)
        {
            return defaultValue;
        }

        string keyLower = key.ToLowerInvariant();
        for (int i = 0; i < args.Length; i++)
        {
            var a = args[i];
            if (string.IsNullOrWhiteSpace(a))
            {
                continue;
            }

            var low = a.ToLowerInvariant();
            if (low == $"--{keyLower}" || low == $"-{keyLower}")
            {
                if (i + 1 < args.Length && bool.TryParse(args[i + 1], out var parsed))
                {
                    return parsed;
                }
                return true;
            }

            if (low.StartsWith($"--{keyLower}=", StringComparison.Ordinal))
            {
                var raw = a.Substring(key.Length + 3);
                if (bool.TryParse(raw, out var parsed))
                {
                    return parsed;
                }
            }
        }

        return defaultValue;
    }
}
