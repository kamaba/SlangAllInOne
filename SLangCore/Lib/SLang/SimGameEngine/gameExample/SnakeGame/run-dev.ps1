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
# keep dev-slot slang_qt.dll fresh (same fix as 2026-11-18)
$qtSrc = [System.IO.Path]::GetFullPath((Join-Path $modDir '..\SLangQT\slang_qt.dll'))
$qtDst = Join-Path $modDir 'slang_qt.dll'
if ((Test-Path -LiteralPath $qtSrc) -and ((Get-FileHash -LiteralPath $qtSrc -Algorithm MD5).Hash -ne (Get-FileHash -LiteralPath $qtDst -Algorithm MD5).Hash)) {
    Copy-Item -LiteralPath $qtSrc -Destination $qtDst -Force
    Write-Host "[run-dev] refreshed stale slang_qt.dll from export slot"
}
# keep dev-slot sl_audio_lib.dll fresh (SnakeSfx, 2026-11-19): the audio FFI
# resolves the dll by bare name, PATH search covers the module dir.
$auSrc = [System.IO.Path]::GetFullPath((Join-Path $modDir '..\SLangAudio\sl_audio_lib.dll'))
$auDst = Join-Path $modDir 'sl_audio_lib.dll'
if ((Test-Path -LiteralPath $auSrc) -and ((-not (Test-Path -LiteralPath $auDst)) -or ((Get-FileHash -LiteralPath $auSrc -Algorithm MD5).Hash -ne (Get-FileHash -LiteralPath $auDst -Algorithm MD5).Hash))) {
    Copy-Item -LiteralPath $auSrc -Destination $auDst -Force
    Write-Host "[run-dev] refreshed sl_audio_lib.dll from export slot"
}
if ($Offscreen) { $env:QT_QPA_PLATFORM = 'offscreen' }
$env:PATH = $modDir + ';' + $env:PATH
# fix CWD to the game dir so SnakeSfx's cwd-relative sfx\ probe always hits
Set-Location $root
$extra = @()
if ($Debug) { $extra += '--debug-server' }
& $slang run (Join-Path $modDir 'SnakeGame.module.slb') --no-banner @extra
exit $LASTEXITCODE
