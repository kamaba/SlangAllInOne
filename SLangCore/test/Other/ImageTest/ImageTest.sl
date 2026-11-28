# =========================================================================
# ImageTest —— SLangImage 模块端到端测试
#
# 覆盖：
#   1.  原生层可用性（sl_image_lib.dll 预载 + @DllStaticImport 静态绑定）
#   2.  内存往返：PNG / TGA（无损）+ BMP（RGB，alpha 丢）+ JPEG（有损容差）
#   3.  门面层：Png / ImageIO / ImageBuffer / ImageInfo
#   4.  文件路径往返：save -> probeFile -> load -> File.delete 清理
#   5.  错误路径：垃圾字节 / 不存在文件 / 无效 buffer
#   6.  纯 SL 像素运算：setPixel/getPixel / fill / flipY / crop / convertTo
#   7.  GIF 动画拆解/合成：GifEncoder 命令式逐帧合成 / GifDocument 声明式 /
#       Gif.decode 拆解回帧（延迟 / 循环数 / 透明语义 / 量化容差 / LZW
#       满表大帧字节精确） / ImageIO 静态 GIF 单帧路径 / 文件往返 / 错误路径
#   8.  ImageSequence（仿 Pillow ImageSequence）：iterator + moveNext /
#       seek / tell / nFrames / for-in / allFrames / allImages /
#       framesOfImage / frameCount / saveFrame / saveAllFrames / 错误路径
#   9.  仿 Pillow Image 模块方法集：newImage / paste / rotate（任意角 +
#       expand 包围盒）/ splitChannels / mergeRgba / mergeRgb /
#       alphaComposite / blend / ImageFilter（Blur/Contour/Emboss/
#       FindEdges/Sharpen/Smooth/Detail/EdgeEnhance + convolve3x3 通用核）/
#       ImageIO.show 临时落盘
#   10. C 层像素批量运算（sli_op_*）：resize 最近邻采样精确 / 双线性角点 /
#       convertTo Gray8 BT.601 / premultiply 往返 / flipX 行反转
#       （重循环已下沉 sl_image_lib.dll，绑定失败自动回落纯 SL 循环）
#   11. 仿 Pillow advanced：ImageChops（8 通道运算 + softLight/hardLight）/
#       ImageEnhance（brightness/contrast/color/sharpness）/ ImageMask（渐变/
#       圆形/条纹蒙版 + applyMaskBlend/transitionBlend/checkerboardBlend/
#       pasteMasked）/ ImageDraw（point/line/rect/ellipse/circle/arc/polygon/
#       3x5 位图 text）+ 绘制画布 PNG 往返
#
# 运行：dotnet run --project Project\CSimpleVMTest\CSimpleVMTest.csproj --
#       SLangCore\test\Other\ImageTest\ProjectTest.jsonc
# =========================================================================

import Std;
import SLangImage;

class ImageTest
{
    static int s_pass = 0
    static int s_fail = 0

    static void check( string name, bool ok )
    {
        if ok
        {
            s_pass = s_pass + 1
            Console.println( "[PASS] " + name )
        }
        else
        {
            s_fail = s_fail + 1
            Console.println( "[FAIL] " + name )
        }
    }

    # w x h RGBA8 渐变图（R 随 x、G 随 y、B 随 x+y，alpha 恒 255）
    static Image.ImageBuffer makeGradient( int w, int h )
    {
        Image.ImageBuffer b = Image.ImageBuffer( w, h, Image.EPixelFormat.Rgba8 )
        int y = 0
        while y < h
        {
            int x = 0
            while x < w
            {
                int r = ( x * 255 ) / ( w - 1 )
                int g = ( y * 255 ) / ( h - 1 )
                int bl = ( ( x + y ) * 255 ) / ( w + h - 2 )
                b.setPixel( x, y, ColorInt( r, g, bl, 255 ) )
                x = x + 1
            }
            y = y + 1
        }
        ret b
    }

    # 逐字节比较（无损往返判定）
    static bool bytesEqual( Array<UInt8> a, Array<UInt8> b )
    {
        if a == null || b == null
        {
            ret false
        }
        if a.length != b.length
        {
            ret false
        }
        int i = 0
        while i < a.length
        {
            if a[ i ] != b[ i ]
            {
                ret false
            }
            i = i + 1
        }
        ret true
    }

    # 逐像素比较两个 buffer 指定坐标（含 alpha）
    static bool pixSame( Image.ImageBuffer a, int ax, int ay, Image.ImageBuffer b, int bx, int by )
    {
        if a == null || b == null
        {
            ret false
        }
        ColorInt ca = a.getPixel( ax, ay )
        ColorInt cb = b.getPixel( bx, by )
        ret ca.r == cb.r && ca.g == cb.g && ca.b == cb.b && ca.a == cb.a
    }

    # ImageDraw 空实参安全（null img / null 颜色不崩溃）
    static bool t187nulls( Image.ImageBuffer canvas )
    {
        Image.ImageDraw.point( null, 0, 0, ColorInt.black() )
        Image.ImageDraw.point( canvas, 0, 0, null )
        Image.ImageDraw.line( null, 0, 0, 1, 1, ColorInt.black(), 1 )
        Image.ImageDraw.rectangle( null, 0, 0, 1, 1, ColorInt.black(), null, 1 )
        Image.ImageDraw.ellipse( null, 0, 0, 1, 1, ColorInt.black(), null, 1 )
        Image.ImageDraw.arc( null, 0, 0, 1, 1, 0, 90, ColorInt.black(), 1 )
        Image.ImageDraw.text( null, 0, 0, "X", ColorInt.black() )
        Image.ImageDraw.polygon( null, null, null, ColorInt.black(), null )
        ret true
    }

    # RGB 逐像素比较（BMP 等 alpha 丢弃格式）
    static bool rgbEquals( Image.ImageBuffer a, Image.ImageBuffer b )
    {
        if a == null || b == null
        {
            ret false
        }
        if a.width != b.width || a.height != b.height
        {
            ret false
        }
        int y = 0
        while y < a.height
        {
            int x = 0
            while x < a.width
            {
                ColorInt ca = a.getPixel( x, y )
                ColorInt cb = b.getPixel( x, y )
                if ca.r != cb.r || ca.g != cb.g || ca.b != cb.b
                {
                    ret false
                }
                x = x + 1
            }
            y = y + 1
        }
        ret true
    }

    # 有损往返：RGB 平均每通道误差
    static Int32 lossyAvgError( Image.ImageBuffer a, Image.ImageBuffer b )
    {
        if a == null || b == null
        {
            ret 999999
        }
        Int32 total = 0
        int y = 0
        while y < a.height
        {
            int x = 0
            while x < a.width
            {
                ColorInt ca = a.getPixel( x, y )
                ColorInt cb = b.getPixel( x, y )
                Int32 dr = ca.r - cb.r
                Int32 dg = ca.g - cb.g
                Int32 db = ca.b - cb.b
                if dr < 0
                {
                    dr = 0 - dr
                }
                if dg < 0
                {
                    dg = 0 - dg
                }
                if db < 0
                {
                    db = 0 - db
                }
                total = total + dr + dg + db
                x = x + 1
            }
            y = y + 1
        }
        Int32 count = a.width * a.height * 3
        ret total / count
    }

    # 4 色象限图（shift 轮转配色；多帧共享同一 4 色全局调色板 -> 精确直配）
    static Image.ImageBuffer makeQuads( int w, int h, int shift )
    {
        Image.ImageBuffer b = Image.ImageBuffer( w, h, Image.EPixelFormat.Rgba8 )
        int y = 0
        while y < h
        {
            int x = 0
            while x < w
            {
                int q = 3
                if y < h / 2
                {
                    if x < w / 2 { q = 0 } else { q = 1 }
                }
                else
                {
                    if x < w / 2 { q = 2 } else { q = 3 }
                }
                int c = ( q + shift ) % 4
                if c == 0 { b.setPixel( x, y, ColorInt( 200, 40, 80, 255 ) ) }
                elif c == 1 { b.setPixel( x, y, ColorInt( 40, 200, 120, 255 ) ) }
                elif c == 2 { b.setPixel( x, y, ColorInt( 80, 60, 200, 255 ) ) }
                else { b.setPixel( x, y, ColorInt( 230, 200, 60, 255 ) ) }
                x = x + 1
            }
            y = y + 1
        }
        ret b
    }

