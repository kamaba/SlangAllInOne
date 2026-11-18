import SimGameEngine;
import Std;
import Math;
import SLangRender;

# ============================================================================
# SimTimeTest — 引擎统一时间同步验证（第 14 套，doc/18）
# ----------------------------------------------------------------------------
# 覆盖：TimeService 帧推进（裁剪/暂停/timeScale/平滑 dt/累计时长/帧号）、
# 固定步长累加器（步数消费/上限防螺旋死亡）、固定步插值系数 alpha、
# 自动实测帧间隔（rawDt<0）、域时钟（render/physics/logic/audio/video：
# offset/now/drift/snap/nudge 渐变对齐）、Application.tick 全链路集成
# （探针钩子计数 + EngineTime static 快照 + 旧 deltaTime 字段兼容）。
# 写法约束（doc/10 §6）：时间值全用 2 的幂（二进制精确断言）；域号用字面量
# （static 常量不作实参）；方法调用不作实参；&& 只写双操作数。
# ============================================================================

public class SimTimeTest
{
    static Int32 _pass = 0
    static Int32 _fail = 0

    static void check( bool cond, string msg )
    {
        if cond
        {
            _pass = _pass + 1
        }
        else
        {
            _fail = _fail + 1
            Console.println( "[FAIL] " + msg )
        }
    }

    static bool near( Float32 a, Float32 b )
    {
        Float32 d = a - b
        if d < 0.0f
        {
            d = 0.0f - d
        }
        ret d < 0.0001f
    }

    static Int32 passCount()
    {
        ret _pass
    }

    static Int32 failCount()
    {
        ret _fail
    }

    # 测试用 Behaviour：fixedUpdate/update 计数探针
    public class TimeProbe extends Behaviour
    {
        public Int32 fixedCount = 0
        public Int32 updateCount = 0

        override void fixedUpdate()
        {
            this.fixedCount = this.fixedCount + 1
        }
        override void update()
        {
            this.updateCount = this.updateCount + 1
        }
    }

    # 新建已配置的服务（时间值全 2 的幂保证精确断言）
    static TimeService fresh( Float32 fixedDt, Float32 maxDt, Int32 maxSteps )
    {
        TimeService t = TimeService()
        t.syncConfig( false, 1.0f, fixedDt, maxDt, maxSteps )
        ret t
    }

    # ── T1. 帧推进基础 + EngineTime 快照 ──────────────────
    static void testAdvanceBasics()
    {
        TimeService t = fresh( 0.0625f, 0.125f, 5 )
        t.advanceFrame( 0.0625f )
        check( t.frameCount == 1, "T1 frameCount==1" )
        check( near( t.deltaTime, 0.0625f ), "T1 deltaTime" )
        check( near( t.unscaledDeltaTime, 0.0625f ), "T1 unscaledDeltaTime" )
        check( near( t.smoothDeltaTime, 0.0625f ), "T1 smooth first frame = raw" )
        check( t.pendingFixedSteps == 1, "T1 pending fixed steps == 1" )
        t.consumeFixedStep()
        check( t.pendingFixedSteps == 0, "T1 consumed" )
        check( near( t.fixedAcc, 0.0f ), "T1 accumulator drained" )
        t.updateFixedAlpha()
        check( near( t.fixedAlpha, 0.0f ), "T1 alpha 0 when drained" )
        # EngineTime static 快照同步
        check( EngineTime.frameCount == 1, "T1 snapshot frameCount" )
        check( near( EngineTime.deltaTime, 0.0625f ), "T1 snapshot deltaTime" )
        check( near( EngineTime.fixedDeltaTime, 0.0625f ), "T1 snapshot fixedDeltaTime" )
        check( near( EngineTime.unscaledDeltaTime, 0.0625f ), "T1 snapshot unscaled" )
        check( near( EngineTime.elapsedTime, 0.0625f ), "T1 snapshot elapsed" )
    }

