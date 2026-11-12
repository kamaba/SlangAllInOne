# =========================================================================
# Std/ColorInt.sl —— 8bit RGBA 颜色（Image.Color + Render/ColorUInt8 合并）
#
# 通道存 Int32，值域恒 0..255（构造时钳制，杜绝越界字节写回像素缓冲）。
# 灰度加权：ITU-R BT.601（299/587/114），与 ImageBuffer 像素运算字节级兼容。
# toInt(Float32)：浮点加权结果四舍五入回 0..255 字节，供双线性重采样等
# 亚像素运算使用（ImageBuffer.resizeBilinear 的唯一浮点出口）。
# HSL / YCbCr / alpha 合成 / 亮度 / 打包互转 继承自 Render 侧 ColorUInt8。
#
# 浮点转整数统一走 SystemConvertInt32（显式、可读、不依赖隐式截断）。
# 纯 SL 实现，无后端依赖。
# =========================================================================

public class ColorInt
{
    public Int32 r = 0
    public Int32 g = 0
    public Int32 b = 0
    public Int32 a = 0

    # ── 构造 ─────────────────────────────────────────────

    _init_()
    {
        this.r = 0
        this.g = 0
        this.b = 0
        this.a = 0
    }

    # 灰度（不透明）
    _init_( Int32 v )
    {
        this.r = ColorInt.clamp8( v )
        this.g = this.r
        this.b = this.r
        this.a = 255
    }

    # RGB（不透明）
    _init_( Int32 _r, Int32 _g, Int32 _b )
    {
        this.r = ColorInt.clamp8( _r )
        this.g = ColorInt.clamp8( _g )
        this.b = ColorInt.clamp8( _b )
        this.a = 255
    }

    _init_( Int32 _r, Int32 _g, Int32 _b, Int32 _a )
    {
        this.r = ColorInt.clamp8( _r )
        this.g = ColorInt.clamp8( _g )
        this.b = ColorInt.clamp8( _b )
        this.a = ColorInt.clamp8( _a )
    }

    # ── 静态工厂 ─────────────────────────────────────────

    public static ColorInt transparent()
    {
        ret ColorInt( 0, 0, 0, 0 )
    }

    public static ColorInt black()
    {
        ret ColorInt( 0, 0, 0 )
    }

    public static ColorInt white()
    {
        ret ColorInt( 255, 255, 255 )
    }

    public static ColorInt fromRgb( Int32 r, Int32 g, Int32 b )
    {
        ret ColorInt( r, g, b )
    }

    public static ColorInt fromRgba( Int32 r, Int32 g, Int32 b, Int32 a )
    {
        ret ColorInt( r, g, b, a )
    }

    # 0xRRGGBBAA
    public static ColorInt fromPackedRgba( Int32 packed )
    {
        Int32 rr = ( packed >> 24 ) & 0xFF
        Int32 gg = ( packed >> 16 ) & 0xFF
        Int32 bb = ( packed >> 8 ) & 0xFF
        Int32 aa = packed & 0xFF
        ret ColorInt( rr, gg, bb, aa )
    }

    # 0xAARRGGBB
    public static ColorInt fromPackedArgb( Int32 packed )
    {
        Int32 aa = ( packed >> 24 ) & 0xFF
        Int32 rr = ( packed >> 16 ) & 0xFF
        Int32 gg = ( packed >> 8 ) & 0xFF
        Int32 bb = packed & 0xFF
        ret ColorInt( rr, gg, bb, aa )
    }

    # ── 打包 ─────────────────────────────────────────────

    # 0xRRGGBBAA
    public Int32 toPackedRgba()
    {
        Int32 v = ( this.r & 0xFF ) << 24
        v = v | ( ( this.g & 0xFF ) << 16 )
        v = v | ( ( this.b & 0xFF ) << 8 )
        v = v | ( this.a & 0xFF )
        ret v
    }

    # 0xAARRGGBB
    public Int32 toPackedArgb()
    {
        Int32 v = ( this.a & 0xFF ) << 24
        v = v | ( ( this.r & 0xFF ) << 16 )
        v = v | ( ( this.g & 0xFF ) << 8 )
        v = v | ( this.b & 0xFF )
        ret v
    }

    # ── 属性 ─────────────────────────────────────────────

    public get bool isOpaque()
    {
        ret this.a >= 255
    }

    public get bool isTransparent()
    {
        ret this.a <= 0
    }

    # Rec.709 亮度，范围 0..1
    public get Float32 luma()
    {
        Float32 rr = 1.0f * this.r / 255.0f
        Float32 gg = 1.0f * this.g / 255.0f
        Float32 bb = 1.0f * this.b / 255.0f
        ret 0.2126f * rr + 0.7152f * gg + 0.0722f * bb
    }

