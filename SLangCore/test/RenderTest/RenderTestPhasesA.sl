import SLangRender;
import SLangAudio;
import Math;
import Std;

# Phase A 主断言集（各后端同效果复用；共享 _pipe/_pixels 经 RenderTest.*）：
#   runV1Compat         v1 兼容：RenderContext 直连渲染目标快速回归
#   runPipeline         13 阶段管线主测（像素/统计/颜色变化/分层剔除/后处理/逐阶段驱动）
#   runMultiCameraImage 多相机 + 图片加载渲染（depth 升序逐相机渲染 + WIC 解码纹理）
public class RenderTestPhasesA
{

    # ── Phase A1：v1 RenderContext 直连路径回归 ─────────────────────
    public static bool runV1Compat()
    {
        Console.println( "-- Phase A1: v1 RenderContext compat (direct FBO path, 128x128) --" )

        SLang.RenderContext ctx = SLang.RenderContext.create( 128, 128 )
        if ctx == null
        {
            Console.println( "[v1] FAIL: context create - " + SLang.Render.errorString() )
            ret false
        }
        Int64 px = Memory.alloc( 128 * 128 * 4 )
        if px == 0
        {
            Console.println( "[v1] FAIL: pixel alloc" )
            ctx.destroy()
            ret false
        }
        if ctx.renderFrame( 1.0f, 0.0f, 0.0f, px ) == false
        {
            Console.println( "[v1] FAIL: renderFrame - " + SLang.Render.errorString() )
            ctx.destroy()
            ret false
        }
        Int32 cr = RenderTestHelpers.sampleChannel( px, 128, 64, 64, 0 )
        Int32 cb = RenderTestHelpers.sampleChannel( px, 128, 64, 64, 2 )
        Console.println( "[v1] center RGB.r=" + cr.toString() + " RGB.b=" + cb.toString() )
        ctx.destroy()
        if cr < 240 || cb > 15
        {
            Console.println( "[v1] FAIL: center should be red" )
            ret false
        }
        Console.println( "[v1] PASS" )
        ret true
    }

    # ── Phase A2：13 阶段管线主测 ──────────────────────────────────


