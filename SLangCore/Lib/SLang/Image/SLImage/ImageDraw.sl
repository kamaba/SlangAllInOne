import Std;

# =========================================================================
# Image/ImageDraw.sl —— 2D 绘图门面（仿 Pillow ImageDraw）
#
# 对标 https://www.runoob.com/pillow/pillow-advanced.html「绘制与文字添加」：
#   draw.line([(x0,y0),(x1,y1)], fill, width)  -> Image.ImageDraw.line( img, x0,y0,x1,y1, c, w )
#   draw.rectangle([x0,y0,x1,y1], outline, fill, width) -> rectangle( img, x0,y0,x1,y1, fill, outline, w )
#   draw.ellipse([x0,y0,x1,y1], outline, fill) -> ellipse( img, x0,y0,x1,y1, fill, outline, w )
#   draw.polygon(points, outline, fill)       -> polygon( img, xs, ys, fill, outline )
#   draw.arc(box, start, end, fill, width)     -> arc( img, x0,y0,x1,y1, startDeg, endDeg, c, w )
#   draw.point((x, y), fill)                   -> point( img, x, y, c )
#   draw.text((x,y), s, fill)                 -> text( img, x, y, s, c )
#   draw.textsize(s)                          -> textWidth( s ) / textHeight
#
# 纯 SL 实现：几何驱动逐像素 setPixel（越界自动丢弃，无崩溃）；
# 绘制区域有界（仅覆盖图形本体），不做整图循环 —— 与 sli_op_* 下沉
# 不冲突。文本用内置 3x5 位图字体（48 字形，与 SimGameEngine 同款）。
# =========================================================================

namespace Image
{
    public class ImageDraw
    {
        # 字形表（惰性构建）：顺序对应 _chars，每字形 5 行 × 3 列拼成 15 字符串
        static List<string> _font = null
        static string _chars = " ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-.%:+/,()=#"

        # ── 点 ───────────────────────────────────────────────
        public static void point( ImageBuffer img, Int32 x, Int32 y, ColorInt c )
        {
            if img == null || c == null
            {
                ret
            }
            img.setPixel( x, y, c )
        }

        # ── 笔刷（方形 hlf = width/2，围绕中心散点）──────────
        static void _brush( ImageBuffer img, Int32 x, Int32 y, ColorInt c, Int32 width )
        {
            if width <= 1
            {
                img.setPixel( x, y, c )
                ret
            }
            Int32 hlf = width / 2
            Int32 dy = 0 - hlf
            while dy <= hlf
            {
                Int32 dx = 0 - hlf
                while dx <= hlf
                {
                    img.setPixel( x + dx, y + dy, c )
                    dx = dx + 1
                }
                dy = dy + 1
            }
        }

        # ── 线（Bresenham + 笔刷；两端点必含）────────────────
        public static void line( ImageBuffer img, Int32 x0, Int32 y0, Int32 x1, Int32 y1, ColorInt c, Int32 width )
        {
            if img == null || c == null
            {
                ret
            }
            Int32 w = width
            if w < 1
            {
                w = 1
            }
            Int32 dx = x1 - x0
            if dx < 0
            {
                dx = 0 - dx
            }
            Int32 dy = y1 - y0
            if dy < 0
            {
                dy = 0 - dy
            }
            Int32 sx = 1
            if x0 >= x1
            {
                sx = -1
            }
            Int32 sy = 1
            if y0 >= y1
            {
                sy = -1
            }
            Int32 err = dx - dy
            Int32 cx = x0
            Int32 cy = y0
            while true
            {
                ImageDraw._brush( img, cx, cy, c, w )
                if cx == x1 && cy == y1
                {
                    break
                }
                Int32 e2 = err * 2
                if e2 > 0 - dy
                {
                    err = err - dy
                    cx = cx + sx
                }
                if e2 < dx
                {
                    err = err + dx
                    cy = cy + sy
                }
            }
        }

        # ── 水平跨度填充（fill != null 时）───────────────────
        static void _span( ImageBuffer img, Int32 x0, Int32 x1, Int32 y, ColorInt fill )
        {
            if fill == null
            {
                ret
            }
            Int32 xa = x0
            Int32 xb = x1
            if xa > xb
            {
                Int32 t = xa
                xa = xb
                xb = t
            }
            while xa <= xb
            {
                img.setPixel( xa, y, fill )
                xa = xa + 1
            }
        }

