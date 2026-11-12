# =========================================================================
# Image/Jpeg.sl —— JPEG（JFIF / EXIF）容器模型
#
# 纯 SL 实现：
#   - MPEG 帧头位域解析（4 字节 -> 版本 / 层 / 码率 / 采样率 / 声道 / 填充）
#   - 码率表与采样率表查表、帧长计算
#   - ID3v2 头识别与 **syncsafe 整数** 解码（每个字节只用低 7 位）
# 依赖后端：
#   - decode / encode（Huffman 解码 + IDCT）
#   - EXIF / JFIF 段遍历
# =========================================================================

namespace Image
{
    public enum EMpegVersion
    {
        Mpeg25 = 0
        Reserved = 1
        Mpeg2 = 2
        Mpeg1 = 3
    }

    public enum EMpegLayer
    {
        Reserved = 0
        Layer3 = 1
        Layer2 = 2
        Layer1 = 3
    }

    public enum EMpegChannelMode
    {
        Stereo = 0
        JointStereo = 1
        DualChannel = 2
        Mono = 3
    }

    # 色度下采样（JPEG 编码选项）：0=不采样 1=水平1/2 2=水平垂直各1/2（常用）
    public enum EChromaSubsampling
    {
        S444 = 0
        S422 = 1
        S420 = 2
        S440 = 3
        S411 = 4
    }

    public enum EJpegMode
    {
        Baseline = 0
        Progressive = 1
        Lossless = 2
    }

    # ── 帧头（音频侧复用同一套 MPEG 帧结构）────────────────
    public class JpegFrameHeader
    {
        public EMpegVersion version = EMpegVersion.Mpeg1
        public EMpegLayer layer = EMpegLayer.Layer3
        public Int32 bitrateKbps = 0
        public Int32 sampleRate = 0
        public EMpegChannelMode channelMode = EMpegChannelMode.Stereo
        public Int32 padding = 0
        public bool hasCrc = false
        public Int32 frameLength = 0

        _init_()
        {
            this.version = EMpegVersion.Mpeg1
            this.layer = EMpegLayer.Layer3
            this.bitrateKbps = 0
            this.sampleRate = 0
            this.channelMode = EMpegChannelMode.Stereo
            this.padding = 0
            this.hasCrc = false
            this.frameLength = 0
        }

        public get bool isValid()
        {
            ret this.bitrateKbps > 0 && this.sampleRate > 0 && this.frameLength > 0
        }

        public get Int32 channelCount()
        {
            if this.channelMode == EMpegChannelMode.Mono
            {
                ret 1
            }
            ret 2
        }

        override string toString()
        {
            string s = "MpegFrame("
            s = s + this.bitrateKbps.toString() + "kbps"
            s = s + ", " + this.sampleRate.toString() + "Hz"
            s = s + ", len=" + this.frameLength.toString() + ")"
            ret s
        }
    }

    # ── EXIF ───────────────────────────────────────────────
    public class JpegExif
    {
        public EOrientation orientation = EOrientation.Normal
        public string make = ""
        public string model = ""
        public string dateTime = ""
        public Int32 iso = 0
        public Float32 exposureTime = 0.0f
        public Float32 fNumber = 0.0f
        public Float32 focalLength = 0.0f

        _init_()
        {
            this.orientation = EOrientation.Normal
            this.make = ""
            this.model = ""
            this.dateTime = ""
            this.iso = 0
            this.exposureTime = 0.0f
            this.fNumber = 0.0f
            this.focalLength = 0.0f
        }

        public get bool hasOrientation()
        {
            ret this.orientation != EOrientation.Normal
        }

        override string toString()
        {
            string s = "JpegExif(orient=" + this.orientation.toString()
            s = s + ", " + this.make + " " + this.model + ")"
            ret s
        }
    }

    # ── 编码参数 ───────────────────────────────────────────
    public class JpegEncodeOptions
    {
        # 1..100，100 质量最高体积最大
        public Int32 quality = 85
        public EChromaSubsampling subsampling = EChromaSubsampling.S420
        public EJpegMode mode = EJpegMode.Baseline
        public bool optimizeHuffman = true
        # 重启间隔（MCU 数），0 = 关闭；非 0 便于并行解码与抗损坏
        public Int32 restartInterval = 0

        _init_()
        {
            this.quality = 85
            this.subsampling = EChromaSubsampling.S420
            this.mode = EJpegMode.Baseline
            this.optimizeHuffman = true
            this.restartInterval = 0
        }

