# run-website-examples.ps1 - Verify that every "run" page example (official website,
# csharp-server api/example/list) really compiles and runs, through the SAME pipeline
# the website uses (web/src/lib/runCommon.ts planRun + api/compile.ts + wasmRunner.ts):
#   1. GET  <ApiBase>/api/example/list           (same data source as the run page)
#   2. planRun normalization                     (Playground.runMain / Project._main_ / auto-wrap)
#   3. inject "import Std;" + write Playground.sl/sp/jsonc into out\playground-verify
#      (same jsonc as api/compile.ts; --format binary+json, SLB preferred like wasmRunner)
#   4. compile with the Front compiler
#   5. run in the WEBSITE wasm VM via node scripts\website-wasm-run.cjs
#      (assets = SLangOfficialWebsite\web\public\wasm, staged to a CJS-safe dir)
#   6. compare captured stdout lines against expected_output
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\run-website-examples.ps1
#   powershell ... -Slug fib,table99                  # only these slugs
#   powershell ... -Local <file.ps1>                 # test candidate codes BEFORE pushing to DB;
#                                                    # file defines $LocalExamples = @{ slug = @{ Code; Expected } }
#   powershell ... -ApiBase http://localhost:35221
# Exit 0 = all examples pass; 1 = at least one failed.
#
# Policy when an example fails: FIX THE EXAMPLE CODE FIRST (slang_dev DB row +
# csharp-server/sql migration + web/src/data/examples.json), not the compiler.
param(
    [string]$ApiBase = $(if ($env:SLANG_API_BASE) { $env:SLANG_API_BASE } else { 'http://localhost:35221' }),
    [string[]]$Slug = @(),
    [string]$Local = '',
    [switch]$ShowOutput
)

. (Join-Path $PSScriptRoot 'common.ps1')

# ---- layout (mirrors api/compile.ts; references ../export -> SlangAllInOne\out\export) ----
$ScratchDir   = Join-Path $AllInOneDir 'out\playground-verify'
$OutDir       = Join-Path $ScratchDir 'Playground'
$WebWasmSrc   = Join-Path $RepoRoot 'SLangOfficialWebsite\web\public\wasm'
$StagedAssets = Join-Path $AllInOneDir 'out\wasm-verify\assets'
$NodeRunner   = Join-Path $PSScriptRoot 'website-wasm-run.cjs'
$WasmAssets   = @('csimple_lang.js', 'csimple_lang.wasm', 'Core.module.json', 'Std.module.json', 'Math.module.json')

function Write-Header([string]$Text) {
    Write-Host ''
    Write-Host ('=== ' + $Text + ' ===') -ForegroundColor Cyan
}

function Build-Sp([bool]$IsProject) {
    $call = if ($IsProject) { 'Project._main_()' } else { 'Playground.runMain()' }
    return @"
Project
{
    _main_()
    {
        $call
    }
    _before_()
    {
    }
    _after_()
    {
    }
}

"@
}

function Build-Jsonc() {
    return @"
{
  "project": {
    "name": "Playground",
    "desc": "website examples verify scratch",
    "mainVersion": 0,
    "subVersion": 0,
    "buildVersion": 1,
    "buildSubVersion": 0
  },
  "source": { "root": "." },
  "compile": {
    "optimize": false,
    "target": "x64",
    "debug": true,
    "isUseForceSemiColonInLineEnd": false,
    "isForceUseClassKey": false,
    "isSupportDoublePlus": false,
    "requireSameNumericTypes": false
  },
  "compileFiles": {
    "files": [{ "path": "Playground.sl", "group": "core", "tag": "base", "ignore": false, "priority": 0 }]
  },
  "compileFilter": { "isAllGroup": true, "isAllTag": true },
  "global": { "imports": ["Std.Console"] },
  "references": [
    { "path": "../export/Core", "uuid": "123123123213", "name": "Core.module.json" },
    { "path": "../export/Std", "uuid": "456456456456", "name": "Std.module.json" },
    { "path": "../export/Math", "uuid": "789789789789", "name": "Math.module.json" }
  ],
  "export": {
    "moduleName": "Playground",
    "outputDir": ".",
    "versionMain": 0,
    "versionSub": 0,
    "versionPatch": 1,
    "includeMetadata": true,
    "debugText": { "outputDir": "", "code": false, "token": false, "node": false, "file": false, "meta": false, "ir": false }
  }
}
"@
}

# ---- runCommon.ts planRun port (keep in sync with web/src/lib/runCommon.ts) ----
function Get-PlannedSource([string]$Code) {
    # returns @{ Source; Entry = 'playground'|'project'; Wrapped = $bool }
    if ($Code -match 'class\s+Playground|runMain') {
        return @{ Source = $Code; Entry = 'playground'; Wrapped = $false }
    }
    if ($Code -match 'Project' -and $Code -match '_main_') {
        return @{ Source = $Code; Entry = 'project'; Wrapped = $false }
    }
    $indented = ($Code -split "`n" | ForEach-Object { '        ' + $_ }) -join "`n"
    $wrapped = "Playground`n{`n    static runMain()`n    {`n$indented`n    }`n}"
    return @{ Source = $wrapped; Entry = 'playground'; Wrapped = $true }
}

