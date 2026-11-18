# dbg-cycle.ps1 - rebuild sl_render_lib.dll and push it to every slot the
# RenderTest runtime may load from (export + zip + installed dir), then run.
param([switch]$Run = $true)
$ErrorActionPreference = "Stop"
$root = "D:\project\lang\SlangAllInOne"
$msbuild = "C:\Program Files\Microsoft Visual Studio\18\Community\MSBuild\Current\Bin\MSBuild.exe"
$proj = "$root\SLangCore\Lib\SLang\Render\cvm_render_lib\cvm_sl_render_lib.vcxproj"
$exp  = "$root\out\export\SLangRender"
$test = "$root\SLangCore\test\RenderTest"

& $msbuild $proj /nologo /v:m /p:Configuration=Debug /p:Platform=x64 | Out-Null
if ($LASTEXITCODE -ne 0) { throw "build failed" }
Copy-Item "$root\SLangCore\Lib\SLang\Render\cvm_render_lib\x64\Debug\sl_render_lib.dll" "$exp\sl_render_lib.dll" -Force

$stage = "$root\out\tmp_sr_zip"
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item -ItemType Directory -Force -Path $stage | Out-Null
Copy-Item "$exp\SLangRender.module.json","$exp\SLangRender.module.slb","$exp\sl_render_lib.dll" $stage -Force
Compress-Archive -Path "$stage\*" -DestinationPath "$test\modules\SLangRender.zip" -Force
Copy-Item "$stage\*" "$test\modules\SLangRender\" -Force
Copy-Item "$stage\*" "$root\package\win32-debug\modules\SLangRender\" -Force
Compress-Archive -Path "$stage\*" -DestinationPath "$root\package\win32-debug\modules\SLangRender.zip" -Force
Remove-Item $stage -Recurse -Force
Write-Host "pushed dll -> export/zip/installed"

if ($Run) {
    Push-Location $test
    $ErrorActionPreference = "Continue"
    cmd /c "`"$root\out\cli-release\slang.exe`" run `".\export\RenderTest\RenderTest.module.slb`" --no-banner > `"$root\out\rt_dbg.log`" 2>&1"
    $ec = $LASTEXITCODE
    Pop-Location
    Write-Host "RT exit=$ec"
    Get-Content "$root\out\rt_dbg.log" | Select-String -SimpleMatch "[dbg]" | Select-Object -Last 20 | ForEach-Object { $_.Line }
    Get-Content "$root\out\rt_dbg.log" -Tail 6
}
