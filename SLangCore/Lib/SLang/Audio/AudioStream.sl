# =========================================================================
# Audio/AudioStream.sl —— 流式解码类（stm 句柄包装）
#
# 喂压缩比特流、拉 PCM：create -> feed(bytes)* -> read*(capFrames)*
# -> free。MP4 容器依赖尾部索引随机访问，按设计不支持流式（feed 返回
# 0 且 lastError 为 unsupported）；裸 PCM 家族必须显式给位深
# （createPcm）；wav / mp3 / adts-aac 自动嗅探。
#
# 用法：
#   AudioStream stm = AudioStream.create()
#   stm.feed( chunk1 )
#   Array<UInt8> pcm = stm.readS16Bytes( 4096 )
#   ...
#   stm.free()
#
# 格式参数在首帧喂入后才定型（如 MP3 首帧）：定型前 sampleRate /
# channels 返回 0。read* 在暂无产出时返回 null / 空数组（非错误，
# SLA_E_NO_DATA 语义：继续 feed 后重试）。
# =========================================================================

namespace Audio
{
    public class AudioStream
    {
        # C 侧 stm 句柄（模块内；0 = 未创建 / 已释放）
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

        # 自动嗅探流（wav / mp3 / aac-adts）
        public static AudioStream create()
        {
            if !AudioFfi.ensureReady()
            {
                ret null
            }
            Int64 stm = AudioFfi.libStreamCreate( AudioFfi.HINT_AUTO, 0, 0 )
            if stm == 0
            {
                ret null
            }
            ret AudioStream( stm )
        }

        # 裸 PCM 流（必须显式位深；sr/ch 原样直通）
        public static AudioStream createPcm( ESampleFormat sampleFormat,
                                             Int32 sampleRate, Int32 channels )
        {
            if !AudioFfi.ensureReady()
            {
                ret null
            }
            Int32 hint = AudioFfi.sampleFormatToHint( sampleFormat )
            if hint == AudioFfi.HINT_AUTO
            {
                ret null
            }
            Int64 stm = AudioFfi.libStreamCreate( hint, sampleRate, channels )
            if stm == 0
            {
                ret null
            }
            ret AudioStream( stm )
        }

        # 裸 MP3 / AAC-ADTS 流（显式格式提示）
        public static AudioStream createFormat( EAudioFormat format )
        {
            if !AudioFfi.ensureReady()
            {
                ret null
            }
            Int32 hint = AudioFfi.HINT_AUTO
            if format == EAudioFormat.Mp3
            {
                hint = AudioFfi.HINT_MP3
            }
            elif format == EAudioFormat.Aac
            {
                hint = AudioFfi.HINT_AAC_ADTS
            }
            else
            {
                ret null
            }
            Int64 stm = AudioFfi.libStreamCreate( hint, 0, 0 )
            if stm == 0
            {
                ret null
            }
            ret AudioStream( stm )
        }

        # ── 状态 ─────────────────────────────────────────────

        public get bool isReady()
        {
            ret this._handle != 0
        }

        # 采样率（首帧喂入前为 0）
        public get Int32 sampleRate()
        {
            if this._handle == 0
            {
                ret 0
            }
            ret AudioFfi.libStreamSampleRate( this._handle )
        }

        # 声道数（首帧喂入前为 0）
        public get Int32 channels()
        {
            if this._handle == 0
            {
                ret 0
            }
            ret AudioFfi.libStreamChannels( this._handle )
        }

        # 累计已产出帧数
        public get Int64 framesOut()
        {
            if this._handle == 0
            {
                ret 0
            }
            ret AudioFfi.libStreamFramesOut( this._handle )
        }

        # C 侧源格式 id（SLA_FMT_*）
        public get Int32 sourceFormatId()
        {
            if this._handle == 0
            {
                ret 0
            }
            ret AudioFfi.libStreamSourceFormat( this._handle )
        }

        public get EAudioFormat sourceFormat()
        {
            ret AudioFfi.srcIdToFormat( this.sourceFormatId )
        }

        # ── 数据面 ───────────────────────────────────────────

        # 喂入压缩数据（<= MAX_INLINE_BYTES）；返回本轮消费字节数
        # （0 = 全缓存待更多数据或失败，区分看 AudioFfi.lastErrorText）
        public Int64 feed( Array<UInt8> bytes )
        {
            if this._handle == 0 || bytes == null || bytes.length <= 0
            {
                ret 0
            }
            Int64 src = AudioFfi._copyIn( bytes, bytes.length )
            if src == 0
            {
                ret 0
            }
            Int64 consumed = AudioFfi.libStreamFeed( this._handle, src, bytes.length )
            Memory.free( src )
            ret consumed
        }

        # 拉取至多 capFrames 帧 S16LE PCM 字节流；无产出 / 失败返回
        # null（调用方继续 feed 后重试）。块长 = frames * channels * 2。
        # 注：格式在首帧产出后才定型（channels == 0），此时按声道上限 8
        # 预留缓冲，读后用真实声道数计算字节（避免按猜值翻倍/截断）。
        public Array<UInt8> readS16Bytes( Int32 capFrames )
        {
            if this._handle == 0 || capFrames <= 0
            {
                ret null
            }
            Int32 chReserve = this.channels
            if chReserve <= 0
            {
                chReserve = 8
            }
            Int32 byteCap = capFrames * chReserve * 2
            if byteCap <= 0 || byteCap > AudioFfi.MAX_INLINE_BYTES
            {
                ret null
            }
            Int64 dst = Memory.alloc( byteCap )
            if dst == 0
            {
                ret null
            }
            Array<UInt8> result = null
            Int64 got = AudioFfi.libStreamReadI16( this._handle, dst, capFrames )
            if got > 0
            {
                Int32 chNow = this.channels
                if chNow <= 0
                {
                    chNow = chReserve
                }
                Int32 bytes = SystemConvertInt32( got * chNow * 2 )
                result = AudioFfi._copyOut( dst, bytes )
            }
            Memory.free( dst )
            ret result
        }

        # 拉取至多 capFrames 帧并转 AudioBuffer（Float32 视图）；
        # 无产出返回 null。需要已定型声道数。
        public AudioBuffer readBuffer( Int32 capFrames )
        {
            Int32 ch = this.channels
            if ch <= 0
            {
                ret null
            }
            Array<UInt8> pcm = this.readS16Bytes( capFrames )
            if pcm == null
            {
                ret null
            }
            ret AudioBuffer.fromS16Interleaved( pcm, ch, this.sampleRate )
        }

        # ── 释放 ─────────────────────────────────────────────

        public bool free()
        {
            if this._handle == 0
            {
                ret true
            }
            bool ok = AudioFfi.libStreamFree( this._handle )
            this._handle = 0
            ret ok
        }

        override string toString()
        {
            if this._handle == 0
            {
                ret "AudioStream(empty)"
            }
            ret "AudioStream(" + this.sampleRate.toString() + "Hz, " + this.channels.toString() + "ch, out=" + this.framesOut.toString() + ")"
        }
    }
}
