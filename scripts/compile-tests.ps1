# compile-tests.ps1 - Compile test suites with the C# front compiler.
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\compile-tests.ps1                            # default suites
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\compile-tests.ps1 -Tests BaseTest,MathTest   # selected suites
# Known suites:
#   Default : BaseTest ExpendTest MathTest SpecialTest BenchMark NullFastTest
#   Optional: InlineLambdaTest InlineMethodTest AutoInlineTest
#   Broken  : TensoraTest RenderTest MysqlTest (always skipped)
param(
    [string[]]$Tests = @()
)

. (Join-Path $PSScriptRoot 'common.ps1')

if ($Tests.Count -eq 0) { $Tests = $DefaultTests }
if (-not (Test-SuiteName $Tests)) { exit 1 }

if (Invoke-CompileTests $Tests) { exit 0 } else { exit 1 }
