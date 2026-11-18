import Core;
import Std;
import Math;
import SimGameEngine;
import SLangRender;

# ============================================================================
# 场景脚本（doc/19 示例）：挂载在 scene.json 节点上的 Behaviour 子类。
# SceneManager 按 script 短名找到 SceneScriptFactories 里的工厂，工厂读节点
# 参数、创建脚本实例，由 Application 帧循环驱动生命周期钩子。
#
# 形态约束：方法调用表达式不作实参；下标先落局部变量；不用 `tr`/`base`/
# `out`/`params`/`global` 等保留字作变量名。
# ============================================================================

# 材质球：start 时用固定形状库生成球体顶点灌进自身 MeshRef
public class SphereMeshScript extends Behaviour
{
    public Float32 radius = 1.0f
    public Int32 segU = 12
    public Int32 segV = 8

    override void start()
    {
        GameObject o = this.owner
        if o == null
        {
            ret
        }
        MeshRef mr = o.getComponent<MeshRef>()
        if mr == null
        {
            ret
        }
        Array<Float32> par = Array<Float32>( 3 )
        Float32 u = this.segU.toFloat32()
        Float32 v = this.segV.toFloat32()
        par[0] = this.radius
        par[1] = u
        par[2] = v
        ShapeMesh sm = ShapeFactory.build( 3, par )
        if sm != null
        {
            sm.applyTo( mr )
        }
        o.addComponent( AxisGizmoScript() )
    }
}

# 坐标轴箭头脚本：挂在有网格的节点上，每帧用 owner 的局部位置生成
# XYZ 三轴箭头顶点（数值交给 SceneDemo 汇总，走烘焙组视图旋转）。
public class AxisGizmoScript extends Behaviour
{
    override void update()
    {
        GameObject o = this.owner
        if o == null
        {
            ret
        }
        Transform t = o.transform
        Float32_3 p = t.localPosition
        SceneDemo.pushAxisAt( p )
    }
}

# 形状展厅：shape 号 + 尺寸，从固定形状库构建对应网格
# 形状号（ShapeFactory/doc/17 形状表）：0 cube / 3 sphere / 4 cylinder /
# 5 cone / 6 torus / 7 prism / 8 pipe / 11 door；参数个数按 C 侧形状表精确给出。
public class ShapeMeshScript extends Behaviour
{
    public Int32 shape = 0
    public Float32 size = 1.0f
    # 非等比尺寸（可选）：>0 时覆盖 size 的等比三轴值（地面等扁平形状用）
    public Float32 sx = 0.0f
    public Float32 sy = 0.0f
    public Float32 sz = 0.0f

    override void start()
    {
        GameObject o = this.owner
        if o == null
        {
            ret
        }
        MeshRef mr = o.getComponent<MeshRef>()
        if mr == null
        {
            ret
        }
        Float32 s = this.size
        Int32 kind = this.shape
        Array<Float32> par = null
        if kind == 1
        {
            # PLANE(XZ 平面地面)：width,height,cols,rows
            Array<Float32> p = Array<Float32>( 4 )
            p[0] = s
            p[1] = s
            p[2] = 1.0f
            p[3] = 1.0f
            par = p
        }
        elif kind == 3
        {
            Array<Float32> p = Array<Float32>( 3 )
            p[0] = s * 0.55f
            p[1] = 14.0f
            p[2] = 10.0f
            par = p
        }
        elif kind == 4
        {
            Array<Float32> p = Array<Float32>( 4 )
            p[0] = s * 0.45f
            p[1] = s * 1.4f
            p[2] = 14.0f
            p[3] = 2.0f
            par = p
        }
        elif kind == 5
        {
            Array<Float32> p = Array<Float32>( 3 )
            p[0] = s * 0.55f
            p[1] = s * 1.5f
            p[2] = 14.0f
            par = p
        }
        elif kind == 6
        {
            Array<Float32> p = Array<Float32>( 4 )
            p[0] = s * 0.62f
            p[1] = s * 0.22f
            p[2] = 18.0f
            p[3] = 8.0f
            par = p
        }
        elif kind == 8
        {
            Array<Float32> p = Array<Float32>( 4 )
            p[0] = s * 0.6f
            p[1] = s * 1.4f
            p[2] = s * 0.25f
            p[3] = 14.0f
            par = p
        }
        elif kind == 11
        {
            Array<Float32> p = Array<Float32>( 5 )
            p[0] = s
            p[1] = s * 1.5f
            p[2] = s * 0.5f
            p[3] = s * 0.3f
            p[4] = s * 0.28f
            par = p
        }
        else
        {
            # 0 cube / 7 prism：三轴尺寸（sx/sy/sz>0 时非等比覆盖）
            Array<Float32> p = Array<Float32>( 3 )
            if this.sx > 0.0f
            {
                p[0] = this.sx
            }
            else
            {
                p[0] = s
            }
            if this.sy > 0.0f
            {
                p[1] = this.sy
            }
            else
            {
                p[1] = s
            }
            if this.sz > 0.0f
            {
                p[2] = this.sz
            }
            else
            {
                p[2] = s
            }
            par = p
        }
        ShapeMesh sm = ShapeFactory.build( kind, par )
        if sm != null
        {
            sm.applyTo( mr )
        }
        o.addComponent( AxisGizmoScript() )
    }
}

