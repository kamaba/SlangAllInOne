# build-unity-package.ps1 - build and install the com.slang.unity UPM package.
# ASCII only: PowerShell 5.1 -File reads BOM-less UTF-8 as the local ANSI codepage.
#
# v2 layout: the package lives in <UnityProject>/Packages/com.slang.unity.
# Native DLLs live in the package; SLB data is installed into StreamingAssets.
# Use -SlOnly while Unity is running (native DLLs are locked by the Editor).

param(
    [string]$UnityProject = 'C:\Users\Administrator\My project',
    [string]$SlangExe     = 'd:\project\lang\SlangAllInOne\package\win32-release\slang.exe',
    [string]$VmDll        = 'd:\project\lang\csimple_lang\build\Release\bin\csimple_lang_dll.dll',
    [string]$VmExe        = 'd:\project\lang\SlangAllInOne\package\win32-release\bin\csimple_lang.exe',
    [switch]$SlOnly
)

$ErrorActionPreference = 'Stop'

$here      = Split-Path -Parent $MyInvocation.MyCommand.Path
$pkgSrc    = Join-Path $here 'package\com.slang.unity'
$projectSl = Join-Path $here 'HelloCube'
$exportRoot= 'd:\project\lang\SlangAllInOne\out\export'
$nativeOut = Join-Path $exportRoot 'HelloCubeNative'
$builtDll  = Join-Path $nativeOut 'slang_unity_native.dll'
$pkgDllName= 'slang_unity_native3.dll'
$slbSrc    = Join-Path $exportRoot 'HelloCube\HelloCube.module.slb'
$slangLib  = Join-Path (Split-Path -Parent $SlangExe) 'lib'
$sllibSrc  = Join-Path $projectSl 'sllib'

$pkgDst    = Join-Path $UnityProject 'Packages\com.slang.unity'
$pluginDst = Join-Path $pkgDst 'Plugins\x86_64'
$sampleDst = Join-Path $pkgDst 'Samples~\HelloCube'
$sampleLib = Join-Path $sampleDst 'lib'
$sllibDst  = Join-Path $sampleDst 'sllib'
$streamDst = Join-Path $UnityProject 'Assets\StreamingAssets\Slang'
$streamLib = Join-Path $streamDst 'lib'
$streamSllib = Join-Path $streamDst 'sllib'
$pluginLib  = Join-Path $pluginDst 'lib'

foreach ($d in @($pkgDst, $pluginDst, $pluginLib, $sampleDst, $sampleLib, $sllibDst, $streamDst, $streamLib, $streamSllib))
{
    if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
}

Write-Host '== [1/6] compile C++ plugin (Unity Native Plugin API) =='
if (-not $SlOnly)
{
    $bat = Join-Path $here 'native\build-native.cmd'
    & cmd.exe /c $bat $nativeOut
    if ($LASTEXITCODE -ne 0) { throw "native build failed (exit $LASTEXITCODE)" }
}
if (-not (Test-Path -LiteralPath $builtDll)) { throw "native DLL not found: $builtDll" }
Write-Host "    built: $builtDll"

Write-Host '== [2/6] compile SL project (binary+json) =='
$before = (Get-Date).ToUniversalTime().AddSeconds(-2)
& $SlangExe compile $projectSl --format binary+json --no-banner
if (-not (Test-Path -LiteralPath $slbSrc)) { throw "SLB not produced: $slbSrc" }
$slb = Get-Item -LiteralPath $slbSrc
if ($slb.LastWriteTimeUtc -lt $before) { throw "SLB was not rewritten (Front compile failed); check Logs/Front.txt" }
Write-Host "    built: $slbSrc ($($slb.Length) bytes)"

Write-Host '== [3/6] sync package sources =='
& robocopy $pkgSrc $pkgDst /E /NFL /NDL /NJH /NJS /NP | Out-Null
if ($LASTEXITCODE -ge 8) { throw "robocopy failed (exit $LASTEXITCODE)" }
Write-Host "    package: $pkgDst"

