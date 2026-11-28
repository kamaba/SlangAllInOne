# =========================================================================
# Image/ImageFfi.sl —— C 层 sl_image_lib.dll 的 FFI 静态绑定 + 内存搬运
#
# C 契约：../cvm_image_lib/vm_sl_image.h（55 个 sli_* 导出，普通 C ABI）
#         其中 13 个 sli_gif_* 的 SL 绑定在 Gif.sl（动画拆解 / 合成），
#         20 个 sli_op_*（像素批量运算：卷积/旋转/缩放/合成混合/通道拆合/
#         格式转换/贴入/填充/翻转/预乘/灰度/通道运算/蒙版合成/外插混合）
#         在本文件，SL 侧重循环方法（ImageBuffer/ImageFilter/ImageChops/
#         ImageEnhance/ImageMask）以「C 快路径 + 纯 SL 循环兜底」接入
# 后端：  stb_image / stb_image_write（公有领域 OR MIT-0，JPEG/PNG/BMP/GIF/
#         TGA/PSD/HDR/PIC/PNM 读写）+ WIC（系统组件，TIFF/ICO/WebP 解码、
#         TIFF 编码兜底）
# 像素契约：恒 RGBA8、4 字节/像素、top-down；图像/blob 句柄 1 起始，0 = 无效
#
# 分层：
#   1) lib* 直接映射层 —— @DllStaticImport 薄封装，绑定失败走函数体兜底
#      （false/0/""，ensureReady() == false 即兜底征兆）
#   2) formatToInt / intToFormat —— EImageFormat 与 SLI_FMT_* 值恒等，
#      显式逐值映射（不走隐式数值转换）
#   3) 便利层 —— probeFile / decodeFile / probeMem / decodeMem /
#      encodeMem / saveMem
#
# 已知缺口（v1 约束）：VM 没有 Array<UInt8> <-> 原生指针的批量互转系统
# 方法，内存路径（*Mem）用 Memory.alloc + 逐字节 writeI8/readUInt8 搬运，
# 故设 MAX_INLINE_BYTES = 4 MiB 上限。超过上限或大图场景请走文件路径
# API（probeFile / decodeFile / saveMem 落盘段），它们直通 C 层零搬运。
# =========================================================================

namespace Image
{
    public class ImageFfi
    {
        # 内存搬运上限（4 MiB）：*Mem 路径的像素/数据块尺寸墙
        # 注：必须带 static——无 static 的 const 在 static 方法里经类名访问
        # 会编译成 LoadNotStaticField（实例字段加载，无 this 栈对象），
        # 运行期取值无效；static const 才走编译期常量内联
        public static const Int32 MAX_INLINE_BYTES = 4194304

        # probe 输出块大小（vm_sl_image.h SLI_PROBE_OUT_BYTES）：
        # 6 × int32 = width / height / srcFormat / srcChannels / hasAlpha / isAnimated
        public static const Int32 PROBE_OUT_BYTES = 24

        static bool _ready = false

        # sli_op_* C 快路径总开关（运行期可变，非 const——避开编译期折叠）：
        # true  = rotate/blend/blendFactor/maskBlend/pasteMasked 走 C 直调
        # false = 走纯 SL 循环兜底（语义等价，较慢）
        # 暂关原因（坑 9）：VM CallFFIStatic fast path 对「本批签名」存在
        # 实参错位（C 返回 true 但未写 out 块，输出为 alloc 残影；DLL 本身
        # P/Invoke 直测正确）—— 待 csimple_lang 修复弹参/封送后置 true。
        # 其余 v2 函数（fill/paste/convolve/resize/convert/chops/grayscale/
        # luma_mean/split/merge/flip/premultiply）实测 C 路径正常，不受此开关影响。
        public static bool opFastPathsEnabled = false

        # ── 生命周期 ─────────────────────────────────────────
        # 幂等初始化（C 层 sli_init 可重入）；首次成功后置位，
        # shutdown() 之后重新走一次即可
        public static bool ensureReady()
        {
            if ImageFfi._ready
            {
                ret true
            }
            ImageFfi._ready = ImageFfi.libInit()
            ret ImageFfi._ready
        }

        public static void shutdown()
        {
            if ImageFfi._ready
            {
                ImageFfi.libUninit()
                ImageFfi._ready = false
            }
        }

