import Std;
import Math;
# Hlsl —— HLSL 着色器对象模型
#
# 着色器统一用 HLSL 编写（与 Unity 一致）：
#   入口：VSMain / PSMain / CSMain（可配置）
#   目标：vs_5_0 / ps_5_0 / cs_6_0（DX12 走 DXIL，Vulkan 走 DXC -> SPIR-V）
#   语义：POSITION / NORMAL / TEXCOORD0 / SV_POSITION / SV_Target
#   cbuffer：UnityPerFrame / UnityPerDraw / UnityPerMaterial（见 HlslLibrary）
#
# 编译产物是 ShaderModule（字节码 + 反射信息），交给 GraphicsPipelineState 组装成 PSO

enum EShaderStage
{
    Vertex = 0
    Pixel
    Geometry
    Hull
    Domain
    Compute
}

enum EShaderParamType
{
    Float = 0
    Float2
    Float3
    Float4
    Matrix4x4
    Texture2D
    Sampler
    ConstantBuffer
    StructuredBuffer
}

# ── 反射出来的着色器参数 ───────────────────────────────
public class ShaderParameter
{
    public string name = ""
    public EShaderParamType paramType = EShaderParamType.Float
    public Int32 bindPoint = 0        # register(b0) / (t0) / (s0) 里的数字
    public Int32 bindSpace = 0        # space0 / space1
    public Int32 stageFlags = 1       # 可见阶段位掩码：1=VS 2=PS 4=CS

    public void _init_()
    {
        this.name = ""
        this.paramType = EShaderParamType.Float
        this.bindPoint = 0
        this.bindSpace = 0
        this.stageFlags = 1
    }

    public void _init_( string _name, EShaderParamType _type, Int32 _bindPoint )
    {
        this.name = _name
        this.paramType = _type
        this.bindPoint = _bindPoint
        this.bindSpace = 0
        this.stageFlags = 1
    }

    override string toString()
    {
        ret this.name + " : register(b" + this.bindPoint.toString() + ")"
    }
}

# ── 编译后的着色器模块（DXIL / SPIR-V 字节码）───────────
public class ShaderModule
{
    public string name = ""
    public string entryPoint = "main"
    public string target = "vs_5_0"
    public EShaderStage stage = EShaderStage.Vertex
    public Array<Int32> bytecode = null
    public Array<ShaderParameter> parameters = null
    public bool isValid = false

    public void _init_()
    {
        this.name = ""
        this.entryPoint = "main"
        this.target = "vs_5_0"
        this.stage = EShaderStage.Vertex
        this.bytecode = Array<Int32>( 0 )
        this.parameters = Array<ShaderParameter>( 0 )
        this.isValid = false
    }

    # 调用后端编译器（DXC / FXC）把 HLSL 编成字节码
    public static ShaderModule compile( string name, string source, string entry, string target, EShaderStage stage )
    {
        ShaderModule m = ShaderModule()
        m.name = name
        m.entryPoint = entry
        m.target = target
        m.stage = stage

        object result = SystemCallExternalFunction( "Render.compileHlsl", name, source, entry, target, stage )
        if result is ShaderModule ok
        {
            ret ok
        }
        if GpuUtil.asBool( result )
        {
            m.isValid = true
        }
        ret m
    }

    public int parameterCount()
    {
        ret this.parameters.length
    }

    override string toString()
    {
        ret "ShaderModule(" + this.name + ", " + this.target + ", valid=" + this.isValid.toString() + ")"
    }
}

# ── HLSL 着色器（源码 + 编译 + uniform 设置）────────────
public class HlslShader
{
    public string name = "HlslShader"

    # 源码：VS / PS / CS 三段，按需填
    public string vertexSource = ""
    public string pixelSource = ""
    public string computeSource = ""

    public string vertexEntry = "VSMain"
    public string pixelEntry = "PSMain"
    public string computeEntry = "CSMain"

    # 目标模型：DX12 用 5_1 / 6_x；Vulkan 转 SPIR-V 时后端自动处理
    public string vertexTarget = "vs_5_1"
    public string pixelTarget = "ps_5_1"
    public string computeTarget = "cs_6_0"

    public Array<ShaderParameter> parameters = null

    ShaderModule _vs = null
    ShaderModule _ps = null
    ShaderModule _cs = null