        public void clamp()
        {
            if this.quality < 1 { this.quality = 1 }
            if this.quality > 100 { this.quality = 100 }
            if this.restartInterval < 0 { this.restartInterval = 0 }
        }

        public static JpegEncodeOptions defaultOptions()
        {
            ret JpegEncodeOptions()
        }

        public static JpegEncodeOptions ofQuality( Int32 q )
        {
            JpegEncodeOptions o = JpegEncodeOptions()
            o.quality = q
            o.clamp()
            ret o
        }

        # 高质量：4:4:4 + 优化 Huffman
        public static JpegEncodeOptions highQuality()
        {
            JpegEncodeOptions o = JpegEncodeOptions()
            o.quality = 95
            o.subsampling = EChromaSubsampling.S444
            o.optimizeHuffman = true
            ret o
        }
    }

    public class JpegDecodeOptions
    {
        # DCT 缩放输出：只解出 1/num 尺寸（1/1、1/2、1/4、1/8），省 CPU
        public Int32 scaleNumerator = 1
        public Int32 scaleDenominator = 1
        public bool forceRgba = true
        # 是否应用 EXIF Orientation 自动旋转
        public bool applyOrientation = true

        _init_()
        {
            this.scaleNumerator = 1
            this.scaleDenominator = 1
            this.forceRgba = true
            this.applyOrientation = true
        }

        public static JpegDecodeOptions defaultOptions()
        {
            ret JpegDecodeOptions()
        }

        # 缩略图场景：1/4 尺寸
        public static JpegDecodeOptions quarter()
        {
            JpegDecodeOptions o = JpegDecodeOptions()
            o.scaleNumerator = 1
            o.scaleDenominator = 4
            ret o
        }
    }

    # ── JPEG 门面 ──────────────────────────────────────────
    public class Jpeg
    {
        # ── 采样率表（纯 SL 查表）──────────────────────────
        public static Int32 sampleRateOf( EMpegVersion version, Int32 index )
        {
            if index < 0 || index > 3
            {
                ret 0
            }
            if version == EMpegVersion.Mpeg1
            {
                if index == 0 { ret 44100 }
                if index == 1 { ret 48000 }
                if index == 2 { ret 32000 }
                ret 0
            }
            if version == EMpegVersion.Mpeg2
            {
                if index == 0 { ret 22050 }
                if index == 1 { ret 24000 }
                if index == 2 { ret 16000 }
                ret 0
            }
            if version == EMpegVersion.Mpeg25
            {
                if index == 0 { ret 11025 }
                if index == 1 { ret 12000 }
                if index == 2 { ret 8000 }
                ret 0
            }
            ret 0
        }

        # ── 码率表（kbps）──────────────────────────────────
        # index 1..14 有效；0 = free，15 = 非法
        public static Int32 bitrateOf( EMpegVersion version, EMpegLayer layer, Int32 index )
        {
            if index <= 0 || index >= 15
            {
                ret 0
            }
            bool isV1 = version == EMpegVersion.Mpeg1

            # MPEG1 Layer3（MP3 最常见）
            if isV1 && layer == EMpegLayer.Layer3
            {
                if index == 1 { ret 32 }
                if index == 2 { ret 40 }
                if index == 3 { ret 48 }
                if index == 4 { ret 56 }
                if index == 5 { ret 64 }
                if index == 6 { ret 80 }
                if index == 7 { ret 96 }
                if index == 8 { ret 112 }
                if index == 9 { ret 128 }
                if index == 10 { ret 160 }
                if index == 11 { ret 192 }
                if index == 12 { ret 224 }
                if index == 13 { ret 256 }
                if index == 14 { ret 320 }
                ret 0
            }

            # MPEG2 / 2.5 Layer1
            if !isV1 && layer == EMpegLayer.Layer1
            {
                if index == 1 { ret 32 }
                if index == 2 { ret 48 }
                if index == 3 { ret 56 }
                if index == 4 { ret 64 }
                if index == 5 { ret 80 }
                if index == 6 { ret 96 }
                if index == 7 { ret 112 }
                if index == 8 { ret 128 }
                if index == 9 { ret 144 }
                if index == 10 { ret 160 }
                if index == 11 { ret 176 }
                if index == 12 { ret 192 }
                if index == 13 { ret 224 }
                if index == 14 { ret 256 }
                ret 0
            }

            # MPEG2 / 2.5 Layer2 & Layer3（同一张表）
            if !isV1
            {
                if index == 1 { ret 8 }
                if index == 2 { ret 16 }
                if index == 3 { ret 24 }
                if index == 4 { ret 32 }
                if index == 5 { ret 40 }
                if index == 6 { ret 48 }
                if index == 7 { ret 56 }
                if index == 8 { ret 64 }
                if index == 9 { ret 80 }
                if index == 10 { ret 96 }
                if index == 11 { ret 112 }
                if index == 12 { ret 128 }
                if index == 13 { ret 144 }
                if index == 14 { ret 160 }
                ret 0
            }

            # MPEG1 Layer1 / Layer2（其余，按常用值近似）
            if layer == EMpegLayer.Layer1
            {
                ret index * 32
            }
            if index == 1 { ret 32 }
            if index == 2 { ret 48 }
            if index == 3 { ret 56 }
            if index == 4 { ret 64 }
            if index == 5 { ret 80 }
            if index == 6 { ret 96 }
            if index == 7 { ret 112 }
            if index == 8 { ret 128 }
            if index == 9 { ret 160 }
            if index == 10 { ret 192 }
            if index == 11 { ret 224 }
            if index == 12 { ret 256 }
            if index == 13 { ret 320 }
            if index == 14 { ret 384 }
            ret 0
        }