        # 最近一次错误文本（SLI_OK 时返回空串）
        public static string lastErrorText()
        {
            Int32 code = ImageFfi.libLastError()
            if code == 0
            {
                ret ""
            }
            string s = ImageFfi.libErrorString( code )
            if s == null
            {
                ret ""
            }
            ret s
        }

        # ═══════════════════════════════════════════════════
        # 1) lib* 直接映射层（22 个 sli_*）
        # ═══════════════════════════════════════════════════

        # ── 生命周期 / 诊断 ──

        @DllStaticImport( "sl_image_lib", "sli_init", "->bool" )
        public static bool libInit()
        {
            ret false
        }

        @DllStaticImport( "sl_image_lib", "sli_uninit", "->bool" )
        public static bool libUninit()
        {
            ret false
        }

        @DllStaticImport( "sl_image_lib", "sli_last_error", "->i32" )
        public static Int32 libLastError()
        {
            ret 0
        }

        @DllStaticImport( "sl_image_lib", "sli_error_string", "i32->utf8" )
        public static string libErrorString( Int32 code )
        {
            ret ""
        }

        @DllStaticImport( "sl_image_lib", "sli_error_detail", "->utf8" )
        public static string libErrorDetail()
        {
            ret ""
        }

        @DllStaticImport( "sl_image_lib", "sli_version_string", "->utf8" )
        public static string libVersionString()
        {
            ret ""
        }

        @DllStaticImport( "sl_image_lib", "sli_codec_list", "->utf8" )
        public static string libCodecList()
        {
            ret ""
        }

        # ── 探测（输出 24 字节块，布局见 PROBE_OUT_BYTES）──

        @DllStaticImport( "sl_image_lib", "sli_probe_file", "utf8,ptr->bool" )
        public static bool libProbeFile( string path, Int64 outPtr )
        {
            ret false
        }

        @DllStaticImport( "sl_image_lib", "sli_probe_mem", "ptr,i64,ptr->bool" )
        public static bool libProbeMem( Int64 dataPtr, Int64 size, Int64 outPtr )
        {
            ret false
        }

        # ── 解码（句柄 1 起始；0 = 失败）──

        @DllStaticImport( "sl_image_lib", "sli_decode_file", "utf8,i32->i64" )
        public static Int64 libDecodeFile( string path, Int32 reqChannels )
        {
            ret 0
        }

        @DllStaticImport( "sl_image_lib", "sli_decode_mem", "ptr,i64,i32->i64" )
        public static Int64 libDecodeMem( Int64 dataPtr, Int64 size, Int32 reqChannels )
        {
            ret 0
        }

        # ── 图像访问 / 释放 ──

        @DllStaticImport( "sl_image_lib", "sli_image_width", "i64->i32" )
        public static Int32 libImageWidth( Int64 img )
        {
            ret 0
        }

        @DllStaticImport( "sl_image_lib", "sli_image_height", "i64->i32" )
        public static Int32 libImageHeight( Int64 img )
        {
            ret 0
        }

        @DllStaticImport( "sl_image_lib", "sli_image_channels", "i64->i32" )
        public static Int32 libImageChannels( Int64 img )
        {
            ret 0
        }

        @DllStaticImport( "sl_image_lib", "sli_image_src_format", "i64->i32" )
        public static Int32 libImageSrcFormat( Int64 img )
        {
            ret 0
        }

        @DllStaticImport( "sl_image_lib", "sli_image_copy_pixels", "i64,ptr,i64->bool" )
        public static bool libImageCopyPixels( Int64 img, Int64 dstPtr, Int64 capBytes )
        {
            ret false
        }

        @DllStaticImport( "sl_image_lib", "sli_image_free", "i64->bool" )
        public static bool libImageFree( Int64 img )
        {
            ret false
        }

        # ── 编码 / blob（sli_encode_mem: fmt, quality, w, h, pixels_ptr）──

        @DllStaticImport( "sl_image_lib", "sli_encode_mem", "i32,i32,i32,i32,ptr->i64" )
        public static Int64 libEncodeMem( Int32 fmt, Int32 quality, Int32 width, Int32 height, Int64 pixelsPtr )
        {
            ret 0
        }

        @DllStaticImport( "sl_image_lib", "sli_blob_size", "i64->i64" )
        public static Int64 libBlobSize( Int64 blob )
        {
            ret 0
        }

