# Batch-add "publish" section to all test-project jsonc files (2026-10-22):
#   mode=both (exe + slb), outputDir=publish (relative to the jsonc directory).
# Negative-test projects (expected compile failures) are excluded. Matched by
# jsonc base name OR parent directory name (InlineLambdaForbiddenTest keeps its
# jsonc named ProjectTest.jsonc, i.e. only the directory identifies it).
# Preserves original BOM / newline style. -WhatIf = dry run. Idempotent: files
# that already carry a "publish" section are skipped.
param([switch]$WhatIf)

$root = 'D:\project\lang\SlangAllInOne\SLangCore\test'
$negNames = @(
    'PlatformAotNegTest','PlatformNegTest','PlatformOverrideNegTest','PlatformVariantNegTest',
    'HookMacroOutsideNegTest','HookBeforeUndefNegTest','HookBeforeSubscriptNegTest','HookBeforeExprNegTest',
    'AtSignNegativeTest','InlineLambdaForbiddenTest'
)
$files = Get-ChildItem $root -Recurse -Filter *.jsonc |
    Where-Object { $negNames -notcontains $_.BaseName -and $negNames -notcontains $_.Directory.Name }
$changed = 0; $skipped = 0
foreach ($f in $files) {
    $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
    $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    $enc = New-Object System.Text.UTF8Encoding($hasBom)
    $text = [System.IO.File]::ReadAllText($f.FullName)
    if ($text -match '"publish"\s*:') { $skipped++; continue }
    $nl = if ($text -match "`r`n") { "`r`n" } else { "`n" }
    $idx = $text.LastIndexOf('}')
    if ($idx -lt 0) { $skipped++; continue }
    $head = $text.Substring(0, $idx).TrimEnd()
    $tail = $text.Substring($idx)
    $pub = ',' + $nl + '  "publish": {' + $nl +
           '    "mode": "both",' + $nl +
           '    "outputDir": "publish"' + $nl +
           '  }' + $nl
    $new = $head + $pub + $tail
    if (-not $WhatIf) { [System.IO.File]::WriteAllText($f.FullName, $new, $enc) }
    $changed++
    Write-Host ('[OK] ' + $f.FullName.Substring($root.Length + 1))
}
Write-Host ('--- changed: ' + $changed + '  skipped(existing publish/bad tail): ' + $skipped)
