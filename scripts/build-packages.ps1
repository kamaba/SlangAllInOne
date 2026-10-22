# build-packages.ps1 - Build the four local slang packages under SlangAllInOne\package\:
#   win32-debug / win32-release   Windows host: dotnet publish -c Debug | -c Release
#   linux-debug  / linux-release   WSL: C VM .so + dotnet publish + bin\ assembly
#
# Package forms (2026-10-18 user directive; authoritative doc RELEASE.md):
#   *-debug   : Front (.NET Debug assemblies + pdb) + C VM Debug dll/so (+pdb) -
#               both ends source-debuggable, framework-dependent (.NET 8 runtime
#               needed on the target); the Debug C VM has no JIT by design;
#               lib\ packs the *.module.json debug copies next to the slb by
#               default (csproj PackStdModules --config Debug).
#   *-release : Native AOT single-file native slang (zero .NET dependency) +
#               hardened C VM Release runtime with the JIT compiled in and ON
#               by default (--no-jit / SL_JIT=0 turns it off).
#
# The .NET side needs NO extra flags - `dotnet publish -c <Cfg>` auto-selects
# AOT (Release), the host RID and the platform-qualified output dir
# package\<platform>-<config> (csproj, 2026-10-18). The Linux halves run inside
# WSL because Native AOT cannot cross-compile across OSes; there the same
# zero-flag publish lands in package\linux-<config>. lib\ and md\ are
# platform-independent and are copied from the same-config Windows package
# (built first automatically when needed).
#
# Usage (workspace root):
#   powershell -NoProfile -ExecutionPolicy Bypass -File SlangAllInOne\scripts\build-packages.ps1
#   ... -Packages win32-debug,linux-release     # subset (any of the four names)
#   ... -NoSmoke                                # skip the Std.module.slb smoke runs
param(
    [string[]]$Packages = @('win32-debug', 'win32-release', 'linux-debug', 'linux-release'),
    [switch]$NoSmoke
)

. (Join-Path $PSScriptRoot 'common.ps1')

# powershell -File passes "-Packages a,b,c" as ONE string; split on commas so
# both calling styles work ("-Packages a,b" and "-Packages a b").
$Packages = @($Packages | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })

function Write-Step([string]$Text) { Write-Host ''; Write-Host ('=== ' + $Text + ' ===') -ForegroundColor Cyan }
function Write-Ok([string]$Text)   { Write-Host ('  ' + $Text) -ForegroundColor Green }
function Fail([string]$Text)       { Write-Host ('FAIL: ' + $Text) -ForegroundColor Red; exit 1 }

# Run one bash command line inside WSL and return ONLY its exit code (int).
# Same contract as release-slang.ps1: stdout must NOT flow into the return
# value; the command must be a quote-free token stream.
function Invoke-WslBash([string]$Cmd) {
    & wsl bash -c $Cmd | Out-Host
    $code = $LASTEXITCODE
    if ($code -ne 0) {
        Start-Sleep -Seconds 2
        & wsl bash -c $Cmd | Out-Host
        $code = $LASTEXITCODE
    }
    return $code
}

$ProjFile = Join-Path $AllInOneDir 'SlangAllInOne.csproj'
$PkgRoot  = Join-Path $AllInOneDir 'package'
$Known    = @('win32-debug', 'win32-release', 'linux-debug', 'linux-release')

# ---------- plan ----------
$bad = @($Packages | Where-Object { $Known -notcontains $_ })
if ($bad.Count -gt 0) { Fail ('unknown package name(s): ' + ($bad -join ', ') + ' (known: ' + ($Known -join ', ') + ')') }

