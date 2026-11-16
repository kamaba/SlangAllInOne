# =========================================================================
# Audio/AudioSource.sl —— 可挂载音频源组件（Unity 风格门面，模块内实现）
#
# 参考 UnityEngine.AudioSource 的 API 形状，但完全跑在 SLang Audio
# 自研栈上（AudioClip 预解码 + AudioPlayer/waveOut 输出），与
# unity\HelloCube\sllib\AudioSource.sl（SlangUnity 桥接层，FFI 进
# Unity C# 引擎）无任何复用关系。
#
# 语义（与 Unity 对齐的部分）：
#   clip      当前片段（set 时若在播先 Stop）
#   volume    0.0~1.0 浮点音量（映射 AudioPlayer 0..100）
#   loop      循环开关（重播由 update() 驱动：播完检测 -> 重新入队）
#   isPlaying 播放中（暂停 / 播完且未 loop 均为 false）
#   time      当前播放位置（秒，loop 时按片段长度取模）
#   Play/Stop/Pause/UnPause   常规控制
#   playOneShot( clip, s )    一次性叠加播放（独立临时播放器，
#                             不打断主 clip 状态；update() 里回收）
#
# 使用（游戏主循环驱动 loop / one-shot 回收）：
#   AudioSource src = AudioSource()
#   src.clip = AudioClip.loadFile( "bgm.wav" )
#   src.loop = true
#   src.volume = 0.6f
#   src.Play()
#   while running
#   {
#       src.update()          # 每帧：loop 重播 + one-shot 回收
#   }
#   src.free()
#
# 注：loop 重播与 one-shot 回收是轮询语义（无内部线程），需要调用方
# 周期性调 update()；不调 update() 时单次播放（loop=false）完全正常。
# =========================================================================

namespace Audio
{
    public class AudioSource
    {
        # 主通道：片段 + 播放器（Play 时按 clip 的 sr/ch 创建）
        AudioClip _clip = null
        AudioPlayer _ply = null

        # one-shot 临时播放器槽（8 路叠加；update() 里回收播完的）
        Array<AudioPlayer> _oneshots = null

        Float32 _volume = 1.0f
        bool _loop = false
        bool _playing = false
        bool _paused = false
        Int32 _loopCount = 0

        _init_()
        {
            this._clip = null
            this._ply = null
            this._oneshots = Array<AudioPlayer>( 8 )
            this._volume = 1.0f
            this._loop = false
            this._playing = false
            this._paused = false
            this._loopCount = 0
        }

        # ── 属性（Unity 风格）───────────────────────────────

        # 当前片段（set 时若在播先停播）
        public get AudioClip clip()
        {
            ret this._clip
        }

        public set void clip( AudioClip value )
        {
            if this._playing
            {
                this.Stop()
            }
            this._clip = value
        }

        # 音量 0.0~1.0（越界钳制；播放中即时生效）
        public get Float32 volume()
        {
            ret this._volume
        }

        public set void volume( Float32 value )
        {
            if value < 0.0f
            {
                value = 0.0f
            }
            if value > 1.0f
            {
                value = 1.0f
            }
            this._volume = value
            if this._ply != null
            {
                this._ply.setVolume( SystemConvertInt32( value * 100.0f + 0.5f ) )
            }
        }

        # 循环开关
        public get bool loop()
        {
            ret this._loop
        }

        public set void loop( bool value )
        {
            this._loop = value
        }

        # 播放中（暂停 / 已播完且未 loop 为 false）
        public get bool isPlaying()
        {
            if !this._playing || this._paused
            {
                ret false
            }
            if this._ply == null
            {
                ret false
            }
            if this._loop
            {
                ret true
            }
            if this._ply.buffered() > 0
            {
                ret true
            }
            ret this._ply.position() < this._ply.enqueuedFrames()
        }

        # 已完成的重播轮数（loop 累计；Stop 归零）
        public get Int32 loopCount()
        {
            ret this._loopCount
        }

        # 当前播放位置（秒；loop 时按片段长度取模）
        public get Float32 time()
        {
            if this._ply == null || this._clip == null
            {
                ret 0.0f
            }
            Int32 sr = this._clip.sampleRate
            if sr <= 0
            {
                ret 0.0f
            }
            Int64 pos = this._ply.position()
            Int64 frames = this._clip.frameCount
            if frames > 0
            {
                pos = pos % frames
            }
            ret ( 1.0f * pos ) / sr
        }

        # 活跃 one-shot 路数
        public get Int32 oneshotCount()
        {
            Int32 c = 0
            Int32 i = 0
            while i < 8
            {
                if this._oneshots[i] != null
                {
                    c = c + 1
                }
                i = i + 1
            }
            ret c
        }