        @DllStaticImport( "sl_image_lib", "sli_blob_copy", "i64,ptr,i64->bool" )
        public static bool libBlobCopy( Int64 blob, Int64 dstPtr, Int64 capBytes )
        {
            ret false
        }

        @DllStaticImport( "sl_image_lib", "sli_blob_save", "i64,utf8->bool" )
        public static bool libBlobSave( Int64 blob, string path )
        {
            ret false
        }

        @DllStaticImport( "sl_image_lib", "sli_blob_free", "i64->bool" )
        public static bool libBlobFree( Int64 blob )
        {
            ret false
        }

        # ── 像素批量运算（sli_op_*，14 个；裸指针，无句柄槽）──
        # 像素契约同上（RGBA8 top-down / Gray8 平面 w*h 字节）；
        # 失败返回 false（粘性错误）—— 调用方据此回落纯 SL 循环兜底。
        # 契约详见 vm_sl_image.h「像素批量运算」段。

        @DllStaticImport( "sl_image_lib", "sli_op_convolve3x3", "ptr,ptr,i32,i32,ptr->bool" )
        public static bool libOpConvolve3x3( Int64 srcPtr, Int64 dstPtr, Int32 w, Int32 h, Int64 ctlPtr )
        {
            ret false
        }

        # angleMilliDeg = 度数×1000（i32；规避 VM CallFFIStatic fast path
        # 对 f32 实参的栈封送 bug——坑 9）
        @DllStaticImport( "sl_image_lib", "sli_op_rotate", "ptr,ptr,ptr,i32->bool" )
        public static bool libOpRotate( Int64 srcPtr, Int64 dstPtr, Int64 ctlPtr, Int32 angleMilliDeg )
        {
            ret false
        }

        @DllStaticImport( "sl_image_lib", "sli_op_resize", "ptr,ptr,ptr->bool" )
        public static bool libOpResize( Int64 srcPtr, Int64 dstPtr, Int64 ctlPtr )
        {
            ret false
        }

        @DllStaticImport( "sl_image_lib", "sli_op_alpha_composite", "ptr,ptr,ptr,i32,i32->bool" )
        public static bool libOpAlphaComposite( Int64 dstPtr, Int64 srcPtr, Int64 outPtr, Int32 w, Int32 h )
        {
            ret false
        }

        # alphaX1000 = alpha×1000（0..1000；i32 规避 f32 封送 bug——坑 9）
        @DllStaticImport( "sl_image_lib", "sli_op_blend", "ptr,ptr,ptr,i32,i32,i32->bool" )
        public static bool libOpBlend( Int64 aPtr, Int64 bPtr, Int64 outPtr, Int32 w, Int32 h, Int32 alphaX1000 )
        {
            ret false
        }

        @DllStaticImport( "sl_image_lib", "sli_op_split_rgba", "ptr,ptr,ptr,ptr,ptr,ptr->bool" )
        public static bool libOpSplitRgba( Int64 srcPtr, Int64 rPtr, Int64 gPtr, Int64 bPtr, Int64 aPtr, Int64 ctlPtr )
        {
            ret false
        }

        @DllStaticImport( "sl_image_lib", "sli_op_merge_rgb", "ptr,ptr,ptr,ptr,i32,i32->bool" )
        public static bool libOpMergeRgb( Int64 rPtr, Int64 gPtr, Int64 bPtr, Int64 dstPtr, Int32 w, Int32 h )
        {
            ret false
        }

        @DllStaticImport( "sl_image_lib", "sli_op_merge_rgba", "ptr,ptr,ptr,ptr,ptr,ptr->bool" )
        public static bool libOpMergeRgba( Int64 rPtr, Int64 gPtr, Int64 bPtr, Int64 aPtr, Int64 dstPtr, Int64 ctlPtr )
        {
            ret false
        }

        @DllStaticImport( "sl_image_lib", "sli_op_convert", "ptr,ptr,i32,i32,i32,i32->bool" )
        public static bool libOpConvert( Int64 srcPtr, Int64 dstPtr, Int32 w, Int32 h, Int32 srcFmt, Int32 dstFmt )
        {
            ret false
        }

        @DllStaticImport( "sl_image_lib", "sli_op_paste", "ptr,ptr,ptr->bool" )
        public static bool libOpPaste( Int64 dstPtr, Int64 srcPtr, Int64 ctlPtr )
        {
            ret false
        }

