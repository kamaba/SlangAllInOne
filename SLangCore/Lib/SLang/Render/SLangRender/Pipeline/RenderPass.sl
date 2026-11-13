import Std;
import Math;
# RenderPass —— 一次具体的渲染步骤（Unity SRP Pass）
#
# Unity 的 RenderPass 模型：
#   configure()   确定本次要写的 RT / 是否清屏
#   render()      用 ScriptableRenderContext 录制命令并绘制
# 这里把常用 pass 也实现出来：深度预通道、阴影投射、不透明/透明绘制、
# 天空盒、全屏后处理。上层管线（URP）把若干 pass 串起来。

# Pass 执行顺序（值越小越靠前），与 Unity RenderPassEvent 同义
enum ERenderPassEvent
{
    BeforeRendering = 0
    ShadowCasters = 50
    DepthPrepass = 100
    Opaque = 200
    Skybox = 250
    Transparent = 300
    PostProcessing = 800
    AfterRendering = 1000
}

# ── Pass 基类 ─────────────────────────────────────────
public class RenderPass
{
    public string name = "RenderPass"
    public int passEvent = ERenderPassEvent.Opaque
    public string profilerName = "RenderPass"

    # 目标（null 表示写回 backbuffer）
    public RenderTargetIdentifier colorAttachment = null
    public RenderTargetIdentifier depthAttachment = null

    public bool clearColorFlag = false
    public bool clearDepthFlag = false
    public Color clearColor = Color.black()

    # 本 pass 用到的剔除结果（由管线在 setup 阶段填好）
    public CullingResults cullingResults = null
    public Camera camera = null

    # ── P1 Pass 功能块：类型常量 + 桥接世界字段 ───────────────
    # 派发不用 virtual 重写——子类构造不调 this._init_()（运行期递归
    # 地雷），完全手动设字段；基类 execute 按 passType 走 exec* 私有
    # 方法（同 ECommandOpcode 教训后的「类静态 + type 字段」约定）。
    public static Int32 TYPE_BASE = 0
    public static Int32 TYPE_OPAQUE = 1
    public static Int32 TYPE_TRANSPARENT = 2
    public static Int32 TYPE_POST = 3
    public static Int32 TYPE_BLIT = 4

    # Pass 类型（TYPE_*，execute 派发键）
    public Int32 passType = 0

    # 桥接世界数据（P0 CullingData 快照；Opaque/Transparent 消费）
    public CullingData culling = null

    # 视口与清屏（OpaquePass 录 setRenderTargets 用）
    public Int32 viewportX = 0
    public Int32 viewportY = 0
    public Int32 viewportWidth = 256
    public Int32 viewportHeight = 256
    public bool clearTargetColor = false
    public bool clearTargetDepth = false

    # 后处理参数（PostProcessPass）
    public bool postEnabled = false
    public Float32 postBrightness = 1.0f
    public Float32 postSaturation = 1.0f
    public Float32 postVignette = 1.0f

    # 输出回读（BlitPass；非 0 时 blit 后追加 readback）
    public Int64 blitReadbackPtr = 0

    public void _init_()
    {
        this.name = "RenderPass"
        this.passEvent = ERenderPassEvent.Opaque
        this.profilerName = "RenderPass"
        this.clearColorFlag = false
        this.clearDepthFlag = false
        this.clearColor = Color.black()
        this.cullingResults = CullingResults()
    }

    public void _init_( string _name )
    {
        this._init_()
        this.name = _name
        this.profilerName = _name
    }

    # 设置写哪个 RT、是否清屏（在 render 之前调用）
    public void configure( RenderTargetIdentifier color, RenderTargetIdentifier depth, bool clearC, bool clearD, Color clearCol )
    {
        this.colorAttachment = color
        this.depthAttachment = depth
        this.clearColorFlag = clearC
        this.clearDepthFlag = clearD
        this.clearColor = clearCol
    }

    # 由管线注入剔除结果
    public void setup( CullingResults cull, Camera cam )
    {
        this.cullingResults = cull
        this.camera = cam
    }

    # ── P1 execute：按 passType 派发录制（命令进共享命令流）──
    # 每个 Pass = 一个录制单元；命令录进 ctx 持有的同一条 CommandBuffer
    # （C 侧 slr_cmd_execute_stream 每次调用都重置 PerDraw 槽与描述符
    # 表——sl_cmd.c 帧级前置 memset，因此一帧全部命令必须同一条流内
    # 提交，ScriptableRenderContext.submitPasses 负责单流整包）。
    public void execute( ScriptableRenderContext ctx, CommandBuffer cmd )
    {
        if this.passType == RenderPass.TYPE_OPAQUE
        {
            this.executeOpaque( ctx, cmd )
        }
        elif this.passType == RenderPass.TYPE_TRANSPARENT
        {
            this.executeTransparent( ctx, cmd )
        }
        elif this.passType == RenderPass.TYPE_POST
        {
            this.executePost( ctx, cmd )
        }
        elif this.passType == RenderPass.TYPE_BLIT
        {
            this.executeBlit( ctx, cmd )
        }
    }

