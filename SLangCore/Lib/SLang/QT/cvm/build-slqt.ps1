# Lib/SLang/QT/cvm/build-slqt.ps1 - one-click build for the SLangQT module
# (Lib/SLang/QT, stdlib-style module - NOT a plugin since 2026-11-02).
#   1) native DLL (stub backend by default; -Qt switches to the real Qt6 backend)
#      -> intermediate copy in cvm\obj\slang_qt.dll
#   2) SL module (Front compile <QT>\QT.sp, R15 format binary+json)
#      -> <repo>\SlangAllInOne\out\export\SLangQT\SLangQT.module.slb
#      (QT.jsonc vmDlls also msbuilds the stub vcxproj and copies the DLL there)
#   3) deploy: copy the step-1 DLL next to the module product (pkg_dir flat slot,
#      the FFI static-lib preload candidate).
# Consumers reference the module product directly (ServerTest/MysqlTest form):
#   { "path": "<...>\out\export\SLangQT\SLangQT.module.json" }
# Usage: powershell -ExecutionPolicy Bypass -File build-slqt.ps1 [-Qt] [-Qt6Dir <dir>]
# Deps: MSVC x64 cl.exe + dotnet SDK. -Qt additionally needs Qt6 (widgets/gui/core).
# NOTE: keep comments pure ASCII - PS 5.1 -File reads BOM-less UTF-8 as GBK
# and mojibake in comments can swallow quotes and break parsing.

param(
    [switch]$Qt,
    [string]$Qt6Dir = "C:\Qt\6.8.1\msvc2022_64"
)
$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path   # Lib/SLang/QT/cvm
$qtRoot = Split-Path -Parent $here                         # Lib/SLang/QT (NOT $qt: collides with [switch]$Qt)
$repo = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $here)))))  # <repo root>
$src  = Join-Path $here "src\slang_qt"

# --- 1) locate the MSVC x64 environment (reuse cl from PATH when present) ---
if (-not (Get-Command cl.exe -ErrorAction SilentlyContinue)) {
    $vsRoot = "C:\Program Files\Microsoft Visual Studio\18\Community\VC\Tools\MSVC"
    $msvc = Get-ChildItem $vsRoot -Directory -ErrorAction SilentlyContinue |
            Sort-Object Name -Descending | Select-Object -First 1
    if ($null -eq $msvc) { throw "no cl.exe on PATH and MSVC not found ($vsRoot) - enter an MSVC x64 env first" }

    $sdkInc = "C:\Program Files (x86)\Windows Kits\10\Include"
    $sdk = Get-ChildItem $sdkInc -Directory -ErrorAction SilentlyContinue |
           Sort-Object Name -Descending | Select-Object -First 1
    if ($null -eq $sdk) { throw "Windows SDK not found ($sdkInc)" }

    $msvcRoot = $msvc.FullName
    $sdkVer   = $sdk.Name
    $sdkRoot  = "C:\Program Files (x86)\Windows Kits\10"
    $env:PATH = "$sdkRoot\bin\$sdkVer\x64;$msvcRoot\bin\Hostx64\x64;" + $env:PATH
    $env:INCLUDE = "$msvcRoot\include;$sdkRoot\Include\$sdkVer\ucrt;$sdkRoot\Include\$sdkVer\um;$sdkRoot\Include\$sdkVer\shared;$sdkRoot\Include\$sdkVer\cppwinrt"
    $env:LIB = "$msvcRoot\lib\x64;$sdkRoot\Lib\$sdkVer\ucrt\x64;$sdkRoot\Lib\$sdkVer\um\x64"
    Write-Host "using MSVC $($msvc.Name) + SDK $sdkVer"
}

# --- 2) build the native DLL into the local intermediate slot ---
$objDir = Join-Path $here "obj"
New-Item -ItemType Directory -Force -Path $objDir | Out-Null
$dll = Join-Path $objDir "slang_qt.dll"