        @DllStaticImport( "sl_image_lib", "sli_op_fill", "ptr,i32,i32,i32->bool" )
        public static bool libOpFill( Int64 dstPtr, Int32 w, Int32 h, Int32 rgba )
        {
            ret false
        }

        @DllStaticImport( "sl_image_lib", "sli_op_flip_y", "ptr,i32,i32->bool" )
        public static bool libOpFlipY( Int64 dstPtr, Int32 w, Int32 h )
        {
            ret false
        }

        @DllStaticImport( "sl_image_lib", "sli_op_flip_x", "ptr,i32,i32->bool" )
        public static bool libOpFlipX( Int64 dstPtr, Int32 w, Int32 h )
        {
            ret false
        }

        @DllStaticImport( "sl_image_lib", "sli_op_premultiply", "ptr,i32,i32,i32->bool" )
        public static bool libOpPremultiply( Int64 dstPtr, Int32 w, Int32 h, Int32 unpre )
        {
            ret false
        }

        # ── 高级合成家族（sli_op_* v2.1：仿 Pillow ImageChops/ImageEnhance/蒙版）──

        @DllStaticImport( "sl_image_lib", "sli_op_grayscale", "ptr,ptr,i32,i32->bool" )
        public static bool libOpGrayscale( Int64 srcPtr, Int64 dstPtr, Int32 w, Int32 h )
        {
            ret false
        }

        @DllStaticImport( "sl_image_lib", "sli_op_luma_mean", "ptr,i32,i32->i32" )
        public static Int32 libOpLumaMean( Int64 srcPtr, Int32 w, Int32 h )
        {
            ret 0
        }

        # op：0 add / 1 subtract / 2 multiply / 3 screen / 4 difference /
        #     5 lighter / 6 darker / 7 invert / 8 softLight / 9 hardLight / 10 overlay
        @DllStaticImport( "sl_image_lib", "sli_op_chops", "i32,ptr,ptr,ptr,i32,i32->bool" )
        public static bool libOpChops( Int32 op, Int64 aPtr, Int64 bPtr, Int64 outPtr, Int32 w, Int32 h )
        {
            ret false
        }

        @DllStaticImport( "sl_image_lib", "sli_op_mask_blend", "ptr,ptr,ptr,ptr,ptr->bool" )
        public static bool libOpMaskBlend( Int64 aPtr, Int64 bPtr, Int64 maskPtr, Int64 outPtr, Int64 ctlPtr )
        {
            ret false
        }

        @DllStaticImport( "sl_image_lib", "sli_op_paste_masked", "ptr,ptr,ptr,ptr->bool" )
        public static bool libOpPasteMasked( Int64 dstPtr, Int64 srcPtr, Int64 maskPtr, Int64 ctlPtr )
        {
            ret false
        }

        # factorX1000 = factor×1000（不钳，外插用；i32 规避 f32 封送 bug——坑 9）
        @DllStaticImport( "sl_image_lib", "sli_op_blend_factor", "ptr,ptr,ptr,i32,i32,i32->bool" )
        public static bool libOpBlendFactor( Int64 aPtr, Int64 bPtr, Int64 outPtr, Int32 w, Int32 h, Int32 factorX1000 )
        {
            ret false
        }

        # ═══════════════════════════════════════════════════
        # 2) 格式映射：EImageFormat <-> SLI_FMT_*（值恒等，显式逐值）
        # ═══════════════════════════════════════════════════

        public static Int32 formatToInt( EImageFormat format )
        {
            if format == EImageFormat.Bmp
            {
                ret 1
            }
            if format == EImageFormat.Png
            {
                ret 2
            }
            if format == EImageFormat.Jpeg
            {
                ret 3
            }
            if format == EImageFormat.Gif
            {
                ret 4
            }
            if format == EImageFormat.Webp
            {
                ret 5
            }
            if format == EImageFormat.Svg
            {
                ret 6
            }
            if format == EImageFormat.Tiff
            {
                ret 7
            }
            if format == EImageFormat.Ico
            {
                ret 8
            }
            if format == EImageFormat.Tga
            {
                ret 9
            }
            if format == EImageFormat.Ppm
            {
                ret 10
            }
            if format == EImageFormat.Avif
            {
                ret 11
            }
            if format == EImageFormat.Heic
            {
                ret 12
            }
            ret 0
        }