    # ── 数值工具 ─────────────────────────────────────────

    public static Int32 clamp8( Int32 v )
    {
        if v < 0
        {
            ret 0
        }
        if v > 255
        {
            ret 255
        }
        ret v
    }

    # 浮点 -> 0..255 字节（四舍五入 + 钳制）
    public static Int32 toInt( Float32 v )
    {
        Int32 i = SystemConvertInt32( v + 0.5f )
        ret ColorInt.clamp8( i )
    }

    # 0..1 的浮点转 0..255 字节（带四舍五入 + 饱和）
    public static Int32 toByte( Float32 v )
    {
        if v < 0.0f
        {
            ret 0
        }
        if v > 1.0f
        {
            ret 255
        }
        ret SystemConvertInt32( v * 255.0f + 0.5f )
    }

    public static Float32 max3( Float32 a, Float32 b, Float32 c )
    {
        Float32 m = a
        if b > m { m = b }
        if c > m { m = c }
        ret m
    }

    public static Float32 min3( Float32 a, Float32 b, Float32 c )
    {
        Float32 m = a
        if b < m { m = b }
        if c < m { m = c }
        ret m
    }

    # ── 派生色 ───────────────────────────────────────────

    # ITU-R BT.601 加权灰度；alpha 原样保留
    public ColorInt grayscale()
    {
        Int32 v = ( 299 * this.r + 587 * this.g + 114 * this.b + 500 ) / 1000
        ret ColorInt( v, v, v, this.a )
    }

    # 直通 alpha -> 预乘 alpha（四舍五入）
    public ColorInt premultiply()
    {
        ret ColorInt( ( this.r * this.a + 127 ) / 255,
                      ( this.g * this.a + 127 ) / 255,
                      ( this.b * this.a + 127 ) / 255,
                      this.a )
    }

    # 预乘 alpha -> 直通 alpha（钳制 255；a=0 归零）
    public ColorInt unpremultiply()
    {
        if this.a <= 0
        {
            ret ColorInt( 0, 0, 0, 0 )
        }
        if this.a >= 255
        {
            ret ColorInt( this.r, this.g, this.b, this.a )
        }
        ret ColorInt( ColorInt.clamp8( this.r * 255 / this.a ),
                      ColorInt.clamp8( this.g * 255 / this.a ),
                      ColorInt.clamp8( this.b * 255 / this.a ),
                      this.a )
    }

    # 保持 rgb，替换 alpha
    public ColorInt withAlpha( Int32 alpha )
    {
        ret ColorInt( this.r, this.g, this.b, alpha )
    }

    public ColorInt invert()
    {
        ret ColorInt( 255 - this.r, 255 - this.g, 255 - this.b, this.a )
    }

    public ColorInt lerp( ColorInt other, Float32 t )
    {
        if t < 0.0f { t = 0.0f }
        if t > 1.0f { t = 1.0f }
        Int32 nr = this.r + ColorInt.toInt( ( 1.0f * other.r - this.r ) * t )
        Int32 ng = this.g + ColorInt.toInt( ( 1.0f * other.g - this.g ) * t )
        Int32 nb = this.b + ColorInt.toInt( ( 1.0f * other.b - this.b ) * t )
        Int32 na = this.a + ColorInt.toInt( ( 1.0f * other.a - this.a ) * t )
        ret ColorInt( nr, ng, nb, na )
    }

    # ── alpha 合成：src over dst ─────────────────────────

    public static ColorInt blendOver( ColorInt dst, ColorInt src )
    {
        if src.a >= 255
        {
            ret src
        }
        if src.a <= 0
        {
            ret dst
        }
        Float32 sa = 1.0f * src.a / 255.0f
        Float32 da = 1.0f * dst.a / 255.0f
        Float32 oa = sa + da * ( 1.0f - sa )
        if oa <= 0.0f
        {
            ret ColorInt( 0, 0, 0, 0 )
        }
        Float32 rr = ( 1.0f * src.r * sa + 1.0f * dst.r * da * ( 1.0f - sa ) ) / oa
        Float32 gg = ( 1.0f * src.g * sa + 1.0f * dst.g * da * ( 1.0f - sa ) ) / oa
        Float32 bb = ( 1.0f * src.b * sa + 1.0f * dst.b * da * ( 1.0f - sa ) ) / oa
        ret ColorInt( ColorInt.toInt( rr ), ColorInt.toInt( gg ), ColorInt.toInt( bb ),
                      ColorInt.toByte( oa ) )
    }

    # ── HSL：返回 [h(0..360), s(0..1), l(0..1)] ──────────

