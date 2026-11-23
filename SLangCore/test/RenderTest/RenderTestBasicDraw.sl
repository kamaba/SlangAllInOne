# ============================================================================
# RenderTestBasicDraw —— BasicDraw 基础图形统一接口层回归（GDI / RHI 双后端）
# ----------------------------------------------------------------------------
# 用户点名图形全覆盖：点/点列/线/粗线/虚线/折线/圆/填圆/椭圆/填椭圆/三角/
# 填三角/四边形/填四边形/矩形/填矩形/多边形/填多边形/贝塞尔/圆弧/曲线/
# 方向箭头，外加 clear 语义与 toRgba 块一致性。
#
# 断言策略：
#   - 256x256 画布一次 clear 后 4x4 分格绘制（每格 64px），格内独立断言，
#     避免跨格串扰；RHI 单帧顶点 ~1500 << 4096 单槽上限；
#   - 内点采样避开边界半像素差异；环/弧类用距离带统计（方向无关——
#     GDI Arc 扫掠方向与 RHI 采样方向不逐像素对齐）；
#   - 虚线断言 = 同一扫描行上「既有 dash 像素又有 gap 像素」；
#   - 颜色比较为整值 0xAARRGGBB（两后端非黑像素 alpha 均为 255，
#     GDI 的纯黑像素 alpha 特例不在本测试取值范围）。
# ============================================================================

import SLangRender;
import Math;
import Std;

public class RenderTestBasicDraw
{
    # 单点像素断言
    static bool chk( BasicDraw d, Int32 x, Int32 y, Int32 expect )
    {
        Int32 px = d.pixelAt( x, y )
        if px == expect
        {
            ret true
        }
        ret false
    }

    # 矩形窗内非背景像素计数
    static Int32 countNotBack( BasicDraw d, Int32 x0, Int32 x1, Int32 y0, Int32 y1, Int32 back )
    {
        Int32 n = 0
        Int32 y = y0
        while y <= y1
        {
            Int32 x = x0
            while x <= x1
            {
                Int32 px = d.pixelAt( x, y )
                if px != back
                {
                    n += 1
                }
                x += 1
            }
            y += 1
        }
        ret n
    }

    # 距离带统计：窗内距 (cx,cy) 的整数距离平方 ∈ [r0^2, r1^2] 的
    # 非背景像素数（r0>r1 时区间为空，返回 0）
    static Int32 ringCount( BasicDraw d, Int32 cx, Int32 cy, Int32 r0, Int32 r1,
        Int32 x0, Int32 x1, Int32 y0, Int32 y1, Int32 back )
    {
        Int32 n = 0
        Int32 q0 = r0 * r0
        Int32 q1 = r1 * r1
        Int32 y = y0
        while y <= y1
        {
            Int32 x = x0
            while x <= x1
            {
                Int32 dx = x - cx
                Int32 dy = y - cy
                Int32 d2 = dx * dx + dy * dy
                if d2 >= q0
                {
                    if d2 <= q1
                    {
                        Int32 px = d.pixelAt( x, y )
                        if px != back
                        {
                            n += 1
                        }
                    }
                }
                x += 1
            }
            y += 1
        }
        ret n
    }

    # 虚线行扫描：同一行内既有笔色像素又有背景像素（on/off 双非零）
    static bool chkDashed( BasicDraw d, Int32 x0, Int32 x1, Int32 y, Int32 color, Int32 back )
    {
        Int32 on = 0
        Int32 off = 0
        Int32 x = x0
        while x <= x1
        {
            Int32 px = d.pixelAt( x, y )
            if px == color
            {
                on += 1
            }
            else
            {
                off += 1
            }
            x += 1
        }
        if on <= 0
        {
            ret false
        }
        if off <= 0
        {
            ret false
        }
        ret true
    }

    # toRgba 块与 pixelAt 单点一致性（RGBA8 top-down，R 在前）
    static bool chkBlock( BasicDraw d, Int32 x, Int32 y )
    {
        Int64 blk = d.toRgbaBlock()
        if blk == 0
        {
            ret false
        }
        Int32 w = d.width()
        Int32 off = ( y * w + x ) * 4
        Int32 r = Memory.readUInt8( blk, off )
        Int32 g = Memory.readUInt8( blk, off + 1 )
        Int32 b = Memory.readUInt8( blk, off + 2 )
        Int32 a = Memory.readUInt8( blk, off + 3 )
        Memory.free( blk )
        Int32 px = d.pixelAt( x, y )
        Int32 v = ( a << 24 ) | ( r << 16 ) | ( g << 8 ) | b
        if v == px
        {
            ret true
        }
        ret false
    }

