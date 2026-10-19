# release-slang.ps1 - One-click DUAL-PLATFORM Native AOT release (win-x64 + linux-x64).
#
# ★ Release channel policy (2026-10-17 user directive; authoritative doc:
#   SlangAllInOne\RELEASE.md):
#   - ONLY Native AOT packages are released - self-contained native binaries,
#     no .NET runtime needed on target machines. The classic .NET-dependent
#     debug packages (package\win32-debug / package\linux-debug) are local dev
#     tools only and are never released.
#   - EVERY release ships BOTH Windows and Linux packages as two assets of the
#     SAME GitHub Release: slang_release_<v>_win-x64.zip and
#     slang_release_<v>_linux-x64.tar.gz.
#
# Pipeline: preflight -> build win AOT package -> build linux AOT package (WSL)
#   -> layout checks -> off-tree smoke on BOTH platforms -> zip + tar.gz ->
#   git commit + tag + push -> GitHub Release with BOTH assets:
#   https://github.com/kamaba/SlangAllInOne/releases/tag/v<Version>
#
# 2026-10-18: the csproj now auto-AOTs Release publishes (dotnet publish -c
#   Release) and defaults the output dir to package\win32-release /
#   package\linux-release; the explicit -o / -r flags below stay for
#   determinism. Local four-package builds (no GitHub): build-packages.ps1.
#
# 2026-10-19: the release also ships the VSCode extension (.vsix) - copied
#   into BOTH archives under vsix\ AND attached as a third GitHub Release
#   asset. SOFT-FAIL by design: node missing / extension build failure only
#   warns and the release continues without it - the dual-platform main
#   line must never be aborted by the optional asset (authoritative design:
#   slang_vscode_plugin\09_packaging_release.md §3).
#
# Usage (workspace root, maintenance machine; Linux half needs WSL with
# clang/cmake/ninja/libsqlite3-dev + dotnet SDK - see RELEASE.md):
#   powershell -NoProfile -ExecutionPolicy Bypass -File SlangAllInOne\scripts\release-slang.ps1 -Version 0.0.3
#   powershell -NoProfile -ExecutionPolicy Bypass -File SlangAllInOne\scripts\release-slang.ps1 -Version 0.0.3 -Draft
#   powershell -NoProfile -ExecutionPolicy Bypass -File SlangAllInOne\scripts\release-slang.ps1 -Version 0.0.3 -SkipBuild  # re-zip existing packages
#   powershell -NoProfile -ExecutionPolicy Bypass -File SlangAllInOne\scripts\release-slang.ps1 -Version 0.0.3 -NoCommit  # refuse dirty worktree
#   powershell -NoProfile -ExecutionPolicy Bypass -File SlangAllInOne\scripts\release-slang.ps1 -Version 0.0.3 -NoPush    # stop after tag+archives
#
# Auth: token via -Token, else the one stored by git credential manager (the
# same token `git push` uses; needs scope "repo").
#
# Git policy (aligned with the repo's .gitignore "/package"):
#   - package\ build outputs are untracked on first run (git rm -r --cached);
#     binaries are distributed through GitHub Releases, not through git.
#   - dirty source files are committed as "release: slang_release <v>"
#     (use -NoCommit to abort instead).
param(
    [string]$Version = '',      # required, e.g. -Version 0.0.3
    [string]$Token = '',
    [switch]$SkipBuild,
    [switch]$Draft,
    [switch]$NoCommit,
    [switch]$NoPush
)

