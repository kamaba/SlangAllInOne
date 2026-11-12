# =========================================================================
# Image/ImageIO.sl —— 图像模块门面（统一入口）
#
# 用法：
#   ImageBuffer img = Image.ImageIO.load( "a.png" )
#   Image.ImageIO.save( img, "out.webp", EImageFormat.Webp, 80 )
#   ImageBuffer thumb = Image.ImageIO.thumbnail( img, 256, 256 )
#
# 纯 SL：thumbnail（等比缩放到框内）、格式能力表、MIME / 扩展名映射
# 后端：  ImageFfi（sl_image_lib.dll：stb_image / stb_image_write + WIC）
# =========================================================================

namespace Image
{
    public class ImageIO
    {
        # ── 识别 ─────────────────────────────────────────────
        # 按内容判定（推荐：扩展名不可信）
        public static EImageFormat detectFormat( Array<UInt8> bytes )
        {
            ret ImageInfo.sniff( bytes )
        }

        # 按扩展名判定（无法读取内容时的兜底）
        public static EImageFormat formatOfPath( string path )
        {
            ret ImageInfo.fromExtension( path )
        }

        # 不解码像素，只取宽高等元数据
        public static ImageInfo probe( Array<UInt8> bytes )
        {
            ret ImageInfo.probe( bytes )
        }

        # 按路径探测（C 层读文件头，零搬运；失败返回空 ImageInfo）
        public static ImageInfo probeFile( string path )
        {
            ret ImageFfi.probeFile( path )
        }

        # ── 解码 / 编码 ─────────────────────────────────────
        public static ImageBuffer decode( Array<UInt8> bytes )
        {
            ret ImageBuffer.decode( bytes )
        }

        # 指定格式走对应子模块（后端会据此选用解码器）
        public static ImageBuffer decode( Array<UInt8> bytes, EImageFormat format )
        {
            if bytes == null
            {
                ret null
            }
            if format == EImageFormat.Png
            {
                ret Png.decode( bytes )
            }
            if format == EImageFormat.Jpeg
            {
                ret Jpeg.decode( bytes )
            }
            if format == EImageFormat.Webp
            {
                ret Webp.decode( bytes )
            }
            # C 层按内容自动嗅探（format 仅为提示，stb/WIC 不需要它）
            ret ImageFfi.decodeMem( bytes )
        }

        # quality 仅对有损格式（JPEG / WebP / AVIF / HEIC）有意义
        public static Array<UInt8> encode( ImageBuffer buffer, EImageFormat format, Int32 quality )
        {
            if buffer == null
            {
                ret null
            }
            if format == EImageFormat.Png
            {
                ret Png.encode( buffer )
            }
            if format == EImageFormat.Jpeg
            {
                ret Jpeg.encode( buffer, JpegEncodeOptions.ofQuality( quality ) )
            }
            if format == EImageFormat.Webp
            {
                WebpEncodeOptions o = WebpEncodeOptions()
                o.lossless = false
                o.quality = quality
                o.clamp()
                ret Webp.encode( buffer, o )
            }
            # 兜底格式（BMP/TGA/PPM/TIFF 等）走 C 层 stb/WIC 编码
            Array<UInt8> rgba = ImageFfi.rgbaBytesOf( buffer )
            if rgba == null
            {
                ret null
            }
            ret ImageFfi.encodeMem( format, quality, buffer.width, buffer.height, rgba )
        }

        # ── 文件 ─────────────────────────────────────────────
        public static ImageBuffer load( string path )
        {
            ret ImageFfi.decodeFile( path )
        }

        public static bool save( ImageBuffer buffer, string path, EImageFormat format, Int32 quality )
        {
            if buffer == null || path == null
            {
                ret false
            }
            # blob 直写文件（无回读搬运，不受 4 MiB 上限限制）
            Array<UInt8> rgba = ImageFfi.rgbaBytesOf( buffer )
            if rgba == null
            {
                ret false
            }
            ret ImageFfi.saveMem( format, quality, buffer.width, buffer.height, rgba, path )
        }

        # 按扩展名推断保存格式
        public static bool save( ImageBuffer buffer, string path, Int32 quality )
        {
            ret ImageIO.save( buffer, path, ImageInfo.fromExtension( path ), quality )
        }

