import Core;
import Std;
import Math;

# ============================================================================
# TimeService — 引擎统一时间推进状态机（doc/18；贯穿逻辑/渲染/音频/视频/物理）
# ----------------------------------------------------------------------------
# 单点时间源：每帧 advanceFrame 消费「真实流逝」→ 产出本帧全套时间读数
# （scaled/unscaled dt、平滑 dt、累计时长、帧号），并把固定步长累加器
# （fixedUpdate ×N，物理/碰撞/稳定逻辑专用）与固定步插值系数 alpha 一并
# 管理。域时钟（render/physics/logic/audio/video）= C 单调钟 + 每域偏移
# （微秒 Int64），音频/视频播放头经 snap/nudge 挂接对齐（防爆音渐变校正）。
#
# 用法（Application.tick 已自动接入）：
#   app.time.advanceFrame( -1 )     # -1 = 引擎自动实测（推荐宿主传 -1）
#   while app.time.pendingFixedSteps > 0 { ...; app.time.consumeFixedStep() }
#   app.time.updateFixedAlpha()     # 帧尾插值系数
# 脚本侧只读 EngineTime（static 快照，每帧由本类写入）。
# ============================================================================

public class TimeService
{
    # ── 配置（真源在 Application；每帧 syncConfig 同步进来）──
    bool paused = false
    Float32 timeScale = 1.0f
    Float32 fixedDt = 0.0166667f
    Float32 maxDeltaTime = 0.1f
    Int32 maxFixedSteps = 5

    # ── 帧状态（推进后经 EngineTime 快照暴露）──
    Int64 frameCount = 0
    Float32 deltaTime = 0.0f
    Float32 unscaledDeltaTime = 0.0f
    Float32 smoothDeltaTime = 0.0f
    Float32 elapsedTime = 0.0f
    Float32 unscaledElapsedTime = 0.0f
    Float32 fixedAcc = 0.0f
    Int32 pendingFixedSteps = 0
    Float32 fixedAlpha = 0.0f

    # ── 域时钟状态（offset 微秒；域 now = EngineClock.nowUs() + offset）──
    Array<Int64> _domainOffsetUs = null
    Array<Int64> _domainLastNowUs = null
    # nudge 单次最大校正量（微秒）——音频/视频渐变对齐防爆音
    Int64 maxNudgeUs = 2000

    # 外部播放头（音频/视频后端上报；每帧 syncExternalClocks 统一收口）
    Int64 _audioHeadUs = 0
    Int64 _videoHeadUs = 0
    bool _hasAudioHead = false
    bool _hasVideoHead = false
    bool _snapAudioNext = false
    bool _snapVideoNext = false
    Int64 lastAudioDriftUs = 0
    Int64 lastVideoDriftUs = 0
    Int32 syncedAudioCount = 0
    Int32 syncedVideoCount = 0

    Int64 _lastNowUs = 0
    bool _hasLastNow = false

    public void _init_()
    {
        this.paused = false
        this.timeScale = 1.0f
        this.fixedDt = 1.0f / 60.0f
        this.maxDeltaTime = 0.1f
        this.maxFixedSteps = 5
        this.frameCount = 0
        this.deltaTime = 0.0f
        this.unscaledDeltaTime = 0.0f
        this.smoothDeltaTime = 0.0f
        this.elapsedTime = 0.0f
        this.unscaledElapsedTime = 0.0f
        this.fixedAcc = 0.0f
        this.pendingFixedSteps = 0
        this.fixedAlpha = 0.0f
        this._domainOffsetUs = Array<Int64>( 6 )
        this._domainLastNowUs = Array<Int64>( 6 )
        Int32 i = 0
        while i < 6
        {
            this._domainOffsetUs[ i ] = 0
            this._domainLastNowUs[ i ] = 0
            i = i + 1
        }
        this.maxNudgeUs = 2000
        this._audioHeadUs = 0
        this._videoHeadUs = 0
        this._hasAudioHead = false
        this._hasVideoHead = false
        this._snapAudioNext = false
        this._snapVideoNext = false
        this.lastAudioDriftUs = 0
        this.lastVideoDriftUs = 0
        this.syncedAudioCount = 0
        this.syncedVideoCount = 0
        this._lastNowUs = 0
        this._hasLastNow = false
    }

    # 配置同步（Application 每帧把旧接口字段灌入；字段真源不迁移，向后兼容）
    public void syncConfig( bool pausedCfg, Float32 scaleCfg, Float32 fixedDtCfg, Float32 maxDtCfg, Int32 maxStepsCfg )
    {
        this.paused = pausedCfg
        this.timeScale = scaleCfg
        this.fixedDt = fixedDtCfg
        this.maxDeltaTime = maxDtCfg
        this.maxFixedSteps = maxStepsCfg
    }