Write-Host '== [4/6] deploy native DLLs into the package =='
function Deploy-Native([string]$src, [string]$dst)
{
    if (-not (Test-Path -LiteralPath $src)) { return }
    try
    {
        Copy-Item -LiteralPath $src -Destination $dst -Force -ErrorAction Stop
    }
    catch
    {
        if (Test-Path -LiteralPath $dst)
        {
            Write-Host "    WARNING: locked by Unity, kept existing: $dst"
        }
        else
        {
            throw
        }
    }
}
if (-not $SlOnly)
{
    if (-not (Test-Path -LiteralPath $VmDll)) { throw "C VM DLL not found: $VmDll" }
    Deploy-Native $builtDll (Join-Path $pluginDst $pkgDllName)
    Deploy-Native $VmDll (Join-Path $pluginDst 'csimple_lang_dll.dll')
    if (-not (Test-Path -LiteralPath $VmExe)) { throw "C VM CLI not found: $VmExe" }
    Deploy-Native $VmExe (Join-Path $pluginDst 'csimple_lang.exe')
    $vmBin = Split-Path -Parent $VmDll
    Deploy-Native (Join-Path $vmBin 'sqlite3.dll') (Join-Path $pluginDst 'sqlite3.dll')
}
Write-Host "    plugins: $pluginDst ($pkgDllName)"

Write-Host '== [5/6] assemble Samples~ and install runtime data =='
foreach ($f in @('HelloCube.sl', 'HelloCube.sp', 'HelloCube.jsonc'))
{
    Copy-Item -LiteralPath (Join-Path $projectSl $f) -Destination (Join-Path $sampleDst $f) -Force
}
Copy-Item -LiteralPath $slbSrc -Destination (Join-Path $sampleDst 'HelloCube.module.slb') -Force
$jsonSrc = Join-Path $exportRoot 'HelloCube\HelloCube.module.json'
if (Test-Path -LiteralPath $jsonSrc)
{
    Copy-Item -LiteralPath $jsonSrc -Destination (Join-Path $sampleDst 'HelloCube.module.json') -Force
}
foreach ($slFile in (Get-ChildItem -LiteralPath $sllibSrc -Filter '*.sl' -File))
{
    Copy-Item -LiteralPath $slFile.FullName -Destination (Join-Path $sllibDst $slFile.Name) -Force
    Copy-Item -LiteralPath $slFile.FullName -Destination (Join-Path $streamSllib $slFile.Name) -Force
}
foreach ($m in @('Core', 'Std'))
{
    $p = Join-Path $slangLib ($m + '.module.slb')
    if (-not (Test-Path -LiteralPath $p)) { throw "standard library module not found: $p" }
    Copy-Item -LiteralPath $p -Destination (Join-Path $sampleLib ($m + '.module.slb')) -Force
    Copy-Item -LiteralPath $p -Destination (Join-Path $streamLib ($m + '.module.slb')) -Force
    # The SLB's moduleReferences are relative to the Front export dir, so they
    # cannot resolve from StreamingAssets. The C VM CLI falls back to
    # <exe>/lib/<name>.module.slb; keep the standard modules next to the CLI.
    Copy-Item -LiteralPath $p -Destination (Join-Path $pluginLib ($m + '.module.slb')) -Force
}
foreach ($f in @('HelloCube.module.slb', 'HelloCube.module.json', 'HelloCube.sl', 'HelloCube.sp', 'HelloCube.jsonc'))
{
    $p = Join-Path $sampleDst $f
    if (Test-Path -LiteralPath $p) { Copy-Item -LiteralPath $p -Destination (Join-Path $streamDst $f) -Force }
}
Write-Host "    sample : $sampleDst (incl. sllib/)"
Write-Host "    runtime: $streamDst"

Write-Host '== [6/6] remove v1 Assets-level leftovers =='
$legacy = @((Join-Path $UnityProject 'Assets\SlangUnity'),
            (Join-Path $UnityProject 'Assets\Plugins\x86_64'))
foreach ($p in $legacy)
{
    if (Test-Path -LiteralPath $p)
    {
        Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath $p)
        {
            Write-Host "    WARNING: still present (Unity may hold locked DLLs): $p"
        }
        else
        {
            Write-Host "    removed: $p"
        }
    }
}

Write-Host '== summary =='
Write-Host "    UPM package : $pkgDst"
Write-Host "    native DLL  : $(Join-Path $pluginDst $pkgDllName)"
Write-Host "    SLB data    : $(Join-Path $streamDst 'HelloCube.module.slb')"
Write-Host 'OK. In Unity: Tools > SlangUnity > Enter Play Mode.'
