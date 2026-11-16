import SLangRender;
import SLangAudio;
import Math;
import Std;

# Feature 注入 / 资产层 / RT 池 / 帧设置 phase 分组：
#   runFeatureInject   Phase FEATURE  AfterPost 全屏色块 + Volume 覆盖栈
#   runAssetPipeline   Phase ASSET    RenderPipeline 资产层（资产 -> 实例 -> Render(FrameData)）
#   runRtPool          Phase RTPOOL   RT 句柄池（同尺寸复用 / releaseAll）
#   runFrameSettings   Phase FS       FrameSettings（后处理开关 / 透明序策略 / 目标缩放）
public class RenderTestPhasesD
{

    # ── Phase FEATURE：Feature 注入（AIPrompt P2：HDRP CustomPass 等价物）──
    # 场景同 Phase PASS（蓝 z0.3 -> 贴图 z0.5 -> 三角 z0.0 + 四 Pass 单流），
    # 追加一个 AfterPost 注入点 ColorOverlayFeature（全屏绿 0.35 半透明色块，
    # PFLAT + PerDraw 槽 63，C 侧零新增）：
    #   1 注入点遍历：submitPasses 在 PostProcessPass 之后 / BlitPass 之前
    #     执行 Feature（setPerDraw + drawItem 两条命令经 replayInto 进共享流，
    #     画进 rt_post 后随 blit 进 final）；
    #   2 像素断言：整幅被绿罩调制（dst = dst*0.65 + 绿*0.35）——角落 g 由
    #     ~15 升到 ~99、三角 r 由 255 降到 ~166；
    #   3 Volume 覆盖栈：push 参数 Profile（a=0.5）二渲 -> 覆盖强度变化
    #     （g 升到 ~135），pop 后栈深归零。
    public static bool runFeatureInject()
    {
        Console.println( "-- Phase FEATURE: AfterPost ColorOverlayFeature injection (single stream, 256x256) --" )
        SLang.RenderPipeline pipe = SLang.RenderPipeline.create( 256, 256 )
        if pipe == null
        {
            Console.println( "[feat] FAIL: pipeline create - " + SLang.Render.errorString() )
            ret false
        }
        Int64 pixels = Memory.alloc( 256 * 256 * 4 )
        if pixels == 0
        {
            Console.println( "[feat] FAIL: pixel alloc" )
            pipe.destroy()
            ret false
        }
        Int64 texPtr = RenderTestHelpers.makeGradientTexture()
        if texPtr == 0
        {
            Console.println( "[feat] FAIL: texture pixels alloc" )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }
        SLang.RenderTexture tex = SLang.RenderTexture.createRgba( texPtr, 64, 64 )
        if tex == null
        {
            Console.println( "[feat] FAIL: texture upload - " + SLang.Render.errorString() )
            Memory.free( texPtr )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }

        # MVP（与 Phase PASS 同值；列向量约定：平移在 m03/m13）
        Float32_4x4 triMvp = Float32_4x4( 1.3f, 0.0f, 0.0f, 0.0f,
                                          0.0f, 1.3f, 0.0f, 0.0f,
                                          0.0f, 0.0f, 1.0f, 0.0f,
                                          0.0f, 0.0f, 0.0f, 1.0f )
        Float32_4x4 texMvp = Float32_4x4( 0.55f, 0.0f, 0.0f, 0.45f,
                                          0.0f, 0.55f, 0.0f, 0.35f,
                                          0.0f, 0.0f, 1.0f, 0.0f,
                                          0.0f, 0.0f, 0.0f, 1.0f )
        Float32_4x4 blueMvp = Float32_4x4( 0.25f, 0.0f, 0.0f, 0.55f,
                                           0.0f, 0.25f, 0.0f, 0.35f,
                                           0.0f, 0.0f, 1.0f, 0.0f,
                                           0.0f, 0.0f, 0.0f, 1.0f )

        # CullingData 快照（乱序：蓝 -> 贴图 -> 三角）
        CullingData cull = CullingData()
        cull.addItem( SLang.RenderPipeline.PROG_PFLAT, 2, SLang.RenderPipeline.MESH_QUAD, 0, 1, 3000, 0.3f )
        cull.addItem( SLang.RenderPipeline.PROG_PTEX, 1, SLang.RenderPipeline.MESH_QUAD, 0, 1, 3000, 0.5f )
        cull.addItem( SLang.RenderPipeline.PROG_PFLAT, 0, SLang.RenderPipeline.MESH_TRIANGLE, 0, 0, 2000, 0.0f )
        if cull.count() != 3
        {
            Console.println( "[feat] FAIL: culling snapshot" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }

        # 四 Pass（同 Phase PASS）
        OpaquePass op = OpaquePass()
        op.culling = cull
        op.viewportWidth = 256
        op.viewportHeight = 256
        op.clearTargetColor = true
        op.clearTargetDepth = true
        op.clearColor = Color( 0.06f, 0.06f, 0.10f, 1.0f )
        TransparentPass tp = TransparentPass()
        tp.culling = cull
        PostProcessPass pp = PostProcessPass()
        pp.postEnabled = false
        pp.postBrightness = 1.0f
        pp.postSaturation = 1.0f
        pp.postVignette = 1.0f
        BlitPass bp = BlitPass()
        bp.blitReadbackPtr = pixels

        # 一个 AfterPost Feature（绿罩 0.35；PerDraw 槽 63 避开场景 0..2）
        ColorOverlayFeature feat = ColorOverlayFeature()
        feat.injectionPoint = EInjectionPoint.AfterPost
        feat.profile.setParamFloat( "r", 0.0f )
        feat.profile.setParamFloat( "g", 1.0f )
        feat.profile.setParamFloat( "b", 0.0f )
        feat.profile.setParamFloat( "a", 0.35f )

        ScriptableRenderContext ctx = ScriptableRenderContext()
        ctx.pipeline = pipe
        if ctx.addPass( op ) == false || ctx.addPass( tp ) == false || ctx.addPass( pp ) == false || ctx.addPass( bp ) == false
        {
            Console.println( "[feat] FAIL: addPass x4" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }
        if ctx.addFeature( feat ) == false
        {
            Console.println( "[feat] FAIL: addFeature" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }
        if ctx.featureCount() != 1
        {
            Console.println( "[feat] FAIL: featureCount expect 1" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }
        VolumeStack.clear()
        if VolumeStack.depth() != 0
        {
            Console.println( "[feat] FAIL: volume stack not empty" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }

        # ── 一渲：无 Volume 覆盖（覆盖 alpha 0.35）──────────────
        ctx.beginPassRecording()
        CommandBuffer shared = ctx.passCommandBuffer()
        shared.setTexture( 0, tex.handle )
        shared.setPerDraw( 0, triMvp, Color( 1.0f, 0.0f, 0.0f, 1.0f ) )
        shared.setPerDraw( 1, texMvp, Color( 1.0f, 1.0f, 1.0f, 0.85f ) )
        shared.setPerDraw( 2, blueMvp, Color( 0.3f, 0.4f, 1.0f, 0.5f ) )
        if ctx.submitPasses() == false
        {
            Console.println( "[feat] FAIL: submitPasses 1 - " + SLang.Render.errorString() )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }

        # 命令数：4 预录 + setRT + 3 draw + post + 覆盖 2 条 + blit + readback = 13
        Console.println( "[feat] recorded " + shared.commandCount.toString() + " commands (overflow=" + shared.overflowCount.toString() + ", snapshot=" + shared.culling.count().toString() + ")" )
        if shared.commandCount != 13 || shared.overflowCount != 0
        {
            Console.println( "[feat] FAIL: commandCount expect 13, overflow expect 0" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }
        # 排序快照：场景段 3 条 + 覆盖段 1 条（post/blit 为段边界）
        if shared.culling.count() != 4
        {
            Console.println( "[feat] FAIL: culling snapshot expect 4 (3 scene + 1 overlay)" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }
        # 统计：3 物体 + 覆盖 + post + blit = 6 draws；透明 2 + 覆盖 = 3
        Int32 statDraws = pipe.stat( SLang.RenderPipeline.STAT_DRAW_CALLS )
        Int32 statOpaque = pipe.stat( SLang.RenderPipeline.STAT_OPAQUE_DRAWS )
        Int32 statTransp = pipe.stat( SLang.RenderPipeline.STAT_TRANSPARENT_DRAWS )
        Console.println( "[feat] stats: draws=" + statDraws.toString() + " opaque=" + statOpaque.toString() + " transp=" + statTransp.toString() )
        if statDraws != 6 || statOpaque != 1 || statTransp != 3
        {
            Console.println( "[feat] FAIL: stats expect draws=6 opaque=1 transp=3" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }
        # 帧级统计（P4：RenderEnvironment 消费的静态记录）
        if ScriptableRenderContext.lastPassCount != 4
        {
            Console.println( "[feat] FAIL: lastPassCount expect 4" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }
        if ScriptableRenderContext.lastFeatureRunCount != 1
        {
            Console.println( "[feat] FAIL: lastFeatureRunCount expect 1" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }

        # 像素断言（一渲）：角落 (4,4) 绿罩 -> r≈10 g≈99 b≈16
        Int32 kr = RenderTestHelpers.sampleChannel( pixels, 256, 4, 4, 0 )
        Int32 kg = RenderTestHelpers.sampleChannel( pixels, 256, 4, 4, 1 )
        Int32 kb = RenderTestHelpers.sampleChannel( pixels, 256, 4, 4, 2 )
        Console.println( "[feat] corner   RGB=(" + kr.toString() + "," + kg.toString() + "," + kb.toString() + ")" )
        if kg < 80 || kg > 120 || kr > 30
        {
            Console.println( "[feat] FAIL: corner should be green-tinted by overlay" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }
        # 三角内部 (51,184)：255*0.65≈166 + 绿 89 -> r≈166 g≈89
        Int32 triR = RenderTestHelpers.sampleChannel( pixels, 256, 51, 184, 0 )
        Int32 triG = RenderTestHelpers.sampleChannel( pixels, 256, 51, 184, 1 )
        Console.println( "[feat] tri      RGB=(" + triR.toString() + "," + triG.toString() + ",0)" )
        if triR < 145 || triR > 185 || triG < 70 || triG > 110
        {
            Console.println( "[feat] FAIL: triangle should be red*0.65 + green tint" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }

        # ── 二渲：Volume 覆盖栈（a=0.5 -> 覆盖更强，角落 g≈135）────
        VolumeProfile vp = VolumeProfile()
        vp.name = "override"
        vp.setParamFloat( "r", 0.0f )
        vp.setParamFloat( "g", 1.0f )
        vp.setParamFloat( "b", 0.0f )
        vp.setParamFloat( "a", 0.5f )
        if VolumeStack.push( vp ) == false
        {
            Console.println( "[feat] FAIL: volume push" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }
        if VolumeStack.depth() != 1
        {
            Console.println( "[feat] FAIL: volume depth expect 1" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }
        ctx.beginPassRecording()
        CommandBuffer shared2 = ctx.passCommandBuffer()
        shared2.setTexture( 0, tex.handle )
        shared2.setPerDraw( 0, triMvp, Color( 1.0f, 0.0f, 0.0f, 1.0f ) )
        shared2.setPerDraw( 1, texMvp, Color( 1.0f, 1.0f, 1.0f, 0.85f ) )
        shared2.setPerDraw( 2, blueMvp, Color( 0.3f, 0.4f, 1.0f, 0.5f ) )
        if ctx.submitPasses() == false
        {
            Console.println( "[feat] FAIL: submitPasses 2 - " + SLang.Render.errorString() )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }
        Int32 kg2 = RenderTestHelpers.sampleChannel( pixels, 256, 4, 4, 1 )
        Console.println( "[feat] corner(overlay a=0.5) g=" + kg2.toString() )
        if kg2 < 115 || kg2 > 155
        {
            Console.println( "[feat] FAIL: volume override should raise corner g to ~135" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }
        VolumeProfile popped = VolumeStack.pop()
        if popped != vp
        {
            Console.println( "[feat] FAIL: volume pop identity" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }
        if VolumeStack.depth() != 0
        {
            Console.println( "[feat] FAIL: volume depth expect 0 after pop" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }

        tex.destroy()
        Memory.free( texPtr )
        Memory.free( pixels )
        pipe.destroy()
        Console.println( "[feat] Phase FEATURE: PASS (AfterPost injection + volume override: pixels + stats all ok)" )
        ret true
    }

    # ── Phase ASSET：RenderPipeline 资产层（AIPrompt P3：需求 4）──
    # 资产声明（RenderPipelineAsset：目标尺寸/清除色/FrameSettings/Feature
    # 模板）-> 实例装配 + 全局注册（CameraRenderPipeline.use ->
    # SLang.Render.usePipeline）-> 帧数据完备组装（FrameData：culling +
    # perDraw + 纹理 + 后处理）-> 经 renderCameraScene 门面自动路由到
    # CameraRenderPipeline.render（四 Pass 单流提交）：
    #   ① 一渲断言与 Phase PASS 完全一致（draws=5 + 四像素）——资产化零行为
    #     变化；② 实例侧 addFeature 二渲 -> 覆盖生效（draws=6）；
    #   ③ clearPipeline 注销 + destroy。


    # ── Phase ASSET：RenderPipeline 资产层（AIPrompt P3：需求 4）──
    # 资产声明（RenderPipelineAsset：目标尺寸/清除色/FrameSettings/Feature
    # 模板）-> 实例装配 + 全局注册（CameraRenderPipeline.use ->
    # SLang.Render.usePipeline）-> 帧数据完备组装（FrameData：culling +
    # perDraw + 纹理 + 后处理）-> 经 renderCameraScene 门面自动路由到
    # CameraRenderPipeline.render（四 Pass 单流提交）：
    #   ① 一渲断言与 Phase PASS 完全一致（draws=5 + 四像素）——资产化零行为
    #     变化；② 实例侧 addFeature 二渲 -> 覆盖生效（draws=6）；
    #   ③ clearPipeline 注销 + destroy。
    public static bool runAssetPipeline()
    {
        Console.println( "-- Phase ASSET: RenderPipelineAsset -> CameraRenderPipeline -> Render(FrameData) (256x256) --" )
        # ① 资产声明
        RenderPipelineAsset asset = RenderPipelineAsset()
        asset.targetWidth = 256
        asset.targetHeight = 256
        asset.clearR = 0.06f
        asset.clearG = 0.06f
        asset.clearB = 0.10f
        asset.clearA = 1.0f
        asset.frameSettings = FrameSettings()
        if asset.featureTemplateCount() != 0
        {
            Console.println( "[asset] FAIL: fresh asset should have 0 feature templates" )
            ret false
        }

        # ② 实例装配 + 全局注册
        CameraRenderPipeline cp = CameraRenderPipeline.use( asset )
        if cp == null
        {
            Console.println( "[asset] FAIL: CameraRenderPipeline.use - " + SLang.Render.errorString() )
            ret false
        }
        if cp.isValid == false
        {
            Console.println( "[asset] FAIL: pipeline not valid" )
            cp.destroy()
            ret false
        }
        if SLang.Render.currentPipeline() != cp
        {
            Console.println( "[asset] FAIL: usePipeline registration missing" )
            cp.destroy()
            ret false
        }
        if cp.featureCount() != 0
        {
            Console.println( "[asset] FAIL: fresh pipeline expect 0 features" )
            SLang.Render.clearPipeline()
            cp.destroy()
            ret false
        }

        Int64 pixels = Memory.alloc( 256 * 256 * 4 )
        if pixels == 0
        {
            Console.println( "[asset] FAIL: pixel alloc" )
            SLang.Render.clearPipeline()
            cp.destroy()
            ret false
        }
        Int64 texPtr = RenderTestHelpers.makeGradientTexture()
        if texPtr == 0
        {
            Console.println( "[asset] FAIL: texture pixels alloc" )
            Memory.free( pixels )
            SLang.Render.clearPipeline()
            cp.destroy()
            ret false
        }
        SLang.RenderTexture tex = SLang.RenderTexture.createRgba( texPtr, 64, 64 )
        if tex == null
        {
            Console.println( "[asset] FAIL: texture upload - " + SLang.Render.errorString() )
            Memory.free( texPtr )
            Memory.free( pixels )
            SLang.Render.clearPipeline()
            cp.destroy()
            ret false
        }

        Float32_4x4 triMvp = Float32_4x4( 1.3f, 0.0f, 0.0f, 0.0f,
                                          0.0f, 1.3f, 0.0f, 0.0f,
                                          0.0f, 0.0f, 1.0f, 0.0f,
                                          0.0f, 0.0f, 0.0f, 1.0f )
        Float32_4x4 texMvp = Float32_4x4( 0.55f, 0.0f, 0.0f, 0.45f,
                                          0.0f, 0.55f, 0.0f, 0.35f,
                                          0.0f, 0.0f, 1.0f, 0.0f,
                                          0.0f, 0.0f, 0.0f, 1.0f )
        Float32_4x4 blueMvp = Float32_4x4( 0.25f, 0.0f, 0.0f, 0.55f,
                                           0.0f, 0.25f, 0.0f, 0.35f,
                                           0.0f, 0.0f, 1.0f, 0.0f,
                                           0.0f, 0.0f, 0.0f, 1.0f )

        # ③ 帧数据完备组装（P0 数据层：一帧的全部输入）
        FrameData fd = FrameData()
        fd.time = 0.0f
        fd.dstPixels = pixels
        fd.setViewport( 0, 0, 256, 256 )
        fd.setClearColor( 0.06f, 0.06f, 0.10f, 1.0f )
        fd.setTarget( SLang.RenderPipeline.TARGET_SCENE, 256, 256 )
        fd.setPost( false, 1.0f, 1.0f, 1.0f )
        fd.culling.addItem( SLang.RenderPipeline.PROG_PFLAT, 2, SLang.RenderPipeline.MESH_QUAD, 0, 1, 3000, 0.3f )
        fd.culling.addItem( SLang.RenderPipeline.PROG_PTEX, 1, SLang.RenderPipeline.MESH_QUAD, 0, 1, 3000, 0.5f )
        fd.culling.addItem( SLang.RenderPipeline.PROG_PFLAT, 0, SLang.RenderPipeline.MESH_TRIANGLE, 0, 0, 2000, 0.0f )
        if fd.culling.count() != 3
        {
            Console.println( "[asset] FAIL: frame culling expect 3" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            SLang.Render.clearPipeline()
            cp.destroy()
            ret false
        }
        if fd.perDraw.setSlot( 0, triMvp, Color( 1.0f, 0.0f, 0.0f, 1.0f ) ) == false
        {
            Console.println( "[asset] FAIL: perDraw slot 0" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            SLang.Render.clearPipeline()
            cp.destroy()
            ret false
        }
        if fd.perDraw.setSlot( 1, texMvp, Color( 1.0f, 1.0f, 1.0f, 0.85f ) ) == false
        {
            Console.println( "[asset] FAIL: perDraw slot 1" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            SLang.Render.clearPipeline()
            cp.destroy()
            ret false
        }
        if fd.perDraw.setSlot( 2, blueMvp, Color( 0.3f, 0.4f, 1.0f, 0.5f ) ) == false
        {
            Console.println( "[asset] FAIL: perDraw slot 2" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            SLang.Render.clearPipeline()
            cp.destroy()
            ret false
        }
        if fd.perDraw.usedCount() != 3
        {
            Console.println( "[asset] FAIL: perDraw usedCount expect 3" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            SLang.Render.clearPipeline()
            cp.destroy()
            ret false
        }
        fd.setTexture( 0, tex.handle )
        if fd.hasTexture == false
        {
            Console.println( "[asset] FAIL: frame texture flag" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            SLang.Render.clearPipeline()
            cp.destroy()
            ret false
        }

        # ④ 经 renderCameraScene 门面路由（活动管线 + 句柄一致 + 帧数据
        #    完备 -> CameraRenderPipeline.render；四 Pass 单流提交）
        SLang.RenderPipeline facade = cp.pipeline
        if facade == null
        {
            Console.println( "[asset] FAIL: facade pipeline missing" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            SLang.Render.clearPipeline()
            cp.destroy()
            ret false
        }
        if facade.renderCameraScene( fd ) == false
        {
            Console.println( "[asset] FAIL: renderCameraScene routed render - " + SLang.Render.errorString() )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            SLang.Render.clearPipeline()
            cp.destroy()
            ret false
        }

        # 统计断言（与 Phase PASS 完全一致：draws=5 opaque=1 transp=2）
        Int32 statDraws = facade.stat( SLang.RenderPipeline.STAT_DRAW_CALLS )
        Int32 statOpaque = facade.stat( SLang.RenderPipeline.STAT_OPAQUE_DRAWS )
        Int32 statTransp = facade.stat( SLang.RenderPipeline.STAT_TRANSPARENT_DRAWS )
        Console.println( "[asset] stats: draws=" + statDraws.toString() + " opaque=" + statOpaque.toString() + " transp=" + statTransp.toString() )
        if statDraws != 5 || statOpaque != 1 || statTransp != 2
        {
            Console.println( "[asset] FAIL: stats expect draws=5 opaque=1 transp=2" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            SLang.Render.clearPipeline()
            cp.destroy()
            ret false
        }
        if ScriptableRenderContext.lastPassCount != 4
        {
            Console.println( "[asset] FAIL: lastPassCount expect 4" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            SLang.Render.clearPipeline()
            cp.destroy()
            ret false
        }
        if ScriptableRenderContext.lastFeatureRunCount != 0
        {
            Console.println( "[asset] FAIL: lastFeatureRunCount expect 0 (no features yet)" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            SLang.Render.clearPipeline()
            cp.destroy()
            ret false
        }

        # 像素断言（与 Phase PASS 完全相同的四点）
        Int32 kr = RenderTestHelpers.sampleChannel( pixels, 256, 4, 4, 0 )
        Int32 kg = RenderTestHelpers.sampleChannel( pixels, 256, 4, 4, 1 )
        Int32 kb = RenderTestHelpers.sampleChannel( pixels, 256, 4, 4, 2 )
        if kr < 9 || kr > 21 || kg < 9 || kg > 21 || kb < 19 || kb > 33
        {
            Console.println( "[asset] FAIL: corner pixel (expect clear color)" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            SLang.Render.clearPipeline()
            cp.destroy()
            ret false
        }
        Int32 triR = RenderTestHelpers.sampleChannel( pixels, 256, 51, 184, 0 )
        Int32 triG = RenderTestHelpers.sampleChannel( pixels, 256, 51, 184, 1 )
        Int32 triB = RenderTestHelpers.sampleChannel( pixels, 256, 51, 184, 2 )
        if triR < 240 || triG > 15 || triB > 15
        {
            Console.println( "[asset] FAIL: triangle should be red" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            SLang.Render.clearPipeline()
            cp.destroy()
            ret false
        }
        Int32 qr = RenderTestHelpers.sampleChannel( pixels, 256, 217, 108, 0 )
        Int32 qg = RenderTestHelpers.sampleChannel( pixels, 256, 217, 108, 1 )
        Int32 qb = RenderTestHelpers.sampleChannel( pixels, 256, 217, 108, 2 )
        if qr < 110 || qb < 110 || qg < 35 || qg > 90
        {
            Console.println( "[asset] FAIL: textured quad pixel missing" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            SLang.Render.clearPipeline()
            cp.destroy()
            ret false
        }
        Int32 br = RenderTestHelpers.sampleChannel( pixels, 256, 198, 76, 0 )
        Int32 bb = RenderTestHelpers.sampleChannel( pixels, 256, 198, 76, 2 )
        Console.println( "[asset] pixels ok (corner/tri/quadtex/overlap: b=" + bb.toString() + ")" )
        if bb < 150 || ( bb - br ) < 40
        {
            Console.println( "[asset] FAIL: overlap should be blue-dominant" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            SLang.Render.clearPipeline()
            cp.destroy()
            ret false
        }

        # ⑤ 实例侧运行期注入 Feature（经管线入口直接 render）-> 覆盖生效
        # 绿罩 0.35（默认 profile 是红色 (1,0,0,0.35)，需显式配置成绿——
        # corner 期望 g∈[80,120]，断言口径与 Phase FEATURE 一渲一致）
        ColorOverlayFeature f = ColorOverlayFeature()
        f.injectionPoint = EInjectionPoint.AfterPost
        f.profile.setParamFloat( "r", 0.0f )
        f.profile.setParamFloat( "g", 1.0f )
        f.profile.setParamFloat( "b", 0.0f )
        f.profile.setParamFloat( "a", 0.35f )
        if cp.addFeature( f ) == false
        {
            Console.println( "[asset] FAIL: pipeline addFeature" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            SLang.Render.clearPipeline()
            cp.destroy()
            ret false
        }
        if cp.render( fd ) == false
        {
            Console.println( "[asset] FAIL: cp.render with feature - " + SLang.Render.errorString() )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            SLang.Render.clearPipeline()
            cp.destroy()
            ret false
        }
        Int32 statDraws2 = facade.stat( SLang.RenderPipeline.STAT_DRAW_CALLS )
        Int32 kg3 = RenderTestHelpers.sampleChannel( pixels, 256, 4, 4, 1 )
        Console.println( "[asset] feature render: draws=" + statDraws2.toString() + " corner g=" + kg3.toString() )
        if statDraws2 != 6 || kg3 < 80 || kg3 > 120
        {
            Console.println( "[asset] FAIL: expect draws=6 and green-tinted corner" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            SLang.Render.clearPipeline()
            cp.destroy()
            ret false
        }

        # ⑥ 注销 + 清理（后续 Phase 回 legacy 路由）
        SLang.Render.clearPipeline()
        if SLang.Render.currentPipeline() != null
        {
            Console.println( "[asset] FAIL: clearPipeline" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            cp.destroy()
            ret false
        }
        if cp.destroy() == false
        {
            Console.println( "[asset] FAIL: pipeline destroy" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            ret false
        }
        tex.destroy()
        Memory.free( texPtr )
        Memory.free( pixels )
        Console.println( "[asset] Phase ASSET: PASS (asset -> instance -> Render(FrameData): routing + pixels + stats identical to PASS)" )
        ret true
    }

    # ── Phase RTPOOL：RT 句柄池（AIPrompt P4：RTHandleSystem 等价物）──
    # 同尺寸请求复用（C 侧纹理计数不变）+ 异尺寸新建 + releaseAll 归零。


    # ── Phase RTPOOL：RT 句柄池（AIPrompt P4：RTHandleSystem 等价物）──
    # 同尺寸请求复用（C 侧纹理计数不变）+ 异尺寸新建 + releaseAll 归零。
    public static bool runRtPool()
    {
        Console.println( "-- Phase RTPOOL: RTHandlePool request/reuse/release (cap 64) --" )
        SLang.RTHandlePool pool = SLang.RTHandlePool()
        if pool == null
        {
            Console.println( "[pool] FAIL: pool alloc" )
            ret false
        }
        if pool.count() != 0
        {
            Console.println( "[pool] FAIL: fresh pool expect 0" )
            ret false
        }
        Int64 texPtr = RenderTestHelpers.makeGradientTexture()
        if texPtr == 0
        {
            Console.println( "[pool] FAIL: texture pixels alloc" )
            ret false
        }
        Int32 baseline = RenderFFI.ffiTextureCount()

        # ① 同尺寸两次请求 -> 同一句柄，C 侧纹理计数只 +1
        SLang.RenderTexture t1 = pool.request( 64, 64, texPtr )
        if t1 == null
        {
            Console.println( "[pool] FAIL: request 64x64 - " + SLang.Render.errorString() )
            Memory.free( texPtr )
            ret false
        }
        SLang.RenderTexture t2 = pool.request( 64, 64, texPtr )
        if t2 == null
        {
            Console.println( "[pool] FAIL: request 64x64 again" )
            pool.releaseAll()
            Memory.free( texPtr )
            ret false
        }
        if t2.handle != t1.handle
        {
            Console.println( "[pool] FAIL: same-size request should reuse handle" )
            pool.releaseAll()
            Memory.free( texPtr )
            ret false
        }
        Int32 afterReuse = RenderFFI.ffiTextureCount()
        if afterReuse != baseline + 1
        {
            Console.println( "[pool] FAIL: texture count expect +1 after reuse, got +" + ( afterReuse - baseline ).toString() )
            pool.releaseAll()
            Memory.free( texPtr )
            ret false
        }

        # ② 异尺寸请求 -> 新建句柄（池计数 2）
        SLang.RenderTexture t3 = pool.request( 32, 32, texPtr )
        if t3 == null
        {
            Console.println( "[pool] FAIL: request 32x32" )
            pool.releaseAll()
            Memory.free( texPtr )
            ret false
        }
        if t3.handle == t1.handle
        {
            Console.println( "[pool] FAIL: different-size request must not reuse" )
            pool.releaseAll()
            Memory.free( texPtr )
            ret false
        }
        Int32 afterNew = RenderFFI.ffiTextureCount()
        if afterNew != baseline + 2 || pool.count() != 2 || pool.reuseCount() != 1 || pool.requestCount() != 3
        {
            Console.println( "[pool] FAIL: pool stats (count/reuse/request)" )
            pool.releaseAll()
            Memory.free( texPtr )
            ret false
        }
        Console.println( "[pool] " + pool.toString() + ", texture count " + baseline.toString() + " -> " + afterNew.toString() )

        # ③ releaseAll -> 计数归零、C 侧纹理数回基线
        pool.releaseAll()
        if pool.count() != 0
        {
            Console.println( "[pool] FAIL: releaseAll count expect 0" )
            Memory.free( texPtr )
            ret false
        }
        Int32 afterRelease = RenderFFI.ffiTextureCount()
        if afterRelease != baseline
        {
            Console.println( "[pool] FAIL: texture count should return to baseline" )
            Memory.free( texPtr )
            ret false
        }
        Memory.free( texPtr )
        Console.println( "[pool] Phase RTPOOL: PASS (size-keyed reuse + releaseAll: counts all ok)" )
        ret true
    }

    # ── Phase FS：FrameSettings 帧渲染配置（AIPrompt P4）──
    # 经 CameraRenderPipeline 消费（同一 3 物体场景，帧数据复用）：
    #   ① transparentSortBackToFront=false -> 透明序翻转近->远：交叠区由
    #     蓝主导（默认，bb>=150）翻为贴图主导（bb<=160 判别）；
    #   ② 翻回默认远->近 -> 蓝主导恢复；
    #   ③ fd.postEnabled + sat=0（vig=0）-> 三角灰度化（同 Phase A2 灰度帧）；
    #   ④ FrameSettings.postEnabled=false 拦截 -> 纯拷贝，三角回纯红
    #     （注意：post Pass 不整段跳过——Blit 固定 post->final、Readback 固定
    #     final，跳段会读到陈旧 rt_post；实现按链路正确性对 AIPrompt
    #     "draws=3" 验收预期做偏离并记录在案）；
    #   ⑤ renderScalePercent=50 -> 视口缩半（GL 左下象限），视口内三角仍红。


    # ── Phase FS：FrameSettings 帧渲染配置（AIPrompt P4）──
    # 经 CameraRenderPipeline 消费（同一 3 物体场景，帧数据复用）：
    #   ① transparentSortBackToFront=false -> 透明序翻转近->远：交叠区由
    #     蓝主导（默认，bb>=150）翻为贴图主导（bb<=160 判别）；
    #   ② 翻回默认远->近 -> 蓝主导恢复；
    #   ③ fd.postEnabled + sat=0（vig=0）-> 三角灰度化（同 Phase A2 灰度帧）；
    #   ④ FrameSettings.postEnabled=false 拦截 -> 纯拷贝，三角回纯红
    #     （注意：post Pass 不整段跳过——Blit 固定 post->final、Readback 固定
    #     final，跳段会读到陈旧 rt_post；实现按链路正确性对 AIPrompt
    #     "draws=3" 验收预期做偏离并记录在案）；
    #   ⑤ renderScalePercent=50 -> 视口缩半（GL 左下象限），视口内三角仍红。
    public static bool runFrameSettings()
    {
        Console.println( "-- Phase FS: FrameSettings (post gate / transparent sort / render scale) --" )
        RenderPipelineAsset asset = RenderPipelineAsset()
        asset.targetWidth = 256
        asset.targetHeight = 256
        asset.frameSettings = FrameSettings()
        FrameSettings fs = asset.frameSettings
        fs.postEnabled = true
        fs.transparentSortBackToFront = false

        CameraRenderPipeline cp = CameraRenderPipeline.create( asset )
        if cp == null
        {
            Console.println( "[fs] FAIL: CameraRenderPipeline.create - " + SLang.Render.errorString() )
            ret false
        }
        Int64 pixels = Memory.alloc( 256 * 256 * 4 )
        if pixels == 0
        {
            Console.println( "[fs] FAIL: pixel alloc" )
            cp.destroy()
            ret false
        }
        Int64 texPtr = RenderTestHelpers.makeGradientTexture()
        if texPtr == 0
        {
            Console.println( "[fs] FAIL: texture pixels alloc" )
            Memory.free( pixels )
            cp.destroy()
            ret false
        }
        SLang.RenderTexture tex = SLang.RenderTexture.createRgba( texPtr, 64, 64 )
        if tex == null
        {
            Console.println( "[fs] FAIL: texture upload - " + SLang.Render.errorString() )
            Memory.free( texPtr )
            Memory.free( pixels )
            cp.destroy()
            ret false
        }

        Float32_4x4 triMvp = Float32_4x4( 1.3f, 0.0f, 0.0f, 0.0f,
                                          0.0f, 1.3f, 0.0f, 0.0f,
                                          0.0f, 0.0f, 1.0f, 0.0f,
                                          0.0f, 0.0f, 0.0f, 1.0f )
        Float32_4x4 texMvp = Float32_4x4( 0.55f, 0.0f, 0.0f, 0.45f,
                                          0.0f, 0.55f, 0.0f, 0.35f,
                                          0.0f, 0.0f, 1.0f, 0.0f,
                                          0.0f, 0.0f, 0.0f, 1.0f )
        Float32_4x4 blueMvp = Float32_4x4( 0.25f, 0.0f, 0.0f, 0.55f,
                                           0.0f, 0.25f, 0.0f, 0.35f,
                                           0.0f, 0.0f, 1.0f, 0.0f,
                                           0.0f, 0.0f, 0.0f, 1.0f )

        FrameData fd = FrameData()
        fd.time = 0.0f
        fd.dstPixels = pixels
        fd.setViewport( 0, 0, 256, 256 )
        fd.setClearColor( 0.06f, 0.06f, 0.10f, 1.0f )
        fd.setTarget( SLang.RenderPipeline.TARGET_SCENE, 256, 256 )
        fd.setPost( false, 1.0f, 1.0f, 1.0f )
        fd.culling.addItem( SLang.RenderPipeline.PROG_PFLAT, 2, SLang.RenderPipeline.MESH_QUAD, 0, 1, 3000, 0.3f )
        fd.culling.addItem( SLang.RenderPipeline.PROG_PTEX, 1, SLang.RenderPipeline.MESH_QUAD, 0, 1, 3000, 0.5f )
        fd.culling.addItem( SLang.RenderPipeline.PROG_PFLAT, 0, SLang.RenderPipeline.MESH_TRIANGLE, 0, 0, 2000, 0.0f )
        fd.perDraw.setSlot( 0, triMvp, Color( 1.0f, 0.0f, 0.0f, 1.0f ) )
        fd.perDraw.setSlot( 1, texMvp, Color( 1.0f, 1.0f, 1.0f, 0.85f ) )
        fd.perDraw.setSlot( 2, blueMvp, Color( 0.3f, 0.4f, 1.0f, 0.5f ) )
        fd.setTexture( 0, tex.handle )
        if fd.culling.count() != 3 || fd.perDraw.usedCount() != 3
        {
            Console.println( "[fs] FAIL: frame data assembly" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            cp.destroy()
            ret false
        }

        # ── ① 透明序翻转（近->远：蓝 z0.3 先画，贴图 z0.5 后画）──────
        if cp.render( fd ) == false
        {
            Console.println( "[fs] FAIL: render sort-flip - " + SLang.Render.errorString() )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            cp.destroy()
            ret false
        }
        Int32 statDraws = cp.stat( SLang.RenderPipeline.STAT_DRAW_CALLS )
        if statDraws != 5
        {
            Console.println( "[fs] FAIL: draws expect 5 (post copy still runs), got " + statDraws.toString() )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            cp.destroy()
            ret false
        }
        # 基线三点（与 PASS 相同：角落/三角/贴图独占点不受透明序影响）
        Int32 kr = RenderTestHelpers.sampleChannel( pixels, 256, 4, 4, 0 )
        Int32 kg = RenderTestHelpers.sampleChannel( pixels, 256, 4, 4, 1 )
        Int32 kb = RenderTestHelpers.sampleChannel( pixels, 256, 4, 4, 2 )
        if kr < 9 || kr > 21 || kg < 9 || kg > 21 || kb < 19 || kb > 33
        {
            Console.println( "[fs] FAIL: corner pixel" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            cp.destroy()
            ret false
        }
        Int32 triR = RenderTestHelpers.sampleChannel( pixels, 256, 51, 184, 0 )
        Int32 triG = RenderTestHelpers.sampleChannel( pixels, 256, 51, 184, 1 )
        if triR < 240 || triG > 15
        {
            Console.println( "[fs] FAIL: triangle should be red" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            cp.destroy()
            ret false
        }
        Int32 qr = RenderTestHelpers.sampleChannel( pixels, 256, 217, 108, 0 )
        Int32 qb = RenderTestHelpers.sampleChannel( pixels, 256, 217, 108, 2 )
        if qr < 110 || qb < 110
        {
            Console.println( "[fs] FAIL: textured quad pixel missing" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            cp.destroy()
            ret false
        }
        # 交叠区翻转断言：贴图后画 -> r 升 b 降（默认远->近时为蓝主导）
        Int32 oR = RenderTestHelpers.sampleChannel( pixels, 256, 198, 76, 0 )
        Int32 oB = RenderTestHelpers.sampleChannel( pixels, 256, 198, 76, 2 )
        Console.println( "[fs] overlap(front-to-back) RGB.r=" + oR.toString() + " b=" + oB.toString() )
        if oR < 125 || oB > 160
        {
            Console.println( "[fs] FAIL: transparent sort should flip overlap to tex-dominant" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            cp.destroy()
            ret false
        }

        # ── ② 翻回默认（远->近）-> 蓝主导恢复 ─────────────────────
        fs.transparentSortBackToFront = true
        if cp.render( fd ) == false
        {
            Console.println( "[fs] FAIL: render sort-default" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            cp.destroy()
            ret false
        }
        Int32 oB2 = RenderTestHelpers.sampleChannel( pixels, 256, 198, 76, 2 )
        Int32 oR2 = RenderTestHelpers.sampleChannel( pixels, 256, 198, 76, 0 )
        Console.println( "[fs] overlap(back-to-front) RGB.r=" + oR2.toString() + " b=" + oB2.toString() )
        if oB2 < 150 || ( oB2 - oR2 ) < 40
        {
            Console.println( "[fs] FAIL: default sort should restore blue-dominant overlap" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            cp.destroy()
            ret false
        }

        # ── ③ 后处理参数流（post on + sat=0 -> 三角灰度化）─────────
        fd.postEnabled = true
        fd.postSaturation = 0.0f
        fd.postVignette = 0.0f
        if cp.render( fd ) == false
        {
            Console.println( "[fs] FAIL: render post-gray" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            cp.destroy()
            ret false
        }
        Int32 gR = RenderTestHelpers.sampleChannel( pixels, 256, 51, 184, 0 )
        Int32 gG = RenderTestHelpers.sampleChannel( pixels, 256, 51, 184, 1 )
        Int32 gB = RenderTestHelpers.sampleChannel( pixels, 256, 51, 184, 2 )
        Console.println( "[fs] post gray tri  RGB=(" + gR.toString() + "," + gG.toString() + "," + gB.toString() + ")" )
        if gR - gG > 8 || gG - gR > 8 || gG - gB > 8 || gB - gG > 8
        {
            Console.println( "[fs] FAIL: post grayscale (r==g==b expected)" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            cp.destroy()
            ret false
        }
        if gR < 50 || gR > 110
        {
            Console.println( "[fs] FAIL: post gray level" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            cp.destroy()
            ret false
        }

        # ── ④ FrameSettings.postEnabled=false 拦截 -> 纯拷贝回红 ───
        fs.postEnabled = false
        if cp.render( fd ) == false
        {
            Console.println( "[fs] FAIL: render post-gated" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            cp.destroy()
            ret false
        }
        Int32 rR = RenderTestHelpers.sampleChannel( pixels, 256, 51, 184, 0 )
        Int32 rG = RenderTestHelpers.sampleChannel( pixels, 256, 51, 184, 1 )
        if rR < 240 || rG > 15
        {
            Console.println( "[fs] FAIL: gated post should copy (triangle red again)" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            cp.destroy()
            ret false
        }

        # ── ⑤ renderScalePercent=50 -> 视口缩半；视口内三角仍红 ────
        fs.postEnabled = true
        fs.renderScalePercent = 50
        fd.postEnabled = false
        if cp.render( fd ) == false
        {
            Console.println( "[fs] FAIL: render scaled viewport" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            cp.destroy()
            ret false
        }
        # (51,184) 落在 GL 左下 128x128 视口内（图象下半 x<128 区域）
        Int32 sR = RenderTestHelpers.sampleChannel( pixels, 256, 51, 184, 0 )
        Console.println( "[fs] scaled(50%) tri RGB.r=" + sR.toString() )
        if sR < 240
        {
            Console.println( "[fs] FAIL: in-viewport triangle should stay red at 50% scale" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            cp.destroy()
            ret false
        }

        tex.destroy()
        Memory.free( texPtr )
        Memory.free( pixels )
        cp.destroy()
        Console.println( "[fs] Phase FS: PASS (post gate + sort strategy + render scale all verified)" )
        ret true
    }

    # ── Phase ENV：渲染环境查询（RenderEnvironment：支持情况 / 当前选择 /
    #    硬件条件 / 资源占用 / 当前渲染配置，快照 + 汇总显示 + 断言）──
}
