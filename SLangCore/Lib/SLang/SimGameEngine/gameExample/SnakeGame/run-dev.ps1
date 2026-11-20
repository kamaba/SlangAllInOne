# SnakeGame dev-run helper.
# 2026-11-18 fix: dev-run flashed-and-exited (or crashed 0xC0000409) because
# the slang_qt.dll staged in out\export\SnakeGame was a STALE build (old hash
# vs out\export\SLangQT). The publish path was fine (stages from the export
# slot); only the dev slot was stale. Re-copy the fresh dll from the export
# slot, then this script runs the game via slang run (dev slb, debug-enabled).
# It also prepends the module dir to PATH as defense for Qt6 loader search.
# Usage:
#   powershell -File run-dev.ps1              # real window
#   powershell -File run-dev.ps1 -Offscreen   # QT_QPA_PLATFORM=offscreen
#   powershell -File run-dev.ps1 -Debug       # slang run --debug-server
param(
    [switch]$Offscreen,
    [switch]$Debug
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$modDir = [System.IO.Path]::GetFullPath((Join-Path $root '..\..\..\..\..\..\out\export\SnakeGame'))
$slang = [System.IO.Path]::GetFullPath((Join-Path $modDir '..\..\cli-release\slang.exe'))
if (-not (Test-Path -LiteralPath (Join-Path $modDir 'SnakeGame.module.slb'))) {
    Write-Host "[run-dev] module not found, compiling first..."
    & $slang compile (Join-Path $root 'SnakeGame.jsonc') --format binary --no-banner
    if ($LASTEXITCODE -ne 0) { throw "[run-dev] compile failed" }
}
# keep dev-slot native dlls fresh (2026-11-19 generalized): any engine/library
# recompile re-stages its export-slot dll, but the copy in out\export\SnakeGame
# goes stale -> FFI binds an old binary (missing new exports, e.g. the engine's
# sle_layer_composite) -> game fails to run. Refresh every native dll that has
# a source slot. Keys = source dir name; values = dll file names.
$syncMap = [ordered]@{
    'SLangQT'      = @('slang_qt.dll')
    'SLangAudio'   = @('sl_audio_lib.dll')
    'SimGameEngine'= @('sl_sim_engine_lib.dll')
    'SLangRender'  = @('sl_render_lib.dll')
}
foreach ($slot in $syncMap.Keys) {
    foreach ($dll in $syncMap[$slot]) {
        $src = [System.IO.Path]::GetFullPath((Join-Path $modDir ('..\' + $slot + '\' + $dll)))
        $dst = Join-Path $modDir $dll
        if (-not (Test-Path -LiteralPath $src)) { continue }
        $needCopy = $false
        if (-not (Test-Path -LiteralPath $dst)) {
            $needCopy = $true
        } else {
            $needCopy = (Get-FileHash -LiteralPath $src -Algorithm MD5).Hash -ne (Get-FileHash -LiteralPath $dst -Algorithm MD5).Hash
        }
        if ($needCopy) {
            Copy-Item -LiteralPath $src -Destination $dst -Force
            Write-Host ("[run-dev] refreshed stale {0} from {1} export slot" -f $dll, $slot)
        }
    }
}
if ($Offscreen) { $env:QT_QPA_PLATFORM = 'offscreen' }
$env:PATH = $modDir + ';' + $env:PATH
# fix CWD to the game dir so SnakeSfx's cwd-relative sfx\ probe always hits
Set-Location $root
$extra = @()
if ($Debug) { $extra += '--debug-server' }
& $slang run (Join-Path $modDir 'SnakeGame.module.slb') --no-banner @extra
exit $LASTEXITCODE