[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

# ---------- helpers ----------
function Write-Step([string]$Text) { Write-Host ''; Write-Host ('=== ' + $Text + ' ===') -ForegroundColor Cyan }
function Write-Ok([string]$Text)   { Write-Host ('  ' + $Text) -ForegroundColor Green }
function Fail([string]$Text)       { Write-Host ('FAIL: ' + $Text) -ForegroundColor Red; exit 1 }

# Windows path -> WSL path (/mnt/<drive>/...). Used for every WSL-side command.
function Convert-ToWslPath([string]$Path) {
    $p = $Path -replace '\\', '/'
    if ($p -match '^([A-Za-z]):/(.*)$') { $p = '/mnt/' + $Matches[1].ToLower() + '/' + $Matches[2] }
    return $p.TrimEnd('/')
}

# Run one bash command line inside WSL and return ONLY its exit code (int).
# NOTE 1: wsl.exe re-splits arguments, so the command must be a single token
#         stream WITHOUT embedded double quotes or parentheses - build it
#         with PS interpolation only (this is why every $cmd below is quote-free).
# NOTE 2: stdout is piped to Out-Host - it must NOT flow into the function's
#         return value. The first dual-platform run failed exactly here:
#         a command with stdout (which cmake ...) made the function return
#         [output..., exitcode] - an ARRAY - and the call sites' -ne 0 checks
#         compared array-vs-int, failing every check despite exit 0.
function Invoke-WslBash([string]$Cmd) {
    & wsl bash -c $Cmd | Out-Host
    $code = $LASTEXITCODE
    if ($code -ne 0) {
        # one retry after a short pause smooths WSL1 spawn hiccups; every call
        # site is an idempotent re-runnable step (cmake/dotnet/cp/tar)
        Start-Sleep -Seconds 2
        & wsl bash -c $Cmd | Out-Host
        $code = $LASTEXITCODE
        if ($code -ne 0) { Write-Host ("  [wsl exit " + $code + "] " + $Cmd) -ForegroundColor Yellow }
    }
    return $code
}

# ---------- paths / names ----------
# Scripts now live in SlangAllInOne\scripts\ (inside the git repo) but were
# originally written for <workspace>\scripts\. The workspace root is the
# directory that contains csimple_lang - detect which layout we are in.
$RepoRoot     = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path (Join-Path $RepoRoot 'csimple_lang'))) {
    $RepoRoot = Split-Path -Parent $RepoRoot   # script sits in SlangAllInOne\scripts\
}
$AioDir       = Join-Path $RepoRoot 'SlangAllInOne'
$ProjFile     = Join-Path $AioDir 'SlangAllInOne.csproj'
$PkgWinDir    = Join-Path $AioDir 'package\win32-release'   # Windows AOT package
$PkgLinuxDir  = Join-Path $AioDir 'package\linux-release'   # Linux AOT package
$DistDir      = Join-Path $AioDir 'package\dist'
$WslRepo      = Convert-ToWslPath $RepoRoot
$WslPkgWin    = Convert-ToWslPath $PkgWinDir
$WslPkgLinux  = Convert-ToWslPath $PkgLinuxDir
$WslDistDir   = Convert-ToWslPath $DistDir
$Tag          = "v$Version"
$RelTitle     = "slang_release $Version"
$StageName    = "slang_release_$Version"               # top folder inside both archives
$ZipName      = "slang_release_${Version}_win-x64.zip"
$TgzName      = "slang_release_${Version}_linux-x64.tar.gz"
$ZipPath      = Join-Path $DistDir $ZipName
$TgzPath      = Join-Path $DistDir $TgzName
# Slang for VSCode extension (optional third asset; see header comment 2026-10-19)
$VscodePluginDir = Join-Path $RepoRoot 'slang_vscode_plugin'
$VsixPath     = $null
$sizeVsix     = 0

# =====================================================================
Write-Step 'Preflight'
# =====================================================================

if (-not $Version) { Fail 'pass -Version <x.y.z> (e.g. -Version 0.0.3)' }
if (-not (Test-Path $ProjFile)) { Fail "project not found: $ProjFile" }
if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) { Fail 'dotnet not found (.NET SDK 8+ required)' }

# git repo + remote -> owner/repo (2>&1 so git's own error text reaches Fail())
if (-not (Test-Path (Join-Path $AioDir '.git'))) { Fail "not a git repo: $AioDir" }
Push-Location $AioDir
$remoteOut = @((git remote get-url origin 2>&1) | ForEach-Object { "$_" })
if ($LASTEXITCODE -ne 0 -or $remoteOut.Count -eq 0) {
    Pop-Location
    Fail ('git remote get-url origin failed in SlangAllInOne: ' + ($remoteOut -join ' | '))
}
$remoteUrl = @($remoteOut | Where-Object { $_ -match 'github\.com' }) | Select-Object -First 1
if (-not $remoteUrl) { Pop-Location; Fail ('origin is not a GitHub remote: ' + ($remoteOut -join ' | ')) }
$OwnerRepo = $null
if ("$remoteUrl" -match 'github\.com[/:]([^/]+)/([^/]+?)(\.git)?$') { $OwnerRepo = $Matches[1] + '/' + $Matches[2] }
if (-not $OwnerRepo) { Pop-Location; Fail "cannot parse owner/repo from: $remoteUrl" }