    # 象限图（左上象限 alpha 0 透明，其余不透明）
    static Image.ImageBuffer makeQuadsAlpha( int w, int h )
    {
        Image.ImageBuffer b = Image.ImageBuffer( w, h, Image.EPixelFormat.Rgba8 )
        int y = 0
        while y < h
        {
            int x = 0
            while x < w
            {
                if y < h / 2 && x < w / 2
                {
                    b.setPixel( x, y, ColorInt( 200, 40, 80, 0 ) )
                }
                elif y < h / 2
                {
                    b.setPixel( x, y, ColorInt( 40, 200, 120, 255 ) )
                }
                elif x < w / 2
                {
                    b.setPixel( x, y, ColorInt( 80, 60, 200, 255 ) )
                }
                else
                {
                    b.setPixel( x, y, ColorInt( 230, 200, 60, 255 ) )
                }
                x = x + 1
            }
            y = y + 1
        }
        ret b
    }

    # ncolors 种纯色（r=k,0,0）LCG 伪随机布点：唯一色 <= 255 精确直配，
    # 16384 像素长流把 LZW 词典推过 4096 满表（CLEAR 复位路径）
    static Image.ImageBuffer makeNoise( int w, int h, int ncolors )
    {
        Image.ImageBuffer b = Image.ImageBuffer( w, h, Image.EPixelFormat.Rgba8 )
        int seed = 1
        int y = 0
        while y < h
        {
            int x = 0
            while x < w
            {
                seed = ( seed * 75 ) % 65537
                int k = seed % ncolors
                b.setPixel( x, y, ColorInt( k, 0, 0, 255 ) )
                x = x + 1
            }
            y = y + 1
        }
        ret b
    }

