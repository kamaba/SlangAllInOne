# ============================================================================
# DrawCanvas — 绘图画布外观层（SimGameEngine 基础绘图 / doc/24）
# ----------------------------------------------------------------------------
# 不再自带软光栅：全部图元委托 SLangRender.BasicDraw（v5.1 统一基础绘图层，
# 一套 API 双后端——BACKEND_GDI Windows GDI 原生 / BACKEND_RHI RHI 管线三角化）。
# 本类职责只剩三件事：
#   1. 颜色契约转换：DrawTypes 0x00RRGGBB → BasicDraw 0xAARRGGBB（补 alpha 255）
#   2. 几何签名适配：DrawCanvas 的 cx/cy/r、x/y/w/h → BasicDraw 的 bbox 端点
#   3. 3x5 位图字体（BasicDraw 无文字原语；字形点亮走 BasicDraw.point）
# 回读：pixelAt/pixelPtr/nonWhiteCount 经 BasicDraw.toRgba 惰性快照到本地缓存。
# 输出：toTexture() 转发 BasicDraw.createTexture()（GDI 直传 / RHI 回读上传）。
# 后端选择：create() 默认 BACKEND_GDI（Windows，像素语义与原软光栅测试对齐）；
#          createBackend() 可显式指定 RHI（跨平台 / GPU 路径）。
# ============================================================================

import Core;
import Std;
import Math;
import SLangRender;

public class DrawCanvas
{
    BasicDraw _bd = null
    Int32 _w = 0
    Int32 _h = 0
    # 像素快照缓存（RGBA8 top-down；绘制后置脏，读取时经 toRgba 刷新）
    Int64 _px = 0
    bool _pxDirty = true

    # 最近一次 DrawChart 绘制的绘图区 / 数据坐标范围（供 abline/legend 叠加用）
    Int32 _plotLeft = 0
    Int32 _plotTop = 0
    Int32 _plotW = 0
    Int32 _plotH = 0
    Float32 _xlo = 0.0f
    Float32 _xhi = 1.0f
    Float32 _ylo = 0.0f
    Float32 _yhi = 1.0f

    # 字形表（惰性构建）：顺序对应 _chars，每字形 5 行 × 3 列拼成 15 字符串
    static List<string> _font = null
    static string _chars = " ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-.%:+/,()=#"

    _init_()
    {
        this._bd = null
        this._w = 0
        this._h = 0
        this._px = 0
        this._pxDirty = true
        this._plotLeft = 0
        this._plotTop = 0
        this._plotW = 0
        this._plotH = 0
        this._xlo = 0.0f
        this._xhi = 1.0f
        this._ylo = 0.0f
        this._yhi = 1.0f
    }

    # ── 创建 / 尺寸 / 释放 ─────────────────────────────────
    # 默认 GDI 后端（Windows；像素行为与测试基准对齐）
    public static DrawCanvas create( Int32 w, Int32 h )
    {
        ret DrawCanvas.createBackend( w, h, BasicDraw.BACKEND_GDI )
    }

    # 显式后端创建：BasicDraw.BACKEND_GDI / BasicDraw.BACKEND_RHI
    public static DrawCanvas createBackend( Int32 w, Int32 h, Int32 backend )
    {
        DrawCanvas c = DrawCanvas()
        BasicDraw bd = BasicDraw.create( w, h, backend )
        if bd == null
        {
            ret c
        }
        c._bd = bd
        c._w = w
        c._h = h
        bd.clear( DrawCanvas.col( DrawTypes.white() ) )
        ret c
    }

    public Int32 width()
    {
        ret this._w
    }

    public Int32 height()
    {
        ret this._h
    }

    public Int32 backend()
    {
        if this._bd == null
        {
            ret 0 - 1
        }
        ret this._bd.backend()
    }

    # BasicDraw 句柄（需要 bezier/arrow/text 等扩展图元时直用）
    public BasicDraw basic()
    {
        ret this._bd
    }

    # 颜色契约：DrawTypes 0x00RRGGBB → BasicDraw 0xAARRGGBB（alpha 恒 255）
    static Int32 col( Int32 c )
    {
        ret ( c & 0xFFFFFF ) | ( 255 << 24 )
    }

