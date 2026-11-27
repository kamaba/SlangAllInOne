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

        Console.println( "" )
        Console.println( "===== ImageTest end PASS=" + s_pass.toString() + " FAIL=" + s_fail.toString() + " =====" )
    }
}
