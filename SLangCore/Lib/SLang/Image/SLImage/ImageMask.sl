import Std;

# =========================================================================
# Image/ImageMask.sl —— 蒙版生成与蒙版合成（仿 Pillow advanced 蒙版技术）
#
# 对标 https://www.runoob.com/pillow/pillow-advanced.html「蒙版应用与高级合成」：
#   create_gradient_mask(size, direction, start, end)
#       -> Image.ImageMask.gradientMask( w, h, EMaskDirection.X, start, end )
#   create_circular_mask(image, radius) -> ImageMask.circularMask( w, h, radius )
#   create_pattern_mask(size, type, scale) -> ImageMask.patternMask( w, h, EMaskPattern.X, scale )
#   apply_mask_blend(im1, im2, mask)     -> ImageMask.applyMaskBlend( a, b, mask )
#   transition_blend(im1, im2, direction)-> ImageMask.transitionBlend( a, b, dir )
#   checkerboard_blend(im1, im2, grid)   -> ImageMask.checkerboardBlend( a, b, grid )
#   paste(im, box, mask)                -> ImageBuffer.pasteMasked( src, x, y, mask )
#
# 蒙版 = Gray8 图（值 0..255 作混合因子）；合成重循环走 C 层
# sli_op_mask_blend；蒙版生成为公式驱动的 SL 直写字节循环。
# =========================================================================

namespace Image
{
    # 渐变方向（教程 direction 参数）
    public enum EMaskDirection
    {
        Horizontal = 0
        Vertical = 1
        Radial = 2
        Diagonal = 3
    }

    # 图案类型（教程 pattern_type 参数）
    public enum EMaskPattern
    {
        Grid = 0
        Dots = 1
        Stripes = 2
        Waves = 3
    }

    public class ImageMask
    {
        # ── 平方根（牛顿迭代；蒙版公式用，24 轮足够掩码精度。
        #    ImageDraw 椭圆跨度复用，故 public）──
        public static Float32 _sqrt( Float32 v )
        {
            if v <= 0.0f
            {
                ret 0.0f
            }
            Float32 x = v
            if x < 1.0f
            {
                x = 1.0f
            }
            Int32 i = 0
            while i < 24
            {
                x = 0.5f * ( x + v / x )
                i = i + 1
            }
            ret x
        }

        static Float32 _dist( Int32 dx, Int32 dy )
        {
            Float32 fx = 1.0f * dx
            Float32 fy = 1.0f * dy
            ret ImageMask._sqrt( fx * fx + fy * fy )
        }

        # ── 蒙版生成（全部 Gray8，直写字节）──────────────────

        # 线性/径向/对角渐变：value = start + (end-start)*t，t 随方向 0..1
        public static ImageBuffer gradientMask( Int32 w, Int32 h, EMaskDirection direction, Int32 start, Int32 end )
        {
            if w <= 0 || h <= 0
            {
                ret null
            }
            ImageBuffer m = ImageBuffer( w, h, EPixelFormat.Gray8 )
            Array<UInt8> px = m.pixelBytes()
            Float32 cx = 0.5f * ( w - 1 )
            Float32 cy = 0.5f * ( h - 1 )
            Float32 maxD = 1.0f
            if direction == EMaskDirection.Radial
            {
                maxD = ImageMask._dist( w / 2, h / 2 )
                if maxD < 1.0f
                {
                    maxD = 1.0f
                }
            }
            Float32 fs = 1.0f * start
            Float32 fe = 1.0f * end
            Int32 y = 0
            while y < h
            {
                Int32 x = 0
                while x < w
                {
                    Float32 t = 0.0f
                    if direction == EMaskDirection.Horizontal
                    {
                        t = 1.0f * x / w
                    }
                    elif direction == EMaskDirection.Vertical
                    {
                        t = 1.0f * y / h
                    }
                    elif direction == EMaskDirection.Radial
                    {
                        t = ImageMask._dist( x - SystemConvertInt32( cx ), y - SystemConvertInt32( cy ) ) / maxD
                    }
                    else
                    {
                        t = 1.0f * ( x + y ) / ( w + h )
                    }
                    Int32 v = SystemConvertInt32( fs + ( fe - fs ) * t )
                    px[ y * w + x ] = SystemConvertUInt8( ColorInt.clamp8( v ) )
                    x = x + 1
                }
                y = y + 1
            }
            ret m
        }