        # ── 4 字节 MPEG 帧头解析（纯 SL 位域）───────────────
        #
        #   byte0       byte1              byte2                    byte3
        #   11111111    111VVLLP           BBBBSSPD                 MMEECOOE
        #
        #   VV 版本  LL 层  P CRC    BBBB 码率索引  SS 采样率索引
        #   P 填充   D 私有  MM 声道模式
        #
        public static JpegFrameHeader readFrameHeader( Array<UInt8> bytes, Int32 offset )
        {
            JpegFrameHeader h = JpegFrameHeader()
            if bytes == null || offset < 0 || offset + 4 > bytes.length
            {
                ret h
            }
            Int32 b0 = ImageInfo.readU8( bytes, offset )
            Int32 b1 = ImageInfo.readU8( bytes, offset + 1 )
            Int32 b2 = ImageInfo.readU8( bytes, offset + 2 )
            Int32 b3 = ImageInfo.readU8( bytes, offset + 3 )

            # 同步字：11 个 1
            if b0 != 0xFF || ( b1 & 0xE0 ) != 0xE0
            {
                ret h
            }

            Int32 v = ( b1 >> 3 ) & 0x03
            if v == 0 { h.version = EMpegVersion.Mpeg25 }
            elif v == 2 { h.version = EMpegVersion.Mpeg2 }
            elif v == 3 { h.version = EMpegVersion.Mpeg1 }
            else { h.version = EMpegVersion.Reserved }

            Int32 l = ( b1 >> 1 ) & 0x03
            if l == 1 { h.layer = EMpegLayer.Layer3 }
            elif l == 2 { h.layer = EMpegLayer.Layer2 }
            elif l == 3 { h.layer = EMpegLayer.Layer1 }
            else { h.layer = EMpegLayer.Reserved }

            h.hasCrc = ( b1 & 0x01 ) == 0

            Int32 bitrateIndex = ( b2 >> 4 ) & 0x0F
            Int32 rateIndex = ( b2 >> 2 ) & 0x03
            h.padding = ( b2 >> 1 ) & 0x01

            Int32 cm = ( b3 >> 6 ) & 0x03
            if cm == 0 { h.channelMode = EMpegChannelMode.Stereo }
            elif cm == 1 { h.channelMode = EMpegChannelMode.JointStereo }
            elif cm == 2 { h.channelMode = EMpegChannelMode.DualChannel }
            else { h.channelMode = EMpegChannelMode.Mono }

            h.bitrateKbps = Jpeg.bitrateOf( h.version, h.layer, bitrateIndex )
            h.sampleRate = Jpeg.sampleRateOf( h.version, rateIndex )
            h.frameLength = Jpeg.frameLengthOf( h )

            ret h
        }

        # 帧长（字节）
        public static Int32 frameLengthOf( JpegFrameHeader h )
        {
            if h == null || h.bitrateKbps <= 0 || h.sampleRate <= 0
            {
                ret 0
            }
            Int32 bps = h.bitrateKbps * 1000
            if h.version == EMpegVersion.Mpeg1 && h.layer == EMpegLayer.Layer3
            {
                ret 144 * bps / h.sampleRate + h.padding
            }
            if h.layer == EMpegLayer.Layer1
            {
                ret ( 12 * bps / h.sampleRate + h.padding ) * 4
            }
            # MPEG2 / 2.5 的 Layer2、Layer3
            ret 72 * bps / h.sampleRate + h.padding
        }

