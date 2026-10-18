# build-all.ps1 - One-click build for the whole repo:
#   1. C VM, Windows (clang + ninja)   -> csimple_lang\build\<Config>\bin\csimple_lang.exe
#   2. C VM, WSL Linux (clang + ninja) -> csimple_lang\build\<Config>Linux\bin\csimple_lang
#   3. Stdlib modules (Core -> Std -> Math)
#   4. Test suites (default set, or -Tests ...)
#   5. -Run : also run the suites on both platforms
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\build-all.ps1                          # build only
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\build-all.ps1 -Run                     # build + run
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\build-all.ps1 -Tests BaseTest,MathTest -Run
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\build-all.ps1 -SkipVm -SkipCompile -Run  # run only
param(
    [ValidateSet('Debug','Release')][string]$Config = 'Debug',
    [string[]]$Tests = @(),
    [switch]$Run,
    [switch]$SkipVm,
    [switch]$SkipCompile
)

. (Join-Path $PSScriptRoot 'common.ps1')

if ($Tests.Count -eq 0) { $Tests = $DefaultTests }
if (-not (Test-SuiteName $Tests)) { exit 1 }

$script:Summary = @()
$script:AnyFail = $false
function Add-Summary([string]$Stage, [string]$Status) {
    $script:Summary += [pscustomobject]@{ Stage = $Stage; Status = $Status }
    if ($Status -eq 'OK') {
        Write-Host ('  >> ' + $Stage + ' : OK') -ForegroundColor Green
    } elseif ($Status -eq 'SKIP') {
        Write-Host ('  >> ' + $Stage + ' : SKIP') -ForegroundColor Yellow
    } else {
        $script:AnyFail = $true
        Write-Host ('  >> ' + $Stage + ' : FAIL') -ForegroundColor Red
    }
}

if ($SkipVm) {
    Add-Summary 'build-vm-win'   'SKIP'
    Add-Summary 'build-vm-linux' 'SKIP'
} else {
    if (Invoke-BuildVmWin $Config)   { Add-Summary 'build-vm-win'   'OK' } else { Add-Summary 'build-vm-win'   'FAIL' }
    if (Invoke-BuildVmLinux $Config) { Add-Summary 'build-vm-linux' 'OK' } else { Add-Summary 'build-vm-linux' 'FAIL' }
}

if ($SkipCompile) {
    Add-Summary 'compile-stdlib' 'SKIP'
    Add-Summary 'compile-tests'  'SKIP'
} else {
    if (Invoke-CompileStdlib)       { Add-Summary 'compile-stdlib' 'OK' } else { Add-Summary 'compile-stdlib' 'FAIL' }
    if (Invoke-CompileTests $Tests) { Add-Summary 'compile-tests'  'OK' } else { Add-Summary 'compile-tests'  'FAIL' }
}

if ($Run) {
    if (Invoke-RunTestsWin $Tests $Config)   { Add-Summary 'run-tests-win'   'OK' } else { Add-Summary 'run-tests-win'   'FAIL' }
    if (Invoke-RunTestsLinux $Tests $Config) { Add-Summary 'run-tests-linux' 'OK' } else { Add-Summary 'run-tests-linux' 'FAIL' }
}

Write-Host ''
Write-Host '=== build-all summary ===' -ForegroundColor Cyan
$script:Summary | Format-Table -AutoSize | Out-Host
if ($script:AnyFail) {
    Write-Host 'build-all: FAILED (see stages above)' -ForegroundColor Red
    exit 1
}
Write-Host 'build-all: ALL OK' -ForegroundColor Green
exit 0
