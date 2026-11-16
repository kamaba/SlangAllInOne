# =========================================================================
# Audio/AudioClip.sl —— 整段解码音频片段（dec 句柄包装）
#
# “提前播放” API 的基础：loadFile/loadBytes 一次性解码为 interleaved
# S16 PCM，数据留在 C 侧句柄里（不受 MAX_INLINE_BYTES 字节搬运墙限制，
# 上限 MAX_NATIVE_BYTES = 64 MiB），play() 即刻开播零解码延迟。
#
# 用法：
#   AudioClip clip = AudioClip.loadFile( "test.wav" )
#   AudioPlayer ply = clip.play( 80 )     # 预载即播（提前播放）
#   ...
#   ply.free(); clip.free()
#
# PCM 契约：interleaved S16LE、源采样率 / 声道数；句柄 1 起始，0 无效。
# =========================================================================

namespace Audio
{
    public class AudioClip
    {
        # C 侧 dec 句柄（模块内；0 = 未加载 / 已释放）
        Int64 _handle = 0

        _init_()
        {
            this._handle = 0
        }

        _init_( Int64 handle )
        {
            this._handle = handle
        }

        # ── 工厂 ─────────────────────────────────────────────

        # 解码整个文件（wav / mp3 / aac / mp4 家族，自动嗅探）；
        # 失败返回 null（原因见 AudioFfi.lastErrorText()）
        public static AudioClip loadFile( string path )
        {
            if !AudioFfi.ensureReady()
            {
                ret null
            }
            if path == null || path == ""
            {
                ret null
            }
            Int64 dec = AudioFfi.libDecodeFile( path, AudioFfi.HINT_AUTO )
            if dec == 0
            {
                ret null
            }
            if AudioFfi.libDecSampleRate( dec ) <= 0
            {
                AudioFfi.libDecFree( dec )
                ret null
            }
            ret AudioClip( dec )
        }

        # 解码内存 bytes（<= MAX_INLINE_BYTES 输入墙）；失败返回 null
        public static AudioClip loadBytes( Array<UInt8> bytes )
        {
            if !AudioFfi.ensureReady()
            {
                ret null
            }
            if bytes == null || bytes.length < 12
            {
                ret null
            }
            Int64 src = AudioFfi._copyIn( bytes, bytes.length )
            if src == 0
            {
                ret null
            }
            Int64 dec = AudioFfi.libDecodeMem( src, bytes.length, AudioFfi.HINT_AUTO )
            Memory.free( src )
            if dec == 0
            {
                ret null
            }
            if AudioFfi.libDecSampleRate( dec ) <= 0
            {
                AudioFfi.libDecFree( dec )
                ret null
            }
            ret AudioClip( dec )
        }

        # ── 元数据（句柄直查，零拷贝）────────────────────────

        public get bool isReady()
        {
            ret this._handle != 0
        }

        # C 侧 dec 句柄原值（模块内 AudioPlayer.enqueueClip 原生直转用；
        # 外部不应直接持有）
        public Int64 nativeHandle()
        {
            ret this._handle
        }

        public get Int32 sampleRate()
        {
            if this._handle == 0
            {
                ret 0
            }
            ret AudioFfi.libDecSampleRate( this._handle )
        }

        public get Int32 channels()
        {
            if this._handle == 0
            {
                ret 0
            }
            ret AudioFfi.libDecChannels( this._handle )
        }

        # 总帧数（帧 = channels 个采样）
        public get Int64 frameCount()
        {
            if this._handle == 0
            {
                ret 0
            }
            ret AudioFfi.libDecFrameCount( this._handle )
        }

        # C 侧源格式 id（SLA_FMT_*，细粒度；粗粒度看 sourceFormat）
        public get Int32 sourceFormatId()
        {
            if this._handle == 0
            {
                ret 0
            }
            ret AudioFfi.libDecSourceFormat( this._handle )
        }

        public get EAudioFormat sourceFormat()
        {
            ret AudioFfi.srcIdToFormat( this.sourceFormatId )
        }

        # 时长（秒）
        public get Float32 duration()
        {
            Int32 sr = this.sampleRate
            if sr <= 0
            {
                ret 0.0f
            }
            ret ( 1.0f * this.frameCount ) / sr
        }

        # ── 数据导出（经 SL 字节环，受尺寸墙约束）────────────

        # S16LE PCM 字节流（Array<UInt8>，长度 = frames*channels*2）；
        # 超过 MAX_INLINE_BYTES 或失败返回 null
        public Array<UInt8> s16Bytes()
        {
            if this._handle == 0
            {
                ret null
            }
            Int64 frames = this.frameCount
            Int32 ch = this.channels
            if frames <= 0 || ch <= 0
            {
                ret null
            }
            Int64 byteCount = frames * ch * 2
            if byteCount <= 0 || byteCount > AudioFfi.MAX_INLINE_BYTES
            {
                ret null
            }
            Int32 bytes = SystemConvertInt32( byteCount )
            Int64 dst = Memory.alloc( bytes )
            if dst == 0
            {
                ret null
            }
            Array<UInt8> result = null
            if AudioFfi.libDecCopyI16( this._handle, dst, frames ) == frames
            {
                result = AudioFfi._copyOut( dst, bytes )
            }
            Memory.free( dst )
            ret result
        }

        # 导出为 AudioBuffer（Float32 交织视图；受 MAX_INLINE_BYTES 墙）
        public AudioBuffer toAudioBuffer()
        {
            Array<UInt8> pcm = this.s16Bytes()
            if pcm == null
            {
                ret null
            }
            ret AudioBuffer.fromS16Interleaved( pcm, this.channels, this.sampleRate )
        }

        # ── 提前播放（预载即播）──────────────────────────────

        # 立即播放本片段：创建 AudioPlayer、原生块直转入队（不经 SL
        # 字节环，上限 MAX_NATIVE_BYTES）、设定音量，返回播放器句柄
        # （调用方负责后续 free）。无声卡或失败返回 null。
        public AudioPlayer play( Int32 volume0100 )
        {
            if this._handle == 0
            {
                ret null
            }
            AudioPlayer ply = AudioPlayer.create( this.sampleRate, this.channels )
            if ply == null
            {
                ret null
            }
            if !ply.enqueueClip( this )
            {
                ply.free()
                ret null
            }
            if volume0100 >= 0 && volume0100 <= 100
            {
                ply.setVolume( volume0100 )
            }
            ret ply
        }

        # ── 释放 ─────────────────────────────────────────────

        # 释放 C 侧句柄（幂等；之后再访问各 getter 返回 0/无效值）
        public bool free()
        {
            if this._handle == 0
            {
                ret true
            }
            bool ok = AudioFfi.libDecFree( this._handle )
            this._handle = 0
            ret ok
        }

        override string toString()
        {
            if this._handle == 0
            {
                ret "AudioClip(empty)"
            }
            ret "AudioClip(" + this.sampleRate.toString() + "Hz, " + this.channels.toString() + "ch, " + this.duration.toString() + "s, src=" + this.sourceFormatId.toString() + ")"
        }
    }
}