# linux-* needs the same-config win32 package as the lib\ + md\ source.
$autoAdded = @()
foreach ($p in @($Packages)) {
    if ($p -like 'linux-*') {
        $win = $p -replace '^linux-', 'win32-'
        if ($Packages -notcontains $win) { $Packages += $win; $autoAdded += $win }
    }
}
if ($autoAdded.Count -gt 0) {
    Write-Host ('  auto-added dependency package(s) for lib\ + md\: ' + ($autoAdded -join ', ')) -ForegroundColor Yellow
}
# Windows side first (linux packages consume its lib\ + md\).
$order = @{ 'win32-debug' = 1; 'win32-release' = 2; 'linux-debug' = 3; 'linux-release' = 4 }
$plan = @($Packages | Sort-Object { $order[$_] })
Write-Step ('Plan: ' + ($plan -join ', '))

# ---------- preflight ----------
if (-not (Test-Path $ProjFile)) { Fail "project not found: $ProjFile" }
if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) { Fail 'dotnet not found (.NET SDK 8+ required)' }
$needLinux = @($plan | Where-Object { $_ -like 'linux-*' }).Count -gt 0
if ($needLinux) {
    if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) { Fail 'wsl.exe not found - the linux packages need WSL (see RELEASE.md)' }
    if ((Invoke-WslBash 'true') -ne 0) { Fail 'WSL not usable (wsl bash -c true failed)' }
    if ((Invoke-WslBash 'which cmake clang ninja') -ne 0) { Fail 'WSL toolchain incomplete - install clang + cmake + ninja (+ libsqlite3-dev), see scripts\build-vm-linux.ps1 header' }
    if ((Invoke-WslBash 'dotnet --version') -ne 0) { Fail 'dotnet SDK missing inside WSL - install dotnet-sdk (see RELEASE.md)' }
}