    # ── T2. dt 上限裁剪 ───────────────────────────────────
    static void testClamp()
    {
        TimeService t = fresh( 0.0625f, 0.125f, 5 )
        t.advanceFrame( 1.0f )
        check( near( t.deltaTime, 0.125f ), "T2 clamped to maxDeltaTime" )
        check( near( t.unscaledDeltaTime, 0.125f ), "T2 unscaled clamped too" )
    }

    # ── T3. 暂停（scaled 停、unscaled 走、无固定步）───────
    static void testPause()
    {
        TimeService t = fresh( 0.0625f, 0.125f, 5 )
        t.advanceFrame( 0.0625f )
        Float32 el0 = t.elapsedTime
        t.syncConfig( true, 1.0f, 0.0625f, 0.125f, 5 )
        t.advanceFrame( 0.125f )
        check( near( t.deltaTime, 0.0f ), "T3 paused scaled dt 0" )
        check( near( t.unscaledDeltaTime, 0.125f ), "T3 unscaled keeps flowing" )
        check( t.pendingFixedSteps == 0, "T3 no fixed steps when paused" )
        check( near( t.elapsedTime, el0 ), "T3 elapsed frozen" )
        check( near( t.unscaledElapsedTime, 0.1875f ), "T3 unscaled elapsed accumulates" )
    }

    # ── T4. timeScale（缩放 dt 与固定步数，unscaled 不动）──
    static void testTimeScale()
    {
        TimeService t = fresh( 0.0625f, 0.125f, 5 )
        t.syncConfig( false, 0.5f, 0.0625f, 0.125f, 5 )
        t.advanceFrame( 0.125f )
        check( near( t.deltaTime, 0.0625f ), "T4 scaled dt half" )
        check( near( t.unscaledDeltaTime, 0.125f ), "T4 unscaled raw" )
        check( t.pendingFixedSteps == 1, "T4 fixed steps use scaled" )
    }

    # ── T5. 固定步多步消费（maxDt 足够大不被裁剪）─────────
    static void testFixedSteps()
    {
        TimeService t = fresh( 0.0625f, 1.0f, 5 )
        t.advanceFrame( 0.25f )
        check( t.pendingFixedSteps == 4, "T5 four steps pending" )
        Int32 i = 0
        while i < 4
        {
            t.consumeFixedStep()
            i = i + 1
        }
        check( t.pendingFixedSteps == 0, "T5 all consumed" )
        check( near( t.fixedAcc, 0.0f ), "T5 accumulator exact zero (power of two)" )
    }

    # ── T6. maxFixedSteps 上限（防螺旋死亡，余量丢弃）─────
    static void testStepCap()
    {
        TimeService t = fresh( 0.0625f, 1.0f, 5 )
        t.advanceFrame( 0.5f )   # 需 8 步，上限 5
        check( t.pendingFixedSteps == 5, "T6 capped at maxFixedSteps" )
        Int32 i = 0
        while i < 5
        {
            t.consumeFixedStep()
            i = i + 1
        }
        check( near( t.fixedAcc, 0.0f ), "T6 excess dropped (no spiral)" )
    }

    # ── T7. 固定步插值系数 alpha ──────────────────────────
    static void testFixedAlpha()
    {
        TimeService t = fresh( 0.0625f, 0.125f, 5 )
        t.advanceFrame( 0.09375f )   # 1.5 步
        check( t.pendingFixedSteps == 1, "T7 one full step" )
        t.consumeFixedStep()
        t.updateFixedAlpha()
        check( near( t.fixedAlpha, 0.5f ), "T7 alpha = residual/fixedDt" )
        check( near( EngineTime.fixedAlpha, 0.5f ), "T7 snapshot alpha" )
    }