        # ── 矩形（PIL rectangle：box 含两端）────────────────
        public static void rectangle( ImageBuffer img, Int32 x0, Int32 y0, Int32 x1, Int32 y1, ColorInt fill, ColorInt outline, Int32 outlineWidth )
        {
            if img == null
            {
                ret
            }
            Int32 ax = x0
            Int32 bx = x1
            if ax > bx
            {
                Int32 t = ax
                ax = bx
                bx = t
            }
            Int32 ay = y0
            Int32 by = y1
            if ay > by
            {
                Int32 t = ay
                ay = by
                by = t
            }
            # 填充
            Int32 y = ay
            while y <= by
            {
                ImageDraw._span( img, ax, bx, y, fill )
                y = y + 1
            }
            # 边框（四条线）
            if outline != null
            {
                ImageDraw.line( img, ax, ay, bx, ay, outline, outlineWidth )
                ImageDraw.line( img, ax, by, bx, by, outline, outlineWidth )
                ImageDraw.line( img, ax, ay, ax, by, outline, outlineWidth )
                ImageDraw.line( img, bx, ay, bx, by, outline, outlineWidth )
            }
        }

        public static void rectangle( ImageBuffer img, Int32 x0, Int32 y0, Int32 x1, Int32 y1, ColorInt fill, ColorInt outline )
        {
            ImageDraw.rectangle( img, x0, y0, x1, y1, fill, outline, 1 )
        }

        # ── 椭圆（fill 行跨度 + outline 内缩边界判定）─────────
        static bool _inside( Int32 cx, Int32 cy, Float32 rx, Float32 ry, Int32 x, Int32 y )
        {
            if rx < 0.5f || ry < 0.5f
            {
                if x == cx
                {
                    ret y == cy
                }
                ret false
            }
            Float32 fx = ( 1.0f * x - cx ) / rx
            Float32 fy = ( 1.0f * y - cy ) / ry
            Float32 d = fx * fx + fy * fy
            ret d <= 1.0f
        }

        public static void ellipse( ImageBuffer img, Int32 x0, Int32 y0, Int32 x1, Int32 y1, ColorInt fill, ColorInt outline, Int32 outlineWidth )
        {
            if img == null
            {
                ret
            }
            Int32 ax = x0
            Int32 bx = x1
            if ax > bx
            {
                Int32 t = ax
                ax = bx
                bx = t
            }
            Int32 ay = y0
            Int32 by = y1
            if ay > by
            {
                Int32 t = ay
                ay = by
                by = t
            }
            Int32 cx = ( ax + bx ) / 2
            Int32 cy = ( ay + by ) / 2
            Float32 rx = 0.5f * ( bx - ax )
            Float32 ry = 0.5f * ( by - ay )
            # 填充：逐行求跨度
            if fill != null
            {
                Int32 y = ay
                while y <= by
                {
                    if ImageDraw._inside( cx, cy, rx, ry, cx, y )
                    {
                        Float32 nry = ( 1.0f * y - cy ) / ry
                        Float32 ratio = 1.0f - nry * nry
                        if ratio < 0.0f
                        {
                            ratio = 0.0f
                        }
                        Float32 hspan = ImageMask._sqrt( ratio ) * rx
                        Int32 ih = SystemConvertInt32( hspan + 0.5f )
                        ImageDraw._span( img, cx - ih, cx + ih, y, fill )
                    }
                    y = y + 1
                }
            }
            # 边框：k 内缩层，边界 = 在内缩椭圆上且存在 4 邻域出界
            if outline != null
            {
                Int32 k = 0
                while k < outlineWidth
                {
                    Float32 rkx = rx - k
                    Float32 rky = ry - k
                    if rkx < 0.5f || rky < 0.5f
                    {
                        break
                    }
                    Int32 y = ay
                    while y <= by
                    {
                        Int32 x = ax
                        while x <= bx
                        {
                            if ImageDraw._inside( cx, cy, rkx, rky, x, y )
                            {
                                bool edge = false
                                if !ImageDraw._inside( cx, cy, rkx, rky, x + 1, y )
                                {
                                    edge = true
                                }
                                if !ImageDraw._inside( cx, cy, rkx, rky, x - 1, y )
                                {
                                    edge = true
                                }
                                if !ImageDraw._inside( cx, cy, rkx, rky, x, y + 1 )
                                {
                                    edge = true
                                }
                                if !ImageDraw._inside( cx, cy, rkx, rky, x, y - 1 )
                                {
                                    edge = true
                                }
                                if edge
                                {
                                    img.setPixel( x, y, outline )
                                }
                            }
                            x = x + 1
                        }
                        y = y + 1
                    }
                    k = k + 1
                }
            }
        }

        public static void ellipse( ImageBuffer img, Int32 x0, Int32 y0, Int32 x1, Int32 y1, ColorInt fill, ColorInt outline )
        {
            ImageDraw.ellipse( img, x0, y0, x1, y1, fill, outline, 1 )
        }

        # 圆 = 外接盒的正椭圆
        public static void circle( ImageBuffer img, Int32 cx, Int32 cy, Int32 radius, ColorInt fill, ColorInt outline, Int32 outlineWidth )
        {
            ImageDraw.ellipse( img, cx - radius, cy - radius, cx + radius, cy + radius, fill, outline, outlineWidth )
        }

