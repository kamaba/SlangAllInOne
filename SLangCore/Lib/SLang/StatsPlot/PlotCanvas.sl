# =========================================================================
# Stats/PlotCanvas.sl —— RGBA8 软光栅画布 + 图元 + 内置 3×5 位图字体
#
# 用法见 doc/02-Usage.md §4/§5；实现说明见 doc/01-Design.md §5.4/D2/D3。
# 像素契约：RGBA8 top-down、alpha 恒 255，原生缓冲（Memory.alloc）。
#   pixelPtr() 直接对喂 slQT QLabel.setPixmapRgba(ptr, w, h)（RenderTest 同款通道）。
# 字体：内置 3×5 位图（ASCII 48 字形：数字/大写字母/符号；小写自动转大写）；
#       未经 CSS 无抗锯齿，标签简体、定位由 Plot 层负责。
# =========================================================================

import Core;
import Std;

namespace StatsPlot
{
    public class PlotCanvas
    {
        Int32 _w = 0
        Int32 _h = 0
        Int64 _px = 0

        # 字形表（惰性构建）：_chars 顺序一一对应，每字形 5 行 × 3 列拼为 15 字符串
        static List<string> _f = null
        static string _chars = " ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-.%:+/,()=#"

        _init_()
        {
            this._w = 0
            this._h = 0
            this._px = 0
        }

        # ── 创建 / 释放 ────────────────────────────────────
        public static PlotCanvas create( Int32 w, Int32 h )
        {
            PlotCanvas c = PlotCanvas()
            c._w = w
            c._h = h
            Int32 total = w * h * 4
            if total <= 0
            {
                ret c
            }
            c._px = Memory.alloc( total )
            c.fill( PlotCanvas.rgb( 255, 255, 255 ) )
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

        # RGBA8 缓冲地址（上屏/落盘通道；配合 width/height）
        public Int64 pixelPtr()
        {
            ret this._px
        }

        public void free()
        {
            if this._px != 0
            {
                Memory.free( this._px )
                this._px = 0
            }
        }

        # ── 颜色 ───────────────────────────────────────────
        public static Int32 rgb( Int32 r, Int32 g, Int32 b )
        {
            ret ( r << 16 ) | ( g << 8 ) | b
        }

        public static Int32 redOf( Int32 c )
        {
            ret ( c >> 16 ) & 255
        }

        public static Int32 greenOf( Int32 c )
        {
            ret ( c >> 8 ) & 255
        }

        public static Int32 blueOf( Int32 c )
        {
            ret c & 255
        }

        # R 默认调色板 palette()：black/red/green3/blue/cyan/magenta/yellow/gray
        public static Int32 palette( Int32 i )
        {
            Int32 k = i % 8
            if k == 0 { ret PlotCanvas.rgb( 0, 0, 0 ) }
            if k == 1 { ret PlotCanvas.rgb( 255, 0, 0 ) }
            if k == 2 { ret PlotCanvas.rgb( 0, 205, 0 ) }
            if k == 3 { ret PlotCanvas.rgb( 0, 0, 255 ) }
            if k == 4 { ret PlotCanvas.rgb( 0, 255, 255 ) }
            if k == 5 { ret PlotCanvas.rgb( 255, 0, 255 ) }
            if k == 6 { ret PlotCanvas.rgb( 255, 255, 0 ) }
            ret PlotCanvas.rgb( 128, 128, 128 )
        }

        # ── 像素 ───────────────────────────────────────────
        public void setPixel( Int32 x, Int32 y, Int32 c )
        {
            if this._px == 0 { ret }
            if x < 0 || y < 0 { ret }
            if x >= this._w || y >= this._h { ret }
            Int32 idx = ( y * this._w + x ) * 4
            Memory.writeI8( this._px, idx, PlotCanvas.redOf( c ) )
            Memory.writeI8( this._px, idx + 1, PlotCanvas.greenOf( c ) )
            Memory.writeI8( this._px, idx + 2, PlotCanvas.blueOf( c ) )
            Memory.writeI8( this._px, idx + 3, 255 )
        }

        # 读打包色（越界返回 -1）
        public Int32 pixelAt( Int32 x, Int32 y )
        {
            if this._px == 0 { ret -1 }
            if x < 0 || y < 0 { ret -1 }
            if x >= this._w || y >= this._h { ret -1 }
            Int32 idx = ( y * this._w + x ) * 4
            Int32 r = SystemConvertInt32( Memory.readUInt8( this._px, idx ) )
            Int32 g = SystemConvertInt32( Memory.readUInt8( this._px, idx + 1 ) )
            Int32 b = SystemConvertInt32( Memory.readUInt8( this._px, idx + 2 ) )
            ret PlotCanvas.rgb( r, g, b )
        }

        public bool pixelIs( Int32 x, Int32 y, Int32 c )
        {
            ret this.pixelAt( x, y ) == c
        }

        # 区域非白像素计数（测试断言主通道）
        public Int32 nonWhiteCount( Int32 x0, Int32 y0, Int32 x1, Int32 y1 )
        {
            if this._px == 0 { ret 0 }
            Int32 xa = x0
            Int32 ya = y0
            Int32 xb = x1
            Int32 yb = y1
            if xa < 0 { xa = 0 }
            if ya < 0 { ya = 0 }
            if xb > this._w { xb = this._w }
            if yb > this._h { yb = this._h }
            if xa >= xb || ya >= yb { ret 0 }
            Int32 cnt = 0
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
                    if r != 255 || g != 255 || b != 255
                    {
                        cnt = cnt + 1
                    }
                    x = x + 1
                }
                y = y + 1
            }
            ret cnt
        }

