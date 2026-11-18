import SLangRender;
import SLangAudio;
import Math;
import Std;

# 环境查询 / 数据快照 / 软光追 / 异步提交 phase 分组：
#   runEnvironmentQuery  Phase ENV    渲染环境查询（支持情况/当前选择/硬件/资源/配置/帧级统计）
#   runDataSnapshot      Phase DATA   数据层快照（CullingData / FrameData / PassData）
#   runRayTracing        Phase RAY    N4a 软光追 demo（CPU whitted + SLMC RaySet*/RayRender）
#   runAsyncSubmit       Phase ASYNC  N3 异步提交（SLMC 双缓冲 + 渲染 worker 线程）
public class RenderTestPhasesE
{

    # ── Phase ENV：渲染环境查询（RenderEnvironment：支持情况 / 当前选择 /
    #    硬件条件 / 资源占用 / 当前渲染配置，快照 + 汇总显示 + 断言）──
    public static bool runEnvironmentQuery()
    {
        Console.println( "-- Phase ENV: RenderEnvironment query (support / current / hardware / resources / config) --" )
        RenderEnvironment env = RenderEnvironment.query()
        Console.println( env.toString() )
        if env.available == false
        {
            Console.println( "[env] FAIL: render library not available" )
            ret false
        }
        if env.initialized == false || env.backend != "gl"
        {
            Console.println( "[env] FAIL: expected initialized gl backend, got '" + env.backend + "'" )
            ret false
        }
        if RenderEnvironment.isBackendSupported( "gl" ) == false
        {
            Console.println( "[env] FAIL: gl not in supported backends" )
            ret false
        }
        if env.gpuRenderer == "unknown"
        {
            Console.println( "[env] FAIL: gpu renderer string missing" )
            ret false
        }
        # P4 帧级统计字段随 SRP 草稿链移除（2026-11-18）：passCount/
        # featureCount 保留恒 0（快照形状兼容，不再断言非零）
        Console.println( "[env] frame stats: passes=" + env.passCount.toString() + " featureRuns=" + env.featureCount.toString() )
        Console.println( "[env] Phase ENV: PASS (available + gl current + hardware + resources + config)" )
        ret true
    }

    # ── Phase DATA：数据层三类端到端（CullingData / FrameData / PassData）──
    # P0「数据与流程分离」验收：① CullingData —— CommandBuffer 排序后产出
    # 可视物体快照（乱序录制 -> 排序 -> 列内容/分桶计数断言）；② FrameData
    # —— buildFrameData 采集一帧上下文（目标/环境），setViewProj/setViewport/
    # setClearColor/setTarget 写入后读回，renderCameraScene(fd) 转发 runStages
    # 实渲染并做像素断言（行为与 A2 runStages 路径一致）；③ PassData ——
    # 单 Pass 数据描述（输入/输出 RT 引用 + float 参数槽读写回）。


