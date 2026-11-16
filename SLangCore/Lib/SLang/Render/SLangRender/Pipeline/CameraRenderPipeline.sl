import Std;
import Math;
# ============================================================================
# CameraRenderPipeline.sl —— P3 RenderPipeline 资产层（AIPrompt 需求 4）
# ----------------------------------------------------------------------------
# Unity HDRP「RenderPipelineAsset（资产/配置）+ RenderPipeline（实例）+
# Render(ScriptableRenderContext, Camera)」三段式在桥接世界（13 阶段管线
# 整数槽位世界）的落体：
#
#   RenderPipelineAsset（RenderPipeline.sl）  资产：目标尺寸/清除色/
#       FrameSettings/Feature 模板表 ——「资产声明」
#   CameraRenderPipeline（本类）            实例：持有 SLang.RenderPipeline
#       句柄门面 + ScriptableRenderContext ——「实例装配」：
#       create(asset) 建管线 + 组 context + 注册资产 Feature 模板
#   render(FrameData)（本类）              帧入口 = P1 的 context submit
#       流程包装：FrameData（P0 数据层，含 culling/perDraw/纹理/后处理参数）
#       -> 组装 Opaque/Transparent/Post/Blit 四 Pass -> beginPassRecording
#       预录帧级共享状态 -> submitPasses 单流整包（C 侧零改动）。
#       fd.culling 为空（如 Phase DATA 的 legacy 帧）时回退 runStages ——
#       「Pipeline.sl 的 renderCameraScene 改为默认实现或保留 legacy 分支」
#       的兼容策略：经 SLang.Render.usePipeline 注册后，
#       SLang.RenderPipeline.renderCameraScene(fd) 自动路由到本类（见
#       Pipeline.sl 路由段），未注册/句柄不符时走 legacy runStages。
#
# 静态注册门面：SLang.Render.usePipeline / currentPipeline / clearPipeline
#（Render.sl；AIPrompt 原定 usePipeline 门面位置，纯 SL 路由零 C 改动）。
#
# 派发/构造红线（全模块约定）：无虚函数派发、子类构造不调 this._init_()、
# 数组固定容量 + 游标、FFI <=6 参（本类零新增 FFI）。
# ============================================================================
public class CameraRenderPipeline
{
    public string name = "CameraRenderPipeline"

    # 后端句柄门面（create 时 SLang.RenderPipeline.create 产出）
    public SLang.RenderPipeline pipeline = null
    # P1 提交上下文（submitPasses 消费）
    public ScriptableRenderContext context = null
    # 资产引用（配置 + Feature 模板来源）
    public RenderPipelineAsset asset = null
    # 帧渲染配置（create 时取 asset.frameSettings，null 兜底默认）
    public FrameSettings frameSettings = null
    public Int32 width = 256
    public Int32 height = 256

    # 全局注册（SLang.Render 持引用；本类编译序在 Render.sl 之后，
    # 静态转发见 Render.sl P3 段——互引先例：RenderPass <-> Context）
    static CameraRenderPipeline _active = null

    public void _init_()
    {
        this.name = "CameraRenderPipeline"
        this.pipeline = null
        this.context = null
        this.asset = null
        this.frameSettings = null
        this.width = 256
        this.height = 256
    }

    # ── 创建 / 注册 ──────────────────────────────────────
    # create(asset) —— 资产实例化：建管线 + 组 context + 注册 Feature 模板。
    # 返回 null：资产空 / 尺寸非法 / 管线创建失败。
    public static CameraRenderPipeline create( RenderPipelineAsset a )
    {
        if a == null
        {
            ret null
        }
        Int32 w = a.targetWidth
        Int32 h = a.targetHeight
        if w <= 0 || h <= 0
        {
            ret null
        }
        SLang.RenderPipeline pipe = SLang.RenderPipeline.create( w, h )
        if pipe == null
        {
            ret null
        }
        CameraRenderPipeline cp = CameraRenderPipeline()
        cp.name = "CameraRenderPipeline"
        cp.pipeline = pipe
        cp.asset = a
        cp.width = w
        cp.height = h
        # 帧配置（null 兜底默认）
        if a.frameSettings != null
        {
            cp.frameSettings = a.frameSettings
        }
        else
        {
            cp.frameSettings = FrameSettings()
        }
        # 清除色（资产声明）
        pipe.setClearColor( a.clearR, a.clearG, a.clearB, a.clearA )
        # 组 context（P1 单流提交器）
        cp.context = ScriptableRenderContext()
        cp.context.pipeline = pipe
        # Feature 模板注册（资产声明 -> 实例装配）
        Int32 i = 0
        while i < a.featureTemplateCount()
        {
            RenderFeature f = a.featureTemplateAt( i )
            if f != null
            {
                cp.context.addFeature( f )
            }
            i = i + 1
        }
        ret cp
    }

    # use(asset) —— create + 全局注册（SLang.Render.usePipeline 转发）
    public static CameraRenderPipeline use( RenderPipelineAsset a )
    {
        CameraRenderPipeline cp = CameraRenderPipeline.create( a )
        if cp == null
        {
            ret null
        }
        SLang.Render.usePipeline( cp )
        ret cp
    }

    # active() —— 当前注册的管线实例（未注册 null）
    public static CameraRenderPipeline active()
    {
        ret SLang.Render.currentPipeline()
    }

