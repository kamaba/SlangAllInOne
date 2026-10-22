# release-local.ps1 - One-command local release chain (dev loop closer).
#
# After changing the Frontend and/or the C VM, run this single script to:
#   0. verify the R17 version anchors agree (5 places, hard fail on mismatch)
#   1. kill running slang.exe processes (the IDE LSP locks bin\Debug\net8.0
#      and would fail the dotnet publish step; the language client restarts
#      itself on the next window reload - we burn its restart quota here)
#   2. build-packages.ps1 - the four packages (win/linux x debug/release,
#      layout checks + Std smoke included)
#   3. refresh the out\host publish host (VSCode launch.json publish configs
#      point at it - keeps it from going stale, ~7s)
#   4. build the vsix: compile + hard gates (ext-load-smoke, dap-smoke),
#      embed package\win32-release + linux-release as runtime\, vsce package
#   5. install into the local IDE (Trae CN by default): swap the version dir
#      under the extensions root and rewrite the extensions.json registry
#      (manual equivalent of `code --install-extension` - no CLI exists for
#      Trae CN)
#   6. print the next step - YOU reload the IDE window and debug manually.
#
# Usage (workspace root):
#   powershell -NoProfile -ExecutionPolicy Bypass -File SlangAllInOne\scripts\release-local.ps1
#   ... -SkipPackages                # reuse the existing package\win32-release / linux-release
#   ... -SkipInstall                 # build packages + vsix only, do not touch the IDE
#   ... -ExtensionsRoot <dir>        # override the IDE extensions dir
#                                     # (default %USERPROFILE%\.trae-cn\extensions)
#
# Notes:
#   - Comments in this file are ASCII-only on purpose: under a PS5.1 -File
#     host, BOM-less UTF-8 is read as ANSI/GBK and a multi-byte tail byte can
#     eat the newline -> parser error (see
#     SlangAllInOne\md\ai\troubleshooting\06-build-engineering.md, 2026-10-22).
#   - Version bumping is NOT done here: bump the anchors first (R17, any
#     change anywhere in the repo -> all anchors +1), then run this script -
#     step 0 enforces they agree.
param(
    [switch]$SkipPackages,
    [switch]$SkipInstall,
    [string]$ExtensionsRoot = ''
)

$ErrorActionPreference = 'Stop'

$AllInOneDir = Split-Path -Parent $PSScriptRoot
$RepoRoot    = Split-Path -Parent $AllInOneDir
$PluginDir   = Join-Path $RepoRoot 'slang_vscode_plugin'

function Fail([string]$msg) { Write-Host ('FAIL: ' + $msg) -ForegroundColor Red; exit 1 }
function Ok([string]$msg)   { Write-Host ('  ' + $msg) -ForegroundColor Green }
function Step([string]$msg) { Write-Host ''; Write-Host ('=== ' + $msg + ' ===') -ForegroundColor Cyan }

# Read one version anchor via .NET ReadAllText (UTF-8, ACP-independent - the
# PS5.1 Get-Content GBK trap, see md\09_packaging_release.md 0.0.6 notes).
function Read-Anchor([string]$file, [string]$pattern) {
    if (-not (Test-Path $file)) { return $null }
    $m = [regex]::Match([System.IO.File]::ReadAllText($file), $pattern)
    if (-not $m.Success) { return $null }
    return $m.Groups[1].Value
}

# Kill slang.exe until the IDE language client's restart quota is exhausted
# (it auto-restarts the LSP a few times after an unexpected exit; after the
# quota runs out the process stays dead until the window is reloaded).
function Stop-SlangProcesses {
    if (@(Get-Process slang -ErrorAction SilentlyContinue).Count -eq 0) { return }
    Write-Host '  killing running slang.exe (LSP locks bin\Debug; restart quota burn)...'
    $quiet = 0
    for ($i = 0; $i -lt 8; $i++) {
        $procs = @(Get-Process slang -ErrorAction SilentlyContinue)
        if ($procs.Count -eq 0) {
            $quiet++
            if ($quiet -ge 2) { return }
        } else {
            $quiet = 0
            $procs | Stop-Process -Force
            Write-Host ('  killed ' + $procs.Count + ' slang.exe')
        }
        Start-Sleep -Seconds 2
    }
}