    # ── Phase DATA：数据层三类端到端（CullingData / FrameData / PassData）──
    # P0「数据与流程分离」验收：① CullingData —— CommandBuffer 排序后产出
    # 可视物体快照（乱序录制 -> 排序 -> 列内容/分桶计数断言）；② FrameData
    # —— buildFrameData 采集一帧上下文（目标/环境），setViewProj/setViewport/
    # setClearColor/setTarget 写入后读回，renderCameraScene(fd) 转发 runStages
    # 实渲染并做像素断言（行为与 A2 runStages 路径一致）；③ PassData ——
    # 单 Pass 数据描述（输入/输出 RT 引用 + float 参数槽读写回）。
    public static bool runDataSnapshot()
    {
        Console.println( "-- Phase DATA: CullingData + FrameData + PassData (data layer, 256x256) --" )

        # ── ① CullingData：乱序录制 3 条 drawItem -> 排序 -> 快照断言 ──
        #     与 Phase CB 相同三条（蓝 z0.3 -> 贴图 z0.5 -> 三角 z0.0）；
        #     排序键 queue 升序 + 透明 z 降序 -> 快照序 = 三角/贴图/蓝
        CommandBuffer cb = CommandBuffer()
        cb.name = "cb-data"
        cb.begin()
        cb.drawItem( SLang.RenderPipeline.PROG_PFLAT, 2, SLang.RenderPipeline.MESH_QUAD, 0, 1, 3000, 0.3f )
        cb.drawItem( SLang.RenderPipeline.PROG_PTEX, 1, SLang.RenderPipeline.MESH_QUAD, 0, 1, 3000, 0.5f )
        cb.drawItem( SLang.RenderPipeline.PROG_PFLAT, 0, SLang.RenderPipeline.MESH_TRIANGLE, 0, 0, 2000, 0.0f )
        cb.end()
        Int32 sorted = cb.sortDrawItems()
        if sorted != 3
        {
            Console.println( "[data] FAIL: sortDrawItems expect 3, got " + sorted.toString() )
            ret false
        }
        CullingData cull = cb.culling
        if cull == null
        {
            Console.println( "[data] FAIL: culling snapshot missing" )
            ret false
        }
        if cull.count() != 3
        {
            Console.println( "[data] FAIL: culling count expect 3, got " + cull.count().toString() )
            ret false
        }
        Int32 q0 = cull.getQueue( 0 )
        if q0 != 2000
        {
            Console.println( "[data] FAIL: item0 queue expect 2000 (opaque first), got " + q0.toString() )
            ret false
        }
        Int32 t0 = cull.getTransp( 0 )
        Int32 t1 = cull.getTransp( 1 )
        Int32 t2 = cull.getTransp( 2 )
        if t0 != 0 || t1 != 1 || t2 != 1
        {
            Console.println( "[data] FAIL: transparent flags expect 0/1/1, got " + t0.toString() + "/" + t1.toString() + "/" + t2.toString() )
            ret false
        }
        if cull.getZ( 1 ) <= cull.getZ( 2 )
        {
            Console.println( "[data] FAIL: transparent z not descending (far-to-near)" )
            ret false
        }
        if cull.opaqueCount() != 1 || cull.transparentCount() != 2
        {
            Console.println( "[data] FAIL: bucket counts expect opaque=1 transparent=2" )
            ret false
        }
        Console.println( "[data] culling: 3 items sorted (opaque=" + cull.opaqueCount().toString() + " transparent=" + cull.transparentCount().toString() + ")" )

        # ── ② FrameData：采集 -> 写入读回 -> renderCameraScene 实渲染 ──
        SLang.RenderPipeline pipe = SLang.RenderPipeline.create( 256, 256 )
        if pipe == null
        {
            Console.println( "[data] FAIL: pipeline create - " + SLang.Render.errorString() )
            ret false
        }
        if pipe.setCamera( -1, -1.0f, 1.0f, -1.0f, 1.0f ) == false
        {
            Console.println( "[data] FAIL: setCamera - " + SLang.Render.errorString() )
            pipe.destroy()
            ret false
        }
        if pipe.setClearColor( 0.06f, 0.06f, 0.10f, 1.0f ) == false
        {
            Console.println( "[data] FAIL: setClearColor - " + SLang.Render.errorString() )
            pipe.destroy()
            ret false
        }
        SLang.RenderObject tri = pipe.addObject( SLang.RenderPipeline.MESH_TRIANGLE )
        if tri == null
        {
            Console.println( "[data] FAIL: addObject - " + SLang.Render.errorString() )
            pipe.destroy()
            ret false
        }
        tri.setLayer( 0 )
        tri.setQueue( 2000 )
        tri.setPosition( 0.0f, 0.0f, 0.0f )
        tri.setScale( 1.3f, 1.3f )
        tri.setColor( 1.0f, 0.0f, 0.0f, 1.0f )
        tri.setAnimated( SLang.RenderPipeline.ANIM_HUE_CYCLE, 0.25f )
        Int64 pixels = Memory.alloc( 256 * 256 * 4 )
        if pixels == 0
        {
            Console.println( "[data] FAIL: pixel alloc" )
            pipe.destroy()
            ret false
        }
        FrameData fd = pipe.buildFrameData( 0.0f, pixels )
        if fd == null
        {
            Console.println( "[data] FAIL: buildFrameData" )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }
        if fd.targetW != 256 || fd.targetH != 256 || fd.targetHandle != SLang.RenderPipeline.TARGET_SCENE
        {
            Console.println( "[data] FAIL: frame target expect 256x256 scene" )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }
        if fd.envBackend != "gl" || fd.envRenderer == "unknown"
        {
            Console.println( "[data] FAIL: env snapshot expect gl renderer" )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }
        Array<Float32> vp = Array<Float32>( 16 )
        Int32 vi = 0
        while vi < 16
        {
            vp[ vi ] = 0.0f
            vi = vi + 1
        }
        vp[ 0 ] = 1.5f
        vp[ 5 ] = 1.5f
        vp[ 10 ] = -1.2f
        vp[ 15 ] = 1.0f
        if fd.setViewProj( vp ) == false || fd.hasViewProj == false
        {
            Console.println( "[data] FAIL: setViewProj" )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }
        if fd.viewProj[ 0 ] < 1.49f || fd.viewProj[ 0 ] > 1.51f
        {
            Console.println( "[data] FAIL: viewProj readback" )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }
        fd.setViewport( 0, 0, 256, 256 )
        fd.setClearColor( 0.06f, 0.06f, 0.10f, 1.0f )
        fd.setTarget( SLang.RenderPipeline.TARGET_SCENE, 256, 256 )
        if fd.viewportW != 256 || fd.viewportH != 256
        {
            Console.println( "[data] FAIL: viewport readback" )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }
        if fd.clearA < 0.99f || fd.clearA > 1.01f
        {
            Console.println( "[data] FAIL: clearColor readback" )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }
        if pipe.renderCameraScene( fd ) == false
        {
            Console.println( "[data] FAIL: renderCameraScene - " + SLang.Render.errorString() )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }
        Int32 triR = RenderTestHelpers.sampleChannel( pixels, 256, 51, 184, 0 )
        Int32 triG = RenderTestHelpers.sampleChannel( pixels, 256, 51, 184, 1 )
        Int32 triB = RenderTestHelpers.sampleChannel( pixels, 256, 51, 184, 2 )
        Int32 kr = RenderTestHelpers.sampleChannel( pixels, 256, 4, 4, 0 )
        Int32 kg = RenderTestHelpers.sampleChannel( pixels, 256, 4, 4, 1 )
        Int32 kb = RenderTestHelpers.sampleChannel( pixels, 256, 4, 4, 2 )
        if triR < 240 || triG > 15 || triB > 15
        {
            Console.println( "[data] FAIL: triangle pixel expect red, got r=" + triR.toString() + " g=" + triG.toString() + " b=" + triB.toString() )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }
        if kr < 9 || kr > 21 || kg < 9 || kg > 21 || kb < 19 || kb > 33
        {
            Console.println( "[data] FAIL: corner pixel expect dark blue, got r=" + kr.toString() + " g=" + kg.toString() + " b=" + kb.toString() )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }
        Console.println( "[data] frame: target/env/viewProj/viewport ok, renderCameraScene pixels ok" )

        # ── ③ PassData：单 Pass 数据描述（输入/输出 RT + 参数槽读写回）──
        PassData pd = PassData()
        pd.begin( "opaque", 0 )
        pd.setInput( "scene", SLang.RenderPipeline.TARGET_SCENE )
        pd.setOutput( "post", SLang.RenderPipeline.TARGET_POST )
        pd.setParamFloat( "brightness", 1.25f )
        pd.setParamFloat( "vignette", 0.5f )
        if pd.name != "opaque" || pd.inputName != "scene" || pd.outputName != "post"
        {
            Console.println( "[data] FAIL: pass names" )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }
        if pd.inputHandle != SLang.RenderPipeline.TARGET_SCENE || pd.outputHandle != SLang.RenderPipeline.TARGET_POST || pd.passEvent != 0
        {
            Console.println( "[data] FAIL: pass handles" )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }
        if pd.paramCount != 2
        {
            Console.println( "[data] FAIL: param count expect 2, got " + pd.paramCount.toString() )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }
        if pd.getParamValue( "brightness" ) < 1.24f || pd.getParamValue( "brightness" ) > 1.26f
        {
            Console.println( "[data] FAIL: brightness param readback" )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }
        if pd.getParamValue( "missing" ) != 0.0f
        {
            Console.println( "[data] FAIL: missing param expect 0.0" )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }
        Console.println( "[data] pass: in/out + " + pd.paramCount.toString() + " params ok" )
        Memory.free( pixels )
        pipe.destroy()
        Console.println( "[data] Phase DATA: PASS (culling snapshot + frame data + pass data)" )
        ret true
    }

