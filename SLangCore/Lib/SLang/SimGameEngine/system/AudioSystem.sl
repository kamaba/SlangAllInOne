import Core;
import Std;
import Math;
import SLangAudio;

# ============================================================================
# AudioSystem — 音频系统总管（system/ 层，仿 Unity AudioManager）
# ----------------------------------------------------------------------------
# 职责：SLangAudio（sl_audio_lib.dll）的总入口——后端就绪 / 加载音效 /
# 创建 AudioSource（Unity 风格 clip/volume/loop）/ 播放控制 / 释放。
# 跨模块消费形态（doc/10 §1.3/§6）：
#   - namespace 限定 `Audio.AudioIO` / `Audio.AudioClip` / `Audio.AudioSource`；
#   - `AudioClip.loadFile(string)` / `AudioIO.probeFile(string)` 为 string
#     参数静态（引用顺序规则下可靠）；实例方法（play/free）可靠。
# 无声卡环境：AudioPlayer.deviceAvailable() false 时 play 优雅降级（不报错）。
# ============================================================================

public class AudioSystem
{
    public bool ready = false
    public string lastError = ""
    # 当前主通道音源（playSource 成功时登记；供帧尾时钟同步读取播放头）
    public Audio.AudioSource activeSource = null

    # 后端就绪（waveOut/wasapi；失败原因见 lastError）
    public bool init()
    {
        bool ok = Audio.AudioIO.ensureReady()
        if ok
        {
            this.ready = true
        }
        else
        {
            this.lastError = Audio.AudioIO.lastErrorText()
        }
        ret ok
    }

    public string backendsText()
    {
        ret Audio.AudioIO.backendsText()
    }

    public bool deviceAvailable()
    {
        ret Audio.AudioPlayer.deviceAvailable()
    }

    # 加载音效（wav/mp4/aac；按扩展名与内容探测解码）
    public Audio.AudioClip loadClip( string path )
    {
        Audio.AudioClip clip = Audio.AudioClip.loadFile( path )
        if clip == null
        {
            this.lastError = Audio.AudioIO.lastErrorText()
        }
        ret clip
    }

    # 创建 Unity 风格音源（clip/volume/loop 三件套）
    public Audio.AudioSource createSource( Audio.AudioClip clip, Float32 volume, bool loop )
    {
        Audio.AudioSource src = Audio.AudioSource()
        src.clip = clip
        src.volume = volume
        src.loop = loop
        ret src
    }

    # 播放（真实出声；无输出设备返回 false 但不抛错）
    public bool playSource( Audio.AudioSource src )
    {
        if this.deviceAvailable() == false
        {
            this.lastError = "no audio output device"
            ret false
        }
        bool ok = src.Play()
        if !ok
        {
            this.lastError = Audio.AudioIO.lastErrorText()
        }
        else
        {
            this.activeSource = src
        }
        ret ok
    }

    # ── 时间同步（doc/18 v1.1）────────────────────────────
    # 每帧由 Application.tick 帧尾调用；把当前音源播放头（秒→微秒）上报
    # 给时间服务，域偏移的渐变对齐统一由 TimeService.syncExternalClocks 收口。
    # snapNow=true = seek/换曲后一步对齐（正常播放请保持 false 防爆音）。
    public bool syncClock( TimeService svc )
    {
        if svc == null || this.activeSource == null
        {
            ret false
        }
        if this.activeSource.isPlaying == false
        {
            ret false
        }
        Float32 sec = this.activeSource.time
        if sec < 0.0f
        {
            sec = 0.0f
        }
        Int64 headUs = SystemConvertInt64( sec * 1000000.0f )
        svc.reportAudioHead( headUs, false )
        ret true
    }

    # seek / 换曲后用：一步把音频域时钟对齐到当前播放头
    public bool snapClock( TimeService svc )
    {
        if svc == null || this.activeSource == null
        {
            ret false
        }
        Float32 sec = this.activeSource.time
        if sec < 0.0f
        {
            sec = 0.0f
        }
        Int64 headUs = SystemConvertInt64( sec * 1000000.0f )
        svc.reportAudioHead( headUs, true )
        ret true
    }

    public string probeFile( string path )
    {
        Audio.AudioInfo info = Audio.AudioIO.probeFile( path )
        if info == null
        {
            ret ""
        }
        ret info.toString()
    }

    public void shutdown()
    {
        Audio.AudioIO.shutdown()
        this.ready = false
        this.activeSource = null
    }
}
