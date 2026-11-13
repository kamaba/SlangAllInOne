import Std;
import Math;
# 光源组件：方向光 / 点光 / 聚光 + 颜色 / 强度 / 范围。
# 数学类型使用 Math 库的 Float32 系列。
public class Light extends Component
{
    # 光照类型
    public Int32 type = 0   # 0 = Directional, 1 = Point, 2 = Spot

    public Color color = Color.white()

    # 强度（通常 [0, 8+]）
    public Float32 intensity = 1.0f

    # 字段名 lightRange：range 是小写容器构造糖（range() => Range），类成员名须避让
    public Float32 lightRange = 0.0f

    # 聚光有效：圆锥半角（角度制，光轴两侧）
    public Float32 spotAngle = 30.0f

    # 阴影
    public bool castShadow = false
    # N2a 阴影质量：0 = 旧 2D 投影黑斑（默认）；1 = shadow map
    # （光空间深度图 + shader PCF；仅平行光生效，VK 后端按 0 回退）
    public Float32 shadowQuality = 0.0f
    # N2b CSM 参数（0 = 管线默认 bias 0.002 / strength 0.35 / 单级联）：
    # shadowBias 防 acne 深度偏移；shadowStrength 阴影强度覆盖（0..1，
    # 原 v3.4 字段未消费——复用为管线强度覆盖）；shadowCascades
    # 级联数（1 = 单级；4 = CSM 4 级联 v 分段 0.05/0.25/0.6/1.0）
    public Float32 shadowBias = 0.0f
    public Float32 shadowStrength = 0.0f
    public Float32 shadowCascades = 0.0f

    # ── 显式光照参数（applyTo 写管线槽用；无 Transform 时的方向/位置）──
    # dirX/dirY：平行光 = 表面 -> 光源方向；聚光 = 光轴方向（光源 -> 外）
    # posX/posY：聚光世界位置
    public Float32 dirX = 1.0f
    public Float32 dirY = 0.0f
    public Float32 posX = 0.0f
    public Float32 posY = 0.0f

    # ── 构造 / 预设 ──────────────────────────────────────
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

    # ── 类型判定 ─────────────────────────────────────────
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

    # ── 方向 ─────────────────────────────────────────────
    # 方向光：从 Transform 旋转推出光照方向（默认沿 +Z 照射）
    public get Float32_3 direction()
    {
        Component c = this.getComponent<Transform>()
        if c is Transform t
        {
            ret t.forward()
        }
        ret Float32_3.forward()
    }

    public get Float32_3 worldPosition()
    {
        Component c = this.getComponent<Transform>()
        if c is Transform t
        {
            ret t.worldPosition()
        }
        ret Float32_3.zero()
    }

    # ── 着色参数 ─────────────────────────────────────────
    # 返回用于着色器的颜色 * 强度
    public Color effectiveColor()
    {
        ret this.color.clone()._mul_( this.intensity ) as Color
    }

    # 点光 / 聚光衰减（距离平方反比，带范围截断）
    public Float32 attenuation( Float32 distance )
    {
        if this.type == 0
        {
            ret 1.0f
        }
        if this.lightRange > 0.0f && distance >= this.lightRange
        {
            ret 0.0f
        }
        Float32 d = Mathf.max( distance, 0.0001f )
        Float32 atten = 1.0f / ( 1.0f + d * d )
        if this.lightRange > 0.0f
        {
            Float32 k = 1.0f - Mathf.clamp( distance / this.lightRange, 0.0f, 1.0f )
            atten = atten * k * k
        }
        ret atten
    }

    # 聚光锥角衰减（worldPoint 为被照点）
    public Float32 spotAttenuation( Float32_3 worldPoint )
    {
        if this.type != 2
        {
            ret 1.0f
        }
        Float32_3 toPoint = worldPoint._sub_( this.worldPosition() ) as Float32_3
        Float32 dist = toPoint.length()
        if dist <= 0.0001f
        {
            ret 1.0f
        }
        toPoint = toPoint.normalize()
        Float32 cosAngle = toPoint.dot( this.direction() )
        Float32 cosEdge = Mathf.cos( Mathf.radians( this.spotAngle ) )
        if cosAngle <= cosEdge
        {
            ret 0.0f
        }
        Float32 t = ( cosAngle - cosEdge ) / ( 1.0f - cosEdge )
        ret t * t
    }

    # ── 预设工厂 ─────────────────────────────────────────
    public static Light directional( Color c, Float32 intensity )
    {
        Light l = Light()
        l.type = 0
        l.color = c.clone()
        l.intensity = intensity
        ret l
    }

    public static Light point( Color c, Float32 intensity, Float32 lightRange )
    {
        Light l = Light()
        l.type = 1
        l.color = c.clone()
        l.intensity = intensity
        l.lightRange = lightRange
        ret l
    }

    public static Light spot( Color c, Float32 intensity, Float32 lightRange, Float32 spotAngleDegrees )
    {
        Light l = Light()
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
    # 平行光 6 项 / 聚光 10 项）。参数块为类级静态暂存（单线程 VM 复用）。
    static Int64 _applyPtr = 0

    public bool applyTo( SLang.RenderPipeline pipe, Int32 slot )
    {
        if pipe == null || pipe.isValid == false
        {
            ret false
        }
        if Light._applyPtr == 0
        {
            Light._applyPtr = Memory.alloc( 40 )
            if Light._applyPtr == 0
            {
                ret false
            }
        }
        Int64 p = Light._applyPtr
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
        ret String.toFormat( "Light(type={0}, color={1}, intensity={2})",
            this.type.toString(), this.color.toString(), this.intensity.toString() )
    }
}
