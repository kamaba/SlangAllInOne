# compile-stdlib.ps1 - Compile the standard library modules (Core -> Std -> Math).
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\compile-stdlib.ps1

. (Join-Path $PSScriptRoot 'common.ps1')

if (Invoke-CompileStdlib) { exit 0 } else { exit 1 }