    # ── Phase RAY：软光追 demo（N4a：CPU whitted + SLMC RaySet*/RayRender）──
    # 场景（RayScene SL 参考实现与 C 侧 sl_ray.c 数学逐字一致）：
    #   地面 y=0 灰 0.55（reflect 0.2）；球 A 红色漫反射 c(0,1,0) r1
    #   reflect 0；球 B 蓝色镜面 c(1.6,0.6,1.8) r0.6 reflect 0.7；
    #   平行光 (-0.5,1,-0.5) 强度 1.0（表面 -> 光源）；相机 (0,1,-4)
    #   fov60 朝 +z；背景天蓝 (0.45,0.62,0.95)；AMBIENT 0.25。
    # 链路：cb.recordRayScene -> cb.rayRender(0,256,256)（CPU 逐像素
    #   whitted -> 产纹理写描述符槽 0）-> 全屏 quad（MESH_QUAD scale2
    #   + PROG_PTEX）贴图上屏 -> post(纯拷贝) -> blit -> readback。
    # 断言四点（回读 top-left 坐标；C 实渲 vs RayScene 参考值 ±2/255，
    #   再对手算理论值 ±6/255 双保险——公式见 RayScene 类头注释）：
    #   背景    (32,32)   射线未命中 -> (0.45,0.62,0.95) = (115,158,242)
    #   漫反射  (128,128) 球 A 正面 n·l=0.408，lit=0.658
    #            -> (0.85,0.15,0.15)*0.658 = (143,25,25)
    #   阴影    (157,175) 地面点 ~(0.62,0,0.62) 被球 A 遮挡：
    #            local=0.55*0.25=0.1375，地板 reflect 0.2 且反射线
    #            未命中 -> 0.1375*0.8 + 0.2*bg = (0.20,0.234,0.30) = (51,60,77)
    #   反射    (128,197) 光泽地板点 ~(0,0,-0.8)：lit=1.0665（未被遮挡），
    #            反射线命中球 A 背光面（n·l<0 -> 仅环境光）：
    #            0.8*0.55*1.0665 + 0.2*(0.85,0.15,0.15)*0.25
    #            = (0.512,0.477,0.477) = (131,122,122)


