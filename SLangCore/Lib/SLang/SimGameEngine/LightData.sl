import Core;
import Std;
import Math;
import SLangRender;

# ============================================================================
# LightData — 引擎侧光源组件（v2.13，doc/19 §6）
# ----------------------------------------------------------------------------
# 分层契约（2026-11-18 定稿）：引擎层持有「实体光源对象」（本类，挂场景
# 节点、带位置/方向/锥角/范围/阴影等形状属性，随引擎逻辑变化），Render
# 层（SLangRender）只有「数据」—— RenderLight 槽位门面。本类 applyTo
# 即 Engine -> Render 的转换点：每帧 RenderSystem.sync 收集场景中的
# LightData，按发现顺序把最终参数写入管线光照槽 0..7（SLR_MAX_LIGHTS=8；
# 固化着色器消费首个平行光 + 首个聚光，点光为预留槽）。
# 参数布局与 SLangRender.RenderLight.applyTo 完全一致（vm_sl_render.h v3.3）：
#   平行光 [dirX, dirY, r, g, b, intensity, shadowQuality, bias, strength, cascades]
#   聚光   [posX, posY, dirX, dirY, angleDeg, range, r, g, b, intensity]
# dir 为 2D 光照方向（平行光 = 表面 -> 光源方向；聚光 = 光轴方向）。
# 自带 applyTo（不经 RenderLight 对象转发，避免跨模块对象创建）。
# ============================================================================
public class LightData extends Behaviour
{
    # 0 = Directional, 1 = Point（预留）, 2 = Spot
    public Int32 type = 0
    public Float32_3 color = Float32_3( 1.0f, 1.0f, 1.0f )
    public Float32 intensity = 1.0f
    public Float32 dirX = 1.0f
    public Float32 dirY = 0.0f
    public Float32 posX = 0.0f
    public Float32 posY = 0.0f
    # 聚光有效：圆锥半角（角度制，光轴两侧）；lightRange：range 是保留字避让
    public Float32 spotAngle = 30.0f
    public Float32 lightRange = 0.0f
    # 阴影：1 = shadow map（仅平行光，GL/GLES；VK/D3D11 回退黑斑路径）
    public Float32 shadowQuality = 0.0f
    public Float32 shadowBias = 0.0f
    public Float32 shadowStrength = 0.0f
    public Float32 shadowCascades = 0.0f

    static Int64 _applyPtr = 0

    public bool applyTo( SLang.RenderPipeline pipe, Int32 slot )
    {
        if pipe == null
        {
            ret false
        }
        if LightData._applyPtr == 0
        {
            LightData._applyPtr = Memory.alloc( 40 )
            if LightData._applyPtr == 0
            {
                ret false
            }
        }
        Int64 p = LightData._applyPtr
        Float32 cr = this.color.x
        Float32 cg = this.color.y
        Float32 cb = this.color.z
        Int32 ty = this.type
        if ty == 2
        {
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

    # 脚本动效写入口（跨模块字段直写不可靠，统一走方法；doc/10 §6）
    public void setSwing( Float32 x, Float32 intensity )
    {
        this.posX = x
        this.intensity = intensity
    }

    override string toString()
    {
        ret String.toFormat( "LightData(type={0}, intensity={1})",
            this.type.toString(), this.intensity.toString() )
    }
}
