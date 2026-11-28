import Std;

# =========================================================================
# Image/ImageBuffer.sl —— CPU 侧像素缓冲（本目录的核心）
#
# 数据布局：**紧密排布、无行对齐填充**，stride = width * bytesPerPixel。
# 这样 (x,y) 的偏移就是 (y * width + x) * bpp，纯 SL 可以高效寻址。
#
# 纯 SL 实现：读写像素 / 填充 / 裁剪 / 翻转 / 最近邻与双线性缩放 /
#             像素格式互转 / 预乘 alpha / 任意角旋转 / 贴入 / 通道拆合 /
#             alpha 合成与线性混合（仿 Pillow Image 模块方法集）。
# 依赖后端：  decode() / encode()（PNG、JPEG、WebP 的熵编解码）。
#
# 数值转换统一走 SystemConvertInt32 / SystemConvertUInt8（Core 已实现），
# 不使用隐式截断，避免不同后端行为不一致。
#
# 像素颜色类 ColorInt（8bit RGBA，Int32 存储 0..255）迁至 Std 根级
# （Std/ColorInt.sl），本模块经 references 引用 Std。
# =========================================================================

namespace Image
{
    public class ImageBuffer
    {
        public Int32 width = 0
        public Int32 height = 0
        public EPixelFormat pixelFormat = EPixelFormat.Rgba8
        public EColorSpace colorSpace = EColorSpace.SRGB

        # 像素数据，长度 = width * height * bytesPerPixel
        Array<UInt8> _data = null

        _init_()
        {
            this.width = 0
            this.height = 0
            this.pixelFormat = EPixelFormat.Rgba8
            this.colorSpace = EColorSpace.SRGB
            this._data = Array<UInt8>( 0 )
        }

        _init_( Int32 _width, Int32 _height )
        {
            this.width = _width
            this.height = _height
            this.pixelFormat = EPixelFormat.Rgba8
            this.colorSpace = EColorSpace.SRGB
            this._data = Array<UInt8>( _width * _height * 4 )
        }

        _init_( Int32 _width, Int32 _height, EPixelFormat _fmt )
        {
            this.width = _width
            this.height = _height
            this.pixelFormat = _fmt
            this.colorSpace = EColorSpace.SRGB
            this._data = Array<UInt8>( _width * _height * ImageBuffer.bytesPerPixelOf( _fmt ) )
        }

        # ── 静态：每种像素格式占几个字节 ─────────────────────
        public static Int32 bytesPerPixelOf( EPixelFormat fmt )
        {
            if fmt == EPixelFormat.Gray8
            {
                ret 1
            }
            if fmt == EPixelFormat.Gray16
            {
                ret 2
            }
            if fmt == EPixelFormat.Rgb8
            {
                ret 3
            }
            if fmt == EPixelFormat.Rgba8
            {
                ret 4
            }
            if fmt == EPixelFormat.Bgr8
            {
                ret 3
            }
            if fmt == EPixelFormat.Bgra8
            {
                ret 4
            }
            if fmt == EPixelFormat.Rgb16
            {
                ret 6
            }
            if fmt == EPixelFormat.Rgba16
            {
                ret 8
            }
            if fmt == EPixelFormat.Rgb32F
            {
                ret 12
            }
            if fmt == EPixelFormat.Rgba32F
            {
                ret 16
            }
            ret 0
        }

        public static Int32 channelCountOf( EPixelFormat fmt )
        {
            if fmt == EPixelFormat.Gray8 || fmt == EPixelFormat.Gray16
            {
                ret 1
            }
            if fmt == EPixelFormat.Rgb8 || fmt == EPixelFormat.Bgr8
            {
                ret 3
            }
            if fmt == EPixelFormat.Rgb16
            {
                ret 3
            }
            if fmt == EPixelFormat.Rgb32F
            {
                ret 3
            }
            if fmt == EPixelFormat.Rgba8 || fmt == EPixelFormat.Bgra8
            {
                ret 4
            }
            if fmt == EPixelFormat.Rgba16
            {
                ret 4
            }
            if fmt == EPixelFormat.Rgba32F
            {
                ret 4
            }
            ret 0
        }

        # ── 属性 ─────────────────────────────────────────────
        public get Int32 bytesPerPixel()
        {
            ret ImageBuffer.bytesPerPixelOf( this.pixelFormat )
        }

        public get Int32 channelCount()
        {
            ret ImageBuffer.channelCountOf( this.pixelFormat )
        }

        public get Int32 stride()
        {
            ret this.width * this.bytesPerPixel()
        }

        public get Int32 pixelCount()
        {
            ret this.width * this.height
        }

        public get Int32 byteLength()
        {
            ret this._data.length
        }

        public get bool isValid()
        {
            if this.width <= 0
            {
                ret false
            }
            if this.height <= 0
            {
                ret false
            }
            if this.bytesPerPixel() <= 0
            {
                ret false
            }
            Int32 need = this.width * this.height
            need = need * this.bytesPerPixel()
            if this._data.length >= need
            {
                ret true
            }
            ret false
        }

        public get bool hasAlpha()
        {
            ret this.channelCount() == 4
        }

        public Array<UInt8> pixelBytes()
        {
            ret this._data
        }

        # ── 内部：字节读写（显式转换，避免隐式截断歧义）──────
        Int32 byteAt( Int32 index )
        {
            ret SystemConvertInt32( this._data[ index ] )
        }

        void setByteAt( Int32 index, Int32 value )
        {
            this._data[ index ] = SystemConvertUInt8( value )
        }

        Int32 offsetOf( Int32 x, Int32 y )
        {
            ret ( y * this.width + x ) * this.bytesPerPixel()
        }

        public bool inBounds( Int32 x, Int32 y )
        {
            ret x >= 0 && y >= 0 && x < this.width && y < this.height
        }

        # ── 像素读写 ─────────────────────────────────────────
        public ColorInt getPixel( Int32 x, Int32 y )
        {
            if !this.inBounds( x, y )
            {
                ret ColorInt.transparent()
            }
            Int32 o = this.offsetOf( x, y )

            if this.pixelFormat == EPixelFormat.Gray8
            {
                Int32 v = this.byteAt( o )
                ret ColorInt(v, v, v, 255 )
            }
            if this.pixelFormat == EPixelFormat.Gray16
            {
                # 取高字节近似为 8 位
                Int32 v = this.byteAt( o + 1 )
                ret ColorInt(v, v, v, 255 )
            }
            if this.pixelFormat == EPixelFormat.Rgb8
            {
                ret ColorInt(this.byteAt( o ), this.byteAt( o + 1 ), this.byteAt( o + 2 ), 255 )
            }
            if this.pixelFormat == EPixelFormat.Rgba8
            {
                ret ColorInt(this.byteAt( o ), this.byteAt( o + 1 ),
                           this.byteAt( o + 2 ), this.byteAt( o + 3 ) )
            }
            if this.pixelFormat == EPixelFormat.Bgr8
            {
                ret ColorInt(this.byteAt( o + 2 ), this.byteAt( o + 1 ), this.byteAt( o ), 255 )
            }
            if this.pixelFormat == EPixelFormat.Bgra8
            {
                ret ColorInt(this.byteAt( o + 2 ), this.byteAt( o + 1 ),
                           this.byteAt( o ), this.byteAt( o + 3 ) )
            }
            if this.pixelFormat == EPixelFormat.Rgb16 ||
               this.pixelFormat == EPixelFormat.Rgba16
            {
                # 每通道 2 字节，取高字节
                ret ColorInt(this.byteAt( o + 1 ), this.byteAt( o + 3 ),
                           this.byteAt( o + 5 ), 255 )
            }
            ret ColorInt.transparent()
        }

