param(
    [string]$SlangCli = 'D:\project\lang\SlangAllInOne\out\cli-release\slang.exe'
)

# compile.ps1 - build the 4 GameTestWeb modules (SL -> .slb via the dotnet Front).
# Success criterion = each .slb timestamp is rewritten (dotnet exit code is
# unreliable, see csimple_lang/wasm/server.js lesson). Keep this file ASCII-only.

$ErrorActionPreference = 'Stop'
$webDir = $PSScriptRoot
$root = Join-Path $webDir '..\..\..\..'   # web -> GameTest -> samples -> SLangCore -> SlangAllInOne
$root = [System.IO.Path]::GetFullPath($root)
Set-Location $root

$modules = @('SceneDemoWeb', 'RExamplesWeb', 'StatsGalleryWeb', 'RDataGalleryWeb')

$fail = 0
foreach ($name in $modules) {
    $jsonc = Join-Path $webDir ($name + '.jsonc')
    $slb = Join-Path $root ('out\export\' + $name + '\' + $name + '.module.slb')

    $before = $null
    if (Test-Path $slb) { $before = (Get-Item $slb).LastWriteTimeUtc }

    Write-Host ('== compile ' + $name + ' ==')
    & $SlangCli compile $jsonc --format binary --no-banner
    $cli = $LASTEXITCODE

    $after = $null
    if (Test-Path $slb) { $after = (Get-Item $slb).LastWriteTimeUtc }

    Write-Host ($name + ' slang exit=' + $cli)
    if ($null -eq $after) {
        Write-Host ($name + ' FAIL: slb not produced') -ForegroundColor Red
        $fail = 1
        continue
    }
    if ($null -ne $before -and $after -eq $before) {
        Write-Host ($name + ' FAIL: slb not rewritten (stale)') -ForegroundColor Red
        $fail = 1
        continue
    }
    Write-Host ($name + ' OK -> ' + $slb) -ForegroundColor Green
}

if ($fail -ne 0) { exit 1 }
Write-Host 'ALL 4 GameTestWeb modules OK'