        # ── 整块 ───────────────────────────────────────────
        public void fill( Int32 c )
        {
            if this._px == 0 { ret }
            Int32 rr = PlotCanvas.redOf( c )
            Int32 gg = PlotCanvas.greenOf( c )
            Int32 bb = PlotCanvas.blueOf( c )
            Int32 total = this._w * this._h
            Int32 i = 0
            while i < total
            {
                Int32 idx = i * 4
                Memory.writeI8( this._px, idx, rr )
                Memory.writeI8( this._px, idx + 1, gg )
                Memory.writeI8( this._px, idx + 2, bb )
                Memory.writeI8( this._px, idx + 3, 255 )
                i = i + 1
            }
        }

        # ── 图元 ───────────────────────────────────────────
        public void fillRect( Int32 x, Int32 y, Int32 w, Int32 h, Int32 c )
        {
            Int32 y0 = y
            if y0 < 0 { y0 = 0 }
            Int32 y1 = y + h
            if y1 > this._h { y1 = this._h }
            Int32 x0 = x
            if x0 < 0 { x0 = 0 }
            Int32 x1 = x + w
            if x1 > this._w { x1 = this._w }
            Int32 yy = y0
            while yy < y1
            {
                Int32 xx = x0
                while xx < x1
                {
                    this.setPixel( xx, yy, c )
                    xx = xx + 1
                }
                yy = yy + 1
            }
        }

        public void rectBorder( Int32 x, Int32 y, Int32 w, Int32 h, Int32 c )
        {
            if w <= 0 || h <= 0 { ret }
            this.line( x, y, x + w - 1, y, c )
            this.line( x, y + h - 1, x + w - 1, y + h - 1, c )
            this.line( x, y, x, y + h - 1, c )
            this.line( x + w - 1, y, x + w - 1, y + h - 1, c )
        }

        # Bresenham 直线
        public void line( Int32 x0, Int32 y0, Int32 x1, Int32 y1, Int32 c )
        {
            Int32 ax = x0
            Int32 ay = y0
            Int32 bx = x1
            Int32 by = y1
            Int32 dx = bx - ax
            Int32 dy = by - ay
            Int32 adx = dx
            if adx < 0 { adx = 0 - adx }
            Int32 ady = dy
            if ady < 0 { ady = 0 - ady }
            Int32 sx = 1
            if dx < 0 { sx = -1 }
            Int32 sy = 1
            if dy < 0 { sy = -1 }
            Int32 err = adx - ady
            Int32 negA = 0 - ady
            Int32 guard = 0
            Int32 maxStep = adx + ady + 2
            while guard < maxStep
            {
                this.setPixel( ax, ay, c )
                if ax == bx && ay == by
                {
                    break
                }
                Int32 e2 = err * 2
                if e2 > negA
                {
                    err = err - ady
                    ax = ax + sx
                }
                if e2 < adx
                {
                    err = err + adx
                    ay = ay + sy
                }
                guard = guard + 1
            }
        }

        # 多段线（坐标 Float32，内部取整）
        public void polyline( List<Float32> xs, List<Float32> ys, Int32 c )
        {
            Int32 n = xs.length
            if n < 2
            {
                ret
            }
            Int32 i = 0
            while i < n - 1
            {
                this.line( xs._getItem_( i ) as Int32, ys._getItem_( i ) as Int32, xs._getItem_( i + 1 ) as Int32, ys._getItem_( i + 1 ) as Int32, c )
                i = i + 1
            }
        }