    public Array<Float32> toHsl()
    {
        Array<Float32> res = Array<Float32>( 3 )
        Float32 rr = 1.0f * this.r / 255.0f
        Float32 gg = 1.0f * this.g / 255.0f
        Float32 bb = 1.0f * this.b / 255.0f
        Float32 max = ColorInt.max3( rr, gg, bb )
        Float32 min = ColorInt.min3( rr, gg, bb )
        Float32 l = ( max + min ) * 0.5f
        Float32 h = 0.0f
        Float32 s = 0.0f
        if max > min
        {
            Float32 d = max - min
            if l > 0.5f
            {
                s = d / ( 2.0f - max - min )
            }
            else
            {
                s = d / ( max + min )
            }
            if max == rr
            {
                h = ( gg - bb ) / d
                if gg < bb { h = h + 6.0f }
            }
            elif max == gg
            {
                h = ( bb - rr ) / d + 2.0f
            }
            else
            {
                h = ( rr - gg ) / d + 4.0f
            }
            h = h * 60.0f
        }
        res[0] = h
        res[1] = s
        res[2] = l
        ret res
    }

    public static ColorInt fromHsl( Float32 h, Float32 s, Float32 l )
    {
        if s <= 0.0f
        {
            Int32 v = ColorInt.toByte( l )
            ret ColorInt( v, v, v )
        }
        Float32 hh = h / 60.0f
        while hh >= 6.0f
        {
            hh = hh - 6.0f
        }
        while hh < 0.0f
        {
            hh = hh + 6.0f
        }
        Float32 q = 0.0f
        if l < 0.5f
        {
            q = l * ( 1.0f + s )
        }
        else
        {
            q = l + s - l * s
        }
        Float32 p = 2.0f * l - q
        Float32 rr = ColorInt.hue2rgb( p, q, hh + 2.0f )
        Float32 gg = ColorInt.hue2rgb( p, q, hh )
        Float32 bb = ColorInt.hue2rgb( p, q, hh - 2.0f )
        ret ColorInt( ColorInt.toByte( rr ), ColorInt.toByte( gg ), ColorInt.toByte( bb ) )
    }

    # ── YCbCr（JPEG / 视频内部色彩空间）───────────────────

    public Array<Float32> toYCbCr()
    {
        Array<Float32> res = Array<Float32>( 3 )
        Float32 rr = 1.0f * this.r
        Float32 gg = 1.0f * this.g
        Float32 bb = 1.0f * this.b
        res[0] = 0.299f * rr + 0.587f * gg + 0.114f * bb
        res[1] = 128.0f - 0.168736f * rr - 0.331264f * gg + 0.5f * bb
        res[2] = 128.0f + 0.5f * rr - 0.418688f * gg - 0.081312f * bb
        ret res
    }

    public static ColorInt fromYCbCr( Float32 y, Float32 cb, Float32 cr )
    {
        Float32 rr = y + 1.402f * ( cr - 128.0f )
        Float32 gg = y - 0.344136f * ( cb - 128.0f ) - 0.714136f * ( cr - 128.0f )
        Float32 bb = y + 1.772f * ( cb - 128.0f )
        ret ColorInt( ColorInt.toByte( rr / 255.0f ), ColorInt.toByte( gg / 255.0f ),
                      ColorInt.toByte( bb / 255.0f ) )
    }

    # ── 运算 ─────────────────────────────────────────────

    public void clamp()
    {
        this.r = ColorInt.clamp8( this.r )
        this.g = ColorInt.clamp8( this.g )
        this.b = ColorInt.clamp8( this.b )
        this.a = ColorInt.clamp8( this.a )
    }

    # ── 内部工具 ─────────────────────────────────────────

    static Float32 hue2rgb( Float32 p, Float32 q, Float32 t )
    {
        Float32 tt = t
        if tt < 0.0f { tt = tt + 6.0f }
        if tt >= 6.0f { tt = tt - 6.0f }
        if tt < 1.0f { ret p + ( q - p ) * tt }
        if tt < 3.0f { ret q }
        if tt < 4.0f { ret p + ( q - p ) * ( 4.0f - tt ) }
        ret p
    }

    override string toString()
    {
        string s = "ColorInt("
        s = s + this.r.toString() + "," + this.g.toString()
        s = s + "," + this.b.toString() + "," + this.a.toString()
        s = s + ")"
        ret s
    }

    override bool _eq_( ColorInt c )
    {
        ret this.r == c.r && this.g == c.g && this.b == c.b && this.a == c.a
    }

    override bool _ne_( ColorInt c )
    {
        ret !this._eq_( c )
    }
}