    # ── Phase A2：13 阶段管线主测 ──────────────────────────────────
    public static bool runPipeline()
    {
        Console.println( "-- Phase A2: Unity-style 13-stage pipeline (256x256 RGBA8) --" )

        # 2026-11-13 修复：原误写 1280x720 —— renderFrame 按管线 w/h 回写，
        # 1280x720 会写爆 256x256 的 RenderTest._pixels 缓冲（3.5MB 堆越界，几何错位
        # 采样必失败，且堆破坏污染后续阶段）。与本阶段 256x256 采样断言一致。
        SLang.RenderPipeline pipe = SLang.RenderPipeline.create( 256, 256 )
        if pipe == null
        {
            Console.println( "[pipe] FAIL: create - " + SLang.Render.errorString() )
            ret false
        }
        RenderTest._pipe = pipe
        RenderTest._texW = 256
        RenderTest._texH = 256

        if pipe.setCamera( -1, -1.0f, 1.0f, -1.0f, 1.0f ) == false
        {
            Console.println( "[pipe] FAIL: setCamera" )
            ret false
        }
        if pipe.setClearColor( 0.06f, 0.06f, 0.10f, 1.0f ) == false
        {
            Console.println( "[pipe] FAIL: setClearColor" )
            ret false
        }

        # 对象 1：动画三角（layer0，Geometry 队列，色相循环）
        SLang.RenderObject tri = pipe.addObject( SLang.RenderPipeline.MESH_TRIANGLE )
        if tri == null
        {
            Console.println( "[pipe] FAIL: add triangle" )
            ret false
        }
        tri.setLayer( 0 )
        tri.setQueue( 2000 )
        tri.setPosition( 0.0f, 0.0f, 0.0f )
        tri.setScale( 1.3f, 1.3f )
        tri.setColor( 1.0f, 0.0f, 0.0f, 1.0f )
        tri.setAnimated( SLang.RenderPipeline.ANIM_HUE_CYCLE, 0.25f )

        # 贴图：64x64 绿->品红渐变
        Int64 texPtr = RenderTestHelpers.makeGradientTexture()
        if texPtr == 0
        {
            Console.println( "[pipe] FAIL: texture pixels alloc" )
            ret false
        }
        SLang.RenderTexture tex = SLang.RenderTexture.createRgba( texPtr, 64, 64 )
        if tex == null
        {
            Console.println( "[pipe] FAIL: texture upload - " + SLang.Render.errorString() )
            ret false
        }

        # 对象 2：贴图 quad（layer1，Transparent 队列，叠在三角右上）
        SLang.RenderObject quad = pipe.addObject( SLang.RenderPipeline.MESH_QUAD )
        if quad == null
        {
            Console.println( "[pipe] FAIL: add quad" )
            ret false
        }
        quad.setLayer( 1 )
        quad.setQueue( 3000 )
        quad.setPosition( 0.45f, 0.35f, 0.5f )
        quad.setScale( 0.55f, 0.55f )
        quad.setColor( 1.0f, 1.0f, 1.0f, 0.85f )
        quad.setTexture( tex )

        Int32 objCount = pipe.objectCount()
        Console.println( "[pipe] scene: objects=" + objCount.toString() + " textures=" + pipe.stat( SLang.RenderPipeline.STAT_TEXTURE_COUNT ).toString() )
        if objCount != 2 || pipe.stat( SLang.RenderPipeline.STAT_TEXTURE_COUNT ) < 1
        {
            Console.println( "[pipe] FAIL: scene setup counts" )
            ret false
        }

        RenderTest._pixels = Memory.alloc( 256 * 256 * 4 )
        if RenderTest._pixels == 0
        {
            Console.println( "[pipe] FAIL: pixel alloc" )
            ret false
        }

        # ── 帧 1（t=0，三角红 hue=0）：一键全流程 ──────────────────
        if pipe.renderFrame( 0.0f, RenderTest._pixels ) == false
        {
            Console.println( "[pipe] FAIL: renderFrame t=0 - " + SLang.Render.errorString() )
            ret false
        }

        # 背景（左上角，远离三角与 quad）
        Int32 kr = RenderTestHelpers.sampleChannel( RenderTest._pixels, 256, 4, 4, 0 )
        Int32 kg = RenderTestHelpers.sampleChannel( RenderTest._pixels, 256, 4, 4, 1 )
        Int32 kb = RenderTestHelpers.sampleChannel( RenderTest._pixels, 256, 4, 4, 2 )
        Console.println( "[pipe] t=0 corner   RGB=(" + kr.toString() + "," + kg.toString() + "," + kb.toString() + ")" )
        if kr < 9 || kr > 21
        {
            Console.println( "[pipe] FAIL: corner should be clear color" )
            ret false
        }
        if kg < 9 || kg > 21
        {
            Console.println( "[pipe] FAIL: corner should be clear color" )
            ret false
        }
        if kb < 19 || kb > 33
        {
            Console.println( "[pipe] FAIL: corner should be clear color" )
            ret false
        }

        # 三角内部（左下区域，不受 quad 影响）
        Int32 triR = RenderTestHelpers.sampleChannel( RenderTest._pixels, 256, 51, 184, 0 )
        Int32 triG = RenderTestHelpers.sampleChannel( RenderTest._pixels, 256, 51, 184, 1 )
        Int32 triB = RenderTestHelpers.sampleChannel( RenderTest._pixels, 256, 51, 184, 2 )
        Console.println( "[pipe] t=0 tri      RGB=(" + triR.toString() + "," + triG.toString() + "," + triB.toString() + ")" )
        if triR < 240 || triG > 15 || triB > 15
        {
            Console.println( "[pipe] FAIL: triangle should be red at t=0" )
            ret false
        }

        # 贴图 quad 区域（右上，三角外侧 -> 贴图像素混背景）
        Int32 qr = RenderTestHelpers.sampleChannel( RenderTest._pixels, 256, 204, 64, 0 )
        Int32 qg = RenderTestHelpers.sampleChannel( RenderTest._pixels, 256, 204, 64, 1 )
        Int32 qb = RenderTestHelpers.sampleChannel( RenderTest._pixels, 256, 204, 64, 2 )
        Console.println( "[pipe] t=0 quad tex RGB=(" + qr.toString() + "," + qg.toString() + "," + qb.toString() + ")" )
        if qr < 110 || qb < 110
        {
            Console.println( "[pipe] FAIL: textured quad pixel missing" )
            ret false
        }
        if qg < 35 || qg > 90
        {
            Console.println( "[pipe] FAIL: textured quad pixel missing" )
            ret false
        }

        # 管线统计断言
        Int32 lastStage = pipe.stat( SLang.RenderPipeline.STAT_LAST_STAGE )
        Int32 visible   = pipe.stat( SLang.RenderPipeline.STAT_VISIBLE )
        Int32 culled    = pipe.stat( SLang.RenderPipeline.STAT_CULLED )
        Int32 opaque    = pipe.stat( SLang.RenderPipeline.STAT_OPAQUE_DRAWS )
        Int32 transp    = pipe.stat( SLang.RenderPipeline.STAT_TRANSPARENT_DRAWS )
        Int32 layers    = pipe.stat( SLang.RenderPipeline.STAT_LAYERS_MASK )
        Int32 chunks    = pipe.stat( SLang.RenderPipeline.STAT_CHUNK_COUNT )
        Int32 uploads   = pipe.stat( SLang.RenderPipeline.STAT_UPLOAD_COUNT )
        Int32 timeMs    = pipe.stat( SLang.RenderPipeline.STAT_TIME_MS )
        Console.println( "[pipe] stats: stage=" + lastStage.toString() + " visible=" + visible.toString() + " culled=" + culled.toString() + " opaque=" + opaque.toString() + " transp=" + transp.toString() + " layers=" + layers.toString() + " chunks=" + chunks.toString() + " uploads=" + uploads.toString() )
        if lastStage != 13 || visible != 2
        {
            Console.println( "[pipe] FAIL: pipeline stats after first frame" )
            ret false
        }
        if culled != 0 || opaque != 1
        {
            Console.println( "[pipe] FAIL: pipeline stats after first frame" )
            ret false
        }
        if transp != 1 || layers != 3
        {
            Console.println( "[pipe] FAIL: pipeline stats after first frame" )
            ret false
        }
        if chunks != 2 || uploads != 4
        {
            Console.println( "[pipe] FAIL: pipeline stats after first frame" )
            ret false
        }
        if pipe.stat( SLang.RenderPipeline.STAT_DRAW_CALLS ) < 3 || pipe.stat( SLang.RenderPipeline.STAT_PROGRAM_SWITCHES ) < 3 || timeMs != 0
        {
            Console.println( "[pipe] FAIL: pipeline stats (draws/switches/time)" )
            ret false
        }

        # ── 帧 2（t=5，hue=0.25 三角转绿）：颜色变化验证 ───────────
        if pipe.renderFrame( 5.0f, RenderTest._pixels ) == false
        {
            Console.println( "[pipe] FAIL: renderFrame t=5" )
            ret false
        }
        triR = RenderTestHelpers.sampleChannel( RenderTest._pixels, 256, 51, 184, 0 )
        triG = RenderTestHelpers.sampleChannel( RenderTest._pixels, 256, 51, 184, 1 )
        triB = RenderTestHelpers.sampleChannel( RenderTest._pixels, 256, 51, 184, 2 )
        Console.println( "[pipe] t=5 tri      RGB=(" + triR.toString() + "," + triG.toString() + "," + triB.toString() + ")" )
        if triG < 200 || triB > 20
        {
            Console.println( "[pipe] FAIL: triangle should shift to green (color anim broken)" )
            ret false
        }
        if triR < 90 || triR > 180
        {
            Console.println( "[pipe] FAIL: triangle should shift to green (color anim broken)" )
            ret false
        }
        if pipe.stat( SLang.RenderPipeline.STAT_TIME_MS ) != 5000 || pipe.stat( SLang.RenderPipeline.STAT_DT_MS ) != 5000
        {
            Console.println( "[pipe] FAIL: core time update (timeMs/dtMs)" )
            ret false
        }

        # ── 帧 3：分层剔除（cullingMask 排除 layer1 -> quad 消失）──
        if pipe.setCamera( -3, -1.0f, 1.0f, -1.0f, 1.0f ) == false
        {
            Console.println( "[pipe] FAIL: setCamera mask" )
            ret false
        }
        if pipe.renderFrame( 5.0f, RenderTest._pixels ) == false
        {
            Console.println( "[pipe] FAIL: renderFrame masked" )
            ret false
        }
        qr = RenderTestHelpers.sampleChannel( RenderTest._pixels, 256, 204, 64, 0 )
        qg = RenderTestHelpers.sampleChannel( RenderTest._pixels, 256, 204, 64, 1 )
        qb = RenderTestHelpers.sampleChannel( RenderTest._pixels, 256, 204, 64, 2 )
        Console.println( "[pipe] masked quad   RGB=(" + qr.toString() + "," + qg.toString() + "," + qb.toString() + ")" )
        if qr > 30 || qg > 30
        {
            Console.println( "[pipe] FAIL: quad should vanish when layer culled" )
            ret false
        }
        if qb < 18 || qb > 34
        {
            Console.println( "[pipe] FAIL: quad should vanish when layer culled" )
            ret false
        }
        if pipe.stat( SLang.RenderPipeline.STAT_VISIBLE ) != 1 || pipe.stat( SLang.RenderPipeline.STAT_CULLED ) != 1 || pipe.stat( SLang.RenderPipeline.STAT_LAYERS_MASK ) != 1
        {
            Console.println( "[pipe] FAIL: culling stats" )
            ret false
        }
        if pipe.setCamera( -1, -1.0f, 1.0f, -1.0f, 1.0f ) == false
        {
            Console.println( "[pipe] FAIL: restore camera" )
            ret false
        }

        # ── 帧 4：后处理灰度（saturation=0 -> RGB 相等）──────────
        if pipe.setPostEffect( 1, 1.0f, 0.0f, 0.0f ) == false
        {
            Console.println( "[pipe] FAIL: setPostEffect gray" )
            ret false
        }
        if pipe.renderFrame( 0.0f, RenderTest._pixels ) == false
        {
            Console.println( "[pipe] FAIL: renderFrame post" )
            ret false
        }
        triR = RenderTestHelpers.sampleChannel( RenderTest._pixels, 256, 51, 184, 0 )
        triG = RenderTestHelpers.sampleChannel( RenderTest._pixels, 256, 51, 184, 1 )
        triB = RenderTestHelpers.sampleChannel( RenderTest._pixels, 256, 51, 184, 2 )
        Console.println( "[pipe] post gray tri  RGB=(" + triR.toString() + "," + triG.toString() + "," + triB.toString() + ")" )
        if pipe.stat( SLang.RenderPipeline.STAT_POST_ENABLED ) != 1
        {
            Console.println( "[pipe] FAIL: post enabled stat" )
            ret false
        }
        if triR - triG > 8 || triG - triR > 8
        {
            Console.println( "[pipe] FAIL: post-process grayscale (r==g==b expected)" )
            ret false
        }
        if triG - triB > 8 || triB - triG > 8
        {
            Console.println( "[pipe] FAIL: post-process grayscale (r==g==b expected)" )
            ret false
        }
        if triR < 50 || triR > 110
        {
            Console.println( "[pipe] FAIL: post-process grayscale (r==g==b expected)" )
            ret false
        }

        # 恢复视觉后处理（亮度/饱和度/暗角），供 QT 阶段展示
        if pipe.setPostEffect( 1, 1.05f, 1.15f, 0.35f ) == false
        {
            Console.println( "[pipe] FAIL: setPostEffect display" )
            ret false
        }

        # ── 帧 5：SL 侧逐阶段驱动 1..13（与 renderFrame 等价）─────
        Int64 framesBefore = pipe.frameCount()
        if pipe.runStages( 10.0f, RenderTest._pixels ) == false
        {
            Console.println( "[pipe] FAIL: runStages 1..13" )
            ret false
        }
        if pipe.stat( SLang.RenderPipeline.STAT_LAST_STAGE ) != 13
        {
            Console.println( "[pipe] FAIL: last stage after runStages" )
            ret false
        }
        if pipe.frameCount() != framesBefore + 1
        {
            Console.println( "[pipe] FAIL: frame count after runStages" )
            ret false
        }
        triR = RenderTestHelpers.sampleChannel( RenderTest._pixels, 256, 51, 184, 0 )
        triG = RenderTestHelpers.sampleChannel( RenderTest._pixels, 256, 51, 184, 1 )
        triB = RenderTestHelpers.sampleChannel( RenderTest._pixels, 256, 51, 184, 2 )
        Console.println( "[pipe] t=10 tri     RGB=(" + triR.toString() + "," + triG.toString() + "," + triB.toString() + ")" )
        if triR > 20 || triG < 200 || triB < 200
        {
            Console.println( "[pipe] FAIL: triangle should be cyan at t=10 (stages walk)" )
            ret false
        }
        if pipe.stat( SLang.RenderPipeline.STAT_TIME_MS ) != 10000 || pipe.stat( SLang.RenderPipeline.STAT_VISIBLE ) != 2
        {
            Console.println( "[pipe] FAIL: stats after stages walk" )
            ret false
        }
        if pipe.stat( SLang.RenderPipeline.STAT_FRAME ) < 5
        {
            Console.println( "[pipe] FAIL: frame stat" )
            ret false
        }

        Console.println( "[pipe] Phase A2: PASS (13-stage pipeline: triangle anim + textured quad + culling + post + staged walk)" )
        ret true
    }

