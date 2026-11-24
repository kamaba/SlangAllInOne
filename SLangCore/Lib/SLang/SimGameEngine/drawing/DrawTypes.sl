# ============================================================================
# DrawTypes — 绘图常量层（SimGameEngine 基础绘图 / doc/24）
# ----------------------------------------------------------------------------
# 纯常量：线型 / 点符号 / 图例位置 / 调色板 / 字体缩放。
# 颜色为打包 Int32（0x00RRGGBB，低 24 位 RGB），与 DrawCanvas 像素契约一致。
# 命名对齐：R 基元图形（lty/pch/col/cex）语义 + SLang camelCase 风格。
# 零 C 依赖、零跨模块调用。
# ============================================================================

public class DrawTypes
{
    # ── 线型（R lty）──
    public static Int32 LTY_SOLID = 0
    public static Int32 LTY_DASHED = 1
    public static Int32 LTY_DOTTED = 2
    public static Int32 LTY_DASHDOT = 3

    # ── 点符号（R pch）──
    public static Int32 PCH_NONE = 0
    public static Int32 PCH_CIRCLE = 1
    public static Int32 PCH_SQUARE = 2
    public static Int32 PCH_PIXEL = 3

    # ── 图例位置（R legend 的简化四角 + 右下）──
    public static Int32 LEGEND_TOPRIGHT = 0
    public static Int32 LEGEND_TOPLEFT = 1
    public static Int32 LEGEND_BOTTOMRIGHT = 2
    public static Int32 LEGEND_BOTTOMLEFT = 3

    # ── 绘图类型（R plot(type=...)）──
    public static Int32 PLOT_POINTS = 0
    public static Int32 PLOT_LINES = 1
    public static Int32 PLOT_BOTH = 2
    public static Int32 PLOT_STEPS = 3

    # ── 默认字体（3x5 位图字符宽高）──
    public static Int32 GLYPH_W = 3
    public static Int32 GLYPH_H = 5
    public static Int32 GLYPH_ADVANCE = 4

    # ── 绘图自带三角/对数（不依赖跨模块 Mathf 绑定；角度单位弧度）──
    public static Float32 PI = 3.14159265f

    public static Float32 sin( Float32 x )
    {
        Float32 v = x
        Float32 twoPi = 6.28318531f
        Float32 pi = DrawTypes.PI
        Int32 guard = 0
        while guard < 64
        {
            if v <= pi { if v >= ( 0.0f - pi ) { break } }
            if v > pi { v = v - twoPi }
            else { v = v + twoPi }
            guard = guard + 1
        }
        Float32 v2 = v * v
        Float32 r = v - ( v * v2 / 6.0f )
        r = r + ( v * v2 * v2 / 120.0f )
        r = r - ( v * v2 * v2 * v2 / 5040.0f )
        r = r + ( v * v2 * v2 * v2 * v2 / 362880.0f )
        r = r - ( v * v2 * v2 * v2 * v2 * v2 / 39916800.0f )
        ret r
    }

    public static Float32 cos( Float32 x )
    {
        ret DrawTypes.sin( x + DrawTypes.PI * 0.5f )
    }

    public static Int32 log2Floor( Int32 n )
    {
        Int32 v = n
        Int32 r = 0
        while v > 1
        {
            v = v / 2
            r = r + 1
        }
        ret r
    }

    # ── 颜色构造 ──
    public static Int32 rgb( Int32 r, Int32 g, Int32 b )
    {
        Int32 rr = r
        Int32 gg = g
        Int32 bb = b
        if rr < 0 { rr = 0 }
        if rr > 255 { rr = 255 }
        if gg < 0 { gg = 0 }
        if gg > 255 { gg = 255 }
        if bb < 0 { bb = 0 }
        if bb > 255 { bb = 255 }
        ret ( rr << 16 ) | ( gg << 8 ) | bb
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

    # ── 常用色 ──
    public static Int32 black()
    {
        ret DrawTypes.rgb( 0, 0, 0 )
    }

    public static Int32 white()
    {
        ret DrawTypes.rgb( 255, 255, 255 )
    }

    public static Int32 red()
    {
        ret DrawTypes.rgb( 255, 0, 0 )
    }

    public static Int32 green()
    {
        ret DrawTypes.rgb( 0, 160, 0 )
    }

    public static Int32 blue()
    {
        ret DrawTypes.rgb( 0, 0, 255 )
    }

    public static Int32 gray()
    {
        ret DrawTypes.rgb( 128, 128, 128 )
    }

    public static Int32 lightGray()
    {
        ret DrawTypes.rgb( 220, 220, 220 )
    }

    # ── R 默认调色板 palette()：black/red/green3/blue/cyan/magenta/yellow/gray ──
    public static Int32 palette( Int32 i )
    {
        Int32 k = i % 8
        if k < 0 { k = k + 8 }
        if k == 0 { ret DrawTypes.rgb( 0, 0, 0 ) }
        if k == 1 { ret DrawTypes.rgb( 255, 0, 0 ) }
        if k == 2 { ret DrawTypes.rgb( 0, 205, 0 ) }
        if k == 3 { ret DrawTypes.rgb( 0, 0, 255 ) }
        if k == 4 { ret DrawTypes.rgb( 0, 255, 255 ) }
        if k == 5 { ret DrawTypes.rgb( 255, 0, 255 ) }
        if k == 6 { ret DrawTypes.rgb( 255, 255, 0 ) }
        ret DrawTypes.rgb( 128, 128, 128 )
    }
}