        public void setPixel( Int32 x, Int32 y, ColorInt c )
        {
            if !this.inBounds( x, y ) || c == null
            {
                ret
            }
            Int32 o = this.offsetOf( x, y )

            if this.pixelFormat == EPixelFormat.Gray8
            {
                Int32 v = c.grayscale().r
                this.setByteAt( o, v )
            }
            elif this.pixelFormat == EPixelFormat.Gray16
            {
                Int32 v = c.grayscale().r
                this.setByteAt( o, 0 )
                this.setByteAt( o + 1, v )
            }
            elif this.pixelFormat == EPixelFormat.Rgb8
            {
                this.setByteAt( o, c.r )
                this.setByteAt( o + 1, c.g )
                this.setByteAt( o + 2, c.b )
            }
            elif this.pixelFormat == EPixelFormat.Rgba8
            {
                this.setByteAt( o, c.r )
                this.setByteAt( o + 1, c.g )
                this.setByteAt( o + 2, c.b )
                this.setByteAt( o + 3, c.a )
            }
            elif this.pixelFormat == EPixelFormat.Bgr8
            {
                this.setByteAt( o, c.b )
                this.setByteAt( o + 1, c.g )
                this.setByteAt( o + 2, c.r )
            }
            elif this.pixelFormat == EPixelFormat.Bgra8
            {
                this.setByteAt( o, c.b )
                this.setByteAt( o + 1, c.g )
                this.setByteAt( o + 2, c.r )
                this.setByteAt( o + 3, c.a )
            }
        }

        # ── 整块操作 ─────────────────────────────────────────
        public void fill( ColorInt c )
        {
            if c == null || !this.isValid
            {
                ret
            }
            # C 快路径（RGBA8 整块填充；失败回落下方 SL 逐像素循环）
            if this.pixelFormat == EPixelFormat.Rgba8 && ImageFfi.ensureReady()
            {
                Int32 need = this.width * this.height * 4
                Int64 p = Memory.alloc( need )
                if p != 0
                {
                    if ImageFfi.libOpFill( p, this.width, this.height, c.toPackedRgba() )
                    {
                        if ImageFfi._fillBytes( p, this._data, need )
                        {
                            Memory.free( p )
                            ret
                        }
                    }
                    Memory.free( p )
                }
            }
            Int32 y = 0
            while y < this.height
            {
                Int32 x = 0
                while x < this.width
                {
                    this.setPixel( x, y, c )
                    x = x + 1
                }
                y = y + 1
            }
        }

        public ImageBuffer clone()
        {
            ImageBuffer b = ImageBuffer( this.width, this.height, this.pixelFormat )
            b.colorSpace = this.colorSpace
            Int32 i = 0
            while i < this._data.length
            {
                b._data[ i ] = this._data[ i ]
                i = i + 1
            }
            ret b
        }

        public void flipY()
        {
            if !this.isValid
            {
                ret
            }
            # C 快路径（4 字节像素行交换；失败回落下方 SL 循环）
            if this.bytesPerPixel() == 4 && ImageFfi.ensureReady()
            {
                Int32 need = this.width * this.height * 4
                Int64 p = ImageFfi._copyIn( this._data, need )
                if p != 0
                {
                    if ImageFfi.libOpFlipY( p, this.width, this.height )
                    {
                        if ImageFfi._fillBytes( p, this._data, need )
                        {
                            Memory.free( p )
                            ret
                        }
                    }
                    Memory.free( p )
                }
            }
            Int32 stride = this.stride()
            Array<UInt8> row = Array<UInt8>( stride )
            Int32 top = 0
            Int32 bottom = this.height - 1
            while top < bottom
            {
                Int32 topOff = top * stride
                Int32 bottomOff = bottom * stride
                Int32 i = 0
                while i < stride
                {
                    row[ i ] = this._data[ topOff + i ]
                    i = i + 1
                }
                i = 0
                while i < stride
                {
                    this._data[ topOff + i ] = this._data[ bottomOff + i ]
                    this._data[ bottomOff + i ] = row[ i ]
                    i = i + 1
                }
                top = top + 1
                bottom = bottom - 1
            }
        }

        public void flipX()
        {
            if !this.isValid
            {
                ret
            }
            # C 快路径（4 字节像素行内交换；失败回落下方 SL 循环）
            if this.bytesPerPixel() == 4 && ImageFfi.ensureReady()
            {
                Int32 need = this.width * this.height * 4
                Int64 p = ImageFfi._copyIn( this._data, need )
                if p != 0
                {
                    if ImageFfi.libOpFlipX( p, this.width, this.height )
                    {
                        if ImageFfi._fillBytes( p, this._data, need )
                        {
                            Memory.free( p )
                            ret
                        }
                    }
                    Memory.free( p )
                }
            }
            Int32 bpp = this.bytesPerPixel()
            Int32 y = 0
            while y < this.height
            {
                Int32 left = 0
                Int32 right = this.width - 1
                while left < right
                {
                    Int32 a = ( y * this.width + left ) * bpp
                    Int32 b = ( y * this.width + right ) * bpp
                    Int32 k = 0
                    while k < bpp
                    {
                        UInt8 tmp = this._data[ a + k ]
                        this._data[ a + k ] = this._data[ b + k ]
                        this._data[ b + k ] = tmp
                        k = k + 1
                    }
                    left = left + 1
                    right = right - 1
                }
                y = y + 1
            }
        }

        public ImageBuffer crop( Int32 x0, Int32 y0, Int32 w, Int32 h )
        {
            if !this.isValid
            {
                ret null
            }
            if x0 < 0 { x0 = 0 }
            if y0 < 0 { y0 = 0 }
            if w <= 0 || h <= 0
            {
                ret null
            }
            if x0 + w > this.width { w = this.width - x0 }
            if y0 + h > this.height { h = this.height - y0 }
            if w <= 0 || h <= 0
            {
                ret null
            }
            ImageBuffer dst = ImageBuffer( w, h, this.pixelFormat )
            dst.colorSpace = this.colorSpace
            Int32 rowBytes = w * this.bytesPerPixel()
            Int32 y = 0
            while y < h
            {
                Int32 src = ( y0 + y ) * this.stride() + x0 * this.bytesPerPixel()
                Int32 dstOff = y * rowBytes
                Int32 i = 0
                while i < rowBytes
                {
                    dst._data[ dstOff + i ] = this._data[ src + i ]
                    i = i + 1
                }
                y = y + 1
            }
            ret dst
        }