    # 单后端全量绘制 + 断言（back2 用于 clear 语义阶段）
    static bool checkDraw( BasicDraw d, Int32 back, Int32 back2,
        Int32 c1, Int32 c2, Int32 c3, Int32 c4, Int32 c5 )
    {
        if d.isReady() == false
        {
            ret false
        }
        bool ok = true
        bool dr = false
        # 失败格定位（首个失败断言区段编号；-1 = 全过）：
        #   0=行0 1=行1 20..23=行2 各格 30..32=行3 各格 4=clear 段
        Int32 failAt = -1
        d.clear( back )

        # ── 格 (0,0)：点 / 横线 / 竖线 / 粗线 / 虚线 ──
        dr = d.point( 8, 8, c1 )
        dr = d.line( 4, 16, 60, 16, c2 )
        dr = d.line( 14, 4, 14, 62, c1 )
        dr = d.lineEx( 4, 40, 60, 40, 7, BasicDraw.PEN_SOLID, c3 )
        dr = d.dashedLine( 4, 56, 60, 56, c4 )
        # ── 格 (1,0)：圆描边 ──
        dr = d.circle( 96, 32, 26, c5 )
        # ── 格 (2,0)：填圆 ──
        dr = d.fillCircle( 160, 32, 26, c3 )
        # ── 格 (3,0)：椭圆描边（正圆 bbox，中心 (223,31) 半径 23）──
        dr = d.ellipse( 200, 8, 246, 54, c4 )
        # ── 格 (0,1)：填椭圆 ──
        dr = d.fillEllipse( 8, 72, 58, 122, c5 )
        # ── 格 (1,1)：三角描边 ──
        dr = d.triangle( 72, 120, 94, 72, 118, 120, c1 )
        # ── 格 (2,1)：填三角 ──
        dr = d.fillTriangle( 136, 120, 158, 72, 182, 120, c2 )
        # ── 格 (3,1)：四边形填充 + 描边 ──
        List<Float32> qx = List<Float32>()
        qx.add( 200.0f )
        qx.add( 246.0f )
        qx.add( 238.0f )
        qx.add( 208.0f )
        List<Float32> qy = List<Float32>()
        qy.add( 72.0f )
        qy.add( 78.0f )
        qy.add( 120.0f )
        qy.add( 114.0f )
        dr = d.fillQuad( qx, qy, c3 )
        dr = d.quad( qx, qy, c4 )
        # ── 格 (0,2)：矩形填充 + 描边 ──
        dr = d.fillRect( 6, 134, 58, 186, c1 )
        dr = d.rect( 6, 134, 58, 186, c2 )
        # ── 格 (1,2)：五边形填充 + 描边（凸，中心 (95,155) 内部）──
        List<Float32> pgx = List<Float32>()
        pgx.add( 95.0f )
        pgx.add( 118.0f )
        pgx.add( 109.0f )
        pgx.add( 81.0f )
        pgx.add( 72.0f )
        List<Float32> pgy = List<Float32>()
        pgy.add( 134.0f )
        pgy.add( 150.0f )
        pgy.add( 178.0f )
        pgy.add( 178.0f )
        pgy.add( 150.0f )
        dr = d.fillPolygon( pgx, pgy, c4 )
        dr = d.polygon( pgx, pgy, c5 )
        # ── 格 (2,2)：贝塞尔（4 点单段；B(0.5)=(158,148) 精确过点）──
        List<Float32> bxs = List<Float32>()
        bxs.add( 134.0f )
        bxs.add( 158.0f )
        bxs.add( 158.0f )
        bxs.add( 182.0f )
        List<Float32> bys = List<Float32>()
        bys.add( 184.0f )
        bys.add( 136.0f )
        bys.add( 136.0f )
        bys.add( 184.0f )
        dr = d.bezier( bxs, bys, c5 )
        # ── 格 (3,2)：大圆弧（约 340°，方向无关断言）──
        dr = d.curve( 224, 160, 26, 0.05f, 6.0f, c3 )
        # ── 格 (0,3)：方向箭头 ──
        dr = d.arrow( 4, 248, 54, 206, 9, c2 )
        # ── 格 (1,3)：点列 + 折线 ──
        List<Float32> pox = List<Float32>()
        pox.add( 68.0f )
        pox.add( 76.0f )
        pox.add( 84.0f )
        pox.add( 92.0f )
        pox.add( 100.0f )
        pox.add( 108.0f )
        pox.add( 116.0f )
        List<Float32> poy = List<Float32>()
        poy.add( 200.0f )
        poy.add( 200.0f )
        poy.add( 200.0f )
        poy.add( 200.0f )
        poy.add( 200.0f )
        poy.add( 200.0f )
        poy.add( 200.0f )
        dr = d.points( pox, poy, c5 )
        List<Float32> plx = List<Float32>()
        plx.add( 68.0f )
        plx.add( 80.0f )
        plx.add( 92.0f )
        plx.add( 104.0f )
        plx.add( 116.0f )
        List<Float32> ply = List<Float32>()
        ply.add( 244.0f )
        ply.add( 214.0f )
        ply.add( 240.0f )
        ply.add( 216.0f )
        ply.add( 246.0f )
        dr = d.polyline( plx, ply, c1 )

        # ================================ 断言 ================================
        # 格 (0,0)
        ok = RenderTestBasicDraw.chk( d, 8, 8, c1 ) && ok
        ok = RenderTestBasicDraw.chk( d, 32, 16, c2 ) && ok
        ok = RenderTestBasicDraw.chk( d, 32, 15, back ) && ok
        ok = RenderTestBasicDraw.chk( d, 32, 17, back ) && ok
        ok = RenderTestBasicDraw.chk( d, 14, 33, c1 ) && ok
        ok = RenderTestBasicDraw.chk( d, 32, 38, c3 ) && ok
        ok = RenderTestBasicDraw.chk( d, 32, 42, c3 ) && ok
        ok = RenderTestBasicDraw.chk( d, 32, 36, back ) && ok
        ok = RenderTestBasicDraw.chk( d, 32, 44, back ) && ok
        if RenderTestBasicDraw.chkDashed( d, 4, 60, 56, c4, back ) == false
        {
            ok = false
        }
        # 格 (1,0)：圆描边——中心空 + 环带非空 + 内外带空
        ok = RenderTestBasicDraw.chk( d, 96, 32, back ) && ok
        Int32 cr = RenderTestBasicDraw.ringCount( d, 96, 32, 24, 28, 70, 122, 6, 58, back )
        Int32 ci = RenderTestBasicDraw.ringCount( d, 96, 32, 0, 17, 70, 122, 6, 58, back )
        Int32 co = RenderTestBasicDraw.ringCount( d, 96, 32, 32, 99, 70, 122, 6, 58, back )
        if cr < 8
        {
            ok = false
        }
        if ci != 0
        {
            ok = false
        }
        if co != 0
        {
            ok = false
        }
        # 格 (2,0)：填圆——中心/内点命中 + 外点空
        ok = RenderTestBasicDraw.chk( d, 160, 32, c3 ) && ok
        ok = RenderTestBasicDraw.chk( d, 160, 14, c3 ) && ok
        ok = RenderTestBasicDraw.chk( d, 182, 32, c3 ) && ok
        ok = RenderTestBasicDraw.chk( d, 188, 32, back ) && ok
        ok = RenderTestBasicDraw.chk( d, 160, 4, back ) && ok
        # 格 (3,0)：椭圆描边——中心空 + 环带非空 + 内外带空
        ok = RenderTestBasicDraw.chk( d, 223, 31, back ) && ok
        Int32 er = RenderTestBasicDraw.ringCount( d, 223, 31, 20, 25, 200, 246, 8, 54, back )
        Int32 ei = RenderTestBasicDraw.ringCount( d, 223, 31, 0, 14, 200, 246, 8, 54, back )
        Int32 eo = RenderTestBasicDraw.ringCount( d, 223, 31, 27, 99, 200, 246, 8, 54, back )
        if er < 6
        {
            ok = false
        }
        if ei != 0
        {
            ok = false
        }
        if eo != 0
        {
            ok = false
        }
        if failAt < 0 && ok == false
        {
            failAt = 0
        }
        # 格 (0,1)：填椭圆
        ok = RenderTestBasicDraw.chk( d, 33, 97, c5 ) && ok
        ok = RenderTestBasicDraw.chk( d, 12, 97, c5 ) && ok
        ok = RenderTestBasicDraw.chk( d, 5, 97, back ) && ok
        ok = RenderTestBasicDraw.chk( d, 33, 70, back ) && ok
        # 格 (1,1)：三角描边——底边/左边中点命中，内部空
        ok = RenderTestBasicDraw.chk( d, 95, 120, c1 ) && ok
        ok = RenderTestBasicDraw.chk( d, 83, 96, c1 ) && ok
        ok = RenderTestBasicDraw.chk( d, 95, 104, back ) && ok
        # 格 (2,1)：填三角——质心/内点命中，顶点上方空
        ok = RenderTestBasicDraw.chk( d, 158, 104, c2 ) && ok
        ok = RenderTestBasicDraw.chk( d, 145, 112, c2 ) && ok
        ok = RenderTestBasicDraw.chk( d, 158, 68, back ) && ok
        # 格 (3,1)：四边形——内部填充色 + 顶边中点/顶点描边色
        ok = RenderTestBasicDraw.chk( d, 222, 96, c3 ) && ok
        ok = RenderTestBasicDraw.chk( d, 223, 75, c4 ) && ok
        ok = RenderTestBasicDraw.chk( d, 200, 72, c4 ) && ok
        if failAt < 0 && ok == false
        {
            failAt = 1
        }
        # 格 (0,2)：矩形——内部填充色 + 顶/底边中点描边色 + 外部空
        # 底边像素：GDI Rectangle 的 bottom 排他画在 y1-1，RHI line 画在 y1 → 双容忍
        ok = RenderTestBasicDraw.chk( d, 32, 160, c1 ) && ok
        ok = RenderTestBasicDraw.chk( d, 32, 134, c2 ) && ok
        bool btm = RenderTestBasicDraw.chk( d, 32, 185, c2 )
        if btm == false
        {
            btm = RenderTestBasicDraw.chk( d, 32, 186, c2 )
        }
        if btm == false
        {
            ok = false
        }
        ok = RenderTestBasicDraw.chk( d, 32, 130, back ) && ok
        ok = RenderTestBasicDraw.chk( d, 62, 160, back ) && ok
        if failAt < 0 && ok == false
        {
            failAt = 20
        }
        # 格 (1,2)：五边形——中心填充色 + 顶点描边色 + 外部空
        ok = RenderTestBasicDraw.chk( d, 95, 155, c4 ) && ok
        ok = RenderTestBasicDraw.chk( d, 95, 134, c5 ) && ok
        ok = RenderTestBasicDraw.chk( d, 68, 155, back ) && ok
        if failAt < 0 && ok == false
        {
            failAt = 21
        }
        # 格 (2,2)：贝塞尔——B(0.5) 过点（GDI 曲线展平可偏 1px → 5 点容忍）+ 两端点
        bool bz = RenderTestBasicDraw.chk( d, 158, 148, c5 )
        if bz == false
        {
            bz = RenderTestBasicDraw.chk( d, 157, 148, c5 )
        }
        if bz == false
        {
            bz = RenderTestBasicDraw.chk( d, 159, 148, c5 )
        }
        if bz == false
        {
            bz = RenderTestBasicDraw.chk( d, 158, 147, c5 )
        }
        if bz == false
        {
            bz = RenderTestBasicDraw.chk( d, 158, 149, c5 )
        }
        if bz == false
        {
            ok = false
        }
        ok = RenderTestBasicDraw.chk( d, 134, 184, c5 ) && ok
        # 终点像素两后端均排他（GDI exclusive-end / RHI 终边过中心）→ 窗口存在性
        Int32 bze = RenderTestBasicDraw.countNotBack( d, 179, 183, 181, 185, back )
        if bze == 0
        {
            ok = false
        }
        if failAt < 0 && ok == false
        {
            failAt = 22
        }
        # 格 (3,2)：大圆弧——中心空 + 弧带非空 + 内外带空
        ok = RenderTestBasicDraw.chk( d, 224, 160, back ) && ok
        Int32 ar = RenderTestBasicDraw.ringCount( d, 224, 160, 23, 29, 196, 252, 132, 188, back )
        Int32 ai = RenderTestBasicDraw.ringCount( d, 224, 160, 0, 14, 196, 252, 132, 188, back )
        Int32 ao = RenderTestBasicDraw.ringCount( d, 224, 160, 33, 99, 196, 252, 132, 188, back )
        if ar < 15
        {
            ok = false
        }
        if ai != 0
        {
            ok = false
        }
        if ao != 0
        {
            ok = false
        }
        if failAt < 0 && ok == false
        {
            failAt = 23
        }
        # 格 (0,3)：箭头——头内点命中 + 头/杆区域存在性
        #（头尖顶点像素两后端均排他，不作精确断言）
        ok = RenderTestBasicDraw.chk( d, 49, 210, c2 ) && ok
        Int32 ah = RenderTestBasicDraw.countNotBack( d, 50, 55, 204, 209, back )
        if ah == 0
        {
            ok = false
        }
        Int32 na = RenderTestBasicDraw.countNotBack( d, 0, 63, 192, 255, back )
        if na < 50
        {
            ok = false
        }
        if failAt < 0 && ok == false
        {
            failAt = 30
        }
        # 格 (1,3)：点列 + 折线
        ok = RenderTestBasicDraw.chk( d, 76, 200, c5 ) && ok
        ok = RenderTestBasicDraw.chk( d, 100, 200, c5 ) && ok
        ok = RenderTestBasicDraw.chk( d, 68, 244, c1 ) && ok
        ok = RenderTestBasicDraw.chk( d, 74, 229, c1 ) && ok
        if failAt < 0 && ok == false
        {
            failAt = 31
        }
        # toRgba 块一致性（3 点抽查）
        if RenderTestBasicDraw.chkBlock( d, 32, 16 ) == false
        {
            ok = false
        }
        if RenderTestBasicDraw.chkBlock( d, 160, 32 ) == false
        {
            ok = false
        }
        if RenderTestBasicDraw.chkBlock( d, 158, 148 ) == false
        {
            ok = false
        }
        if failAt < 0 && ok == false
        {
            failAt = 32
        }
        # ── clear 语义：整幅重置后无旧图元残留（含原贝塞尔过点）──
        d.clear( back2 )
        ok = RenderTestBasicDraw.chk( d, 0, 0, back2 ) && ok
        ok = RenderTestBasicDraw.chk( d, 255, 0, back2 ) && ok
        ok = RenderTestBasicDraw.chk( d, 0, 255, back2 ) && ok
        ok = RenderTestBasicDraw.chk( d, 255, 255, back2 ) && ok
        ok = RenderTestBasicDraw.chk( d, 128, 128, back2 ) && ok
        ok = RenderTestBasicDraw.chk( d, 158, 148, back2 ) && ok
        ok = RenderTestBasicDraw.chk( d, 96, 32, back2 ) && ok
        Int32 nz = RenderTestBasicDraw.countNotBack( d, 0, 255, 0, 255, back2 )
        if nz != 0
        {
            ok = false
        }
        # clear 后重画可用
        dr = d.fillRect( 10, 10, 20, 20, c3 )
        ok = RenderTestBasicDraw.chk( d, 15, 15, c3 ) && ok
        ok = RenderTestBasicDraw.chk( d, 25, 25, back2 ) && ok
        if failAt < 0 && ok == false
        {
            failAt = 4
        }
        Console.println( "[bd]   backend=" + d.backend().toString() + " failAt=" + failAt.toString() )
        ret ok
    }

