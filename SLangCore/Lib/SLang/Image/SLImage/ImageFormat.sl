# =========================================================================
# Image/ImageFormat.sl —— 图像格式 / 像素格式 / 色彩空间 / 错误码
#
# 约定（与 DB/Sqlite.sl 保持一致）：
#   - 所有类型必须是 namespace 下的顶级类型，**不能嵌套在类内**
#     （嵌套类型会让导出端把父类全名写进 namespaceList，加载端随即创建
#       同名命名空间节点遮蔽类节点，导致调用链解析失败）
#   - 编解码本体由 ImageFfi（sl_image_lib.dll：stb/WIC，@DllStaticImport
#     静态绑定）实现；本目录负责：数据模型 + 能用纯 SL 算出来的部分
#     （magic 嗅探、PNG/BMP 头解析、像素运算、缩放、色彩转换…）
# =========================================================================

namespace Image
{
    # ---------------------------------------------------------------
    # 容器 / 文件格式
    # ---------------------------------------------------------------
    public enum EImageFormat
    {
        Unknown = 0
        Bmp = 1
        Png = 2
        Jpeg = 3
        Gif = 4
        Webp = 5
        Svg = 6
        Tiff = 7
        Ico = 8
        Tga = 9
        Ppm = 10
        Avif = 11
        Heic = 12
    }

    # ---------------------------------------------------------------
    # 像素排布（ImageBuffer 的内存布局）
    #   Gray8/Gray16: 1 通道 8/16 位；Rgb8/Rgba8: 3/4 通道 8 位（Rgba8 默认）
    #   Bgr8/Bgra8: 蓝在前；Rgb16/Rgba16: 16 位；Rgb32F/Rgba32F: Float32（HDR）
    # ---------------------------------------------------------------
    public enum EPixelFormat
    {
        Unknown = 0
        Gray8 = 1
        Gray16 = 2
        Rgb8 = 3
        Rgba8 = 4
        Bgr8 = 5
        Bgra8 = 6
        Rgb16 = 7
        Rgba16 = 8
        Rgb32F = 9
        Rgba32F = 10
    }

    # ---------------------------------------------------------------
    # 色彩空间
    # ---------------------------------------------------------------
    public enum EColorSpace
    {
        Unknown = 0
        SRGB = 1
        Linear = 2
        DisplayP3 = 3
        Rec709 = 4
        AdobeRgb = 5
    }

    # ---------------------------------------------------------------
    # 缩放插值
    # ---------------------------------------------------------------
    public enum EInterpolation
    {
        Nearest = 0
        Bilinear = 1
        Bicubic = 2
        Lanczos = 3
    }

    # ---------------------------------------------------------------
    # EXIF Orientation（1..8），JPEG 常见
    # ---------------------------------------------------------------
    public enum EOrientation
    {
        Normal = 1
        MirrorHorizontal = 2
        Rotate180 = 3
        MirrorVertical = 4
        MirrorHorizontalRotate270 = 5
        Rotate90 = 6
        MirrorHorizontalRotate90 = 7
        Rotate270 = 8
    }

    # ---------------------------------------------------------------
    # 错误码
    # ---------------------------------------------------------------
    public enum ImageErrorCode extends Error
    {
        OK = {code = 0}
        UnsupportedFormat = {code = 1}
        DecodeFailed = {code = 2}
        EncodeFailed = {code = 3}
        InvalidData = {code = 4}
        OutOfBounds = {code = 5}
        CodecMissing = {code = 6}
        IoError = {code = 7}
    }
}