    # ── T8. 累计时长 / 平滑 dt（EMA）──────────────────────
    static void testAccumulators()
    {
        TimeService t = fresh( 0.0625f, 0.125f, 5 )
        t.advanceFrame( 0.0625f )
        t.advanceFrame( 0.0625f )
        check( t.frameCount == 2, "T8 frameCount 2" )
        check( near( t.elapsedTime, 0.125f ), "T8 scaled elapsed" )
        check( near( t.unscaledElapsedTime, 0.125f ), "T8 unscaled elapsed" )
        check( near( t.smoothDeltaTime, 0.0625f ), "T8 smooth stable for constant dt" )
        t.advanceFrame( 0.125f )
        check( near( t.smoothDeltaTime, 0.06875f ), "T8 smooth EMA toward new dt" )
    }

    # ── T9. 自动实测（rawDt<0：首帧 0，次帧真实间隔）──────
    static void testAutoMeasure()
    {
        TimeService t = fresh( 0.0625f, 0.125f, 5 )
        t.advanceFrame( 0.0f - 1.0f )
        check( near( t.deltaTime, 0.0f ), "T9 auto first frame dt 0" )
        t.advanceFrame( 0.0f - 1.0f )
        check( t.frameCount == 2, "T9 frameCount 2" )
        bool inRange = ( t.deltaTime >= 0.0f ) && ( t.deltaTime < 0.125f )
        check( inRange, "T9 auto dt within [0, maxDeltaTime)" )
        check( near( t.unscaledDeltaTime, t.deltaTime ), "T9 auto not scaled (scale=1)" )
    }

    # ── T10. 域时钟（offset/now/drift/snap/nudge）─────────
    static void testDomains()
    {
        TimeService t = fresh( 0.0625f, 0.125f, 5 )
        # 域 4 = audio：offset 直设 +1s
        t.setDomainOffset( 4, 1000000 )
        check( t.domainOffset( 4 ) == 1000000, "T10 offset set/get" )
        Int64 dn = t.domainNowUs( 4 )
        Int64 mn = EngineClock.nowUs()
        Int64 gap = dn - mn
        # gap ≈ offset（两次 nowUs 间时钟几乎不动；容差 ±1ms）
        bool okGap = ( gap > 999000 ) && ( gap < 1001000 )
        check( okGap, "T10 domain now = master + offset" )
        # drift：源与主钟同相推进 → drift ≈ 0
        Int64 m0 = EngineClock.nowUs()
        t.snapDomain( 5, m0 )                    # 域 5 = video 对齐主钟
        Int64 m1 = EngineClock.nowUs()
        Int64 src = m0 + ( m1 - m0 )             # 源推进 = 真实推进
        Int64 drift = t.domainDriftUs( 5, src )
        bool okDrift = ( drift > 0 - 1000 ) && ( drift < 1000 )
        check( okDrift, "T10 drift ~0 when source in phase" )
        # nudge 渐变对齐（maxNudge=2000us/次）
        t.setDomainOffset( 3, 0 )                # 域 3 = logic
        t.nudgeDomain( 3, 100000 )
        check( t.domainOffset( 3 ) == 2000, "T10 nudge single step" )
        t.nudgeDomain( 3, 100000 )
        t.nudgeDomain( 3, 100000 )
        check( t.domainOffset( 3 ) == 6000, "T10 nudge accumulates" )
        t.nudgeDomain( 3, 0 - 50000 )            # 反向渐变
        check( t.domainOffset( 3 ) == 4000, "T10 nudge reverse" )
        # domainDeltaUs（首调记基线返回 0，次调为真实间隔 >= 0）
        t.domainDeltaUs( 2 )
        Int64 d2 = t.domainDeltaUs( 2 )
        check( d2 >= 0, "T10 domain delta >= 0" )
    }

    # ── T11. 域号越界钳制 ─────────────────────────────────
    static void testDomainClamp()
    {
        TimeService t = fresh( 0.0625f, 0.125f, 5 )
        check( t.domainOffset( 0 - 1 ) == 0, "T11 clamp low to master" )
        check( t.domainOffset( 99 ) == 0, "T11 clamp high to master" )
    }