    # ── 帧推进：rawDt 秒（< 0 = 引擎用 C 单调钟自动实测）────────
    public void advanceFrame( Float32 rawDt )
    {
        Float32 raw = rawDt
        if raw < 0.0f
        {
            Int64 now = EngineClock.nowUs()
            if this._hasLastNow
            {
                Int64 d = now - this._lastNowUs
                raw = d * 0.000001f
            }
            else
            {
                raw = 0.0f
            }
            this._lastNowUs = now
            this._hasLastNow = true
        }
        if raw > this.maxDeltaTime
        {
            raw = this.maxDeltaTime
        }
        if raw < 0.0f
        {
            raw = 0.0f
        }
        this.unscaledDeltaTime = raw
        Float32 scaled = raw
        if this.paused
        {
            scaled = 0.0f
        }
        else
        {
            scaled = raw * this.timeScale
        }
        this.deltaTime = scaled
        if this.frameCount == 0
        {
            this.smoothDeltaTime = scaled
        }
        else
        {
            this.smoothDeltaTime = this.smoothDeltaTime * 0.9f + scaled * 0.1f
        }
        this.elapsedTime = this.elapsedTime + scaled
        this.unscaledElapsedTime = this.unscaledElapsedTime + raw
        this.frameCount = this.frameCount + 1

        # 固定步长累加（scaled；步数上限内消费，超限丢弃余量防螺旋死亡）
        this.fixedAcc = this.fixedAcc + scaled
        Int32 steps = 0
        while steps < this.maxFixedSteps
        {
            if this.fixedAcc < this.fixedDt
            {
                break
            }
            this.fixedAcc = this.fixedAcc - this.fixedDt
            steps = steps + 1
        }
        if steps >= this.maxFixedSteps && this.fixedAcc > this.fixedDt
        {
            this.fixedAcc = 0.0f
        }
        this.pendingFixedSteps = steps
        this.writeSnapshot()
    }

    # 消费一个固定步（Application 在每步 fixedUpdate/物理步之后调用）
    public void consumeFixedStep()
    {
        if this.pendingFixedSteps > 0
        {
            this.pendingFixedSteps = this.pendingFixedSteps - 1
        }
    }

    # 帧尾插值系数：剩余累加 / 固定步长（0..1）——渲染用上一固定步状态与
    # 当前状态间插值（物理稳定步长与渲染帧率解耦的另一半）
    public void updateFixedAlpha()
    {
        Float32 a = 0.0f
        if this.fixedDt > 0.0f
        {
            a = this.fixedAcc / this.fixedDt
        }
        if a > 1.0f
        {
            a = 1.0f
        }
        if a < 0.0f
        {
            a = 0.0f
        }
        this.fixedAlpha = a
        EngineTime.fixedAlpha = a
    }

    # 累加器重置（loadScene / shutdown；不清运行时长与帧号）
    public void resetAccumulators()
    {
        this.fixedAcc = 0.0f
        this.pendingFixedSteps = 0
        this.fixedAlpha = 0.0f
        EngineTime.fixedAlpha = 0.0f
    }

    # ── 域时钟（render/physics/logic/audio/video 挂接对齐）────────

    # 域当前时刻（微秒）= C 单调钟 + 域偏移
    public Int64 domainNowUs( Int32 domain )
    {
        Int64 now = EngineClock.nowUs()
        Int64 off = this.domainOffset( domain )
        ret now + off
    }

    # 域帧间差（微秒；首帧返回 0）
    public Int64 domainDeltaUs( Int32 domain )
    {
        Int64 d = this.domainIndex( domain )
        Array<Int64> lasts = this._domainLastNowUs
        Int64 last = lasts[ d ]
        if last == 0
        {
            ret 0
        }
        Int64 now = this.domainNowUs( domain )
        lasts[ d ] = now
        ret now - last
    }

    # 立即对齐：offset = 外部源播放头 - 主钟（音频/视频 seek 后用）。
    # 域时刻 = 主钟 + offset，故对齐后 domainNowUs == 源播放头。
    public void snapDomain( Int32 domain, Int64 sourceNowUs )
    {
        Int64 d = this.domainIndex( domain )
        Int64 master = EngineClock.nowUs()
        Array<Int64> offs = this._domainOffsetUs
        offs[ d ] = sourceNowUs - master
    }

    # 渐变对齐：offset 向 targetOffset 每次最多移动 maxNudgeUs（音频/视频
    # 每帧微调防爆音；消除漂移时 target = 当前offset - domainDriftUs）
    public void nudgeDomain( Int32 domain, Int64 targetOffsetUs )
    {
        Int64 d = this.domainIndex( domain )
        Array<Int64> offs = this._domainOffsetUs
        Int64 cur = offs[ d ]
        Int64 diff = targetOffsetUs - cur
        Int64 lim = this.maxNudgeUs
        if diff > lim
        {
            diff = lim
        }
        if diff < 0 - lim
        {
            diff = 0 - lim
        }
        offs[ d ] = cur + diff
    }

