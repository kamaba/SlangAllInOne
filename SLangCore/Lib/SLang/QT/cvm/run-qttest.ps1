# Lib/SLang/QT/cvm/run-qttest.ps1 - run the QTTest smoke with the REAL Qt6 backend.
# Prereqs (one-time):
#   1) Qt6 SDK on disk (default C:\Qt\6.8.1\msvc2022_64, aqtinstall layout)
#   2) build the Qt backend:  powershell -File build-slqt.ps1 -Qt
#   3) stage the test once:   dotnet run --project SlangAllInOne\Project\CSimpleVMTest
#                                -- <repo>\SlangAllInOne\SLangCore\test\Other\QTTest\QTTest
# The Qt window opens on YOUR desktop; closing it ends the run and flushes
# the smoke output (PASS line) into this console.
# Usage: powershell -ExecutionPolicy Bypass -File run-qttest.ps1
# NOTE: keep comments pure ASCII - PS 5.1 -File reads BOM-less UTF-8 as GBK.

$ErrorActionPreference = 'Stop'
$here  = Split-Path -Parent $MyInvocation.MyCommand.Path   # Lib/SLang/QT/cvm
$qtRoot = Split-Path -Parent $here                          # Lib/SLang/QT
$repo  = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $here)))))  # <repo root>

$qtBackendDll = Join-Path $here "x64\QtRelease\slang_qt.dll"
if (-not (Test-Path $qtBackendDll)) {
    throw "Qt backend not built: $qtBackendDll missing - run: powershell -File build-slqt.ps1 -Qt"
}

$qtBin = "C:\Qt\6.8.1\msvc2022_64\bin"
if (-not (Test-Path $qtBin)) { throw "Qt runtime dir not found: $qtBin" }
# Qt6 运行库同位部署（2026-11-02）：cvm FFI 装载用 LOAD_WITH_ALTERED_SEARCH_PATH，
# 被装载 dll 的依赖从其自身目录解析；平台插件由 slang_qt 后端按自身目录自适应
# 注入 -platformpluginpath —— 不再需要 PATH / QT_QPA_PLATFORM_PLUGIN_PATH 环境注入。
# 三件套 + qwindows.dll 随包铺进槽位，运行环境完全自洽。

# sync the Qt-backend dll into the spm modules slot (QTTest project, publish
# step 8 carries it) and the staged package slot (vmDlls re-stages the STUB on
# every module recompile - the Qt dll must be re-applied before each real run)
$pkg = Join-Path $repo "SlangAllInOne\package\win32-debug"
$modSlot = Join-Path $repo "SlangAllInOne\SLangCore\test\Other\QTTest\modules\SLangQT"
Copy-Item $qtBackendDll (Join-Path $modSlot "slang_qt.dll") -Force
Copy-Item $qtBackendDll (Join-Path $pkg "SLangQT\slang_qt.dll") -Force
foreach ($slot in @($modSlot, (Join-Path $pkg "SLangQT"))) {
    foreach ($qtDll in @("Qt6Core.dll", "Qt6Gui.dll", "Qt6Widgets.dll")) {
        Copy-Item (Join-Path $qtBin $qtDll) (Join-Path $slot $qtDll) -Force
    }
    $platDir = Join-Path $slot "plugins\platforms"
    New-Item -ItemType Directory -Path $platDir -Force | Out-Null
    Copy-Item (Join-Path $qtBin "..\plugins\platforms\qwindows.dll") $platDir -Force
}

$slb = Join-Path $pkg "QTTest\QTTest.module.slb"
if (-not (Test-Path $slb)) { throw "staged smoke not found: $slb - run the CSimpleVMTest host once (step 3 above)" }

Write-Host "running QTTest with the REAL Qt6 backend (close the window to finish)..."
& (Join-Path $pkg "slang.exe") run $slb
Write-Host ("slang.exe exit code: " + $LASTEXITCODE)