    # ── T12. Application 全链路（探针钩子 + 快照 + 兼容镜像）──
    static void testApplicationIntegration()
    {
        Application app = Application()
        app.init()
        check( app.time != null, "T12 time service created on init" )
        check( EngineTime.service == app.time, "T12 EngineTime bound to service" )
        Scene scene = app.activeScene
        GameObject go = scene.createObject( "TP" )
        TimeProbe p = TimeProbe()
        go.addComponent( p )
        app.fixedDt = 0.0625f
        app.maxDeltaTime = 0.5f
        # 首帧自动实测：dt=0（无步、无 update）
        app.tick( 0.0f - 1.0f )
        check( EngineTime.frameCount == 1, "T12 auto first frame counted" )
        check( p.fixedCount == 0, "T12 no fixed step at dt 0" )
        # 第二帧显式 0.0625：1 个固定步 + 1 次 update
        app.tick( 0.0625f )
        check( near( EngineTime.deltaTime, 0.0625f ), "T12 EngineTime dt" )
        check( near( app.deltaTime, 0.0625f ), "T12 legacy deltaTime mirror" )
        check( p.fixedCount == 1, "T12 one fixed step" )
        check( p.updateCount == 1, "T12 one update" )
        # 0.25 = 4 步整除 → alpha 0
        app.tick( 0.25f )
        check( p.fixedCount == 5, "T12 four more fixed steps" )
        check( near( EngineTime.fixedAlpha, 0.0f ), "T12 alpha drained on exact frame" )
        # 0.09375 = 1.5 步 → alpha 0.5
        app.tick( 0.09375f )
        check( p.fixedCount == 6, "T12 one more fixed step" )
        check( near( EngineTime.fixedAlpha, 0.5f ), "T12 alpha half step" )
        # 暂停：dt 0 / 无 update / 无步
        app.paused = true
        app.tick( 0.125f )
        check( near( EngineTime.deltaTime, 0.0f ), "T12 paused snapshot dt 0" )
        check( p.updateCount == 3, "T12 no update when paused (still 3)" )
        check( p.fixedCount == 6, "T12 no fixed step when paused" )
        # timeScale：scaled 固定步长不受影响
        app.paused = false
        app.timeScale = 0.5f
        app.tick( 0.125f )
        check( near( EngineTime.deltaTime, 0.0625f ), "T12 scaled dt" )
        check( near( EngineTime.timeScale, 0.5f ), "T12 timeScale snapshot" )
        check( near( EngineTime.unscaledDeltaTime, 0.125f ), "T12 unscaled raw" )
        app.shutdown()
    }

    # ── T13. EngineTime 域便捷查询（默认 offset 全 0 同相）──
    static void testEngineTimeDomainFacades()
    {
        Application app = Application()
        app.init()
        app.tick( 0.0625f )
        Int64 rn = EngineTime.renderNowUs()
        Int64 an = EngineTime.audioNowUs()
        Int64 vn = EngineTime.videoNowUs()
        Int64 pn = EngineTime.physicsNowUs()
        Int64 ln = EngineTime.logicNowUs()
        Int64 da = an - rn
        bool okA = ( da > 0 - 1000 ) && ( da < 1000 )
        check( okA, "T13 audio clock in phase with render (offset 0)" )
        Int64 dv = vn - pn
        bool okV = ( dv > 0 - 1000 ) && ( dv < 1000 )
        check( okV, "T13 video clock in phase with physics" )
        Int64 dl = ln - rn
        bool okL = ( dl > 0 - 1000 ) && ( dl < 1000 )
        check( okL, "T13 logic clock in phase with render" )
        # 音频播放头挂接闭环：snap 对齐后 drift 收敛
        Int64 m0 = EngineClock.nowUs()
        app.time.snapDomain( 4, m0 )
        Int64 m1 = EngineClock.nowUs()
        Int64 src = m0 + ( m1 - m0 )
        Int64 drift = app.time.domainDriftUs( 4, src )
        bool okSync = ( drift > 0 - 1000 ) && ( drift < 1000 )
        check( okSync, "T13 audio snap-to-master closed loop" )
        app.shutdown()
    }