    # 不透明段：绑场景目标（可选清屏）+ 遍历 culling 画 queue < 2500
    # （CullingData 列为 Int64，经 SystemConvertInt32 显式窄化——同
    # Core Int64.toInt32 的转换通路；drawItem 七元组取 Int32）
    void executeOpaque( ScriptableRenderContext ctx, CommandBuffer cmd )
    {
        if this.culling == null
        {
            ret
        }
        Int32 clearFlags = 0
        if this.clearTargetColor
        {
            clearFlags = clearFlags + SLang.RenderPipeline.CLEAR_COLOR
        }
        if this.clearTargetDepth
        {
            clearFlags = clearFlags + SLang.RenderPipeline.CLEAR_DEPTH
        }
        Color cc = this.clearColor
        if cc == null
        {
            cc = Color.black()
        }
        cmd.setRenderTargets( SLang.RenderPipeline.TARGET_SCENE, this.viewportX, this.viewportY,
                              this.viewportWidth, this.viewportHeight, clearFlags, cc )
        Int32 i = 0
        while i < this.culling.count()
        {
            Int64 qMin = 2500
            if this.culling.getQueue( i ) < qMin
            {
                Int32 prog = SystemConvertInt32( this.culling.getProg( i ) )
                Int32 slot = SystemConvertInt32( this.culling.getSlot( i ) )
                Int32 mesh = SystemConvertInt32( this.culling.getMesh( i ) )
                Int32 texd = SystemConvertInt32( this.culling.getTex( i ) )
                Int32 transp = SystemConvertInt32( this.culling.getTransp( i ) )
                Int32 queue = SystemConvertInt32( this.culling.getQueue( i ) )
                Float32 z = this.culling.getZ( i )
                cmd.drawItem( prog, slot, mesh, texd, transp, queue, z )
            }
            i = i + 1
        }
    }

    # 透明段：不重绑目标（OpaquePass 已绑场景目标，同帧槽位持久），
    # 遍历 culling 画 queue >= 2500（z 降序由 sortDrawItems 统一整理）
    void executeTransparent( ScriptableRenderContext ctx, CommandBuffer cmd )
    {
        if this.culling == null
        {
            ret
        }
        Int32 i = 0
        while i < this.culling.count()
        {
            Int64 qMin = 2500
            if this.culling.getQueue( i ) >= qMin
            {
                Int32 prog = SystemConvertInt32( this.culling.getProg( i ) )
                Int32 slot = SystemConvertInt32( this.culling.getSlot( i ) )
                Int32 mesh = SystemConvertInt32( this.culling.getMesh( i ) )
                Int32 texd = SystemConvertInt32( this.culling.getTex( i ) )
                Int32 transp = SystemConvertInt32( this.culling.getTransp( i ) )
                Int32 queue = SystemConvertInt32( this.culling.getQueue( i ) )
                Float32 z = this.culling.getZ( i )
                cmd.drawItem( prog, slot, mesh, texd, transp, queue, z )
            }
            i = i + 1
        }
    }

    # 后处理：全屏 pass（enabled=0 走纯拷贝 scene -> post）
    void executePost( ScriptableRenderContext ctx, CommandBuffer cmd )
    {
        Int32 enabled = 0
        if this.postEnabled
        {
            enabled = 1
        }
        cmd.postProcess( enabled, this.postBrightness, this.postSaturation, this.postVignette )
    }

    # 整合输出：blit post -> final + 可选回读（非 0 指针时）
    void executeBlit( ScriptableRenderContext ctx, CommandBuffer cmd )
    {
        cmd.blitFinal()
        if this.blitReadbackPtr != 0
        {
            cmd.readback( this.blitReadbackPtr )
        }
    }

    # ── 生命周期（子类重写 render）─────────────────────────
    public void begin( ScriptableRenderContext ctx )
    {
        if this.profilerName != ""
        {
            ctx.cmd.beginEvent( this.profilerName )
        }
    }

    public virtual void render( ScriptableRenderContext ctx )
    {
        # 基类默认：清一次屏
        if this.clearColorFlag || this.clearDepthFlag
        {
            ctx.cmd.clearRenderTarget( this.clearColorFlag, this.clearDepthFlag, this.clearColor )
        }
    }

