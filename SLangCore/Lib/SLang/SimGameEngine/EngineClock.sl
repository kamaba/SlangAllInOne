import Core;
import Std;

# ============================================================================
# EngineClock — 引擎统一时间周期（C99 高精度时钟封装，doc/09 §1）
# ----------------------------------------------------------------------------
# 贯穿逻辑 / 渲染 / 音频 / 物理的统一单调时间源（QueryPerformanceCounter，
# 跨平台 fallback clock_gettime）。全部返回整型（微秒/毫秒），避免浮点跨界。
# 用法：
#   Int64 frameStart = EngineClock.nowUs()
#   ... 逻辑 ...
#   Int64 logicUs = EngineClock.nowUs() - frameStart
# 帧间隔：EngineClock.mark() 每帧调用一次（Application.tick 已自动调，
# deltaTime 字段读秒值）。
# 定时器（查询式）：Timer 句柄 start/elapsedUs/reset/destroy。
# ============================================================================

public class EngineClock
{
    # 单调时钟微秒（进程内一致基准）
    public static Int64 nowUs()
    {
        ret EngineFfi.libTimeNowUs()
    }

    # 单调时钟毫秒
    public static Int64 nowMs()
    {
        ret EngineClock.nowUs() / 1000
    }

    # 帧标记：返回距上次调用的微秒数（每帧调一次即帧间隔采样）
    public static Int64 mark()
    {
        ret EngineFfi.libTimeMark()
    }

    # ── 定时器（句柄 1 起始；0 = 表满）────────────────────
    public static Int64 timerCreate()
    {
        ret EngineFfi.libTimerCreate()
    }

    public static bool timerStart( Int64 h )
    {
        ret EngineFfi.libTimerStart( h ) == 1
    }

    # 已流逝微秒（未启动 / 无效返回 -1）
    public static Int64 timerElapsedUs( Int64 h )
    {
        ret EngineFfi.libTimerElapsedUs( h )
    }

    public static bool timerReset( Int64 h )
    {
        ret EngineFfi.libTimerReset( h ) == 1
    }

    public static bool timerDestroy( Int64 h )
    {
        ret EngineFfi.libTimerDestroy( h ) == 1
    }
}

# ============================================================================
# Timer — 定时器对象封装（RAII 形态；显式 destroy 释放句柄）
# ============================================================================

public class Timer
{
    public Int64 handle = 0

    public static Timer create()
    {
        Timer t = Timer()
        t.handle = EngineClock.timerCreate()
        ret t
    }

    public bool valid()
    {
        ret this.handle > 0
    }

    public bool start()
    {
        ret EngineClock.timerStart( this.handle )
    }

    # 已流逝毫秒（未启动返回 -1）
    public Int64 elapsedMs()
    {
        ret EngineClock.timerElapsedUs( this.handle ) / 1000
    }

    public bool reset()
    {
        ret EngineClock.timerReset( this.handle )
    }

    public void destroy()
    {
        EngineClock.timerDestroy( this.handle )
        this.handle = 0
    }
}
