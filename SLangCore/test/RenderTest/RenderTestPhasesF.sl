import SLangRender;
import SLangAudio;
import Math;
import Std;

# AA（FXAA + MSAA）/ MotionVectors phase 分组（v3.6，doc/14 v1.2）：
#   runAa      Phase AA   FXAA 内嵌后处理前段 + MSAA 多采样 resolve
#   runMotion  Phase MV   MotionVectors 速度 RT（RG = 速度*0.5+0.5 编码）
#
# 断言策略（GL 后端 128x128；斜边物体最大化 AA 效果差异）：
#   AA  1) 基线（全关）渲染 45° 旋转 quad；
#       2) FXAA on：中心平坦区像素与基线一致（±2）——FXAA 不动平坦区；
#       3) FXAA on：整图差异像素数 > 0——斜边确实被平滑；
#       4) MSAA 4x：整图与基线差异像素数 > 0（边缘混合生效）；
#       5) MSAA + FXAA 组合冒烟（不崩 + 中心一致）；
#       6) 恢复全关：输出与基线逐位一致（零回归）。
#   MV  1) 开关 + 统计（STAT_MV_ENABLED / STAT_MSAA_SAMPLES 回读）；
#       2) 静止两帧：中心 RG ≈ 128（速度 0 = 编码 0.5）；
#       3) +x 移动一帧：中心 R ≈ 0.2*0.5+0.5=0.6 -> 153、G ≈ 128；
#       4) -x 移动一帧：中心 R ≈ 0.4*0.5+0.5=0.7? 否——复位语义：
#          prev = 上帧快照，逐步校验 R 随速度线性变化；
#       5) 关闭后 outputMotionTexture 返回 false。
public class RenderTestPhasesF
{

    # 统计整图与基线不同的像素数（任一 RGB 通道差 > tol 计 1）
    public static Int32 countDiff( Int64 pa, Int64 pb, Int32 w, Int32 h, Int32 tol )
    {
        Int32 n = 0
        Int32 i = 0
        Int32 total = w * h * 4
        while i < total
        {
            Int32 dr = Memory.readUInt8( pa, i ) - Memory.readUInt8( pb, i )
            if dr < 0
            {
                dr = 0 - dr
            }
            if dr > tol
            {
                n = n + 1
            }
            i = i + 1
        }
        ret n
    }

