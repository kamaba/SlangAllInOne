# Lib/SLang/QT/cvm/run-qttest.ps1 - run the QTTest suite with the REAL Qt6 backend.
# Prereqs (one-time):
#   1) Qt6 SDK on disk (default C:\Qt\6.8.1\msvc2022_64, aqtinstall layout)
#   2) build the Qt backend:  powershell -ExecutionPolicy Bypass -File build-slqt.ps1 -Qt
#   3) stage the test once:   dotnet run --project SlangAllInOne\Project\CSimpleVMTest
#                                -- <repo>\SlangAllInOne\SLangCore\test\Other\QTTest\QTTest
# Usage:
#   powershell -ExecutionPolicy Bypass -File run-qttest.ps1 [-Combo full|gui|data|minimal] [-Offscreen]
# The script deploys the requested Qt runtime combo into the package slot via
# deploy-qt.ps1 (own-directory runtime + qt.conf; no system Qt reference), then
# runs the staged QTTest slb with the package slang.exe.
#   -Offscreen : run Qt with the offscreen platform plugin (headless - no
#                window; animation counters still validate the move effect).
#                Default = real window on your desktop (auto-quits after ~1.6s).
# NOTE: keep comments pure ASCII - PS 5.1 -File reads BOM-less UTF-8 as GBK.

param(
    [ValidateSet("minimal","gui","data","full")]
    [string]$Combo = "full",
    [string]$Qt6Dir = "C:\Qt\6.8.1\msvc2022_64",
    [switch]$Offscreen
)
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path   # Lib/SLang/QT/cvm

# deploy the combo into the package slot (also syncs the Qt-backend dll from
# cvm\x64\QtRelease - vmDlls re-stages the STUB on every module recompile)
& (Join-Path $here "deploy-qt.ps1") -Combo $Combo -Targets @("package") -Qt6Dir $Qt6Dir
if ($LASTEXITCODE -ne 0 -and $null -ne $LASTEXITCODE) { throw "deploy-qt.ps1 failed" }

$repo = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $here)))))
$slb = Join-Path $repo "SlangAllInOne\package\win32-debug\QTTest\QTTest.module.slb"
if (-not (Test-Path $slb)) {
    throw "staged smoke not found: $slb - run the CSimpleVMTest host once (prereq step 3)"
}

$plat = "windows (real window)"
if ($Offscreen) {
    $env:QT_QPA_PLATFORM = "offscreen"
    $plat = "offscreen (headless)"
}
else {
    Remove-Item Env:QT_QPA_PLATFORM -ErrorAction SilentlyContinue
}

Write-Host "running QTTest (combo=$Combo, platform=$plat)..."
& (Join-Path $repo "SlangAllInOne\package\win32-debug\slang.exe") run $slb
Write-Host ("slang.exe exit code: " + $LASTEXITCODE)
