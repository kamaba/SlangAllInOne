import Std;

# =========================================================================
# Image/ImageChops.sl —— 通道运算（仿 Pillow ImageChops + 混合模式）
#
# 对标 https://www.runoob.com/pillow/pillow-advanced.html「混合模式」段：
#   ImageChops.add        -> Image.ImageChops.add( im1, im2 )
#   ImageChops.subtract   -> Image.ImageChops.subtract( im1, im2 )
#   ImageChops.multiply   -> Image.ImageChops.multiply( im1, im2 )
#   ImageChops.screen     -> Image.ImageChops.screen( im1, im2 )
#   ImageChops.difference -> Image.ImageChops.difference( im1, im2 )
#   ImageChops.invert     -> Image.ImageChops.invert( im )
#   ImageChops.lighter    -> Image.ImageChops.lighter( im1, im2 )
#   ImageChops.darker     -> Image.ImageChops.darker( im1, im2 )
#   教程 custom_blend 的 soft_light / hard_light / overlay 也在本类
#
# 约定：两图同尺寸；输出恒 Rgba8；运算作用于全部 4 通道（RGBA 同步，
# 与 PIL 一致）；整数公式（除法截断 + clamp8）与 C 层 sli_op_chops
# 逐位对齐（op 0..10），C 失败自动回落 SL 循环。
# =========================================================================

namespace Image
{
    public class ImageChops
    {
        # ── 二元运算分派（op 0..10 对齐 C 层）─────────────────
        static Int32 _chopChannel( Int32 op, Int32 a, Int32 b )
        {
            if op == 0
            {
                ret ColorInt.clamp8( a + b )
            }
            if op == 1
            {
                Int32 d = a - b
                if d < 0
                {
                    ret 0
                }
                ret d
            }
            if op == 2
            {
                ret a * b / 255
            }
            if op == 3
            {
                ret 255 - ( 255 - a ) * ( 255 - b ) / 255
            }
            if op == 4
            {
                Int32 d = a - b
                if d < 0
                {
                    d = 0 - d
                }
                ret d
            }
            if op == 5
            {
                if a > b
                {
                    ret a
                }
                ret b
            }
            if op == 6
            {
                if a < b
                {
                    ret a
                }
                ret b
            }
            if op == 7
            {
                ret 255 - a
            }
            if op == 8
            {
                ret ( a * ( 255 - b ) + b * b / 255 ) / 255
            }
            if op == 9
            {
                if b < 128
                {
                    ret 2 * a * b / 255
                }
                ret 255 - 2 * ( 255 - a ) * ( 255 - b ) / 255
            }
            # op == 10（overlay）
            if a < 128
            {
                ret 2 * a * b / 255
            }
            ret 255 - 2 * ( 255 - a ) * ( 255 - b ) / 255
        }