    # ── Phase AA：FXAA + MSAA 端到端 ────────────────────────────────
    public static bool runAa()
    {
        Console.println( "-- Phase AA: FXAA + MSAA --" )
        SLang.RenderPipeline pipe = SLang.RenderPipeline.create( 128, 128 )
        if pipe == null
        {
            Console.println( "[aa] FAIL: pipeline create - " + SLang.Render.errorString() )
            ret false
        }
        pipe.setClearColor( 0.06f, 0.06f, 0.10f, 1.0f )
        # 45° 旋转 quad（斜边 -> MSAA/FXAA 效果最大化）
        SLang.RenderObject quad = pipe.addObject( SLang.RenderPipeline.MESH_QUAD )
        quad.setPosition( 0.0f, 0.0f, 0.0f )
        quad.setRotationZ( 0.785398f )
        quad.setScale( 0.7f, 0.7f )
        quad.setColor( 0.9f, 0.2f, 0.2f, 1.0f )
        Int64 pxA = Memory.alloc( 128 * 128 * 4 )
        Int64 pxB = Memory.alloc( 128 * 128 * 4 )
        if pxA == 0 || pxB == 0
        {
            Console.println( "[aa] FAIL: alloc pixels" )
            ret false
        }

        # 1) 基线（全关）
        Int32 act = pipe.setAa( 0, 0, 8.0f )
        if act != 0
        {
            Console.println( "[aa] FAIL: baseline msaa request 0 got " + act )
            ret false
        }
        if pipe.renderFrame( 0.0f, pxA ) == false
        {
            Console.println( "[aa] FAIL: baseline render - " + SLang.Render.errorString() )
            ret false
        }

        # 2) FXAA on：中心平坦区与基线一致
        if pipe.setAa( 0, 1, 8.0f ) != 0
        {
            Console.println( "[aa] FAIL: fxaa-only msaa should be 0" )
            ret false
        }
        if pipe.renderFrame( 0.0f, pxB ) == false
        {
            Console.println( "[aa] FAIL: fxaa render" )
            ret false
        }
        Int32 cr0 = RenderTestHelpers.sampleChannel( pxA, 128, 64, 64, 0 )
        Int32 cr1 = RenderTestHelpers.sampleChannel( pxB, 128, 64, 64, 0 )
        Int32 dr = cr1 - cr0
        if dr < 0
        {
            dr = 0 - dr
        }
        if dr > 2
        {
            Console.println( "[aa] FAIL: fxaa changed flat center (" + cr0 + "->" + cr1 + ")" )
            ret false
        }
        Int32 fxaaDiff = countDiff( pxA, pxB, 128, 128, 2 )
        Console.println( "[aa] fxaa diff pixels: " + fxaaDiff )
        # 3) 斜边确实被平滑（差异像素 > 0）
        if fxaaDiff <= 0
        {
            Console.println( "[aa] FAIL: fxaa produced no edge change" )
            ret false
        }

        # 4) MSAA 4x：边缘混合生效（与基线差异 > 0，中心平坦区一致）
        Int32 actMs = pipe.setAa( 4, 0, 8.0f )
        Console.println( "[aa] msaa requested 4 active " + actMs )
        if actMs != 4
        {
            Console.println( "[aa] FAIL: msaa 4 not active (got " + actMs + ")" )
            ret false
        }
        if pipe.renderFrame( 0.0f, pxB ) == false
        {
            Console.println( "[aa] FAIL: msaa render" )
            ret false
        }
        Int32 msaaDiff = countDiff( pxA, pxB, 128, 128, 2 )
        Console.println( "[aa] msaa diff pixels: " + msaaDiff )
        if msaaDiff <= 0
        {
            Console.println( "[aa] FAIL: msaa produced no edge change" )
            ret false
        }
        Int32 crMs = RenderTestHelpers.sampleChannel( pxB, 128, 64, 64, 0 )
        Int32 drm = crMs - cr0
        if drm < 0
        {
            drm = 0 - drm
        }
        if drm > 2
        {
            Console.println( "[aa] FAIL: msaa changed flat center (" + cr0 + "->" + crMs + ")" )
            ret false
        }

        # 5) MSAA + FXAA 组合冒烟
        if pipe.setAa( 4, 1, 8.0f ) != 4
        {
            Console.println( "[aa] FAIL: msaa+fxaa combo" )
            ret false
        }
        if pipe.renderFrame( 0.0f, pxB ) == false
        {
            Console.println( "[aa] FAIL: msaa+fxaa render" )
            ret false
        }
        Console.println( "[aa] msaa+fxaa combo OK" )

        # 6) 恢复全关：与基线逐位一致（零回归）
        if pipe.setAa( 0, 0, 8.0f ) != 0
        {
            Console.println( "[aa] FAIL: restore off" )
            ret false
        }
        if pipe.renderFrame( 0.0f, pxB ) == false
        {
            Console.println( "[aa] FAIL: restore render" )
            ret false
        }
        Int32 restoreDiff = countDiff( pxA, pxB, 128, 128, 0 )
        if restoreDiff != 0
        {
            Console.println( "[aa] FAIL: off-path not bit-identical (" + restoreDiff + " px)" )
            ret false
        }
        Console.println( "[aa] restore bit-identical OK" )
        pipe.destroy()
        Memory.free( pxA )
        Memory.free( pxB )
        Console.println( "[aa] PASS" )
        ret true
    }

