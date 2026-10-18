# run-tests-win.ps1 - Run test suites on the Windows C VM.
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\run-tests-win.ps1                            # default suites, Debug VM
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\run-tests-win.ps1 -Tests BaseTest,MathTest   # selected suites
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\run-tests-win.ps1 -Config Release            # Release VM
param(
    [string[]]$Tests = @(),
    [ValidateSet('Debug','Release')][string]$Config = 'Debug'
)

. (Join-Path $PSScriptRoot 'common.ps1')

if ($Tests.Count -eq 0) { $Tests = $DefaultTests }
if (-not (Test-SuiteName $Tests)) { exit 1 }

if (Invoke-RunTestsWin $Tests $Config) { exit 0 } else { exit 1 }