        # ── 缩放（最近邻 / 双线性）───────────────────────────
        public ImageBuffer resize( Int32 newWidth, Int32 newHeight, EInterpolation mode )
        {
            if !this.isValid || newWidth <= 0 || newHeight <= 0
            {
                ret null
            }
            # C 快路径（RGBA8；Bicubic/Lanczos 与非 RGBA8 走下方 SL 兜底）
            Int32 imode = -1
            if mode == EInterpolation.Nearest
            {
                imode = 0
            }
            elif mode == EInterpolation.Bilinear
            {
                imode = 1
            }
            if imode >= 0 && this.pixelFormat == EPixelFormat.Rgba8 && ImageFfi.ensureReady()
            {
                Int64 s = ImageFfi._copyIn( this._data, this.width * this.height * 4 )
                if s != 0
                {
                    Int32 dstNeed = newWidth * newHeight * 4
                    Int64 d = Memory.alloc( dstNeed )
                    if d != 0
                    {
                        Int64 ctl = Memory.alloc( 20 )
                        if ctl != 0
                        {
                            Array<Int32> cvals = Array<Int32>( 5 )
                            cvals[ 0 ] = this.width
                            cvals[ 1 ] = this.height
                            cvals[ 2 ] = newWidth
                            cvals[ 3 ] = newHeight
                            cvals[ 4 ] = imode
                            bool done = false
                            if ImageFfi._writeCtl( ctl, cvals )
                            {
                                if ImageFfi.libOpResize( s, d, ctl )
                                {
                                    done = true
                                }
                            }
                            if done
                            {
                                ImageBuffer dst = ImageBuffer( newWidth, newHeight, EPixelFormat.Rgba8 )
                                dst.colorSpace = this.colorSpace
                                if ImageFfi._fillBytes( d, dst._data, dstNeed )
                                {
                                    Memory.free( ctl )
                                    Memory.free( d )
                                    Memory.free( s )
                                    ret dst
                                }
                            }
                            Memory.free( ctl )
                        }
                        Memory.free( d )
                    }
                    Memory.free( s )
                }
            }
            if mode == EInterpolation.Nearest
            {
                ret this.resizeNearest( newWidth, newHeight )
            }
            ret this.resizeBilinear( newWidth, newHeight )
        }

        ImageBuffer resizeNearest( Int32 nw, Int32 nh )
        {
            ImageBuffer dst = ImageBuffer( nw, nh, this.pixelFormat )
            dst.colorSpace = this.colorSpace
            Int32 y = 0
            while y < nh
            {
                Int32 sy = SystemConvertInt32( 1.0f * y * this.height / nh )
                if sy >= this.height { sy = this.height - 1 }
                Int32 x = 0
                while x < nw
                {
                    Int32 sx = SystemConvertInt32( 1.0f * x * this.width / nw )
                    if sx >= this.width { sx = this.width - 1 }
                    dst.setPixel( x, y, this.getPixel( sx, sy ) )
                    x = x + 1
                }
                y = y + 1
            }
            ret dst
        }

        ImageBuffer resizeBilinear( Int32 nw, Int32 nh )
        {
            ImageBuffer dst = ImageBuffer( nw, nh, this.pixelFormat )
            dst.colorSpace = this.colorSpace
            Int32 y = 0
            while y < nh
            {
                Float32 fy = 1.0f * ( y + 0.5f ) * this.height / nh - 0.5f
                if fy < 0.0f { fy = 0.0f }
                Int32 y0 = SystemConvertInt32( fy )
                Int32 y1 = y0 + 1
                Float32 wy = fy - 1.0f * y0
                if y0 < 0 { y0 = 0 }
                if y1 < 0 { y1 = 0 }
                if y0 >= this.height { y0 = this.height - 1 }
                if y1 >= this.height { y1 = this.height - 1 }

                Int32 x = 0
                while x < nw
                {
                    Float32 fx = 1.0f * ( x + 0.5f ) * this.width / nw - 0.5f
                    if fx < 0.0f { fx = 0.0f }
                    Int32 x0 = SystemConvertInt32( fx )
                    Int32 x1 = x0 + 1
                    Float32 wx = fx - 1.0f * x0
                    if x0 < 0 { x0 = 0 }
                    if x1 < 0 { x1 = 0 }
                    if x0 >= this.width { x0 = this.width - 1 }
                    if x1 >= this.width { x1 = this.width - 1 }

                    ColorInt c00 = this.getPixel( x0, y0 )
                    ColorInt c10 = this.getPixel( x1, y0 )
                    ColorInt c01 = this.getPixel( x0, y1 )
                    ColorInt c11 = this.getPixel( x1, y1 )

                    Float32 w00 = ( 1.0f - wx ) * ( 1.0f - wy )
                    Float32 w10 = wx * ( 1.0f - wy )
                    Float32 w01 = ( 1.0f - wx ) * wy
                    Float32 w11 = wx * wy

                    Int32 rr = ColorInt.toInt( 1.0f * c00.r * w00 + 1.0f * c10.r * w10 +
                                            1.0f * c01.r * w01 + 1.0f * c11.r * w11 )
                    Int32 gg = ColorInt.toInt( 1.0f * c00.g * w00 + 1.0f * c10.g * w10 +
                                            1.0f * c01.g * w01 + 1.0f * c11.g * w11 )
                    Int32 bb = ColorInt.toInt( 1.0f * c00.b * w00 + 1.0f * c10.b * w10 +
                                            1.0f * c01.b * w01 + 1.0f * c11.b * w11 )
                    Int32 aa = ColorInt.toInt( 1.0f * c00.a * w00 + 1.0f * c10.a * w10 +
                                            1.0f * c01.a * w01 + 1.0f * c11.a * w11 )
                    dst.setPixel( x, y, ColorInt( rr, gg, bb, aa ) )
                    x = x + 1
                }
                y = y + 1
            }
            ret dst
        }

        # ── 像素格式互转 ─────────────────────────────────────
        public ImageBuffer convertTo( EPixelFormat target )
        {
            if !this.isValid
            {
                ret null
            }
            if target == this.pixelFormat
            {
                ret this.clone()
            }
            # C 快路径（8/16 位整数格式互转；浮点格式走下方 SL 兜底）
            Int32 sf = ImageFfi.fmtToInt( this.pixelFormat )
            Int32 tf = ImageFfi.fmtToInt( target )
            if sf > 0 && tf > 0 && ImageFfi.ensureReady()
            {
                Int32 srcNeed = this.width * this.height * this.bytesPerPixel()
                Int64 s = ImageFfi._copyIn( this._data, srcNeed )
                if s != 0
                {
                    Int32 dstNeed = this.width * this.height * ImageBuffer.bytesPerPixelOf( target )
                    Int64 d = Memory.alloc( dstNeed )
                    if d != 0
                    {
                        if ImageFfi.libOpConvert( s, d, this.width, this.height, sf, tf )
                        {
                            ImageBuffer dst = ImageBuffer( this.width, this.height, target )
                            dst.colorSpace = this.colorSpace
                            if ImageFfi._fillBytes( d, dst._data, dstNeed )
                            {
                                Memory.free( d )
                                Memory.free( s )
                                ret dst
                            }
                        }
                        Memory.free( d )
                    }
                    Memory.free( s )
                }
            }
            ImageBuffer dst = ImageBuffer( this.width, this.height, target )
            dst.colorSpace = this.colorSpace
            Int32 y = 0
            while y < this.height
            {
                Int32 x = 0
                while x < this.width
                {
                    dst.setPixel( x, y, this.getPixel( x, y ) )
                    x = x + 1
                }
                y = y + 1
            }
            ret dst
        }

