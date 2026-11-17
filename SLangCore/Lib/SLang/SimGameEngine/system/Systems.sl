import Core;
import Std;
import Math;
import SLangRender;
import SLangAudio;

# ============================================================================
# Systems — 引擎系统总注册门面（system/ 层）
# ----------------------------------------------------------------------------
# 仿 Unity 的系统总逻辑聚合点：碰撞 / 渲染 / 音频三个子系统的统一持有、
# 初始化、逐帧驱动与释放。与 Application 的接线（doc/09 §2 帧序）：
#   - app.collisionSystem = systems.collision   （固定步自动 step，P3）
#   - 每渲染帧：systems.sync(scene, time) → systems.frame(time, dstPtr)
# 使用（消费方工程）：
#   Systems sys = Systems()
#   sys.init( 480, 360 )                         # 渲染管线 + 音频后端
#   app.collisionSystem = sys.collision          # 碰撞挂固定步
#   ... app.tick(dt) 循环 ...
#   Int32 n = sys.sync( app.activeScene, time )  # 场景→RenderObject
#   sys.frame( time, dstPtr )                    # 出帧到 RGBA8 原生块
#   sys.shutdown()
# ============================================================================

public class Systems
{
    public CollisionSystem collision = CollisionSystem()
    public RenderSystem render = RenderSystem()
    public AudioSystem audio = AudioSystem()

    # 初始化全部子系统（渲染 w×h 离屏目标 + 音频后端）；
    # 返回 false 时逐项排查（render.ready / audio.ready / audio.lastError）
    public bool init( Int32 width, Int32 height )
    {
        bool r = this.render.init( width, height )
        bool a = this.audio.init()
        ret r && a
    }

    # 固定步驱动（与 Application.collisionSystem 二选一——都挂时以
    # Application 的为准；本方法供手动驱动形态使用）
    public void fixedStep( Scene scene )
    {
        this.collision.step( scene )
    }

    # 场景 → RenderObject 同步（渲染帧开头调用）；返回提交对象数
    public Int32 sync( Scene scene, Float32 time )
    {
        ret this.render.sync( scene )
    }

    # 出帧（RGBA8 → dstPtr 原生块）
    public bool frame( Float32 time, Int64 dstPtr )
    {
        ret this.render.frame( time, dstPtr )
    }

    public void shutdown()
    {
        this.audio.shutdown()
        this.render.shutdown()
    }
}