        # 二元通用：C 快路径（sli_op_chops）+ SL 兜底循环
        static ImageBuffer _binary( Int32 op, ImageBuffer im1, ImageBuffer im2 )
        {
            if im1 == null || im2 == null || !im1.isValid || !im2.isValid
            {
                ret null
            }
            if im1.width != im2.width || im1.height != im2.height
            {
                ret null
            }
            # C 快路径
            if ImageFfi.ensureReady()
            {
                Int64 ap = ImageFfi._uploadRgba( im1 )
                if ap != 0
                {
                    Int64 bp = ImageFfi._uploadRgba( im2 )
                    if bp != 0
                    {
                        Int32 need = im1.width * im1.height * 4
                        Int64 outp = Memory.alloc( need )
                        if outp != 0
                        {
                            if ImageFfi.libOpChops( op, ap, bp, outp, im1.width, im1.height )
                            {
                                ImageBuffer result = ImageBuffer( im1.width, im1.height, EPixelFormat.Rgba8 )
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
            # SL 兜底
            ImageBuffer result = ImageBuffer( im1.width, im1.height, EPixelFormat.Rgba8 )
            Int32 y = 0
            while y < im1.height
            {
                Int32 x = 0
                while x < im1.width
                {
                    ColorInt c1 = im1.getPixel( x, y )
                    ColorInt c2 = im2.getPixel( x, y )
                    result.setPixel( x, y, ColorInt( ImageChops._chopChannel( op, c1.r, c2.r ),
                                                     ImageChops._chopChannel( op, c1.g, c2.g ),
                                                     ImageChops._chopChannel( op, c1.b, c2.b ),
                                                     ImageChops._chopChannel( op, c1.a, c2.a ) ) )
                    x = x + 1
                }
                y = y + 1
            }
            ret result
        }

        # ── PIL ImageChops 同名 API ─────────────────────────
        # 加（饱和加法）
        public static ImageBuffer add( ImageBuffer im1, ImageBuffer im2 )
        {
            ret ImageChops._binary( 0, im1, im2 )
        }

        # 减（钳 0）
        public static ImageBuffer subtract( ImageBuffer im1, ImageBuffer im2 )
        {
            ret ImageChops._binary( 1, im1, im2 )
        }

        # 正片叠底
        public static ImageBuffer multiply( ImageBuffer im1, ImageBuffer im2 )
        {
            ret ImageChops._binary( 2, im1, im2 )
        }

        # 滤色
        public static ImageBuffer screen( ImageBuffer im1, ImageBuffer im2 )
        {
            ret ImageChops._binary( 3, im1, im2 )
        }

        # 差值（绝对差）
        public static ImageBuffer difference( ImageBuffer im1, ImageBuffer im2 )
        {
            ret ImageChops._binary( 4, im1, im2 )
        }

        # 逐通道取亮
        public static ImageBuffer lighter( ImageBuffer im1, ImageBuffer im2 )
        {
            ret ImageChops._binary( 5, im1, im2 )
        }

        # 逐通道取暗
        public static ImageBuffer darker( ImageBuffer im1, ImageBuffer im2 )
        {
            ret ImageChops._binary( 6, im1, im2 )
        }

        # ── 教程 custom_blend 的混合模式（page 公式）─────────
        # 柔光：(a*(255-b) + b*b/255) / 255
        public static ImageBuffer softLight( ImageBuffer im1, ImageBuffer im2 )
        {
            ret ImageChops._binary( 8, im1, im2 )
        }

        # 强光：b<128 ? 2ab/255 : 255-2(255-a)(255-b)/255
        public static ImageBuffer hardLight( ImageBuffer im1, ImageBuffer im2 )
        {
            ret ImageChops._binary( 9, im1, im2 )
        }

        # 叠加：a<128 ? 2ab/255 : 255-2(255-a)(255-b)/255
        public static ImageBuffer overlay( ImageBuffer im1, ImageBuffer im2 )
        {
            ret ImageChops._binary( 10, im1, im2 )
        }

        # ── 反相（一元，PIL ImageChops.invert / 教程 ImageOps.invert）──
        public static ImageBuffer invert( ImageBuffer im )
        {
            if im == null || !im.isValid
            {
                ret null
            }
            # C 快路径（sli_op_chops op=7，b 实参传自身占位）
            if ImageFfi.ensureReady()
            {
                Int64 ap = ImageFfi._uploadRgba( im )
                if ap != 0
                {
                    Int32 need = im.width * im.height * 4
                    Int64 outp = Memory.alloc( need )
                    if outp != 0
                    {
                        if ImageFfi.libOpChops( 7, ap, ap, outp, im.width, im.height )
                        {
                            ImageBuffer result = ImageBuffer( im.width, im.height, EPixelFormat.Rgba8 )
                            if ImageFfi._fillBytes( outp, result._data, need )
                            {
                                Memory.free( outp )
                                Memory.free( ap )
                                ret result
                            }
                        }
                        Memory.free( outp )
                    }
                    Memory.free( ap )
                }
            }
            # SL 兜底
            ImageBuffer result = ImageBuffer( im.width, im.height, EPixelFormat.Rgba8 )
            Int32 y = 0
            while y < im.height
            {
                Int32 x = 0
                while x < im.width
                {
                    ColorInt c = im.getPixel( x, y )
                    result.setPixel( x, y, ColorInt( 255 - c.r, 255 - c.g, 255 - c.b, 255 - c.a ) )
                    x = x + 1
                }
                y = y + 1
            }
            ret result
        }

        override string toString()
        {
            ret "ImageChops"
        }
    }
}