    # ── T14. 外部播放头上报 + 帧尾统一域收口（doc/18 v1.1）──
    static void testExternalClockSync()
    {
        TimeService t = fresh( 0.0625f, 0.125f, 5 )
        Int64 head = EngineClock.nowUs() - 250000
        t.reportAudioHead( head, true )
        t.reportVideoHead( head, false )
        check( t.hasAudioHead(), "T14 audio head registered" )
        check( t.hasVideoHead(), "T14 video head registered" )
        check( t.audioHeadUs() == head, "T14 audio head value" )
        check( t.videoHeadUs() == head, "T14 video head value" )
        t.syncExternalClocks()
        check( t.syncedAudioCount == 1, "T14 audio sync once" )
        check( t.syncedVideoCount == 1, "T14 video sync once" )
        Int64 offA = t.domainOffset( 4 )
        Int64 wantA = head - EngineClock.nowUs()
        bool okA = ( offA - wantA > -5000 ) && ( offA - wantA < 5000 )
        check( okA, "T14 audio snap offset = head - master" )
        Int64 nowA = t.domainNowUs( 4 )
        bool okNow = ( nowA - head > -5000 ) && ( nowA - head < 5000 )
        check( okNow, "T14 audio domain now tracks playback head" )
        Int64 off0 = t.domainOffset( 5 )
        t.reportVideoHead( head, false )
        t.syncExternalClocks()
        Int64 moved = t.domainOffset( 5 ) - off0
        bool bounded = ( moved <= t.maxNudgeUs ) && ( moved >= 0 - t.maxNudgeUs )
        check( bounded, "T14 video nudge bounded by maxNudgeUs" )
        t.clearExternalHeads()
        check( t.hasAudioHead() == false, "T14 clear heads audio" )
        check( t.hasVideoHead() == false, "T14 clear heads video" )
    }

    # ── T15. 视频钟 / 渲染统一时间门面（贯穿闭环）──────────
    static void testCycleFacades()
    {
        Application app = Application()
        app.init()
        check( app.videoClock != null, "T15 VideoClock created on init" )
        Int64 head = EngineClock.nowUs() - 125000
        bool ok = app.videoClock.reportHeadUs( head, true )
        check( ok, "T15 VideoClock report head" )
        check( app.videoClock.reportCount == 1, "T15 VideoClock report count" )
        check( app.videoClock.hasHead(), "T15 VideoClock has head" )
        app.tick( 0.0625f )
        check( app.time.syncedVideoCount == 1, "T15 frame tail synced video domain" )
        Int64 vn = app.videoClock.nowUs()
        bool okV = ( vn - head > -5000 ) && ( vn - head < 5000 )
        check( okV, "T15 video domain follows reported head" )
        RenderSystem rs = RenderSystem()
        check( near( rs.resolveTime( 0.0f - 1.0f ), EngineTime.elapsedTime ),
            "T15 render frame uses EngineTime.elapsedTime" )
        check( near( rs.resolveTime( 0.25f ), 0.25f ), "T15 explicit render time kept" )
        app.shutdown()
    }

    public static void run()
    {
        Console.println( "" )
        Console.println( "===== SimTimeTest (unified time sync) =====" )
        testAdvanceBasics()
        testClamp()
        testPause()
        testTimeScale()
        testFixedSteps()
        testStepCap()
        testFixedAlpha()
        testAccumulators()
        testAutoMeasure()
        testDomains()
        testDomainClamp()
        testApplicationIntegration()
        testEngineTimeDomainFacades()
        testExternalClockSync()
        testCycleFacades()
        Console.println( "===== SimTimeTest PASS=" + _pass.toString() + " FAIL=" + _fail.toString() + " =====" )
    }
}
