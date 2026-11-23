import SimGameEngine;
import SLangRender;
import Std;
import Math;

# ============================================================================
# SimTextDrawTest — 第 22 套：Windows GDI（render CVM）/ TTF 解析 / 动态字库 / TextMesh / GameManager
# ----------------------------------------------------------------------------
# 字体样本在测试内现造一份最小 sfnt（2 个简单轮廓 + cmap format 4），
# 落临时文件后走 Font.load 全链路，不依赖仓库二进制资源。
# ============================================================================

public class SimTextDrawTest
{
    static Int32 _pass = 0
    static Int32 _fail = 0

    static void check( bool cond, string msg )
    {
        if cond
        {
            _pass = _pass + 1
        }
        else
        {
            _fail = _fail + 1
            Console.println( "[FAIL] " + msg )
        }
    }

    static Int32 passCount()
    {
        ret _pass
    }

    static Int32 failCount()
    {
        ret _fail
    }

    static void put16( Int64 p, Int32 off, Int32 v )
    {
        Memory.writeI8( p, off, ( v >> 8 ) & 255 )
        Memory.writeI8( p, off + 1, v & 255 )
    }

    static void put32( Int64 p, Int32 off, Int32 v )
    {
        Memory.writeI8( p, off, ( v >> 24 ) & 255 )
        Memory.writeI8( p, off + 1, ( v >> 16 ) & 255 )
        Memory.writeI8( p, off + 2, ( v >> 8 ) & 255 )
        Memory.writeI8( p, off + 3, v & 255 )
    }

    static void tableRecord( Int64 p, Int32 rec, Int32 a, Int32 b, Int32 c, Int32 d,
        Int32 off, Int32 len )
    {
        put32( p, rec, ( a << 24 ) | ( b << 16 ) | ( c << 8 ) | d )
        put32( p, rec + 8, off )
        put32( p, rec + 12, len )
    }

    # 造一份 352 字节的 TrueType：glyph1 方形（A），glyph2 三角（B）
    static string makeFont()
    {
        string path = "sim_text_draw_probe.ttf"
        Int32 total = 352
        Int64 p = Memory.alloc( total )
        Int32 i = 0
        while i < total
        {
            Memory.writeI8( p, i, 0 )
            i += 1
        }
        put32( p, 0, 65536 )
        put16( p, 4, 7 )
        tableRecord( p, 12, 104, 101, 97, 100, 124, 54 )
        tableRecord( p, 28, 109, 97, 120, 112, 178, 6 )
        tableRecord( p, 44, 104, 104, 101, 97, 184, 36 )
        tableRecord( p, 60, 104, 109, 116, 120, 220, 12 )
        tableRecord( p, 76, 99, 109, 97, 112, 232, 32 )
        tableRecord( p, 92, 108, 111, 99, 97, 276, 8 )
        tableRecord( p, 108, 103, 108, 121, 102, 284, 68 )
        put16( p, 124 + 18, 1000 )
        put16( p, 124 + 50, 0 )
        put16( p, 178 + 4, 3 )
        put16( p, 184 + 34, 3 )
        put16( p, 220, 500 )
        put16( p, 224, 600 )
        put16( p, 228, 700 )
        put16( p, 234, 1 )
        put16( p, 236, 3 )
        put16( p, 238, 1 )
        put32( p, 240, 12 )
        put16( p, 244, 4 )
        put16( p, 246, 32 )
        put16( p, 248, 0 )
        put16( p, 250, 4 )
        put16( p, 252, 4 )
        put16( p, 254, 1 )
        put16( p, 256, 0 )
        put16( p, 258, 66 )
        put16( p, 260, 65535 )
        put16( p, 262, 0 )
        put16( p, 264, 65 )
        put16( p, 266, 65535 )
        put16( p, 268, 65472 )
        put16( p, 270, 1 )
        put16( p, 272, 0 )
        put16( p, 274, 0 )
        put16( p, 276, 0 )
        put16( p, 278, 0 )
        put16( p, 280, 17 )
        put16( p, 282, 34 )
        # glyph1：方形 4 点
        put16( p, 284, 1 )
        put16( p, 286, 0 )
        put16( p, 288, 0 )
        put16( p, 290, 600 )
        put16( p, 292, 700 )
        put16( p, 294, 3 )
        put16( p, 296, 0 )
        i = 0
        while i < 4
        {
            Memory.writeI8( p, 298 + i, 1 )
            i += 1
        }
        put16( p, 302, 0 )
        put16( p, 304, 600 )
        put16( p, 306, 0 )
        put16( p, 308, 64936 )
        put16( p, 310, 0 )
        put16( p, 312, 0 )
        put16( p, 314, 700 )
        put16( p, 316, 64836 )
        # glyph2：三角 3 点
        put16( p, 318, 1 )
        put16( p, 320, 0 )
        put16( p, 322, 0 )
        put16( p, 324, 600 )
        put16( p, 326, 700 )
        put16( p, 328, 2 )
        put16( p, 330, 0 )
        Memory.writeI8( p, 332, 1 )
        Memory.writeI8( p, 333, 1 )
        Memory.writeI8( p, 334, 1 )
        put16( p, 336, 0 )
        put16( p, 338, 600 )
        put16( p, 340, 64336 )
        put16( p, 342, 0 )
        put16( p, 344, 0 )
        put16( p, 346, 700 )

        UInt8[] bytes = Array<UInt8>.create( total )
        i = 0
        while i < total
        {
            bytes[i] = SystemConvertUInt8( Memory.readUInt8( p, i ) )
            i += 1
        }
        File.writeAllBytes( path, bytes )
        Memory.free( p )
        ret path
    }

