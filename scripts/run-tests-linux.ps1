# run-tests-linux.ps1 - Run test suites on the WSL Linux C VM (SL_FORCE_RUN=1).
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\run-tests-linux.ps1                            # default suites, Debug VM
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\run-tests-linux.ps1 -Tests BaseTest,MathTest   # selected suites
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\run-tests-linux.ps1 -Config Release            # Release VM
param(
    [string[]]$Tests = @(),
    [ValidateSet('Debug','Release')][string]$Config = 'Debug'
)

. (Join-Path $PSScriptRoot 'common.ps1')

if ($Tests.Count -eq 0) { $Tests = $DefaultTests }
if (-not (Test-SuiteName $Tests)) { exit 1 }

if (Invoke-RunTestsLinux $Tests $Config) { exit 0 } else { exit 1 }