        # ── 控制 ────────────────────────────────────────────

        # 从头播放当前片段（已在播则重启；无声卡 / 未设 clip 返回 false）
        public bool Play()
        {
            if this._clip == null || !this._clip.isReady
            {
                ret false
            }
            if this._ply == null
            {
                this._ply = AudioPlayer.create( this._clip.sampleRate, this._clip.channels )
                if this._ply == null
                {
                    ret false
                }
            }
            this._ply.stop()
            if this._ply.enqueueClip( this._clip ) <= 0
            {
                ret false
            }
            this._ply.setVolume( SystemConvertInt32( this._volume * 100.0f + 0.5f ) )
            this._playing = true
            this._paused = false
            ret true
        }

        # 停播并复位（time/loopCount 归零；播放器保留复用）
        public bool Stop()
        {
            this._playing = false
            this._paused = false
            this._loopCount = 0
            if this._ply == null
            {
                ret true
            }
            ret this._ply.stop()
        }

        public bool Pause()
        {
            if this._ply == null || !this._playing
            {
                ret false
            }
            if this._ply.pause()
            {
                this._paused = true
                ret true
            }
            ret false
        }

        public bool UnPause()
        {
            if this._ply == null || !this._paused
            {
                ret false
            }
            if this._ply.resume()
            {
                this._paused = false
                ret true
            }
            ret false
        }

        # 一次性叠加播放（独立临时播放器，不打断主 clip 状态）；
        # volumeScale 相对当前 volume 的缩放（0.0~1.0）。播完由
        # update() 回收。返回 false = clip 无效 / 无声卡。
        public bool playOneShot( AudioClip clip, Float32 volumeScale )
        {
            if clip == null || !clip.isReady
            {
                ret false
            }
            AudioPlayer p = AudioPlayer.create( clip.sampleRate, clip.channels )
            if p == null
            {
                ret false
            }
            if p.enqueueClip( clip ) <= 0
            {
                p.free()
                ret false
            }
            if volumeScale < 0.0f
            {
                volumeScale = 0.0f
            }
            if volumeScale > 1.0f
            {
                volumeScale = 1.0f
            }
            p.setVolume( SystemConvertInt32( this._volume * volumeScale * 100.0f + 0.5f ) )
            Int32 i = 0
            while i < 8
            {
                if this._oneshots[i] == null
                {
                    this._oneshots[i] = p
                    ret true
                }
                i = i + 1
            }
            # 槽满：挤掉 0 号（最旧）
            AudioPlayer old = this._oneshots[0]
            if old != null
            {
                old.stop()
                old.free()
            }
            this._oneshots[0] = p
            ret true
        }

        # ── 帧驱动（主循环每帧调用）─────────────────────────

        # loop 重播（主通道播完且 loop 开 -> 重新入队）+
        # one-shot 播放器回收（播完即 free 腾槽）
        public void update()
        {
            if this._playing && this._loop && this._ply != null
            {
                Int64 enq = this._ply.enqueuedFrames()
                if enq > 0 && this._ply.buffered() == 0 && this._ply.position() >= enq
                {
                    this._ply.stop()
                    if this._ply.enqueueClip( this._clip ) > 0
                    {
                        this._loopCount = this._loopCount + 1
                    }
                }
            }
            Int32 i = 0
            while i < 8
            {
                AudioPlayer p = this._oneshots[i]
                if p != null
                {
                    Int64 enq = p.enqueuedFrames()
                    if enq > 0 && p.buffered() == 0 && p.position() >= enq
                    {
                        p.stop()
                        p.free()
                        this._oneshots[i] = null
                    }
                }
                i = i + 1
            }
        }

        # ── 释放 ────────────────────────────────────────────

        # 释放主播放器 + 全部 one-shot（clip 归调用方所有，不代释放）
        public bool free()
        {
            this.Stop()
            if this._ply != null
            {
                this._ply.free()
                this._ply = null
            }
            Int32 i = 0
            while i < 8
            {
                AudioPlayer p = this._oneshots[i]
                if p != null
                {
                    p.stop()
                    p.free()
                    this._oneshots[i] = null
                }
                i = i + 1
            }
            this._clip = null
            ret true
        }

        override string toString()
        {
            if this._clip == null
            {
                ret "AudioSource(no clip)"
            }
            string s = "AudioSource(" + this._clip.sampleRate.toString() + "Hz, vol=" + this._volume.toString() + ", loop=" + this._loop.toString() + ", playing=" + this.isPlaying.toString() + ")"
            ret s
        }
    }
}