        # ── 缩略图（纯 SL：等比缩放并装进 maxW × maxH 的框）──
        public static ImageBuffer thumbnail( ImageBuffer src, Int32 maxWidth, Int32 maxHeight )
        {
            if src == null || !src.isValid
            {
                ret null
            }
            if maxWidth <= 0 || maxHeight <= 0
            {
                ret null
            }
            Float32 sw = 1.0f * src.width
            Float32 sh = 1.0f * src.height
            Float32 scale = 1.0f * maxWidth / sw
            Float32 scaleY = 1.0f * maxHeight / sh
            if scaleY < scale
            {
                scale = scaleY
            }
            if scale > 1.0f
            {
                # 不放大，只缩小
                scale = 1.0f
            }
            Int32 nw = SystemConvertInt32( sw * scale )
            Int32 nh = SystemConvertInt32( sh * scale )
            if nw <= 0 { nw = 1 }
            if nh <= 0 { nh = 1 }
            ret src.resize( nw, nh, EInterpolation.Bilinear )
        }

        # ── 格式能力表（纯 SL）──────────────────────────────
        public static bool supportsAlpha( EImageFormat format )
        {
            if format == EImageFormat.Png || format == EImageFormat.Webp ||
               format == EImageFormat.Gif || format == EImageFormat.Tiff ||
               format == EImageFormat.Ico || format == EImageFormat.Tga ||
               format == EImageFormat.Avif || format == EImageFormat.Heic ||
               format == EImageFormat.Svg
            {
                ret true
            }
            ret false
        }

        public static bool isAnimated( EImageFormat format )
        {
            if format == EImageFormat.Gif
            {
                ret true
            }
            if format == EImageFormat.Webp
            {
                ret true
            }
            if format == EImageFormat.Avif
            {
                ret true
            }
            if format == EImageFormat.Heic
            {
                ret true
            }
            ret false
        }

        public static bool isLossy( EImageFormat format )
        {
            if format == EImageFormat.Jpeg
            {
                ret true
            }
            if format == EImageFormat.Webp
            {
                ret true
            }
            if format == EImageFormat.Avif
            {
                ret true
            }
            if format == EImageFormat.Heic
            {
                ret true
            }
            ret false
        }

        # 矢量格式：需要光栅化才能拿到位图
        public static bool isVector( EImageFormat format )
        {
            ret format == EImageFormat.Svg
        }

        # 是否需要外部解码库（BMP / PPM 用纯 SL 也能解）
        public static bool needsNativeCodec( EImageFormat format )
        {
            if format == EImageFormat.Png || format == EImageFormat.Jpeg ||
               format == EImageFormat.Webp || format == EImageFormat.Gif ||
               format == EImageFormat.Avif || format == EImageFormat.Heic ||
               format == EImageFormat.Svg
            {
                ret true
            }
            ret false
        }

        public static string mimeType( EImageFormat format )
        {
            if format == EImageFormat.Png  { ret "image/png" }
            if format == EImageFormat.Jpeg { ret "image/jpeg" }
            if format == EImageFormat.Gif  { ret "image/gif" }
            if format == EImageFormat.Webp { ret "image/webp" }
            if format == EImageFormat.Svg  { ret "image/svg+xml" }
            if format == EImageFormat.Bmp  { ret "image/bmp" }
            if format == EImageFormat.Tiff { ret "image/tiff" }
            if format == EImageFormat.Ico  { ret "image/x-icon" }
            if format == EImageFormat.Avif { ret "image/avif" }
            if format == EImageFormat.Heic { ret "image/heic" }
            if format == EImageFormat.Tga  { ret "image/x-tga" }
            if format == EImageFormat.Ppm  { ret "image/x-portable-pixmap" }
            ret "application/octet-stream"
        }

        # 首选扩展名（含点号）
        public static string extension( EImageFormat format )
        {
            if format == EImageFormat.Png  { ret ".png" }
            if format == EImageFormat.Jpeg { ret ".jpg" }
            if format == EImageFormat.Gif  { ret ".gif" }
            if format == EImageFormat.Webp { ret ".webp" }
            if format == EImageFormat.Svg  { ret ".svg" }
            if format == EImageFormat.Bmp  { ret ".bmp" }
            if format == EImageFormat.Tiff { ret ".tiff" }
            if format == EImageFormat.Ico  { ret ".ico" }
            if format == EImageFormat.Avif { ret ".avif" }
            if format == EImageFormat.Heic { ret ".heic" }
            if format == EImageFormat.Tga  { ret ".tga" }
            if format == EImageFormat.Ppm  { ret ".ppm" }
            ret ""
        }

        override string toString()
        {
            ret "ImageIO"
        }
    }
}