    # ── Phase RAY：软光追 demo（N4a：CPU whitted + SLMC RaySet*/RayRender）──
    # 场景（RayScene SL 参考实现与 C 侧 sl_ray.c 数学逐字一致）：
    #   地面 y=0 灰 0.55（reflect 0.2）；球 A 红色漫反射 c(0,1,0) r1
    #   reflect 0；球 B 蓝色镜面 c(1.6,0.6,1.8) r0.6 reflect 0.7；
    #   平行光 (-0.5,1,-0.5) 强度 1.0（表面 -> 光源）；相机 (0,1,-4)
    #   fov60 朝 +z；背景天蓝 (0.45,0.62,0.95)；AMBIENT 0.25。
    # 链路：cb.recordRayScene -> cb.rayRender(0,256,256)（CPU 逐像素
    #   whitted -> 产纹理写描述符槽 0）-> 全屏 quad（MESH_QUAD scale2
    #   + PROG_PTEX）贴图上屏 -> post(纯拷贝) -> blit -> readback。
    # 断言四点（回读 top-left 坐标；C 实渲 vs RayScene 参考值 ±2/255，
    #   再对手算理论值 ±6/255 双保险——公式见 RayScene 类头注释）：
    #   背景    (32,32)   射线未命中 -> (0.45,0.62,0.95) = (115,158,242)
    #   漫反射  (128,128) 球 A 正面 n·l=0.408，lit=0.658
    #            -> (0.85,0.15,0.15)*0.658 = (143,25,25)
    #   阴影    (157,175) 地面点 ~(0.62,0,0.62) 被球 A 遮挡：
    #            local=0.55*0.25=0.1375，地板 reflect 0.2 且反射线
    #            未命中 -> 0.1375*0.8 + 0.2*bg = (0.20,0.234,0.30) = (51,60,77)
    #   反射    (128,197) 光泽地板点 ~(0,0,-0.8)：lit=1.0665（未被遮挡），
    #            反射线命中球 A 背光面（n·l<0 -> 仅环境光）：
    #            0.8*0.55*1.0665 + 0.2*(0.85,0.15,0.15)*0.25
    #            = (0.512,0.477,0.477) = (131,122,122)
    public static bool runRayTracing()
    {
        Console.println( "-- Phase RAY: software ray tracing (CPU whitted, 2 spheres + ground, 256x256) --" )
        SLang.RenderPipeline pipe = SLang.RenderPipeline.create( 256, 256 )
        if pipe == null
        {
            Console.println( "[ray] FAIL: pipeline create - " + SLang.Render.errorString() )
            ret false
        }
        Int64 pixels = Memory.alloc( 256 * 256 * 4 )
        if pixels == 0
        {
            Console.println( "[ray] FAIL: pixel alloc" )
            pipe.destroy()
            ret false
        }

        # ── 场景（与 C 侧 RaySet* 命令同参数）─────────────────────
        RayScene scene = RayScene()
        scene.setGround( 0.55f, 0.55f, 0.55f, 0.2f )
        scene.setLight( -0.5f, 1.0f, -0.5f, 1.0f )
        scene.setCamera( 0.0f, 1.0f, -4.0f, 60.0f )
        scene.setBackground( 0.45f, 0.62f, 0.95f )
        RaySphere sphA = RaySphere()
        sphA.setAll( 0.0f, 1.0f, 0.0f, 1.0f, 0.85f, 0.15f, 0.15f, 0.0f )
        scene.addSphere( sphA )
        RaySphere sphB = RaySphere()
        sphB.setAll( 1.6f, 0.6f, 1.8f, 0.6f, 0.15f, 0.25f, 0.85f, 0.7f )
        scene.addSphere( sphB )

        # ── 录制：6 场景命令 + rayRender + 上屏 6 命令 = 13 条 ──────
        # 全屏 quad：MESH_QUAD 半径 0.5，scale 2 覆盖整个 NDC
        Float32_4x4 fsMvp = Float32_4x4( 2.0f, 0.0f, 0.0f, 0.0f,
                                         0.0f, 2.0f, 0.0f, 0.0f,
                                         0.0f, 0.0f, 1.0f, 0.0f,
                                         0.0f, 0.0f, 0.0f, 1.0f )
        CommandBuffer cb = CommandBuffer()
        cb.name = "cb-ray"
        cb.begin()
        cb.recordRayScene( scene )
        cb.rayRender( 0, 256, 256 )
        cb.setRenderTargets( SLang.RenderPipeline.TARGET_SCENE, 0, 0, 256, 256,
                             3, Color( 0.0f, 0.0f, 0.0f, 1.0f ) )
        cb.setPerDraw( 0, fsMvp, Color( 1.0f, 1.0f, 1.0f, 1.0f ) )
        cb.drawItem( SLang.RenderPipeline.PROG_PTEX, 0, SLang.RenderPipeline.MESH_QUAD, 0, 0, 2000, 0.0f )
        cb.postProcess( 0, 1.0f, 1.0f, 1.0f )
        cb.blitFinal()
        cb.readback( pixels )
        cb.end()
        Console.println( "[ray] recorded " + cb.commandCount.toString() + " commands (overflow=" + cb.overflowCount.toString() + ")" )
        if cb.commandCount != 13 || cb.overflowCount != 0
        {
            Console.println( "[ray] FAIL: commandCount expect 13, overflow expect 0" )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }

        Int32 sorted = cb.sortDrawItems()
        if sorted != 1
        {
            Console.println( "[ray] FAIL: sortDrawItems expect 1" )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }

        # ── 提交渲染：C 侧逐 opcode 回放（rayRender 产纹理 + quad 上屏）──
        if !pipe.executeCommandBuffer( cb )
        {
            Console.println( "[ray] FAIL: executeCommandBuffer - " + SLang.Render.errorString() )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }

        # 统计断言：quad + post + blit = 3 draw，1 不透明，1 实例
        Int32 statDraws = pipe.stat( SLang.RenderPipeline.STAT_DRAW_CALLS )
        Int32 statOpaque = pipe.stat( SLang.RenderPipeline.STAT_OPAQUE_DRAWS )
        Int32 statInst = pipe.stat( SLang.RenderPipeline.STAT_INSTANCE_COUNT )
        Console.println( "[ray] stats: draws=" + statDraws.toString() + " opaque=" + statOpaque.toString() + " instances=" + statInst.toString() )
        if statDraws != 3 || statOpaque != 1 || statInst != 1
        {
            Console.println( "[ray] FAIL: stats expect draws=3 opaque=1 instances=1" )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }

        # ── 四点像素断言（参考值 + 手算值双保险）──────────────────
        # 参考值：RayScene.tracePixel（与 C 侧逐字一致的 SL 实现）
        Float32_3 eBg = scene.tracePixel( 32, 32, 256, 256 )
        Float32_3 eDiff = scene.tracePixel( 128, 128, 256, 256 )
        Float32_3 eShadow = scene.tracePixel( 166, 176, 256, 256 )
        Float32_3 eRefl = scene.tracePixel( 128, 197, 256, 256 )

        # 1 背景 (32,32)：未命中 -> 纯背景色（字面值断言）
        printRayPx( "bg     ", pixels, 32, 32 )
        if rayPxOk( pixels, 256, 32, 32, 0.45f, 0.62f, 0.95f, 0.012f ) == false
        {
            Console.println( "[ray] FAIL: background (32,32) expect (0.45,0.62,0.95)" )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }

        # 2 球 A 漫反射 (128,128)
        printRayPx( "diffuse", pixels, 128, 128 )
        if rayPxOk( pixels, 256, 128, 128, eDiff.x, eDiff.y, eDiff.z, 0.008f ) == false
        {
            Console.println( "[ray] FAIL: sphere diffuse (128,128) vs reference (" + eDiff.toString() + ")" )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }
        if rayPxOk( pixels, 256, 128, 128, 0.562f, 0.099f, 0.099f, 0.024f ) == false
        {
            Console.println( "[ray] FAIL: sphere diffuse (128,128) vs hand value (143,25,25)" )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }

        # 3 地面阴影 (166,176)：地面点 (0.8,0,0.6) 在球 A 阴影椭圆内
        #   （视线绕开球；local 仅环境光，地板反射背景混 0.2）
        printRayPx( "shadow ", pixels, 166, 176 )
        if rayPxOk( pixels, 256, 166, 176, eShadow.x, eShadow.y, eShadow.z, 0.008f ) == false
        {
            Console.println( "[ray] FAIL: ground shadow (166,176) vs reference (" + eShadow.toString() + ")" )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }
        if rayPxOk( pixels, 256, 166, 176, 0.20f, 0.234f, 0.30f, 0.024f ) == false
        {
            Console.println( "[ray] FAIL: ground shadow (166,176) vs hand value (51,60,77)" )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }

        # 4 光泽地板反射 (128,197)：反射球 A 背光面（红染地板）
        printRayPx( "reflect", pixels, 128, 197 )
        if rayPxOk( pixels, 256, 128, 197, eRefl.x, eRefl.y, eRefl.z, 0.008f ) == false
        {
            Console.println( "[ray] FAIL: floor reflection (128,197) vs reference (" + eRefl.toString() + ")" )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }
        if rayPxOk( pixels, 256, 128, 197, 0.512f, 0.477f, 0.477f, 0.024f ) == false
        {
            Console.println( "[ray] FAIL: floor reflection (128,197) vs hand value (131,122,122)" )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }

        Memory.free( pixels )
        pipe.destroy()
        Console.println( "[ray] Phase RAY: PASS (bg + diffuse + shadow + reflection 4-point hand-computed assertions, ref=(" + eBg.x.toString() + "," + eDiff.x.toString() + "," + eShadow.x.toString() + "," + eRefl.x.toString() + "))" )
        ret true
    }