        public void premultiplyAlpha()
        {
            if !this.hasAlpha()
            {
                ret
            }
            # C 快路径（4 字节 alpha 格式就地预乘；失败回落下方 SL 循环）
            if this.bytesPerPixel() == 4 && ImageFfi.ensureReady()
            {
                Int32 need = this.width * this.height * 4
                Int64 p = ImageFfi._copyIn( this._data, need )
                if p != 0
                {
                    if ImageFfi.libOpPremultiply( p, this.width, this.height, 0 )
                    {
                        if ImageFfi._fillBytes( p, this._data, need )
                        {
                            Memory.free( p )
                            ret
                        }
                    }
                    Memory.free( p )
                }
            }
            Int32 y = 0
            while y < this.height
            {
                Int32 x = 0
                while x < this.width
                {
                    this.setPixel( x, y, this.getPixel( x, y ).premultiply() )
                    x = x + 1
                }
                y = y + 1
            }
        }

        public void unpremultiplyAlpha()
        {
            if !this.hasAlpha()
            {
                ret
            }
            # C 快路径（4 字节 alpha 格式就地反预乘；失败回落下方 SL 循环）
            if this.bytesPerPixel() == 4 && ImageFfi.ensureReady()
            {
                Int32 need = this.width * this.height * 4
                Int64 p = ImageFfi._copyIn( this._data, need )
                if p != 0
                {
                    if ImageFfi.libOpPremultiply( p, this.width, this.height, 1 )
                    {
                        if ImageFfi._fillBytes( p, this._data, need )
                        {
                            Memory.free( p )
                            ret
                        }
                    }
                    Memory.free( p )
                }
            }
            Int32 y = 0
            while y < this.height
            {
                Int32 x = 0
                while x < this.width
                {
                    this.setPixel( x, y, this.getPixel( x, y ).unpremultiply() )
                    x = x + 1
                }
                y = y + 1
            }
        }

        # ── 仿 Pillow Image 模块的补充能力 ────────────────────
        # 对标 https://www.runoob.com/pillow/pillow-image-module.html：
        #   Image.new            -> newImage / ImageBuffer 构造
        #   Image.paste          -> paste
        #   Image.rotate         -> rotate
        #   Image.split          -> splitChannels
        #   Image.merge          -> mergeRgba / mergeRgb
        #   Image.alpha_composite-> alphaComposite
        #   Image.blend          -> blend
        # （open/save/resize/crop/convert/copy/thumbnail/getpixel/putpixel
        #   此前已有：ImageIO.load/save/thumbnail + 本类方法）

        # Image.new(mode, size, color)：新建纯色 Rgba8 图（color = null 得透明）
        public static ImageBuffer newImage( Int32 width, Int32 height, ColorInt color )
        {
            if width <= 0 || height <= 0
            {
                ret null
            }
            ImageBuffer b = ImageBuffer( width, height, EPixelFormat.Rgba8 )
            if color != null
            {
                b.fill( color )
            }
            ret b
        }

        # Image.new 默认色 0（RGBA 下即透明黑）
        public static ImageBuffer newImage( Int32 width, Int32 height )
        {
            ret ImageBuffer.newImage( width, height, null )
        }

        # Image.paste(im, box)：src 整块贴入本图 (x, y)，越界自动裁剪，
        # 逐像素拷贝（含 alpha，无混合；返回是否完成贴入）
        public bool paste( ImageBuffer src, Int32 x, Int32 y )
        {
            if !this.isValid || src == null || !src.isValid
            {
                ret false
            }
            # C 快路径（双 RGBA8 整块贴入；失败回落下方 SL 逐像素循环）
            if this.pixelFormat == EPixelFormat.Rgba8 && src.pixelFormat == EPixelFormat.Rgba8 && ImageFfi.ensureReady()
            {
                Int32 dstNeed = this.width * this.height * 4
                Int32 srcNeed = src.width * src.height * 4
                Int64 d = ImageFfi._copyIn( this._data, dstNeed )
                if d != 0
                {
                    Int64 s = ImageFfi._copyIn( src._data, srcNeed )
                    if s != 0
                    {
                        bool done = false
                        Int64 ctl = Memory.alloc( 24 )
                        if ctl != 0
                        {
                            Array<Int32> cvals = Array<Int32>( 6 )
                            cvals[ 0 ] = this.width
                            cvals[ 1 ] = this.height
                            cvals[ 2 ] = src.width
                            cvals[ 3 ] = src.height
                            cvals[ 4 ] = x
                            cvals[ 5 ] = y
                            if ImageFfi._writeCtl( ctl, cvals )
                            {
                                if ImageFfi.libOpPaste( d, s, ctl )
                                {
                                    done = ImageFfi._fillBytes( d, this._data, dstNeed )
                                }
                            }
                            Memory.free( ctl )
                        }
                        Memory.free( s )
                        if done
                        {
                            Memory.free( d )
                            ret true
                        }
                    }
                    Memory.free( d )
                }
            }
            Int32 sy = 0
            while sy < src.height
            {
                Int32 dy = y + sy
                if dy >= 0 && dy < this.height
                {
                    Int32 sx = 0
                    while sx < src.width
                    {
                        Int32 dx = x + sx
                        if dx >= 0 && dx < this.width
                        {
                            this.setPixel( dx, dy, src.getPixel( sx, sy ) )
                        }
                        sx = sx + 1
                    }
                }
                sy = sy + 1
            }
            ret true
        }