    static void runDraw()
    {
        Console.println( "  [GdiCanvas] Windows GDI primitives via render CVM" )
        GdiCanvas c = GdiCanvas.create( 64, 48 )
        check( c.isReady(), "GDI DIB canvas created" )
        check( c.width() == 64 && c.height() == 48, "GDI canvas size" )
        Int32 clear = GdiCanvas.rgba( 0, 0, 0, 0 )
        c.clear( clear )
        check( c.pixelAt( 0, 0 ) == clear, "GDI clear = transparent" )
        Int32 red = GdiCanvas.rgba( 255, 0, 0, 255 )
        c.fillRect( 5, 5, 20, 18, red )
        check( c.pixelAt( 6, 6 ) == red, "GDI fillRect inside" )
        check( c.pixelAt( 30, 30 ) != red, "GDI fillRect outside untouched" )
        check( c.pixelAt( -1, 0 ) == -1, "GDI pixelAt out of range = -1" )
        c.clear( clear )
        c.line( 0, 0, 20, 20, red )
        check( GdiCanvas.alphaOf( c.pixelAt( 10, 10 ) ) == 255, "GDI LineTo hit" )
        c.clear( clear )
        c.fillEllipse( 22, 16, 42, 32, red )
        check( c.pixelAt( 32, 24 ) == red, "GDI fillEllipse center" )
        check( GdiCanvas.alphaOf( c.pixelAt( 60, 40 ) ) == 0, "GDI fillEllipse outside" )
        c.clear( clear )
        List<Float32> px = List<Float32>( 4 )
        List<Float32> py = List<Float32>( 4 )
        px.add( 3.0f )
        py.add( 3.0f )
        px.add( 20.0f )
        py.add( 3.0f )
        px.add( 20.0f )
        py.add( 18.0f )
        px.add( 3.0f )
        py.add( 18.0f )
        c.fillPolygon( px, py, red, red )
        check( c.pixelAt( 10, 10 ) == red, "GDI Polygon fill" )
        Int64 rgba8 = c.toRgbaBlock()
        check( rgba8 != 0, "GDI BGRA -> RGBA8 block" )
        if rgba8 != 0
        {
            Int32 off = ( 10 * c.width() + 10 ) * 4
            check( Memory.readUInt8( rgba8, off ) == 255, "RGBA8 red channel" )
            check( Memory.readUInt8( rgba8, off + 3 ) == 255, "RGBA8 alpha channel" )
            Memory.free( rgba8 )
        }
        GdiCanvas other = GdiCanvas.create( 64, 48 )
        other.blit( c, 0, 0 )
        check( other.pixelAt( 10, 10 ) == red, "GDI BitBlt copy" )
        other.clear( clear )
        check( other.drawText( "GDI", 2, 2, 20, red ), "GDI TextOutW call" )
        c.dispose()
        other.dispose()
    }