        # ── ID3v2（syncsafe 整数）───────────────────────────
        # 头 10 字节："ID3" + ver(2) + flags(1) + size(4)
        # size 每个字节只用低 7 位，共 28 位
        public static bool hasId3v2( Array<UInt8> bytes )
        {
            if bytes == null || bytes.length < 10
            {
                ret false
            }
            Int32 v0 = ImageInfo.readU8( bytes, 0 )
            Int32 v1 = ImageInfo.readU8( bytes, 1 )
            Int32 v2 = ImageInfo.readU8( bytes, 2 )
            if v0 != 0x49
            {
                ret false
            }
            if v1 != 0x44
            {
                ret false
            }
            if v2 != 0x33
            {
                ret false
            }
            ret true
        }

        public static Int32 id3v2Size( Array<UInt8> bytes )
        {
            if !Jpeg.hasId3v2( bytes )
            {
                ret 0
            }
            Int32 b0 = ImageInfo.readU8( bytes, 6 )
            Int32 b1 = ImageInfo.readU8( bytes, 7 )
            Int32 b2 = ImageInfo.readU8( bytes, 8 )
            Int32 b3 = ImageInfo.readU8( bytes, 9 )
            ret ( b0 << 21 ) | ( b1 << 14 ) | ( b2 << 7 ) | b3
        }

        # 标签头总长 = 10 + size（+10 若 flags 的 footer 位置 1）
        public static Int32 id3v2TotalSize( Array<UInt8> bytes )
        {
            if !Jpeg.hasId3v2( bytes )
            {
                ret 0
            }
            ret 10 + Jpeg.id3v2Size( bytes )
        }

        public static bool isJpeg( Array<UInt8> bytes )
        {
            if bytes == null || bytes.length < 3
            {
                ret false
            }
            Int32 v0 = ImageInfo.readU8( bytes, 0 )
            Int32 v1 = ImageInfo.readU8( bytes, 1 )
            Int32 v2 = ImageInfo.readU8( bytes, 2 )
            if v0 != 0xFF
            {
                ret false
            }
            if v1 != 0xD8
            {
                ret false
            }
            if v2 != 0xFF
            {
                ret false
            }
            ret true
        }

        public static bool isValidQuality( Int32 q )
        {
            ret q >= 1 && q <= 100
        }

        # ── 后端编解码 ──────────────────────────────────────
        public static ImageBuffer decode( Array<UInt8> bytes )
        {
            ret Jpeg.decode( bytes, JpegDecodeOptions.defaultOptions() )
        }

        public static ImageBuffer decode( Array<UInt8> bytes, JpegDecodeOptions options )
        {
            if bytes == null
            {
                ret null
            }
            # C 层 stb_image 解码（恒输出 RGBA8）；
            # options（快速上采样 / 块平滑）在 v1 C 层无对应项，暂忽略
            ret ImageFfi.decodeMem( bytes )
        }

        public static Array<UInt8> encode( ImageBuffer buffer )
        {
            ret Jpeg.encode( buffer, JpegEncodeOptions.defaultOptions() )
        }

        public static Array<UInt8> encode( ImageBuffer buffer, JpegEncodeOptions options )
        {
            if buffer == null
            {
                ret null
            }
            # C 层 stb_image_write：仅 quality 生效；
            # 子采样 / 算术编码 / restart 间隔在 v1 C 层无对应项，暂忽略
            Int32 q = options.quality
            if q < 1
            {
                q = 1
            }
            if q > 100
            {
                q = 100
            }
            Array<UInt8> rgba = ImageFfi.rgbaBytesOf( buffer )
            if rgba == null
            {
                ret null
            }
            ret ImageFfi.encodeMem( EImageFormat.Jpeg, q, buffer.width, buffer.height, rgba )
        }

        # EXIF 读取（遍历 APP1 段）
        # v1 缺口：C 层（stb/WIC）不提供 EXIF 解析，返回 null；
        # 后续可由纯 SL 解析器补齐（TIFF IFD 结构见 Webp/Jpeg 头注释）
        public static JpegExif readExif( Array<UInt8> bytes )
        {
            ret null
        }

        override string toString()
        {
            ret "Jpeg"
        }
    }
}