# token: -Token > git credential manager
if (-not $Token) {
    $env:GIT_TERMINAL_PROMPT = '0'   # never prompt - fail instead of hanging
    $env:GCM_INTERACTIVE = 'never'   # Git Credential Manager: no GUI popup
    # NOTE: under `powershell -File` piping a string into a native command's
    # stdin is unreliable (git sees an empty stream -> "missing protocol
    # field"), so feed git through Start-Process file redirections instead.
    $gitExe = (Get-Command git -ErrorAction SilentlyContinue).Source
    if (-not $gitExe) { Pop-Location; Fail 'git not found in PATH' }
    $credIn  = Join-Path $env:TEMP 'slang-release-cred-in.txt'
    $credOut = Join-Path $env:TEMP 'slang-release-cred-out.txt'
    $credErr = Join-Path $env:TEMP 'slang-release-cred-err.txt'
    [IO.File]::WriteAllText($credIn, "protocol=https`nhost=github.com`n`n")
    $p = Start-Process -FilePath $gitExe -ArgumentList 'credential','fill' -NoNewWindow -Wait -PassThru `
            -RedirectStandardInput $credIn -RedirectStandardOutput $credOut -RedirectStandardError $credErr
    $cred   = @(Get-Content $credOut -ErrorAction SilentlyContinue)
    $errTxt = (@(Get-Content $credErr -ErrorAction SilentlyContinue)) -join ' | '
    Remove-Item $credIn, $credOut, $credErr -Force -Confirm:$false -ErrorAction SilentlyContinue
    $line = @($cred | Where-Object { $_ -like 'password=*' }) | Select-Object -First 1
    if (-not $line) {
        Pop-Location
        Fail ('no GitHub token from git credential manager (' + $errTxt + '). Pass -Token <token> or do one HTTPS git push to store it.')
    }
    $Token = $line.Substring(9)
}

$headers = @{ Authorization = "Bearer $Token"; 'User-Agent' = 'slang-release-script'; Accept = 'application/vnd.github+json' }

# local tag must not exist yet
git rev-parse -q --verify "refs/tags/$Tag" 2>$null | Out-Null
if ($LASTEXITCODE -eq 0) { Pop-Location; Fail "local tag $Tag already exists (bump -Version, or git tag -d $Tag)" }

# remote: token works, repo reachable, tag & release both free
try   { $me = Invoke-RestMethod -Uri 'https://api.github.com/user' -Headers $headers -ErrorAction Stop }
catch { Pop-Location; Fail ('token rejected by api.github.com: ' + $_.Exception.Message) }
try   { Invoke-RestMethod -Uri "https://api.github.com/repos/$OwnerRepo" -Headers $headers -ErrorAction Stop | Out-Null }
catch { Pop-Location; Fail "token cannot access repo $OwnerRepo (needs scope 'repo')" }
$remoteTag = $false
try { Invoke-RestMethod -Uri "https://api.github.com/repos/$OwnerRepo/git/refs/tags/$Tag" -Headers $headers -ErrorAction Stop | Out-Null; $remoteTag = $true } catch { }
$remoteRel = $false
try { Invoke-RestMethod -Uri "https://api.github.com/repos/$OwnerRepo/releases/tags/$Tag" -Headers $headers -ErrorAction Stop | Out-Null; $remoteRel = $true } catch { }
if ($remoteTag -or $remoteRel) { Pop-Location; Fail "tag/release $Tag already exists on $OwnerRepo" }

# WSL (Linux half): presence + toolchain + dotnet SDK
if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) { Pop-Location; Fail 'wsl.exe not found - the Linux half needs WSL (see RELEASE.md)' }
if ((Invoke-WslBash 'true') -ne 0) { Pop-Location; Fail 'WSL not usable (wsl bash -c true failed)' }
if ((Invoke-WslBash 'which cmake clang ninja') -ne 0) {
    Pop-Location; Fail 'WSL toolchain incomplete - install clang + cmake + ninja (+ libsqlite3-dev), see scripts\build-vm-linux.ps1 header'
}
if ((Invoke-WslBash 'dotnet --version') -ne 0) {
    Write-Host '  dotnet missing in WSL - trying apt install dotnet-sdk-10.0...' -ForegroundColor Yellow
    $null = Invoke-WslBash 'sudo -n apt-get install -y dotnet-sdk-10.0'
    if ((Invoke-WslBash 'dotnet --version') -ne 0) { Pop-Location; Fail 'WSL dotnet SDK unavailable - install dotnet-sdk-10.0 (or newer) inside WSL, see RELEASE.md' }
}
Write-Ok "repo   : $OwnerRepo (token user: $($me.login))"
Write-Ok "target : tag $Tag / release '$RelTitle' / assets $ZipName + $TgzName"
Pop-Location

# =====================================================================
Write-Step 'Build Windows AOT package (dotnet publish -r win-x64)'
# =====================================================================
if ($SkipBuild) {
    Write-Host '  -SkipBuild: reusing the existing package\win32-release tree' -ForegroundColor Yellow
} else {
    # Pre-wipe the package dir: the csproj WipeReleasePackage should cover this,
    # but AOT publishes showed stale-file anomalies (a pdb once survived both
    # Wipe and Trim with exit 0) - clean here so the zip can never inherit
    # stale files from a previous publish.
    if (Test-Path $PkgWinDir) { Remove-Item $PkgWinDir -Recurse -Force -Confirm:$false }
    Push-Location $RepoRoot
    # -c Release alone now implies PublishAot + win-x64 RID + this output dir
    # (csproj 2026-10-18); the explicit flags stay for determinism.
    & dotnet publish $ProjFile -c Release -r win-x64 -o $PkgWinDir
    $code = $LASTEXITCODE
    Pop-Location
    if ($code -ne 0) { Fail 'dotnet publish (win-x64) failed (see log above)' }
    # 2026-10-18 user directive: release packages no longer bundle the test\
    # example (test\RefProbe was removed from v0.0.5 on - the package ships
    # only slang.exe + bin\ + lib\ + md\; examples stay in the repo test tree).
    Write-Ok 'publish ok (Native AOT single-file slang.exe + hardened C VM + stdlib modules + docs)'
}
Write-Ok 'windows package built'

# =====================================================================
Write-Step 'Build Linux AOT package (WSL: C VM .so + dotnet publish -r linux-x64)'
# =====================================================================
if ($SkipBuild) {
    Write-Host '  -SkipBuild: reusing the existing package\linux-release tree' -ForegroundColor Yellow
} else {
    # a) Linux C VM runtime (incremental cmake, hardened Release with the JIT
    #    compiled in and ON by default; the SHARED library lands in
    #    build/ReleaseLinux/ - CMAKE_LIBRARY_OUTPUT_DIRECTORY is unset so only
    #    the exe target goes to bin\). -DVM_JIT_ENABLE=ON pins the JIT against
    #    older CMake caches holding the pre-2026-10-17 default OFF.
    Write-Host '  building libcsimple_lang_dll.so (cmake Release + SLVM_HARDEN=ON + VM_JIT_ENABLE=ON)...'
    $cmd = 'cd ' + $WslRepo + '/csimple_lang && cmake -S . -B build/ReleaseLinux -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER=clang -DCMAKE_MAKE_PROGRAM=/usr/bin/ninja -DCMAKE_RUNTIME_OUTPUT_DIRECTORY=' + $WslRepo + '/csimple_lang/build/ReleaseLinux/bin -DSLVM_HARDEN=ON -DVM_JIT_ENABLE=ON && cmake --build build/ReleaseLinux --target csimple_lang_dll -j8'
    if ((Invoke-WslBash $cmd) -ne 0) { Fail 'Linux C VM build failed (see log above)' }
    Write-Ok 'libcsimple_lang_dll.so built (JIT compiled in, on by default)'

    # b) Native AOT publish (linux-x64). The csproj pack targets are gated off
    #    for linux RIDs (build-vm-win.ps1 / Windows-PE bootstrap would fail),
    #    so this produces ONLY the native slang binary.
    if (Test-Path $PkgLinuxDir) { Remove-Item $PkgLinuxDir -Recurse -Force -Confirm:$false }
    Write-Host '  dotnet publish -c Release (Native AOT, ILC)...'
    $cmd = 'cd ' + $WslRepo + ' && dotnet publish SlangAllInOne/SlangAllInOne.csproj -c Release -r linux-x64 -o ' + $WslPkgLinux
    if ((Invoke-WslBash $cmd) -ne 0) { Fail 'linux-x64 AOT publish failed (see log above)' }
    Write-Ok 'slang (linux-x64 AOT) published'

    # c) assemble bin\: the C VM .so + bundled system sqlite
    #    (CMake links system sqlite3 on Linux -> ship libsqlite3.so.0 with the
    #     package; CvmBackend pre-loads it so no LD_LIBRARY_PATH is needed)
    $cmd = 'mkdir -p ' + $WslPkgLinux + '/bin && cp ' + $WslRepo + '/csimple_lang/build/ReleaseLinux/libcsimple_lang_dll.so ' + $WslPkgLinux + '/bin/ && cp /usr/lib/x86_64-linux-gnu/libsqlite3.so.0 ' + $WslPkgLinux + '/bin/'
    if ((Invoke-WslBash $cmd) -ne 0) { Fail 'linux bin assembly failed (libsqlite3.so.0 not found?)' }
    Write-Ok 'bin assembled (libcsimple_lang_dll.so + libsqlite3.so.0)'

    # d) lib\ + md\ are platform-independent content - copy from the
    #    Windows package (built above; the win pack-modules compiled them).
    #    lib\ = system built-in stdlib (renamed from module\, 2026-10-18 -
    #    see md\project\package-layout.md; modules\ (spm) / plugins\ are
    #    created on demand by the future package/plugin managers).
    robocopy (Join-Path $PkgWinDir 'lib') (Join-Path $PkgLinuxDir 'lib') /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) { Fail 'robocopy lib\ (win -> linux package) failed' }
    robocopy (Join-Path $PkgWinDir 'md') (Join-Path $PkgLinuxDir 'md') /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) { Fail 'robocopy md\ (win -> linux package) failed' }
    # math_lib.dll is a Windows PE - Math FFI is a documented Linux limitation,
    # do not ship a dead binary in the linux package.
    $mathLib = Join-Path $PkgLinuxDir 'lib\math_lib.dll'
    if (Test-Path $mathLib) { Remove-Item $mathLib -Force -Confirm:$false }
    Write-Ok 'lib\ + md\ copied from the Windows package (math_lib.dll excluded)'
}
Write-Ok 'linux package built'

# =====================================================================
Write-Step 'VSCode extension (.vsix) - optional third asset, SOFT-FAIL'
# =====================================================================
# Design (slang_vscode_plugin\09_packaging_release.md §3): build once on the
# Windows side, copy into BOTH package roots under vsix\ (the win zip is
# robocopy /MIR-staged and the linux tar cp -r's the whole package dir, so
# both archives pick vsix\ up automatically) and attach as a third GitHub
# Release asset later. Any failure here only WARNS - the dual-platform main
# line never aborts on the optional asset.
try {
    if (-not (Test-Path (Join-Path $VscodePluginDir 'package.json'))) { throw 'slang_vscode_plugin\package.json not found' }
    $pluginPkg = Get-Content (Join-Path $VscodePluginDir 'package.json') -Raw | ConvertFrom-Json
    $pluginVer = "$($pluginPkg.version)"
    if ($pluginVer -ne $Version) {
        Write-Host "  WARNING: plugin version $pluginVer != release version $Version - shipping anyway (alignment policy: 09_packaging_release.md §2)" -ForegroundColor Yellow
    }
    # release naming family slang_vscode_<v>.vsix (vsce's natural name uses a dash)
    $VsixName  = "slang_vscode_$pluginVer.vsix"
    $builtVsix = Join-Path $VscodePluginDir $VsixName

    $needBuild = $true
    if ($SkipBuild -and (Test-Path $builtVsix)) {
        $needBuild = $false
        Write-Host '  -SkipBuild: reusing the existing .vsix' -ForegroundColor Yellow
    }
    if ($needBuild) {
        if (-not (Get-Command node -ErrorAction SilentlyContinue)) { throw 'node not found in PATH' }
        Push-Location $VscodePluginDir
        try {
            if (-not (Test-Path 'node_modules')) {
                & npm install --no-audit --no-fund
                if ($LASTEXITCODE -ne 0) { throw 'npm install failed' }
            }
            if (Test-Path $builtVsix) { Remove-Item $builtVsix -Force -Confirm:$false }
            # vscode:prepublish (package.json) makes this self-contained:
            # tsc + esbuild run inside vsce before bundling
            & npx vsce package --no-dependencies
            if ($LASTEXITCODE -ne 0) { throw 'vsce package failed' }
            $vsceName = "slang-vscode-$pluginVer.vsix"   # vsce natural name uses dashes
            if ((Test-Path $vsceName) -and $vsceName -ne $VsixName) {
                Move-Item $vsceName $VsixName -Force
            }
            if (-not (Test-Path $builtVsix)) { throw "expected .vsix not produced: $builtVsix" }
        } finally { Pop-Location }
    }
    $VsixPath  = $builtVsix
    $sizeVsix  = [math]::Round((Get-Item $VsixPath).Length / 1KB, 1)
    foreach ($pkg in @($PkgWinDir, $PkgLinuxDir)) {
        New-Item -ItemType Directory -Path (Join-Path $pkg 'vsix') -Force | Out-Null
        Copy-Item $VsixPath (Join-Path $pkg 'vsix') -Force
    }
    Write-Ok "vsix built: $VsixName ($sizeVsix KB) -> vsix\ in both packages"
} catch {
    $VsixPath = $null
    Write-Host "  WARNING: VSCode extension not shipped ($_)" -ForegroundColor Yellow
}

# =====================================================================
Write-Step 'Layout checks'
# =====================================================================
# 2026-10-18 user directive: licenses\ no longer ships in any package
# (csproj PackThirdPartyLicenses removed); the license texts' source of
# truth stays in the repo at csimple_lang\third_party\LICENSES\.
foreach ($must in @(
    'slang.exe', 'bin\csimple_lang_dll.dll', 'bin\sqlite3.dll',
    'lib\Core.module.slb', 'lib\Math.module.slb', 'lib\Std.module.slb', 'lib\math_lib.dll'
)) {
    if (-not (Test-Path (Join-Path $PkgWinDir $must))) { Fail "windows package incomplete, missing: $must (build without -SkipBuild)" }
}
foreach ($must in @(
    'slang', 'bin\libcsimple_lang_dll.so', 'bin\libsqlite3.so.0',
    'lib\Core.module.slb', 'lib\Math.module.slb', 'lib\Std.module.slb'
)) {
    if (-not (Test-Path (Join-Path $PkgLinuxDir $must))) { Fail "linux package incomplete, missing: $must (build without -SkipBuild)" }
}
# Managed artifacts would mean the wrong (classic) publish ran - hard fail.
# (Bare "SimpleLanguageFront" = the Linux apphost, same dead weight as the exe.)
foreach ($forbidden in @(
    'slang.dll', 'slang.deps.json', 'slang.runtimeconfig.json',
    'SimpleLanguageFront.exe', 'SimpleLanguageFront.dll', 'SimpleLanguageFront'
)) {
    if (Test-Path (Join-Path $PkgWinDir $forbidden))   { Fail "windows AOT package must not contain: $forbidden (run the AOT publish, not the classic one)" }
    if (Test-Path (Join-Path $PkgLinuxDir $forbidden)) { Fail "linux AOT package must not contain: $forbidden (run the AOT publish, not the classic one)" }
}
# slang.pdb is NOT a wrong-publish signal: the Native AOT incremental obj cache
# resurrects the stale ~50MB native pdb into the publish dir even with the
# csproj's DebugType=none (reproduced twice on 2026-10-17; csproj Wipe/Trim both
# fail to keep it out). Delete it here as the final guard so neither archive
# ever ships debug symbols.
foreach ($stalePdb in @((Join-Path $PkgWinDir 'slang.pdb'), (Join-Path $PkgLinuxDir 'slang.pdb'))) {
    if (Test-Path $stalePdb) {
        Remove-Item $stalePdb -Force -Confirm:$false
        if (Test-Path $stalePdb) { Fail "cannot remove stale AOT pdb: $stalePdb" }
        Write-Host "  removed stale AOT debug symbols: $stalePdb" -ForegroundColor Yellow
    }
}
Write-Ok 'both package layouts ok (self-contained native slang only)'

# =====================================================================
Write-Step 'Smoke test (both platforms, off-tree)'
# =====================================================================
# Run from a temp dir so the VM's build\logs never pollute the package trees.

# --- Windows: bundled stdlib loads and runs ---
$smokeDir = Join-Path $env:TEMP ('slang-release-smoke-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $smokeDir -Force | Out-Null
$slangExe = Join-Path $PkgWinDir 'slang.exe'
$smokeFail = $false
Push-Location $smokeDir
foreach ($m in @('Std', 'Math')) {
    & $slangExe run-disk (Join-Path $PkgWinDir "lib\$m.module.slb")
    if ($LASTEXITCODE -ne 0) {
        $smokeFail = $true
        Write-Host "  win $m.module.slb exit $LASTEXITCODE" -ForegroundColor Red
        break
    }
    Write-Ok "win $m.module.slb exit 0"
}
Pop-Location
Remove-Item $smokeDir -Recurse -Force -Confirm:$false -ErrorAction SilentlyContinue
if ($smokeFail) { Fail 'Windows smoke test failed - release aborted' }

# --- Linux (WSL): module load + Front compile-and-run (packaged user flow) ---
$cmd = 'rm -rf /tmp/slang-release-smoke && mkdir -p /tmp/slang-release-smoke && cd /tmp/slang-release-smoke && ' + $WslPkgLinux + '/slang run-disk ' + $WslPkgLinux + '/lib/Std.module.slb --no-banner'
if ((Invoke-WslBash $cmd) -ne 0) { Fail 'Linux Std.module.slb smoke failed (see log above)' }
Write-Ok 'linux Std.module.slb exit 0'
# Front compile-to-run end to end: in-process Front compile -> C VM run, the
# exact flow a Linux user exercises with `slang run <project>`.
# SL_FORCE_RUN=1: test jsonc platform checks are hardcoded win64 (known repo
# policy, AGENTS.md "Known expected differences") - Linux runs skip the check.
# 2026-10-18: MiniSmoke moved with the test tree reorg (2026-10-17) from
# simple_language\test\ to SlangAllInOne\SLangCore\test\ (same fix as RefProbe).
$cmd = 'cd ' + $WslRepo + ' && SL_FORCE_RUN=1 ' + $WslPkgLinux + '/slang run SlangAllInOne/SLangCore/test/Other/MiniSmoke/MiniSmoke --no-banner'
if ((Invoke-WslBash $cmd) -ne 0) { Fail 'Linux MiniSmoke compile-and-run failed (see log above)' }
Write-Ok 'linux MiniSmoke compile-and-run exit 0'

# =====================================================================
Write-Step "Archive -> $ZipName + $TgzName"
# =====================================================================
New-Item -ItemType Directory -Path $DistDir -Force | Out-Null
# VM run leaves a build\logs dir when invoked from the package dir - never archive it
if (Test-Path (Join-Path $PkgWinDir 'build'))   { Remove-Item (Join-Path $PkgWinDir 'build') -Recurse -Force -Confirm:$false }
if (Test-Path (Join-Path $PkgLinuxDir 'build')) { Remove-Item (Join-Path $PkgLinuxDir 'build') -Recurse -Force -Confirm:$false }

# Windows zip (staged under the top-level folder)
$StageWin = Join-Path $DistDir $StageName
if (Test-Path $StageWin) { Remove-Item $StageWin -Recurse -Force -Confirm:$false }
if (Test-Path $ZipPath)  { Remove-Item $ZipPath -Force -Confirm:$false }
New-Item -ItemType Directory -Path $StageWin -Force | Out-Null
robocopy $PkgWinDir $StageWin /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
if ($LASTEXITCODE -ge 8) { Fail 'robocopy staging (win) failed' }
Compress-Archive -Path $StageWin -DestinationPath $ZipPath
Remove-Item $StageWin -Recurse -Force -Confirm:$false

# Linux tar.gz (staged + tarred INSIDE WSL so the unix exec bits survive)
if (Test-Path $TgzPath) { Remove-Item $TgzPath -Force -Confirm:$false }
$cmd = 'cd ' + $WslDistDir + ' && rm -rf ' + $StageName + ' && mkdir ' + $StageName + ' && cp -r ' + $WslPkgLinux + '/. ' + $StageName + '/ && tar -czf ' + $TgzName + ' ' + $StageName + ' && rm -rf ' + $StageName
if ((Invoke-WslBash $cmd) -ne 0) { Fail 'linux tar.gz staging failed (see log above)' }

$sizeZip = [math]::Round((Get-Item $ZipPath).Length / 1MB, 1)
$sizeTgz = [math]::Round((Get-Item $TgzPath).Length / 1MB, 1)
$shaZip  = (Get-FileHash $ZipPath -Algorithm SHA256).Hash
$shaTgz  = (Get-FileHash $TgzPath -Algorithm SHA256).Hash
Write-Ok "win zip  : $ZipPath ($sizeZip MB)"
Write-Ok "linux tgz: $TgzPath ($sizeTgz MB)"
Write-Ok "sha256   : zip $shaZip"
Write-Ok "sha256   : tgz $shaTgz"

# =====================================================================
Write-Step 'Git: release commit + tag'
# =====================================================================
Push-Location $AioDir
$branch = @((git rev-parse --abbrev-ref HEAD 2>&1) | ForEach-Object { "$_" }) -join ''
if ($LASTEXITCODE -ne 0 -or -not $branch) { Pop-Location; Fail "cannot resolve the current branch ($branch)" }

# One-time cleanup: .gitignore already declares /package, but files committed
# before that rule are still tracked. Untrack them - binaries are distributed
# through GitHub Releases from now on, release commits stay source-only.
$trackedPkg = @(git ls-files -- package)
if ($trackedPkg.Count -gt 0) {
    Write-Host "  untracking $($trackedPkg.Count) build-output file(s) under package\ (gitignored; binaries ship via GitHub Releases)" -ForegroundColor Yellow
    git rm -r -q --cached -- package | Out-Null
    if ($LASTEXITCODE -ne 0) { Pop-Location; Fail 'git rm -r --cached package failed' }
}

$dirty = @(git status --porcelain)
if ($dirty.Count -gt 0) {
    if ($NoCommit) {
        Pop-Location
        $nl = [Environment]::NewLine
        Fail ('worktree is dirty and -NoCommit given:' + $nl + '  ' + ($dirty -join ($nl + '  ')))
    }
    Write-Host '  committing:'
    $show = $dirty
    if ($show.Count -gt 15) { $show = @($show[0..14]) + "... (+$($dirty.Count - 15) more)" }
    $show | ForEach-Object { Write-Host ('    ' + $_) }
    git add -A | Out-Null
    if ($LASTEXITCODE -ne 0) { Pop-Location; Fail 'git add failed' }
    git commit -m "release: $RelTitle" | Out-Null
    if ($LASTEXITCODE -ne 0) { Pop-Location; Fail 'git commit failed' }
    Write-Ok "committed as 'release: $RelTitle'"
} else {
    Write-Ok 'worktree clean, nothing to commit'
}

git tag -a $Tag -m $RelTitle
if ($LASTEXITCODE -ne 0) { Pop-Location; Fail "git tag $Tag failed" }
Write-Ok "tagged $Tag"
Pop-Location

if ($NoPush) {
    Write-Step 'Done (local only, -NoPush)'
    Write-Host "  tag    : $Tag (NOT pushed, no GitHub release created)"
    Write-Host "  win zip: $ZipPath ($sizeZip MB)"
    Write-Host "  linux  : $TgzPath ($sizeTgz MB)"
    if ($VsixPath) { Write-Host "  vscode : $VsixPath ($sizeVsix KB, in both archives vsix\)" }
    exit 0
}

# =====================================================================
Write-Step 'Push'
# =====================================================================
Push-Location $AioDir
git push origin $branch
if ($LASTEXITCODE -ne 0) { Pop-Location; Fail "git push origin $branch failed (hint: git pull --rebase origin $branch)" }
git push origin $Tag
if ($LASTEXITCODE -ne 0) { Pop-Location; Fail "git push origin $Tag failed" }
Pop-Location
Write-Ok "pushed $branch + $Tag"

# =====================================================================
Write-Step "GitHub release $Tag on $OwnerRepo (both assets)"
# =====================================================================
$vsixLine = ''
if ($VsixPath) {
    $vsixLine = "- $(Split-Path -Leaf $VsixPath) : Slang for VSCode extension (also inside both archives under vsix\; install: code --install-extension)"
}
$notes = @"
$RelTitle - dual-platform self-contained packages (Native AOT; no .NET runtime needed on the target machine).

Contents (both packages share one layout: slang CLI + bin\ C VM runtime + lib\ system stdlib + md\ user docs)
- slang_release_${Version}_win-x64.zip      : slang.exe + csimple_lang_dll.dll + sqlite3.dll + math_lib.dll
- slang_release_${Version}_linux-x64.tar.gz : slang + libcsimple_lang_dll.so + libsqlite3.so.0
$vsixLine

Quick start (unzip/untar anywhere)
  slang run-disk lib\Std.module.slb
  slang run <project>       # compile-and-run; project jsonc references point to lib\

Requirements
- win-x64 : Windows x64
- linux-x64: x86-64 Linux with glibc >= 2.43 (built on Ubuntu 25.10)

Known Linux limitations
- Math FFI unavailable (math_lib is Windows-only); Math module itself loads.
- Windows-only plugins (csharp_mono) not available.

Notes
- User modules must be compiled against the bundled stdlib (reference uuid check on load).
- Assets: $ZipName ($sizeZip MB, sha256 $shaZip) / $TgzName ($sizeTgz MB, sha256 $shaTgz)
"@
$payload = @{ tag_name = $Tag; name = $RelTitle; body = $notes; draft = [bool]$Draft; prerelease = $false } | ConvertTo-Json
try { $rel = Invoke-RestMethod -Method Post -Uri "https://api.github.com/repos/$OwnerRepo/releases" -Headers $headers -ContentType 'application/json' -Body $payload -ErrorAction Stop }
catch { Fail ('create release failed: ' + $_.Exception.Message) }
$uploadZip = "https://uploads.github.com/repos/$OwnerRepo/releases/$($rel.id)/assets?name=$ZipName"
try { $null = Invoke-RestMethod -Method Post -Uri $uploadZip -Headers $headers -ContentType 'application/zip' -InFile $ZipPath -ErrorAction Stop }
catch { Fail ('win zip upload failed: ' + $_.Exception.Message + " (release exists, attach manually: " + $rel.html_url + ")") }
$uploadTgz = "https://uploads.github.com/repos/$OwnerRepo/releases/$($rel.id)/assets?name=$TgzName"
try { $null = Invoke-RestMethod -Method Post -Uri $uploadTgz -Headers $headers -ContentType 'application/gzip' -InFile $TgzPath -ErrorAction Stop }
catch { Fail ('linux tgz upload failed: ' + $_.Exception.Message + " (release exists, attach manually: " + $rel.html_url + ")") }

# optional third asset: VSCode extension - a failure here only warns (soft)
if ($VsixPath) {
    $uploadVsix = "https://uploads.github.com/repos/$OwnerRepo/releases/$($rel.id)/assets?name=$(Split-Path -Leaf $VsixPath)"
    try {
        $null = Invoke-RestMethod -Method Post -Uri $uploadVsix -Headers $headers -ContentType 'application/octet-stream' -InFile $VsixPath -ErrorAction Stop
        Write-Ok "vsix uploaded (third asset: $(Split-Path -Leaf $VsixPath))"
    } catch {
        Write-Host ('  WARNING: vsix upload failed - attach manually: ' + $rel.html_url) -ForegroundColor Yellow
    }
} else {
    Write-Host '  vsix skipped (not built in this run)' -ForegroundColor Yellow
}

# =====================================================================
Write-Step 'Done'
# =====================================================================
Write-Host "  version : $Version (tag $Tag)"
Write-Host "  win zip : $ZipPath ($sizeZip MB, sha256 $shaZip)"
Write-Host "  linux   : $TgzPath ($sizeTgz MB, sha256 $shaTgz)"
if ($VsixPath) { Write-Host "  vscode  : $VsixPath ($sizeVsix KB, in both archives vsix\ + third asset)" }
Write-Host "  release : $($rel.html_url)"
if ($Draft) { Write-Host '  draft release - publish it on the GitHub releases page when ready' -ForegroundColor Yellow }
exit 0