if ($Qt) {
    # Real Qt6 backend: msbuild the Qt vcxproj (Qt6_DIR resolves moc-less C++ glue).
    $msbuild = Get-Command msbuild.exe -ErrorAction SilentlyContinue
    if ($null -eq $msbuild) {
        # fall back to the VS-bundled MSBuild (same VS root probing as cl above)
        $vsMb = "C:\Program Files\Microsoft Visual Studio\18\Community\MSBuild\Current\Bin\MSBuild.exe"
        if (Test-Path $vsMb) { $msbuild = @{ Source = $vsMb } }
    }
    if ($null -eq $msbuild) { throw "msbuild not found (PATH and VS 18 Community probing failed)" }
    & $msbuild.Source (Join-Path $here "slang_qt_qt.vcxproj") /nologo /v:m /p:Configuration=Release /p:Platform=x64 /p:Qt6_DIR="$Qt6Dir"
    if ($LASTEXITCODE -ne 0) { throw "msbuild slang_qt_qt failed (exit $LASTEXITCODE)" }
    Copy-Item (Join-Path $here "x64\QtRelease\slang_qt.dll") $dll -Force
    Write-Host "SLangQT native built (Qt6 backend, Qt6_DIR=$Qt6Dir) -> $dll"
}
else {
    # STUB backend: plain C, no Qt dependency - validates the full SL chain headless.
    $cflags = @("/nologo", "/W3", "/O2", "/LD", "/utf-8", "/I$src", "/Fo$objDir\", "/Fe$dll")
    & cl @cflags (Join-Path $src "slang_qt.c") (Join-Path $src "slang_qt_stub.c")
    if ($LASTEXITCODE -ne 0) { throw "cl build failed (exit $LASTEXITCODE)" }
    Write-Host "SLangQT native built (STUB backend) -> $dll"
}

# --- 3) compile the SLangQT module (R15: binary+json) ---
$front = Join-Path $repo "simple_language\source\SimpleLanguageFront.csproj"
& dotnet run --project $front -- compile -p (Join-Path $qtRoot "QT.sp") -e ir --format binary+json
if ($LASTEXITCODE -ne 0) { Write-Host "warning: Front compile exit $LASTEXITCODE (Front errors are in the log above)" }

# --- 4) deploy: DLL next to the module product (FFI pkg_dir flat candidate) ---
$exportDir = Join-Path $repo "SlangAllInOne\out\export\SLangQT"
if (Test-Path $exportDir) {
    Copy-Item $dll (Join-Path $exportDir "slang_qt.dll") -Force
    Write-Host "deployed slang_qt.dll -> $exportDir"
}
else {
    Write-Host "warning: module export dir missing ($exportDir) - Front compile did not export?"
}

# --- 5) pack the module into the consumer project modules\ slot (spm layout) ---
# modules\SLangQT\{SLangQT.module.slb|json + slang_qt.dll} - the QTTest project
# references ./modules/SLangQT (package-layout section 2.6 form); publish step 8
# carries the whole dir into the app package.
$exportRoot = Join-Path $repo "SlangAllInOne\out\export\SLangQT"
$testModules = Join-Path $repo "SlangAllInOne\SLangCore\test\Other\QTTest\modules\SLangQT"
if ((Test-Path $exportRoot) -and (Test-Path (Split-Path -Parent $testModules))) {
    New-Item -ItemType Directory -Force -Path $testModules | Out-Null
    Copy-Item (Join-Path $exportRoot "SLangQT.module.slb") $testModules -Force
    Copy-Item (Join-Path $exportRoot "SLangQT.module.json") $testModules -Force
    Copy-Item $dll (Join-Path $testModules "slang_qt.dll") -Force
    Write-Host "packed SLangQT module -> $testModules (slb + json + dll, spm layout)"
}
else {
    Write-Host "warning: skip pack (exportRoot=$exportRoot)"
}

Write-Host "SLangQT module build done."