    public bool isReady()
    {
        if this._bd == null
        {
            ret false
        }
        ret this._bd.isReady()
    }

    # 绘图区 / 数据范围记录（DrawChart 绘制后写入；叠加层按此换算坐标）
    public void setPlotFrame( Int32 left, Int32 top, Int32 w, Int32 h, Float32 xlo, Float32 xhi, Float32 ylo, Float32 yhi )
    {
        this._plotLeft = left
        this._plotTop = top
        this._plotW = w
        this._plotH = h
        this._xlo = xlo
        this._xhi = xhi
        this._ylo = ylo
        this._yhi = yhi
    }

    public Int32 plotLeft() { ret this._plotLeft }
    public Int32 plotTop() { ret this._plotTop }
    public Int32 plotWidth() { ret this._plotW }
    public Int32 plotHeight() { ret this._plotH }
    public Float32 xlo() { ret this._xlo }
    public Float32 xhi() { ret this._xhi }
    public Float32 ylo() { ret this._ylo }
    public Float32 yhi() { ret this._yhi }

    # 像素快照（绘制后首次读取时经 BasicDraw.toRgba 刷新一次）
    void _ensurePixels()
    {
        if this._bd == null
        {
            ret
        }
        if this._px == 0
        {
            this._px = Memory.alloc( this._w * this._h * 4 )
            if this._px == 0
            {
                ret
            }
        }
        if this._pxDirty
        {
            this._bd.toRgba( this._px )
            this._pxDirty = false
        }
    }

    public void free()
    {
        if this._bd != null
        {
            this._bd.dispose()
            this._bd = null
        }
        if this._px != 0
        {
            Memory.free( this._px )
            this._px = 0
        }
        this._pxDirty = true
    }

    # 转 SLangRender 纹理（转发 BasicDraw.createTexture；调用方持有返回纹理）
    public SLang.RenderTexture toTexture()
    {
        if this._bd == null
        {
            ret null
        }
        ret this._bd.createTexture()
    }

    # ── 像素读取 ───────────────────────────────────────────
    # RGBA8 top-down 像素块地址（上屏通道：喂 QLabel.setPixmapRgba）
    public Int64 pixelPtr()
    {
        this._ensurePixels()
        ret this._px
    }

    public Int32 pixelAt( Int32 x, Int32 y )
    {
        if this._bd == null
        {
            ret -1
        }
        if x < 0 || y < 0
        {
            ret -1
        }
        if x >= this._w || y >= this._h
        {
            ret -1
        }
        this._ensurePixels()
        if this._px == 0
        {
            ret -1
        }
        Int32 idx = ( y * this._w + x ) * 4
        Int32 r = SystemConvertInt32( Memory.readUInt8( this._px, idx ) )
        Int32 g = SystemConvertInt32( Memory.readUInt8( this._px, idx + 1 ) )
        Int32 b = SystemConvertInt32( Memory.readUInt8( this._px, idx + 2 ) )
        ret DrawTypes.rgb( r, g, b )
    }

    public bool pixelIs( Int32 x, Int32 y, Int32 c )
    {
        ret this.pixelAt( x, y ) == c
    }

    public Int32 nonWhiteCount( Int32 x0, Int32 y0, Int32 x1, Int32 y1 )
    {
        if this._bd == null
        {
            ret 0
        }
        Int32 xa = x0
        Int32 ya = y0
        Int32 xb = x1
        Int32 yb = y1
        if xa < 0 { xa = 0 }
        if ya < 0 { ya = 0 }
        if xb > this._w { xb = this._w }
        if yb > this._h { yb = this._h }
        if xa >= xb || ya >= yb { ret 0 }
        this._ensurePixels()
        if this._px == 0 { ret 0 }
        Int32 cnt = 0
        Int32 white = DrawTypes.white()
        Int32 y = ya
        while y < yb
        {
            Int32 x = xa
            while x < xb
            {
                Int32 idx = ( y * this._w + x ) * 4
                Int32 r = SystemConvertInt32( Memory.readUInt8( this._px, idx ) )
                Int32 g = SystemConvertInt32( Memory.readUInt8( this._px, idx + 1 ) )
                Int32 b = SystemConvertInt32( Memory.readUInt8( this._px, idx + 2 ) )
                if DrawTypes.rgb( r, g, b ) != white
                {
                    cnt = cnt + 1
                }
                x = x + 1
            }
            y = y + 1
        }
        ret cnt
    }

