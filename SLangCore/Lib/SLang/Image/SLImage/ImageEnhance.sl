import Std;

# =========================================================================
# Image/ImageEnhance.sl —— 图像增强（仿 Pillow ImageEnhance）
#
# 对标 https://www.runoob.com/pillow/pillow-advanced.html「图像增强」段：
#   ImageEnhance.Brightness(img).enhance(f) -> Image.ImageEnhance.brightness( img, f )
#   ImageEnhance.Contrast(img).enhance(f)   -> Image.ImageEnhance.contrast( img, f )
#   ImageEnhance.Color(img).enhance(f)      -> Image.ImageEnhance.color( img, f )
#   ImageEnhance.Sharpness(img).enhance(f)  -> Image.ImageEnhance.sharpness( img, f )
#
# PIL 语义：四者同构 —— result = degenerate*(1-f) + image*f（线性外插，
# f=1 原图 / f=0 退化图 / f>1 增强 / 0<f<1 减弱）：
#   Brightness  degenerate = 纯黑
#   Contrast   degenerate = 纯灰（原图 BT.601 灰度均值）
#   Color      degenerate = 灰度化的原图
#   Sharpness  degenerate = 原图 Blur（PIL 用高斯，此处 3x3 近似）
# 外插用 sli_op_blend_factor（不钳 factor）；重循环全走 C 快路径。
# =========================================================================

namespace Image
{
    public class ImageEnhance
    {
        # ── 线性外插混合（不钳 factor；ImageBuffer.blend 钳 0..1 故独立）──
        static ImageBuffer _blendFactor( ImageBuffer degenerate, ImageBuffer img, Float32 factor )
        {
            # C 快路径（sli_op_blend_factor；VM 封送 bug 期间由开关关停——坑 9）
            if ImageFfi.opFastPathsEnabled && ImageFfi.ensureReady()
            {
                Int64 ap = ImageFfi._uploadRgba( degenerate )
                if ap != 0
                {
                    Int64 bp = ImageFfi._uploadRgba( img )
                    if bp != 0
                    {
                        Int32 need = img.width * img.height * 4
                        Int64 outp = Memory.alloc( need )
                        if outp != 0
                        {
                            if ImageFfi.libOpBlendFactor( ap, bp, outp, img.width, img.height, SystemConvertInt32( factor * 1000.0f ) )
                            {
                                ImageBuffer result = ImageBuffer( img.width, img.height, EPixelFormat.Rgba8 )
                                if ImageFfi._fillBytes( outp, result._data, need )
                                {
                                    Memory.free( outp )
                                    Memory.free( bp )
                                    Memory.free( ap )
                                    ret result
                                }
                            }
                            Memory.free( outp )
                        }
                        Memory.free( bp )
                    }
                    Memory.free( ap )
                }
            }
            # SL 兜底（同式浮点直算）
            ImageBuffer result = ImageBuffer( img.width, img.height, EPixelFormat.Rgba8 )
            Int32 y = 0
            while y < img.height
            {
                Int32 x = 0
                while x < img.width
                {
                    ColorInt ca = degenerate.getPixel( x, y )
                    ColorInt cb = img.getPixel( x, y )
                    Int32 rr = ColorInt.toInt( 1.0f * ca.r * ( 1.0f - factor ) + 1.0f * cb.r * factor )
                    Int32 gg = ColorInt.toInt( 1.0f * ca.g * ( 1.0f - factor ) + 1.0f * cb.g * factor )
                    Int32 bb = ColorInt.toInt( 1.0f * ca.b * ( 1.0f - factor ) + 1.0f * cb.b * factor )
                    Int32 aa = ColorInt.toInt( 1.0f * ca.a * ( 1.0f - factor ) + 1.0f * cb.a * factor )
                    result.setPixel( x, y, ColorInt( rr, gg, bb, aa ) )
                    x = x + 1
                }
                y = y + 1
            }
            ret result
        }