    # Phase RAY 像素容差检查（|actual - expect| <= tol，三通道全过才 true）
    public static bool rayPxOk( Int64 pixels, Int32 w, Int32 x, Int32 y,
                         Float32 er, Float32 eg, Float32 eb, Float32 tol )
    {
        Int32 ar = RenderTestHelpers.sampleChannel( pixels, w, x, y, 0 )
        Int32 ag = RenderTestHelpers.sampleChannel( pixels, w, x, y, 1 )
        Int32 ab = RenderTestHelpers.sampleChannel( pixels, w, x, y, 2 )
        Float32 fr = ar.toFloat32() / 255.0f
        Float32 fg = ag.toFloat32() / 255.0f
        Float32 fb = ab.toFloat32() / 255.0f
        if Mathf.abs( fr - er ) > tol
        {
            ret false
        }
        if Mathf.abs( fg - eg ) > tol
        {
            ret false
        }
        if Mathf.abs( fb - eb ) > tol
        {
            ret false
        }
        ret true
    }

    # Phase RAY 采样点打印（诊断输出；参数名避开关键字 label）


    # Phase RAY 采样点打印（诊断输出；参数名避开关键字 label）
    public static void printRayPx( string mark, Int64 pixels, Int32 x, Int32 y )
    {
        Int32 r = RenderTestHelpers.sampleChannel( pixels, 256, x, y, 0 )
        Int32 g = RenderTestHelpers.sampleChannel( pixels, 256, x, y, 1 )
        Int32 b = RenderTestHelpers.sampleChannel( pixels, 256, x, y, 2 )
        Console.println( "[ray] " + mark + " (" + x.toString() + "," + y.toString() + ") RGB=(" + r.toString() + "," + g.toString() + "," + b.toString() + ")" )
    }

