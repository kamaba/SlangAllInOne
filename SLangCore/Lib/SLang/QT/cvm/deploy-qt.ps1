# Lib/SLang/QT/cvm/deploy-qt.ps1 - combo-based Qt runtime deployment (2026-11-03)
#
# Copies Qt module DLLs + plugin CATEGORIES from the Qt SDK into OUR OWN
# runtime slots (same-dir placement beside slang_qt.dll), so the app never
# references the system Qt install. Release/publish MUST do the same via the
# jsonc "qtRuntime" section (PublishCommand Step 8b, missing pieces = FAIL);
# this script is the dev/staging equivalent with named combos for quick
# experimentation (swap combos, watch QTTest panel matrix + move effect).
#
# Combos (cumulative):
#   minimal : Core/Gui/Widgets + platforms(qwindows/qoffscreen/qminimal) + styles
#   gui     : minimal + Svg/SvgWidgets + imageformats + iconengines
#   data    : gui + Network/Sql/Xml/Concurrent + sqldrivers/networkinformation/tls
#   full    : data + OpenGL/OpenGLWidgets/PrintSupport/Test/UiTools/Help/DBus/
#             Designer + generic plugin + opengl32sw.dll
#
# Targets:
#   modules : <QTTest>\modules\SLangQT                (project spm slot; publish carries it)
#   package : <repo>\SlangAllInOne\package\win32-debug\modules\SLangQT (+ qt.conf beside slang.exe)
#             (aligned with StageReferencedModules: CVM fallback root 2 spm layout
#              <exe>\modules\<name>\<name>.module.json)
#   publish : <QTTest>\publish\release\modules\SLangQT (+ qt.conf beside QTTest.exe)
#
# The script CLEANS previously deployed Qt files in each target first
# (Qt6*.dll / opengl32sw.dll / d3dcompiler_47.dll / plugins\), so switching
# combos gives a true minimal set (no stale leftovers).
#
# It also syncs the Qt-backend slang_qt.dll from cvm\x64\QtRelease when
# present (vmDlls re-stages the STUB on every module recompile; the real
# backend must be re-applied before each real run).
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File deploy-qt.ps1 -Combo full
#   powershell -ExecutionPolicy Bypass -File deploy-qt.ps1 -Combo minimal -Targets modules
#   powershell -ExecutionPolicy Bypass -File deploy-qt.ps1 -Combo data -Targets modules,package,publish
# NOTE: keep comments pure ASCII - PS 5.1 -File reads BOM-less UTF-8 as GBK
# and mojibake in comments can swallow quotes and break parsing.

param(
    [ValidateSet("minimal","gui","data","full")]
    [string]$Combo = "full",
    [string]$Qt6Dir = "C:\Qt\6.8.1\msvc2022_64",
    [string[]]$Targets = @("modules","package"),
    [string]$SlangQtDll = ""
)
$ErrorActionPreference = "Stop"
$here    = Split-Path -Parent $MyInvocation.MyCommand.Path   # Lib/SLang/QT/cvm
$repo    = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $here)))))  # <repo root>
$testDir = Join-Path $repo "SlangAllInOne\SLangCore\test\Other\QTTest"

if (-not (Test-Path (Join-Path $Qt6Dir "bin\Qt6Core.dll"))) {
    throw "Qt SDK not found: $Qt6Dir (pass -Qt6Dir <sdk root containing bin\ + plugins\>)"
}
$qtBin     = Join-Path $Qt6Dir "bin"
$qtPlugins = Join-Path $Qt6Dir "plugins"

# --- combo tables ------------------------------------------------------------
$basePlugins = @{
    platforms = @("qwindows","qoffscreen","qminimal")
    styles    = @("qmodernwindowsstyle")
}
$comboModules = @{
    minimal = @()
    gui     = @("Svg","SvgWidgets")
    data    = @("Svg","SvgWidgets","Network","Sql","Xml","Concurrent")
    full    = @("Svg","SvgWidgets","Network","Sql","Xml","Concurrent",
                "OpenGL","OpenGLWidgets","PrintSupport","Test","UiTools","Help","DBus","Designer")
}
$comboPlugins = @{
    minimal = $basePlugins
    gui     = @{ platforms=$basePlugins.platforms; styles=$basePlugins.styles
                 imageformats=@("qgif","qico","qjpeg","qsvg"); iconengines=@("qsvgicon") }
    data    = @{ platforms=$basePlugins.platforms; styles=$basePlugins.styles
                 imageformats=@("qgif","qico","qjpeg","qsvg"); iconengines=@("qsvgicon")
                 sqldrivers=@("qsqlite"); networkinformation=@("qnetworklistmanager")
                 tls=@("qschannelbackend","qcertonlybackend") }
    full    = @{ platforms=$basePlugins.platforms; styles=$basePlugins.styles
                 imageformats=@("qgif","qico","qjpeg","qsvg"); iconengines=@("qsvgicon")
                 sqldrivers=@("qsqlite"); networkinformation=@("qnetworklistmanager")
                 tls=@("qschannelbackend","qcertonlybackend"); generic=@("qtuiotouchplugin") }
}
$comboExtras = @{
    minimal = @()
    gui     = @()
    data    = @()
    full    = @("opengl32sw.dll")
}

