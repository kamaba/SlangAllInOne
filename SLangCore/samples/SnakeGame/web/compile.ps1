param(
    [string]$SlangCli = 'D:\project\lang\SlangAllInOne\out\cli-release\slang.exe'
)

# compile.ps1 - build the SnakeGameWeb module (SL -> .slb via the dotnet Front).
# Success criterion = the .slb timestamp is rewritten (dotnet exit code is
# unreliable, see csimple_lang/wasm/server.js lesson). Keep this file ASCII.

$ErrorActionPreference = 'Stop'
$webDir = $PSScriptRoot
$root = Join-Path $webDir '..\..\..\..'   # web -> SnakeGame -> samples -> SLangCore -> SlangAllInOne
$root = [System.IO.Path]::GetFullPath($root)
Set-Location $root

$jsonc = Join-Path $webDir 'SnakeGameWeb.jsonc'
$slb = Join-Path $root 'out\export\SnakeGameWeb\SnakeGameWeb.module.slb'

$before = $null
if (Test-Path $slb) { $before = (Get-Item $slb).LastWriteTimeUtc }

& $SlangCli compile $jsonc --format binary --no-banner
$cli = $LASTEXITCODE

$after = $null
if (Test-Path $slb) { $after = (Get-Item $slb).LastWriteTimeUtc }

Write-Host ('slang exit=' + $cli)
if ($null -eq $after) {
    Write-Host 'FAIL: slb not produced' -ForegroundColor Red
    exit 1
}
if ($null -ne $before -and $after -eq $before) {
    Write-Host 'FAIL: slb not rewritten (stale)' -ForegroundColor Red
    exit 1
}
Write-Host ('OK -> ' + $slb)
