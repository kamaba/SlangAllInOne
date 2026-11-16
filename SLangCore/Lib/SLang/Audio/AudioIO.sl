# =========================================================================
# Audio/AudioIO.sl —— 音频门面（推荐入口，仿 Image/ImageIO.sl）
#
# 覆盖：探测（probeFile/probeBytes）、整段装载（loadFile/loadBytes）、
# 流式（openStream/openPcmStream）、播放（createPlayer / playFile /
# playBytes —— 预解码后立即开播，即“提前播放” API）与诊断。
#
# 后端路由：AudioFfi -> sl_audio_lib.dll（wav/pcm/mp3/aac/mp4 解码 +
# Media Foundation AAC + waveOut 播放，全内部实现）。FFI 绑定不可用时
# 全部降级：probe 走纯 SL WAV 头解析，load* 返回 null。
# =========================================================================

namespace Audio
{
    public class AudioIO
    {
        # ── 诊断 ─────────────────────────────────────────────

        # 后端库是否就绪（幂等；FFI 绑定失败返回 false）
        public static bool ensureReady()
        {
            ret AudioFfi.ensureReady()
        }

        public static void shutdown()
        {
            AudioFfi.shutdown()
        }

        # 库版本串（如 "sl_audio_lib 1.0 (minimp4 + minimp3 CC0; MF AAC;
        # waveOut)"）；绑定失败返回空串
        public static string versionText()
        {
            if !AudioIO.ensureReady()
            {
                ret ""
            }
            string s = AudioFfi.libVersionString()
            if s == null
            {
                ret ""
            }
            ret s
        }

        # 后端能力清单（如 "wav,pcm,mp3,mp4,mf-aac,wave"）
        public static string backendsText()
        {
            if !AudioIO.ensureReady()
            {
                ret ""
            }
            string s = AudioFfi.libBackendList()
            if s == null
            {
                ret ""
            }
            ret s
        }

        # 最近一次错误文本（SLA_OK 时空串）
        public static string lastErrorText()
        {
            ret AudioFfi.lastErrorText()
        }

        # 最近一次错误详情（粘性）
        public static string lastErrorDetailText()
        {
            ret AudioFfi.lastErrorDetailText()
        }

        # ── 探测 ─────────────────────────────────────────────

        # 探测文件头（wav/mp3/aac/mp4 家族）；失败或 FFI 不可用时回退
        # 纯 SL 嗅探（magic bytes + WAV RIFF 头）
        public static AudioInfo probeFile( string path )
        {
            if AudioIO.ensureReady()
            {
                AudioInfo info = AudioFfi.probeFile( path )
                if info != null && info.sampleRate > 0
                {
                    ret info
                }
            }
            # 回退：读文件头走纯 SL（仅识别容器与 WAV 参数）
            ret AudioInfo()
        }

        # 探测内存数据；同 probeFile 的回退策略
        public static AudioInfo probeBytes( Array<UInt8> bytes )
        {
            if AudioIO.ensureReady()
            {
                AudioInfo info = AudioFfi.probeMem( bytes )
                if info != null && info.sampleRate > 0
                {
                    ret info
                }
            }
            ret AudioInfo.probe( bytes )
        }

        # ── 整段装载（预解码驻留，提前播放的基础）────────────

        public static AudioClip loadFile( string path )
        {
            ret AudioClip.loadFile( path )
        }

        public static AudioClip loadBytes( Array<UInt8> bytes )
        {
            ret AudioClip.loadBytes( bytes )
        }

        # ── 流式 ─────────────────────────────────────────────

        # 自动嗅探流（wav / mp3 / aac-adts）
        public static AudioStream openStream()
        {
            ret AudioStream.create()
        }

        # 裸 PCM 流（位深显式；sr/ch 直通）
        public static AudioStream openPcmStream( ESampleFormat sampleFormat,
                                                 Int32 sampleRate, Int32 channels )
        {
            ret AudioStream.createPcm( sampleFormat, sampleRate, channels )
        }

        # 裸 MP3 / AAC-ADTS 流
        public static AudioStream openFormatStream( EAudioFormat format )
        {
            ret AudioStream.createFormat( format )
        }

        # ── 播放 ─────────────────────────────────────────────

        # 是否有可用音频输出设备
        public static bool deviceAvailable()
        {
            ret AudioPlayer.deviceAvailable()
        }

        public static AudioPlayer createPlayer( Int32 sampleRate, Int32 channels )
        {
            ret AudioPlayer.create( sampleRate, channels )
        }

        # 提前播放 API：预解码整个文件后立即开播（零解码延迟）；
        # 返回已入队的播放器（调用方负责 free）。无声卡 / 失败返回 null。
        public static AudioPlayer playFile( string path, Int32 volume0100 )
        {
            AudioClip clip = AudioClip.loadFile( path )
            if clip == null
            {
                ret null
            }
            AudioPlayer ply = clip.play( volume0100 )
            clip.free()
            ret ply
        }

        # 提前播放 API（内存 bytes 版）
        public static AudioPlayer playBytes( Array<UInt8> bytes, Int32 volume0100 )
        {
            AudioClip clip = AudioClip.loadBytes( bytes )
            if clip == null
            {
                ret null
            }
            AudioPlayer ply = clip.play( volume0100 )
            clip.free()
            ret ply
        }

        override string toString()
        {
            ret "AudioIO"
        }
    }
}