        # ── 圆弧（0°=右侧，顺时针增大；参数角步进 + 笔刷）─────
        public static void arc( ImageBuffer img, Int32 x0, Int32 y0, Int32 x1, Int32 y1, Int32 startDeg, Int32 endDeg, ColorInt c, Int32 width )
        {
            if img == null || c == null
            {
                ret
            }
            Int32 ax = x0
            Int32 bx = x1
            if ax > bx
            {
                Int32 t = ax
                ax = bx
                bx = t
            }
            Int32 ay = y0
            Int32 by = y1
            if ay > by
            {
                Int32 t = ay
                ay = by
                by = t
            }
            Int32 cx = ( ax + bx ) / 2
            Int32 cy = ( ay + by ) / 2
            Float32 rx = 0.5f * ( bx - ax )
            Float32 ry = 0.5f * ( by - ay )
            Int32 w = width
            if w < 1
            {
                w = 1
            }
            Int32 sweep = endDeg - startDeg
            if sweep < 0
            {
                sweep = 0 - sweep
            }
            if sweep > 360
            {
                sweep = 360
            }
            Int32 steps = SystemConvertInt32( rx )
            if ry > rx
            {
                steps = SystemConvertInt32( ry )
            }
            steps = steps * 8 + 8
            Int32 i = 0
            while i <= steps
            {
                Float32 ang = 1.0f * ( startDeg + sweep * i / steps ) * 3.14159265f / 180.0f
                Float32 fx = 1.0f * cx + Image.ImageBuffer._cos( ang ) * rx
                Float32 fy = 1.0f * cy + Image.ImageBuffer._sin( ang ) * ry
                ImageDraw._brush( img, SystemConvertInt32( fx + 0.5f ), SystemConvertInt32( fy + 0.5f ), c, w )
                i = i + 1
            }
        }

        # ── 多边形（even-odd 扫线填充 + 顶点连线描边）─────────
        public static void polygon( ImageBuffer img, List<Int32> xs, List<Int32> ys, ColorInt fill, ColorInt outline )
        {
            if img == null || xs == null || ys == null
            {
                ret
            }
            Int32 n = xs.length
            if n < 3 || ys.length != n
            {
                ret
            }
            # 包围盒
            Int32 ymin = ys[ 0 ]
            Int32 ymax = ys[ 0 ]
            Int32 i = 1
            while i < n
            {
                if ys[ i ] < ymin
                {
                    ymin = ys[ i ]
                }
                if ys[ i ] > ymax
                {
                    ymax = ys[ i ]
                }
                i = i + 1
            }
            # 填充：逐扫描行收集边交点 → 排序 → 成对填充
            if fill != null
            {
                Int32 y = ymin
                while y <= ymax
                {
                    List<Float32> crossings = List<Float32>()
                    i = 0
                    while i < n
                    {
                        Int32 j = i + 1
                        if j >= n
                        {
                            j = 0
                        }
                        Int32 ya = ys[ i ]
                        Int32 yb = ys[ j ]
                        bool cross = false
                        if ya <= y && yb > y
                        {
                            cross = true
                        }
                        if yb <= y && ya > y
                        {
                            cross = true
                        }
                        if cross
                        {
                            Float32 t = 1.0f * ( y - ya ) / ( yb - ya )
                            Int32 xi0 = xs[ i ]
                            Int32 xi1 = xs[ j ]
                            Float32 xi = 1.0f * xi0 + ( 1.0f * xi1 - 1.0f * xi0 ) * t
                            crossings.add( xi )
                        }
                        i = i + 1
                    }
                    # 插入排序（变量索引走 _getItem_/_setItem_——List 泛型索引器
                    # 声明语句右侧不稳定，坑 7 同族）
                    Int32 cn = crossings.length
                    Int32 a = 1
                    while a < cn
                    {
                        Float32 v = crossings._getItem_( a )
                        Int32 b = a - 1
                        bool go = true
                        while go
                        {
                            if b < 0
                            {
                                go = false
                            }
                            else
                            {
                                Float32 vb = crossings._getItem_( b )
                                if vb > v
                                {
                                    crossings._setItem_( b + 1, vb )
                                    b = b - 1
                                }
                                else
                                {
                                    go = false
                                }
                            }
                        }
                        crossings._setItem_( b + 1, v )
                        a = a + 1
                    }
                    # 成对填充
                    Int32 p = 0
                    while p + 1 < cn
                    {
                        Float32 ca = crossings._getItem_( p )
                        Float32 cb = crossings._getItem_( p + 1 )
                        Int32 xa = SystemConvertInt32( ca + 0.5f )
                        Int32 xb = SystemConvertInt32( cb + 0.5f )
                        ImageDraw._span( img, xa, xb, y, fill )
                        p = p + 2
                    }
                    y = y + 1
                }
            }
            # 描边：闭合折线（泛型索引器先取局部——坑 7）
            if outline != null
            {
                i = 0
                while i < n
                {
                    Int32 j = i + 1
                    if j >= n
                    {
                        j = 0
                    }
                    Int32 x0 = xs[ i ]
                    Int32 y0 = ys[ i ]
                    Int32 x1 = xs[ j ]
                    Int32 y1 = ys[ j ]
                    ImageDraw.line( img, x0, y0, x1, y1, outline, 1 )
                    i = i + 1
                }
            }
        }