        public static EImageFormat intToFormat( Int32 v )
        {
            if v == 1
            {
                ret EImageFormat.Bmp
            }
            if v == 2
            {
                ret EImageFormat.Png
            }
            if v == 3
            {
                ret EImageFormat.Jpeg
            }
            if v == 4
            {
                ret EImageFormat.Gif
            }
            if v == 5
            {
                ret EImageFormat.Webp
            }
            if v == 6
            {
                ret EImageFormat.Svg
            }
            if v == 7
            {
                ret EImageFormat.Tiff
            }
            if v == 8
            {
                ret EImageFormat.Ico
            }
            if v == 9
            {
                ret EImageFormat.Tga
            }
            if v == 10
            {
                ret EImageFormat.Ppm
            }
            if v == 11
            {
                ret EImageFormat.Avif
            }
            if v == 12
            {
                ret EImageFormat.Heic
            }
            ret EImageFormat.Unknown
        }

        # ═══════════════════════════════════════════════════
        # 内部搬运辅助（私有）
        # ═══════════════════════════════════════════════════

        # Array<UInt8> -> 新分配原生块（count 字节，逐字节 writeI8）；
        # 返回 0 = 拒绝或分配失败（调用方持有释放权）
        # （Gif.sl 复用，故 public）
        public static Int64 _copyIn( Array<UInt8> bytes, Int32 count )
        {
            if bytes == null || count <= 0 || count > bytes.length
            {
                ret 0
            }
            if count > ImageFfi.MAX_INLINE_BYTES
            {
                ret 0
            }
            Int64 ptr = Memory.alloc( count )
            if ptr == 0
            {
                ret 0
            }
            Int32 i = 0
            while i < count
            {
                Memory.writeI8( ptr, i, SystemConvertInt32( bytes[ i ] ) )
                i = i + 1
            }
            ret ptr
        }

        # 原生块 -> 新 Array<UInt8>（count 字节，逐字节 readUInt8）
        # （Gif.sl 复用，故 public）
        public static Array<UInt8> _copyOut( Int64 ptr, Int32 count )
        {
            if ptr == 0 || count <= 0
            {
                ret null
            }
            Array<UInt8> result = Array<UInt8>( count )
            Int32 i = 0
            while i < count
            {
                result[ i ] = SystemConvertUInt8( Memory.readUInt8( ptr, i ) )
                i = i + 1
            }
            ret result
        }

        # probe 输出块（24 字节）-> ImageInfo
        static ImageInfo _infoFromProbe( Int64 outPtr, Int64 byteSize )
        {
            ImageInfo info = ImageInfo()
            if outPtr == 0
            {
                ret info
            }
            info.width = Memory.readInt32( outPtr, 0 )
            info.height = Memory.readInt32( outPtr, 4 )
            info.format = ImageFfi.intToFormat( Memory.readInt32( outPtr, 8 ) )
            Int32 ch = Memory.readInt32( outPtr, 12 )
            if Memory.readInt32( outPtr, 16 ) != 0
            {
                info.hasAlpha = true
            }
            else
            {
                info.hasAlpha = false
            }
            if Memory.readInt32( outPtr, 20 ) != 0
            {
                info.isAnimated = true
            }
            else
            {
                info.isAnimated = false
            }
            info.bitDepth = 8
            info.frameCount = 1
            info.colorSpace = EColorSpace.SRGB
            info.byteSize = byteSize
            if ch == 1 || ch == 2
            {
                info.pixelFormat = EPixelFormat.Gray8
            }
            elif ch == 3
            {
                info.pixelFormat = EPixelFormat.Rgb8
            }
            else
            {
                info.pixelFormat = EPixelFormat.Rgba8
            }
            ret info
        }

        # 图像句柄 -> ImageBuffer（RGBA8，top-down）；总是释放句柄
        static ImageBuffer _takeImage( Int64 img )
        {
            if img == 0
            {
                ret null
            }
            ImageBuffer buf = null
            Int32 w = ImageFfi.libImageWidth( img )
            Int32 h = ImageFfi.libImageHeight( img )
            Int32 need = w * h * 4
            if w > 0 && h > 0 && need > 0 && need <= ImageFfi.MAX_INLINE_BYTES
            {
                Int64 dst = Memory.alloc( need )
                if dst != 0
                {
                    if ImageFfi.libImageCopyPixels( img, dst, need )
                    {
                        buf = ImageBuffer( w, h )
                        Array<UInt8> pixels = buf.pixelBytes()
                        Int32 i = 0
                        while i < need
                        {
                            pixels[ i ] = SystemConvertUInt8( Memory.readUInt8( dst, i ) )
                            i = i + 1
                        }
                    }
                    Memory.free( dst )
                }
            }
            ImageFfi.libImageFree( img )
            ret buf
        }

