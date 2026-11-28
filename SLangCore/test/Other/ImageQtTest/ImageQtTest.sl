import Std;
import SLangQT;
import SLangImage;

# =========================================================================
# ImageQtTest —— SLangImage x SLangQT 显示桥接端到端测试
#
#   Image 侧用纯模块 API 生成 8 张画廊（ImageDraw 几何/文本、
#   ImageMask 渐变/棋盘混合、ImageEnhance、ImageChops、ImageFilter），
#   经 ImageBuffer.toNativeRgba() 导出原生 RGBA8 top-down 像素块
#   （Memory.alloc 分配，w*h*4 字节），QT 侧 QLabel.setPixmapRgba
#   ( ptr, w, h ) 直接上屏 —— Qt 实现 QImage 零拷贝 wrap ->
#   QPixmap::fromImage 深拷贝 -> setScaledContents，显示后调用方
#   Memory.free( ptr ) 随时安全。
#
# 双后端协议（仿 RenderTestQt）：
#   stub（CSimpleVMTest -test 默认链）：画廊生成断言照跑 [PASS]/[FAIL]，
#     窗口部分 backendKind() != "qt" -> [SKIP] 行（不计入 PASS/FAIL）
#   qt（deploy-qt.ps1 部署 Qt runtime 后 slang.exe 跑 slb）：
#     真实窗口 60s 自动轮播 8 张（900ms/张），按钮 <- / -> 手动翻页，
#     _pixOk >= 30 才 PASS
# =========================================================================

public class ImageQtTest
{
    # ── 测试行协议（[PASS]/[FAIL] 行 + 尾行汇总）─────────────────
    static Int32 s_pass = 0
    static Int32 s_fail = 0

    # ── 画廊状态（固定 8 张，320x240 RGBA8 = 307200B << 4MiB 上传上限）──
    # 注：画廊对象存 8 个独立字段 —— 模板参数不允许带点的跨模块类型名
    #   （Array<Image.ImageBuffer> 非法），if 链取图零语法风险
    static Image.ImageBuffer _g0 = null
    static Image.ImageBuffer _g1 = null
    static Image.ImageBuffer _g2 = null
    static Image.ImageBuffer _g3 = null
    static Image.ImageBuffer _g4 = null
    static Image.ImageBuffer _g5 = null
    static Image.ImageBuffer _g6 = null
    static Image.ImageBuffer _g7 = null
    static Int32 _count = 0
    public static Int32 _pixOk = 0        # setPixmapRgba 成功计数
    public static Int32 _shown = 0        # 当前帧索引

    # ── QT 窗口控件 ──────────────────────────────────────────────
    static SLang.QApplication _app = null
    static SLang.QLabel _label = null
    static SLang.QPushButton _btnPrev = null
    static SLang.QPushButton _btnNext = null

    static void check( string name, bool ok )
    {
        if ok
        {
            Console.println( "[PASS] " + name )
            s_pass = s_pass + 1
        }
        else
        {
            Console.println( "[FAIL] " + name )
            s_fail = s_fail + 1
        }
    }

    # ── 画廊素材辅助：水平渐变图（x=0 -> c0, x=w-1 -> c1）────────
    static Image.ImageBuffer makeGradient( Int32 w, Int32 h, ColorInt c0, ColorInt c1 )
    {
        Image.ImageBuffer im = Image.ImageBuffer( w, h, Image.EPixelFormat.Rgba8 )
        Int32 x = 0
        while x < w
        {
            Int32 t = 0
            if w > 1
            {
                t = x * 255 / ( w - 1 )
            }
            Int32 r = ( c0.r * ( 255 - t ) + c1.r * t ) / 255
            Int32 g = ( c0.g * ( 255 - t ) + c1.g * t ) / 255
            Int32 b = ( c0.b * ( 255 - t ) + c1.b * t ) / 255
            Int32 y = 0
            while y < h
            {
                im.setPixel( x, y, ColorInt( r, g, b, 255 ) )
                y = y + 1
            }
            x = x + 1
        }
        ret im
    }