    # ── 像素写入 / 清屏 ────────────────────────────────────
    public void setPixel( Int32 x, Int32 y, Int32 c )
    {
        if this._bd == null { ret }
        this._bd.point( x, y, DrawCanvas.col( c ) )
        this._pxDirty = true
    }

    # 整幅覆盖（语义同 BasicDraw.clear：RHI 路径会丢弃已绘制图元）
    public void fill( Int32 c )
    {
        if this._bd == null { ret }
        this._bd.clear( DrawCanvas.col( c ) )
        this._pxDirty = true
    }

    # ── 线 ─────────────────────────────────────────────────
    # 直线（两端包含；BasicDraw GDI LineTo / RHI _strokeSeg）
    public void line( Int32 x0, Int32 y0, Int32 x1, Int32 y1, Int32 c )
    {
        if this._bd == null { ret }
        this._bd.line( x0, y0, x1, y1, DrawCanvas.col( c ) )
        this._pxDirty = true
    }

    # 带线型的线：style 取 DrawTypes.LTY_*（映射 BasicDraw PEN_*）；width 1..8
    public void lineEx( Int32 x0, Int32 y0, Int32 x1, Int32 y1, Int32 c, Int32 style, Int32 width )
    {
        if this._bd == null { ret }
        Int32 w = width
        if w < 1 { w = 1 }
        if w > 8 { w = 8 }
        Int32 pen = BasicDraw.PEN_SOLID
        if style == DrawTypes.LTY_DASHED { pen = BasicDraw.PEN_DASH }
        if style == DrawTypes.LTY_DOTTED { pen = BasicDraw.PEN_DOT }
        if style == DrawTypes.LTY_DASHDOT { pen = BasicDraw.PEN_DASHDOT }
        this._bd.lineEx( x0, y0, x1, y1, w, pen, DrawCanvas.col( c ) )
        this._pxDirty = true
    }

    # 虚线便捷入口（dash/gap 参数保留兼容旧签名；实际走 PEN_DASH 4/4 节距）
    public void dashedLine( Int32 x0, Int32 y0, Int32 x1, Int32 y1, Int32 c, Int32 dash, Int32 gap )
    {
        if this._bd == null { ret }
        this._bd.lineEx( x0, y0, x1, y1, 1, BasicDraw.PEN_DASH, DrawCanvas.col( c ) )
        this._pxDirty = true
    }

    public void polyline( List<Float32> xs, List<Float32> ys, Int32 c )
    {
        if this._bd == null { ret }
        this._bd.polyline( xs, ys, DrawCanvas.col( c ) )
        this._pxDirty = true
    }

    # ── 矩形（x/y/w/h → bbox 端点适配）────────────────────
    public void rect( Int32 x, Int32 y, Int32 w, Int32 h, Int32 c )
    {
        if w <= 0 || h <= 0 { ret }
        if this._bd == null { ret }
        this._bd.rect( x, y, x + w - 1, y + h - 1, DrawCanvas.col( c ) )
        this._pxDirty = true
    }

    public void fillRect( Int32 x, Int32 y, Int32 w, Int32 h, Int32 c )
    {
        if w <= 0 || h <= 0 { ret }
        if this._bd == null { ret }
        this._bd.fillRect( x, y, x + w - 1, y + h - 1, DrawCanvas.col( c ) )
        this._pxDirty = true
    }

    # ── 圆 / 椭圆（cx/cy/r → bbox 端点适配）───────────────
    public void circle( Int32 cx, Int32 cy, Int32 r, Int32 c )
    {
        if r <= 0 { ret }
        if this._bd == null { ret }
        this._bd.circle( cx, cy, r, DrawCanvas.col( c ) )
        this._pxDirty = true
    }

    public void fillCircle( Int32 cx, Int32 cy, Int32 r, Int32 c )
    {
        if r <= 0 { ret }
        if this._bd == null { ret }
        this._bd.fillCircle( cx, cy, r, DrawCanvas.col( c ) )
        this._pxDirty = true
    }