        # ═══════════════════════════════════════════════════
        # 3) 便利层
        # ═══════════════════════════════════════════════════

        # ImageBuffer -> 紧密 RGBA8 像素块（编码 / 落盘的 C 层入参契约）；
        # 非 RGBA8 先经 convertTo 转换；buffer 无效返回 null
        public static Array<UInt8> rgbaBytesOf( ImageBuffer buffer )
        {
            if buffer == null || !buffer.isValid
            {
                ret null
            }
            if buffer.pixelFormat == EPixelFormat.Rgba8
            {
                ret buffer.pixelBytes()
            }
            ImageBuffer rgba = buffer.convertTo( EPixelFormat.Rgba8 )
            if rgba == null
            {
                ret null
            }
            ret rgba.pixelBytes()
        }

        # ── sli_op_* 快路径搬运辅助（ImageBuffer/ImageFilter 复用，故 public）──

        # 原生块 -> 已有 Array<UInt8> 就地回填（不再分配新数组）
        public static bool _fillBytes( Int64 ptr, Array<UInt8> bytes, Int32 count )
        {
            if ptr == 0 || bytes == null || count <= 0 || count > bytes.length
            {
                ret false
            }
            Int32 i = 0
            while i < count
            {
                bytes[ i ] = SystemConvertUInt8( Memory.readUInt8( ptr, i ) )
                i = i + 1
            }
            ret true
        }

        # int32 控制块写入（自偏移 0 起逐个 writeI32）
        public static bool _writeCtl( Int64 ptr, Array<Int32> values )
        {
            if ptr == 0 || values == null
            {
                ret false
            }
            Int32 i = 0
            while i < values.length
            {
                Memory.writeI32( ptr, i * 4, values[ i ] )
                i = i + 1
            }
            ret true
        }

        # ImageBuffer（任意格式）-> 原生 RGBA8 块（含格式转换）；
        # 0 = 无效 / 超 MAX_INLINE_BYTES / 分配失败（调用方持有释放权）
        public static Int64 _uploadRgba( ImageBuffer buffer )
        {
            Array<UInt8> rgba = ImageFfi.rgbaBytesOf( buffer )
            if rgba == null
            {
                ret 0
            }
            ret ImageFfi._copyIn( rgba, rgba.length )
        }

        # EPixelFormat -> C 层 fmt id（显式逐值；浮点格式 9/10 返回 0 =
        # 不支持，调用方回落 SL 循环）
        public static Int32 fmtToInt( EPixelFormat fmt )
        {
            if fmt == EPixelFormat.Gray8 { ret 1 }
            if fmt == EPixelFormat.Gray16 { ret 2 }
            if fmt == EPixelFormat.Rgb8 { ret 3 }
            if fmt == EPixelFormat.Rgba8 { ret 4 }
            if fmt == EPixelFormat.Bgr8 { ret 5 }
            if fmt == EPixelFormat.Bgra8 { ret 6 }
            if fmt == EPixelFormat.Rgb16 { ret 7 }
            if fmt == EPixelFormat.Rgba16 { ret 8 }
            ret 0
        }

        # ── 文件路径（零搬运直通 C 层，推荐入口）────────────

        # 探测文件头；失败返回空 ImageInfo（width == 0 可判）
        public static ImageInfo probeFile( string path )
        {
            if !ImageFfi.ensureReady()
            {
                ret ImageInfo()
            }
            if path == null || path == ""
            {
                ret ImageInfo()
            }
            Int32 probeBytes = ImageFfi.PROBE_OUT_BYTES
            Int64 probeOut = Memory.alloc( probeBytes )
            if probeOut == 0
            {
                ret ImageInfo()
            }
            ImageInfo info = ImageInfo()
            if ImageFfi.libProbeFile( path, probeOut )
            {
                info = ImageFfi._infoFromProbe( probeOut, 0 )
            }
            Memory.free( probeOut )
            ret info
        }