        # 圆形蒙版：圆内 255 圆外 0（radius<=0 时取 min(cx, cy)）
        public static ImageBuffer circularMask( Int32 w, Int32 h, Int32 radius )
        {
            if w <= 0 || h <= 0
            {
                ret null
            }
            Int32 cx = w / 2
            Int32 cy = h / 2
            Int32 r = radius
            if r <= 0
            {
                r = cx
                if cy < r
                {
                    r = cy
                }
            }
            ImageBuffer m = ImageBuffer( w, h, EPixelFormat.Gray8 )
            Array<UInt8> px = m.pixelBytes()
            Int32 y = 0
            while y < h
            {
                Int32 x = 0
                while x < w
                {
                    Int32 v = 0
                    if ImageMask._dist( x - cx, y - cy ) <= 1.0f * r
                    {
                        v = 255
                    }
                    px[ y * w + x ] = SystemConvertUInt8( v )
                    x = x + 1
                }
                y = y + 1
            }
            ret m
        }

        # 图案蒙版（Grid 网格 / Dots 点阵 / Stripes 条纹 / Waves 波浪）
        public static ImageBuffer patternMask( Int32 w, Int32 h, EMaskPattern pattern, Int32 scale )
        {
            if w <= 0 || h <= 0 || scale <= 0
            {
                ret null
            }
            ImageBuffer m = ImageBuffer( w, h, EPixelFormat.Gray8 )
            Array<UInt8> px = m.pixelBytes()
            Int32 hlf = scale / 2
            Int32 y = 0
            while y < h
            {
                Int32 x = 0
                while x < w
                {
                    Int32 v = 0
                    if pattern == EMaskPattern.Grid
                    {
                        if x % scale < hlf || y % scale < hlf
                        {
                            v = 255
                        }
                    }
                    elif pattern == EMaskPattern.Dots
                    {
                        Int32 cxx = x % scale - hlf
                        Int32 cyy = y % scale - hlf
                        if ImageMask._dist( cxx, cyy ) < 1.0f * ( scale / 4 )
                        {
                            v = 255
                        }
                    }
                    elif pattern == EMaskPattern.Stripes
                    {
                        if ( x + y ) % scale < hlf
                        {
                            v = 255
                        }
                    }
                    else
                    {
                        # Waves：127.5 + 127.5*sin(x/scale)*cos(y/scale)
                        Float32 sx = 1.0f * x / scale
                        Float32 sy = 1.0f * y / scale
                        Float32 sv = Image.ImageBuffer._sin( sx )
                        Float32 cv = Image.ImageBuffer._cos( sy )
                        Int32 iv = SystemConvertInt32( 127.5f + 127.5f * sv * cv )
                        v = ColorInt.clamp8( iv )
                    }
                    px[ y * w + x ] = SystemConvertUInt8( v )
                    x = x + 1
                }
                y = y + 1
            }
            ret m
        }

        # 棋盘格蒙版（(x/grid + y/grid) 奇偶交替）
        public static ImageBuffer checkerboardMask( Int32 w, Int32 h, Int32 grid )
        {
            if w <= 0 || h <= 0 || grid <= 0
            {
                ret null
            }
            ImageBuffer m = ImageBuffer( w, h, EPixelFormat.Gray8 )
            Array<UInt8> px = m.pixelBytes()
            Int32 y = 0
            while y < h
            {
                Int32 x = 0
                while x < w
                {
                    Int32 v = 0
                    if ( ( x / grid + y / grid ) % 2 ) == 0
                    {
                        v = 255
                    }
                    px[ y * w + x ] = SystemConvertUInt8( v )
                    x = x + 1
                }
                y = y + 1
            }
            ret m
        }

        # ── 蒙版合成 ────────────────────────────────────────