    public void ellipse( Int32 cx, Int32 cy, Int32 rx, Int32 ry, Int32 c )
    {
        if rx <= 0 || ry <= 0 { ret }
        if this._bd == null { ret }
        this._bd.ellipse( cx - rx, cy - ry, cx + rx, cy + ry, DrawCanvas.col( c ) )
        this._pxDirty = true
    }

    public void fillEllipse( Int32 cx, Int32 cy, Int32 rx, Int32 ry, Int32 c )
    {
        if rx <= 0 || ry <= 0 { ret }
        if this._bd == null { ret }
        this._bd.fillEllipse( cx - rx, cy - ry, cx + rx, cy + ry, DrawCanvas.col( c ) )
        this._pxDirty = true
    }

    # 圆弧（起止角为弧度；a1<a0 时归一为 a1→a0 递增扫描，覆盖同一角域）
    public void arc( Int32 cx, Int32 cy, Int32 r, Float32 a0, Float32 a1, Int32 c )
    {
        if r <= 0 { ret }
        if this._bd == null { ret }
        Float32 s = a0
        Float32 e = a1
        if e < s
        {
            s = a1
            e = a0
        }
        Float32 rf = SystemConvertFloat32( r )
        Float32 cxf = SystemConvertFloat32( cx )
        Float32 cyf = SystemConvertFloat32( cy )
        List<Float32> coords = List<Float32>()
        coords.add( cxf - rf )
        coords.add( cyf - rf )
        coords.add( cxf + rf )
        coords.add( cyf + rf )
        coords.add( cxf + rf * DrawTypes.cos( s ) )
        coords.add( cyf + rf * DrawTypes.sin( s ) )
        coords.add( cxf + rf * DrawTypes.cos( e ) )
        coords.add( cyf + rf * DrawTypes.sin( e ) )
        this._bd.arc( coords, DrawCanvas.col( c ) )
        this._pxDirty = true
    }

    # 饼图扇形（起止角为弧度，自圆心扇形闭合；弧采样后走 BasicDraw.fillPolygon）
    public void pieSlice( Int32 cx, Int32 cy, Int32 r, Float32 a0, Float32 a1, Int32 c )
    {
        if r <= 0 { ret }
        if this._bd == null { ret }
        List<Float32> xs = List<Float32>()
        List<Float32> ys = List<Float32>()
        xs.add( SystemConvertFloat32( cx ) )
        ys.add( SystemConvertFloat32( cy ) )
        Float32 step = 2.0f / SystemConvertFloat32( r )
        if step > 0.10f { step = 0.10f }
        if a1 < a0
        {
            Float32 a = a0
            Int32 guard = 0
            while a > a1 && guard < 2048
            {
                xs.add( SystemConvertFloat32( cx ) + SystemConvertFloat32( r ) * DrawTypes.cos( a ) )
                ys.add( SystemConvertFloat32( cy ) + SystemConvertFloat32( r ) * DrawTypes.sin( a ) )
                a = a - step
                guard = guard + 1
            }
        }
        else
        {
            Float32 a = a0
            Int32 guard = 0
            while a < a1 && guard < 2048
            {
                xs.add( SystemConvertFloat32( cx ) + SystemConvertFloat32( r ) * DrawTypes.cos( a ) )
                ys.add( SystemConvertFloat32( cy ) + SystemConvertFloat32( r ) * DrawTypes.sin( a ) )
                a = a + step
                guard = guard + 1
            }
        }
        xs.add( SystemConvertFloat32( cx ) + SystemConvertFloat32( r ) * DrawTypes.cos( a1 ) )
        ys.add( SystemConvertFloat32( cy ) + SystemConvertFloat32( r ) * DrawTypes.sin( a1 ) )
        this._bd.fillPolygon( xs, ys, DrawCanvas.col( c ) )
        this._pxDirty = true
    }

    # ── 多边形 ─────────────────────────────────────────────
    public void polygon( List<Float32> xs, List<Float32> ys, Int32 c )
    {
        if this._bd == null { ret }
        this._bd.polygon( xs, ys, DrawCanvas.col( c ) )
        this._pxDirty = true
    }

