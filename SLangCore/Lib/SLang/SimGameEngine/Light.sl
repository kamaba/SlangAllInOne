import Core;
import Std;
import Math;
import SLangRender;

# ============================================================================
# Light — 光源实体（Unity Light 形态：extends GameObject + LightData 组件）
# ----------------------------------------------------------------------------
# 本节点继承 GameObject（自带 Transform / layer / 层级 / 场景归属），构造期
# 挂一个 LightData 组件承载光源参数（类型 / 颜色 / 强度 / 方向 / 锥角 / 范围 /
# 阴影）。LightData 仍是被 RenderSystem.applyLights 收集的组件；本类只是
# 「光源实体」外壳，提供贴合 Unity 的方向/位置/工厂/衰减访问入口。
#
# 遵循 doc/10 §6：跨模块调用中间结果落局部变量；SLang 子类构造不自动调
# 父类 _init_，故手工复制 GameObject 节点字段初始化。
# 本轮只建结构 + 绑定，不改 RenderSystem 消费链路（by design）。
# ============================================================================
public class Light extends GameObject
{
    public static Int32 TYPE_DIRECTIONAL = 0
    public static Int32 TYPE_POINT = 1
    public static Int32 TYPE_SPOT = 2

    public LightData lightData = null

    public void _init_()
    {
        # ── 复制 GameObject._init_（父类构造不自动触发）──
        this.parent = null
        this.components = List<Component>( 8 )
        this.name = "Light"
        this.tag = "Untagged"
        this.transform = Transform()
        this.transform.parent = this
        this.components.add( this.transform )
        this.activeSelf = true
        this.layer = 0
        this.pendingDestroy = false
        this.nodeId = 0
        this._children = List<GameObject>( 8 )
        this._scene = null
        # ── 绑定 LightData 组件 ──
        LightData ld = LightData()
        this.addComponent( ld )
        this.lightData = ld
    }

    public void _init_( string _name )
    {
        this._init_()
        this.name = _name
    }

    # ── 工厂（Unity 风格：directional / point / spot）──
    public static Light create( string name )
    {
        Light l = Light()
        l.name = name
        ret l
    }

    public static Light directional( string name )
    {
        Light l = Light( name )
        Int32 ty = Light.TYPE_DIRECTIONAL
        l.setType( ty )
        ret l
    }

    public static Light point( string name )
    {
        Light l = Light( name )
        Int32 ty = Light.TYPE_POINT
        l.setType( ty )
        ret l
    }

    public static Light spot( string name )
    {
        Light l = Light( name )
        Int32 ty = Light.TYPE_SPOT
        l.setType( ty )
        ret l
    }

    public LightData getData()
    {
        ret this.lightData
    }

    # ── 参数转发 ─────────────────────────────────────────
    public void setType( Int32 ty )
    {
        if ty < 0 || ty > 2
        {
            ret
        }
        this.lightData.type = ty
    }

    public void setColor( Float32 r, Float32 g, Float32 b )
    {
        this.lightData.color = Float32_3( r, g, b )
    }

    public void setIntensity( Float32 value )
    {
        this.lightData.intensity = value
    }

    # 2D 光照方向（表面 -> 光源）；同步写 LightData.dirX/dirY
    public void setDirection( Float32 dx, Float32 dy )
    {
        this.lightData.dirX = dx
        this.lightData.dirY = dy
    }

    # 聚光位置（2D）
    public void setPosition2D( Float32 px, Float32 py )
    {
        this.lightData.posX = px
        this.lightData.posY = py
    }

    public void setSpotAngle( Float32 angleDeg )
    {
        this.lightData.spotAngle = angleDeg
    }

    public void setRange( Float32 value )
    {
        if value < 0.0f
        {
            ret
        }
        this.lightData.lightRange = value
    }

    public void setShadows( Float32 quality, Float32 bias, Float32 strength )
    {
        this.lightData.shadowQuality = quality
        this.lightData.shadowBias = bias
        this.lightData.shadowStrength = strength
    }

    # 脚本摆动写入口（沿用 LightData.setSwing）
    public void setSwing( Float32 x, Float32 intensity )
    {
        this.lightData.setSwing( x, intensity )
    }

    # ═══════════════════════════════════════════════════════
    # 方向 / 位置（经 Transform，Unity 风格）
    # ═══════════════════════════════════════════════════════

    # 世界方向（取节点 forward）
    public Float32_3 direction()
    {
        ret this.transform.forward()
    }

    # 世界位置
    public Float32_3 worldPosition()
    {
        ret this.transform.worldPosition()
    }

    # 点光/聚光的 3D 范围衰减（Unity 风格：1 - clamp(d/range, 0, 1)）
    public Float32 attenuation( Float32 distance )
    {
        Float32 rangeVal = this.lightData.lightRange
        if rangeVal <= 0.0f
        {
            ret 1.0f
        }
        Float32 t = Mathf.clamp( distance / rangeVal, 0.0f, 1.0f )
        ret 1.0f - t
    }

    # 聚光锥角衰减：cos(半角) 与方向夹角的平滑插值
    public Float32 spotAttenuation( Float32 cosAngle )
    {
        Int32 spotTy = Light.TYPE_SPOT
        if this.lightData.type != spotTy
        {
            ret 1.0f
        }
        Float32 angleRad = Mathf.radians( this.lightData.spotAngle )
        Float32 outerCos = Mathf.cos( angleRad )
        if cosAngle <= outerCos
        {
            ret 0.0f
        }
        ret Mathf.clamp( ( cosAngle - outerCos ) / ( 1.0f - outerCos ), 0.0f, 1.0f )
    }

    override string toString()
    {
        ret String.toFormat( "Light(type={0}, intensity={1})",
            this.lightData.type.toString(), this.lightData.intensity.toString() )
    }
}