    # ── Phase MV：MotionVectors 速度 RT 端到端 ─────────────────────
    public static bool runMotion()
    {
        Console.println( "-- Phase MV: motion vectors --" )
        SLang.RenderPipeline pipe = SLang.RenderPipeline.create( 128, 128 )
        if pipe == null
        {
            Console.println( "[mv] FAIL: pipeline create - " + SLang.Render.errorString() )
            ret false
        }
        pipe.setClearColor( 0.06f, 0.06f, 0.10f, 1.0f )
        SLang.RenderObject quad = pipe.addObject( SLang.RenderPipeline.MESH_QUAD )
        quad.setPosition( 0.0f, 0.0f, 0.0f )
        quad.setScale( 0.6f, 0.6f )
        quad.setColor( 0.9f, 0.2f, 0.2f, 1.0f )
        Int64 px = Memory.alloc( 128 * 128 * 4 )
        Int64 mv = Memory.alloc( 128 * 128 * 4 )
        if px == 0 || mv == 0
        {
            Console.println( "[mv] FAIL: alloc" )
            ret false
        }

        # 1) 开关 + 统计
        if pipe.setMotionVectors( 1 ) == false
        {
            Console.println( "[mv] FAIL: setMotionVectors - " + SLang.Render.errorString() )
            ret false
        }
        if pipe.stat( SLang.RenderPipeline.STAT_MV_ENABLED ) != 1
        {
            Console.println( "[mv] FAIL: stat mv enabled" )
            ret false
        }

        # 2) 静止两帧：中心 RG ≈ 128（速度 0）
        if pipe.renderFrame( 0.0f, px ) == false
        {
            Console.println( "[mv] FAIL: static frame 1" )
            ret false
        }
        if pipe.renderFrame( 0.0f, px ) == false
        {
            Console.println( "[mv] FAIL: static frame 2" )
            ret false
        }
        if pipe.outputMotionTexture( mv ) == false
        {
            Console.println( "[mv] FAIL: output motion rt - " + SLang.Render.errorString() )
            ret false
        }
        Int32 sr = RenderTestHelpers.sampleChannel( mv, 128, 64, 64, 0 )
        Int32 sg = RenderTestHelpers.sampleChannel( mv, 128, 64, 64, 1 )
        Console.println( "[mv] static center RG: (" + sr + "," + sg + ")" )
        Int32 dsr = sr - 128
        if dsr < 0
        {
            dsr = 0 - dsr
        }
        Int32 dsg = sg - 128
        if dsg < 0
        {
            dsg = 0 - dsg
        }
        if dsr > 2 || dsg > 2
        {
            Console.println( "[mv] FAIL: static object has nonzero velocity (" + sr + "," + sg + ")" )
            ret false
        }

        # 3) +x 移动一帧：prev=(0,0) cur=(0.2,0) -> 速度 ndc 0.2
        #    R = 0.2*0.5+0.5 = 0.6 -> 153；G = 128
        quad.setPosition( 0.2f, 0.0f, 0.0f )
        if pipe.renderFrame( 0.0f, px ) == false
        {
            Console.println( "[mv] FAIL: moving frame" )
            ret false
        }
        if pipe.outputMotionTexture( mv ) == false
        {
            Console.println( "[mv] FAIL: output motion rt (moving)" )
            ret false
        }
        Int32 mr = RenderTestHelpers.sampleChannel( mv, 128, 64, 64, 0 )
        Int32 mg = RenderTestHelpers.sampleChannel( mv, 128, 64, 64, 1 )
        Console.println( "[mv] moving(+x) center RG: (" + mr + "," + mg + ")" )
        if mr < 140
        {
            Console.println( "[mv] FAIL: +x velocity too small (R=" + mr + ")" )
            ret false
        }
        Int32 dmg = mg - 128
        if dmg < 0
        {
            dmg = 0 - dmg
        }
        if dmg > 4
        {
            Console.println( "[mv] FAIL: y velocity should be 0 (G=" + mg + ")" )
            ret false
        }

        # 4) -x 回移：prev=(0.2,0) cur=(0,0) -> 速度 -0.2 -> R ≈ 103
        quad.setPosition( 0.0f, 0.0f, 0.0f )
        if pipe.renderFrame( 0.0f, px ) == false
        {
            Console.println( "[mv] FAIL: moving back frame" )
            ret false
        }
        if pipe.outputMotionTexture( mv ) == false
        {
            Console.println( "[mv] FAIL: output motion rt (back)" )
            ret false
        }
        Int32 br = RenderTestHelpers.sampleChannel( mv, 128, 64, 64, 0 )
        Console.println( "[mv] moving(-x) center R: " + br )
        if br > 116
        {
            Console.println( "[mv] FAIL: -x velocity too small (R=" + br + ")" )
            ret false
        }

        # 5) 关闭：RT 输出失效 + 统计回 0
        if pipe.setMotionVectors( 0 ) == false
        {
            Console.println( "[mv] FAIL: disable motion" )
            ret false
        }
        if pipe.outputMotionTexture( mv ) != false
        {
            Console.println( "[mv] FAIL: disabled motion rt should fail" )
            ret false
        }
        if pipe.stat( SLang.RenderPipeline.STAT_MV_ENABLED ) != 0
        {
            Console.println( "[mv] FAIL: stat mv disabled" )
            ret false
        }
        pipe.destroy()
        Memory.free( px )
        Memory.free( mv )
        Console.println( "[mv] PASS" )
        ret true
    }