    # ── 画廊生成（纯 SLangImage API，两种后端都跑并断言）─────────
    static void buildGallery()
    {
        _count = 8

        # G1 ImageDraw 几何：填充矩形 / 填充椭圆 / 圆 / 线 / 点
        Image.ImageBuffer g1 = Image.ImageBuffer.newImage( 320, 240, ColorInt( 24, 26, 34, 255 ) )
        Image.ImageDraw.rectangle( g1, 16, 16, 120, 100, ColorInt( 230, 57, 70, 255 ), null, 1 )
        Image.ImageDraw.ellipse( g1, 140, 24, 260, 96, ColorInt( 86, 204, 242, 255 ), null, 1 )
        Image.ImageDraw.circle( g1, 60, 180, 28, ColorInt( 255, 200, 60, 255 ), null, 1 )
        Image.ImageDraw.line( g1, 140, 40, 300, 200, ColorInt( 180, 220, 120, 255 ), 1 )
        Image.ImageDraw.point( g1, 10, 10, ColorInt( 255, 255, 255, 255 ) )
        ColorInt p1 = g1.getPixel( 60, 60 )
        bool g1ok = false
        if p1.r == 230
        {
            if p1.g == 57
            {
                g1ok = true
            }
        }
        ImageQtTest.check( "gallery1 draw rect fill", g1ok )
        ColorInt p1e = g1.getPixel( 200, 60 )
        bool g1e = false
        if p1e.b == 242
        {
            if p1e.g == 204
            {
                g1e = true
            }
        }
        ImageQtTest.check( "gallery1 draw ellipse fill", g1e )

        # G2 ImageDraw 文本：3x5 位图字体 + 度量断言
        Image.ImageBuffer g2 = Image.ImageBuffer.newImage( 320, 240, ColorInt( 10, 14, 24, 255 ) )
        Int32 tw = Image.ImageDraw.textWidth( "HELLO QT" )
        Int32 th = Image.ImageDraw.textHeight()
        bool g2m = false
        if tw >= 20
        {
            if tw <= 40
            {
                if th == 5
                {
                    g2m = true
                }
            }
        }
        ImageQtTest.check( "gallery2 text metrics", g2m )
        Image.ImageDraw.text( g2, 24, 40, "HELLO QT", ColorInt( 120, 240, 160, 255 ) )
        bool hasInk = false
        Int32 yy = 0
        while yy < 5
        {
            Int32 xx = 0
            while xx < 3
            {
                ColorInt pc = g2.getPixel( 24 + xx, 40 + yy )
                if pc.g == 240
                {
                    hasInk = true
                }
                xx = xx + 1
            }
            yy = yy + 1
        }
        ImageQtTest.check( "gallery2 text ink", hasInk )

        # G3 ImageDraw 多边形：三角形填充（质心采样必在内部）
        Image.ImageBuffer g3 = Image.ImageBuffer.newImage( 320, 240, ColorInt( 16, 16, 20, 255 ) )
        List<Int32> xs = List<Int32>()
        List<Int32> ys = List<Int32>()
        xs.add( 30 )
        xs.add( 290 )
        xs.add( 160 )
        ys.add( 30 )
        ys.add( 30 )
        ys.add( 210 )
        Image.ImageDraw.polygon( g3, xs, ys, ColorInt( 200, 60, 255, 255 ), null )
        ColorInt p3 = g3.getPixel( 160, 90 )
        bool g3ok = false
        if p3.r == 200
        {
            if p3.b == 255
            {
                g3ok = true
            }
        }
        ImageQtTest.check( "gallery3 polygon fill", g3ok )

        # G4 ImageMask 渐变蒙版混合：A(红->蓝渐变) x B(纯橙) 水平渐变蒙版
        #   （坑 9 门控下走 SL 兜底，结果与 C 一致，仅慢）
        Image.ImageBuffer a4 = ImageQtTest.makeGradient( 320, 240, ColorInt( 255, 40, 40, 255 ), ColorInt( 40, 40, 255, 255 ) )
        Image.ImageBuffer b4 = Image.ImageBuffer.newImage( 320, 240, ColorInt( 255, 160, 32, 255 ) )
        Image.ImageBuffer m4 = Image.ImageMask.gradientMask( 320, 240, Image.EMaskDirection.Horizontal, 255, 0 )
        Image.ImageBuffer g4 = Image.ImageMask.applyMaskBlend( a4, b4, m4 )
        bool g4ok = false
        if g4 != null
        {
            if g4.width == 320
            {
                if g4.height == 240
                {
                    ColorInt left4 = g4.getPixel( 4, 120 )
                    ColorInt right4 = g4.getPixel( 316, 120 )
                    if left4.g > 150
                    {
                        if right4.g < 60
                        {
                            g4ok = true
                        }
                    }
                }
            }
        }
        ImageQtTest.check( "gallery4 mask gradient blend", g4ok )

        # G5 ImageMask 棋盘混合：纯红 x 纯蓝 32px 棋盘（相邻块必异色）
        Image.ImageBuffer a5 = Image.ImageBuffer.newImage( 320, 240, ColorInt( 220, 40, 40, 255 ) )
        Image.ImageBuffer b5 = Image.ImageBuffer.newImage( 320, 240, ColorInt( 40, 80, 230, 255 ) )
        Image.ImageBuffer g5 = Image.ImageMask.checkerboardBlend( a5, b5, 32 )
        bool g5ok = false
        if g5 != null
        {
            ColorInt qa = g5.getPixel( 2, 120 )
            ColorInt qb = g5.getPixel( 34, 120 )
            if qa.b != qb.b
            {
                g5ok = true
            }
        }
        ImageQtTest.check( "gallery5 checkerboard blend", g5ok )

        # G6 ImageEnhance 亮度 1.5（PIL 外插：degenerate*(1-f)+img*f）
        Image.ImageBuffer base6 = ImageQtTest.makeGradient( 320, 240, ColorInt( 30, 30, 30, 255 ), ColorInt( 200, 200, 200, 255 ) )
        Image.ImageBuffer g6 = Image.ImageEnhance.brightness( base6, 1.5f )
        bool g6ok = false
        if g6 != null
        {
            if g6.width == 320
            {
                ColorInt dark6 = base6.getPixel( 2, 120 )
                ColorInt bright6 = g6.getPixel( 2, 120 )
                if bright6.r > dark6.r
                {
                    g6ok = true
                }
            }
        }
        ImageQtTest.check( "gallery6 enhance brightness 1.5", g6ok )

        # G7 ImageChops softLight（C 快路径 sli_op_chops op=8）
        Image.ImageBuffer a7 = ImageQtTest.makeGradient( 320, 240, ColorInt( 240, 200, 80, 255 ), ColorInt( 60, 80, 200, 255 ) )
        Image.ImageBuffer g7 = Image.ImageChops.softLight( a7, b4 )
        bool g7ok = false
        if g7 != null
        {
            if g7.width == 320
            {
                if g7.height == 240
                {
                    ColorInt pa7 = a7.getPixel( 4, 120 )
                    ColorInt ps7 = g7.getPixel( 4, 120 )
                    if ps7.g != pa7.g
                    {
                        g7ok = true
                    }
                }
            }
        }
        ImageQtTest.check( "gallery7 chops softLight", g7ok )

        # G8 ImageFilter FindEdges（C 快路径 convolve3x3）
        Image.ImageBuffer g8 = Image.ImageFilter.apply( base6, Image.EImageFilter.FindEdges )
        bool g8ok = false
        if g8 != null
        {
            if g8.width == 320
            {
                if g8.height == 240
                {
                    g8ok = true
                }
            }
        }
        ImageQtTest.check( "gallery8 filter findEdges", g8ok )

        # 入廊 + 全量非空断言（8 独立字段，模板参数禁带点 → 不用容器）
        _g0 = g1
        _g1 = g2
        _g2 = g3
        _g3 = g4
        _g4 = g5
        _g5 = g6
        _g6 = g7
        _g7 = g8
        bool allThere = true
        if _g0 == null
        {
            allThere = false
        }
        if _g1 == null
        {
            allThere = false
        }
        if _g2 == null
        {
            allThere = false
        }
        if _g3 == null
        {
            allThere = false
        }
        if _g4 == null
        {
            allThere = false
        }
        if _g5 == null
        {
            allThere = false
        }
        if _g6 == null
        {
            allThere = false
        }
        if _g7 == null
        {
            allThere = false
        }
        ImageQtTest.check( "gallery all 8 non-null", allThere )
    }

