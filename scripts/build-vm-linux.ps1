# build-vm-linux.ps1 - Build the C VM for WSL Linux (clang + ninja via CMake).
# Prerequisites inside WSL: clang, cmake, ninja, libsqlite3-dev.
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\build-vm-linux.ps1
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\build-vm-linux.ps1 -Config Release
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\build-vm-linux.ps1 -Config Release -Harden
#     (-Harden: distribution build, configures with SLVM_HARDEN=ON;
#      see csimple_lang\md\BINARY_HARDENING.md)
param(
    [ValidateSet('Debug','Release')][string]$Config = 'Debug',
    [switch]$Harden
)

. (Join-Path $PSScriptRoot 'common.ps1')

if (Invoke-BuildVmLinux $Config -Harden:$Harden) { exit 0 } else { exit 1 }
