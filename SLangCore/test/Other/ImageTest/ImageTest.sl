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

        Console.println( "" )
        Console.println( "===== ImageTest end PASS=" + s_pass.toString() + " FAIL=" + s_fail.toString() + " =====" )
    }
}
