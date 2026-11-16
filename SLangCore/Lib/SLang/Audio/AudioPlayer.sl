# =========================================================================
# Audio/AudioPlayer.sl —— 播放器（ply 句柄包装，waveOut + 库自持线程）
#
# 队列语义：enqueue 的 S16 块进内部环形缓冲，waveOut 依序消耗；
# position = 已通过扬声器输出的帧数；stop 清空队列并复位。
# 所有方法线程安全（C 层内部锁）；无声卡环境 create 返回 null
# （先查 AudioPlayer.deviceAvailable()）。
#
# 用法（配合 AudioClip 的提前播放）：
#   AudioPlayer ply = clip.play( 80 )
#   Int64 t = SystemTimerNowMillis()
#   while ply.position() < ply.enqueuedFrames()
#   {
#       if SystemTimerNowMillis() - t > 5000 { break }
#   }
#   ply.stop(); ply.free()
# =========================================================================

namespace Audio
{
    public class AudioPlayer
    {
        # C 侧 ply 句柄（模块内；0 = 未创建 / 已释放）
        Int64 _handle = 0
        Int32 _channels = 0
        Int64 _enqueued = 0

        _init_()
        {
            this._handle = 0
            this._channels = 0
            this._enqueued = 0
        }

        _init_( Int64 handle, Int32 channels )
        {
            this._handle = handle
            this._channels = channels
            this._enqueued = 0
        }

        # ── 工厂 / 设备 ──────────────────────────────────────

        # 是否有可用音频输出设备
        public static bool deviceAvailable()
        {
            if !AudioFfi.ensureReady()
            {
                ret false
            }
            ret AudioFfi.libDeviceAvailable()
        }

        # 创建播放器（sr/ch 必须与喂入 PCM 一致）；无声卡返回 null
        public static AudioPlayer create( Int32 sampleRate, Int32 channels )
        {
            if !AudioFfi.ensureReady()
            {
                ret null
            }
            if sampleRate <= 0 || channels <= 0
            {
                ret null
            }
            Int64 ply = AudioFfi.libPlayerCreate( sampleRate, channels )
            if ply == 0
            {
                ret null
            }
            ret AudioPlayer( ply, channels )
        }

        # ── 状态 ─────────────────────────────────────────────

        public get bool isReady()
        {
            ret this._handle != 0
        }

        public get Int32 channels()
        {
            ret this._channels
        }

        # 已通过扬声器输出的帧数
        public Int64 position()
        {
            if this._handle == 0
            {
                ret 0
            }
            ret AudioFfi.libPlayerPosition( this._handle )
        }

        # 队列剩余帧数
        public Int64 buffered()
        {
            if this._handle == 0
            {
                ret 0
            }
            ret AudioFfi.libPlayerBuffered( this._handle )
        }

        # 累计入队帧数（SL 侧记账，stop 后归零）
        public Int64 enqueuedFrames()
        {
            ret this._enqueued
        }

        # ── 入队 ─────────────────────────────────────────────

        # AudioClip 原生直转：dec 句柄 -> C 侧临时块 -> 播放环形缓冲，
        # 不经 SL 字节环（上限 MAX_NATIVE_BYTES）；返回入队帧数
        public Int64 enqueueClip( AudioClip clip )
        {
            if this._handle == 0
            {
                ret 0
            }
            if clip == null || !clip.isReady
            {
                ret 0
            }
            Int64 frames = clip.frameCount
            Int32 ch = clip.channels
            if frames <= 0 || ch <= 0
            {
                ret 0
            }
            Int64 byteCount = frames * ch * 2
            if byteCount <= 0 || byteCount > AudioFfi.MAX_NATIVE_BYTES
            {
                ret 0
            }
            Int32 bytes = SystemConvertInt32( byteCount )
            Int64 tmp = Memory.alloc( bytes )
            if tmp == 0
            {
                ret 0
            }
            Int64 got = AudioFfi.libDecCopyI16( clip.nativeHandle(), tmp, frames )
            Int64 queued = 0
            if got == frames
            {
                queued = AudioFfi.libPlayerEnqueue( this._handle, tmp, frames )
            }
            Memory.free( tmp )
            this._enqueued = this._enqueued + queued
            ret queued
        }

        # S16LE PCM 字节流入队（块长须为 channels*2 的整倍数）；
        # 返回入队帧数（0 = 参数坏 / 设备忙重试）
        public Int64 enqueueBytes( Array<UInt8> s16 )
        {
            if this._handle == 0 || s16 == null
            {
                ret 0
            }
            Int32 ch = this._channels
            if ch <= 0
            {
                ret 0
            }
            Int32 stride = ch * 2
            if s16.length < stride
            {
                ret 0
            }
            Int32 usable = ( s16.length / stride ) * stride
            Int64 src = AudioFfi._copyIn( s16, usable )
            if src == 0
            {
                ret 0
            }
            Int64 frames = usable / stride
            Int64 queued = AudioFfi.libPlayerEnqueue( this._handle, src, frames )
            Memory.free( src )
            this._enqueued = this._enqueued + queued
            ret queued
        }

        # ── 控制 ─────────────────────────────────────────────

        # paused = true 暂停 / false 恢复
        public bool setPaused( bool paused )
        {
            if this._handle == 0
            {
                ret false
            }
            if paused
            {
                ret AudioFfi.libPlayerPause( this._handle, 1 )
            }
            ret AudioFfi.libPlayerPause( this._handle, 0 )
        }

        public bool pause()
        {
            ret this.setPaused( true )
        }

        public bool resume()
        {
            ret this.setPaused( false )
        }

        # 立即停播：清空队列并复位（入队记账同步归零）
        public bool stop()
        {
            if this._handle == 0
            {
                ret false
            }
            bool ok = AudioFfi.libPlayerStop( this._handle )
            if ok
            {
                this._enqueued = 0
            }
            ret ok
        }

        # 音量 0..100
        public bool setVolume( Int32 vol0100 )
        {
            if this._handle == 0
            {
                ret false
            }
            if vol0100 < 0
            {
                vol0100 = 0
            }
            if vol0100 > 100
            {
                vol0100 = 100
            }
            ret AudioFfi.libPlayerVolume( this._handle, vol0100 )
        }

        # ── 释放 ─────────────────────────────────────────────

        public bool free()
        {
            if this._handle == 0
            {
                ret true
            }
            bool ok = AudioFfi.libPlayerFree( this._handle )
            this._handle = 0
            this._enqueued = 0
            ret ok
        }

        override string toString()
        {
            if this._handle == 0
            {
                ret "AudioPlayer(empty)"
            }
            ret "AudioPlayer(pos=" + this.position().toString() + ", buffered=" + this.buffered().toString() + ")"
        }
    }
}