    # 填充（转发 BasicDraw.fillPolygon：GDI 原生填充 / RHI 自首顶点扇形三角化）
    public void fillPolygon( List<Float32> xs, List<Float32> ys, Int32 c )
    {
        if this._bd == null { ret }
        this._bd.fillPolygon( xs, ys, DrawCanvas.col( c ) )
        this._pxDirty = true
    }

    # ── 文本（内置 3x5 位图字体；点亮像素走 BasicDraw.point）──
    public void text( Int32 x, Int32 y, string s, Int32 c )
    {
        if this._bd == null { ret }
        DrawCanvas._ensureFont()
        Int32 n = 0
        if s != null
        {
            n = s.length
        }
        Int32 cc = DrawCanvas.col( c )
        Int32 cx = x
        Int32 i = 0
        while i < n
        {
            Int32 code = SystemStringCharCodeAt( s, i )
            if code >= 97 && code <= 122
            {
                code = code - 32
            }
            Int32 gi = DrawCanvas._glyphIndex( code )
            if gi >= 0
            {
                string g = DrawCanvas._font._getItem_( gi )
                Int32 row = 0
                while row < DrawTypes.GLYPH_H
                {
                    string ln = g.slice( row * DrawTypes.GLYPH_W, row * DrawTypes.GLYPH_W + DrawTypes.GLYPH_W )
                    Int32 k = 0
                    while k < DrawTypes.GLYPH_W
                    {
                        if SystemStringCharCodeAt( ln, k ) == 49
                        {
                            this._bd.point( cx + k, y + row, cc )
                        }
                        k = k + 1
                    }
                    row = row + 1
                }
            }
            cx = cx + DrawTypes.GLYPH_ADVANCE
            i = i + 1
        }
        this._pxDirty = true
    }

    static Int32 _glyphIndex( Int32 code )
    {
        Int32 n = DrawCanvas._chars.length
        Int32 i = 0
        while i < n
        {
            if SystemStringCharCodeAt( DrawCanvas._chars, i ) == code
            {
                ret i
            }
            i = i + 1
        }
        ret -1
    }

    static void _ensureFont()
    {
        if DrawCanvas._font != null
        {
            ret
        }
        List<string> f = List<string>()
        f.add( "000000000000000" )
        f.add( "111101111101101" )   # A
        f.add( "110101110101110" )   # B
        f.add( "111100100100111" )   # C
        f.add( "110101101101110" )   # D
        f.add( "111100110100111" )   # E
        f.add( "111100110100100" )   # F
        f.add( "111100101101111" )   # G
        f.add( "101101111101101" )   # H
        f.add( "111010010010111" )   # I
        f.add( "111001001001111" )   # J
        f.add( "101101110101101" )   # K
        f.add( "100100100100111" )   # L
        f.add( "101111111101101" )   # M
        f.add( "110101101101101" )   # N
        f.add( "111101101101111" )   # O
        f.add( "111101111100100" )   # P
        f.add( "111101101111001" )   # Q
        f.add( "111101111110101" )   # R
        f.add( "111100111001111" )   # S
        f.add( "111010010010010" )   # T
        f.add( "101101101101111" )   # U
        f.add( "101101101101010" )   # V
        f.add( "101101111111101" )   # W
        f.add( "101101010101101" )   # X
        f.add( "101101010010010" )   # Y
        f.add( "111001010100111" )   # Z
        f.add( "111101101101111" )   # 0
        f.add( "010110010010111" )   # 1
        f.add( "111001111100111" )   # 2
        f.add( "111001111001111" )   # 3
        f.add( "101101111001001" )   # 4
        f.add( "111100111001111" )   # 5
        f.add( "111100111101111" )   # 6
        f.add( "111001010010010" )   # 7
        f.add( "111101111101111" )   # 8
        f.add( "111101111001111" )   # 9
        f.add( "000000111000000" )   # -
        f.add( "000000000000010" )   # .
        f.add( "110001010100011" )   # %
        f.add( "000010000010000" )   # :
        f.add( "000010111010000" )   # +
        f.add( "001001010100100" )   # /
        f.add( "000000000010100" )   # ,
        f.add( "011100100100011" )   # (
        f.add( "110001001001110" )   # )
        f.add( "000111000111000" )   # =
        f.add( "010111010111010" )   # #
        DrawCanvas._font = f
    }
}
