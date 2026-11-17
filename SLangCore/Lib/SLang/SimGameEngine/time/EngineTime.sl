import Core;
import Std;
import Math;

# ============================================================================
# EngineTime — 时间读数 static 门面（doc/18；TimeService 每帧写入快照）
# ----------------------------------------------------------------------------
# 脚本/渲染/音频/视频/物理统一的只读时间视图：每帧 advanceFrame 后全部字段
# 反映本帧读数。域时钟（音频/视频播放头对齐）提供按域的便捷查询——static
# 常量不作实参（doc/10 §6），故每域给具体方法（内部走字面量域号）。
#
# 用法（Behaviour.update / fixedUpdate 内）：
#   Float32 dt = EngineTime.deltaTime          # 本帧 scaled dt（秒）
#   Int32 fc = EngineTime.frameCount
#   Float32 a = EngineTime.fixedAlpha          # 固定步插值系数（渲染侧用）
#   Int64 ap = EngineTime.audioNowUs()         # 音频域时钟（播放头对齐后）
# ============================================================================

public class EngineTime
{
    # ── 域号（TimeService 域表索引；0..5）──
    public static Int32 DOMAIN_MASTER = 0
    public static Int32 DOMAIN_RENDER = 1
    public static Int32 DOMAIN_PHYSICS = 2
    public static Int32 DOMAIN_LOGIC = 3
    public static Int32 DOMAIN_AUDIO = 4
    public static Int32 DOMAIN_VIDEO = 5

    # ── 每帧快照（只读；TimeService.advanceFrame 写入）──
    public static Int64 frameCount = 0
    public static Float32 deltaTime = 0.0f
    public static Float32 unscaledDeltaTime = 0.0f
    public static Float32 smoothDeltaTime = 0.0f
    public static Float32 timeScale = 1.0f
    public static Float32 fixedDeltaTime = 0.0166667f
    public static Float32 fixedAlpha = 0.0f
    public static Float32 elapsedTime = 0.0f
    public static Float32 unscaledElapsedTime = 0.0f
    public static bool paused = false

    # 活跃 TimeService（Application.init 创建；null = 未初始化）
    public static TimeService service = null

    # ── 域时钟便捷查询（static 常量不作实参 → 每域一个方法）────

    # 渲染域时钟（微秒；与主钟一致，域偏移可由渲染侧设置）
    public static Int64 renderNowUs()
    {
        ret EngineTime.domainNow( 1 )
    }

    # 物理域时钟
    public static Int64 physicsNowUs()
    {
        ret EngineTime.domainNow( 2 )
    }

    # 逻辑域时钟
    public static Int64 logicNowUs()
    {
        ret EngineTime.domainNow( 3 )
    }

    # 音频域时钟（宿主把音频播放头 snap/nudge 对齐后即引擎音频时间）
    public static Int64 audioNowUs()
    {
        ret EngineTime.domainNow( 4 )
    }

    # 视频域时钟
    public static Int64 videoNowUs()
    {
        ret EngineTime.domainNow( 5 )
    }

    # 通用域查询（domain 为局部变量时用）
    public static Int64 domainNowUs( Int32 domain )
    {
        ret EngineTime.domainNow( domain )
    }

    static Int64 domainNow( Int32 domain )
    {
        TimeService svc = EngineTime.service
        if svc == null
        {
            ret EngineClock.nowUs()
        }
        ret svc.domainNowUs( domain )
    }
}