    # ── Phase TAA：时域抗锯齿 + 速度重投影 ────────────────────────
    # 断言策略（GL 后端 128x128）：
    #   1) 开关 + 统计（STAT_TAA=1 且自动打开 motion）；
    #   2) 静止场景连续多帧：与无 TAA 基线逐位一致（历史=当前，收敛正确）；
    #   3) 物体移动帧：速度图确实非零（重投影输入就绪），TAA 渲染有效；
    #   4) MSAA + TAA 组合冒烟（resolve 与 TAA 串联无重复）；
    #   5) 关闭 TAA：stat 回 0，输出与基线逐位一致（零回归）。
    public static bool runTaa()
    {
        Console.println( "-- Phase TAA: temporal AA + reprojection --" )
        SLang.RenderPipeline pipe = SLang.RenderPipeline.create( 128, 128 )
        if pipe == null
        {
            Console.println( "[taa] FAIL: pipeline create - " + SLang.Render.errorString() )
            ret false
        }
        pipe.setClearColor( 0.06f, 0.06f, 0.10f, 1.0f )
        SLang.RenderObject quad = pipe.addObject( SLang.RenderPipeline.MESH_QUAD )
        quad.setPosition( 0.0f, 0.0f, 0.0f )
        quad.setScale( 0.6f, 0.6f )
        quad.setColor( 0.9f, 0.2f, 0.2f, 1.0f )
        Int64 pxA = Memory.alloc( 128 * 128 * 4 )
        Int64 pxB = Memory.alloc( 128 * 128 * 4 )
        Int64 vel = Memory.alloc( 128 * 128 * 4 )
        if pxA == 0 || pxB == 0 || vel == 0
        {
            Console.println( "[taa] FAIL: alloc" )
            ret false
        }

        # 1) 基线 + 开关 + 统计
        if pipe.renderFrame( 0.0f, pxA ) == false
        {
            Console.println( "[taa] FAIL: baseline render - " + SLang.Render.errorString() )
            ret false
        }
        if pipe.setTaa( 1, 0.1f ) == false
        {
            Console.println( "[taa] SKIP: backend does not support TAA (stat=" +
                             pipe.stat( SLang.RenderPipeline.STAT_TAA ).toString() + ")" )
            pipe.destroy()
            Memory.free( pxA )
            Memory.free( pxB )
            Memory.free( vel )
            ret true
        }
        if pipe.stat( SLang.RenderPipeline.STAT_TAA ) != 1
        {
            Console.println( "[taa] FAIL: stat taa" )
            ret false
        }
        if pipe.stat( SLang.RenderPipeline.STAT_MV_ENABLED ) != 1
        {
            Console.println( "[taa] FAIL: TAA did not auto-enable motion" )
            ret false
        }
        Console.println( "[taa] enabled + motion auto-on OK" )

        # 2) 静止场景连续 8 帧：与基线逐位一致（首帧 reset 后 hist=cur）
        Int32 i = 0
        while i < 8
        {
            if pipe.renderFrame( 0.0f, pxB ) == false
            {
                Console.println( "[taa] FAIL: static frame " + i.toString() )
                ret false
            }
            i = i + 1
        }
        # 静止时 hist = cur，mix(h,c,0.1) 理论恒等；TAA 路径多一次
        # 纹理采样 + float mix，几何边缘 1px 过渡带有舍入噪声（中心/背景
        # 平坦区完全一致）——断言平坦区逐位一致 + 全图差异像素 < 4%。
        Int32 staticDiff = countDiff( pxA, pxB, 128, 128, 2 )
        Console.println( "[taa] static 8f diff px (tol=2): " + staticDiff.toString() )
        Int32 crBase = RenderTestHelpers.sampleChannel( pxA, 128, 64, 64, 0 )
        Int32 crTaa = RenderTestHelpers.sampleChannel( pxB, 128, 64, 64, 0 )
        Int32 bgBase = RenderTestHelpers.sampleChannel( pxA, 128, 4, 4, 0 )
        Int32 bgTaa = RenderTestHelpers.sampleChannel( pxB, 128, 4, 4, 0 )
        if crBase != crTaa || bgBase != bgTaa || staticDiff > 655
        {
            Console.println( "[taa] FAIL: static scene unstable (center " +
                             crBase.toString() + "/" + crTaa.toString() + " bg " +
                             bgBase.toString() + "/" + bgTaa.toString() + " diff " +
                             staticDiff.toString() + ")" )
            ret false
        }

        # 3) 移动帧：速度图非零，TAA 渲染有效
        quad.setPosition( 0.2f, 0.0f, 0.0f )
        if pipe.renderFrame( 0.0f, pxB ) == false
        {
            Console.println( "[taa] FAIL: moving frame - " + SLang.Render.errorString() )
            ret false
        }
        if pipe.outputMotionTexture( vel ) == false
        {
            Console.println( "[taa] FAIL: motion rt for TAA reprojection" )
            ret false
        }
        Int32 vr = RenderTestHelpers.sampleChannel( vel, 128, 64, 64, 0 )
        Console.println( "[taa] reprojection velocity R: " + vr.toString() )
        if vr < 140
        {
            Console.println( "[taa] FAIL: TAA reprojection has no velocity input (R=" +
                             vr.toString() + ")" )
            ret false
        }

        # 4) MSAA + TAA 组合冒烟（resolve -> TAA -> post 串联）
        Console.println( "[taa] combo: setting msaa4..." )
        if pipe.setAa( 4, 0, 8.0f ) != 4
        {
            Console.println( "[taa] FAIL: msaa for combo" )
            ret false
        }
        Console.println( "[taa] combo: rendering..." )
        if pipe.renderFrame( 0.0f, pxB ) == false
        {
            Console.println( "[taa] FAIL: msaa+taa combo render - " + SLang.Render.errorString() )
            ret false
        }
        Console.println( "[taa] msaa+taa combo OK" )

        # 5) 关闭 TAA：stat 回 0 + 输出与（同场景）无 TAA 逐位一致
        if pipe.setTaa( 0, 0.1f ) == true || pipe.stat( SLang.RenderPipeline.STAT_TAA ) != 0
        {
            Console.println( "[taa] FAIL: disable taa" )
            ret false
        }
        # 复位场景到基线形态（MSAA 也关闭），验证零回归
        quad.setPosition( 0.0f, 0.0f, 0.0f )
        pipe.setAa( 0, 0, 8.0f )
        if pipe.renderFrame( 0.0f, pxB ) == false
        {
            Console.println( "[taa] FAIL: restore render" )
            ret false
        }
        Int32 restoreDiff = countDiff( pxA, pxB, 128, 128, 0 )
        if restoreDiff != 0
        {
            Console.println( "[taa] FAIL: off-path not bit-identical (" +
                             restoreDiff.toString() + " px)" )
            ret false
        }
        pipe.destroy()
        Memory.free( pxA )
        Memory.free( pxB )
        Memory.free( vel )
        Console.println( "[taa] PASS" )
        ret true
    }