# ---- step 0: R17 version-anchor consistency (hard gate) --------------------
Step 'Step 0/5: R17 version anchors (must all agree)'
$anchors = @(
    @{ Name = 'Front (CommandExecutor.cs VersionString)'; File = Join-Path $RepoRoot 'simple_language\source\CLI\CommandExecutor.cs'; Pattern = 'VersionString\s*=\s*"([^"]+)"' },
    @{ Name = 'C VM (cli_version.h SLVM_VERSION_STRING)'; File = Join-Path $RepoRoot 'csimple_lang\src\cli\cli_version.h';         Pattern = 'SLVM_VERSION_STRING\s+"([^"]+)"' },
    @{ Name = 'AllInOne (csproj <Version>)';               File = Join-Path $AllInOneDir 'SlangAllInOne.csproj';                   Pattern = '<Version>([^<]+)</Version>' },
    @{ Name = 'VSCode (package.json version)';             File = Join-Path $PluginDir 'package.json';                            Pattern = '"version"\s*:\s*"([^"]+)"' },
    @{ Name = 'VSCode (package-lock.json version)';        File = Join-Path $PluginDir 'package-lock.json';                       Pattern = '"version"\s*:\s*"([^"]+)"' }
)
$ver = $null
$bad = @()
foreach ($a in $anchors) {
    $v = Read-Anchor $a.File $a.Pattern
    if ($v -eq $null) { $bad += ($a.Name + ' -> NOT FOUND'); continue }
    if ($ver -eq $null) { $ver = $v }
    elseif ($v -ne $ver) { $bad += ($a.Name + ' -> ' + $v) }
}
if ($ver -eq $null) { Fail 'cannot read any version anchor' }
if ($bad.Count -gt 0) {
    Write-Host ('  version mismatch (expected ' + $ver + '):') -ForegroundColor Red
    foreach ($b in $bad) { Write-Host ('    ' + $b) -ForegroundColor Red }
    Fail 'R17 violated - bump ALL anchors together (AGENTS.md R17), then re-run'
}
Ok ('all 5 anchors agree: ' + $ver)

# ---- step 1+2: packages -----------------------------------------------------
if (-not $SkipPackages) {
    Step 'Step 1/5: kill slang.exe (unlock bin\Debug for publish)'
    Stop-SlangProcesses

    Step 'Step 2/5: build the four packages (build-packages.ps1)'
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'build-packages.ps1')
    if ($LASTEXITCODE -ne 0) { Fail 'build-packages.ps1 failed (see log above)' }
} else {
    Write-Host '  -SkipPackages: reusing the existing packages' -ForegroundColor Yellow
}

$pkgWin   = Join-Path $AllInOneDir 'package\win32-release'
$pkgLinux = Join-Path $AllInOneDir 'package\linux-release'
foreach ($p in @(@($pkgWin, 'slang.exe', 'win32-release'), @($pkgLinux, 'slang', 'linux-release'))) {
    if (-not (Test-Path (Join-Path $p[0] $p[1]))) {
        Fail ('package missing: ' + $p[2] + ' (run without -SkipPackages first)')
    }
}

# ---- step 3: refresh the out\host publish host -------------------------------
Step 'Step 3/5: refresh out\host publish host (launch.json publish configs)'
Push-Location $RepoRoot
& dotnet build (Join-Path $AllInOneDir 'SlangAllInOne.csproj') -c Debug -o (Join-Path $AllInOneDir 'out\host')
$code = $LASTEXITCODE
Pop-Location
if ($code -ne 0) { Fail 'out\host build failed' }
Ok 'out\host refreshed'

# ---- step 4: vsix (gates + runtime embed + package) --------------------------
Step 'Step 4/5: build the vsix (gates + embedded runtime)'
if (-not (Get-Command node -ErrorAction SilentlyContinue)) { Fail 'node not found in PATH' }
Push-Location $PluginDir
try {
    if (-not (Test-Path 'node_modules')) {
        & npm install --no-audit --no-fund
        if ($LASTEXITCODE -ne 0) { throw 'npm install failed' }
    }
    & npm run compile
    if ($LASTEXITCODE -ne 0) { throw 'npm run compile failed' }

    # release gates (md/09 4): bundle load smoke + DAP end-to-end
    & node scripts\ext-load-smoke.mjs
    if ($LASTEXITCODE -ne 0) { throw 'ext-load-smoke FAILED (pack gate)' }
    & node scripts\dap-smoke.mjs
    if ($LASTEXITCODE -ne 0) { throw 'dap-smoke FAILED (pack gate)' }
    Ok 'gates passed (ext-load-smoke + dap-smoke)'

    # embed the release runtimes (runtime/<plat>-x64, robocopy /XD vsix)
    $runtimeRoot = Join-Path $PluginDir 'runtime'
    if (Test-Path $runtimeRoot) { Remove-Item $runtimeRoot -Recurse -Force }
    foreach ($rt in @(@($pkgWin, 'win32-x64'), @($pkgLinux, 'linux-x64'))) {
        $dst = Join-Path $runtimeRoot $rt[1]
        & robocopy $rt[0] $dst /E /XD vsix /NFL /NDL /NJH /NJS /NP | Out-Null
        if ($LASTEXITCODE -ge 8) { throw ('robocopy failed for ' + $rt[1]) }
    }
    Ok 'runtime embedded (win32-x64 + linux-x64)'

    $vsixName = 'slang-vscode-' + $ver + '.vsix'
    $vsixPath = Join-Path $PluginDir $vsixName
    if (Test-Path $vsixPath) { Remove-Item $vsixPath -Force }
    & npx vsce package --no-dependencies
    if ($LASTEXITCODE -ne 0) { throw 'vsce package failed' }
    if (-not (Test-Path $vsixPath)) { throw ('expected vsix not produced: ' + $vsixPath) }
    Ok ('vsix: ' + $vsixName)
} catch {
    Pop-Location
    Fail $_.Exception.Message
}
Pop-Location