# 通用动效：绕 Z 轴自转 + 可选上下浮动（场景脚本逻辑随 Application 帧循环跑）
public class SpinScript extends Behaviour
{
    public Float32 speed = 0.5f
    public Float32 bob = 0.0f
    Float32 _phase = 0.0f
    Float32_3 _base = Float32_3.zero()

    override void start()
    {
        GameObject o = this.owner
        if o == null
        {
            ret
        }
        Transform t = o.transform
        Float32_3 p = t.localPosition
        this._base = p
        this._phase = 0.0f
    }

    override void update()
    {
        Float32 dt = EngineTime.deltaTime
        this._phase = this._phase + dt * this.speed
        GameObject o = this.owner
        if o == null
        {
            ret
        }
        Transform t = o.transform
        t.rotateZ( dt * this.speed )
        if this.bob > 0.0f
        {
            Float32 wave = Mathf.sin( this._phase * 1.7f ) * this.bob
            Float32 bx = this._base.x
            Float32 by = this._base.y + wave
            Float32 bz = this._base.z
            Float32_3 np = Float32_3( bx, by, bz )
            t.setPosition( np )
        }
    }
}

# 灯光摇摆脚本：挂在带 LightData 的节点上，随时间正弦摆动聚光位置与强度
public class LightSwingScript extends Behaviour
{
    public Float32 swing = 1.5f
    public Float32 speed = 0.8f
    Float32 _baseX = 0.0f
    Float32 _baseI = 0.0f

    override void start()
    {
        GameObject o = this.owner
        if o == null
        {
            ret
        }
        LightData ld = o.getComponent<LightData>()
        if ld == null
        {
            ret
        }
        this._baseX = ld.posX
        this._baseI = ld.intensity
    }

    override void update()
    {
        GameObject o = this.owner
        if o == null
        {
            ret
        }
        LightData ld = o.getComponent<LightData>()
        if ld == null
        {
            ret
        }
        Float32 t = EngineTime.elapsedTime
        Float32 x = this._baseX + Mathf.sin( t * this.speed ) * this.swing
        Float32 i = this._baseI + Mathf.sin( t * 2.3f ) * 0.25f
        ld.setSwing( x, i )
    }
}

# 纯测试脚本：验证场景按路径加载后生命周期钩子确实被 Application 驱动
public class ProbeScript extends Behaviour
{
    public string probeName = "probe"
    public Int32 every = 30
    Int32 _ticks = 0

    override void start()
    {
        Console.println( "[scene] started: " + this.probeName )
    }

    override void update()
    {
        this._ticks = this._ticks + 1
        if this._ticks >= this.every
        {
            this._ticks = 0
            Console.println( "[scene] " + this.probeName + " alive" )
        }
    }
}

# 工厂集合：形态 void(JsonValue cfg, ScriptResult out)，注册给 SceneManager。
# 必须在 SceneDemo.run 之前定义（单遍 call-link 解析要求先定义后引用）。
public class SceneScriptFactories
{
    public static void makeSphereMesh( JsonValue cfg, ScriptResult sink )
    {
        SphereMeshScript s = SphereMeshScript()
        JsonValue rn = cfg.select("radius")
        JsonValue un = cfg.select("segU")
        JsonValue vn = cfg.select("segV")
        s.radius = rn.asFloat32( 1.0f )
        s.segU = un.asInt32( 12 )
        s.segV = vn.asInt32( 8 )
        sink.value = s
    }

    public static void makeShapeMesh( JsonValue cfg, ScriptResult sink )
    {
        ShapeMeshScript s = ShapeMeshScript()
        JsonValue sn = cfg.select("shape")
        JsonValue zn = cfg.select("size")
        JsonValue xn = cfg.select("sx")
        JsonValue yn = cfg.select("sy")
        JsonValue z2 = cfg.select("sz")
        s.shape = sn.asInt32( 0 )
        s.size = zn.asFloat32( 1.0f )
        s.sx = xn.asFloat32( 0.0f )
        s.sy = yn.asFloat32( 0.0f )
        s.sz = z2.asFloat32( 0.0f )
        sink.value = s
    }

    # 坐标轴箭头脚本工厂（给内置网格节点挂箭头，走 singleObject 光照路径）
    public static void makeAxis( JsonValue cfg, ScriptResult sink )
    {
        AxisGizmoScript a = AxisGizmoScript()
        sink.value = a
    }

    public static void makeSpin( JsonValue cfg, ScriptResult sink )
    {
        SpinScript s = SpinScript()
        JsonValue sp = cfg.select("speed")
        JsonValue bn = cfg.select("bob")
        s.speed = sp.asFloat32( 0.5f )
        s.bob = bn.asFloat32( 0.0f )
        sink.value = s
    }

    public static void makeProbe( JsonValue cfg, ScriptResult sink )
    {
        ProbeScript s = ProbeScript()
        JsonValue ln = cfg.select("label")
        JsonValue en = cfg.select("every")
        s.probeName = ln.asString( "probe" )
        s.every = en.asInt32( 30 )
        sink.value = s
    }

    public static void makeLightSwing( JsonValue cfg, ScriptResult sink )
    {
        LightSwingScript s = LightSwingScript()
        JsonValue sn = cfg.select("swing")
        JsonValue sp = cfg.select("speed")
        s.swing = sn.asFloat32( 1.5f )
        s.speed = sp.asFloat32( 0.8f )
        sink.value = s
    }
}