    # ── QT 显示核心：toNativeRgba -> setPixmapRgba -> free ──────
    # （QPixmap::fromImage 已深拷贝，显示返回后原生块立即可释放）
    public static void showCurrent()
    {
        if _label == null
        {
            ret
        }
        Int32 idx = _shown
        if idx < 0
        {
            ret
        }
        if idx >= _count
        {
            ret
        }
        Image.ImageBuffer img = null
        if idx == 0
        {
            img = _g0
        }
        if idx == 1
        {
            img = _g1
        }
        if idx == 2
        {
            img = _g2
        }
        if idx == 3
        {
            img = _g3
        }
        if idx == 4
        {
            img = _g4
        }
        if idx == 5
        {
            img = _g5
        }
        if idx == 6
        {
            img = _g6
        }
        if idx == 7
        {
            img = _g7
        }
        if img == null
        {
            ret
        }
        Int64 ptr = img.toNativeRgba()
        if ptr == 0
        {
            Console.println( "[qt] toNativeRgba FAILED on gallery #" + idx.toString() )
            ret
        }
        bool ok = _label.setPixmapRgba( ptr, img.width, img.height )
        Memory.free( ptr )
        if ok
        {
            _pixOk = _pixOk + 1
        }
    }

    # QTimer 900ms 自动轮播
    public static void onTick()
    {
        ImageQtTest.showCurrent()
        _shown = _shown + 1
        if _shown >= _count
        {
            _shown = 0
        }
    }