$modules = @("Core","Gui","Widgets") + $comboModules[$Combo]
$plugins = $comboPlugins[$Combo]
$extras  = $comboExtras[$Combo]

# --- Qt-backend slang_qt.dll (optional sync; build with build-slqt.ps1 -Qt) --
if ($SlangQtDll -eq "") { $SlangQtDll = Join-Path $here "x64\QtRelease\slang_qt.dll" }
$hasBackendDll = Test-Path $SlangQtDll

# --- helpers -----------------------------------------------------------------
function Clean-QtFiles([string]$dir) {
    if (-not (Test-Path $dir)) { return }
    Get-ChildItem $dir -Filter "Qt6*.dll" -File -ErrorAction SilentlyContinue |
        Remove-Item -Force
    foreach ($x in @("opengl32sw.dll","d3dcompiler_47.dll")) {
        $p = Join-Path $dir $x
        if (Test-Path $p) { Remove-Item $p -Force }
    }
    $pdir = Join-Path $dir "plugins"
    if (Test-Path $pdir) { Remove-Item $pdir -Recurse -Force }
}

function Write-QtConf([string]$exeDir, [string]$pluginsEntry) {
    New-Item -ItemType Directory -Force -Path $exeDir | Out-Null
    $conf = Join-Path $exeDir "qt.conf"
    # qt.conf beside the exe: redirects the plugin search tree AND suppresses
    # the compile-time baked-in SDK prefix (no reference to the system install).
    "[Paths]`r`nPlugins = $pluginsEntry`r`n" | Out-File -FilePath $conf -Encoding ascii -NoNewline
    Write-Host "  qt.conf -> $conf (Plugins = $pluginsEntry)"
}

# --- slot map ----------------------------------------------------------------
$pkgRoot  = Join-Path $repo "SlangAllInOne\package\win32-debug"
$pubRoot  = Join-Path $testDir "publish\release"
$slotMap = @{
    modules = @{ dir = Join-Path $testDir "modules\SLangQT"; conf = ""; entry = "" }
    package = @{ dir = Join-Path $pkgRoot "modules\SLangQT"; conf = $pkgRoot; entry = "modules/SLangQT/plugins" }
    publish = @{ dir = Join-Path $pubRoot "modules\SLangQT"; conf = $pubRoot; entry = "modules/SLangQT/plugins" }
}

# --- deploy ------------------------------------------------------------------
$totalDlls = 0
foreach ($t in $Targets) {
    if (-not $slotMap.ContainsKey($t)) {
        throw "unknown target '$t' (expected modules|package|publish)"
    }
    $slot = $slotMap[$t]
    $dir = $slot.dir
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    Clean-QtFiles $dir

    foreach ($m in $modules) {
        $src = Join-Path $qtBin "Qt6$m.dll"
        if (-not (Test-Path $src)) { throw "missing Qt module dll: $src" }
        Copy-Item $src $dir -Force
    }
    foreach ($cat in $plugins.Keys) {
        $dstCat = Join-Path $dir "plugins\$cat"
        New-Item -ItemType Directory -Force -Path $dstCat | Out-Null
        foreach ($p in $plugins[$cat]) {
            $src = Join-Path $qtPlugins "$cat\$p.dll"
            if (-not (Test-Path $src)) { throw "missing Qt plugin dll: $src" }
            Copy-Item $src $dstCat -Force
        }
    }
    foreach ($x in $extras) {
        $src = Join-Path $qtBin $x
        if (Test-Path $src) { Copy-Item $src $dir -Force }
        else { Write-Host "  warn: extra dll missing: $src" }
    }
    if ($hasBackendDll) {
        Copy-Item $SlangQtDll (Join-Path $dir "slang_qt.dll") -Force
    }
    else {
        Write-Host "  warn: Qt-backend slang_qt.dll not found ($SlangQtDll) - run build-slqt.ps1 -Qt first"
    }
    if ($slot.conf -ne "") { Write-QtConf $slot.conf $slot.entry }

    $n = (Get-ChildItem $dir -Recurse -Filter *.dll | Measure-Object).Count
    $totalDlls += $n
    Write-Host "[OK] combo=$Combo target=$t -> $dir ($n dlls)"
}

Write-Host "deploy-qt done (combo=$Combo, targets=$($Targets -join ','), dlls=$totalDlls)."