# ---- output normalization (per-line) ----
function Normalize-Lines([AllowNull()][string[]]$InLines) {
    $out = New-Object System.Collections.Generic.List[string]
    if ($null -ne $InLines) {
        foreach ($l in $InLines) {
            $t = ([string]$l) -replace '\[\d+\s?ms\]', '[N ms]'
            $out.Add($t.TrimEnd(' '))
        }
    }
    while ($out.Count -gt 0 -and $out[$out.Count - 1] -eq '') { $out.RemoveAt($out.Count - 1) }
    return $out
}

function ConvertTo-LineArray([string]$Text) {
    if ($null -eq $Text -or $Text -eq '') { return @() }
    return ($Text -replace "`r`n", "`n") -split "`n"
}

function Get-FrontErrorTail([string]$LogPath) {
    if (-not (Test-Path $LogPath)) { return '(no Front.txt)' }
    try {
        $lines = [System.IO.File]::ReadAllLines($LogPath)
        $errs = @($lines | Where-Object { $_ -match '\[Error\]' })
        if ($errs.Count -gt 0) { return ($errs | Select-Object -Last 12) -join "`n" }
        return (($lines | Select-Object -Last 12) -join "`n")
    } catch { return '(unreadable Front.txt)' }
}

function Stage-WasmAssets {
    # csimple_lang.js must be require()d OUTSIDE web/ ("type":"module" would load it
    # as ESM in Node and the UMD footer would not export the factory) -> stage a copy.
    New-Item -ItemType Directory -Path $StagedAssets -Force | Out-Null
    foreach ($f in $WasmAssets) {
        $src = Join-Path $WebWasmSrc $f
        $dst = Join-Path $StagedAssets $f
        if (-not (Test-Path $src)) {
            Write-Host ('wasm asset missing: ' + $src) -ForegroundColor Red
            exit 1
        }
        if ((-not (Test-Path $dst)) -or (Get-Item $src).LastWriteTime -gt (Get-Item $dst).LastWriteTime) {
            Copy-Item $src $dst -Force
        }
    }
}