    # ── Phase A3：多相机 + 图片加载渲染 ─────────────────────────────
    # 场景（256x256）：橙图 quad（layer2，test_image.png 经 WIC 加载）
    #   左半 (-0.5,0)；蓝 quad（layer0）右半 (0.5,0)；动画小三角（layer1）
    #   顶部 (0,0.6)。相机0 = 默认（全屏、mask -1、深蓝清屏）；
    #   相机1 = depth 10、mask 仅 layer2、viewport 右半、深绿清屏。
    # 断言：depth 升序（相机1 后画覆盖右半）、cullingMask 分离、
    #   viewport 分割、禁用相机回退、图片像素与纹理注册表。


    # ── Phase A3：多相机 + 图片加载渲染 ─────────────────────────────
    # 场景（256x256）：橙图 quad（layer2，test_image.png 经 WIC 加载）
    #   左半 (-0.5,0)；蓝 quad（layer0）右半 (0.5,0)；动画小三角（layer1）
    #   顶部 (0,0.6)。相机0 = 默认（全屏、mask -1、深蓝清屏）；
    #   相机1 = depth 10、mask 仅 layer2、viewport 右半、深绿清屏。
    # 断言：depth 升序（相机1 后画覆盖右半）、cullingMask 分离、
    #   viewport 分割、禁用相机回退、图片像素与纹理注册表。
    public static bool runMultiCameraImage()
    {
        Console.println( "-- Phase A3: multi-camera (depth order + viewport split) + image file load --" )

        # 图片加载：坏路径 -> null；好路径 -> 纹理句柄
        SLang.RenderTexture badTex = SLang.RenderTexture.loadFile( "no/such/file_missing.png" )
        if badTex != null
        {
            Console.println( "[cam] FAIL: loadFile should fail for missing file" )
            ret false
        }

        SLang.RenderPipeline pipe = SLang.RenderPipeline.create( 1280, 720 )
        if pipe == null
        {
            Console.println( "[cam] FAIL: pipeline create - " + SLang.Render.errorString() )
            ret false
        }

        Int32 texBefore = pipe.stat( SLang.RenderPipeline.STAT_TEXTURE_COUNT )
        # 相对路径依赖运行进程 CWD（package 目录），失败则回退绝对路径
        SLang.RenderTexture imgTex = SLang.RenderTexture.loadFile( "SlangAllInOne/SLangCore/test/RenderTest/test_image.png" )
        if imgTex == null
        {
            imgTex = SLang.RenderTexture.loadFile( "D:/project/lang/SlangAllInOne/SLangCore/test/RenderTest/test_image.png" )
        }
        if imgTex == null || imgTex.isValid == false
        {
            Console.println( "[cam] FAIL: loadFile test_image.png - " + SLang.Render.errorString() )
            ret false
        }
        if pipe.stat( SLang.RenderPipeline.STAT_TEXTURE_COUNT ) != texBefore + 1
        {
            Console.println( "[cam] FAIL: texture registry count after loadFile" )
            ret false
        }
        Console.println( "[cam] image loaded: " + imgTex.toString() )

        # 橙图 quad（layer2，不透明）
        SLang.RenderObject imgQuad = pipe.addObject( SLang.RenderPipeline.MESH_QUAD )
        if imgQuad == null
        {
            Console.println( "[cam] FAIL: add image quad" )
            ret false
        }
        imgQuad.setLayer( 2 )
        imgQuad.setQueue( 2000 )
        imgQuad.setPosition( -0.5f, 0.0f, 0.0f )
        imgQuad.setScale( 0.7f, 0.7f )
        imgQuad.setColor( 1.0f, 1.0f, 1.0f, 1.0f )
        imgQuad.setTexture( imgTex )

        # 蓝 quad（layer0，不透明，静态）
        SLang.RenderObject blueQuad = pipe.addObject( SLang.RenderPipeline.MESH_QUAD )
        if blueQuad == null
        {
            Console.println( "[cam] FAIL: add blue quad" )
            ret false
        }
        blueQuad.setLayer( 0 )
        blueQuad.setQueue( 2000 )
        blueQuad.setPosition( 0.5f, 0.0f, 0.0f )
        blueQuad.setScale( 0.6f, 0.6f )
        blueQuad.setColor( 0.2f, 0.4f, 1.0f, 1.0f )

        # 动画小三角（layer1，顶部，QT 展示动感；不触碰任何断言采样点）
        SLang.RenderObject tri = pipe.addObject( SLang.RenderPipeline.MESH_TRIANGLE )
        if tri == null
        {
            Console.println( "[cam] FAIL: add anim triangle" )
            ret false
        }
        tri.setLayer( 1 )
        tri.setQueue( 2000 )
        tri.setPosition( 0.0f, 0.6f, 0.0f )
        tri.setScale( 0.3f, 0.3f )
        tri.setColor( 1.0f, 0.0f, 0.0f, 1.0f )
        tri.setAnimated( SLang.RenderPipeline.ANIM_HUE_CYCLE, 0.25f )

        # 相机1：depth=10（后画）、mask 仅 layer2、viewport 右半、深绿清屏
        SLang.RenderCamera cam = pipe.addCamera( 10 )
        if cam == null || cam.isValid == false
        {
            Console.println( "[cam] FAIL: addCamera - " + SLang.Render.errorString() )
            ret false
        }
        if pipe.cameraCount() != 2 || cam.setCullMask( 4 ) == false || cam.setExtents( -1.0f, 1.0f, -1.0f, 1.0f ) == false
        {
            Console.println( "[cam] FAIL: camera setup" )
            ret false
        }
        if cam.setViewport( 640, 0, 640, 720 ) == false || cam.setClearColor( 0.0f, 0.25f, 0.1f, 1.0f ) == false
        {
            Console.println( "[cam] FAIL: camera viewport/clear" )
            ret false
        }
        if cam.setClearFlags( SLang.RenderPipeline.CLEAR_COLOR | SLang.RenderPipeline.CLEAR_DEPTH ) == false
        {
            Console.println( "[cam] FAIL: camera clear flags" )
            ret false
        }

        Int64 px = Memory.alloc( 1280 * 720 * 4 )
        if px == 0
        {
            Console.println( "[cam] FAIL: pixel alloc" )
            ret false
        }

        # ── 帧 1：双相机渲染（cam0 全屏 + cam1 右半覆盖）──────────
        if pipe.renderFrame( 0.0f, px ) == false
        {
            Console.println( "[cam] FAIL: renderFrame dual-cam - " + SLang.Render.errorString() )
            ret false
        }
        if pipe.stat( SLang.RenderPipeline.STAT_CAMERA_COUNT ) != 2
        {
            Console.println( "[cam] FAIL: STAT_CAMERA_COUNT should be 2" )
            ret false
        }
        Int32 vis = pipe.stat( SLang.RenderPipeline.STAT_VISIBLE )
        Console.println( "[cam] dual-cam stats: cameras=" + pipe.stat( SLang.RenderPipeline.STAT_CAMERA_COUNT ).toString() + " visible=" + vis.toString() )
        if vis != 3
        {
            Console.println( "[cam] FAIL: visible union should be 3 objects" )
            ret false
        }

        # (320,360) 左半：cam0 的橙图 quad 中心（图片橙色；世界 (-0.5,0)）
        Int32 r1 = RenderTestHelpers.sampleChannel( px, 1280, 320, 360, 0 )
        Int32 g1 = RenderTestHelpers.sampleChannel( px, 1280, 320, 360, 1 )
        Int32 b1 = RenderTestHelpers.sampleChannel( px, 1280, 320, 360, 2 )
        Console.println( "[cam] left img    RGB=(" + r1.toString() + "," + g1.toString() + "," + b1.toString() + ") @ (320,360)" )
        if r1 < 200 || g1 < 100 || g1 > 160 || b1 > 70
        {
            Console.println( "[cam] FAIL: image quad pixel should be orange in cam0 view" )
            ret false
        }
        # (800,360) 右半：cam1 重画同一橙图 quad（depth=10 后画；
        # 右半 viewport 内世界 (-0.5,0)）
        r1 = RenderTestHelpers.sampleChannel( px, 1280, 800, 360, 0 )
        g1 = RenderTestHelpers.sampleChannel( px, 1280, 800, 360, 1 )
        b1 = RenderTestHelpers.sampleChannel( px, 1280, 800, 360, 2 )
        Console.println( "[cam] right img   RGB=(" + r1.toString() + "," + g1.toString() + "," + b1.toString() + ") @ (800,360)" )
        if r1 < 200 || g1 < 100 || g1 > 160 || b1 > 70
        {
            Console.println( "[cam] FAIL: cam1 should redraw layer2 image quad in right viewport" )
            ret false
        }
        # (1200,113) 右半：cam1 独立清屏色（深绿）；cam0 深蓝背景被覆盖
        r1 = RenderTestHelpers.sampleChannel( px, 1280, 1200, 113, 0 )
        g1 = RenderTestHelpers.sampleChannel( px, 1280, 1200, 113, 1 )
        b1 = RenderTestHelpers.sampleChannel( px, 1280, 1200, 113, 2 )
        Console.println( "[cam] right clear RGB=(" + r1.toString() + "," + g1.toString() + "," + b1.toString() + ") @ (1200,113)" )
        if r1 > 15 || g1 < 55 || g1 > 75 || b1 < 15 || b1 > 35
        {
            Console.println( "[cam] FAIL: cam1 clear color should cover right viewport" )
            ret false
        }
        # (320,113) 左半：cam0 深蓝背景清屏色
        r1 = RenderTestHelpers.sampleChannel( px, 1280, 320, 113, 0 )
        g1 = RenderTestHelpers.sampleChannel( px, 1280, 320, 113, 1 )
        b1 = RenderTestHelpers.sampleChannel( px, 1280, 320, 113, 2 )
        Console.println( "[cam] left bg     RGB=(" + r1.toString() + "," + g1.toString() + "," + b1.toString() + ") @ (320,113)" )
        if r1 < 9 || r1 > 21 || g1 < 9 || g1 > 21 || b1 < 19 || b1 > 33
        {
            Console.println( "[cam] FAIL: left half should keep cam0 clear color" )
            ret false
        }

        # ── 帧 2：禁用相机1 -> 右半回到 cam0 画面（多相机选择开关）──
        if cam.setEnabled( false ) == false
        {
            Console.println( "[cam] FAIL: disable cam1" )
            ret false
        }
        if pipe.renderFrame( 0.0f, px ) == false
        {
            Console.println( "[cam] FAIL: renderFrame single-cam" )
            ret false
        }
        if pipe.stat( SLang.RenderPipeline.STAT_CAMERA_COUNT ) != 1
        {
            Console.println( "[cam] FAIL: STAT_CAMERA_COUNT should be 1 after disable" )
            ret false
        }
        r1 = RenderTestHelpers.sampleChannel( px, 1280, 800, 360, 0 )
        g1 = RenderTestHelpers.sampleChannel( px, 1280, 800, 360, 1 )
        b1 = RenderTestHelpers.sampleChannel( px, 1280, 800, 360, 2 )
        Console.println( "[cam] blue quad   RGB=(" + r1.toString() + "," + g1.toString() + "," + b1.toString() + ") @ (800,360)" )
        if r1 < 40 || r1 > 65 || g1 < 90 || g1 > 115 || b1 < 240
        {
            Console.println( "[cam] FAIL: cam0 blue quad should show after disabling cam1" )
            ret false
        }
        r1 = RenderTestHelpers.sampleChannel( px, 1280, 960, 360, 0 )
        g1 = RenderTestHelpers.sampleChannel( px, 1280, 960, 360, 1 )
        b1 = RenderTestHelpers.sampleChannel( px, 1280, 960, 360, 2 )
        Console.println( "[cam] blue quad   RGB=(" + r1.toString() + "," + g1.toString() + "," + b1.toString() + ") @ (960,360)" )
        if r1 < 40 || r1 > 65 || g1 < 90 || g1 > 115 || b1 < 240
        {
            Console.println( "[cam] FAIL: blue quad should appear in cam0-only frame" )
            ret false
        }

        # ── 场景移交 QT 窗口展示（重新启用相机1）──────────────────
        if cam.setEnabled( true ) == false
        {
            Console.println( "[cam] FAIL: re-enable cam1" )
            ret false
        }
        RenderTest._pipe = pipe
        RenderTest._pixels = px
        RenderTest._texW = 1280
        RenderTest._texH = 720

        Console.println( "[cam] Phase A3: PASS (multi-camera depth order + viewport split + cullingMask + image file render)" )
        ret true
    }

