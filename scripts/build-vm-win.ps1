# build-vm-win.ps1 - Build the C VM for Windows (clang + ninja via CMake).
# Release builds are hardened BY DEFAULT (LTO + anti-debug are baked into the
# CMake/VS project configs; see csimple_lang\md\BINARY_HARDENING.md §5.3-5.4).
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\build-vm-win.ps1
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\build-vm-win.ps1 -Config Release
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\build-vm-win.ps1 -Config Release -Harden
#     (-Harden: redundant safety net - explicitly flips SLVM_HARDEN=ON on the tree
#      (guards against an old cache holding OFF) and rebuilds.)
param(
    [ValidateSet('Debug','Release')][string]$Config = 'Debug',
    [switch]$Harden
)

. (Join-Path $PSScriptRoot 'common.ps1')

if (Invoke-BuildVmWin $Config -Harden:$Harden) { exit 0 } else { exit 1 }