        # apply_mask_blend：out = a*(1-m/255) + b*(m/255)（4 通道；
        # mask 取 Gray8 平面字节 / 其它格式经红通道）；C 快路径 + SL 兜底
        public static ImageBuffer applyMaskBlend( ImageBuffer a, ImageBuffer b, ImageBuffer mask )
        {
            if a == null || b == null || mask == null
            {
                ret null
            }
            if !a.isValid || !b.isValid || !mask.isValid
            {
                ret null
            }
            if a.width != b.width || a.height != b.height
            {
                ret null
            }
            if mask.width != a.width || mask.height != a.height
            {
                ret null
            }
            # C 快路径（sli_op_mask_blend；VM 封送 bug 期间由开关关停——坑 9；
            # mask 须 Gray8 直读平面）
            if mask.pixelFormat == EPixelFormat.Gray8 && ImageFfi.opFastPathsEnabled && ImageFfi.ensureReady()
            {
                Int64 aptr = ImageFfi._uploadRgba( a )
                if aptr != 0
                {
                    Int64 bptr = ImageFfi._uploadRgba( b )
                    if bptr != 0
                    {
                        Int32 need = a.width * a.height * 4
                        Int32 maskNeed = a.width * a.height
                        Int64 mptr = ImageFfi._copyIn( mask.pixelBytes(), maskNeed )
                        if mptr != 0
                        {
                            Int64 outp = Memory.alloc( need )
                            if outp != 0
                            {
                                bool done = false
                                Int64 ctl = Memory.alloc( 8 )
                                if ctl != 0
                                {
                                    Array<Int32> cvals = Array<Int32>( 2 )
                                    cvals[ 0 ] = a.width
                                    cvals[ 1 ] = a.height
                                    if ImageFfi._writeCtl( ctl, cvals )
                                    {
                                        if ImageFfi.libOpMaskBlend( aptr, bptr, mptr, outp, ctl )
                                        {
                                            done = true
                                        }
                                    }
                                    Memory.free( ctl )
                                }
                                if done
                                {
                                    ImageBuffer result = ImageBuffer( a.width, a.height, EPixelFormat.Rgba8 )
                                    if ImageFfi._fillBytes( outp, result._data, need )
                                    {
                                        Memory.free( outp )
                                        Memory.free( mptr )
                                        Memory.free( bptr )
                                        Memory.free( aptr )
                                        ret result
                                    }
                                }
                                Memory.free( outp )
                            }
                            Memory.free( mptr )
                        }
                        Memory.free( bptr )
                    }
                    Memory.free( aptr )
                }
            }
            # SL 兜底（整数直算与 C 一致）
            ImageBuffer result = ImageBuffer( a.width, a.height, EPixelFormat.Rgba8 )
            Int32 y = 0
            while y < a.height
            {
                Int32 x = 0
                while x < a.width
                {
                    Int32 mv = mask.getPixel( x, y ).r
                    ColorInt ca = a.getPixel( x, y )
                    ColorInt cb = b.getPixel( x, y )
                    Int32 rr = ColorInt.clamp8( ca.r + ( cb.r - ca.r ) * mv / 255 )
                    Int32 gg = ColorInt.clamp8( ca.g + ( cb.g - ca.g ) * mv / 255 )
                    Int32 bb = ColorInt.clamp8( ca.b + ( cb.b - ca.b ) * mv / 255 )
                    Int32 aa = ColorInt.clamp8( ca.a + ( cb.a - ca.a ) * mv / 255 )
                    result.setPixel( x, y, ColorInt( rr, gg, bb, aa ) )
                    x = x + 1
                }
                y = y + 1
            }
            ret result
        }

        # ── 组合捷径（教程 transition_blend / checkerboard_blend）──

        # 过渡混合：a -> b 沿方向渐变（gradientMask 0..255 后蒙版混合）
        public static ImageBuffer transitionBlend( ImageBuffer a, ImageBuffer b, EMaskDirection direction )
        {
            if a == null || b == null || !a.isValid || !b.isValid
            {
                ret null
            }
            ImageBuffer mask = ImageMask.gradientMask( a.width, a.height, direction, 0, 255 )
            if mask == null
            {
                ret null
            }
            ret ImageMask.applyMaskBlend( a, b, mask )
        }

        # 棋盘格混合：(x/grid + y/grid) 偶取 a 奇取 b
        public static ImageBuffer checkerboardBlend( ImageBuffer a, ImageBuffer b, Int32 grid )
        {
            if a == null || b == null || !a.isValid || !b.isValid
            {
                ret null
            }
            ImageBuffer mask = ImageMask.checkerboardMask( a.width, a.height, grid )
            if mask == null
            {
                ret null
            }
            ret ImageMask.applyMaskBlend( a, b, mask )
        }

        override string toString()
        {
            ret "ImageMask"
        }
    }
}
