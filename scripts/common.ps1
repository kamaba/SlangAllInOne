# common.ps1 - Shared helpers for all SimpleLanguage build/run scripts.
# Dot-source this file from the other scripts in this folder.
# ASCII only (PowerShell 5.1 encoding safe).
#
# Pipeline facts (verified on disk, 2026-10-18):
#   Front compile : dotnet run --project simple_language\source\SimpleLanguageFront.csproj -- compile -p <sp> -e ir
#   Stdlib        : dotnet run --project SlangAllInOne\Project\CompileStdlib\SimpleLanguageCompileStdlib.csproj -- core|math|std
#                   (CompileCore/CompileMath/CompileStd merged into one driver; "all" = Core -> Std -> Math
#                    with one clean child process per module, built into the driver)
#   VM Windows    : clang preferred (csimple_lang\scripts\cmake-build-clang.ps1 -> build\<C>\bin\csimple_lang.exe);
#                   without clang, falls back to incremental build of the existing configured tree build\<C>
#                   (this machine was configured with MSVC + ninja inside VS).
#   VM Linux(WSL) : cmake clang/ninja into build\<C>Linux                                   -> build\<C>Linux\bin\csimple_lang
#   Run Windows   : csimple_lang.exe run --no-banner <module.json>
#   Run Linux     : cd <repo> && SL_FORCE_RUN=1 csimple_lang run --no-banner <module.json>
#
# IMPORTANT: the front compiler returns exit code 0 even when compilation fails,
# so "module.json was rewritten during this run" is the real success check.

# Scripts may sit at <workspace>\scripts\ (legacy) or at
# <workspace>\SlangAllInOne\scripts\ (current, inside the git repo).
# The workspace root is the directory that contains csimple_lang - detect
# which layout we are in so both locations work.
$RepoRoot  = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path (Join-Path $RepoRoot 'csimple_lang'))) {
    $RepoRoot  = Split-Path -Parent $RepoRoot
}
$AllInOneDir = Join-Path $RepoRoot 'SlangAllInOne'
$SLDir     = Join-Path $RepoRoot 'simple_language'
$SLCoreDir = Join-Path $AllInOneDir 'SLangCore'    # test suites live at $SLCoreDir\test\... since the 2026-10-17 reorg
$VMDir     = Join-Path $RepoRoot 'csimple_lang'
$ExportDir = Join-Path $AllInOneDir 'out\export'
$FrontProj = Join-Path $SLDir 'source\SimpleLanguageFront.csproj'

# 2026-10-18: CompileCore/CompileMath/CompileStd merged into one driver -
# core/math/std presets (launchSettings.json profiles in that project), plus
# all (Core -> Std -> Math, one clean child process per module, built in;
# Std only references Core, Math references Core+Std - order makes a clean
# out\export build fully self-bootstrapping).
$StdlibDriverCsproj = Join-Path $AllInOneDir 'Project\CompileStdlib\SimpleLanguageCompileStdlib.csproj'
$StdlibModules = @(
    @{ Name = 'Core'; Preset = 'core'; Module = 'Core\Core.module.json' },
    @{ Name = 'Std';  Preset = 'std';  Module = 'Std\Std.module.json' },
    @{ Name = 'Math'; Preset = 'math'; Module = 'Math\Math.module.json' }
)