        # ── 灰度化（BT.601 写回 RGB，alpha 保留；Color 的 degenerate）──
        public static ImageBuffer grayscale( ImageBuffer img )
        {
            if img == null || !img.isValid
            {
                ret null
            }
            # C 快路径（sli_op_grayscale）
            if ImageFfi.ensureReady()
            {
                Int64 sp = ImageFfi._uploadRgba( img )
                if sp != 0
                {
                    Int32 need = img.width * img.height * 4
                    Int64 dp = Memory.alloc( need )
                    if dp != 0
                    {
                        if ImageFfi.libOpGrayscale( sp, dp, img.width, img.height )
                        {
                            ImageBuffer result = ImageBuffer( img.width, img.height, EPixelFormat.Rgba8 )
                            result.colorSpace = img.colorSpace
                            if ImageFfi._fillBytes( dp, result._data, need )
                            {
                                Memory.free( dp )
                                Memory.free( sp )
                                ret result
                            }
                        }
                        Memory.free( dp )
                    }
                    Memory.free( sp )
                }
            }
            # SL 兜底
            ImageBuffer result = ImageBuffer( img.width, img.height, EPixelFormat.Rgba8 )
            result.colorSpace = img.colorSpace
            Int32 y = 0
            while y < img.height
            {
                Int32 x = 0
                while x < img.width
                {
                    ColorInt g = img.getPixel( x, y ).grayscale()
                    result.setPixel( x, y, g )
                    x = x + 1
                }
                y = y + 1
            }
            ret result
        }

        # ── 四个增强器（PIL ImageEnhance 同名）──────────────
        # 亮度：f>1 提亮 / f<1 压暗（像素线性缩放）
        public static ImageBuffer brightness( ImageBuffer img, Float32 factor )
        {
            if img == null || !img.isValid
            {
                ret null
            }
            ImageBuffer black = ImageBuffer.newImage( img.width, img.height, ColorInt.black() )
            ret ImageEnhance._blendFactor( black, img, factor )
        }

        # 对比度：围绕灰度均值放大/缩小（f=0 得均匀灰图）
        public static ImageBuffer contrast( ImageBuffer img, Float32 factor )
        {
            if img == null || !img.isValid
            {
                ret null
            }
            # BT.601 灰度均值（C 快路径 + SL 兜底）
            Int32 mean = 0
            bool got = false
            if ImageFfi.ensureReady()
            {
                Int64 sp = ImageFfi._uploadRgba( img )
                if sp != 0
                {
                    Int32 m = ImageFfi.libOpLumaMean( sp, img.width, img.height )
                    if m >= 0
                    {
                        mean = m
                        got = true
                    }
                    Memory.free( sp )
                }
            }
            if !got
            {
                Int64 sum = 0
                Int32 n = img.width * img.height
                Int32 y = 0
                while y < img.height
                {
                    Int32 x = 0
                    while x < img.width
                    {
                        ColorInt c = img.getPixel( x, y )
                        sum = sum + ( 299 * c.r + 587 * c.g + 114 * c.b + 500 ) / 1000
                        x = x + 1
                    }
                    y = y + 1
                }
                mean = SystemConvertInt32( ( sum + n / 2 ) / n )
            }
            ImageBuffer gray = ImageBuffer.newImage( img.width, img.height, ColorInt( mean, mean, mean, 255 ) )
            ret ImageEnhance._blendFactor( gray, img, factor )
        }

        # 饱和度：f=0 灰度图 / f>1 增艳
        public static ImageBuffer color( ImageBuffer img, Float32 factor )
        {
            if img == null || !img.isValid
            {
                ret null
            }
            ImageBuffer gray = ImageEnhance.grayscale( img )
            if gray == null
            {
                ret null
            }
            ret ImageEnhance._blendFactor( gray, img, factor )
        }

        # 锐度：f=0 模糊 / f>1 锐化（degenerate = Blur 近似 PIL 高斯）
        public static ImageBuffer sharpness( ImageBuffer img, Float32 factor )
        {
            if img == null || !img.isValid
            {
                ret null
            }
            ImageBuffer blur = ImageFilter.apply( img, EImageFilter.Blur )
            if blur == null
            {
                ret null
            }
            ret ImageEnhance._blendFactor( blur, img, factor )
        }

        override string toString()
        {
            ret "ImageEnhance"
        }
    }
}