    public void end( ScriptableRenderContext ctx )
    {
        if this.profilerName != ""
        {
            ctx.cmd.endEvent()
        }
    }

    override string toString()
    {
        ret "RenderPass(" + this.name + ", event=" + this.passEvent.toString() + ")"
    }
}

# ── 清屏 Pass ─────────────────────────────────────────
public class ClearPass extends RenderPass
{
    public void _init_( string _name, Color clearCol )
    {
        this._init_()
        this.name = _name
        this.profilerName = _name
        this.clearColorFlag = true
        this.clearDepthFlag = true
        this.clearColor = clearCol
    }

    override void render( ScriptableRenderContext ctx )
    {
        ctx.cmd.clearRenderTarget( true, true, this.clearColor )
    }
}

# ── 阴影投射 Pass（把物体深度渲到 shadow map）─────────────
public class ShadowCasterPass extends RenderPass
{
    public GpuTexture shadowMap = null
    public Material depthOnlyMaterial = null
    public Float32_4x4 lightViewProjection = Float32_4x4.identity()

    public void _init_()
    {
        this.name = "ShadowCaster"
        this.profilerName = "RenderPass.ShadowCaster"
        this.passEvent = ERenderPassEvent.ShadowCasters
    }

    public void setLightData( Float32_4x4 lightVP, GpuTexture shadowTex )
    {
        this.lightViewProjection = lightVP
        this.shadowMap = shadowTex
    }

    override void render( ScriptableRenderContext ctx )
    {
        if this.shadowMap == null || this.cullingResults == null
        {
            ret
        }
        ctx.cmd.setRenderTarget( RenderTargetBinding( null, RenderTargetIdentifier.fromTexture( this.shadowMap ) ) )
        ctx.cmd.clearRenderTarget( false, true, Color.black() )

        # 深度只需写深度；这里用 DepthOnly 材质做 override
        if this.depthOnlyMaterial != null
        {
            ctx.drawRenderers( this.cullingResults, 0, 5000, this.depthOnlyMaterial )
        }
        else
        {
            ctx.drawRenderers( this.cullingResults, 0, 5000, null )
        }
    }
}

# ── 深度预通道 ─────────────────────────────────────────
public class DepthPrepass extends RenderPass
{
    public Material depthOnlyMaterial = null

    public void _init_()
    {
        this.name = "DepthPrepass"
        this.profilerName = "RenderPass.DepthPrepass"
        this.passEvent = ERenderPassEvent.DepthPrepass
    }

    override void render( ScriptableRenderContext ctx )
    {
        if this.depthAttachment == null
        {
            ret
        }
        ctx.cmd.setRenderTarget( RenderTargetBinding( null, this.depthAttachment ) )
        if this.cullingResults != null
        {
            ctx.drawRenderers( this.cullingResults, 0, 2500, this.depthOnlyMaterial )
        }
    }
}

# ── 物体绘制 Pass（不透明 / 透明共用）──────────────────────
public class DrawObjectsPass extends RenderPass
{
    public Int32 queueMin = 0
    public Int32 queueMax = 2500
    public Material overrideMaterial = null

    public void _init_( string _name, Int32 minQ, Int32 maxQ )
    {
        this._init_()
        this.name = _name
        this.profilerName = _name
        this.queueMin = minQ
        this.queueMax = maxQ
        if maxQ <= 2500
        {
            this.passEvent = ERenderPassEvent.Opaque
        }
        else
        {
            this.passEvent = ERenderPassEvent.Transparent
        }
    }

    override void render( ScriptableRenderContext ctx )
    {
        if this.colorAttachment == null
        {
            ret
        }
        RenderTargetBinding binding = RenderTargetBinding( this.colorAttachment, this.depthAttachment )
        ctx.cmd.setRenderTarget( binding )

        if this.clearColorFlag
        {
            ctx.cmd.clearRenderTarget( true, false, this.clearColor )
        }

        if this.cullingResults != null
        {
            ctx.drawRenderers( this.cullingResults, this.queueMin, this.queueMax, this.overrideMaterial )
        }
    }
}

# ── 天空盒 Pass ─────────────────────────────────────────
public class SkyboxPass extends RenderPass
{
    public Material skyboxMaterial = null

    public void _init_()
    {
        this.name = "Skybox"
        this.profilerName = "RenderPass.Skybox"
        this.passEvent = ERenderPassEvent.Skybox
    }

    override void render( ScriptableRenderContext ctx )
    {
        if this.colorAttachment == null || this.camera == null
        {
            ret
        }
        RenderTargetBinding binding = RenderTargetBinding( this.colorAttachment, this.depthAttachment )
        ctx.cmd.setRenderTarget( binding )
        ctx.drawSkybox( this.camera )
    }
}