    static fun()
    {
        Console.println( "" )
        Console.println( "===== ImageTest start =====" )

        # ── 1. 原生层可用性 ──────────────────────────────────────
        check( "T01 ImageFfi.ensureReady (DLL 预载 + 静态绑定)", Image.ImageFfi.ensureReady() )
        string ver = Image.ImageFfi.libVersionString()
        Console.println( "sl_image_lib version = " + ver )
        check( "T02 libVersionString not empty", ver != "" )
        string codecs = Image.ImageFfi.libCodecList()
        Console.println( "codecs = " + codecs )
        check( "T03 libCodecList not empty", codecs != "" )

        # ── 2. 测试图 ────────────────────────────────────────────
        int w = 64
        int h = 48
        Image.ImageBuffer grad = ImageTest.makeGradient( w, h )
        check( "T04 gradient buffer valid", grad != null && grad.isValid )
        Array<UInt8> rgba = Image.ImageFfi.rgbaBytesOf( grad )
        check( "T05 rgbaBytesOf size == w*h*4", rgba != null && rgba.length == w * h * 4 )

        # ── 3. PNG 无损往返（encodeMem / probeMem / decodeMem）───
        Array<UInt8> png = Image.ImageFfi.encodeMem( Image.EImageFormat.Png, 100, w, h, rgba )
        check( "T06 png encodeMem not null", png != null )
        check( "T07 png bytes > 100", png != null && png.length > 100 )
        Image.ImageInfo pi = Image.ImageFfi.probeMem( png )
        check( "T08 png probeMem format", pi.format == Image.EImageFormat.Png )
        check( "T09 png probeMem width/height", pi.width == w && pi.height == h )
        Image.ImageBuffer pback = Image.ImageFfi.decodeMem( png )
        check( "T10 png decodeMem not null", pback != null )
        check( "T11 png decode w/h", pback.width == w && pback.height == h )
        check( "T12 png decode pixelFormat RGBA8", pback.pixelFormat == Image.EPixelFormat.Rgba8 )
        bool pngSame = false
        if pback != null
        {
            pngSame = ImageTest.bytesEqual( rgba, pback.pixelBytes() )
        }
        check( "T13 png roundtrip lossless (byte-exact)", pngSame )

        # ── 4. TGA 无损往返（stb 默认 RLE）──────────────────────
        Array<UInt8> tga = Image.ImageFfi.encodeMem( Image.EImageFormat.Tga, 100, w, h, rgba )
        check( "T14 tga encodeMem not null", tga != null )
        Image.ImageBuffer tback = Image.ImageFfi.decodeMem( tga )
        check( "T15 tga decode not null", tback != null )
        check( "T16 tga decode w/h", tback.width == w && tback.height == h )
        check( "T17 tga roundtrip lossless", ImageTest.rgbEquals( grad, tback ) )

        # ── 5. BMP 往返（24 位 BGR，alpha 丢弃后回读为 255）─────
        Array<UInt8> bmp = Image.ImageFfi.encodeMem( Image.EImageFormat.Bmp, 100, w, h, rgba )
        check( "T18 bmp encodeMem not null", bmp != null )
        Image.ImageBuffer bback = Image.ImageFfi.decodeMem( bmp )
        check( "T19 bmp decode not null", bback != null )
        check( "T20 bmp decode w/h", bback.width == w && bback.height == h )
        check( "T21 bmp roundtrip RGB exact", ImageTest.rgbEquals( grad, bback ) )
        bool bmpAlpha255 = false
        if bback != null
        {
            ColorInt c0 = bback.getPixel( w / 2, h / 2 )
            bmpAlpha255 = c0.a == 255
        }
        check( "T22 bmp decode alpha == 255", bmpAlpha255 )

        # ── 6. JPEG 有损往返（质量 90）──────────────────────────
        Array<UInt8> jpg = Image.ImageFfi.encodeMem( Image.EImageFormat.Jpeg, 90, w, h, rgba )
        check( "T23 jpeg encodeMem not null", jpg != null )
        Image.ImageBuffer jback = Image.ImageFfi.decodeMem( jpg )
        check( "T24 jpeg decode not null", jback != null )
        check( "T25 jpeg decode w/h", jback.width == w && jback.height == h )
        Int32 jerr = ImageTest.lossyAvgError( grad, jback )
        Console.println( "jpeg avg per-channel error = " + jerr.toString() )
        check( "T26 jpeg avg error < 12", jerr < 12 )
        Image.ImageInfo ji = Image.ImageFfi.probeMem( jpg )
        check( "T27 jpeg probeMem format", ji.format == Image.EImageFormat.Jpeg )
        check( "T28 jpeg probeMem w/h", ji.width == w && ji.height == h )

        # ── 7. 门面层：Png / ImageIO / ImageBuffer / ImageInfo ──
        Array<UInt8> png2 = Image.Png.encode( grad, Image.PngEncodeOptions.defaultOptions() )
        check( "T29 Png.encode facade not null", png2 != null )
        Image.ImageBuffer pback2 = Image.Png.decode( png2 )
        check( "T30 Png.decode facade w/h", pback2 != null && pback2.width == w && pback2.height == h )
        Array<UInt8> tga2 = Image.ImageIO.encode( grad, Image.EImageFormat.Tga, 100 )
        check( "T31 ImageIO.encode(Tga) not null", tga2 != null )
        Image.ImageBuffer tback2 = Image.ImageIO.decode( tga2, Image.EImageFormat.Tga )
        check( "T32 ImageIO.decodeAs w/h", tback2 != null && tback2.width == w && tback2.height == h )
        Image.ImageBuffer dback = Image.ImageBuffer.decode( png2 )
        check( "T33 ImageBuffer.decode static w/h", dback != null && dback.width == w && dback.height == h )
        Image.ImageInfo pinfo = Image.ImageInfo.probe( png2 )
        check( "T34 ImageInfo.probe format Png", pinfo.format == Image.EImageFormat.Png )
        check( "T35 ImageInfo.probe w/h", pinfo.width == w && pinfo.height == h )

        # ── 8. 文件路径往返（save -> probeFile -> load）──────────
        string tmp = "image_test_tmp_gradient.png"
        bool saved = Image.ImageIO.save( grad, tmp, Image.EImageFormat.Png, 100 )
        check( "T36 ImageIO.save png ok", saved )
        Image.ImageInfo fi = Image.ImageIO.probeFile( tmp )
        check( "T37 probeFile w/h", fi.width == w && fi.height == h )
        check( "T38 probeFile format Png", fi.format == Image.EImageFormat.Png )
        Image.ImageBuffer loaded = Image.ImageIO.load( tmp )
        check( "T39 ImageIO.load not null", loaded != null )
        check( "T40 load w/h", loaded != null && loaded.width == w && loaded.height == h )
        bool loadSame = false
        if loaded != null
        {
            loadSame = ImageTest.rgbEquals( grad, loaded )
        }
        check( "T41 load roundtrip RGB exact", loadSame )
        check( "T42 File.delete cleanup", File.delete( tmp ) )
        check( "T43 File.exists false after delete", !File.exists( tmp ) )

        # ── 9. 错误路径 ──────────────────────────────────────────
        Array<UInt8> garbage = Array<UInt8>( 32 )
        Int32 gi = 0
        while gi < 32
        {
            garbage[ gi ] = SystemConvertUInt8( 0x5A )
            gi = gi + 1
        }
        check( "T44 decodeMem(garbage) == null", Image.ImageFfi.decodeMem( garbage ) == null )
        Image.ImageInfo ginfo = Image.ImageFfi.probeMem( garbage )
        check( "T45 probeMem(garbage) format Unknown", ginfo.format == Image.EImageFormat.Unknown )
        Image.ImageInfo ninfo = Image.ImageIO.probeFile( "no_such_file_xyz.png" )
        check( "T46 probeFile(missing) width == 0", ninfo.width == 0 )
        check( "T47 load(missing) == null", Image.ImageIO.load( "no_such_file_xyz.png" ) == null )
        Image.ImageBuffer bad = Image.ImageBuffer( 0, 0 )
        check( "T48 encode(invalid buffer) == null", Image.ImageFfi.rgbaBytesOf( bad ) == null )

        # ── 10. 纯 SL 像素运算（不经 FFI）───────────────────────
        Image.ImageBuffer px = Image.ImageBuffer( 8, 8, Image.EPixelFormat.Rgba8 )
        px.setPixel( 3, 5, ColorInt( 10, 20, 30, 40 ) )
        ColorInt pc = px.getPixel( 3, 5 )
        check( "T49 setPixel/getPixel", pc.r == 10 && pc.g == 20 && pc.b == 30 && pc.a == 40 )
        px.fill( ColorInt( 255, 0, 0 ) )
        ColorInt fc = px.getPixel( 0, 0 )
        check( "T50 fill", fc.r == 255 && fc.g == 0 && fc.b == 0 )
        Image.ImageBuffer fy = grad.clone()
        fy.flipY()
        ColorInt topSrc = grad.getPixel( 0, h - 1 )
        ColorInt topDst = fy.getPixel( 0, 0 )
        check( "T51 flipY", topSrc.r == topDst.r && topSrc.g == topDst.g && topSrc.b == topDst.b )
        Image.ImageBuffer cr = grad.crop( 8, 6, 16, 12 )
        check( "T52 crop w/h", cr != null && cr.width == 16 && cr.height == 12 )
        Image.ImageBuffer gray = grad.convertTo( Image.EPixelFormat.Gray8 )
        check( "T53 convertTo Gray8 channels == 1", gray != null && gray.channelCount == 1 )
        Image.ImageBuffer backRgba = gray.convertTo( Image.EPixelFormat.Rgba8 )
        check( "T54 Gray8 -> Rgba8 channels == 4", backRgba != null && backRgba.channelCount == 4 )

        # ── 11. GIF 动画拆解 / 合成 ─────────────────────────────
        # 11a. 命令式编码器：new -> addFrameWithDelay x3 -> build（一次性）
        int qw = 32
        int qh = 24
        Image.ImageBuffer q1 = ImageTest.makeQuads( qw, qh, 0 )
        Image.ImageBuffer q2 = ImageTest.makeQuads( qw, qh, 1 )
        Image.ImageBuffer q3 = ImageTest.makeQuads( qw, qh, 2 )
        Image.GifEncoder genc = Image.GifEncoder( qw, qh, 0 )
        check( "T55 GifEncoder ctor valid", genc != null && genc.isValid )
        bool addAll = genc.addFrameWithDelay( q1, 0 )
        addAll = genc.addFrameWithDelay( q2, 100 ) && addAll
        addAll = genc.addFrameWithDelay( q3, 250 ) && addAll
        check( "T56 GifEncoder addFrameWithDelay x3", addAll )
        check( "T57 GifEncoder frameCount == 3", genc.frameCount == 3 )
        Array<UInt8> anim = genc.build()
        check( "T58 GifEncoder.build not null", anim != null )
        check( "T59 gif bytes > 100", anim != null && anim.length > 100 )
        check( "T60 GifEncoder one-shot after build", !genc.isValid && !genc.addFrame( q1 ) )
        genc.close()

        # 11b. 容器嗅探（probeMem 识别 GIF）
        Image.ImageInfo gpi = null
        if anim != null
        {
            gpi = Image.ImageFfi.probeMem( anim )
        }
        check( "T61 gif probeMem format", gpi != null && gpi.format == Image.EImageFormat.Gif )
        check( "T62 gif probeMem w/h", gpi != null && gpi.width == qw && gpi.height == qh )

        # 11c. 拆解：Gif.decode -> GifDocument（循环 / 延迟 / 像素全对）
        Image.GifDocument doc = Image.Gif.decode( anim )
        check( "T63 Gif.decode doc not null", doc != null )
        check( "T64 gif doc w/h", doc != null && doc.width == qw && doc.height == qh )
        check( "T65 gif doc frameCount == 3", doc != null && doc.frameCount == 3 )
        check( "T66 gif doc loopCount == 0 (infinite)", doc != null && doc.loopCount == 0 )
        Image.GifFrame gf0 = null
        Image.GifFrame gf1 = null
        Image.GifFrame gf2 = null
        if doc != null
        {
            gf0 = doc.frameAt( 0 )
            gf1 = doc.frameAt( 1 )
            gf2 = doc.frameAt( 2 )
        }
        check( "T67 gif frame delays [0,100,250]ms", gf0 != null && gf1 != null && gf2 != null && gf0.delayMs == 0 && gf1.delayMs == 100 && gf2.delayMs == 250 )
        bool f0same = false
        bool f1same = false
        bool f2same = false
        if gf0 != null && gf1 != null && gf2 != null
        {
            f0same = ImageTest.bytesEqual( q1.pixelBytes(), gf0.image.pixelBytes() )
            f1same = ImageTest.bytesEqual( q2.pixelBytes(), gf1.image.pixelBytes() )
            f2same = ImageTest.bytesEqual( q3.pixelBytes(), gf2.image.pixelBytes() )
        }
        check( "T68 gif frame0 byte-exact (palette direct hit)", f0same )
        check( "T69 gif frame1 byte-exact", f1same )
        check( "T70 gif frame2 byte-exact", f2same )
        check( "T71 gif frameAt out-of-range -> null", doc != null && doc.frameAt( 3 ) == null && doc.frameAt( -1 ) == null )

        # 11d. 单帧渐变：量化容差 + 无 NETSCAPE（2 参 ctor，loopCount -1）
        Image.GifEncoder ggrad = Image.GifEncoder( w, h )
        bool gAdd = ggrad.addFrame( grad )
        Array<UInt8> gbytes = ggrad.build()
        check( "T72 single-frame gradient gif built", gAdd && gbytes != null )
        Image.GifDocument gdoc = Image.Gif.decode( gbytes )
        check( "T73 gradient gif frameCount == 1 && loopCount == -1", gdoc != null && gdoc.frameCount == 1 && gdoc.loopCount == -1 )
        Int32 gerr = 999999
        if gdoc != null
        {
            Image.GifFrame gfr = gdoc.frameAt( 0 )
            if gfr != null
            {
                gerr = ImageTest.lossyAvgError( grad, gfr.image )
            }
        }
        Console.println( "gif gradient avg per-channel error = " + gerr.toString() )
        check( "T74 gradient gif avg error < 24", gerr < 24 )

        # 11e. 透明语义：alpha 0 象限 <-> GCE 透明索引
        Image.ImageBuffer qa = ImageTest.makeQuadsAlpha( qw, qh )
        Image.GifEncoder tenc = Image.GifEncoder( qw, qh, -1 )
        bool tAdd = tenc.addFrameWithDelay( qa, 80 )
        Array<UInt8> tbytes = tenc.build()
        Image.GifDocument tdoc = Image.Gif.decode( tbytes )
        bool tA0 = false
        bool tA255 = false
        if tdoc != null
        {
            Image.GifFrame tfr = tdoc.frameAt( 0 )
            if tfr != null
            {
                Image.ImageBuffer tb = tfr.image
                ColorInt ta = tb.getPixel( qw / 4, qh / 4 )
                ColorInt tc1 = tb.getPixel( qw * 3 / 4, qh / 4 )
                ColorInt tc2 = tb.getPixel( qw / 4, qh * 3 / 4 )
                ColorInt tc3 = tb.getPixel( qw * 3 / 4, qh * 3 / 4 )
                tA0 = ta.a == 0
                tA255 = tc1.a == 255 && tc2.a == 255 && tc3.a == 255
            }
        }
        check( "T75 gif transparent quadrant roundtrip", tAdd && tbytes != null && tdoc != null && tA0 && tA255 )

        # 11f. LZW 词典长流：128x128、200 色噪声（palette 精确直配 -> 字节
        #      精确往返；词典必然越过 4096 满表走 CLEAR 复位路径）
        Image.ImageBuffer nz = ImageTest.makeNoise( 128, 128, 200 )
        Image.GifEncoder nenc = Image.GifEncoder( 128, 128, 0 )
        bool nAdd = nenc.addFrameWithDelay( nz, 40 )
        Array<UInt8> nbytes = nenc.build()
        Image.GifDocument ndoc = Image.Gif.decode( nbytes )
        bool nSame = false
        if nAdd && ndoc != null
        {
            Image.GifFrame nfr = ndoc.frameAt( 0 )
            if nfr != null
            {
                nSame = ImageTest.bytesEqual( nz.pixelBytes(), nfr.image.pixelBytes() )
            }
        }
        check( "T76 gif noise 200-color byte-exact (LZW dict fills)", nSame )

        # 11g. ImageIO 静态 GIF（单帧走 SLI_FMT_GIF 静态路径）
        Array<UInt8> sgif = Image.ImageIO.encode( q1, Image.EImageFormat.Gif, 100 )
        check( "T77 ImageIO.encode(Gif) not null", sgif != null )
        Image.ImageInfo sinfo = null
        if sgif != null
        {
            sinfo = Image.ImageFfi.probeMem( sgif )
        }
        check( "T78 static gif probeMem format+w/h", sinfo != null && sinfo.format == Image.EImageFormat.Gif && sinfo.width == qw && sinfo.height == qh )
        Image.ImageBuffer sback = null
        if sgif != null
        {
            sback = Image.ImageIO.decode( sgif, Image.EImageFormat.Gif )
        }
        bool sSame = false
        if sback != null
        {
            sSame = ImageTest.bytesEqual( q1.pixelBytes(), sback.pixelBytes() )
        }
        check( "T79 static gif decode byte-exact", sSame )

        # 11h. 声明式文档 + 文件往返（encode / decodeFrames / save / decodeFile）
        Image.GifDocument mdoc = Image.GifDocument( qw, qh )
        mdoc.loopCount = 3
        bool m1 = mdoc.addFrameWithDelay( q1, 50 )
        bool m2 = mdoc.addFrameWithDelay( q2, 60 )
        Array<UInt8> mbytes = Image.Gif.encode( mdoc )
        check( "T80 Gif.encode(doc) not null", m1 && m2 && mbytes != null )
        var mfr = Image.Gif.decodeFrames( mbytes )
        check( "T81 Gif.decodeFrames length == 2", mfr != null && mfr.length == 2 )
        string tmpAnim = "image_test_tmp_anim.gif"
        bool animSaved = Image.Gif.save( mdoc, tmpAnim )
        check( "T82 Gif.save file ok", animSaved )
        Image.GifDocument fdoc = Image.Gif.decodeFile( tmpAnim )
        check( "T83 Gif.decodeFile not null", fdoc != null )
        check( "T84 file gif frameCount == 2 && loopCount == 3", fdoc != null && fdoc.frameCount == 2 && fdoc.loopCount == 3 )
        bool fdelay = false
        bool fpix = false
        if fdoc != null
        {
            Image.GifFrame ffr0 = fdoc.frameAt( 0 )
            Image.GifFrame ffr1 = fdoc.frameAt( 1 )
            if ffr0 != null && ffr1 != null
            {
                fdelay = ffr0.delayMs == 50 && ffr1.delayMs == 60
                fpix = ImageTest.bytesEqual( q1.pixelBytes(), ffr0.image.pixelBytes() )
            }
        }
        check( "T85 file gif delays [50,60]ms", fdelay )
        check( "T86 file gif frame0 byte-exact", fpix )
        check( "T87 File.delete anim cleanup", File.delete( tmpAnim ) )

        # 11i. 错误路径
        check( "T88 Gif.decode(garbage) == null", Image.Gif.decode( garbage ) == null )
        check( "T89 Gif.decodeFile(missing) == null", Image.Gif.decodeFile( "no_such_file_xyz.gif" ) == null )
        check( "T90 Gif.encode(null) == null", Image.Gif.encode( null ) == null )
        check( "T91 Gif.save(null, path) == false", !Image.Gif.save( null, "image_test_tmp_null.gif" ) )
        Image.GifDocument edoc = Image.GifDocument( qw, qh )
        check( "T92 Gif.encode(empty doc) == null", Image.Gif.encode( edoc ) == null )
        Image.GifEncoder zenc = Image.GifEncoder( qw, qh )
        Array<UInt8> zbytes = zenc.build()
        check( "T93 empty GifEncoder.build == null && invalid", zbytes == null && !zenc.isValid )
        Image.ImageBuffer smol = Image.ImageBuffer( 16, 12, Image.EPixelFormat.Rgba8 )
        check( "T94 GifDocument.addFrameWithDelay rejects mismatch/null", !edoc.addFrameWithDelay( smol, 10 ) && !edoc.addFrame( null ) )
        Image.GifEncoder mism = Image.GifEncoder( qw, qh )
        check( "T95 GifEncoder.addFrame rejects mismatch/null", !mism.addFrame( smol ) && !mism.addFrame( null ) )
        mism.close()

        # ── 12. ImageSequence（仿 Pillow ImageSequence 模块）────────
        # https://www.runoob.com/pillow/imagesequence-module.html
        # 12a. 迭代器手动游标（moveNext / tell / seek / nFrames）
        Image.ImageSequenceIterator sit = Image.ImageSequence.iterator( doc )
        check( "T96 ImageSequence.iterator not null", sit != null )
        check( "T97 iterator isValid && nFrames == 3", sit != null && sit.isValid && sit.nFrames == 3 )
        bool t98 = false
        bool t99 = false
        bool t100 = false
        bool t101 = false
        bool t102 = false
        if sit != null
        {
            t98 = sit.moveNext() && sit.tell() == 0 && sit.current != null && sit.current.delayMs == 0
            t99 = sit.moveNext() && sit.tell() == 1 && sit.current != null && sit.current.delayMs == 100
            t100 = sit.seek( 2 ) && sit.tell() == 2 && sit.current != null && sit.current.delayMs == 250
            t101 = !sit.seek( 3 ) && !sit.seek( -1 ) && sit.tell() == 2
            t102 = !sit.moveNext() && sit.tell() == 2
        }
        check( "T98 moveNext -> frame0 (tell=0, delay 0)", t98 )
        check( "T99 moveNext -> frame1 (tell=1, delay 100)", t99 )
        check( "T100 seek(2) -> tell=2, delay 250", t100 )
        check( "T101 seek out-of-range rejected", t101 )
        check( "T102 moveNext false at end after seek(2)", t102 )

        # 12b. for-in 遍历（重置后全帧 + 延迟累加）
        Int32 seqCount = 0
        Int32 seqDelaySum = 0
        bool t103 = false
        if sit != null
        {
            sit.reset()
            for f in sit
            {
                seqCount = seqCount + 1
                seqDelaySum = seqDelaySum + f.delayMs
            }
            t103 = seqCount == 3 && seqDelaySum == 350
        }
        check( "T103 for-in iterates 3 frames, delay sum 350", t103 )

        # 12c. allFrames / allImages / allFramesOf
        var allF = Image.ImageSequence.allFrames( doc )
        check( "T104 allFrames length == 3", allF != null && allF.length == 3 )
        var allI = Image.ImageSequence.allImages( doc )
        check( "T105 allImages length == 3", allI != null && allI.length == 3 )
        var allB = Image.ImageSequence.allFramesOf( anim )
        check( "T106 allFramesOf(bytes) length == 3", allB != null && allB.length == 3 )
        Image.ImageBuffer seqImg0 = null
        if allI != null && allI.length == 3
        {
            seqImg0 = allI[ 0 ]
        }
        bool t107 = false
        if seqImg0 != null
        {
            t107 = ImageTest.bytesEqual( q1.pixelBytes(), seqImg0.pixelBytes() )
        }
        check( "T107 allImages[0] byte-exact vs frame0", t107 )

        # 12d. framesOfImage / frameCount 门面
        var sf = Image.ImageSequence.framesOfImage( q1 )
        check( "T108 framesOfImage -> single frame", sf != null && sf.length == 1 )
        check( "T109 frameCount(doc) == 3", Image.ImageSequence.frameCount( doc ) == 3 )
        check( "T110 frameCountOfImage q1==1 / null==0", Image.ImageSequence.frameCountOfImage( q1 ) == 1 && Image.ImageSequence.frameCountOfImage( null ) == 0 )

        # 12e. 错误路径（空迭代器 / 空列表）
        Image.ImageSequenceIterator badIt = Image.ImageSequence.iteratorOf( garbage )
        check( "T111 iteratorOf(garbage) empty iterator", badIt != null && !badIt.isValid && badIt.nFrames == 0 && !badIt.moveNext() )
        Image.ImageSequenceIterator nullIt = Image.ImageSequence.iterator( null )
        check( "T112 iterator(null doc) empty iterator", nullIt != null && nullIt.nFrames == 0 && !nullIt.seek( 0 ) )
        var nullFrames = Image.ImageSequence.allFrames( null )
        check( "T113 allFrames(null) empty list", nullFrames != null && nullFrames.length == 0 )

        # 12f. 帧落盘（教程示例 1：frame.save(f'frame_{i}.png')）
        Image.GifFrame seqF1 = null
        if allF != null && allF.length == 3
        {
            seqF1 = allF[ 1 ]
        }
        bool t114 = false
        if seqF1 != null
        {
            t114 = Image.ImageSequence.saveFrame( seqF1, "image_test_seq_frame1.png" )
        }
        check( "T114 saveFrame(frame1) -> png", t114 )
        check( "T115 saved frame file exists", File.exists( "image_test_seq_frame1.png" ) )
        Image.ImageBuffer reF = Image.ImageIO.load( "image_test_seq_frame1.png" )
        bool t116 = false
        if reF != null
        {
            t116 = ImageTest.rgbEquals( q2, reF )
        }
        check( "T116 saved frame reload RGB exact", t116 )
        check( "T117 File.delete frame cleanup", File.delete( "image_test_seq_frame1.png" ) )
        Int32 savedCount = Image.ImageSequence.saveAllFrames( doc, "image_test_seq_" )
        check( "T118 saveAllFrames saved 3 frames", savedCount == 3 )
        check( "T119 saveAllFrames files exist", File.exists( "image_test_seq_0.png" ) && File.exists( "image_test_seq_1.png" ) && File.exists( "image_test_seq_2.png" ) )
        check( "T120 cleanup seq frame files", File.delete( "image_test_seq_0.png" ) && File.delete( "image_test_seq_1.png" ) && File.delete( "image_test_seq_2.png" ) )

        # ── 13. 仿 Pillow Image 模块方法集 ────────────────────
        # https://www.runoob.com/pillow/pillow-image-module.html
        # 13a. newImage（Image.new）
        Image.ImageBuffer solidRed = Image.ImageBuffer.newImage( 6, 4, ColorInt( 255, 0, 0, 255 ) )
        ColorInt nc = solidRed.getPixel( 2, 2 )
        check( "T121 newImage(w,h,color) solid fill", solidRed != null && solidRed.isValid && solidRed.width == 6 && solidRed.height == 4 && nc.r == 255 && nc.g == 0 && nc.b == 0 && nc.a == 255 )
        Image.ImageBuffer solidNull = Image.ImageBuffer.newImage( 5, 5 )
        ColorInt tc = solidNull.getPixel( 0, 0 )
        check( "T122 newImage(w,h) default transparent", solidNull != null && solidNull.isValid && tc.a == 0 )

        # 13b. paste（Image.paste）
        Image.ImageBuffer pasteBase = Image.ImageBuffer.newImage( 8, 8, ColorInt.white() )
        Image.ImageBuffer pasteSrc = Image.ImageBuffer.newImage( 4, 2, ColorInt( 0, 0, 255, 255 ) )
        bool pasted = pasteBase.paste( pasteSrc, 2, 3 )
        ColorInt pIn = pasteBase.getPixel( 3, 3 )
        ColorInt pOut = pasteBase.getPixel( 1, 2 )
        check( "T123 paste inside blue / outside white", pasted && pIn.b == 255 && pIn.r == 0 && pOut.r == 255 && pOut.b == 255 )
        Image.ImageBuffer clipBase = Image.ImageBuffer.newImage( 8, 8, ColorInt.white() )
        bool clipped = clipBase.paste( pasteSrc, 6, 6 )
        ColorInt c66 = clipBase.getPixel( 6, 6 )
        ColorInt c55 = clipBase.getPixel( 5, 5 )
        check( "T124 paste clipped at right-bottom", clipped && c66.b == 255 && c66.r == 0 && c55.r == 255 && c55.b == 255 )
        check( "T125 paste(null) == false", !clipBase.paste( null, 0, 0 ) )

        # 13c. rotate（Image.rotate，正角 = 逆时针）
        Image.ImageBuffer rot180 = grad.rotate( 180.0f )
        bool r180ok = rot180 != null && rot180.width == w && rot180.height == h
        if r180ok
        {
            Int32 ry = 0
            while ry < h && r180ok
            {
                Int32 rx = 0
                while rx < w && r180ok
                {
                    r180ok = ImageTest.pixSame( rot180, rx, ry, grad, w - 1 - rx, h - 1 - ry )
                    rx = rx + 1
                }
                ry = ry + 1
            }
        }
        check( "T126 rotate(180) pixel mirror exact", r180ok )

        Image.ImageBuffer rot90 = grad.rotate( 90.0f, true )
        bool r90ok = rot90 != null && rot90.width == h && rot90.height == w
        if r90ok
        {
            r90ok = ImageTest.pixSame( rot90, 0, 0, grad, w - 1, 0 )
        }
        if r90ok
        {
            r90ok = ImageTest.pixSame( rot90, h - 1, 0, grad, w - 1, h - 1 )
        }
        check( "T127 rotate(90, expand) dims + corners", r90ok )

        Image.ImageBuffer rot270 = grad.rotate( 270.0f, true )
        bool r270ok = rot270 != null && rot270.width == h && rot270.height == w
        if r270ok
        {
            r270ok = ImageTest.pixSame( rot270, 0, 0, grad, 0, h - 1 )
        }
        check( "T128 rotate(270, expand) dims + corner", r270ok )

        Image.ImageBuffer g10 = ImageTest.makeGradient( 10, 10 )
        Image.ImageBuffer rot45 = g10.rotate( 45.0f, true, Image.EInterpolation.Bilinear )
        bool r45ok = rot45 != null && rot45.width == 14 && rot45.height == 14
        if r45ok
        {
            ColorInt r45corner = rot45.getPixel( 0, 0 )
            ColorInt r45center = rot45.getPixel( 6, 6 )
            r45ok = r45corner.a == 0 && r45center.a == 255
        }
        check( "T129 rotate(45, expand, bilinear) dims + corners", r45ok )
        Image.ImageBuffer badBuf = Image.ImageBuffer( 0, 0 )
        check( "T130 rotate(invalid) == null", badBuf.rotate( 45.0f ) == null )

        # 13d. splitChannels / mergeRgba / mergeRgb（Image.split / merge）
        var chans = grad.splitChannels()
        Image.ImageBuffer ch0 = null
        Image.ImageBuffer ch1 = null
        Image.ImageBuffer ch3 = null
        bool splitOk = chans != null && chans.length == 4
        if splitOk
        {
            ch0 = chans[ 0 ]
            ch1 = chans[ 1 ]
            ch3 = chans[ 3 ]
            splitOk = ch0 != null && ch1 != null && ch3 != null
        }
        if splitOk
        {
            splitOk = ch0.pixelFormat == Image.EPixelFormat.Gray8 && ch0.width == w && ch0.height == h
        }
        if splitOk
        {
            ColorInt s0 = grad.getPixel( 0, 0 )
            ColorInt v0 = ch0.getPixel( 0, 0 )
            ColorInt v1 = ch1.getPixel( 0, 0 )
            ColorInt v3 = ch3.getPixel( 0, 0 )
            splitOk = v0.r == s0.r && v1.r == s0.g && v3.r == s0.a
        }
        check( "T131 splitChannels -> 4 Gray8 planes", splitOk )

        Image.ImageBuffer merged = null
        if chans != null && chans.length == 4
        {
            # 注：chans[i] 泛型索引器表达式直接作跨模块静态方法实参会导致
            # 方法查找失败（List<T> 模板参数类型不匹配），先赋类型化局部再传参
            Image.ImageBuffer mr = chans[ 0 ]
            Image.ImageBuffer mg = chans[ 1 ]
            Image.ImageBuffer mb = chans[ 2 ]
            Image.ImageBuffer ma = chans[ 3 ]
            merged = Image.ImageBuffer.mergeRgba( mr, mg, mb, ma )
        }
        bool mergeOk = merged != null
        if mergeOk
        {
            Int32 my = 0
            while my < h && mergeOk
            {
                Int32 mx = 0
                while mx < w && mergeOk
                {
                    mergeOk = ImageTest.pixSame( grad, mx, my, merged, mx, my )
                    mx = mx + 1
                }
                my = my + 1
            }
        }
        check( "T132 mergeRgba(split) roundtrip pixel-exact", mergeOk )

        Image.ImageBuffer merged3 = null
        if chans != null && chans.length >= 3
        {
            Image.ImageBuffer mr3 = chans[ 0 ]
            Image.ImageBuffer mg3 = chans[ 1 ]
            Image.ImageBuffer mb3 = chans[ 2 ]
            merged3 = Image.ImageBuffer.mergeRgb( mr3, mg3, mb3 )
        }
        check( "T133 mergeRgb alpha == 255", merged3 != null && merged3.getPixel( 1, 1 ).a == 255 )
        check( "T134 merge/split error paths", Image.ImageBuffer.mergeRgba( null, null, null, null ) == null && Image.ImageBuffer.newImage( 0, 4, ColorInt.white() ) == null )

        # 13e. alphaComposite / blend（Image.alpha_composite / Image.blend）
        Image.ImageBuffer acDst = Image.ImageBuffer.newImage( 4, 4, ColorInt( 255, 0, 0, 255 ) )
        Image.ImageBuffer acSrc = Image.ImageBuffer.newImage( 4, 4, ColorInt( 0, 0, 255, 255 ) )
        Image.ImageBuffer acOut = Image.ImageBuffer.alphaComposite( acDst, acSrc )
        check( "T135 alphaComposite opaque src wins exact", acOut != null && ImageTest.pixSame( acOut, 1, 1, acSrc, 1, 1 ) )
        Image.ImageBuffer acDst2 = Image.ImageBuffer.newImage( 4, 4 )
        Image.ImageBuffer acSrc2 = Image.ImageBuffer.newImage( 4, 4, ColorInt( 200, 100, 50, 128 ) )
        Image.ImageBuffer acOut2 = Image.ImageBuffer.alphaComposite( acDst2, acSrc2 )
        bool acOk = acOut2 != null
        if acOk
        {
            ColorInt o = acOut2.getPixel( 2, 2 )
            ColorInt s = acSrc2.getPixel( 2, 2 )
            Int32 dr = o.r - s.r
            if dr < 0 { dr = 0 - dr }
            Int32 dg = o.g - s.g
            if dg < 0 { dg = 0 - dg }
            Int32 db = o.b - s.b
            if db < 0 { db = 0 - db }
            Int32 da = o.a - s.a
            if da < 0 { da = 0 - da }
            acOk = dr <= 2 && dg <= 2 && db <= 2 && da <= 2
        }
        check( "T136 alphaComposite over transparent ≈ src", acOk )

        Image.ImageBuffer bl1 = Image.ImageBuffer.newImage( 4, 4, ColorInt( 255, 0, 0, 255 ) )
        Image.ImageBuffer bl2 = Image.ImageBuffer.newImage( 4, 4, ColorInt( 0, 0, 255, 255 ) )
        Image.ImageBuffer blOut = Image.ImageBuffer.blend( bl1, bl2, 0.5f )
        bool blOk = blOut != null
        if blOk
        {
            ColorInt bo = blOut.getPixel( 1, 2 )
            blOk = bo.r >= 126 && bo.r <= 128 && bo.b >= 126 && bo.b <= 128 && bo.a == 255
        }
        check( "T137 blend(red, blue, 0.5) ≈ (127,0,127)", blOk )

        # 13f. ImageFilter（img.filter(ImageFilter.X)）
        Image.ImageBuffer filtSolid = Image.ImageBuffer.newImage( 8, 8, ColorInt( 100, 100, 100, 255 ) )
        Image.ImageBuffer fBlur = Image.ImageFilter.apply( filtSolid, Image.EImageFilter.Blur )
        check( "T138 filter Blur on solid exact", fBlur != null && ImageTest.pixSame( fBlur, 3, 3, filtSolid, 3, 3 ) )
        Image.ImageBuffer fContour = Image.ImageFilter.apply( filtSolid, Image.EImageFilter.Contour )
        ColorInt fcw = null
        if fContour != null
        {
            fcw = fContour.getPixel( 4, 4 )
        }
        check( "T139 filter Contour on solid -> white", fcw != null && fcw.r == 255 && fcw.g == 255 && fcw.b == 255 )
        Image.ImageBuffer fEdges = Image.ImageFilter.apply( filtSolid, Image.EImageFilter.FindEdges )
        ColorInt fe = null
        if fEdges != null
        {
            fe = fEdges.getPixel( 2, 5 )
        }
        check( "T140 filter FindEdges on solid -> black", fe != null && fe.r == 0 && fe.g == 0 && fe.b == 0 )
        Image.ImageBuffer fEmboss = Image.ImageFilter.apply( filtSolid, Image.EImageFilter.Emboss )
        ColorInt fm = null
        if fEmboss != null
        {
            fm = fEmboss.getPixel( 5, 2 )
        }
        check( "T141 filter Emboss on solid -> 128", fm != null && fm.r == 128 && fm.g == 128 && fm.b == 128 )
        Image.ImageBuffer fSharp = Image.ImageFilter.apply( filtSolid, Image.EImageFilter.Sharpen )
        Image.ImageBuffer fSmooth = Image.ImageFilter.apply( filtSolid, Image.EImageFilter.Smooth )
        Image.ImageBuffer fDetail = Image.ImageFilter.apply( filtSolid, Image.EImageFilter.Detail )
        Image.ImageBuffer fEdgeEnh = Image.ImageFilter.apply( filtSolid, Image.EImageFilter.EdgeEnhance )
        check( "T142 Sharpen/Smooth/Detail/EdgeEnhance solid exact", fSharp != null && fSmooth != null && fDetail != null && fEdgeEnh != null && ImageTest.pixSame( fSharp, 0, 0, filtSolid, 0, 0 ) && ImageTest.pixSame( fSmooth, 7, 7, filtSolid, 7, 7 ) && ImageTest.pixSame( fDetail, 3, 4, filtSolid, 3, 4 ) && ImageTest.pixSame( fEdgeEnh, 6, 1, filtSolid, 6, 1 ) )
        Array<Int32> ident = Array<Int32>( 9 )
        Int32 ik = 0
        while ik < 9
        {
            ident[ ik ] = 0
            ik = ik + 1
        }
        ident[ 4 ] = 1
        Image.ImageBuffer identOut = Image.ImageFilter.convolve3x3( grad, ident, 1, 0 )
        check( "T143 convolve3x3 identity kernel byte-exact", identOut != null && ImageTest.bytesEqual( grad.pixelBytes(), identOut.pixelBytes() ) )
        check( "T144 filter error paths", Image.ImageFilter.apply( null, Image.EImageFilter.Blur ) == null && Image.ImageFilter.convolve3x3( grad, null, 1, 0 ) == null && Image.ImageFilter.convolve3x3( grad, ident, 0, 0 ) == null )

        # 13g. show（Image.show：临时 PNG + 系统查看器）
        bool shown = Image.ImageIO.show( grad, false )
        check( "T145 ImageIO.show(no-viewer) saves temp png", shown && File.exists( "slang_image_show.png" ) )
        check( "T146 File.delete show temp", File.delete( "slang_image_show.png" ) )
        check( "T147 show(null) == false", !Image.ImageIO.show( null ) )

        # ── 14. C 层像素批量运算（sli_op_*）专项验证 ──────────
        # 14a. resize 最近邻：32x24 应逐字节等于 64x48 的 (2x, 2y) 采样
        Image.ImageBuffer rn = grad.resize( 32, 24, Image.EInterpolation.Nearest )
        bool t148 = rn != null && rn.width == 32 && rn.height == 24
        if t148
        {
            Int32 ry = 0
            while ry < 24 && t148
            {
                Int32 rx = 0
                while rx < 32 && t148
                {
                    t148 = ImageTest.pixSame( rn, rx, ry, grad, rx * 2, ry * 2 )
                    rx = rx + 1
                }
                ry = ry + 1
            }
        }
        check( "T148 resize Nearest exact (2x subsample)", t148 )

        # 14b. resize 双线性角点：负半像素钳到 (0,0)，角点应与源完全一致
        Image.ImageBuffer rb = grad.resize( 96, 72, Image.EInterpolation.Bilinear )
        bool t149 = rb != null && rb.width == 96 && rb.height == 72
        if t149
        {
            ColorInt cc = rb.getPixel( 0, 0 )
            ColorInt src00 = grad.getPixel( 0, 0 )
            t149 = cc.a == 255 && cc.r == src00.r && cc.g == src00.g && cc.b == src00.b
        }
        check( "T149 resize Bilinear corner (0,0) exact", t149 )

        # 14c. convertTo Gray8：BT.601 加权逐字节
        Image.ImageBuffer grayC = grad.convertTo( Image.EPixelFormat.Gray8 )
        bool t150 = grayC != null
        if t150
        {
            ColorInt s0 = grad.getPixel( 10, 7 )
            Int32 expect = ( 299 * s0.r + 587 * s0.g + 114 * s0.b + 500 ) / 1000
            ColorInt g0 = grayC.getPixel( 10, 7 )
            t150 = g0.r == expect && g0.g == expect && g0.b == expect
        }
        check( "T150 convertTo Gray8 BT.601 exact", t150 )

        # 14d. premultiply / unpremultiply 往返（公式直算）
        Image.ImageBuffer pm = Image.ImageBuffer.newImage( 6, 4 )
        pm.setPixel( 2, 1, ColorInt( 200, 150, 100, 128 ) )
        pm.premultiplyAlpha()
        ColorInt pmd = pm.getPixel( 2, 1 )
        bool t151 = pmd.a == 128 && pmd.r == ( 200 * 128 + 127 ) / 255 && pmd.g == ( 150 * 128 + 127 ) / 255 && pmd.b == ( 100 * 128 + 127 ) / 255
        if t151
        {
            pm.unpremultiplyAlpha()
            ColorInt pmu = pm.getPixel( 2, 1 )
            t151 = pmu.a == 128 && pmu.r >= 199 && pmu.r <= 201 && pmu.g >= 149 && pmu.g <= 151 && pmu.b >= 99 && pmu.b <= 101
        }
        check( "T151 premultiply/unpremultiply formula exact", t151 )

        # 14e. flipX 行反转（3 像素行）
        Image.ImageBuffer fx = Image.ImageBuffer.newImage( 3, 1, ColorInt.black() )
        fx.setPixel( 0, 0, ColorInt( 10, 0, 0, 255 ) )
        fx.setPixel( 1, 0, ColorInt( 20, 0, 0, 255 ) )
        fx.setPixel( 2, 0, ColorInt( 30, 0, 0, 255 ) )
        fx.flipX()
        check( "T152 flipX row reverse", fx.getPixel( 0, 0 ).r == 30 && fx.getPixel( 1, 0 ).r == 20 && fx.getPixel( 2, 0 ).r == 10 )

        # ── 15. 仿 Pillow advanced（ImageChops / ImageEnhance / ImageMask / ImageDraw）──
        # https://www.runoob.com/pillow/pillow-advanced.html
        Image.ImageBuffer A = Image.ImageBuffer.newImage( 16, 16, ColorInt( 100, 60, 40, 255 ) )
        Image.ImageBuffer B = Image.ImageBuffer.newImage( 16, 16, ColorInt( 20, 90, 210, 255 ) )

        # 15a. ImageChops 通道运算（整数公式逐位验证）
        Image.ImageBuffer cAdd = Image.ImageChops.add( A, B )
        ColorInt ca = null
        if cAdd != null
        {
            ca = cAdd.getPixel( 3, 3 )
        }
        check( "T153 chops add saturates", ca != null && ca.r == 120 && ca.g == 150 && ca.b == 250 )
        Image.ImageBuffer cSub = Image.ImageChops.subtract( A, B )
        ColorInt cs = null
        if cSub != null
        {
            cs = cSub.getPixel( 3, 3 )
        }
        check( "T154 chops subtract clamps 0", cs != null && cs.r == 80 && cs.g == 0 && cs.b == 0 )
        Image.ImageBuffer cMul = Image.ImageChops.multiply( A, B )
        ColorInt cm = null
        if cMul != null
        {
            cm = cMul.getPixel( 3, 3 )
        }
        check( "T155 chops multiply a*b/255", cm != null && cm.r == 100 * 20 / 255 && cm.g == 60 * 90 / 255 && cm.b == 40 * 210 / 255 )
        Image.ImageBuffer cScr = Image.ImageChops.screen( A, B )
        ColorInt cc2 = null
        if cScr != null
        {
            cc2 = cScr.getPixel( 3, 3 )
        }
        check( "T156 chops screen", cc2 != null && cc2.r == 255 - ( 255 - 100 ) * ( 255 - 20 ) / 255 && cc2.b == 255 - ( 255 - 40 ) * ( 255 - 210 ) / 255 )
        Image.ImageBuffer cDiff = Image.ImageChops.difference( A, B )
        ColorInt cd = null
        if cDiff != null
        {
            cd = cDiff.getPixel( 3, 3 )
        }
        check( "T157 chops difference abs", cd != null && cd.r == 80 && cd.g == 30 && cd.b == 170 )
        Image.ImageBuffer cInv = Image.ImageChops.invert( A )
        ColorInt ci = null
        if cInv != null
        {
            ci = cInv.getPixel( 3, 3 )
        }
        check( "T158 chops invert", ci != null && ci.r == 155 && ci.g == 195 && ci.b == 215 && ci.a == 0 )
        Image.ImageBuffer cLight = Image.ImageChops.lighter( A, B )
        Image.ImageBuffer cDark = Image.ImageChops.darker( A, B )
        check( "T159 chops lighter/darker", cLight != null && cDark != null && cLight.getPixel( 5, 5 ).r == 100 && cLight.getPixel( 5, 5 ).b == 210 && cDark.getPixel( 5, 5 ).r == 20 && cDark.getPixel( 5, 5 ).g == 60 )
        Image.ImageBuffer cSoft = Image.ImageChops.softLight( A, B )
        ColorInt cso = null
        if cSoft != null
        {
            cso = cSoft.getPixel( 3, 3 )
        }
        check( "T160 chops softLight formula", cso != null && cso.r == ( 100 * ( 255 - 20 ) + 20 * 20 / 255 ) / 255 && cso.b == ( 40 * ( 255 - 210 ) + 210 * 210 / 255 ) / 255 )
        Image.ImageBuffer cHard = Image.ImageChops.hardLight( A, B )
        ColorInt chd = null
        if cHard != null
        {
            chd = cHard.getPixel( 3, 3 )
        }
        check( "T161 chops hardLight b<128 branch", chd != null && chd.r == 2 * 100 * 20 / 255 && chd.g == 2 * 60 * 90 / 255 && chd.b == 255 - 2 * ( 255 - 40 ) * ( 255 - 210 ) / 255 )
        check( "T162 chops error paths", Image.ImageChops.add( null, B ) == null && Image.ImageChops.add( A, null ) == null && Image.ImageChops.invert( null ) == null && Image.ImageChops.subtract( A, Image.ImageBuffer.newImage( 4, 4 ) ) == null )

        # 15b. ImageEnhance 四增强器
        Image.ImageBuffer bright = Image.ImageEnhance.brightness( A, 1.5f )
        ColorInt cb2 = null
        if bright != null
        {
            cb2 = bright.getPixel( 3, 3 )
        }
        check( "T163 enhance brightness 1.5x", cb2 != null && cb2.r == 150 && cb2.g == 90 && cb2.b == 60 )
        Image.ImageBuffer dark2 = Image.ImageEnhance.brightness( A, 0.5f )
        ColorInt cd2 = null
        if dark2 != null
        {
            cd2 = dark2.getPixel( 3, 3 )
        }
        check( "T164 enhance brightness 0.5x", cd2 != null && cd2.r == 50 && cd2.g == 30 && cd2.b == 20 )
        # contrast factor=0 -> 纯灰（均值）图
        Image.ImageBuffer grayC2 = Image.ImageEnhance.contrast( A, 0.0f )
        Int32 meanV = ( 299 * 100 + 587 * 60 + 114 * 40 + 500 ) / 1000
        ColorInt cg2 = null
        if grayC2 != null
        {
            cg2 = grayC2.getPixel( 3, 3 )
        }
        check( "T165 enhance contrast 0 -> luma mean", cg2 != null && cg2.r == meanV && cg2.g == meanV && cg2.b == meanV )
        # color factor=0 -> 灰度图
        Image.ImageBuffer col0 = Image.ImageEnhance.color( A, 0.0f )
        ColorInt cl2 = null
        if col0 != null
        {
            cl2 = col0.getPixel( 3, 3 )
        }
        check( "T166 enhance color 0 -> grayscale", cl2 != null && cl2.r == cl2.g && cl2.g == cl2.b && cl2.r == ( 299 * 100 + 587 * 60 + 114 * 40 + 500 ) / 1000 )
        # sharpness factor=1 -> 原图不变
        Image.ImageBuffer sharp1 = Image.ImageEnhance.sharpness( A, 1.0f )
        bool t167 = sharp1 != null
        if t167
        {
            t167 = ImageTest.pixSame( sharp1, 3, 3, A, 3, 3 )
        }
        check( "T167 enhance sharpness 1.0 identity", t167 )
        check( "T168 enhance error paths", Image.ImageEnhance.brightness( null, 1.0f ) == null && Image.ImageEnhance.color( null, 1.0f ) == null )

        # 15c. ImageMask 蒙版生成与蒙版合成
        Image.ImageBuffer gm = Image.ImageMask.gradientMask( 10, 4, Image.EMaskDirection.Horizontal, 0, 255 )
        bool t169 = gm != null && gm.pixelFormat == Image.EPixelFormat.Gray8
        if t169
        {
            # 10 宽渐变：v = 255*x/10 —— x=0 得 0、x=9 得 229（端值 255 仅 x=w 出界）
            t169 = gm.getPixel( 0, 0 ).r == 0 && gm.getPixel( 9, 3 ).r == 229
        }
        check( "T169 gradientMask horizontal 0->229", t169 )
        Image.ImageBuffer cmask = Image.ImageMask.circularMask( 9, 9, 4 )
        bool t170 = cmask != null
        if t170
        {
            t170 = cmask.getPixel( 4, 4 ).r == 255 && cmask.getPixel( 0, 0 ).r == 0 && cmask.getPixel( 8, 8 ).r == 0
        }
        check( "T170 circularMask center 255 / corners 0", t170 )
        Image.ImageBuffer stripe = Image.ImageMask.patternMask( 8, 8, Image.EMaskPattern.Stripes, 4 )
        bool t171 = stripe != null
        if t171
        {
            t171 = stripe.getPixel( 0, 0 ).r == 255 && stripe.getPixel( 2, 0 ).r == 0
        }
        check( "T171 patternMask stripes", t171 )
        # applyMaskBlend：mask=0 全取 A，mask=255 全取 B（蒙版须与 A/B 同尺寸 16x16）
        Image.ImageBuffer m0 = Image.ImageBuffer.newImage( 16, 16, ColorInt( 0, 0, 0, 255 ) )
        Image.ImageBuffer m255 = Image.ImageBuffer.newImage( 16, 16, ColorInt( 255, 255, 255, 255 ) )
        Image.ImageBuffer ab0 = Image.ImageMask.applyMaskBlend( A, B, m0 )
        Image.ImageBuffer ab255 = Image.ImageMask.applyMaskBlend( A, B, m255 )
        bool t172 = ab0 != null && ab255 != null
        if t172
        {
            t172 = ImageTest.pixSame( ab0, 1, 1, A, 1, 1 ) && ImageTest.pixSame( ab255, 1, 1, B, 1, 1 )
        }
        check( "T172 applyMaskBlend extremes exact", t172 )
        # transitionBlend horizontal：x=0 处 m=0 全 A；x=15 处 m=239（255*15/16）
        # -> A*(1-239/255)+B*(239/255) = 整数直算 (26, 88, 199)（容差 1）
        Image.ImageBuffer tb = Image.ImageMask.transitionBlend( A, B, Image.EMaskDirection.Horizontal )
        bool t173 = tb != null
        if t173
        {
            t173 = ImageTest.pixSame( tb, 0, 0, A, 0, 0 )
        }
        if t173
        {
            ColorInt tbe = tb.getPixel( 15, 15 )
            Int32 d0 = tbe.r - 26
            if d0 < 0 { d0 = 0 - d0 }
            Int32 d1 = tbe.g - 88
            if d1 < 0 { d1 = 0 - d1 }
            Int32 d2 = tbe.b - 199
            if d2 < 0 { d2 = 0 - d2 }
            t173 = d0 <= 1 && d1 <= 1 && d2 <= 1
        }
        check( "T173 transitionBlend horizontal ends", t173 )
        # checkerboardBlend grid=4：偶格 (0+0)=0 → mask 255 → B；奇格 (1+0) → A
        Image.ImageBuffer ck = Image.ImageMask.checkerboardBlend( A, B, 4 )
        bool t174 = ck != null
        if t174
        {
            t174 = ImageTest.pixSame( ck, 0, 0, B, 0, 0 ) && ImageTest.pixSame( ck, 5, 0, A, 5, 0 )
        }
        check( "T174 checkerboardBlend parity B/A", t174 )
        # pasteMasked：全 255 蒙版 = 完全覆盖
        Image.ImageBuffer pmBase = Image.ImageBuffer.newImage( 8, 8, ColorInt.white() )
        bool t175 = pmBase.pasteMasked( A, 2, 2, m255 )
        if t175
        {
            t175 = ImageTest.pixSame( pmBase, 3, 3, A, 3, 3 )
        }
        check( "T175 pasteMasked full mask overwrite", t175 )
        check( "T176 mask error paths", Image.ImageMask.gradientMask( 0, 4, Image.EMaskDirection.Horizontal, 0, 255 ) == null && Image.ImageMask.applyMaskBlend( null, B, m0 ) == null && !pmBase.pasteMasked( A, 2, 2, null ) )

        # 15d. ImageDraw 几何绘制
        Image.ImageBuffer canvas = Image.ImageBuffer.newImage( 32, 32, ColorInt.white() )
        Image.ImageDraw.point( canvas, 5, 7, ColorInt.black() )
        check( "T177 draw point", canvas.getPixel( 5, 7 ).r == 0 )
        Image.ImageDraw.line( canvas, 0, 0, 9, 0, ColorInt( 255, 0, 0, 255 ), 1 )
        check( "T178 draw line endpoints", canvas.getPixel( 0, 0 ).r == 255 && canvas.getPixel( 9, 0 ).r == 255 && canvas.getPixel( 5, 0 ).r == 255 )
        Image.ImageDraw.rectangle( canvas, 10, 10, 14, 12, ColorInt( 0, 255, 0, 255 ), null, 1 )
        check( "T179 draw rect fill", canvas.getPixel( 12, 11 ).g == 255 && canvas.getPixel( 12, 11 ).r == 0 )
        Image.ImageDraw.rectangle( canvas, 20, 20, 24, 22, null, ColorInt( 0, 0, 255, 255 ), 1 )
        bool t180 = canvas.getPixel( 20, 21 ).b == 255 && canvas.getPixel( 24, 21 ).b == 255 && canvas.getPixel( 22, 21 ).b == 255
        check( "T180 draw rect outline only", t180 )
        Image.ImageDraw.ellipse( canvas, 2, 18, 6, 22, ColorInt( 128, 0, 128, 255 ), null, 1 )
        check( "T181 draw ellipse fill center", canvas.getPixel( 4, 20 ).r == 128 && canvas.getPixel( 4, 20 ).b == 128 )
        Image.ImageDraw.circle( canvas, 26, 26, 3, ColorInt( 0, 255, 255, 255 ), null, 1 )
        check( "T182 draw circle center", canvas.getPixel( 26, 26 ).g == 255 && canvas.getPixel( 26, 26 ).b == 255 )
        Image.ImageDraw.arc( canvas, 16, 2, 22, 8, 0, 90, ColorInt( 255, 128, 0, 255 ), 1 )
        check( "T183 draw arc 0deg right point", canvas.getPixel( 22, 5 ).r == 255 )
        var pxs = List<Int32>()
        pxs.add( 10 )
        pxs.add( 30 )
        var pys = List<Int32>()
        pys.add( 30 )
        pys.add( 22 )
        pxs.add( 22 )
        pxs.add( 16 )
        pys.add( 34 )
        pys.add( 30 )
        Image.ImageDraw.polygon( canvas, pxs, pys, ColorInt( 255, 0, 255, 255 ), null )
        check( "T184 draw polygon fill centroid", canvas.getPixel( 17, 29 ).r == 255 && canvas.getPixel( 17, 29 ).b == 255 )
        Image.ImageBuffer txtCanvas = Image.ImageBuffer.newImage( 20, 8, ColorInt.white() )
        Image.ImageDraw.text( txtCanvas, 1, 1, "AB", ColorInt.black() )
        # 'A' 字形第一行 = 111（3 列全亮）
        check( "T185 draw text A glyph row", txtCanvas.getPixel( 1, 1 ).r == 0 && txtCanvas.getPixel( 2, 1 ).r == 0 && txtCanvas.getPixel( 3, 1 ).r == 0 )
        check( "T186 draw textWidth/textHeight", Image.ImageDraw.textWidth( "AB" ) == 7 && Image.ImageDraw.textHeight() == 5 )
        check( "T187 draw null-safe no crash", ImageTest.t187nulls( canvas ) )
        # 落盘往返：绘制图存 PNG 再读回逐像素一致
        bool saved2 = Image.ImageIO.save( canvas, "image_test_draw.png", Image.EImageFormat.Png, 100 )
        Image.ImageBuffer reCanvas = Image.ImageIO.load( "image_test_draw.png" )
        bool t188 = saved2 && reCanvas != null
        if t188
        {
            t188 = ImageTest.rgbEquals( canvas, reCanvas )
        }
        check( "T188 draw canvas PNG roundtrip", t188 )
        check( "T189 File.delete draw cleanup", File.delete( "image_test_draw.png" ) )

        Console.println( "" )
        Console.println( "===== ImageTest end PASS=" + s_pass.toString() + " FAIL=" + s_fail.toString() + " =====" )
    }
}