    public void _init_()
    {
        this.name = "HlslShader"
        this.vertexSource = ""
        this.pixelSource = ""
        this.computeSource = ""
        this.parameters = Array<ShaderParameter>( 0 )
    }

    public void _init_( string _name )
    {
        this._init_()
        this.name = _name
    }

    public void _init_( string _name, string _vsSource, string _psSource )
    {
        this._init_()
        this.name = _name
        this.vertexSource = _vsSource
        this.pixelSource = _psSource
    }

    # ── 编译 ─────────────────────────────────────────────
    public bool compile()
    {
        bool ok = true
        if this.vertexSource != ""
        {
            this._vs = ShaderModule.compile( this.name + ".vs", this.vertexSource, this.vertexEntry, this.vertexTarget, EShaderStage.Vertex )
            if !this._vs.isValid
            {
                ok = false
            }
        }
        if this.pixelSource != ""
        {
            this._ps = ShaderModule.compile( this.name + ".ps", this.pixelSource, this.pixelEntry, this.pixelTarget, EShaderStage.Pixel )
            if !this._ps.isValid
            {
                ok = false
            }
        }
        if this.computeSource != ""
        {
            this._cs = ShaderModule.compile( this.name + ".cs", this.computeSource, this.computeEntry, this.computeTarget, EShaderStage.Compute )
            if !this._cs.isValid
            {
                ok = false
            }
        }
        ret ok
    }

    public ShaderModule vertexModule()
    {
        ret this._vs
    }

    public ShaderModule pixelModule()
    {
        ret this._ps
    }

    public ShaderModule computeModule()
    {
        ret this._cs
    }

    public get bool isCompiled()
    {
        ret this._vs != null || this._ps != null || this._cs != null
    }

    # ── 参数反射 ─────────────────────────────────────────
    public void addParameter( string pname, EShaderParamType ptype, Int32 bindPoint )
    {
        # 下标长度先落局部变量（this.xxx.length 形式下标解析器不支持）
        Int32 oldLen = this.parameters.length
        Array<ShaderParameter> np = Array<ShaderParameter>( oldLen + 1 )
        int i = 0
        while i < oldLen
        {
            np[i] = this.parameters[i]
            i++
        }
        np[ oldLen ] = ShaderParameter( pname, ptype, bindPoint )
        this.parameters = np
    }

    # ── uniform 设置（走后端，按名字绑定）─────────────────
    public bool setFloat( string pname, Float32 value )
    {
        ret GpuUtil.asBool( SystemCallExternalFunction( "Render.setUniformFloat", this.name, pname, value ) )
    }

    public bool setVector3( string pname, Float32_3 value )
    {
        ret GpuUtil.asBool( SystemCallExternalFunction( "Render.setUniformVector3", this.name, pname, value.x, value.y, value.z ) )
    }

    public bool setVector4( string pname, Float32_4 value )
    {
        ret GpuUtil.asBool( SystemCallExternalFunction( "Render.setUniformVector4", this.name, pname, value.x, value.y, value.z, value.w ) )
    }

    public bool setColor( string pname, Color value )
    {
        # Std.Color 无 toFloat32_4（避免 Std->Math 反向依赖），此处自行组装
        ret this.setVector4( pname, Float32_4( value.r, value.g, value.b, value.a ) )
    }

    public bool setMatrix( string pname, Float32_4x4 value )
    {
        ret GpuUtil.asBool( SystemCallExternalFunction( "Render.setUniformMatrix4", this.name, pname, value ) )
    }

    public bool setTexture( string pname, GpuTextureView view )
    {
        ret GpuUtil.asBool( SystemCallExternalFunction( "Render.setUniformTextureView", this.name, pname, view.descriptorIndex ) )
    }

    public bool setSampler( string pname, Sampler s )
    {
        ret GpuUtil.asBool( SystemCallExternalFunction( "Render.setUniformSampler", this.name, pname, s.descriptorIndex ) )
    }

    override string toString()
    {
        ret "HlslShader(" + this.name + ", compiled=" + this.isCompiled().toString() + ")"
    }
}

