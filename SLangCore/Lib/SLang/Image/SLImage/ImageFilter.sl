import Std;

# =========================================================================
# Image/ImageFilter.sl —— 3x3 卷积滤镜（仿 Pillow ImageFilter）
#
# 对标 https://www.runoob.com/pillow/pillow-image-module.html 中
# img.filter(ImageFilter.BLUR / CONTOUR) 的用法：
#   Image.ImageFilter.apply( img, Image.EImageFilter.Blur )
#   Image.ImageFilter.apply( img, Image.EImageFilter.Contour )
#
# 命名滤镜的 3x3 核取自 PIL ImageFilter.py 源码（scale = 核元素和时归一化，
# sum = 0 的边缘类核配 offset 提亮显示）；convolve3x3 提供通用核入口
# （≈ ImageFilter.Kernel((3,3), weights, scale, offset)）。
#
# 约定：输出恒 Rgba8；RGB 三通道卷积，alpha 取中心像素原值（不卷积）；
# 边界像素复制（replicate edge）；除法取整用截断；结果 clamp8 到 [0,255]。
# =========================================================================

namespace Image
{
    # 命名滤镜（PIL ImageFilter 同名近似核）
    public enum EImageFilter
    {
        Blur = 0
        Contour = 1
        Detail = 2
        Emboss = 3
        EdgeEnhance = 4
        FindEdges = 5
        Sharpen = 6
        Smooth = 7
    }

    public class ImageFilter
    {
        # ── 命名滤镜入口（img.filter(ImageFilter.X)）────────
        public static ImageBuffer apply( ImageBuffer src, EImageFilter filter )
        {
            if src == null
            {
                ret null
            }
            Array<Int32> k = ImageFilter.kernelOf( filter )
            Int32 scale = ImageFilter.scaleOf( filter )
            Int32 offset = ImageFilter.offsetOf( filter )
            ret ImageFilter.convolve3x3( src, k, scale, offset )
        }

        # ── 通用 3x3 卷积（ImageFilter.Kernel）──────────────
        # kernel 行主序 9 元素（k[0]=左上 ... k[8]=右下）；
        # out = Σ(w*c) / scale + offset，逐通道 clamp8；失败返回 null
        public static ImageBuffer convolve3x3( ImageBuffer src, Array<Int32> kernel, Int32 scale, Int32 offset )
        {
            if src == null || !src.isValid
            {
                ret null
            }
            if kernel == null || kernel.length < 9
            {
                ret null
            }
            if scale <= 0
            {
                ret null
            }
            # C 快路径（sli_op_convolve3x3；失败回落下方 SL 循环）
            if ImageFfi.ensureReady()
            {
                Int64 sp = ImageFfi._uploadRgba( src )
                if sp != 0
                {
                    Int32 dstNeed = src.width * src.height * 4
                    Int64 dp = Memory.alloc( dstNeed )
                    if dp != 0
                    {
                        Int64 ctl = Memory.alloc( 44 )
                        if ctl != 0
                        {
                            Array<Int32> cvals = Array<Int32>( 11 )
                            Int32 ci = 0
                            while ci < 9
                            {
                                cvals[ ci ] = kernel[ ci ]
                                ci = ci + 1
                            }
                            cvals[ 9 ] = scale
                            cvals[ 10 ] = offset
                            bool done = false
                            if ImageFfi._writeCtl( ctl, cvals )
                            {
                                if ImageFfi.libOpConvolve3x3( sp, dp, src.width, src.height, ctl )
                                {
                                    done = true
                                }
                            }
                            if done
                            {
                                ImageBuffer dst = ImageBuffer( src.width, src.height, EPixelFormat.Rgba8 )
                                if ImageFfi._fillBytes( dp, dst.pixelBytes(), dstNeed )
                                {
                                    Memory.free( ctl )
                                    Memory.free( dp )
                                    Memory.free( sp )
                                    ret dst
                                }
                            }
                            Memory.free( ctl )
                        }
                        Memory.free( dp )
                    }
                    Memory.free( sp )
                }
            }
            ImageBuffer dst = ImageBuffer( src.width, src.height, EPixelFormat.Rgba8 )
            Int32 y = 0
            while y < src.height
            {
                Int32 x = 0
                while x < src.width
                {
                    Int32 sr = 0
                    Int32 sg = 0
                    Int32 sb = 0
                    Int32 dy = -1
                    while dy <= 1
                    {
                        Int32 dx = -1
                        while dx <= 1
                        {
                            Int32 nx = x + dx
                            if nx < 0
                            {
                                nx = 0
                            }
                            if nx >= src.width
                            {
                                nx = src.width - 1
                            }
                            Int32 ny = y + dy
                            if ny < 0
                            {
                                ny = 0
                            }
                            if ny >= src.height
                            {
                                ny = src.height - 1
                            }
                            Int32 ki = dy + 1
                            ki = ki * 3 + dx + 1
                            Int32 w = kernel[ ki ]
                            ColorInt c = src.getPixel( nx, ny )
                            sr = sr + w * c.r
                            sg = sg + w * c.g
                            sb = sb + w * c.b
                            dx = dx + 1
                        }
                        dy = dy + 1
                    }
                    Int32 rr = sr / scale + offset
                    Int32 gg = sg / scale + offset
                    Int32 bb = sb / scale + offset
                    dst.setPixel( x, y, ColorInt( ColorInt.clamp8( rr ),
                                                  ColorInt.clamp8( gg ),
                                                  ColorInt.clamp8( bb ),
                                                  src.getPixel( x, y ).a ) )
                    x = x + 1
                }
                y = y + 1
            }
            ret dst
        }