    # 按钮翻页（静态方法引用桥接，连接 id 在 runQtWindow 断言）
    public static void onPrev()
    {
        _shown = _shown - 1
        if _shown < 0
        {
            _shown = _count - 1
        }
        ImageQtTest.showCurrent()
    }

    public static void onNext()
    {
        _shown = _shown + 1
        if _shown >= _count
        {
            _shown = 0
        }
        ImageQtTest.showCurrent()
    }

    # 60s 超时自动退出（无人值守跑法）
    public static void onQuit()
    {
        if _app != null
        {
            _app.quit()
        }
    }

    # ── QT 窗口画廊（qt 后端真实显示；stub 返回 1 = SKIP）────────
    # 返回协议（仿 RenderTestQt.runQtWindow）：2 = PASS / 1 = SKIP / 0 = FAIL
    public static Int32 runQtWindow()
    {
        string kind = SLang.QT.backendKind()
        if kind != "qt"
        {
            ret 1
        }
        if _count < 1
        {
            ret 0
        }
        _app = SLang.QT.newApp()
        if _app == null
        {
            Console.println( "[qt] FAIL: newApp" )
            ret 0
        }
        SLang.QWidget host = SLang.QT.newWidget( 0 )
        if host == null
        {
            Console.println( "[qt] FAIL: newWidget" )
            ret 0
        }
        host.setTitle( "SLangImage x QT - toNativeRgba -> setPixmapRgba" )
        host.resize( 360, 320 )
        _label = SLang.QT.newLabel( host.handle, "" )
        if _label == null
        {
            Console.println( "[qt] FAIL: newLabel" )
            host.delete()
            ret 0
        }
        _label.setGeometry( 10, 10, 340, 256 )
        _btnPrev = SLang.QT.newButton( host.handle, "<- prev" )
        if _btnPrev == null
        {
            Console.println( "[qt] FAIL: newButton prev" )
            host.delete()
            ret 0
        }
        _btnPrev.setGeometry( 10, 276, 160, 30 )
        _btnNext = SLang.QT.newButton( host.handle, "next ->" )
        if _btnNext == null
        {
            Console.println( "[qt] FAIL: newButton next" )
            host.delete()
            ret 0
        }
        _btnNext.setGeometry( 190, 276, 160, 30 )
        host.show()
        Int64 c1 = _btnPrev.clicked( ImageQtTest.onPrev )
        Int64 c2 = _btnNext.clicked( ImageQtTest.onNext )
        if c1 == 0
        {
            Console.println( "[qt] FAIL: clicked connect prev" )
            host.delete()
            ret 0
        }
        if c2 == 0
        {
            Console.println( "[qt] FAIL: clicked connect next" )
            host.delete()
            ret 0
        }
        Console.println( "[qt] gallery window up: 8 images, 900ms auto-cycle, 60s auto-quit" )
        SLang.QTimer timer = SLang.QT.newTimer( 900, false, ImageQtTest.onTick )
        SLang.QTimer quitter = SLang.QT.newTimer( 60000, true, ImageQtTest.onQuit )
        ImageQtTest.showCurrent()
        _app.exec()
        timer.delete()
        quitter.delete()
        host.delete()
        _label = null
        _btnPrev = null
        _btnNext = null
        if _pixOk < 30
        {
            Console.println( "[qt] FAIL: pixOk=" + _pixOk.toString() + " < 30" )
            ret 0
        }
        Console.println( "[qt] pixOk=" + _pixOk.toString() + " (60s auto-quit path)" )
        ret 2
    }

    # ── 入口：画廊生成断言 + QT 窗口（双后端协议）────────────────
    public static void fun()
    {
        Console.println( "===== ImageQtTest start =====" )
        ImageQtTest.buildGallery()
        Int32 r = ImageQtTest.runQtWindow()
        if r == 2
        {
            ImageQtTest.check( "qt gallery window (pixOk=" + _pixOk.toString() + ")", true )
        }
        if r == 1
        {
            Console.println( "-- [SKIP] qt gallery window: backend=" + SLang.QT.backendKind() + " --" )
        }
        if r == 0
        {
            ImageQtTest.check( "qt gallery window", false )
        }
        Console.println( "===== ImageQtTest end PASS=" + s_pass.toString() + " FAIL=" + s_fail.toString() + " =====" )
    }
}