    # clear() —— 取消全局注册（不销毁管线；destroy 另行调用）
    public static void clear()
    {
        SLang.Render.clearPipeline()
    }

    # ── 查询 ─────────────────────────────────────────────
    get bool isValid()
    {
        if this.pipeline == null
        {
            ret false
        }
        ret this.pipeline.isValid
    }

    # pipelineHandle() —— 底层句柄（renderCameraScene 路由匹配用）
    public Int64 pipelineHandle()
    {
        if this.pipeline == null
        {
            ret 0
        }
        ret this.pipeline.handle
    }

    # addFeature(feature) —— 运行期补注册（转发 context）
    public bool addFeature( RenderFeature feature )
    {
        if this.context == null
        {
            ret false
        }
        ret this.context.addFeature( feature )
    }

    public Int32 featureCount()
    {
        if this.context == null
        {
            ret 0
        }
        ret this.context.featureCount()
    }

    # stat(id) —— 统计转发（SLang.RenderPipeline.STAT_*）
    public Int32 stat( Int32 id )
    {
        if this.pipeline == null
        {
            ret 0
        }
        ret this.pipeline.stat( id )
    }

    # ── 帧入口（P3：Render(FrameData) = P1 context submit 流程包装）──
    public bool render( FrameData fd )
    {
        if this.isValid == false
        {
            ret false
        }
        if fd == null || fd.dstPixels == 0
        {
            ret false
        }
        # legacy 分支：帧数据无可视物体快照（C 侧场景对象驱动的一帧，
        # 如 Phase DATA），回退 runStages —— 行为与 P0/P1 完全一致
        if fd.culling == null || fd.culling.count() <= 0
        {
            ret this.pipeline.runStages( fd.time, fd.dstPixels )
        }
        ret this.renderBridged( fd )
    }

    # ── 桥接帧组装（数据完备的 FrameData -> 四 Pass 单流提交）──────
    bool renderBridged( FrameData fd )
    {
        FrameSettings fs = this.frameSettings
        if fs == null
        {
            fs = FrameSettings()
        }
        # 视口（fd 未设时用管线尺寸；renderScalePercent 目标尺寸缩放）
        Int32 vpX = fd.viewportX
        Int32 vpY = fd.viewportY
        Int32 vpW = fd.viewportW
        Int32 vpH = fd.viewportH
        if vpW <= 0
        {
            vpW = this.width
        }
        if vpH <= 0
        {
            vpH = this.height
        }
        if fs.renderScalePercent != 100
        {
            vpW = vpW * fs.renderScalePercent / 100
            vpH = vpH * fs.renderScalePercent / 100
            if vpW < 1
            {
                vpW = 1
            }
            if vpH < 1
            {
                vpH = 1
            }
        }
        # 组四 Pass（P1 内置；culling 快照注入）
        OpaquePass op = OpaquePass()
        op.culling = fd.culling
        op.viewportX = vpX
        op.viewportY = vpY
        op.viewportWidth = vpW
        op.viewportHeight = vpH
        op.clearTargetColor = fs.clearOnBegin
        op.clearTargetDepth = fs.clearOnBegin
        op.clearColor = Color( fd.clearR, fd.clearG, fd.clearB, fd.clearA )

        TransparentPass tp = TransparentPass()
        tp.culling = fd.culling

        PostProcessPass pp = PostProcessPass()
        pp.postEnabled = fd.postEnabled && fs.postEnabled
        pp.postBrightness = fd.postBrightness
        pp.postSaturation = fd.postSaturation
        pp.postVignette = fd.postVignette

        BlitPass bp = BlitPass()
        bp.blitReadbackPtr = fd.dstPixels

        this.context.clearPasses()
        if this.context.addPass( op ) == false
        {
            ret false
        }
        if this.context.addPass( tp ) == false
        {
            ret false
        }
        if this.context.addPass( pp ) == false
        {
            ret false
        }
        if this.context.addPass( bp ) == false
        {
            ret false
        }
        # 预录帧级共享状态（单流约束：setTexture + setPerDraw×N）
        this.context.beginPassRecording()
        CommandBuffer shared = this.context.passCommandBuffer()
        shared.transparentDescending = fs.transparentSortBackToFront
        if fd.hasTexture
        {
            shared.setTexture( fd.texSlot, fd.texHandle )
        }
        Int32 slot = 0
        while slot < PerDrawData.CAP_SLOTS
        {
            if fd.perDraw.isUsed( slot )
            {
                shared.setPerDraw( slot, fd.perDraw.getMvp( slot ), fd.perDraw.getColor( slot ) )
            }
            slot = slot + 1
        }
        # 提交（Feature 注入点在 Pass 间隙由 submitPasses 遍历）
        bool ok = this.context.submitPasses()
        this.context.clearPasses()
        ret ok
    }

    # destroy() —— 销毁底层管线（context 仅持引用，一并失效）
    public bool destroy()
    {
        if SLang.Render.currentPipeline() == this
        {
            CameraRenderPipeline.clear()
        }
        if this.pipeline == null
        {
            ret false
        }
        bool ok = this.pipeline.destroy()
        if ok
        {
            this.pipeline = null
        }
        ret ok
    }

    override string toString()
    {
        string valid = "false"
        if this.isValid
        {
            valid = "true"
        }
        ret "CameraRenderPipeline(" + this.width.toString() + "x" + this.height.toString() + ", valid=" + valid + ")"
    }
}