        # Image.paste(im, box, mask)：带蒙版贴入 —— mask 为 Gray8 平面
        # （取其红通道值 0..255 作混合因子），dst = src*m/255 + dst*(1-m/255)；
        # 覆盖域内逐像素混合（Pillow paste(im, box, mask) 同义）；
        # mask 尺寸须等于 src；返回是否完成
        public bool pasteMasked( ImageBuffer src, Int32 x, Int32 y, ImageBuffer mask )
        {
            if !this.isValid || src == null || !src.isValid
            {
                ret false
            }
            if mask == null || !mask.isValid
            {
                ret false
            }
            if mask.width != src.width || mask.height != src.height
            {
                ret false
            }
            # C 快路径（sli_op_paste_masked；VM 封送 bug 期间由开关关停——坑 9）
            if this.pixelFormat == EPixelFormat.Rgba8 && src.pixelFormat == EPixelFormat.Rgba8 && ImageFfi.opFastPathsEnabled && ImageFfi.ensureReady()
            {
                Int32 dstNeed = this.width * this.height * 4
                Int32 srcNeed = src.width * src.height * 4
                Int32 maskNeed = mask.width * mask.height * ImageFfi.fmtToInt( mask.pixelFormat )
                if maskNeed == mask.width * mask.height
                {
                    Int64 d = ImageFfi._copyIn( this._data, dstNeed )
                    if d != 0
                    {
                        Int64 s = ImageFfi._copyIn( src._data, srcNeed )
                        if s != 0
                        {
                            Int64 m = ImageFfi._copyIn( mask._data, maskNeed )
                            if m != 0
                            {
                                bool done = false
                                Int64 ctl = Memory.alloc( 24 )
                                if ctl != 0
                                {
                                    Array<Int32> cvals = Array<Int32>( 6 )
                                    cvals[ 0 ] = this.width
                                    cvals[ 1 ] = this.height
                                    cvals[ 2 ] = src.width
                                    cvals[ 3 ] = src.height
                                    cvals[ 4 ] = x
                                    cvals[ 5 ] = y
                                    if ImageFfi._writeCtl( ctl, cvals )
                                    {
                                        if ImageFfi.libOpPasteMasked( d, s, m, ctl )
                                        {
                                            done = ImageFfi._fillBytes( d, this._data, dstNeed )
                                        }
                                    }
                                    Memory.free( ctl )
                                }
                                Memory.free( m )
                                Memory.free( s )
                                if done
                                {
                                    Memory.free( d )
                                    ret true
                                }
                            }
                            Memory.free( s )
                        }
                        Memory.free( d )
                    }
                }
            }
            # SL 兜底：域内逐像素按因子混合（任意格式经 getPixel/setPixel；
            # 整数直算与 C 层 op_clamp8(d + (s-d)*m/255) 逐位一致，不走
            # ColorInt.lerp —— 其负方向 delta 被钳 0 的已知 bug）
            Int32 sy = 0
            while sy < src.height
            {
                Int32 dy = y + sy
                if dy >= 0 && dy < this.height
                {
                    Int32 sx = 0
                    while sx < src.width
                    {
                        Int32 dx = x + sx
                        if dx >= 0 && dx < this.width
                        {
                            Int32 mv = mask.getPixel( sx, sy ).r
                            ColorInt dc = this.getPixel( dx, dy )
                            ColorInt sc = src.getPixel( sx, sy )
                            Int32 rr = ColorInt.clamp8( dc.r + ( sc.r - dc.r ) * mv / 255 )
                            Int32 gg = ColorInt.clamp8( dc.g + ( sc.g - dc.g ) * mv / 255 )
                            Int32 bb = ColorInt.clamp8( dc.b + ( sc.b - dc.b ) * mv / 255 )
                            Int32 aa = ColorInt.clamp8( dc.a + ( sc.a - dc.a ) * mv / 255 )
                            this.setPixel( dx, dy, ColorInt( rr, gg, bb, aa ) )
                        }
                        sx = sx + 1
                    }
                }
                sy = sy + 1
            }
            ret true
        }

        # Image.rotate(angle)：绕中心旋转（正角 = 逆时针，Pillow 同参），
        # 输出恒 Rgba8，圈外填透明；expand = true 输出旋转包围盒尺寸
        public ImageBuffer rotate( Float32 angleDegrees )
        {
            ret this.rotate( angleDegrees, false, EInterpolation.Nearest )
        }

        public ImageBuffer rotate( Float32 angleDegrees, bool expand )
        {
            ret this.rotate( angleDegrees, expand, EInterpolation.Nearest )
        }

        public ImageBuffer rotate( Float32 angleDegrees, bool expand, EInterpolation mode )
        {
            if !this.isValid
            {
                ret null
            }
            Float32 rad = angleDegrees * 3.14159265f / 180.0f
            Float32 c = ImageBuffer._cos( rad )
            Float32 s = ImageBuffer._sin( rad )
            Float32 absC = c
            if absC < 0.0f { absC = 0.0f - absC }
            Float32 absS = s
            if absS < 0.0f { absS = 0.0f - absS }
            Int32 nw = this.width
            Int32 nh = this.height
            if expand
            {
                nw = SystemConvertInt32( absC * this.width + absS * this.height + 0.5f )
                nh = SystemConvertInt32( absS * this.width + absC * this.height + 0.5f )
            }
            if nw <= 0 || nh <= 0
            {
                ret null
            }
            # C 快路径（sli_op_rotate；VM f32/封送 bug 期间由开关关停——坑 9）
            if ImageFfi.opFastPathsEnabled && ImageFfi.ensureReady()
            {
                Int64 srcp = ImageFfi._uploadRgba( this )
                if srcp != 0
                {
                    Int32 dstNeed = nw * nh * 4
                    Int64 dstp = Memory.alloc( dstNeed )
                    if dstp != 0
                    {
                        Int64 ctl = Memory.alloc( 20 )
                        if ctl != 0
                        {
                            Int32 imode = 1
                            if mode == EInterpolation.Nearest
                            {
                                imode = 0
                            }
                            Array<Int32> cvals = Array<Int32>( 5 )
                            cvals[ 0 ] = this.width
                            cvals[ 1 ] = this.height
                            cvals[ 2 ] = nw
                            cvals[ 3 ] = nh
                            cvals[ 4 ] = imode
                            bool done = false
                            if ImageFfi._writeCtl( ctl, cvals )
                            {
                                if ImageFfi.libOpRotate( srcp, dstp, ctl, SystemConvertInt32( angleDegrees * 1000.0f ) )
                                {
                                    done = true
                                }
                            }
                            if done
                            {
                                ImageBuffer dst = ImageBuffer( nw, nh, EPixelFormat.Rgba8 )
                                dst.colorSpace = this.colorSpace
                                if ImageFfi._fillBytes( dstp, dst._data, dstNeed )
                                {
                                    Memory.free( ctl )
                                    Memory.free( dstp )
                                    Memory.free( srcp )
                                    ret dst
                                }
                            }
                            Memory.free( ctl )
                        }
                        Memory.free( dstp )
                    }
                    Memory.free( srcp )
                }
            }
            ImageBuffer dst = ImageBuffer( nw, nh, EPixelFormat.Rgba8 )
            Float32 cx = 0.5f * ( this.width - 1 )
            Float32 cy = 0.5f * ( this.height - 1 )
            Float32 ncx = 0.5f * ( nw - 1 )
            Float32 ncy = 0.5f * ( nh - 1 )
            Int32 y = 0
            while y < nh
            {
                Int32 x = 0
                while x < nw
                {
                    Float32 fx = 1.0f * x - ncx
                    Float32 fy = 1.0f * y - ncy
                    # 逆映射（视觉逆时针，y 向下）：
                    # sx = cx + fx*c - fy*s ; sy = cy + fx*s + fy*c
                    Float32 sx = cx + fx * c - fy * s
                    Float32 sy = cy + fx * s + fy * c
                    bool inside = sx >= ( 0.0f - 0.5f ) && sx <= 1.0f * this.width - 0.5f
                    inside = inside && sy >= ( 0.0f - 0.5f ) && sy <= 1.0f * this.height - 0.5f
                    if inside
                    {
                        if mode == EInterpolation.Nearest
                        {
                            Int32 ix = SystemConvertInt32( sx + 0.5f )
                            Int32 iy = SystemConvertInt32( sy + 0.5f )
                            if ix < 0 { ix = 0 }
                            if ix >= this.width { ix = this.width - 1 }
                            if iy < 0 { iy = 0 }
                            if iy >= this.height { iy = this.height - 1 }
                            dst.setPixel( x, y, this.getPixel( ix, iy ) )
                        }
                        else
                        {
                            # 双线性：先 clamp 到图内再取整（边界半像素复制）
                            if sx < 0.0f { sx = 0.0f }
                            if sx > 1.0f * ( this.width - 1 ) { sx = 1.0f * ( this.width - 1 ) }
                            if sy < 0.0f { sy = 0.0f }
                            if sy > 1.0f * ( this.height - 1 ) { sy = 1.0f * ( this.height - 1 ) }
                            Int32 x0 = SystemConvertInt32( sx )
                            Int32 x1 = x0 + 1
                            if x1 >= this.width { x1 = this.width - 1 }
                            Int32 y0 = SystemConvertInt32( sy )
                            Int32 y1 = y0 + 1
                            if y1 >= this.height { y1 = this.height - 1 }
                            Float32 wx = sx - 1.0f * x0
                            Float32 wy = sy - 1.0f * y0
                            ColorInt c00 = this.getPixel( x0, y0 )
                            ColorInt c10 = this.getPixel( x1, y0 )
                            ColorInt c01 = this.getPixel( x0, y1 )
                            ColorInt c11 = this.getPixel( x1, y1 )
                            Float32 w00 = ( 1.0f - wx ) * ( 1.0f - wy )
                            Float32 w10 = wx * ( 1.0f - wy )
                            Float32 w01 = ( 1.0f - wx ) * wy
                            Float32 w11 = wx * wy
                            Int32 rr = ColorInt.toInt( 1.0f * c00.r * w00 + 1.0f * c10.r * w10 +
                                                    1.0f * c01.r * w01 + 1.0f * c11.r * w11 )
                            Int32 gg = ColorInt.toInt( 1.0f * c00.g * w00 + 1.0f * c10.g * w10 +
                                                    1.0f * c01.g * w01 + 1.0f * c11.g * w11 )
                            Int32 bb = ColorInt.toInt( 1.0f * c00.b * w00 + 1.0f * c10.b * w10 +
                                                    1.0f * c01.b * w01 + 1.0f * c11.b * w11 )
                            Int32 aa = ColorInt.toInt( 1.0f * c00.a * w00 + 1.0f * c10.a * w10 +
                                                    1.0f * c01.a * w01 + 1.0f * c11.a * w11 )
                            dst.setPixel( x, y, ColorInt( rr, gg, bb, aa ) )
                        }
                    }
                    x = x + 1
                }
                y = y + 1
            }
            ret dst
        }