# ---------- windows packages ----------
function Invoke-BuildWinPackage([string]$Config) {
    $dirName = 'win32-' + $Config.ToLowerInvariant()
    $dir = Join-Path $PkgRoot $dirName
    Write-Step ('Build ' + $dirName + '  (dotnet publish -c ' + $Config + ')')
    if (Test-Path $dir) { Remove-Item $dir -Recurse -Force -Confirm:$false }
    Push-Location $RepoRoot
    & dotnet publish $ProjFile -c $Config
    $code = $LASTEXITCODE
    Pop-Location
    if ($code -ne 0) { Write-Host ('  dotnet publish failed (exit ' + $code + ')') -ForegroundColor Red; return $false }

    # Layout check (csproj pack targets built bin\ + lib\ + md\ [+ plugins\]).
    # 2026-10-18 user directive: licenses\ no longer ships in any package;
    # lib\ = system built-in stdlib (renamed from module\). plugins\ keeps
    # holding relocated plugin frontend artifacts in Debug packages when any
    # remain — both runtime plugin frontends went native C on 2026-10-21
    # (nothing is published/relocated anymore, the must-list reflects that).
    $isDebug = ($Config -eq 'Debug')
    $must = @('slang.exe', 'bin\csimple_lang_dll.dll', 'bin\sqlite3.dll',
              'lib\Core.module.slb', 'lib\Math.module.slb', 'lib\Std.module.slb')
    if ($isDebug) { $must += @('slang.pdb', 'lib\Core.module.json', 'bin\csimple_lang_dll.pdb') }
    foreach ($m in $must) {
        if (-not (Test-Path (Join-Path $dir $m))) {
            Write-Host ('  package incomplete, missing: ' + $m) -ForegroundColor Red
            return $false
        }
    }
    if (-not (Test-Path (Join-Path $dir 'md'))) {
        Write-Host '  package incomplete, missing: md\' -ForegroundColor Red
        return $false
    }
    Write-Ok ('layout ok -> ' + $dir)

    if ($NoSmoke) { return $true }
    # Off-tree smoke: bundled stdlib loads and runs (temp cwd keeps build\logs out).
    $smokeDir = Join-Path $env:TEMP ('slang-pkg-smoke-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $smokeDir -Force | Out-Null
    Push-Location $smokeDir
    & (Join-Path $dir 'slang.exe') run (Join-Path $dir 'lib\Std.module.slb')
    $exit = $LASTEXITCODE
    Pop-Location
    Remove-Item $smokeDir -Recurse -Force -Confirm:$false -ErrorAction SilentlyContinue
    if ($exit -ne 0) { Write-Host ('  smoke Std.module.slb exit ' + $exit) -ForegroundColor Red; return $false }
    Write-Ok 'smoke: slang.exe run Std.module.slb exit 0'
    return $true
}

# ---------- linux packages ----------
function Invoke-BuildLinuxVm([string]$Config, [bool]$ReleaseHarden) {
    # Release: SLVM_HARDEN=ON + VM_JIT_ENABLE=ON (JIT compiled in, on by
    # default; the pin protects against older CMake caches holding OFF).
    # Debug: plain tree, no JIT (debuggable interpreter by design).
    $wslVm = ConvertTo-WslPath $VMDir
    $buildDir = 'build/' + $Config + 'Linux'
    $flags = ''
    if ($ReleaseHarden) { $flags = ' -DSLVM_HARDEN=ON -DVM_JIT_ENABLE=ON' }
    $cmd = 'cd ' + $wslVm + ' && cmake -S . -B ' + $buildDir +
           ' -G Ninja -DCMAKE_BUILD_TYPE=' + $Config +
           ' -DCMAKE_C_COMPILER=clang -DCMAKE_MAKE_PROGRAM=/usr/bin/ninja' +
           ' -DCMAKE_RUNTIME_OUTPUT_DIRECTORY=' + $wslVm + '/' + $buildDir + '/bin' + $flags +
           ' && cmake --build ' + $buildDir + ' --target csimple_lang_dll -j8'
    return ((Invoke-WslBash $cmd) -eq 0)
}

function Invoke-BuildLinuxPackage([string]$Config) {
    $dirName = 'linux-' + $Config.ToLowerInvariant()
    $dir = Join-Path $PkgRoot $dirName
    $wslPkg = ConvertTo-WslPath $dir
    $wslRepo = ConvertTo-WslPath $RepoRoot
    Write-Step ('Build ' + $dirName + '  (WSL: C VM .so + dotnet publish -c ' + $Config + ')')

    # a) Linux C VM runtime (.so lands in build\<C>Linux\, not bin\).
    Write-Host ('  building libcsimple_lang_dll.so (cmake ' + $Config + ')...')
    if (-not (Invoke-BuildLinuxVm $Config ($Config -eq 'Release'))) {
        Write-Host '  Linux C VM build failed (see log above)' -ForegroundColor Red
        return $false
    }
    Write-Ok 'libcsimple_lang_dll.so built'

    # b) .NET side. No flags needed: the csproj defaults the RID (linux host)
    #    and the output dir to package\linux-<config>; Windows-only pack
    #    targets are host-gated off inside WSL.
    if (Test-Path $dir) { Remove-Item $dir -Recurse -Force -Confirm:$false }
    $cmd = 'cd ' + $wslRepo + ' && dotnet publish SlangAllInOne/SlangAllInOne.csproj -c ' + $Config
    if ((Invoke-WslBash $cmd) -ne 0) { Write-Host '  dotnet publish (WSL) failed (see log above)' -ForegroundColor Red; return $false }
    Write-Ok ('slang (' + $dirName + ') published')

    # c) assemble bin\: the C VM .so + bundled system sqlite (CvmBackend
    #    pre-loads it so no LD_LIBRARY_PATH is needed).
    $cmd = 'mkdir -p ' + $wslPkg + '/bin && cp ' + (ConvertTo-WslPath $VMDir) + '/build/' + $Config + 'Linux/libcsimple_lang_dll.so ' + $wslPkg + '/bin/ && cp /usr/lib/x86_64-linux-gnu/libsqlite3.so.0 ' + $wslPkg + '/bin/'
    if ((Invoke-WslBash $cmd) -ne 0) { Write-Host '  linux bin assembly failed (libsqlite3.so.0 not found?)' -ForegroundColor Red; return $false }
    Write-Ok 'bin assembled (libcsimple_lang_dll.so + libsqlite3.so.0)'

    # d) lib\ + md\ are platform-independent - copy from the same-config
    #    Windows package (built earlier in the plan), drop the Windows-only
    #    math_lib.dll (documented Linux limitation, see RELEASE.md).
    $winDir = Join-Path $PkgRoot ('win32-' + $Config.ToLowerInvariant())
    robocopy (Join-Path $winDir 'lib') (Join-Path $dir 'lib') /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) { Write-Host '  robocopy lib\ (win -> linux package) failed' -ForegroundColor Red; return $false }
    robocopy (Join-Path $winDir 'md') (Join-Path $dir 'md') /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) { Write-Host '  robocopy md\ (win -> linux package) failed' -ForegroundColor Red; return $false }
    $mathLib = Join-Path $dir 'lib\math_lib.dll'
    if (Test-Path $mathLib) { Remove-Item $mathLib -Force -Confirm:$false }
    Write-Ok 'lib\ + md\ copied from the Windows package (math_lib.dll excluded)'

    # Layout check (licenses\ no longer ships - 2026-10-18 user directive).
    $must = @('slang', 'bin\libcsimple_lang_dll.so', 'bin\libsqlite3.so.0',
              'lib\Core.module.slb', 'lib\Math.module.slb', 'lib\Std.module.slb')
    if ($Config -eq 'Debug') { $must += @('slang.dll', 'lib\Core.module.json') }
    foreach ($m in $must) {
        if (-not (Test-Path (Join-Path $dir $m))) {
            Write-Host ('  package incomplete, missing: ' + $m) -ForegroundColor Red
            return $false
        }
    }
    Write-Ok ('layout ok -> ' + $dir)

    if ($NoSmoke) { return $true }
    # Off-tree smoke (temp cwd keeps build\logs out of the package tree).
    # DOTNET_ROLL_FORWARD=Major: the framework-dependent Debug package needs a
    # .NET 8 runtime, but the WSL distro only ships dotnet-sdk-10 (10.0.12) -
    # rolling forward onto 10.x is the officially supported way to run net8.0
    # apps there. Release packages are Native AOT and ignore the variable.
    $cmd = 'rm -rf /tmp/slang-pkg-smoke && mkdir -p /tmp/slang-pkg-smoke && cd /tmp/slang-pkg-smoke && DOTNET_ROLL_FORWARD=Major ' + $wslPkg + '/slang run ' + $wslPkg + '/lib/Std.module.slb --no-banner'
    if ((Invoke-WslBash $cmd) -ne 0) { Write-Host '  smoke Std.module.slb failed (see log above)' -ForegroundColor Red; return $false }
    Write-Ok 'smoke: slang run Std.module.slb exit 0'
    return $true
}

# ---------- run the plan ----------
$results = @()
foreach ($p in $plan) {
    $ok = $false
    if     ($p -eq 'win32-debug')   { $ok = Invoke-BuildWinPackage 'Debug' }
    elseif ($p -eq 'win32-release') { $ok = Invoke-BuildWinPackage 'Release' }
    elseif ($p -eq 'linux-debug')   { $ok = Invoke-BuildLinuxPackage 'Debug' }
    elseif ($p -eq 'linux-release') { $ok = Invoke-BuildLinuxPackage 'Release' }
    $results += [pscustomobject]@{ Package = $p; Path = (Join-Path $PkgRoot $p); Result = $(if ($ok) { 'OK' } else { 'FAIL' }) }
    if (-not $ok) { break }   # later steps consume earlier products - stop on first failure
}

Write-Step 'Summary'
$results | Format-Table -AutoSize | Out-Host
$failed = @($results | Where-Object { $_.Result -ne 'OK' })
if ($failed.Count -gt 0) { exit 1 }
Write-Ok ('all requested packages built under ' + $PkgRoot)
exit 0