    public static bool runBasicDraw()
    {
        Console.println( "-- Phase BD: BasicDraw 统一基础绘图（GDI 直通 + RHI 三角化，双后端像素断言）--" )
        Int32 back = GdiCanvas.rgb( 18, 22, 32 )
        Int32 back2 = GdiCanvas.rgb( 30, 34, 44 )
        Int32 c1 = GdiCanvas.rgb( 255, 60, 60 )
        Int32 c2 = GdiCanvas.rgb( 60, 255, 120 )
        Int32 c3 = GdiCanvas.rgb( 80, 140, 255 )
        Int32 c4 = GdiCanvas.rgb( 255, 220, 60 )
        Int32 c5 = GdiCanvas.rgb( 255, 120, 255 )
        # GDI 后端（Windows 原生）
        BasicDraw g = BasicDraw.create( 256, 256, BasicDraw.BACKEND_GDI )
        bool gdiOk = false
        if g != null
        {
            gdiOk = RenderTestBasicDraw.checkDraw( g, back, back2, c1, c2, c3, c4, c5 )
            g.dispose()
        }
        # RHI 后端（MESH_CUSTOM 三角化 + 调色板纹理）
        BasicDraw r = BasicDraw.create( 256, 256, BasicDraw.BACKEND_RHI )
        bool rhiOk = false
        if r != null
        {
            rhiOk = RenderTestBasicDraw.checkDraw( r, back, back2, c1, c2, c3, c4, c5 )
            r.dispose()
        }
        string gTxt = "FAIL"
        if gdiOk
        {
            gTxt = "ok"
        }
        string rTxt = "FAIL"
        if rhiOk
        {
            rTxt = "ok"
        }
        Console.println( "[bd] Phase BD: " + ( ( gdiOk && rhiOk ) ? "PASS" : "FAIL" ) + " (gdi=" + gTxt + " rhi=" + rTxt + ")" )
        ret gdiOk && rhiOk
    }
}
