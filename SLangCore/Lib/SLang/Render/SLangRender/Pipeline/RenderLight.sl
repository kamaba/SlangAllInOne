import Std;
import Math;
# ============================================================================
# RenderLight —— 管线光照槽门面（Render 层唯一光照表示，2026-11-18 分层定稿）
# ----------------------------------------------------------------------------
# 与 RenderCamera 同款的「渲染槽位门面」形态：本类只承载「写入渲染管线
# 光照槽（slot 0..7）的最终数据」+ applyTo 直写，不含任何实体/场景语义。
#
# 分层契约（Engine -> Render 数据流）：
#   引擎层（SimGameEngine）持有带 Transform / 灯形状等属性的实体光源
#   （LightData：场景节点组件，方向/位置随节点变换、聚光锥角/范围/阴影
#   参数等），经引擎逻辑（场景同步、灯光摆动脚本等）处理后，在每帧
#   RenderSystem.sync 里把「最终光照参数」写入 Render 层槽位 ——
#   LightData.applyTo 与本类 applyTo 的参数块布局完全一致
#   （vm_sl_render.h v3.3：平行光 10 项 / 聚光 10 项）。
#   即：Engine 的 Light/Camera 是「对象」，Render 的 RenderLight/
#   RenderCamera 是「数据」。本类不继承 Component、不挂 Transform、
#   不做衰减/锥角采样等实体逻辑（那些属于引擎层）。
# ============================================================================
public class RenderLight
{
    # 光照类型：0 = Directional, 1 = Point（预留槽）, 2 = Spot
    public Int32 type = 0

    public Color color = Color.white()

    # 强度（通常 [0, 8+]）
    public Float32 intensity = 1.0f

    # 字段名 lightRange：range 是小写容器构造糖（range() => Range），类成员名须避让
    public Float32 lightRange = 0.0f

    # 聚光有效：圆锥半角（角度制，光轴两侧）
    public Float32 spotAngle = 30.0f

    # 阴影
    public bool castShadow = false
    # 阴影质量：0 = 旧 2D 投影黑斑（默认）；1 = shadow map
    # （光空间深度图 + shader PCF；仅平行光生效，VK 后端按 0 回退）
    public Float32 shadowQuality = 0.0f
    # CSM 参数（0 = 管线默认 bias 0.002 / strength 0.35 / 单级联）：
    # shadowBias 防 acne 深度偏移；shadowStrength 阴影强度覆盖（0..1）；
    # shadowCascades 级联数（1 = 单级；4 = CSM 4 级联 v 分段 0.05/0.25/0.6/1.0）
    public Float32 shadowBias = 0.0f
    public Float32 shadowStrength = 0.0f
    public Float32 shadowCascades = 0.0f

    # ── 显式光照参数（applyTo 写管线槽用）──────────────────
    # dirX/dirY：平行光 = 表面 -> 光源方向；聚光 = 光轴方向（光源 -> 外）
    # posX/posY：聚光世界位置
    public Float32 dirX = 1.0f
    public Float32 dirY = 0.0f
    public Float32 posX = 0.0f
    public Float32 posY = 0.0f

    # ── 构造 / 类型判定 ──────────────────────────────────
    public void _init_()
    {
        this.type = 0
        this.color = Color.white()
        this.intensity = 1.0f
        this.lightRange = 0.0f
        this.spotAngle = 30.0f
        this.castShadow = false
        this.shadowQuality = 0.0f
        this.shadowBias = 0.0f
        this.shadowStrength = 0.0f
        this.shadowCascades = 0.0f
        this.dirX = 1.0f
        this.dirY = 0.0f
        this.posX = 0.0f
        this.posY = 0.0f
    }

    public get bool isDirectional()
    {
        ret this.type == 0
    }

    public get bool isPoint()
    {
        ret this.type == 1
    }

    public get bool isSpot()
    {
        ret this.type == 2
    }

    public void setType( Int32 lightType )
    {
        this.type = lightType
    }

    # ── 预设工厂 ─────────────────────────────────────────
    public static RenderLight directional( Color c, Float32 intensity )
    {
        RenderLight l = RenderLight()
        l.type = 0
        l.color = c.clone()
        l.intensity = intensity
        ret l
    }

    public static RenderLight point( Color c, Float32 intensity, Float32 lightRange )
    {
        RenderLight l = RenderLight()
        l.type = 1
        l.color = c.clone()
        l.intensity = intensity
        l.lightRange = lightRange
        ret l
    }

    public static RenderLight spot( Color c, Float32 intensity, Float32 lightRange, Float32 spotAngleDegrees )
    {
        RenderLight l = RenderLight()
        l.type = 2
        l.color = c.clone()
        l.intensity = intensity
        l.lightRange = lightRange
        l.spotAngle = spotAngleDegrees
        ret l
    }

    # ── 管线接入 ─────────────────────────────────────────
    # applyTo(pipe, slot) —— 把本光源写入管线光照槽（经 Memory 参数块 ->
    # RenderPipeline.setLightParams FFI；布局见 vm_sl_render.h v3.3：
    # 平行光 10 项 / 聚光 10 项）。参数块为类级静态暂存（单线程 VM 复用）。
    static Int64 _applyPtr = 0

    public bool applyTo( SLang.RenderPipeline pipe, Int32 slot )
    {
        if pipe == null || pipe.isValid == false
        {
            ret false
        }
        if RenderLight._applyPtr == 0
        {
            RenderLight._applyPtr = Memory.alloc( 40 )
            if RenderLight._applyPtr == 0
            {
                ret false
            }
        }
        Int64 p = RenderLight._applyPtr
        # 跨模块成员先落局部变量（着色器路径同款规避）
        Float32 cr = this.color.r
        Float32 cg = this.color.g
        Float32 cb = this.color.b
        Int32 ty = this.type
        if ty == 2
        {
            # 聚光：[posX, posY, dirX, dirY, angleDeg, range, r, g, b, intensity]
            Memory.writeF32( p, 0, this.posX )
            Memory.writeF32( p, 4, this.posY )
            Memory.writeF32( p, 8, this.dirX )
            Memory.writeF32( p, 12, this.dirY )
            Memory.writeF32( p, 16, this.spotAngle )
            Memory.writeF32( p, 20, this.lightRange )
            Memory.writeF32( p, 24, cr )
            Memory.writeF32( p, 28, cg )
            Memory.writeF32( p, 32, cb )
            Memory.writeF32( p, 36, this.intensity )
        }
        else
        {
            # 平行光：[dirX, dirY, r, g, b, intensity, shadowQuality,
            #          shadowBias, shadowStrength, shadowCascades]（N2b 扩 10 项）
            Memory.writeF32( p, 0, this.dirX )
            Memory.writeF32( p, 4, this.dirY )
            Memory.writeF32( p, 8, cr )
            Memory.writeF32( p, 12, cg )
            Memory.writeF32( p, 16, cb )
            Memory.writeF32( p, 20, this.intensity )
            Memory.writeF32( p, 24, this.shadowQuality )
            Memory.writeF32( p, 28, this.shadowBias )
            Memory.writeF32( p, 32, this.shadowStrength )
            Memory.writeF32( p, 36, this.shadowCascades )
        }
        ret pipe.setLightParams( slot, ty, p )
    }

    override string toString()
    {
        ret String.toFormat( "RenderLight(type={0}, color={1}, intensity={2})",
            this.type.toString(), this.color.toString(), this.intensity.toString() )
    }
}
