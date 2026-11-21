# SnakeGame FairyGUI asset generator.
# Produces fairyui\atlas.png + package.xml + component.xml (XML package for
# SimGameEngine ui/FairyPackage.sl). Re-run any time to regenerate.
# NOTE: pure ASCII source on purpose (PS5.1 -File reads BOM-less UTF8 as GBK);
# Chinese label text is assembled from Unicode code points below.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File make-fairyui.ps1
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$uiDir = Join-Path $root 'fairyui'
New-Item -ItemType Directory -Force -Path $uiDir | Out-Null
Add-Type -AssemblyName System.Drawing

$AW = 512
$AH = 512
$bmp = New-Object System.Drawing.Bitmap $AW, $AH
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
$g.Clear([System.Drawing.Color]::Transparent)

$white = [System.Drawing.Brushes]::White
$dark  = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(200, 8, 16, 8))
$ink   = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 224, 255, 224))

function CStr([int[]]$codes) {
    ($codes | ForEach-Object { [char]$_ }) -join ''
}

function RoundPath([single]$x, [single]$y, [single]$w, [single]$h, [single]$r) {
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = $r * 2.0
    $p.AddArc($x, $y, $d, $d, 180, 90)
    $p.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
    $p.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90)
    $p.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
    $p.CloseFigure()
    return $p
}

# ---- panel_bg (0,0,48,48) scale9 12,12,12,12 --------------------------------
$pp = RoundPath 0 0 48 48 10
$g.FillPath((New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(215, 16, 26, 16))), $pp)
$g.DrawPath((New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(255, 124, 206, 124), 2)), $pp)
$pp.Dispose()

# ---- btn (52,0,48,28) scale9 12,10,12,10 ------------------------------------
$bp = RoundPath 52 0 48 28 8
$g.FillPath((New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(235, 30, 58, 30))), $bp)
$g.DrawPath((New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(255, 159, 232, 159), 2)), $bp)
$bp.Dispose()

# ---- checkbox on/off --------------------------------------------------------
$boxPenOn  = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(255, 159, 232, 159), 2)
$boxPenOff = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(255, 150, 150, 150), 2)
$chkPen    = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(255, 120, 255, 120), 3)
$g.DrawRectangle($boxPenOn,  104, 3, 14, 14)
$g.DrawRectangle($boxPenOff, 128, 3, 14, 14)
$g.DrawLines($chkPen, @(
    (New-Object System.Drawing.Point 107, 11),
    (New-Object System.Drawing.Point 111, 15),
    (New-Object System.Drawing.Point 118, 6)))
$g.FillRectangle($white, 152, 0, 4, 4)   # white 1x1-ish