# name -> @{ Sp = .sp path relative to SlangAllInOne\SLangCore; Module = module.json relative to out\export;
#           Broken = skip reason (optional); ExitOkLinux = expected exit code on Linux (optional, default 0);
#           NoteWin / NoteLinux = known-issues note shown in the run summary (optional) }
$TestMap = [ordered]@{
    'BaseTest'     = @{ Sp = 'test\BaseTest\ProjectTest.sp';           Module = 'ProjectTest\ProjectTest.module.json';
                        NoteWin = '9 FAILs are pre-existing Monitor P5/P6 issues';
                        NoteLinux = '9 FAILs are pre-existing Monitor P5/P6 issues' }
    'ExpendTest'   = @{ Sp = 'test\ExpendTest\ProjectTest.sp';         Module = 'ProjectTest2\ProjectTest.module.json';
                        NoteWin = 'Sqlite3Test FAILs if cwd != test\ExpendTest (Resources/ relative path)';
                        NoteLinux = 'Sqlite3Test FAILs if cwd != test\ExpendTest (Resources/ relative path)' }
    'MathTest'     = @{ Sp = 'test\MathTest\ProjectTest.sp';           Module = 'MathTest\ProjectTest.module.json';
                        NoteLinux = 'matrix 3x3/4x4 FAILs expected: native math_lib.dll is Windows-only' }
    'SpecialTest'  = @{ Sp = 'test\SpecialTest\ProjectTest.sp';        Module = 'SpecialTest\SpecialTest.module.json';
                        ExitOkLinux = 1;
                        NoteLinux = 'exit 1 expected: win64-only plugins are skipped by platform check' }
    'BenchMark'    = @{ Sp = 'test\BenchMark\BenchMark.sp';            Module = 'BenchMark\BenchMark.module.json' }
    'NullFastTest' = @{ Sp = 'test\Other\NullFastTest\ProjectTest.sp'; Module = 'NullFastTest\ProjectTest.module.json' }
    # Broken suites - kept for reference, always skipped by every script.
    'TensoraTest'  = @{ Sp = 'test\TensoraTest\ProjectTest.sp';        Module = ''; Broken = 'Tensora library fails to compile' }
    'RenderTest'   = @{ Sp = 'test\RenderTest\ProjectTest.sp';         Module = ''; Broken = 'incomplete suite; would overwrite ExpendTest output (same moduleName ProjectTest2)' }
    'MysqlTest'    = @{ Sp = 'test\Other\MysqlTest\ProjectTest.sp';    Module = ''; Broken = 'needs a remote mysql db and has no C VM adapter' }
    # Optional suites - pass explicitly via -Tests.
    'InlineLambdaTest' = @{ Sp = 'test\Other\InlineLambdaTest\ProjectTest.sp'; Module = 'InlineLambdaTest\ProjectTest.module.json' }
    'InlineMethodTest' = @{ Sp = 'test\Other\InlineMethodTest\ProjectTest.sp'; Module = 'InlineMethodTest\ProjectTest.module.json' }
    'AutoInlineTest'   = @{ Sp = 'test\Other\AutoInlineTest\ProjectTest.sp';   Module = 'AutoInlineTest\ProjectTest.module.json' }
}

$DefaultTests = @('BaseTest','ExpendTest','MathTest','SpecialTest','BenchMark','NullFastTest')

