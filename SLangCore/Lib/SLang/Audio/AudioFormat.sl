# =========================================================================
# Audio/AudioFormat.sl —— 音频格式 / 采样格式 / 声道布局 / 错误码
#
# 约定同 DB/Sqlite.sl：所有类型为 namespace 下的顶级类型，不嵌套。
#
# 纯 SL 可完整实现：WAV（RIFF 头 + PCM），见 Wav.sl
# 需要后端编解码：MP3 / AAC / FLAC / OGG（熵编码 + 心理声学模型）
# =========================================================================

namespace Audio
{
    # 容器 / 编码格式（显式值：裸名成员无法被 MetaCore 调用链解析）
    public enum EAudioFormat
    {
        Unknown = 0
        # RIFF / PCM（纯 SL 可完整读写）
        Wav = 1
        Mp3 = 2
        # ADTS / ADIF / MP4 容器
        Aac = 3
        # 无损
        Flac = 4
        # Ogg 容器（Vorbis / Opus / FLAC）
        Ogg = 5
        Opus = 6
        Wma = 7
        Aiff = 8
        Amr = 9
        Midi = 10
    }

    # PCM 采样格式（位深）
    public enum ESampleFormat
    {
        Unknown = 0
        # 无符号 8 位，零点 128
        U8 = 1
        # 有符号 16 位小端（最常见）
        S16 = 2
        # 有符号 24 位，打包成 3 字节
        S24 = 3
        # 有符号 32 位
        S32 = 4
        # IEEE Float32
        F32 = 5
        # IEEE Float64
        F64 = 6
    }

    # 声道布局
    public enum EChannelLayout
    {
        Unknown = 0
        Mono = 1
        Stereo = 2
        Quadro = 4
        Surround51 = 6
        Surround71 = 8
    }

    # 常用采样率
    public enum ESampleRate
    {
        # 电话
        Rate8000 = 8000
        # 语音识别常用
        Rate16000 = 16000
        Rate22050 = 22050
        Rate32000 = 32000
        # CD
        Rate44100 = 44100
        # 视频 / Opus 原生
        Rate48000 = 48000
        # 高解析
        Rate96000 = 96000
    }

    # 码率控制模式
    public enum EBitrateMode
    {
        Unknown = 0
        # 恒定码率
        CBR = 1
        # 可变码率
        VBR = 2
        # 平均码率
        ABR = 3
    }

    public enum AudioErrorCode extends Error
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

    # ── 格式能力表（纯 SL）──────────────────────────────────
    public class AudioFormatInfo
    {
        # 是否无损
        public static bool isLossless( EAudioFormat format )
        {
            if format == EAudioFormat.Wav || format == EAudioFormat.Flac ||
               format == EAudioFormat.Aiff
            {
                ret true
            }
            ret false
        }

        # 是否支持元数据标签（ID3 / Vorbis Comment 等）
        public static bool supportsTags( EAudioFormat format )
        {
            if format == EAudioFormat.Mp3 || format == EAudioFormat.Flac ||
               format == EAudioFormat.Ogg || format == EAudioFormat.Opus
            {
                ret true
            }
            ret false
        }

        # 是否需要外部解码库
        public static bool needsNativeCodec( EAudioFormat format )
        {
            if format == EAudioFormat.Wav
            {
                ret false
            }
            ret true
        }

        public static string mimeType( EAudioFormat format )
        {
            if format == EAudioFormat.Wav  { ret "audio/wav" }
            if format == EAudioFormat.Mp3  { ret "audio/mpeg" }
            if format == EAudioFormat.Aac  { ret "audio/aac" }
            if format == EAudioFormat.Flac { ret "audio/flac" }
            if format == EAudioFormat.Ogg  { ret "audio/ogg" }
            if format == EAudioFormat.Opus { ret "audio/opus" }
            if format == EAudioFormat.Wma  { ret "audio/x-ms-wma" }
            if format == EAudioFormat.Aiff { ret "audio/aiff" }
            if format == EAudioFormat.Amr  { ret "audio/amr" }
            if format == EAudioFormat.Midi { ret "audio/midi" }
            ret "application/octet-stream"
        }

        # 首选扩展名（含点号）
        public static string extension( EAudioFormat format )
        {
            if format == EAudioFormat.Wav  { ret ".wav" }
            if format == EAudioFormat.Mp3  { ret ".mp3" }
            if format == EAudioFormat.Aac  { ret ".aac" }
            if format == EAudioFormat.Flac { ret ".flac" }
            if format == EAudioFormat.Ogg  { ret ".ogg" }
            if format == EAudioFormat.Opus { ret ".opus" }
            if format == EAudioFormat.Wma  { ret ".wma" }
            if format == EAudioFormat.Aiff { ret ".aiff" }
            if format == EAudioFormat.Amr  { ret ".amr" }
            if format == EAudioFormat.Midi { ret ".mid" }
            ret ""
        }

        override string toString()
        {
            ret "AudioFormatInfo"
        }
    }
}