# ---- step 5: install into the local IDE --------------------------------------
if (-not $SkipInstall) {
    Step 'Step 5/5: install into the local IDE'
    if ($ExtensionsRoot -eq '') { $ExtensionsRoot = Join-Path $env:USERPROFILE '.trae-cn\extensions' }
    if (-not (Test-Path $ExtensionsRoot)) { Fail ('extensions root not found: ' + $ExtensionsRoot + ' (override with -ExtensionsRoot)') }

    Stop-SlangProcesses

    # a) unpack the vsix (zip) and place extension\* into the version dir
    $dst = Join-Path $ExtensionsRoot ('kamaba.slang-vscode-' + $ver)
    $tmp = Join-Path $env:TEMP ('vsix_install_' + [guid]::NewGuid().ToString('N'))
    $zip = $tmp + '.zip'
    try {
        Copy-Item $vsixPath $zip -Force
        Expand-Archive $zip (Join-Path $tmp 'unpack') -Force

        # remove every older kamaba.slang-vscode-* version dir
        Get-ChildItem $ExtensionsRoot -Directory -Filter 'kamaba.slang-vscode-*' |
            ForEach-Object { Remove-Item $_.FullName -Recurse -Force }

        New-Item -ItemType Directory -Path $dst | Out-Null
        Copy-Item (Join-Path $tmp 'unpack\extension\*') $dst -Recurse -Force

        $installedVer = Read-Anchor (Join-Path $dst 'package.json') '"version"\s*:\s*"([^"]+)"'
        if ($installedVer -ne $ver) { Fail ('installed package.json version mismatch: ' + $installedVer) }
        Ok ('extension dir: ' + $dst + ' (v' + $ver + ')')

        # b) rewrite the extensions.json registry entry (manual equivalent of
        #    the CLI install). Brace-match the existing entry if present,
        #    otherwise append before the closing bracket.
        $ej = Join-Path $ExtensionsRoot 'extensions.json'
        if (-not (Test-Path $ej)) { Fail 'extensions.json not found under the extensions root' }
        $raw = [System.IO.File]::ReadAllText($ej)

        $fsPath = $dst
        $fwd = '/' + $dst.Substring(0, 1).ToLower() + $dst.Substring(1).Replace('\', '/')
        $external = 'file:///' + $fwd.TrimStart('/').Replace(':', '%3A')
        $now = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
        $newEntry = '{"identifier":{"id":"kamaba.slang-vscode"},"version":"' + $ver + '","location":{"$mid":1,"fsPath":"' + ($fsPath -replace '\\', '\\') + '","_sep":1,"external":"' + $external + '","path":"' + $fwd + '","scheme":"file"},"relativeLocation":"kamaba.slang-vscode-' + $ver + '","metadata":{"isApplicationScoped":false,"isMachineScoped":false,"isBuiltin":false,"installedTimestamp":' + $now + ',"pinned":true,"source":"vsix"}}'

        $marker = '{"identifier":{"id":"kamaba.slang-vscode"'
        $start = $raw.IndexOf($marker)
        if ($start -ge 0) {
            $depth = 0
            $end = -1
            for ($i = $start; $i -lt $raw.Length; $i++) {
                $c = $raw[$i]
                if ($c -eq '{') { $depth++ }
                elseif ($c -eq '}') {
                    $depth--
                    if ($depth -eq 0) { $end = $i; break }
                }
            }
            if ($end -lt 0) { Fail 'cannot find the end of the slang entry in extensions.json' }
            $raw = $raw.Substring(0, $start) + $newEntry + $raw.Substring($end + 1)
        } else {
            $trimmed = $raw.TrimEnd()
            if ($trimmed -eq '[]') { $raw = '[' + $newEntry + ']' }
            else {
                if (-not $trimmed.EndsWith(']')) { Fail 'unexpected extensions.json shape (does not end with ])' }
                $raw = $trimmed.Substring(0, $trimmed.Length - 1) + ',' + $newEntry + ']'
            }
        }
        [System.IO.File]::WriteAllText($ej, $raw, (New-Object System.Text.UTF8Encoding($false)))
        Ok 'extensions.json registry updated'
    } finally {
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item $zip -Force -ErrorAction SilentlyContinue
    }
} else {
    Write-Host '  -SkipInstall: packages + vsix only (nothing installed)' -ForegroundColor Yellow
}

# ---- done ---------------------------------------------------------------------
Write-Host ''
Write-Host ('ALL DONE - version ' + $ver) -ForegroundColor Green
Write-Host '  packages : SlangAllInOne\package\{win32,linux}-{debug,release}'
Write-Host '  host     : SlangAllInOne\out\host\slang.exe (publish configs)'
Write-Host ('  vsix     : slang_vscode_plugin\' + $vsixName)
if (-not $SkipInstall) {
    Write-Host ('  installed: ' + $dst)
    Write-Host ''
    Write-Host 'NEXT (manual): reload the IDE window (Ctrl+Shift+P -> Reload Window),' -ForegroundColor Cyan
    Write-Host '               then verify the extension shows v' + $ver + ' and debug away.' -ForegroundColor Cyan
}
exit 0