# ── 全屏后处理 Pass ────────────────────────────────────
public class PostProcessPass extends RenderPass
{
    public Material postMaterial = null
    public GpuTexture source = null

    # P1 改造（2026-11-13）：无参构造完全手动设字段——原 _init_(string)
    # 调 this._init_()（子类内自调用绑定到自身 -> 无限递归，运行期地雷）
    # 且 ERenderPassEvent 为文件级 enum（成员访问解析为「最近类」静态
    # 槽，ECommandOpcode 同源教训）。桥接世界派发走基类 execute 的
    # execPost：postProcess(enabled, brightness, saturation, vignette)；
    # 草稿 render()（GpuTexture 世界）保留不动。
    public void _init_()
    {
        this.name = "PostProcessPass"
        this.profilerName = "PostProcessPass"
        this.passEvent = 800
        this.passType = RenderPass.TYPE_POST
        this.culling = null
        this.postEnabled = false
        this.postBrightness = 1.0f
        this.postSaturation = 1.0f
        this.postVignette = 1.0f
        this.blitReadbackPtr = 0
    }

    override void render( ScriptableRenderContext ctx )
    {
        # 后处理写回 backbuffer，不需要深度
        ctx.cmd.setRenderTarget( RenderTargetBinding( this.colorAttachment, null ) )
        ctx.cmd.clearRenderTarget( true, true, Color.black() )
        if this.postMaterial != null
        {
            ctx.cmd.setTexture( 0, this.source.srv() )
        }
        ctx.drawFullscreen( this.postMaterial )
    }
}

# ── P1 可执行 Pass（桥接世界：录制进共享命令流，单流提交）──────
# 构造约定：无参 _init_ 完全手动设字段、不调 this._init_()（基类
# _init_ 含文件级 enum 访问与草稿类构造，运行期地雷）；派发不靠
# virtual——基类 execute 按 passType 字段走 exec* 私有方法。
# 数据注入：culling（P0 CullingData 快照）由上层在 execute 前设好。
public class OpaquePass extends RenderPass
{
    public void _init_()
    {
        this.name = "OpaquePass"
        this.profilerName = "OpaquePass"
        this.passEvent = 200
        this.passType = RenderPass.TYPE_OPAQUE
        this.culling = null
        this.viewportX = 0
        this.viewportY = 0
        this.viewportWidth = 256
        this.viewportHeight = 256
        this.clearTargetColor = false
        this.clearTargetDepth = false
        this.postEnabled = false
        this.postBrightness = 1.0f
        this.postSaturation = 1.0f
        this.postVignette = 1.0f
        this.blitReadbackPtr = 0
    }
}

public class TransparentPass extends RenderPass
{
    public void _init_()
    {
        this.name = "TransparentPass"
        this.profilerName = "TransparentPass"
        this.passEvent = 300
        this.passType = RenderPass.TYPE_TRANSPARENT
        this.culling = null
        this.blitReadbackPtr = 0
    }
}

public class BlitPass extends RenderPass
{
    public void _init_()
    {
        this.name = "BlitPass"
        this.profilerName = "BlitPass"
        this.passEvent = 1000
        this.passType = RenderPass.TYPE_BLIT
        this.culling = null
        this.blitReadbackPtr = 0
    }
}

# ── Pass 列表（管线持有，按 passEvent 排序执行）────────────
public class RenderPassList
{
    Array<RenderPass> _passes = null

    public void _init_()
    {
        this._passes = Array<RenderPass>( 0 )
    }

    public void add( RenderPass pass )
    {
        Int32 oldLen = this._passes.length
        Array<RenderPass> np = Array<RenderPass>( oldLen + 1 )
        int i = 0
        while i < oldLen
        {
            np[i] = this._passes[i]
            i++
        }
        np[ oldLen ] = pass
        this._passes = np
    }

    public get int count()
    {
        ret this._passes.length
    }

    # 冒泡按 passEvent 升序
    public void sortByEvent()
    {
        int i = 1
        while i < this._passes.length
        {
            RenderPass key = this._passes[i]
            int j = i - 1
            while j >= 0
            {
                if this._passes[j].passEvent > key.passEvent
                {
                    this._passes[ j + 1 ] = this._passes[j]
                    j--
                }
                else
                {
                    break
                }
            }
            this._passes[ j + 1 ] = key
            i++
        }
    }

    public RenderPass at( Int32 index )
    {
        ret this._passes[ index ]
    }

    public void clear()
    {
        this._passes = Array<RenderPass>( 0 )
    }
}
