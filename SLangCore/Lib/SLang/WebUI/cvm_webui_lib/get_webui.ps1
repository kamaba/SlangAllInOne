# ============================================================================
# get_webui.ps1 —— 拉取 webui 上游源码（MIT v2.5.0-beta.4）并切换 vcxproj 到真实源码
# ----------------------------------------------------------------------------
# 运行环境需可访问 GitHub raw（大文件/多文件批量下载对网络稳定性敏感，
# 建议在稳定网络环境执行；成功后 webui_lib.dll 即具备真实 GUI 能力）。
#
#   cd SlangAllInOne\SLangCore\Lib\SLang\WebUI\cvm_webui_lib
#   powershell -ExecutionPolicy Bypass -File get_webui.ps1
#
# 抓取清单（按 webui 仓库目录结构落地，保证 webui.c 的相对 include 可解析）：
#   include/webui.h       -> .\webui.h
#   src/webui.c           -> .\src\webui.c
#   bridge/webui_bridge.h -> .\bridge\webui_bridge.h  （头文件内聚实现，无 .c）
#   src/civetweb/*        -> .\src\civetweb\          （8 个文件：civetweb.h/.c +
#     handle_form/match/md5/response/sha1/sort 六个 .inl——本工程编译定义
#     （NO_SSL/NO_CACHING/NO_CGI/USE_WEBSOCKET）下其余 .inl（http2/timer/
#     mod_*/external_*/openssl_dl/wolfssl_extras/zlib）全部在 #if defined(...)
#     守卫内、不参与编译，无需抓取；2026-10-29 实测清单）
#
# 成功后自动改写 cvm_webui_lib.vcxproj：webui_stub.c -> src\webui.c +
# src\civetweb\civetweb.c（真实 webui 一并编译进 webui_lib.dll，自包含单 DLL）。
# ============================================================================

$ErrorActionPreference = "Stop"
$base = Split-Path -Parent $MyInvocation.MyCommand.Definition
$gh   = "https://raw.githubusercontent.com/webui-dev/webui/main"

function Fetch( $rel, $dest )
{
    for ( $i = 1; $i -le 4; $i++ )
    {
        try
        {
            Invoke-WebRequest -Uri "$gh/$rel" -OutFile $dest -UseBasicParsing -ErrorAction Stop | Out-Null
            $sz = (Get-Item $dest).Length
            if ( $sz -gt 16 ) { Write-Host ("OK   {0,-34} {1}" -f $rel, $sz); return $true }
            Remove-Item $dest -Force
        }
        catch { Start-Sleep -Milliseconds 300 }
    }
    Write-Host ("FAIL {0}" -f $rel)
    return $false
}

New-Item -ItemType Directory -Force -Path "$base\src\civetweb", "$base\bridge" | Out-Null

$ok = $true
$ok = (Fetch "include/webui.h"       "$base\webui.h")              -and $ok
$ok = (Fetch "src/webui.c"           "$base\src\webui.c")          -and $ok
$ok = (Fetch "bridge/webui_bridge.h" "$base\bridge\webui_bridge.h") -and $ok

$civet = @(
    "civetweb.h", "civetweb.c",
    "handle_form.inl", "match.inl", "md5.inl",
    "response.inl", "sha1.inl", "sort.inl"
)
foreach ( $f in $civet )
{
    $ok = (Fetch "src/civetweb/$f" "$base\src\civetweb\$f") -and $ok
}

if ( -not $ok )
{
    Write-Host "部分文件拉取失败，vcxproj 保持 stub 模式。请在稳定网络环境重跑本脚本。"
    exit 1
}

# ---- 改写 vcxproj：stub -> 真实 webui 源码 ----
$vcx = "$base\cvm_webui_lib.vcxproj"
$text = [System.IO.File]::ReadAllText($vcx)
$old = '<ClCompile Include="$(WebUI_SRC)\webui_stub.c" />'
$new = '<ClCompile Include="$(WebUI_SRC)\src\webui.c" />' + "`r`n" +
       '    <ClCompile Include="$(WebUI_SRC)\src\civetweb\civetweb.c" />'
if ( $text.Contains($old) )
{
    $text = $text.Replace($old, $new)
    [System.IO.File]::WriteAllText($vcx, $text, (New-Object System.Text.UTF8Encoding($true)))
    Write-Host "vcxproj 已切换到真实 webui 源码编译。"
}
else
{
    Write-Host "vcxproj 已是真实源码模式（或已改写），跳过。"
}

Write-Host "完成：真实 webui 源码就位，重新导出 SLangWebUI 即得真实 GUI 能力。"