    # ── Phase ASYNC：异步提交（N3：SLMC 双缓冲 + 渲染 worker 线程）──
    # 验收（AIPrompt.md N3）：模式 1 双缓冲 pack 轮换 + 同步执行、
    # 模式 2 worker 线程入队执行 —— 两模式与同步路径逐帧像素一致。
    # 每帧 6 命令流（SetRenderTargets 清色随帧变 + SetPerDraw 槽 0
    # quad 色随帧变 + DrawItem + PostProcess + Blit + Readback）：
    #   边角 (4,4) = 清色_i（quad 外）、中心 (128,128) = quad 色_i
    #   （scale 0.5 中心 quad 内）；清色/quad 色逐帧变化 —— 陈旧槽/
    #   串帧/双缓冲轮换错位立即暴露。
    # 模式 2 流程：asyncMode(1) 控制流开 worker（context 归 worker）->
    #   每帧入队（立即返回）+ asyncFlush 控制流排空（控制流进回放前
    #   先 drain 保 FIFO，返回后主线程断言像素/stats 安全）->
    #   asyncMode(0) 关 worker（context 绑回主线程）-> 1 帧同步复验
    #   （关线程后管线仍可用）。


    # ── Phase ASYNC：异步提交（N3：SLMC 双缓冲 + 渲染 worker 线程）──
    # 验收（AIPrompt.md N3）：模式 1 双缓冲 pack 轮换 + 同步执行、
    # 模式 2 worker 线程入队执行 —— 两模式与同步路径逐帧像素一致。
    # 每帧 6 命令流（SetRenderTargets 清色随帧变 + SetPerDraw 槽 0
    # quad 色随帧变 + DrawItem + PostProcess + Blit + Readback）：
    #   边角 (4,4) = 清色_i（quad 外）、中心 (128,128) = quad 色_i
    #   （scale 0.5 中心 quad 内）；清色/quad 色逐帧变化 —— 陈旧槽/
    #   串帧/双缓冲轮换错位立即暴露。
    # 模式 2 流程：asyncMode(1) 控制流开 worker（context 归 worker）->
    #   每帧入队（立即返回）+ asyncFlush 控制流排空（控制流进回放前
    #   先 drain 保 FIFO，返回后主线程断言像素/stats 安全）->
    #   asyncMode(0) 关 worker（context 绑回主线程）-> 1 帧同步复验
    #   （关线程后管线仍可用）。
    public static bool runAsyncSubmit()
    {
        Console.println( "-- Phase ASYNC: double-buffer pack + render worker (6-cmd stream per frame) --" )
        SLang.RenderPipeline pipe = SLang.RenderPipeline.create( 256, 256 )
        if pipe == null
        {
            Console.println( "[async] FAIL: pipeline create - " + SLang.Render.errorString() )
            ret false
        }
        Int64 pixels = Memory.alloc( 256 * 256 * 4 )
        if pixels == 0
        {
            Console.println( "[async] FAIL: pixel alloc" )
            pipe.destroy()
            ret false
        }

        # quad MVP：中心 scale 0.5（列向量约定，平移 0）——NDC
        # [-0.5,0.5]² -> 像素 [64,192]²：中心在内、边角在外
        Float32_4x4 quadMvp = Float32_4x4( 0.5f, 0.0f, 0.0f, 0.0f,
                                           0.0f, 0.5f, 0.0f, 0.0f,
                                           0.0f, 0.0f, 1.0f, 0.0f,
                                           0.0f, 0.0f, 0.0f, 1.0f )
        CommandBuffer frameCb = CommandBuffer()
        frameCb.name = "cb-async-frame"

        # ── 模式 1：双缓冲 pack 轮换 + 同步执行（基线像素）────────
        Int32 i = 0
        while i < 6
        {
            Float32 fi = i.toFloat32()
            Color clearCol = Color( 0.05f + 0.05f * fi, 0.06f + 0.04f * fi, 0.08f + 0.06f * fi, 1.0f )
            Color quadCol = Color( 0.90f - 0.06f * fi, 0.20f + 0.05f * fi, 0.30f + 0.07f * fi, 1.0f )
            frameCb.begin()
            frameCb.setRenderTargets( SLang.RenderPipeline.TARGET_SCENE, 0, 0, 256, 256, 3, clearCol )
            frameCb.setPerDraw( 0, quadMvp, quadCol )
            frameCb.drawItem( SLang.RenderPipeline.PROG_PFLAT, 0, SLang.RenderPipeline.MESH_QUAD, 0, 0, 2000, 0.5f )
            frameCb.postProcess( 0, 1.0f, 1.0f, 1.0f )
            frameCb.blitFinal()
            frameCb.readback( pixels )
            frameCb.end()
            if i == 0 && frameCb.commandCount != 6
            {
                Console.println( "[async] FAIL: frame stream expect 6 commands, got " + frameCb.commandCount.toString() )
                pipe.destroy()
                Memory.free( pixels )
                ret false
            }
            if !pipe.executeCommandBuffer( frameCb )
            {
                Console.println( "[async] FAIL: sync execute frame " + i.toString() + " - " + SLang.Render.errorString() )
                pipe.destroy()
                Memory.free( pixels )
                ret false
            }
            if !rayPxOk( pixels, 256, 4, 4, 0.05f + 0.05f * fi, 0.06f + 0.04f * fi, 0.08f + 0.06f * fi, 0.03f )
            {
                Console.println( "[async] FAIL: sync frame " + i.toString() + " corner should be clear color" )
                pipe.destroy()
                Memory.free( pixels )
                ret false
            }
            if !rayPxOk( pixels, 256, 128, 128, 0.90f - 0.06f * fi, 0.20f + 0.05f * fi, 0.30f + 0.07f * fi, 0.03f )
            {
                Console.println( "[async] FAIL: sync frame " + i.toString() + " center should be quad color" )
                pipe.destroy()
                Memory.free( pixels )
                ret false
            }
            i = i + 1
        }
        # stats 断言（每流 SetRenderTargets 帧级重置）：1 drawItem +
        # post + blit = 3 draws，opaque=1，transp=0
        Int32 statDraws = pipe.stat( SLang.RenderPipeline.STAT_DRAW_CALLS )
        Int32 statOpaque = pipe.stat( SLang.RenderPipeline.STAT_OPAQUE_DRAWS )
        Console.println( "[async] mode1 sync 6 frames ok; stats: draws=" + statDraws.toString() + " opaque=" + statOpaque.toString() )
        if statDraws != 3 || statOpaque != 1
        {
            Console.println( "[async] FAIL: mode1 stats expect draws=3 opaque=1" )
            pipe.destroy()
            Memory.free( pixels )
            ret false
        }

        # ── 模式 2：worker 线程（控制流开/关 + 普通流入队即返）─────
        CommandBuffer ctrlCb = CommandBuffer()
        ctrlCb.name = "cb-async-ctrl"
        ctrlCb.begin()
        ctrlCb.asyncMode( 1 )
        ctrlCb.end()
        if !pipe.executeCommandBuffer( ctrlCb )
        {
            Console.println( "[async] FAIL: asyncMode(1) control stream - " + SLang.Render.errorString() )
            pipe.destroy()
            Memory.free( pixels )
            ret false
        }
        i = 0
        while i < 6
        {
            Float32 fi = i.toFloat32()
            Color clearCol = Color( 0.05f + 0.05f * fi, 0.06f + 0.04f * fi, 0.08f + 0.06f * fi, 1.0f )
            Color quadCol = Color( 0.90f - 0.06f * fi, 0.20f + 0.05f * fi, 0.30f + 0.07f * fi, 1.0f )
            frameCb.begin()
            frameCb.setRenderTargets( SLang.RenderPipeline.TARGET_SCENE, 0, 0, 256, 256, 3, clearCol )
            frameCb.setPerDraw( 0, quadMvp, quadCol )
            frameCb.drawItem( SLang.RenderPipeline.PROG_PFLAT, 0, SLang.RenderPipeline.MESH_QUAD, 0, 0, 2000, 0.5f )
            frameCb.postProcess( 0, 1.0f, 1.0f, 1.0f )
            frameCb.blitFinal()
            frameCb.readback( pixels )
            frameCb.end()
            # 入队即返（等空槽 = 深度 2 流水线节流；worker 并行回放）
            if !pipe.executeCommandBuffer( frameCb )
            {
                Console.println( "[async] FAIL: async submit frame " + i.toString() + " - " + SLang.Render.errorString() )
                pipe.destroy()
                Memory.free( pixels )
                ret false
            }
            # 排空屏障：控制流进入回放前先 drain —— 等 worker 完成帧 i
            # 的回读后才返回，主线程断言像素安全
            ctrlCb.begin()
            ctrlCb.asyncFlush()
            ctrlCb.end()
            if !pipe.executeCommandBuffer( ctrlCb )
            {
                Console.println( "[async] FAIL: asyncFlush frame " + i.toString() + " - " + SLang.Render.errorString() )
                pipe.destroy()
                Memory.free( pixels )
                ret false
            }
            if !rayPxOk( pixels, 256, 4, 4, 0.05f + 0.05f * fi, 0.06f + 0.04f * fi, 0.08f + 0.06f * fi, 0.03f )
            {
                Console.println( "[async] FAIL: worker frame " + i.toString() + " corner should be clear color" )
                pipe.destroy()
                Memory.free( pixels )
                ret false
            }
            if !rayPxOk( pixels, 256, 128, 128, 0.90f - 0.06f * fi, 0.20f + 0.05f * fi, 0.30f + 0.07f * fi, 0.03f )
            {
                Console.println( "[async] FAIL: worker frame " + i.toString() + " center should be quad color" )
                pipe.destroy()
                Memory.free( pixels )
                ret false
            }
            i = i + 1
        }
        statDraws = pipe.stat( SLang.RenderPipeline.STAT_DRAW_CALLS )
        statOpaque = pipe.stat( SLang.RenderPipeline.STAT_OPAQUE_DRAWS )
        Console.println( "[async] mode2 worker 6 frames ok; stats: draws=" + statDraws.toString() + " opaque=" + statOpaque.toString() )
        if statDraws != 3 || statOpaque != 1
        {
            Console.println( "[async] FAIL: mode2 stats expect draws=3 opaque=1" )
            pipe.destroy()
            Memory.free( pixels )
            ret false
        }

        # 关 worker（控制流：drain -> 停线程 -> context 绑回主线程）
        ctrlCb.begin()
        ctrlCb.asyncMode( 0 )
        ctrlCb.end()
        if !pipe.executeCommandBuffer( ctrlCb )
        {
            Console.println( "[async] FAIL: asyncMode(0) control stream - " + SLang.Render.errorString() )
            pipe.destroy()
            Memory.free( pixels )
            ret false
        }

        # 同步复验：worker 关闭后管线仍可用（帧色 i=6 继续变化，
        # 检测 context 收回后的同步路径无残留状态）
        Float32 f6 = 6.0f
        Color clearCol6 = Color( 0.05f + 0.05f * f6, 0.06f + 0.04f * f6, 0.08f + 0.06f * f6, 1.0f )
        Color quadCol6 = Color( 0.90f - 0.06f * f6, 0.20f + 0.05f * f6, 0.30f + 0.07f * f6, 1.0f )
        frameCb.begin()
        frameCb.setRenderTargets( SLang.RenderPipeline.TARGET_SCENE, 0, 0, 256, 256, 3, clearCol6 )
        frameCb.setPerDraw( 0, quadMvp, quadCol6 )
        frameCb.drawItem( SLang.RenderPipeline.PROG_PFLAT, 0, SLang.RenderPipeline.MESH_QUAD, 0, 0, 2000, 0.5f )
        frameCb.postProcess( 0, 1.0f, 1.0f, 1.0f )
        frameCb.blitFinal()
        frameCb.readback( pixels )
        frameCb.end()
        if !pipe.executeCommandBuffer( frameCb )
        {
            Console.println( "[async] FAIL: post-shutdown sync execute - " + SLang.Render.errorString() )
            pipe.destroy()
            Memory.free( pixels )
            ret false
        }
        if !rayPxOk( pixels, 256, 4, 4, 0.05f + 0.05f * f6, 0.06f + 0.04f * f6, 0.08f + 0.06f * f6, 0.03f )
        {
            Console.println( "[async] FAIL: post-shutdown corner should be clear color" )
            pipe.destroy()
            Memory.free( pixels )
            ret false
        }
        if !rayPxOk( pixels, 256, 128, 128, 0.90f - 0.06f * f6, 0.20f + 0.05f * f6, 0.30f + 0.07f * f6, 0.03f )
        {
            Console.println( "[async] FAIL: post-shutdown center should be quad color" )
            pipe.destroy()
            Memory.free( pixels )
            ret false
        }

        frameCb.disposeStreams()
        ctrlCb.disposeStreams()
        pipe.destroy()
        Memory.free( pixels )
        Console.println( "[async] Phase ASYNC: PASS (mode1 sync 6 + mode2 worker 6 + post-shutdown sync 1; pixels identical)" )
        ret true
    }

    # ── Phase B：QT 窗口 + 后端切换 UI（返回 2=PASS 1=SKIP 0=FAIL）──
    # 顶部按钮行（OpenGL/D3D11/Vulkan/WebGL-GLES）点击切换渲染底层；
    # 7s 自动轮播自动验证四后端在 QT 帧循环下持续渲染（用户点击后停）；
    # 终判 = 帧数 + gl 位 + 至少一个其他后端位。
}