    static void runFont()
    {
        Console.println( "  [Font] sfnt tables + cmap + glyf outline" )
        string path = makeFont()
        check( File.exists( path ), "synthetic ttf written" )
        Font f = Font.load( path )
        check( f.isLoaded(), "Font.load (error=" + f.lastError().toString() + ")" )
        check( f.unitsPerEm() == 1000, "head.unitsPerEm = 1000" )
        check( f.glyphCount() == 3, "maxp.numGlyphs = 3" )
        check( f.glyphForCode( 65 ) == 1, "cmap A -> gid1" )
        check( f.glyphForCode( 66 ) == 2, "cmap B -> gid2" )
        check( f.glyphForCode( 67 ) == 0, "cmap C -> missing" )
        Int32 adv = f.advanceOf( 1 ).toInt32()
        check( adv == 600, "hmtx advance gid1 = 600" )
        Glyph g = f.createGlyph( 1, 2 )
        check( g.glyphId() == 1, "createGlyph gid" )
        check( g.contourCount() == 1, "square contour count" )
        check( g.pointCount() == 4, "square on-curve points = 4 (got "
            + g.pointCount().toString() + ")" )
        check( g.xMax() == 600 && g.yMax() == 700, "glyph bbox" )
        check( g.advance().toInt32() == 600, "glyph advance" )
        Glyph tri = f.createGlyph( 2, 2 )
        check( tri.contourCount() == 1, "triangle contour count" )
        check( tri.pointCount() == 3, "triangle on-curve points = 3" )
        f.dispose()
        File.delete( path )
    }

    static void runAtlasText()
    {
        Console.println( "  [FontAtlas/TextMesh] dynamic glyphs + quad mesh" )
        string path = makeFont()
        Font f = Font.load( path )
        FontAtlas atlas = FontAtlas.create( f, 48 )
        check( atlas.isReady(), "atlas ready" )
        check( atlas.glyphCount() == 0, "atlas starts empty" )
        check( atlas.ensureGlyph( 65 ), "bake A" )
        check( atlas.glyphCount() == 1, "A cached" )
        check( atlas.hasGlyph( 65 ), "hasGlyph A" )
        check( atlas.ensureGlyph( 66 ), "bake B" )
        check( atlas.ensureGlyph( 67 ), "missing code tolerated" )
        check( atlas.ensureGlyph( 65 ), "A re-ensure idempotent" )
        check( atlas.glyphCount() == 3, "cache count = 3 (got "
            + atlas.glyphCount().toString() + ")" )
        Int32 gw = atlas.glyphWAt( 0 )
        check( gw > 0 && gw <= atlas.cellSize(), "glyph cell width in range" )
        Int32 off = ( ( atlas.glyphYAt( 0 ) + atlas.cellSize() - 8 - 17 ) * atlas.width()
            + atlas.glyphXAt( 0 ) + ( gw / 2 ) ) * 4
        Int32 alpha = Memory.readUInt8( atlas.pixelPtr(), off + 3 )
        check( alpha == 255, "glyph A rasterized opaque at center (alpha="
            + alpha.toString() + ")" )
        TextMesh tm = TextMesh()
        tm.attach( atlas )
        tm.setText( "AB" )
        tm.setFontSize( 32 )
        tm.setColor( 1.0f, 1.0f, 1.0f, 1.0f )
        Int32 verts = tm.buildVertices( 480, 360, 1.3333f )
        check( verts == 12, "two glyphs => 12 vertices (got " + verts.toString() + ")" )
        check( tm.vertexCount() == verts, "vertexCount mirror" )
        Float32 vx = Memory.readFloat32( tm.vertexPtr(), 0 )
        Float32 vy = Memory.readFloat32( tm.vertexPtr(), 4 )
        check( vx >= -2.0f && vx <= 2.0f && vy >= -2.0f && vy <= 2.0f, "NDC vertex finite" )
        check( Memory.readFloat32( tm.vertexPtr(), 8 ) >= 0.0f, "uv.u in range" )
        tm.dispose()
        atlas.dispose()
        f.dispose()
        File.delete( path )
    }

    static void runManager()
    {
        Console.println( "  [GameManager] singleton + scene lifecycle" )
        GameManager gm = GameManager.instance()
        check( gm != null, "GameManager.instance non-null" )
        gm.initialize( 0, 0 )
        check( gm.isReady(), "initialize marks ready" )
        Scene s = gm.createScene( "ManagerScene" )
        check( s != null, "createScene" )
        GameObject go = gm.instantiate( "Player" )
        check( go != null, "instantiate" )
        check( gm.find( "Player" ) != null, "find instantiated object" )
        gm.update( 0.016f )
        check( gm.elapsedTime() >= 0.0f, "elapsedTime advanced" )
        gm.pause()
        check( gm.isPaused(), "pause" )
        gm.resume()
        check( !gm.isPaused(), "resume" )
        gm.destroy( go )
        gm.shutdown()
        check( !gm.isReady(), "shutdown clears ready" )
    }

    public static void run()
    {
        runDraw()
        runFont()
        runAtlasText()
        runManager()
        Console.println( "  SimTextDrawTest PASS=" + _pass.toString() + " FAIL=" + _fail.toString() )
    }
}