    # ── Phase L：光照（一个直射光 + 一个 spot 光 + 无光回归）────────
    # 场景（1280x720，ortho [-1,1]²，ambient 0.25）：
    #   直射光 slot 0：方向 (1,0)、白色、强度 0.9 —— 顶部两个白 quad
    #     （rot 0 朝光 vs rot π 背光）验证 ndl 按物体朝向着色；
    #   聚光 slot 1：位置 (0,0.35)、光轴 (0,-1)、锥半角 30°、范围 1.3、
    #     暖色 (1.0,0.85,0.55)、强度 1.2 —— 底部大背光 quad（rot π，
    #     ndl=0 只剩环境光）上验证锥内/锥外亮度差（锥内 + 距离衰减）。
    # v3.4 增补：
    #   阴影 —— 白 box(0.45,-0.2) castShadow（不透明 z=0、地板接收面
    #     z=-0.1）：直射光沿 -x 投出阴影 quad（偏移 0.136、放大 1.15、
    #     黑 0.35、深度夹层 -0.01），S_in(阴影内地板) 显著暗于
    #     S_out(锥内普通地板)；无光回归帧无光源 -> 阴影不生成 ->
    #     纯白基线不受影响；
    #   灯光摇晃 —— 帧 2 摆动聚光（posX=0.08*sin(2.1)、强度
    #     1.2+0.35*sin(3.7)）-> P1 亮度随灯动变化（Δ≥4）；
    #   Phong —— 独立 256 管线子场景：同光照下 Lambert quad vs Phong
    #     quad（spec 2.0/4.0）中心亮度差 = 伪 3D 高光贡献（Δ≥35）。
    # 末帧回归：clearLight(0/1) + setAmbient(1.0) -> 采样点全部回到
    # 纯白（无光照默认态与旧版逐字节一致）。
}