        # Image.split()：拆通道 -> List<ImageBuffer>（每通道一张 Gray8 图，
        # RGBA 出 4 张 [R,G,B,A]，无 alpha 格式出 3 张 [R,G,B]）
        public List<ImageBuffer> splitChannels()
        {
            List<ImageBuffer> result = List<ImageBuffer>()
            if !this.isValid
            {
                ret result
            }
            Int32 planeNeed = this.width * this.height
            # C 快路径（sli_op_split_rgba：RGBA 视图拆 4 张 Gray8 平面；
            # 限 hasAlpha —— 无 alpha 格式 SL 语义只出 3 张平面，走兜底）
            Int64 srcp = 0
            Int64 rp = 0
            Int64 gp = 0
            Int64 bp = 0
            Int64 ap = 0
            bool fast = false
            if ImageFfi.ensureReady() && this.hasAlpha()
            {
                srcp = ImageFfi._uploadRgba( this )
                if srcp != 0
                {
                    rp = Memory.alloc( planeNeed )
                    if rp != 0
                    {
                        gp = Memory.alloc( planeNeed )
                    }
                    if gp != 0
                    {
                        bp = Memory.alloc( planeNeed )
                    }
                    if bp != 0
                    {
                        ap = Memory.alloc( planeNeed )
                    }
                    if ap != 0
                    {
                        Int64 ctl = Memory.alloc( 8 )
                        if ctl != 0
                        {
                            Array<Int32> cvals = Array<Int32>( 2 )
                            cvals[ 0 ] = this.width
                            cvals[ 1 ] = this.height
                            if ImageFfi._writeCtl( ctl, cvals )
                            {
                                if ImageFfi.libOpSplitRgba( srcp, rp, gp, bp, ap, ctl )
                                {
                                    fast = true
                                }
                            }
                            Memory.free( ctl )
                        }
                    }
                }
            }
            ImageBuffer p0 = null
            ImageBuffer p1 = null
            ImageBuffer p2 = null
            ImageBuffer p3 = null
            bool ok = false
            if fast
            {
                p0 = ImageBuffer( this.width, this.height, EPixelFormat.Gray8 )
                p1 = ImageBuffer( this.width, this.height, EPixelFormat.Gray8 )
                p2 = ImageBuffer( this.width, this.height, EPixelFormat.Gray8 )
                p3 = ImageBuffer( this.width, this.height, EPixelFormat.Gray8 )
                p0.colorSpace = this.colorSpace
                p1.colorSpace = this.colorSpace
                p2.colorSpace = this.colorSpace
                p3.colorSpace = this.colorSpace
                ok = ImageFfi._fillBytes( rp, p0._data, planeNeed )
                ok = ImageFfi._fillBytes( gp, p1._data, planeNeed ) && ok
                ok = ImageFfi._fillBytes( bp, p2._data, planeNeed ) && ok
                ok = ImageFfi._fillBytes( ap, p3._data, planeNeed ) && ok
            }
            if srcp != 0
            {
                Memory.free( srcp )
            }
            if rp != 0
            {
                Memory.free( rp )
            }
            if gp != 0
            {
                Memory.free( gp )
            }
            if bp != 0
            {
                Memory.free( bp )
            }
            if ap != 0
            {
                Memory.free( ap )
            }
            if ok
            {
                result.add( p0 )
                result.add( p1 )
                result.add( p2 )
                result.add( p3 )
                ret result
            }
            # SL 兜底循环（原实现）
            Int32 n = 4
            if !this.hasAlpha()
            {
                n = 3
            }
            Int32 ch = 0
            while ch < n
            {
                ImageBuffer plane = ImageBuffer( this.width, this.height, EPixelFormat.Gray8 )
                Int32 y = 0
                while y < this.height
                {
                    Int32 x = 0
                    while x < this.width
                    {
                        ColorInt c = this.getPixel( x, y )
                        Int32 v = c.r
                        if ch == 1
                        {
                            v = c.g
                        }
                        elif ch == 2
                        {
                            v = c.b
                        }
                        elif ch == 3
                        {
                            v = c.a
                        }
                        plane.setPixel( x, y, ColorInt( v, v, v, 255 ) )
                        x = x + 1
                    }
                    y = y + 1
                }
                result.add( plane )
                ch = ch + 1
            }
            ret result
        }

