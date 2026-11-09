# build-hello-cube.ps1 - one-shot build of the SLang Unity C++ binding demo.
# ASCII only: PowerShell 5.1 -File reads BOM-less UTF-8 as the local ANSI codepage.
#
# Steps: MSVC cl.exe -> slang_unity.dll, slang compile -> HelloCube.module.slb,
# then deploy DLLs + SLB + standard library modules into the Unity Assets tree.

param(
    [string]$UnityAssets = 'C:\Users\Administrator\My project\Assets',
    [string]$SlangExe    = 'd:\project\lang\SlangAllInOne\package\win32-release\slang.exe',
    [string]$Vcvars      = 'C:\Program Files\Microsoft Visual Studio\18\Community\VC\Auxiliary\Build\vcvars64.bat',
    [string]$VmDll       = 'd:\project\lang\csimple_lang\build\Release\bin\csimple_lang_dll.dll',
    [switch]$SlOnly
)

$ErrorActionPreference = 'Stop'

$here       = Split-Path -Parent $MyInvocation.MyCommand.Path
$srcCpp     = Join-Path $here 'native\slang_unity.cpp'
$projectDir = Join-Path $here 'HelloCube'
$jsonc      = Join-Path $projectDir 'HelloCube.jsonc'
$exportRoot = 'd:\project\lang\SlangAllInOne\out\export'
$nativeOut  = Join-Path $exportRoot 'HelloCubeNative'
$objDir     = Join-Path $nativeOut 'obj'
$builtDll   = Join-Path $nativeOut 'slang_unity.dll'
$slbSrc     = Join-Path $exportRoot 'HelloCube\HelloCube.module.slb'
$slangLib   = Join-Path (Split-Path -Parent $SlangExe) 'lib'

$pluginDir  = Join-Path $UnityAssets 'Plugins\x86_64'
$slangDir   = Join-Path $UnityAssets 'StreamingAssets\Slang'
$slangLibOut= Join-Path $slangDir 'lib'

foreach ($d in @($nativeOut, $objDir, $pluginDir, $slangDir, $slangLibOut))
{
    if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
}

if (-not $SlOnly)
{
Write-Host '== [1/5] compile C++ native binding (slang_unity.dll) =='
if (-not (Test-Path -LiteralPath $Vcvars)) { throw "vcvars64.bat not found: $Vcvars" }
if (-not (Test-Path -LiteralPath $srcCpp)) { throw "source not found: $srcCpp" }

$clArgs = 'cl.exe /nologo /W3 /O2 /MD /EHsc /LD /D_CRT_SECURE_NO_WARNINGS /DWIN32 ' +
          ('/Fo:"' + $objDir + '\slang_unity.obj" ') +
          ('/Fd:"' + $objDir + '\slang_unity.pdb" ') +
          ('/Fe:"' + $builtDll + '" ') +
          ('"' + $srcCpp + '" ') +
          '/link /SECTION:.slushare,RWS'
$cmdLine = '"' + $Vcvars + '" && ' + $clArgs
& cmd.exe /c $cmdLine
if ($LASTEXITCODE -ne 0) { throw "MSVC compile failed (exit $LASTEXITCODE)" }
if (-not (Test-Path -LiteralPath $builtDll)) { throw "DLL not produced: $builtDll" }
Write-Host "    built: $builtDll"

Write-Host '== [2/5] deploy native DLLs into Assets/Plugins/x86_64 =='
Copy-Item -LiteralPath $builtDll -Destination (Join-Path $pluginDir 'slang_unity.dll') -Force
if (-not (Test-Path -LiteralPath $VmDll)) { throw "C VM dll not found: $VmDll" }
Copy-Item -LiteralPath $VmDll -Destination (Join-Path $pluginDir 'csimple_lang_dll.dll') -Force
$vmBin = Split-Path -Parent $VmDll
foreach ($extra in @('sqlite3.dll'))
{
    $p = Join-Path $vmBin $extra
    if (Test-Path -LiteralPath $p) { Copy-Item -LiteralPath $p -Destination (Join-Path $pluginDir $extra) -Force }
}
Write-Host "    plugin dir: $pluginDir"
}
else
{
    Write-Host '== [1-2/5] skipped (-SlOnly): native DLLs already loaded by Unity =='
}

Write-Host '== [3/5] compile SL project (binary+json) =='
if (-not (Test-Path -LiteralPath $SlangExe)) { throw "slang.exe not found: $SlangExe" }
$before = (Get-Date).ToUniversalTime().AddSeconds(-2)
& $SlangExe compile $projectDir --format binary+json --no-banner
if (-not (Test-Path -LiteralPath $slbSrc)) { throw "SLB not produced: $slbSrc" }
$slb = Get-Item -LiteralPath $slbSrc
if ($slb.LastWriteTimeUtc -lt $before) { throw "SLB was not rewritten (Front compile failed); check Logs/Front.txt" }
Write-Host "    built: $slbSrc ($($slb.Length) bytes)"

Write-Host '== [4/5] deploy SLB + standard library modules =='
Copy-Item -LiteralPath $slbSrc -Destination (Join-Path $slangDir 'HelloCube.module.slb') -Force
$jsonSrc = Join-Path $exportRoot 'HelloCube\HelloCube.module.json'
if (Test-Path -LiteralPath $jsonSrc)
{
    Copy-Item -LiteralPath $jsonSrc -Destination (Join-Path $slangDir 'HelloCube.module.json') -Force
}
foreach ($m in @('Core', 'Std'))
{
    $p = Join-Path $slangLib ($m + '.module.slb')
    if (-not (Test-Path -LiteralPath $p)) { throw "standard library module not found: $p" }
    Copy-Item -LiteralPath $p -Destination (Join-Path $slangLibOut ($m + '.module.slb')) -Force
}
Write-Host "    slb dir: $slangDir"

Write-Host '== [5/5] summary =='
Write-Host "    C++ binding : $(Join-Path $pluginDir 'slang_unity.dll')"
Write-Host "    C VM        : $(Join-Path $pluginDir 'csimple_lang_dll.dll')"
Write-Host "    SL module   : $(Join-Path $slangDir 'HelloCube.module.slb')"
Write-Host 'OK. Run verify-hello-cube.ps1 for the native end-to-end smoke test.'