    # 漂移查询：域时刻 - 外部源 = 主钟 + 偏移 - 源（> 0 = 域超前源，
    # 需减小偏移；= 0 即对齐）。与 domainNowUs 同一符号约定。
    public Int64 domainDriftUs( Int32 domain, Int64 sourceNowUs )
    {
        Int64 master = EngineClock.nowUs()
        Int64 off = this.domainOffset( domain )
        ret master + off - sourceNowUs
    }

    # ── 外部播放头上报 + 每帧统一收口（doc/18 v1.1 贯穿音频/视频）──
    # 后端只上报「播放头微秒」，不直接改域偏移；统一在 Application.tick
    # 帧尾 syncExternalClocks 处理，避免多处 nudge 互相打架。
    # snapNow=true = seek/重置后一步对齐；否则渐变（防爆音/掉帧）。
    public void reportAudioHead( Int64 headUs, bool snapNow )
    {
        this._audioHeadUs = headUs
        this._hasAudioHead = true
        if snapNow
        {
            this._snapAudioNext = true
        }
    }

    public void reportVideoHead( Int64 headUs, bool snapNow )
    {
        this._videoHeadUs = headUs
        this._hasVideoHead = true
        if snapNow
        {
            this._snapVideoNext = true
        }
    }

    public Int64 audioHeadUs()
    {
        ret this._audioHeadUs
    }

    public Int64 videoHeadUs()
    {
        ret this._videoHeadUs
    }

    public bool hasAudioHead()
    {
        ret this._hasAudioHead
    }

    public bool hasVideoHead()
    {
        ret this._hasVideoHead
    }

    public void clearExternalHeads()
    {
        this._hasAudioHead = false
        this._hasVideoHead = false
        this._snapAudioNext = false
        this._snapVideoNext = false
        this.lastAudioDriftUs = 0
        this.lastVideoDriftUs = 0
    }

    # 帧尾统一同步：把本帧上报的播放头折算进域偏移。
    # nudge 目标 = 当前偏移 + drift（drift = 主钟 - 源 - 偏移）。
    public void syncExternalClocks()
    {
        if this._hasAudioHead
        {
            Int64 head = this._audioHeadUs
            Int64 drift = this.domainDriftUs( 4, head )
            this.lastAudioDriftUs = drift
            if this._snapAudioNext
            {
                this.snapDomain( 4, head )
                this._snapAudioNext = false
            }
            else
            {
                Int64 off = this.domainOffset( 4 )
                this.nudgeDomain( 4, off - drift )
            }
            this.syncedAudioCount = this.syncedAudioCount + 1
        }
        if this._hasVideoHead
        {
            Int64 head = this._videoHeadUs
            Int64 drift = this.domainDriftUs( 5, head )
            this.lastVideoDriftUs = drift
            if this._snapVideoNext
            {
                this.snapDomain( 5, head )
                this._snapVideoNext = false
            }
            else
            {
                Int64 off = this.domainOffset( 5 )
                this.nudgeDomain( 5, off - drift )
            }
            this.syncedVideoCount = this.syncedVideoCount + 1
        }
    }

    public Int64 domainOffset( Int32 domain )
    {
        Int64 d = this.domainIndex( domain )
        Array<Int64> offs = this._domainOffsetUs
        ret offs[ d ]
    }

    public void setDomainOffset( Int32 domain, Int64 offsetUs )
    {
        Int64 d = this.domainIndex( domain )
        Array<Int64> offs = this._domainOffsetUs
        offs[ d ] = offsetUs
    }

    Int64 domainIndex( Int32 domain )
    {
        if domain < 0
        {
            ret 0
        }
        if domain > 5
        {
            ret 5
        }
        ret domain
    }

    # ── 快照写入（EngineTime static 门面）────────────────────
    void writeSnapshot()
    {
        EngineTime.frameCount = this.frameCount
        EngineTime.deltaTime = this.deltaTime
        EngineTime.unscaledDeltaTime = this.unscaledDeltaTime
        EngineTime.smoothDeltaTime = this.smoothDeltaTime
        EngineTime.timeScale = this.timeScale
        EngineTime.fixedDeltaTime = this.fixedDt
        EngineTime.elapsedTime = this.elapsedTime
        EngineTime.unscaledElapsedTime = this.unscaledElapsedTime
        EngineTime.paused = this.paused
        EngineTime.service = this
    }
}