# ---- 0) sanity ----
foreach ($d in @('Core', 'Std', 'Math')) {
    if (-not (Test-Path (Join-Path $ExportDir ($d + '\' + $d + '.module.json')))) {
        Write-Host ('stdlib export missing: ' + $d + '.module.json (run scripts\compile-stdlib.ps1)') -ForegroundColor Red
        exit 1
    }
}
$c = Get-Command node.exe -ErrorAction SilentlyContinue
if (-not $c) {
    Write-Host 'node.exe not found in PATH (needed to run the website wasm VM)' -ForegroundColor Red
    exit 1
}
Stage-WasmAssets

# ---- 1) get examples: -Local candidates file or the run-page API ----
if ($Local) {
    if (-not (Test-Path $Local)) { Write-Host ('-Local file not found: ' + $Local) -ForegroundColor Red; exit 1 }
    . $Local
    if (-not $LocalExamples) { Write-Host '-Local file must define $LocalExamples = @{ slug = @{ Code = ...; Expected = ... } }' -ForegroundColor Red; exit 1 }
    $examples = @()
    foreach ($k in @($LocalExamples.Keys)) {
        if ($Slug.Count -eq 0 -or $Slug -contains $k) {
            $examples += [pscustomobject]@{ slug = $k; title = $k; code = $LocalExamples[$k].Code; expectedOutput = $LocalExamples[$k].Expected }
        }
    }
    Write-Header ('Local candidate codes : ' + $examples.Count + ' example(s)')
} else {
    Write-Header ('Fetch run-page examples from ' + $ApiBase)
    try {
        $resp = Invoke-RestMethod -Uri ($ApiBase + '/api/example/list') -TimeoutSec 15
        $examples = @($resp.data)
    } catch {
        Write-Host ('API unreachable: ' + $_.Exception.Message) -ForegroundColor Red
        Write-Host 'Start the csharp-server (slang-server) or set -ApiBase / -Local.' -ForegroundColor Yellow
        exit 1
    }
    if ($Slug.Count -gt 0) { $examples = @($examples | Where-Object { $Slug -contains $_.slug }) }
    Write-Host ('examples: ' + $examples.Count)
}

# ---- 2) run each example through the website pipeline ----
$rows = @()
$failures = @()
$i = 0
foreach ($ex in $examples) {
    $i++
    $slug = [string]$ex.slug
    Write-Host ''
    Write-Host ('--- [' + $i + '/' + $examples.Count + '] ' + $slug + ' : ' + [string]$ex.title)

    # planRun (website normalization) - normalize line endings first
    $code = ([string]$ex.code) -replace "`r`n", "`n"
    $code = $code -replace "`r", "`n"
    $planned = Get-PlannedSource $code
    $entry = $planned.Entry
    $note = ''
    if ($planned.Wrapped) { $note = 'auto-wrapped' }

    # stage scratch files (api/compile.ts: CRLF->LF, inject "import Std;" at top)
    $normalized = $planned.Source -replace "`r`n", "`n"
    New-Item -ItemType Directory -Path $ScratchDir -Force | Out-Null
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText((Join-Path $ScratchDir 'Playground.sl'), ('import Std;' + "`n`n" + $normalized), $utf8)
    [System.IO.File]::WriteAllText((Join-Path $ScratchDir 'Playground.sp'), (Build-Sp ($entry -eq 'project')), $utf8)
    [System.IO.File]::WriteAllText((Join-Path $ScratchDir 'Playground.jsonc'), (Build-Jsonc), $utf8)

    $slbPath  = Join-Path $OutDir 'Playground.module.slb'
    $jsonPath = Join-Path $OutDir 'Playground.module.json'
    $logPath  = Join-Path $OutDir 'Logs\Front.txt'
    foreach ($f in @($slbPath, $jsonPath)) { if (Test-Path $f) { Remove-Item $f -Force } }

    # compile (Front; same jsonc as api/compile.ts, cwd = repo root)
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $spPath = Join-Path $ScratchDir 'Playground.sp'
    $compileOut = ''
    Push-Location $RepoRoot
    try {
        $compileOut = dotnet run --project $FrontProj -- compile -p $spPath -e ir --format binary+json 2>&1 | Out-String
        $null = $LASTEXITCODE
    } finally {
        Pop-Location
    }
    $sw.Stop()
    $modulePath = $null
    if (Test-Path $slbPath) { $modulePath = $slbPath }
    elseif (Test-Path $jsonPath) { $modulePath = $jsonPath }

    if (-not $modulePath) {
        $tail = Get-FrontErrorTail $logPath
        Write-Host ('    COMPILE FAILED') -ForegroundColor Red
        Write-Host ('    Front.txt: ' + $tail) -ForegroundColor DarkGray
        $rows += [pscustomobject]@{ Slug = $slug; Compile = 'FAIL'; Exit = ''; Output = ''; Note = $note }
        $failures += $slug
        continue
    }

    # run in the WEBSITE wasm VM (node + staged public/wasm assets)
    $runJson = node $NodeRunner $modulePath $StagedAssets 2>$null | Out-String
    $run = $null
    try { $run = $runJson | ConvertFrom-Json } catch { $run = $null }
    if (-not $run) {
        Write-Host ('    WASM RUN FAILED (no JSON from node)') -ForegroundColor Red
        Write-Host ($runJson.TrimEnd()) -ForegroundColor DarkGray
        $rows += [pscustomobject]@{ Slug = $slug; Compile = 'OK'; Exit = '?'; Output = ''; Note = $note }
        $failures += $slug
        continue
    }
    $runExit = [int]$run.exit
    $actual = @(Normalize-Lines @($run.lines))
    $expected = @(Normalize-Lines @(ConvertTo-LineArray ([string]$ex.expectedOutput)))

    if ($ShowOutput) {
        foreach ($l in $actual) { Write-Host ('    | ' + $l) -ForegroundColor DarkGray }
    }

    # compare as plain joined strings (PS5.1-safe: no List.ToArray / Compare-Object)
    $actualStr = (@($actual) -join "`n")
    $expectedStr = (@($expected) -join "`n")

    $verdict = 'OK'
    if ($runExit -ne 0) { $verdict = 'EXIT ' + $runExit }
    elseif (@($run.err).Count -gt 0) { $verdict = 'STDERR' }
    elseif ($actualStr -cne $expectedStr) { $verdict = 'MISMATCH' }

    if ($verdict -ne 'OK') {
        Write-Host ('    expected: [' + ($expected -join '][DT]') + ']') -ForegroundColor Yellow
        Write-Host ('    actual  : [' + ($actual -join '][DT]') + ']') -ForegroundColor Yellow
        if (@($run.err).Count -gt 0) { Write-Host ('    stderr: ' + (@($run.err) -join ' | ')) -ForegroundColor Yellow }
    }
    $color = if ($verdict -eq 'OK') { 'Green' } else { 'Red' }
    Write-Host ('    ' + $verdict + '  [' + [math]::Round($sw.Elapsed.TotalSeconds, 1) + 's compile]  entry=' + $entry) -ForegroundColor $color

    $rows += [pscustomobject]@{ Slug = $slug; Compile = 'OK'; Exit = $runExit; Output = $verdict; Note = $note }
    if ($verdict -ne 'OK') { $failures += $slug }
}

# ---- 3) summary ----
Write-Header 'Website run-page examples verdict'
$rows | Format-Table -AutoSize | Out-Host
if ($failures.Count -eq 0) {
    Write-Host ('ALL ' + $examples.Count + ' EXAMPLES PASS') -ForegroundColor Green
    exit 0
}
Write-Host ('FAILED (' + $failures.Count + '): ' + ($failures -join ', ')) -ForegroundColor Red
Write-Host 'Policy: fix the example code first (slang_dev DB row + sql migration + web/src/data/examples.json).'
exit 1