        # Image.merge('RGBA', bands)：4 张同尺寸 Gray8 -> 一张 Rgba8
        public static ImageBuffer mergeRgba( ImageBuffer r, ImageBuffer g, ImageBuffer b, ImageBuffer a )
        {
            if r == null || g == null || b == null || a == null
            {
                ret null
            }
            if !r.isValid || !g.isValid || !b.isValid || !a.isValid
            {
                ret null
            }
            if r.width != g.width || r.width != b.width || r.width != a.width
            {
                ret null
            }
            if r.height != g.height || r.height != b.height || r.height != a.height
            {
                ret null
            }
            # C 快路径（sli_op_merge_rgba；限全 Gray8 平面，其它布局走兜底）
            Int32 planeNeed = r.width * r.height
            bool allGray = r.pixelFormat == EPixelFormat.Gray8
            allGray = g.pixelFormat == EPixelFormat.Gray8 && allGray
            allGray = b.pixelFormat == EPixelFormat.Gray8 && allGray
            allGray = a.pixelFormat == EPixelFormat.Gray8 && allGray
            Int64 rp = 0
            Int64 gp = 0
            Int64 bp = 0
            Int64 ap = 0
            bool ok = false
            ImageBuffer outBuf = null
            if allGray && ImageFfi.ensureReady()
            {
                rp = ImageFfi._copyIn( r._data, planeNeed )
                if rp != 0
                {
                    gp = ImageFfi._copyIn( g._data, planeNeed )
                }
                if gp != 0
                {
                    bp = ImageFfi._copyIn( b._data, planeNeed )
                }
                if bp != 0
                {
                    ap = ImageFfi._copyIn( a._data, planeNeed )
                }
                if ap != 0
                {
                    Int32 dstNeed = planeNeed * 4
                    Int64 dstp = Memory.alloc( dstNeed )
                    if dstp != 0
                    {
                        Int64 ctl = Memory.alloc( 8 )
                        if ctl != 0
                        {
                            Array<Int32> cvals = Array<Int32>( 2 )
                            cvals[ 0 ] = r.width
                            cvals[ 1 ] = r.height
                            if ImageFfi._writeCtl( ctl, cvals )
                            {
                                if ImageFfi.libOpMergeRgba( rp, gp, bp, ap, dstp, ctl )
                                {
                                    ImageBuffer dst = ImageBuffer( r.width, r.height, EPixelFormat.Rgba8 )
                                    if ImageFfi._fillBytes( dstp, dst._data, dstNeed )
                                    {
                                        outBuf = dst
                                        ok = true
                                    }
                                }
                            }
                            Memory.free( ctl )
                        }
                        Memory.free( dstp )
                    }
                }
            }
            if rp != 0
            {
                Memory.free( rp )
            }
            if gp != 0
            {
                Memory.free( gp )
            }
            if bp != 0
            {
                Memory.free( bp )
            }
            if ap != 0
            {
                Memory.free( ap )
            }
            if ok
            {
                ret outBuf
            }
            ret ImageBuffer._mergeRgbaSlow( r, g, b, a )
        }

        # 兜底：逐像素取 R 通道合成（原实现；任何格式平面可用）
        static ImageBuffer _mergeRgbaSlow( ImageBuffer r, ImageBuffer g, ImageBuffer b, ImageBuffer a )
        {
            ImageBuffer dst = ImageBuffer( r.width, r.height, EPixelFormat.Rgba8 )
            Int32 y = 0
            while y < r.height
            {
                Int32 x = 0
                while x < r.width
                {
                    dst.setPixel( x, y, ColorInt( r.getPixel( x, y ).r, g.getPixel( x, y ).r,
                                                  b.getPixel( x, y ).r, a.getPixel( x, y ).r ) )
                    x = x + 1
                }
                y = y + 1
            }
            ret dst
        }

        # Image.merge('RGB', bands)：3 张同尺寸 Gray8 -> 一张不透明 Rgba8
        public static ImageBuffer mergeRgb( ImageBuffer r, ImageBuffer g, ImageBuffer b )
        {
            if r == null || g == null || b == null
            {
                ret null
            }
            if !r.isValid || !g.isValid || !b.isValid
            {
                ret null
            }
            if r.width != g.width || r.width != b.width
            {
                ret null
            }
            if r.height != g.height || r.height != b.height
            {
                ret null
            }
            # C 快路径（sli_op_merge_rgb；限全 Gray8 平面，其它布局走兜底）
            Int32 planeNeed = r.width * r.height
            bool allGray = r.pixelFormat == EPixelFormat.Gray8
            allGray = g.pixelFormat == EPixelFormat.Gray8 && allGray
            allGray = b.pixelFormat == EPixelFormat.Gray8 && allGray
            Int64 rp = 0
            Int64 gp = 0
            Int64 bp = 0
            bool ok = false
            ImageBuffer outBuf = null
            if allGray && ImageFfi.ensureReady()
            {
                rp = ImageFfi._copyIn( r._data, planeNeed )
                if rp != 0
                {
                    gp = ImageFfi._copyIn( g._data, planeNeed )
                }
                if gp != 0
                {
                    bp = ImageFfi._copyIn( b._data, planeNeed )
                }
                if bp != 0
                {
                    Int32 dstNeed = planeNeed * 4
                    Int64 dstp = Memory.alloc( dstNeed )
                    if dstp != 0
                    {
                        if ImageFfi.libOpMergeRgb( rp, gp, bp, dstp, r.width, r.height )
                        {
                            ImageBuffer dst = ImageBuffer( r.width, r.height, EPixelFormat.Rgba8 )
                            if ImageFfi._fillBytes( dstp, dst._data, dstNeed )
                            {
                                outBuf = dst
                                ok = true
                            }
                        }
                        Memory.free( dstp )
                    }
                }
            }
            if rp != 0
            {
                Memory.free( rp )
            }
            if gp != 0
            {
                Memory.free( gp )
            }
            if bp != 0
            {
                Memory.free( bp )
            }
            if ok
            {
                ret outBuf
            }
            ImageBuffer dst = ImageBuffer( r.width, r.height, EPixelFormat.Rgba8 )
            Int32 y = 0
            while y < r.height
            {
                Int32 x = 0
                while x < r.width
                {
                    dst.setPixel( x, y, ColorInt( r.getPixel( x, y ).r, g.getPixel( x, y ).r,
                                                  b.getPixel( x, y ).r, 255 ) )
                    x = x + 1
                }
                y = y + 1
            }
            ret dst
        }

        # Image.alpha_composite(dst, src)：src over dst，逐像素
        # ColorInt.blendOver；两图同尺寸，输出 Rgba8
        public static ImageBuffer alphaComposite( ImageBuffer dst, ImageBuffer src )
        {
            if dst == null || src == null || !dst.isValid || !src.isValid
            {
                ret null
            }
            if dst.width != src.width || dst.height != src.height
            {
                ret null
            }
            # C 快路径（sli_op_alpha_composite；失败回落下方 SL 循环）
            if ImageFfi.ensureReady()
            {
                Int64 dp = ImageFfi._uploadRgba( dst )
                if dp != 0
                {
                    Int64 sp = ImageFfi._uploadRgba( src )
                    if sp != 0
                    {
                        Int32 need = dst.width * dst.height * 4
                        Int64 op = Memory.alloc( need )
                        if op != 0
                        {
                            if ImageFfi.libOpAlphaComposite( dp, sp, op, dst.width, dst.height )
                            {
                                ImageBuffer result = ImageBuffer( dst.width, dst.height, EPixelFormat.Rgba8 )
                                if ImageFfi._fillBytes( op, result._data, need )
                                {
                                    Memory.free( op )
                                    Memory.free( sp )
                                    Memory.free( dp )
                                    ret result
                                }
                            }
                            Memory.free( op )
                        }
                        Memory.free( sp )
                    }
                    Memory.free( dp )
                }
            }
            ImageBuffer result = ImageBuffer( dst.width, dst.height, EPixelFormat.Rgba8 )
            Int32 y = 0
            while y < dst.height
            {
                Int32 x = 0
                while x < dst.width
                {
                    result.setPixel( x, y, ColorInt.blendOver( dst.getPixel( x, y ), src.getPixel( x, y ) ) )
                    x = x + 1
                }
                y = y + 1
            }
            ret result
        }