# ---- digit glyphs d0..d9 (12x20) + dcolon (8x20) at y=32 --------------------
$digitFont = New-Object System.Drawing.Font("Consolas", 15, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
for ($i = 0; $i -lt 10; $i++) {
    $g.DrawString([string]$i, $digitFont, $ink, (2 + $i * 12), 32)
}
$g.DrawString(":", $digitFont, $ink, 121, 32)

# ---- text labels (packed rows starting y=64) --------------------------------
$labelDefs = @()
$labelDefs += ,@("t_title",    @(0x8D2A, 0x5403, 0x86C7), 36)                 # tan chi she
$labelDefs += ,@("t_start",    @(0x5F00, 0x59CB, 0x6E38, 0x620F), 19)          # kai shi you xi
$labelDefs += ,@("t_rank",     @(0x6392, 0x884C, 0x699C), 19)                  # pai hang bang
$labelDefs += ,@("t_sound",    @(0x58F0, 0x97F3), 16)                          # sheng yin
$labelDefs += ,@("t_music",    @(0x80CC, 0x666F, 0x4E50), 16)                  # bei jing yue
$labelDefs += ,@("t_time",     @(0x65F6, 0x95F4), 15)                          # shi jian
$labelDefs += ,@("t_score",    @(0x5206, 0x6570), 15)                          # fen shu
$labelDefs += ,@("t_colname",  @(0x540D, 0x6B21), 16)                          # ming ci
$labelDefs += ,@("t_nodata",   @(0x6682, 0x65E0, 0x8BB0, 0x5F55), 18)          # zan wu ji lu
$labelDefs += ,@("t_paused",   @(0x5DF2, 0x6682, 0x505C), 21)                  # yi zan ting
$labelDefs += ,@("t_over",     @(0x6E38, 0x620F, 0x7ED3, 0x675F), 21)          # you xi jie shu
$labelDefs += ,@("t_ranktitle",@(0x6392, 0x884C, 0x699C), 21)                  # pai hang bang
$labelDefs += ,@("t_back",     @(0x8FD4, 0x56DE), 16)                          # fan hui
$labelDefs += ,@("t_hint",     @(0x7A7A, 0x683C, 0x6682, 0x505C), 13)          # kong ge zan ting
$rects = @{}
$cursorX = 0
$cursorY = 64
$rowH = 0
foreach ($d in $labelDefs) {
    $name = $d[0]
    $txt = CStr $d[1]
    $fpx = $d[2]
    $font = New-Object System.Drawing.Font("Microsoft YaHei", $fpx, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
    $sz = $g.MeasureString($txt, $font)
    $w = [int][math]::Ceiling($sz.Width) + 4
    $h = [int][math]::Ceiling($sz.Height) + 4
    if ($cursorX + $w -gt $AW) { $cursorX = 0; $cursorY += $rowH + 10; $rowH = 0 }
    for ($ox = -1; $ox -le 1; $ox++) {
        for ($oy = -1; $oy -le 1; $oy++) {
            if ($ox -ne 0 -or $oy -ne 0) {
                $g.DrawString($txt, $font, $dark, $cursorX + 1 + $ox, $cursorY + 1 + $oy)
            }
        }
    }
    $g.DrawString($txt, $font, $white, $cursorX + 1, $cursorY + 1)
    $rects[$name] = @($cursorX, $cursorY, $w, $h)
    $cursorX += $w + 10
    if ($h -gt $rowH) { $rowH = $h }
    $font.Dispose()
}

# ---- save atlas --------------------------------------------------------------
$atlasPath = Join-Path $uiDir 'atlas.png'
$bmp.Save($atlasPath, [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose()
$bmp.Dispose()

# ---- standalone textures: logo.png (loader demo) + go3d.png (GoWrapper placeholder) ----
$logo = New-Object System.Drawing.Bitmap 96, 96
$lg = [System.Drawing.Graphics]::FromImage($logo)
$lg.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$lg.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
$lg.Clear([System.Drawing.Color]::FromArgb(255, 20, 40, 20))
$lp = RoundPath 6 6 84 84 10
$lg.DrawPath((New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(255, 159, 232, 159), 3)), $lp)
$lp.Dispose()
$logoFont = New-Object System.Drawing.Font("Microsoft YaHei", 26, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
$lf = CStr @(0x8D2A, 0x5403)   # tan chi
$lg.DrawString($lf, $logoFont, [System.Drawing.Brushes]::White, 14, 26)
$logoFont.Dispose()
$lg.Dispose()
$logo.Save((Join-Path $uiDir 'logo.png'), [System.Drawing.Imaging.ImageFormat]::Png)
$logo.Dispose()

$g3 = New-Object System.Drawing.Bitmap 128, 128
$g3g = [System.Drawing.Graphics]::FromImage($g3)
$g3g.Clear([System.Drawing.Color]::FromArgb(255, 10, 16, 10))
$g3g.DrawRectangle((New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(255, 90, 140, 90), 2)), 2, 2, 124, 124)
$g3g.Dispose()
$g3.Save((Join-Path $uiDir 'go3d.png'), [System.Drawing.Imaging.ImageFormat]::Png)
$g3.Dispose()

# ---- package.xml -------------------------------------------------------------
$sprites = New-Object System.Collections.Generic.List[string]
$sprites.Add('    <sprite name="panel_bg" x="0" y="0" w="48" h="48" scale9="12,12,12,12"/>')
$sprites.Add('    <sprite name="btn" x="52" y="0" w="48" h="28" scale9="12,10,12,10"/>')
$sprites.Add('    <sprite name="chk_on" x="104" y="0" w="20" h="20"/>')
$sprites.Add('    <sprite name="chk_off" x="128" y="0" w="20" h="20"/>')
$sprites.Add('    <sprite name="white" x="152" y="0" w="4" h="4"/>')
for ($i = 0; $i -lt 10; $i++) {
    $sprites.Add('    <sprite name="d' + $i + '" x="' + ($i * 12) + '" y="32" w="12" h="20"/>')
}
$sprites.Add('    <sprite name="dcolon" x="120" y="32" w="8" h="20"/>')
foreach ($d in $labelDefs) {
    $r = $rects[$d[0]]
    $sprites.Add('    <sprite name="' + $d[0] + '" x="' + $r[0] + '" y="' + $r[1] + '" w="' + $r[2] + '" h="' + $r[3] + '"/>')
}

function CenterX([int]$w) { [int]((480 - $w) / 2) }

$xml = New-Object System.Collections.Generic.List[string]
$xml.Add('<?xml version="1.0" encoding="utf-8"?>')
$xml.Add('<package name="snakeui" designWidth="480" designHeight="480">')
$xml.Add('  <atlas file="atlas.png" width="' + $AW + '" height="' + $AH + '">')
foreach ($s in $sprites) { $xml.Add($s) }
$xml.Add('  </atlas>')
$xml.Add('  <components>')
$xml.Add('    <component name="snake_main" file="component.xml"/>')
$xml.Add('  </components>')
$xml.Add('</package>')
$utf8 = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllLines((Join-Path $uiDir 'package.xml'), $xml, $utf8)

# ---- component.xml (design space 480x480; document order = draw order) ------
$tTitle = $rects["t_title"];  $tStart = $rects["t_start"];  $tRank = $rects["t_rank"]
$tSound = $rects["t_sound"];  $tMusic = $rects["t_music"];  $tBack = $rects["t_back"]
$tTime = $rects["t_time"];    $tScore = $rects["t_score"];  $tPause = $rects["t_paused"]
$tOver = $rects["t_over"];    $tRankT = $rects["t_ranktitle"]
$tHint = $rects["t_hint"];    $tColName = $rects["t_colname"]; $tNoData = $rects["t_nodata"]

$c = New-Object System.Collections.Generic.List[string]
$c.Add('<?xml version="1.0" encoding="utf-8"?>')
$c.Add('<component name="snake_main" width="480" height="480">')
# ---- main menu group (m_)：按钮先画、标签后画（标签盖按钮）；loader/graph/go3d 演示 ----
$c.Add('  <group name="menu">')
$c.Add('    <image name="m_panel" src="panel_bg" x="60" y="70" w="360" h="380" scale9="1"/>')
$c.Add('    <image name="m_title" src="t_title" x="' + (CenterX $tTitle[2]) + '" y="82" w="' + $tTitle[2] + '" h="' + $tTitle[3] + '"/>')
$c.Add('    <image name="m_menu_0" src="btn" x="140" y="300" w="200" h="44" scale9="1"/>')
$c.Add('    <image name="m_t_start" src="t_start" x="' + (140 + (200 - $tStart[2]) / 2) + '" y="' + (300 + (44 - $tStart[3]) / 2) + '" w="' + $tStart[2] + '" h="' + $tStart[3] + '"/>')
$c.Add('    <image name="m_menu_1" src="btn" x="140" y="356" w="200" h="44" scale9="1"/>')
$c.Add('    <image name="m_t_rank" src="t_rank" x="' + (140 + (200 - $tRank[2]) / 2) + '" y="' + (356 + (44 - $tRank[3]) / 2) + '" w="' + $tRank[2] + '" h="' + $tRank[3] + '"/>')
$c.Add('    <image name="m_chk_sound" src="chk_on" x="110" y="414" w="24" h="24"/>')
$c.Add('    <image name="m_t_sound" src="t_sound" x="140" y="417" w="' + $tSound[2] + '" h="' + $tSound[3] + '"/>')
$c.Add('    <image name="m_chk_music" src="chk_on" x="240" y="414" w="24" h="24"/>')
$c.Add('    <image name="m_t_music" src="t_music" x="270" y="417" w="' + $tMusic[2] + '" h="' + $tMusic[3] + '"/>')
# loader：包外文件图片（logo.png；tw/th 声明纹理像素尺寸——跨模块读
# RenderTexture 尺寸不可靠，属性显式声明）
$c.Add('    <loader name="m_logo" file="logo.png" tw="96" th="96" x="76" y="130" w="88" h="88"/>')
# go3d：3D 包装占位（go3d.png；运行期经 updateTexPixels 原位更新为软渲染旋转立方体）
$c.Add('    <go3d name="m_go3d" file="go3d.png" tw="128" th="128" x="250" y="124" w="150" h="150"/>')
# graph：纯色图形（无图集依赖）
$c.Add('    <graph name="m_g1" color="#3fa03f" x="76" y="234" w="88" h="10"/>')
$c.Add('    <graph name="m_g2" color="#c8a03f" x="76" y="252" w="66" h="10"/>')
$c.Add('    <graph name="m_g3" color="#c04040" x="76" y="270" w="44" h="10"/>')
$c.Add('  </group>')
# ---- in-game HUD group (h_) ----
$c.Add('  <group name="hud">')
$c.Add('    <image name="h_bar" src="panel_bg" x="0" y="0" w="480" h="44" scale9="1"/>')
$c.Add('    <image name="h_t_time" src="t_time" x="14" y="12" w="' + $tTime[2] + '" h="' + $tTime[3] + '"/>')
$c.Add('    <image name="h_t_score" src="t_score" x="200" y="12" w="' + $tScore[2] + '" h="' + $tScore[3] + '"/>')
$c.Add('    <image name="h_t_back" src="t_back" x="' + (398 + (72 - $tBack[2]) / 2) + '" y="' + (6 + (32 - $tBack[3]) / 2) + '" w="' + $tBack[2] + '" h="' + $tBack[3] + '"/>')
$c.Add('    <image name="h_menu_2" src="btn" x="398" y="6" w="72" h="32" scale9="1"/>')
$c.Add('    <image name="h_t_hint" src="t_hint" x="180" y="458" w="' + $tHint[2] + '" h="' + $tHint[3] + '"/>')
$c.Add('    <image name="h_t_paused" src="t_paused" x="' + (140 + (200 - $tPause[2]) / 2) + '" y="' + (190 + (100 - $tPause[3]) / 2) + '" w="' + $tPause[2] + '" h="' + $tPause[3] + '"/>')
$c.Add('    <image name="h_pause" src="panel_bg" x="140" y="190" w="200" h="100" scale9="1"/>')
$c.Add('  </group>')
# ---- rank panel group (r_) ----
$c.Add('  <group name="rank">')
$c.Add('    <image name="r_panel" src="panel_bg" x="40" y="30" w="400" h="420" scale9="1"/>')
$c.Add('    <image name="r_t_over" src="t_over" x="' + (40 + (400 - $tOver[2]) / 2) + '" y="96" w="' + $tOver[2] + '" h="' + $tOver[3] + '"/>')
$c.Add('    <image name="r_t_title" src="t_ranktitle" x="' + (40 + (400 - $tRankT[2]) / 2) + '" y="52" w="' + $tRankT[2] + '" h="' + $tRankT[3] + '"/>')
$c.Add('    <image name="r_t_nodata" src="t_nodata" x="' + (40 + (400 - $tNoData[2]) / 2) + '" y="250" w="' + $tNoData[2] + '" h="' + $tNoData[3] + '"/>')
$c.Add('    <image name="r_t_c1" src="t_colname" x="78" y="116" w="' + $tColName[2] + '" h="' + $tColName[3] + '"/>')
$c.Add('    <image name="r_t_c2" src="t_score" x="150" y="118" w="' + $tScore[2] + '" h="' + $tScore[3] + '"/>')
$c.Add('    <image name="r_t_c3" src="t_time" x="280" y="118" w="' + $tTime[2] + '" h="' + $tTime[3] + '"/>')
$c.Add('    <image name="r_t_back" src="t_back" x="' + (190 + (100 - $tBack[2]) / 2) + '" y="' + (402 + (38 - $tBack[3]) / 2) + '" w="' + $tBack[2] + '" h="' + $tBack[3] + '"/>')
$c.Add('    <image name="r_menu_3" src="btn" x="190" y="402" w="100" h="38" scale9="1"/>')
$c.Add('  </group>')
$c.Add('</component>')
[System.IO.File]::WriteAllLines((Join-Path $uiDir 'component.xml'), $c, $utf8)

Write-Host "fairyui assets written -> " $uiDir
Write-Host ("sprites total: " + ($sprites.Count) + "  quads: " + $c.Count)