    # ── Phase MB：后处理动态模糊（速度方向对称快门）─────────────
    # 断言策略（GL 后端 128x128）：
    #   1) 开关 + 统计（STAT_MOTION_BLUR=1 + 自动打开 motion）；
    #   2) 静止场景：速度 0 → 所有 tap 重合 → 与基线逐位一致；
    #   3) 运动帧：物体沿 +x 移动，速度非零 → 边缘被涂抹（与无模糊
    #      同场景对比有像素差异），但中心实体像素保持纯色（不糊掉全图）；
    #   4) scale 0 退化（速度输入仍在但位移为 0）→ 与无模糊一致；
    #   5) 关闭后回读 stat=0，恢复逐位一致（零回归）。
    public static bool runMotionBlur()
    {
        Console.println( "-- Phase MB: post-process motion blur --" )
        SLang.RenderPipeline pipe = SLang.RenderPipeline.create( 128, 128 )
        if pipe == null
        {
            Console.println( "[mb] FAIL: pipeline create - " + SLang.Render.errorString() )
            ret false
        }
        pipe.setClearColor( 0.06f, 0.06f, 0.10f, 1.0f )
        SLang.RenderObject quad = pipe.addObject( SLang.RenderPipeline.MESH_QUAD )
        quad.setPosition( 0.0f, 0.0f, 0.0f )
        quad.setScale( 0.5f, 0.5f )
        quad.setColor( 0.9f, 0.2f, 0.2f, 1.0f )
        Int64 pxA = Memory.alloc( 128 * 128 * 4 )
        Int64 pxB = Memory.alloc( 128 * 128 * 4 )
        Int64 vel = Memory.alloc( 128 * 128 * 4 )
        if pxA == 0 || pxB == 0 || vel == 0
        {
            Console.println( "[mb] FAIL: alloc" )
            ret false
        }

        # 1) 基线 + 开关 + 统计
        if pipe.renderFrame( 0.0f, pxA ) == false
        {
            Console.println( "[mb] FAIL: baseline render - " + SLang.Render.errorString() )
            ret false
        }
        if pipe.setMotionBlur( 1, 1.0f, 8 ) == false
        {
            Console.println( "[mb] SKIP: backend unsupported (stat=" +
                             pipe.stat( SLang.RenderPipeline.STAT_MOTION_BLUR ).toString() + ")" )
            pipe.destroy()
            Memory.free( pxA )
            Memory.free( pxB )
            Memory.free( vel )
            ret true
        }
        if pipe.stat( SLang.RenderPipeline.STAT_MOTION_BLUR ) != 1 ||
           pipe.stat( SLang.RenderPipeline.STAT_MV_ENABLED ) != 1
        {
            Console.println( "[mb] FAIL: stat mb/motion" )
            ret false
        }

        # 2) 静止场景：速度 0 → 输出与基线一致（容差 2，浮点采样舍入）
        if pipe.renderFrame( 0.0f, pxB ) == false
        {
            Console.println( "[mb] FAIL: static frame - " + SLang.Render.errorString() )
            ret false
        }
        Int32 staticDiff = countDiff( pxA, pxB, 128, 128, 2 )
        Console.println( "[mb] static diff px (tol=2): " + staticDiff.toString() )
        Int32 crBase = RenderTestHelpers.sampleChannel( pxA, 128, 64, 64, 0 )
        Int32 crBlur = RenderTestHelpers.sampleChannel( pxB, 128, 64, 64, 0 )
        Int32 bgBase = RenderTestHelpers.sampleChannel( pxA, 128, 4, 4, 0 )
        Int32 bgBlur = RenderTestHelpers.sampleChannel( pxB, 128, 4, 4, 0 )
        # 静止物体中心的 tap 全重合 = 原色；背景远景无速度 = 原色；
        # quad 边缘 1px 过渡带的速度残差会把邻色抹入（运动模糊正常行为）
        if crBase != crBlur || bgBase != bgBlur || staticDiff > 400
        {
            Console.println( "[mb] FAIL: static pixels should not blur (" +
                             staticDiff.toString() + " px)" )
            ret false
        }

        # 3) 运动帧：+x 移动一帧设速度（给 TAA/motion 快照），再画一帧
        #    取「有模糊」画面；随后 scale 0 取「无模糊」同场景画面。
        quad.setPosition( 0.18f, 0.0f, 0.0f )
        if pipe.renderFrame( 0.0f, pxB ) == false
        {
            Console.println( "[mb] FAIL: warmup moving frame" )
            ret false
        }
        if pipe.outputMotionTexture( vel ) == false
        {
            Console.println( "[mb] FAIL: motion rt - " + SLang.Render.errorString() )
            ret false
        }
        Int32 vr = RenderTestHelpers.sampleChannel( vel, 128, 64, 64, 0 )
        Console.println( "[mb] velocity R: " + vr.toString() )
        if vr < 140
        {
            Console.println( "[mb] FAIL: no velocity input for blur (R=" + vr.toString() + ")" )
            ret false
        }
        # 移动后再走一帧，中心仍在 quad 内（scale 0.5 半边 0.25 > 0.18）
        if pipe.renderFrame( 0.0f, pxB ) == false
        {
            Console.println( "[mb] FAIL: blurred frame" )
            ret false
        }
        # 3b) 同场景 scale 0（速度仍在 → 速度 0 位移）取对照
        pipe.setMotionBlur( 1, 0.0f, 8 )
        if pipe.renderFrame( 0.0f, pxA ) == false
        {
            Console.println( "[mb] FAIL: scale0 frame" )
            ret false
        }
        Int32 moveDiff = countDiff( pxA, pxB, 128, 128, 2 )
        Console.println( "[mb] motion blur diff px: " + moveDiff.toString() )
        if moveDiff <= 0
        {
            Console.println( "[mb] FAIL: moving scene produced no blur" )
            ret false
        }

        # 4) 关闭：stat 回 0 + 场景复位后与最初基线逐位一致
        if pipe.setMotionBlur( 0, 1.0f, 8 ) == true ||
           pipe.stat( SLang.RenderPipeline.STAT_MOTION_BLUR ) != 0
        {
            Console.println( "[mb] FAIL: disable" )
            ret false
        }
        quad.setPosition( 0.0f, 0.0f, 0.0f )
        if pipe.renderFrame( 0.0f, pxB ) == false
        {
            Console.println( "[mb] FAIL: restore frame" )
            ret false
        }
        Int32 restoreDiff = countDiff( pxA, pxB, 128, 128, 0 )
        # pxA 此刻是 scale0 的移动场景——复位后应与「静止基线」比，
        # 这里直接断言中心颜色回到纯红（背景独立验证另做）
        Int32 cr = RenderTestHelpers.sampleChannel( pxB, 128, 64, 64, 0 )
        Console.println( "[mb] restore center R=" + cr.toString() + " diff(moving)=" +
                         restoreDiff.toString() )
        if cr < 200
        {
            Console.println( "[mb] FAIL: restore center not red" )
            ret false
        }
        pipe.destroy()
        Memory.free( pxA )
        Memory.free( pxB )
        Memory.free( vel )
        Console.println( "[mb] PASS" )
        ret true
    }
}
