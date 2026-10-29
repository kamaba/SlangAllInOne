# Run VM WebUITest with precise process lifetime tracking
$vm='D:\project\lang\SlangAllInOne\package\win32-release\bin\csimple_lang.exe'
$mod='D:\project\lang\SlangAllInOne\package\win32-release\WebUITest\WebUITest.module.slb'
$out='D:\project\lang\SlangAllInOne\out\tmp_webui_vm_log2.txt'
$err='D:\project\lang\SlangAllInOne\out\tmp_webui_vm_err2.txt'
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$p = Start-Process -FilePath $vm -ArgumentList 'run',"`"$mod`"" -WorkingDirectory 'D:\project\lang\SlangAllInOne\package\win32-release' -RedirectStandardOutput $out -RedirectStandardError $err -PassThru -WindowStyle Hidden
Write-Host ("t={0,3}s started pid={1}" -f 0, $p.Id)
for ($i = 1; $i -le 45; $i++) {
    Start-Sleep -Seconds 2
    if ($p.HasExited) {
        Write-Host ("t={0,3}s process EXITED code={1}" -f ($sw.Elapsed.TotalSeconds -as [int]), $p.ExitCode)
        break
    }
    Write-Host ("t={0,3}s alive" -f ($sw.Elapsed.TotalSeconds -as [int]))
}
if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force; Write-Host "killed at t=$([int]$sw.Elapsed.TotalSeconds)s" }