        # ── 滤镜核参数（PIL ImageFilter.py 近似值）────────────
        static Array<Int32> kernelOf( EImageFilter filter )
        {
            if filter == EImageFilter.Blur
            {
                ret ImageFilter._kernel( 1, 2, 1, 2, 4, 2, 1, 2, 1 )
            }
            if filter == EImageFilter.Contour
            {
                ret ImageFilter._kernel( 0, 1, 0, 1, -4, 1, 0, 1, 0 )
            }
            if filter == EImageFilter.Detail
            {
                ret ImageFilter._kernel( 0, -1, 0, -1, 10, -1, 0, -1, 0 )
            }
            if filter == EImageFilter.Emboss
            {
                ret ImageFilter._kernel( -1, 0, 0, 0, 1, 0, 0, 0, 0 )
            }
            if filter == EImageFilter.EdgeEnhance
            {
                ret ImageFilter._kernel( -1, -1, -1, -1, 9, -1, -1, -1, -1 )
            }
            if filter == EImageFilter.FindEdges
            {
                ret ImageFilter._kernel( -1, -1, -1, -1, 8, -1, -1, -1, -1 )
            }
            if filter == EImageFilter.Sharpen
            {
                ret ImageFilter._kernel( -2, -2, -2, -2, 32, -2, -2, -2, -2 )
            }
            # Smooth
            ret ImageFilter._kernel( 1, 1, 1, 1, 5, 1, 1, 1, 1 )
        }

        static Int32 scaleOf( EImageFilter filter )
        {
            if filter == EImageFilter.Blur
            {
                ret 16
            }
            if filter == EImageFilter.Detail
            {
                ret 6
            }
            if filter == EImageFilter.Sharpen
            {
                ret 16
            }
            if filter == EImageFilter.Smooth
            {
                ret 13
            }
            ret 1
        }

        static Int32 offsetOf( EImageFilter filter )
        {
            if filter == EImageFilter.Contour
            {
                ret 255
            }
            if filter == EImageFilter.Emboss
            {
                ret 128
            }
            ret 0
        }

        static Array<Int32> _kernel( Int32 k00, Int32 k01, Int32 k02,
                                     Int32 k10, Int32 k11, Int32 k12,
                                     Int32 k20, Int32 k21, Int32 k22 )
        {
            Array<Int32> k = Array<Int32>( 9 )
            k[ 0 ] = k00
            k[ 1 ] = k01
            k[ 2 ] = k02
            k[ 3 ] = k10
            k[ 4 ] = k11
            k[ 5 ] = k12
            k[ 6 ] = k20
            k[ 7 ] = k21
            k[ 8 ] = k22
            ret k
        }

        override string toString()
        {
            ret "ImageFilter"
        }
    }
}