        # 解码文件 -> ImageBuffer（恒 RGBA8）；失败返回 null
        public static ImageBuffer decodeFile( string path )
        {
            if !ImageFfi.ensureReady()
            {
                ret null
            }
            if path == null || path == ""
            {
                ret null
            }
            ret ImageFfi._takeImage( ImageFfi.libDecodeFile( path, 4 ) )
        }

        # ── 内存 bytes（逐字节搬运，<= MAX_INLINE_BYTES）────

        # 探测内存数据；失败返回空 ImageInfo
        public static ImageInfo probeMem( Array<UInt8> bytes )
        {
            if !ImageFfi.ensureReady()
            {
                ret ImageInfo()
            }
            if bytes == null || bytes.length < 8
            {
                ret ImageInfo()
            }
            Int64 src = ImageFfi._copyIn( bytes, bytes.length )
            if src == 0
            {
                ret ImageInfo()
            }
            Int32 probeBytes = ImageFfi.PROBE_OUT_BYTES
            Int64 probeOut = Memory.alloc( probeBytes )
            ImageInfo info = ImageInfo()
            if probeOut != 0
            {
                if ImageFfi.libProbeMem( src, bytes.length, probeOut )
                {
                    info = ImageFfi._infoFromProbe( probeOut, bytes.length )
                }
                Memory.free( probeOut )
            }
            Memory.free( src )
            ret info
        }

        # 解码内存数据 -> ImageBuffer（恒 RGBA8）；失败返回 null
        public static ImageBuffer decodeMem( Array<UInt8> bytes )
        {
            if !ImageFfi.ensureReady()
            {
                ret null
            }
            if bytes == null || bytes.length < 8
            {
                ret null
            }
            Int64 src = ImageFfi._copyIn( bytes, bytes.length )
            if src == 0
            {
                ret null
            }
            Int64 img = ImageFfi.libDecodeMem( src, bytes.length, 4 )
            Memory.free( src )
            ret ImageFfi._takeImage( img )
        }

        # RGBA8 像素 -> 编码字节流（PNG/JPEG/BMP/TGA/PPM/TIFF）；
        # 失败返回 null。入参必须已是紧密 RGBA8（stride = w * 4）
        public static Array<UInt8> encodeMem( EImageFormat format, Int32 quality, Int32 width, Int32 height, Array<UInt8> rgbaBytes )
        {
            if !ImageFfi.ensureReady()
            {
                ret null
            }
            if rgbaBytes == null || width <= 0 || height <= 0
            {
                ret null
            }
            Int32 need = width * height * 4
            if rgbaBytes.length < need
            {
                ret null
            }
            Int64 src = ImageFfi._copyIn( rgbaBytes, need )
            if src == 0
            {
                ret null
            }
            Int64 blob = ImageFfi.libEncodeMem( ImageFfi.formatToInt( format ), quality, width, height, src )
            Memory.free( src )
            if blob == 0
            {
                ret null
            }
            Array<UInt8> result = null
            Int64 size = ImageFfi.libBlobSize( blob )
            if size > 0 && size <= ImageFfi.MAX_INLINE_BYTES
            {
                Int64 dst = Memory.alloc( SystemConvertInt32( size ) )
                if dst != 0
                {
                    if ImageFfi.libBlobCopy( blob, dst, size )
                    {
                        result = ImageFfi._copyOut( dst, SystemConvertInt32( size ) )
                    }
                    Memory.free( dst )
                }
            }
            ImageFfi.libBlobFree( blob )
            ret result
        }

        # RGBA8 像素 -> 编码落盘（blob 直写文件，无回读搬运，不受
        # MAX_INLINE_BYTES 限制）；失败返回 false
        public static bool saveMem( EImageFormat format, Int32 quality, Int32 width, Int32 height, Array<UInt8> rgbaBytes, string path )
        {
            if !ImageFfi.ensureReady()
            {
                ret false
            }
            if rgbaBytes == null || width <= 0 || height <= 0 || path == null
            {
                ret false
            }
            Int32 need = width * height * 4
            if rgbaBytes.length < need
            {
                ret false
            }
            Int64 src = ImageFfi._copyIn( rgbaBytes, need )
            if src == 0
            {
                ret false
            }
            Int64 blob = ImageFfi.libEncodeMem( ImageFfi.formatToInt( format ), quality, width, height, src )
            Memory.free( src )
            if blob == 0
            {
                ret false
            }
            bool ok = ImageFfi.libBlobSave( blob, path )
            ImageFfi.libBlobFree( blob )
            ret ok
        }
    }
}