# ── P5：SL -> C 程序枚举映射表（Hlsl.sl 定位收窄）─────────────────
# ShaderProgramMap —— 着色器名 <-> C 侧程序槽（SLang.RenderPipeline.PROG_*）
# 的唯一映射表。本链路无 HLSL 编译器（上方 HlslShader 的 compileHlsl 为
# 草稿层 SystemCallExternalFunction 软分发，运行期无后端命中——不假装
# 支持）；材质 -> 程序的真实路由 = 本表 + Material 关键字位掩码
#（Material.resolveProgram）→ C 侧 draw_item(prog) switch 分发。
#   genSlot(effect, variant) —— 固化编译槽 8..17（effect 0..4 = Lambert/
#     Phong/BlinnPhong/NormalMap/Toon × variant 0..1 flat/tex，与 C 侧
#     SLR_PROG_GEN_SLOT 一致：槽 = PROG_GEN_BASE + effect*2 + variant）
public class ShaderProgramMap
{
    # fromName(name) —— 着色器名 -> 程序槽（未知名返回 PROG_PFLAT 兜底）
    public static Int32 fromName( string name )
    {
        if name == "flat"
        {
            ret SLang.RenderPipeline.PROG_FLAT
        }
        if name == "tex"
        {
            ret SLang.RenderPipeline.PROG_TEX
        }
        if name == "perdraw-flat"
        {
            ret SLang.RenderPipeline.PROG_PFLAT
        }
        if name == "perdraw-tex"
        {
            ret SLang.RenderPipeline.PROG_PTEX
        }
        if name == "blit"
        {
            ret SLang.RenderPipeline.PROG_BLIT
        }
        if name == "post"
        {
            ret SLang.RenderPipeline.PROG_POST
        }
        if name == "phong-flat"
        {
            ret SLang.RenderPipeline.PROG_PHONG_FLAT
        }
        if name == "phong-tex"
        {
            ret SLang.RenderPipeline.PROG_PHONG_TEX
        }
        ret SLang.RenderPipeline.PROG_PFLAT
    }

    # nameOf(prog) —— 程序槽 -> 着色器名（未知槽返回 "unknown"）
    public static string nameOf( Int32 prog )
    {
        if prog == SLang.RenderPipeline.PROG_FLAT
        {
            ret "flat"
        }
        if prog == SLang.RenderPipeline.PROG_TEX
        {
            ret "tex"
        }
        if prog == SLang.RenderPipeline.PROG_PFLAT
        {
            ret "perdraw-flat"
        }
        if prog == SLang.RenderPipeline.PROG_PTEX
        {
            ret "perdraw-tex"
        }
        if prog == SLang.RenderPipeline.PROG_BLIT
        {
            ret "blit"
        }
        if prog == SLang.RenderPipeline.PROG_POST
        {
            ret "post"
        }
        if prog == SLang.RenderPipeline.PROG_PHONG_FLAT
        {
            ret "phong-flat"
        }
        if prog == SLang.RenderPipeline.PROG_PHONG_TEX
        {
            ret "phong-tex"
        }
        if prog >= SLang.RenderPipeline.PROG_GEN_BASE
        {
            Int32 rel = prog - SLang.RenderPipeline.PROG_GEN_BASE
            Int32 effect = rel / 2
            Int32 variant = rel - effect * 2
            string vn = "flat"
            if variant == 1
            {
                vn = "tex"
            }
            ret "gen/" + ShaderProgramMap.effectName( effect ) + "-" + vn
        }
        ret "unknown"
    }

    # effectName(effect) —— 固化效果名（0..4；越界 "unknown"）
    public static string effectName( Int32 effect )
    {
        if effect == 0
        {
            ret "lambert"
        }
        if effect == 1
        {
            ret "phong"
        }
        if effect == 2
        {
            ret "blinnphong"
        }
        if effect == 3
        {
            ret "normalmap"
        }
        if effect == 4
        {
            ret "toon"
        }
        ret "unknown"
    }

    # genSlot(effect, variant) —— 固化编译槽（effect 0..4 / variant 0..1；
    # 越界参数返回 PROG_PFLAT 兜底，防越界槽进命令流）
    public static Int32 genSlot( Int32 effect, Int32 variant )
    {
        if effect < 0 || effect > 4
        {
            ret SLang.RenderPipeline.PROG_PFLAT
        }
        if variant < 0 || variant > 1
        {
            ret SLang.RenderPipeline.PROG_PFLAT
        }
        ret SLang.RenderPipeline.PROG_GEN_BASE + effect * 2 + variant
    }
}