function ConvertTo-WslPath([string]$WinPath) {
    # d:\a\b -> /mnt/d/a/b
    return '/mnt/' + $WinPath.Substring(0, 1).ToLower() + $WinPath.Substring(2).Replace('\', '/')
}

function Write-Header([string]$Text) {
    Write-Host ''
    Write-Host ('=== ' + $Text + ' ===') -ForegroundColor Cyan
}

function Test-SuiteName([string[]]$Tests) {
    $bad = @($Tests | Where-Object { -not $TestMap.Contains($_) })
    if ($bad.Count -gt 0) {
        Write-Host ('Unknown suite(s): ' + ($bad -join ', ')) -ForegroundColor Red
        Write-Host ('Known suites  : ' + ($TestMap.Keys -join ', ')) -ForegroundColor Yellow
        return $false
    }
    return $true
}

function Get-ModuleFresh([string]$ModPath, [datetime]$Start) {
    # The front compiler exits 0 even on failure, so the real check is whether
    # module.json was rewritten during the run (with a small clock tolerance).
    if (-not (Test-Path $ModPath)) { return $false }
    if ((Get-Item $ModPath).LastWriteTime -ge $Start.AddSeconds(-5)) { return $true }
    return $false
}

function Find-VsPath {
    # Latest Visual Studio installation path via vswhere, or $null.
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (-not (Test-Path $vswhere)) { return $null }
    $vsPath = & $vswhere -latest -products '*' -property installationPath
    if ($vsPath) { return $vsPath.Trim() }
    return $null
}

function Find-ClangOnWin {
    # clang.exe path or $null (clang is not installed on every machine).
    $c = Get-Command clang.exe -ErrorAction SilentlyContinue
    if ($c) { return $c.Source }
    $p = Join-Path $env:ProgramFiles 'LLVM\bin\clang.exe'
    if (Test-Path $p) { return $p }
    $vsPath = Find-VsPath
    if ($vsPath) {
        $llvmRoot = Join-Path $vsPath 'VC\Tools\Llvm'
        if (Test-Path $llvmRoot) {
            $hit = Get-ChildItem -Path $llvmRoot -Recurse -Filter clang.exe -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($hit) { return $hit.FullName }
        }
    }
    return $null
}

function Import-VsDevEnv {
    # Make cl.exe visible in this process (already true inside a VS developer prompt).
    # Returns $true when cl.exe is available afterwards.
    if (Get-Command cl.exe -ErrorAction SilentlyContinue) { return $true }
    $vsPath = Find-VsPath
    if (-not $vsPath) { return $false }
    $devShell = Join-Path $vsPath 'Common7\Tools\Microsoft.VisualStudio.DevShell.dll'
    if (-not (Test-Path $devShell)) { return $false }
    try {
        Import-Module $devShell -ErrorAction Stop
        $null = Enter-VsDevShell -VsInstallPath $vsPath -SkipAutomaticLocation -DevCmdArguments '-arch=x64' -ErrorAction Stop
    } catch {
        Write-Host ('Enter-VsDevShell failed: ' + $_.Exception.Message) -ForegroundColor Yellow
        return $false
    }
    if (Get-Command cl.exe -ErrorAction SilentlyContinue) { return $true }
    return $false
}

function Find-CMakeOnWin {
    # cmake.exe path or $null (looks in PATH, then inside Visual Studio).
    $c = Get-Command cmake.exe -ErrorAction SilentlyContinue
    if ($c) { return $c.Source }
    $vsPath = Find-VsPath
    if ($vsPath) {
        $p = Join-Path $vsPath 'Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe'
        if (Test-Path $p) { return $p }
    }
    return $null
}

function Invoke-BuildVmWin([string]$Config, [switch]$Harden) {
    $buildDir = Join-Path $VMDir ('build\' + $Config)
    $exe = Join-Path $buildDir 'bin\csimple_lang.exe'

    # Preferred path: clang + ninja via the repo's own build script.
    $clang = Find-ClangOnWin
    if ($clang) {
        Write-Header ('Build C VM - Windows ' + $Config + ' (clang + ninja)')
        $buildScript = Join-Path $VMDir 'scripts\cmake-build-clang.ps1'
        if (-not (Test-Path $buildScript)) {
            Write-Host ('Build script not found: ' + $buildScript) -ForegroundColor Red
            return $false
        }
        # Make clang visible to the child script even when it lives outside PATH.
        $clangDir = Split-Path -Parent $clang
        if (@($env:PATH -split ';') -notcontains $clangDir) { $env:PATH = $clangDir + ';' + $env:PATH }
        # Run as a child process: that script calls exit on failure and would kill this process.
        powershell -NoProfile -ExecutionPolicy Bypass -File $buildScript -Configuration $Config | Out-Host
        if ($LASTEXITCODE -ne 0) {
            Write-Host ('C VM Windows build FAILED (exit ' + $LASTEXITCODE + ')') -ForegroundColor Red
            return $false
        }
        if (-not (Test-Path $exe)) {
            Write-Host ('Build reported success but exe not found: ' + $exe) -ForegroundColor Red
            return $false
        }
        Write-Host ('C VM Windows build OK -> ' + $exe) -ForegroundColor Green
        if ($Harden) { return Invoke-HardenVmWin $Config }
        return $true
    }

    # Fallback: incremental build of the already-configured tree (e.g. MSVC + ninja).
    if (Test-Path (Join-Path $buildDir 'CMakeCache.txt')) {
        Write-Header ('Build C VM - Windows ' + $Config + ' (incremental build of the existing configured tree; clang not installed)')
        if (-not (Invoke-HardenVmWin $Config -BuildOnly)) {
            return $false
        }
        if (-not (Test-Path $exe)) {
            Write-Host ('Build reported success but exe not found: ' + $exe) -ForegroundColor Red
            return $false
        }
        Write-Host ('C VM Windows build OK -> ' + $exe) -ForegroundColor Green
        if ($Harden) { return Invoke-HardenVmWin $Config }
        return $true
    }

    Write-Header ('Build C VM - Windows ' + $Config)
    Write-Host 'No clang.exe on this machine and no existing CMake build tree either.' -ForegroundColor Red
    Write-Host 'Install LLVM clang (winget install LLVM.LLVM), then re-run.' -ForegroundColor Yellow
    return $false
}

# BINARY_HARDENING.md P2: flip SLVM_HARDEN on the existing Windows build tree
# and rebuild. -BuildOnly just builds the tree as-is (used by the fallback path
# inside Invoke-BuildVmWin, which historically built via cmake --build here).
function Invoke-HardenVmWin([string]$Config, [switch]$BuildOnly) {
    $buildDir = Join-Path $VMDir ('build\' + $Config)
    if (-not (Test-Path (Join-Path $buildDir 'CMakeCache.txt'))) {
        Write-Host ('No configured CMake tree for the hardening pass: ' + $buildDir) -ForegroundColor Red
        Write-Host ('Run scripts\build-vm-win.ps1 -Config ' + $Config + ' once first.') -ForegroundColor Yellow
        return $false
    }
    if (-not (Import-VsDevEnv)) {
        Write-Host 'cl.exe is not available: open a VS developer prompt or install LLVM clang (winget install LLVM.LLVM).' -ForegroundColor Red
        return $false
    }
    $cmake = Find-CMakeOnWin
    if (-not $cmake) {
        Write-Host 'cmake.exe not found (looked in PATH and inside Visual Studio).' -ForegroundColor Red
        return $false
    }
    if ($BuildOnly) {
        Write-Host ('cmake --build ' + $buildDir + ' -j8')
        & $cmake --build $buildDir -j8 | Out-Host
        if ($LASTEXITCODE -ne 0) {
            Write-Host ('C VM Windows build FAILED (exit ' + $LASTEXITCODE + ')') -ForegroundColor Red
            return $false
        }
        return $true
    }
    Write-Header ('Harden C VM - Windows ' + $Config + ' (SLVM_HARDEN=ON; full rebuild expected when the tree was last built without it)')
    # Release packages ship the JIT compiled in and ON by default (JIT_DESIGN.md
    # 6.1; 2026-10-18 user directive). CMakeLists defaults VM_JIT_ENABLE=ON only
    # for trees WITHOUT a cached value - an older cache holding OFF would keep
    # the JIT out. Pin it explicitly here so every Release package build is
    # guaranteed a JIT-enabled VM. Debug trees stay unpinned (JIT OFF by design,
    # interpreter stays source-debuggable).
    $cmakeArgs = @('-S', $VMDir, '-B', $buildDir, '-DSLVM_HARDEN=ON')
    if ($Config -eq 'Release') { $cmakeArgs += '-DVM_JIT_ENABLE=ON' }
    & $cmake @cmakeArgs | Out-Host
    if ($LASTEXITCODE -ne 0) {
        Write-Host ('C VM hardening reconfigure FAILED (exit ' + $LASTEXITCODE + ')') -ForegroundColor Red
        return $false
    }
    & $cmake --build $buildDir -j8 | Out-Host
    if ($LASTEXITCODE -ne 0) {
        Write-Host ('C VM hardened build FAILED (exit ' + $LASTEXITCODE + ')') -ForegroundColor Red
        return $false
    }
    Write-Host ('C VM hardened build OK (startup anti-debug gate on)') -ForegroundColor Green
    return $true
}

function Invoke-BuildVmLinux([string]$Config, [switch]$Harden) {
    Write-Header ('Build C VM - WSL Linux ' + $Config + ' (clang + ninja' + $(if ($Harden) { ', SLVM_HARDEN=ON' }) + ')')
    if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
        Write-Host 'wsl.exe not found on this machine' -ForegroundColor Red
        return $false
    }
    $wslVm = ConvertTo-WslPath $VMDir
    $buildDir = 'build/' + $Config + 'Linux'
    $cmd = 'cd ' + $wslVm + ' && cmake -S . -B ' + $buildDir +
           ' -G Ninja -DCMAKE_BUILD_TYPE=' + $Config +
           ' -DCMAKE_C_COMPILER=clang -DCMAKE_MAKE_PROGRAM=/usr/bin/ninja' +
           ' -DCMAKE_RUNTIME_OUTPUT_DIRECTORY=' + $wslVm + '/' + $buildDir + '/bin' +
           $(if ($Harden) { ' -DSLVM_HARDEN=ON' }) +
           ' && cmake --build ' + $buildDir + ' --target csimple_lang -j8'
    wsl bash -c $cmd | Out-Host
    if ($LASTEXITCODE -ne 0) {
        Write-Host ('C VM Linux build FAILED (exit ' + $LASTEXITCODE + ')') -ForegroundColor Red
        return $false
    }
    $exe = Join-Path $VMDir ('build\' + $Config + 'Linux\bin\csimple_lang')
    if (-not (Test-Path $exe)) {
        Write-Host ('Build reported success but exe not found: ' + $exe) -ForegroundColor Red
        return $false
    }
    Write-Host ('C VM Linux build OK -> ' + $exe) -ForegroundColor Green
    return $true
}

function Invoke-CompileStdlib {
    Write-Header 'Compile stdlib (Core -> Std -> Math)'
    # One preset run per module (not a single "-- all"): keeps the per-module
    # exit-code + module.json freshness verdicts, same granularity as before.
    Push-Location $AllInOneDir
    $ok = $true
    try {
        foreach ($p in $StdlibModules) {
            $modPath = Join-Path $ExportDir $p.Module
            $start = Get-Date
            Write-Host ('--- ' + $p.Name + ' : dotnet run --project ...CompileStdlib -- ' + $p.Preset)
            dotnet run --project $StdlibDriverCsproj -- $p.Preset | Out-Host
            $exit = $LASTEXITCODE
            $fresh = Get-ModuleFresh $modPath $start
            if ($exit -eq 0 -and $fresh) {
                Write-Host ($p.Name + ' OK') -ForegroundColor Green
            } else {
                Write-Host ($p.Name + ' FAILED (exit=' + $exit + ', module rewritten=' + $fresh + ')') -ForegroundColor Red
                $ok = $false
            }
        }
    } finally {
        Pop-Location
    }
    return $ok
}

function Invoke-CompileTests([string[]]$Tests) {
    Write-Header ('Compile test suites : ' + ($Tests -join ', '))
    Push-Location $SLCoreDir
    $failed = @()
    try {
        foreach ($t in $Tests) {
            $info = $TestMap[$t]
            if ($info.Broken) {
                Write-Host ($t + ' SKIPPED (broken: ' + $info.Broken + ')') -ForegroundColor Yellow
                continue
            }
            $spPath = Join-Path $SLCoreDir $info.Sp
            if (-not (Test-Path $spPath)) {
                Write-Host ($t + ' FAILED : .sp not found: ' + $info.Sp) -ForegroundColor Red
                $failed += $t
                continue
            }
            $modPath = Join-Path $ExportDir $info.Module
            $start = Get-Date
            Write-Host ('--- ' + $t + ' : compile -p ' + $info.Sp + ' -e ir')
            dotnet run --project $FrontProj -- compile -p $spPath -e ir | Out-Host
            $exit = $LASTEXITCODE
            $fresh = Get-ModuleFresh $modPath $start
            if ($exit -eq 0 -and $fresh) {
                Write-Host ($t + ' compile OK') -ForegroundColor Green
            } else {
                Write-Host ($t + ' compile FAILED (exit=' + $exit + ', module rewritten=' + $fresh + ')') -ForegroundColor Red
                $failed += $t
            }
        }
    } finally {
        Pop-Location
    }
    if ($failed.Count -gt 0) {
        Write-Host ('Compile FAILED for: ' + ($failed -join ', ')) -ForegroundColor Red
        return $false
    }
    return $true
}

function Invoke-RunTestsWin([string[]]$Tests, [string]$Config) {
    Write-Header ('Run suites on Windows (C VM ' + $Config + ') : ' + ($Tests -join ', '))
    $exe = Join-Path $VMDir ('build\' + $Config + '\bin\csimple_lang.exe')
    if (-not (Test-Path $exe)) {
        Write-Host ('C VM exe not found: ' + $exe) -ForegroundColor Red
        Write-Host 'Run scripts\build-vm-win.ps1 first.' -ForegroundColor Yellow
        return $false
    }
    $rows = @()
    $allOk = $true
    foreach ($t in $Tests) {
        $info = $TestMap[$t]
        if ($info.Broken) {
            Write-Host ($t + ' SKIPPED (broken: ' + $info.Broken + ')') -ForegroundColor Yellow
            $rows += [pscustomobject]@{ Suite = $t; Exit = 'SKIP'; Time = ''; Note = $info.Broken }
            continue
        }
        $modPath = Join-Path $ExportDir $info.Module
        if (-not (Test-Path $modPath)) {
            Write-Host ($t + ' SKIPPED : module.json not found, run scripts\compile-tests.ps1 first') -ForegroundColor Yellow
            $rows += [pscustomobject]@{ Suite = $t; Exit = 'SKIP'; Time = ''; Note = 'module.json missing' }
            $allOk = $false
            continue
        }
        Write-Host ('--- ' + $t)
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        & $exe run --no-banner $modPath | Out-Host
        $exit = $LASTEXITCODE
        $sw.Stop()
        $secs = [math]::Round($sw.Elapsed.TotalSeconds, 1)
        $note = ''
        if ($info.NoteWin) { $note = $info.NoteWin }
        if ($exit -eq 0) {
            Write-Host ($t + ' : exit 0 (' + $secs + 's)') -ForegroundColor Green
        } else {
            Write-Host ($t + ' : exit ' + $exit + ' (expected 0)') -ForegroundColor Red
            $allOk = $false
        }
        $rows += [pscustomobject]@{ Suite = $t; Exit = $exit; Time = ('' + $secs + 's'); Note = $note }
    }
    Write-Host ''
    $rows | Format-Table -AutoSize | Out-Host
    return $allOk
}

function Invoke-RunTestsLinux([string[]]$Tests, [string]$Config) {
    Write-Header ('Run suites on WSL Linux (C VM ' + $Config + ') : ' + ($Tests -join ', '))
    if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
        Write-Host 'wsl.exe not found on this machine' -ForegroundColor Red
        return $false
    }
    $exeWin = Join-Path $VMDir ('build\' + $Config + 'Linux\bin\csimple_lang')
    if (-not (Test-Path $exeWin)) {
        Write-Host ('C VM Linux exe not found: ' + $exeWin) -ForegroundColor Red
        Write-Host 'Run scripts\build-vm-linux.ps1 first.' -ForegroundColor Yellow
        return $false
    }
    $wslRoot = ConvertTo-WslPath $RepoRoot
    $wslExe  = (ConvertTo-WslPath $VMDir) + '/build/' + $Config + 'Linux/bin/csimple_lang'
    $rows = @()
    $allOk = $true
    foreach ($t in $Tests) {
        $info = $TestMap[$t]
        if ($info.Broken) {
            Write-Host ($t + ' SKIPPED (broken: ' + $info.Broken + ')') -ForegroundColor Yellow
            $rows += [pscustomobject]@{ Suite = $t; Exit = 'SKIP'; Time = ''; Note = $info.Broken }
            continue
        }
        $modPath = Join-Path $ExportDir $info.Module
        if (-not (Test-Path $modPath)) {
            Write-Host ($t + ' SKIPPED : module.json not found, run scripts\compile-tests.ps1 first') -ForegroundColor Yellow
            $rows += [pscustomobject]@{ Suite = $t; Exit = 'SKIP'; Time = ''; Note = 'module.json missing' }
            $allOk = $false
            continue
        }
        $wslMod = ConvertTo-WslPath $modPath
        # Keep this command free of double quotes and $ signs (powershell -> wsl bash -c passing).
        $cmd = 'cd ' + $wslRoot + ' && SL_FORCE_RUN=1 ' + $wslExe + ' run --no-banner ' + $wslMod
        Write-Host ('--- ' + $t)
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        wsl bash -c $cmd | Out-Host
        $exit = $LASTEXITCODE
        $sw.Stop()
        $secs = [math]::Round($sw.Elapsed.TotalSeconds, 1)
        $expected = 0
        if ($info.ExitOkLinux) { $expected = $info.ExitOkLinux }
        $note = ''
        if ($info.NoteLinux) { $note = $info.NoteLinux }
        if ($exit -eq $expected) {
            Write-Host ($t + ' : exit ' + $exit + ' (expected ' + $expected + ', ' + $secs + 's)') -ForegroundColor Green
        } else {
            Write-Host ($t + ' : exit ' + $exit + ' (expected ' + $expected + ')') -ForegroundColor Red
            $allOk = $false
        }
        $rows += [pscustomobject]@{ Suite = $t; Exit = $exit; Time = ('' + $secs + 's'); Note = $note }
    }
    Write-Host ''
    $rows | Format-Table -AutoSize | Out-Host
    return $allOk
}
