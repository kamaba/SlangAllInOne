# verify-test-harness.ps1 - slang test smoke (round 19)
#   1) full run:   expect [PASS] Good + [FAIL] Bad (exit=1), summary exit 1
#   2) --filter Good: expect only Good, exit 0
#   3) --filter NoSuch: expect "none matched", exit 0
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File verify-test-harness.ps1 [-Cli <slang.exe>]
# NOTE: keep comments pure ASCII - PS 5.1 -File reads BOM-less UTF-8 as GBK.

param(
    [string]$Cli = "D:\project\lang\SlangAllInOne\out\cli-release\slang.exe"
)

$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$proj = Join-Path $here "TestHarness.jsonc"

if (-not (Test-Path $Cli)) { throw "slang.exe not found: $Cli" }

$ok = $true

# --- 1) full run ---
$out = & $Cli test $proj --no-banner 2>&1
$code = $LASTEXITCODE
if ($code -ne 1) { Write-Host "[FAIL] full run exit=$code (expect 1)"; $ok = $false }
else { Write-Host "[OK]   full run exit=1" }
if (($out | Select-String -SimpleMatch "[PASS] Good").Count -lt 1) { Write-Host "[FAIL] missing [PASS] Good"; $ok = $false }
if (($out | Select-String -SimpleMatch "[FAIL] Bad").Count -lt 1) { Write-Host "[FAIL] missing [FAIL] Bad"; $ok = $false }
if (($out | Select-String -SimpleMatch "tests: 2 total, 1 passed, 1 failed").Count -lt 1) { Write-Host "[FAIL] bad summary"; $ok = $false }

# --- 2) filter Good ---
$out2 = & $Cli test $proj --no-banner --filter Good 2>&1
$code2 = $LASTEXITCODE
if ($code2 -ne 0) { Write-Host "[FAIL] filter Good exit=$code2 (expect 0)"; $ok = $false }
else { Write-Host "[OK]   filter Good exit=0" }
if (($out2 | Select-String -SimpleMatch "tests: 1 total, 1 passed, 0 failed").Count -lt 1) { Write-Host "[FAIL] filter summary"; $ok = $false }
if (($out2 | Select-String -SimpleMatch "[FAIL] Bad").Count -ge 1) { Write-Host "[FAIL] filter leaked Bad"; $ok = $false }

# --- 3) filter no match ---
$out3 = & $Cli test $proj --no-banner --filter NoSuchCase 2>&1
$code3 = $LASTEXITCODE
if ($code3 -ne 0) { Write-Host "[FAIL] filter no-match exit=$code3 (expect 0)"; $ok = $false }
else { Write-Host "[OK]   filter no-match exit=0" }
if (($out3 | Select-String -SimpleMatch "none matched").Count -lt 1) { Write-Host "[FAIL] no-match text missing"; $ok = $false }

if ($ok) { Write-Host "verify-test-harness: PASS" } else { throw "verify-test-harness: FAIL" }