        # Image.blend(im1, im2, alpha)：im1*(1-alpha) + im2*alpha 逐通道
        # 混合（Pillow blend 同式，alpha 0..1 clamp）。
        # 不走 ColorInt.lerp：其 toInt 增量被 clamp8 钳到 0..255，负方向
        # 插值（255 -> 0）delta<0 被钳 0 后通道永远停在初值（Std 侧 lerp
        # 的已知 bug，此处用最终值直算绕开：混合结果恒 0..255 无需钳 delta）
        public static ImageBuffer blend( ImageBuffer im1, ImageBuffer im2, Float32 alpha )
        {
            if im1 == null || im2 == null || !im1.isValid || !im2.isValid
            {
                ret null
            }
            if im1.width != im2.width || im1.height != im2.height
            {
                ret null
            }
            if alpha < 0.0f { alpha = 0.0f }
            if alpha > 1.0f { alpha = 1.0f }
            # C 快路径（sli_op_blend；VM 封送 bug 期间由开关关停——坑 9）
            if ImageFfi.opFastPathsEnabled && ImageFfi.ensureReady()
            {
                Int64 ap = ImageFfi._uploadRgba( im1 )
                if ap != 0
                {
                    Int64 bp = ImageFfi._uploadRgba( im2 )
                    if bp != 0
                    {
                        Int32 need = im1.width * im1.height * 4
                        Int64 op = Memory.alloc( need )
                        if op != 0
                        {
                            if ImageFfi.libOpBlend( ap, bp, op, im1.width, im1.height, SystemConvertInt32( alpha * 1000.0f ) )
                            {
                                ImageBuffer result = ImageBuffer( im1.width, im1.height, EPixelFormat.Rgba8 )
                                if ImageFfi._fillBytes( op, result._data, need )
                                {
                                    Memory.free( op )
                                    Memory.free( bp )
                                    Memory.free( ap )
                                    ret result
                                }
                            }
                            Memory.free( op )
                        }
                        Memory.free( bp )
                    }
                    Memory.free( ap )
                }
            }
            Float32 fa = 1.0f - alpha
            ImageBuffer result = ImageBuffer( im1.width, im1.height, EPixelFormat.Rgba8 )
            Int32 y = 0
            while y < im1.height
            {
                Int32 x = 0
                while x < im1.width
                {
                    ColorInt c1 = im1.getPixel( x, y )
                    ColorInt c2 = im2.getPixel( x, y )
                    Int32 rr = ColorInt.toInt( 1.0f * c1.r * fa + 1.0f * c2.r * alpha )
                    Int32 gg = ColorInt.toInt( 1.0f * c1.g * fa + 1.0f * c2.g * alpha )
                    Int32 bb = ColorInt.toInt( 1.0f * c1.b * fa + 1.0f * c2.b * alpha )
                    Int32 aa = ColorInt.toInt( 1.0f * c1.a * fa + 1.0f * c2.a * alpha )
                    result.setPixel( x, y, ColorInt( rr, gg, bb, aa ) )
                    x = x + 1
                }
                y = y + 1
            }
            ret result
        }

        # ── 三角（纯 SL，角度弧度；仿 DrawTypes 自带实现避免跨模块
        #    Mathf 绑定依赖；rotate 兜底需要量级精度。ImageMask 波浪
        #    图案复用，故 public）──
        public static Float32 _sin( Float32 radians )
        {
            Float32 twoPi = 6.28318531f
            Float32 pi = 3.14159265f
            Float32 v = radians
            Int32 guard = 0
            while guard < 64
            {
                if v <= pi
                {
                    if v >= ( 0.0f - pi )
                    {
                        break
                    }
                }
                if v > pi
                {
                    v = v - twoPi
                }
                else
                {
                    v = v + twoPi
                }
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

        public static Float32 _cos( Float32 radians )
        {
            ret ImageBuffer._sin( radians + 1.57079632f )
        }        # ── 字节互转 ─────────────────────────────────────────
        public Array<UInt8> toBytes()
        {
            ret this._data
        }

        # ── 原生显示桥接（QT 等模块）─────────────────────────
        # 导出原生 RGBA8 top-down 像素块（Memory.alloc 分配，
        # width*height*4 字节），供 QLabel.setPixmapRgba 这类原生
        # 显示通道直接消费；非 Rgba8 格式自动转换（ImageFfi.rgbaBytesOf）。
        # 返回 0 = 无效 / 超搬运上限（ImageFfi.MAX_INLINE_BYTES）/ 分配
        # 失败。成功后调用方持有释放权 —— 显示通道内部已深拷贝
        # （QPixmap::fromImage），Memory.free( ptr ) 随时安全
        public Int64 toNativeRgba()
        {
            if !this.isValid
            {
                ret 0
            }
            ret ImageFfi._uploadRgba( this )
        }

        public static ImageBuffer fromBytes( Array<UInt8> bytes, Int32 w, Int32 h, EPixelFormat fmt )
        {
            if bytes == null || w <= 0 || h <= 0
            {
                ret null
            }
            Int32 need = w * h * ImageBuffer.bytesPerPixelOf( fmt )
            if need <= 0 || bytes.length < need
            {
                ret null
            }
            ImageBuffer b = ImageBuffer( w, h, fmt )
            Int32 i = 0
            while i < need
            {
                b._data[ i ] = bytes[ i ]
                i = i + 1
            }
            ret b
        }

        # ── C 层编解码（ImageFfi -> sl_image_lib）─────────────
        # stb_image_write 编码（PNG/JPEG/BMP/TGA/PPM/TIFF）；
        # C 层契约：入参恒 RGBA8。返回压缩字节；失败返回 null
        public Array<UInt8> encode( EImageFormat format, Int32 quality )
        {
            Array<UInt8> rgba = ImageFfi.rgbaBytesOf( this )
            if rgba == null
            {
                ret null
            }
            ret ImageFfi.encodeMem( format, quality, this.width, this.height, rgba )
        }

        # 从压缩字节解码（恒输出 RGBA8）；失败返回 null
        public static ImageBuffer decode( Array<UInt8> bytes )
        {
            if bytes == null
            {
                ret null
            }
            ret ImageFfi.decodeMem( bytes )
        }

        override string toString()
        {
            string s = "ImageBuffer("
            s = s + this.width.toString() + "x" + this.height.toString()
            s = s + ", fmt=" + this.pixelFormat.toString()
            s = s + ")"
            ret s
        }
    }
}
