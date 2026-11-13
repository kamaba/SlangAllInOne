# PipelineDemo —— P3 起改走「资产 -> 实例 -> Render(FrameData)」新入口
#
# 旧版（草稿 GfxDevice/URP 世界）已随 P3 退役：本链路无 HLSL 编译器与
# 真实 GfxDevice 后端，草稿层只演示调用流程却跑不出像素。新入口全链路
# 可执行（AIPrompt P3：UniversalRenderPipeline 真正接管单体的落地形态）：
#
#   RenderPipelineAsset（资产声明：目标尺寸/清除色/FrameSettings/Feature
#       模板表）
#       -> CameraRenderPipeline.use(asset)（实例装配 + 全局注册：
#          SLang.Render.usePipeline 门面）
#       -> FrameData（P0 数据层完备帧：culling 快照 + perDraw 槽 + 纹理 +
#          后处理参数）-> pipeline.render(fd)（四 Pass 单流提交，C 侧零改动）
#       -> readback 像素块（QLabel.setPixmapRgba 可直接消费）
#
# 用法（返回码式，本模块无 Console 引用）：
#   PipelineDemo demo = PipelineDemo()
#   bool ok = demo.startup( 256, 256 )
#   ok = demo.renderDemoFrame( 0.0f, dstPixels )
#   demo.shutdown()
#   PipelineDemo.quickStart() —— 一次性跑通（内部同上，无打印）

import Std;
import Math;

public class PipelineDemo
{
    public RenderPipelineAsset asset = null
    public CameraRenderPipeline pipeline = null
    public Int32 width = 256
    public Int32 height = 256

    public void _init_()
    {
        this.asset = null
        this.pipeline = null
        this.width = 256
        this.height = 256
    }

    # ── 启动：资产声明 + 实例装配 + 全局注册 ───────────────
    public bool startup( Int32 w, Int32 h )
    {
        if w <= 0 || h <= 0
        {
            ret false
        }
        if SLang.Render.initialize() == false
        {
            ret false
        }
        # 1) 资产声明（配置集中；Feature 模板在资产上声明，实例装配时注册）
        RenderPipelineAsset a = RenderPipelineAsset()
        a.targetWidth = w
        a.targetHeight = h
        a.clearR = 0.06f
        a.clearG = 0.06f
        a.clearB = 0.10f
        a.clearA = 1.0f
        a.frameSettings = FrameSettings()   # 默认：post on / 透明远->近
        this.asset = a

        # 2) 实例装配 + 全局注册（use = create + SLang.Render.usePipeline）
        CameraRenderPipeline cp = CameraRenderPipeline.use( a )
        if cp == null
        {
            ret false
        }
        this.pipeline = cp
        this.width = w
        this.height = h
        ret true
    }

    # ── 每帧：组 FrameData（数据完备）-> render 单流提交 ──
    # demo 内容：红三角（PerDraw 槽 0）居中，同 Phase CB/PASS 单物体场景
    public bool renderDemoFrame( Float32 time, Int64 dstPixels )
    {
        if this.pipeline == null || this.pipeline.isValid == false
        {
            ret false
        }
        if dstPixels == 0
        {
            ret false
        }
        # 帧数据（P0 数据层）：可视物体快照 + PerDraw 槽 + 视口/清除/输出
        FrameData fd = FrameData()
        fd.time = time
        fd.dstPixels = dstPixels
        fd.setViewport( 0, 0, this.width, this.height )
        fd.setClearColor( 0.06f, 0.06f, 0.10f, 1.0f )
        fd.setTarget( SLang.RenderPipeline.TARGET_SCENE, this.width, this.height )
        fd.setPost( false, 1.0f, 1.0f, 1.0f )

        Float32_4x4 mvp = Float32_4x4( 1.3f, 0.0f, 0.0f, 0.0f,
                                        0.0f, 1.3f, 0.0f, 0.0f,
                                        0.0f, 0.0f, 1.0f, 0.0f,
                                        0.0f, 0.0f, 0.0f, 1.0f )
        if fd.perDraw.setSlot( 0, mvp, Color( 1.0f, 0.0f, 0.0f, 1.0f ) ) == false
        {
            ret false
        }
        fd.culling.addItem( SLang.RenderPipeline.PROG_PFLAT, 0,
                            SLang.RenderPipeline.MESH_TRIANGLE, -1, 0, 2000, 0.0f )
        if fd.culling.count() != 1
        {
            ret false
        }
        ret this.pipeline.render( fd )
    }

    # ── 运行期注入示例：注册一个 AfterPost 全屏覆盖 Feature ──
    public bool addOverlayFeature()
    {
        if this.pipeline == null
        {
            ret false
        }
        ColorOverlayFeature f = ColorOverlayFeature()
        f.injectionPoint = EInjectionPoint.AfterPost
        f.perDrawSlot = 8    # 避开场景 PerDraw 槽 0..3
        ret this.pipeline.addFeature( f )
    }

    # ── 关闭：取消注册 + 销毁实例 ──────────────────────────
    public void shutdown()
    {
        if this.pipeline != null
        {
            this.pipeline.destroy()
            this.pipeline = null
        }
        if CameraRenderPipeline.active() != null
        {
            CameraRenderPipeline.clear()
        }
        this.asset = null
    }

    # quickStart() —— 一次性跑通（无窗口环境也能走完整链路；返回是否成功）
    static bool quickStart()
    {
        PipelineDemo demo = PipelineDemo()
        if demo.startup( 256, 256 ) == false
        {
            ret false
        }
        Int64 pixels = Memory.alloc( 256 * 256 * 4 )
        if pixels == 0
        {
            demo.shutdown()
            ret false
        }
        bool ok = demo.renderDemoFrame( 0.0f, pixels )
        Memory.free( pixels )
        demo.shutdown()
        ret ok
    }
}