        # 多边形扫描线填充（饼图切片/箱体；顶点按出现顺序闭合）
        public void polygonFilled( List<Float32> xs, List<Float32> ys, Int32 c )
        {
            Int32 n = xs.length
            if n < 3
            {
                ret
            }
            Int32 minY = ys._getItem_( 0 ) as Int32
            Int32 maxY = ys._getItem_( 0 ) as Int32
            Int32 i = 0
            while i < n
            {
                Int32 yy = ys._getItem_( i ) as Int32
                if yy < minY { minY = yy }
                if yy > maxY { maxY = yy }
                i = i + 1
            }
            if minY < 0 { minY = 0 }
            if maxY >= this._h { maxY = this._h - 1 }
            if maxY < minY { ret }
            Int32 y = minY
            while y <= maxY
            {
                List<Int32> its = List<Int32>()
                Int32 e = 0
                while e < n
                {
                    Float32 x0v = xs._getItem_( e )
                    Float32 y0v = ys._getItem_( e )
                    Float32 x1v = xs._getItem_( ( e + 1 ) % n )
                    Float32 y1v = ys._getItem_( ( e + 1 ) % n )
                    Float32 fy = SystemConvertFloat32( y )
                    if ( y0v <= fy && fy < y1v ) || ( y1v <= fy && fy < y0v )
                    {
                        Float32 den = y1v - y0v
                        if den != 0.0f
                        {
                            Float32 t = ( fy - y0v ) / den
                            Float32 px = x0v + t * ( x1v - x0v )
                            its.add( px as Int32 )
                        }
                    }
                    e = e + 1
                }
                # 交点排序 + 两两成对填充
                Int32 m = its.length
                i = 0
                while i < m
                {
                    Int32 j = 0
                    while j < m - i - 1
                    {
                        if its._getItem_( j ) > its._getItem_( j + 1 )
                        {
                            Int32 t2 = its._getItem_( j )
                            its._setItem_( j, its._getItem_( j + 1 ) )
                            its._setItem_( j + 1, t2 )
                        }
                        j = j + 1
                    }
                    i = i + 1
                }
                i = 0
                while i + 1 < its.length
                {
                    Int32 xa = its._getItem_( i )
                    Int32 xb = its._getItem_( i + 1 )
                    Int32 xx = xa
                    while xx <= xb
                    {
                        this.setPixel( xx, y, c )
                        xx = xx + 1
                    }
                    i = i + 2
                }
                y = y + 1
            }
        }

        # 实心圆
        public void circleFilled( Int32 cx, Int32 cy, Int32 r, Int32 c )
        {
            Int32 rr = r * r
            Int32 y = cy - r
            while y <= cy + r
            {
                Int32 x = cx - r
                while x <= cx + r
                {
                    Int32 dx = x - cx
                    Int32 dy = y - cy
                    if dx * dx + dy * dy <= rr
                    {
                        this.setPixel( x, y, c )
                    }
                    x = x + 1
                }
                y = y + 1
            }
        }

        # ── 文本（3×5 位图）────────────────────────────────
        public void text( Int32 x, Int32 y, string s, Int32 c )
        {
            PlotCanvas._ensureFont()
            Int32 n = 0
            if s != null
            {
                n = s.length
            }
            Int32 cx = x
            Int32 i = 0
            while i < n
            {
                Int32 code = SystemStringCharCodeAt( s, i )
                if code >= 97 && code <= 122
                {
                    code = code - 32
                }
                Int32 gi = PlotCanvas._glyphIndex( code )
                if gi >= 0
                {
                    string g = PlotCanvas._f._getItem_( gi )
                    Int32 rrow = 0
                    while rrow < 5
                    {
                        string row = g.slice( rrow * 3, rrow * 3 + 3 )
                        Int32 k = 0
                        while k < 3
                        {
                            if SystemStringCharCodeAt( row, k ) == 49
                            {
                                this.setPixel( cx + k, y + rrow, c )
                            }
                            k = k + 1
                        }
                        rrow = rrow + 1
                    }
                }
                cx = cx + 4
                i = i + 1
            }
        }

        static Int32 _glyphIndex( Int32 code )
        {
            Int32 n = PlotCanvas._chars.length
            Int32 i = 0
            while i < n
            {
                if SystemStringCharCodeAt( PlotCanvas._chars, i ) == code
                {
                    ret i
                }
                i = i + 1
            }
            ret -1
        }

        static void _ensureFont()
        {
            if PlotCanvas._f != null
            {
                ret
            }
            List<string> f = List<string>()
            f.add( "000000000000000" )   # ' ' 空白
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
            PlotCanvas._f = f
        }
    }
}