        # fillPolygon 等价（PIL 风格别名）
        public static void fillPolygon( ImageBuffer img, List<Int32> xs, List<Int32> ys, ColorInt fill )
        {
            ImageDraw.polygon( img, xs, ys, fill, null )
        }

        # ── 文本（内置 3x5 位图字体，48 字形）────────────────
        static void _ensureFont()
        {
            if ImageDraw._font != null
            {
                ret
            }
            List<string> f = List<string>()
            f.add( "000000000000000" )
            f.add( "111101111101101" )
            f.add( "110101110101110" )
            f.add( "111100100100111" )
            f.add( "110101101101110" )
            f.add( "111100110100111" )
            f.add( "111100110100100" )
            f.add( "111100101101111" )
            f.add( "101101111101101" )
            f.add( "111010010010111" )
            f.add( "111001001001111" )
            f.add( "101101110101101" )
            f.add( "100100100100111" )
            f.add( "101111111101101" )
            f.add( "110101101101101" )
            f.add( "111101101101111" )
            f.add( "111101111100100" )
            f.add( "111101101111001" )
            f.add( "111101111110101" )
            f.add( "111100111001111" )
            f.add( "111010010010010" )
            f.add( "101101101101111" )
            f.add( "101101101101010" )
            f.add( "101101111111101" )
            f.add( "101101010101101" )
            f.add( "101101010010010" )
            f.add( "111001010100111" )
            f.add( "111101101101111" )
            f.add( "010110010010111" )
            f.add( "111001111100111" )
            f.add( "111001111001111" )
            f.add( "101101111001001" )
            f.add( "111100111001111" )
            f.add( "111100111101111" )
            f.add( "111001010010010" )
            f.add( "111101111101111" )
            f.add( "111101111001111" )
            f.add( "000000111000000" )
            f.add( "000000000000010" )
            f.add( "110001010100011" )
            f.add( "000010000010000" )
            f.add( "000010111010000" )
            f.add( "001001010100100" )
            f.add( "000000000010100" )
            f.add( "011100100100011" )
            f.add( "110001001001110" )
            f.add( "000111000111000" )
            f.add( "010111010111010" )
            ImageDraw._font = f
        }

        static Int32 _glyphIndex( Int32 code )
        {
            Int32 n = ImageDraw._chars.length
            Int32 i = 0
            while i < n
            {
                if SystemStringCharCodeAt( ImageDraw._chars, i ) == code
                {
                    ret i
                }
                i = i + 1
            }
            ret -1
        }

        # 绘制一行文本（小写自动转大写；未知字符跳格）
        public static void text( ImageBuffer img, Int32 x, Int32 y, string s, ColorInt c )
        {
            if img == null || c == null || s == null
            {
                ret
            }
            ImageDraw._ensureFont()
            Int32 n = s.length
            Int32 cx = x
            Int32 i = 0
            while i < n
            {
                Int32 code = SystemStringCharCodeAt( s, i )
                if code >= 97 && code <= 122
                {
                    code = code - 32
                }
                Int32 gi = ImageDraw._glyphIndex( code )
                if gi >= 0
                {
                    string g = ImageDraw._font._getItem_( gi )
                    Int32 row = 0
                    while row < 5
                    {
                        string ln = g.slice( row * 3, row * 3 + 3 )
                        Int32 k = 0
                        while k < 3
                        {
                            if SystemStringCharCodeAt( ln, k ) == 49
                            {
                                img.setPixel( cx + k, y + row, c )
                            }
                            k = k + 1
                        }
                        row = row + 1
                    }
                }
                cx = cx + 4
                i = i + 1
            }
        }

        # 文本尺寸（步进 4：3 宽字形 + 1 间隔；高恒 5）
        public static Int32 textWidth( string s )
        {
            Int32 n = 0
            if s != null
            {
                n = s.length
            }
            if n <= 0
            {
                ret 0
            }
            ret n * 4 - 1
        }

        public static Int32 textHeight()
        {
            ret 5
        }

        override string toString()
        {
            ret "ImageDraw"
        }
    }
}
