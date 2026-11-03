# preview-docs-web.ps1 — docs-web 一键预览：生成 + 本地静态服务器 + 打开浏览器
# 用法: powershell -File tools\docs-web\preview-docs-web.ps1 [-Port 8931] [-NoBuild]
param(
    [int]$Port = 8931,
    [switch]$NoBuild
)
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$repo = Resolve-Path (Join-Path $here '..\..')   # SlangAllInOne 根

if (-not $NoBuild) {
    node (Join-Path $here 'build-docs-web.js')
    if ($LASTEXITCODE -ne 0) { throw "build-docs-web.js 失败（exit $LASTEXITCODE）" }
}

$job = Start-Process node -ArgumentList "`"$(Join-Path $here 'serve.js')`"","$Port" -PassThru -WindowStyle Hidden
Start-Sleep -Milliseconds 800
$url = "http://127.0.0.1:$Port/"
Write-Host "[preview] $url  （服务器 PID=$($job.Id)，回车停止）"
try { Start-Process $url } catch { }
Read-Host | Out-Null
Stop-Process -Id $job.Id -Force -ErrorAction SilentlyContinue
Write-Host '[preview] 已停止'
