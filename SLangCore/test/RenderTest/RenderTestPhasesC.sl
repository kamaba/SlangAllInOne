import SLangRender;
import SLangAudio;
import Math;
import Std;

# 命令缓冲 / GPU 实例化 phase 分组（2026-11-18：PASS 相位随 SRP 草稿链
# 移除，仅保留独立于草稿的 CommandBuffer 与实例化验证）：
#   runCommandBuffer  Phase CB   真录制（录制 -> 整理 -> 提交渲染）
#   runInstancing     Phase INST N1 GPU 实例化合批（64 实例 1 draw vs 64 draw 像素一致）
public class RenderTestPhasesC
{

    # ── Phase CB：CommandBuffer 真录制（录制 → 整理 → 提交渲染）──
    # Unity 式三段式端到端验收（doc/04 §3.6 SLMC 命令流全链路）：
    #   1 录制：cb.begin() 后零后端调用，仅参数组织与顺序记账 ——
    #     setRenderTargets / setTexture / setPerDraw / drawItem /
    #     postProcess / blitFinal / readback，共 11 条命令；
    #   2 整理：cb.sortDrawItems() 对 DrawItem 段排序（drawItem 乱序
    #     录入：蓝 z0.3 -> 贴图 z0.5 -> 三角 z0.0；正确序 = 三角
    #     (queue2000 不透明先画) -> 贴图(z0.5 远) -> 蓝(z0.3 近)，
    #     透明 z 降序远->近保混合）；
    #   3 提交渲染：pipe.executeCommandBuffer(cb) 按 SLMC 布局打包
    #     整包提交，C 侧逐 opcode 回放（命令流走 RHI vtable ->
    #     GL/D3D11/VK/GLES 四后端同效果，Phase D/E/F 各复检一次）。
    # 场景（自建自毁 256x256 管线，不触碰 RenderTest._pipe/RenderTest._pixels）：
    #   perdraw 槽 0 红三角（不透明 queue2000）；槽 1 白贴图 quad
    #   (中心 0.45,0.35 scale0.55, 透明 z0.5, 64x64 渐变贴图)；槽 2
    #   蓝 quad（中心 0.55,0.35 scale0.25, 透明 z0.3, 与贴图 quad
    #   重叠 —— 重叠点是排序方向验证点：正确序蓝后画 -> 蓝分量高）。
    public static bool runCommandBuffer()
    {
        Console.println( "-- Phase CB: CommandBuffer record -> sort -> execute (SLMC stream, 256x256) --" )
        # 2026-11-13 修复：原误写 1280x720 —— readback/blit 按管线 w/h 回写，
        # 1280x720 会写爆 256x256 的 pixels 缓冲（堆越界、黑角、异常退出码）。
        # 与本阶段 256x256 采样断言/64x64 贴图一致。
        SLang.RenderPipeline pipe = SLang.RenderPipeline.create( 256, 256 )
        if pipe == null
        {
            Console.println( "[cb] FAIL: pipeline create - " + SLang.Render.errorString() )
            ret false
        }
        Int64 pixels = Memory.alloc( 256 * 256 * 4 )
        if pixels == 0
        {
            Console.println( "[cb] FAIL: pixel alloc" )
            pipe.destroy()
            ret false
        }
        Int64 texPtr = RenderTestHelpers.makeGradientTexture()
        if texPtr == 0
        {
            Console.println( "[cb] FAIL: texture pixels alloc" )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }
        SLang.RenderTexture tex = SLang.RenderTexture.createRgba( texPtr, 64, 64 )
        if tex == null
        {
            Console.println( "[cb] FAIL: texture upload - " + SLang.Render.errorString() )
            Memory.free( texPtr )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }

        # MVP（ortho(-1,1,-1,1) 投影≈单位阵 -> MVP≈model2d）
        # 2026-11-13 修复：Float32_4x4 为列向量约定（Math 模块 translation
        # 工厂/toFloat32_3x3 实证：平移在末列 m03/m13），pushMat 写 std140
        # 列主序 [col*4+row]=M[row][col] 与 GLSL uMVP*v 匹配。原矩阵把
        # 平移写在底行（m30/m31）-> GLSL 收到转置矩阵（无平移 + w 被污染）
        # -> quad 几何畸变，采样点全落 quad 外。平移移到每行第 4 参：
        # m03=tx m13=ty。
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

        # ── 1 录制：11 条命令，drawItem 故意乱序（蓝 z0.3 -> 贴图
        #    z0.5 -> 三角 z0.0），排序必须重排为正确绘制序 ──────────
        CommandBuffer cb = CommandBuffer()
        cb.name = "cb-main"
        cb.begin()
        cb.setRenderTargets( SLang.RenderPipeline.TARGET_SCENE, 0, 0, 256, 256,
                             3, Color( 0.06f, 0.06f, 0.10f, 1.0f ) )
        cb.setTexture( 0, tex.handle )
        cb.setPerDraw( 0, triMvp, Color( 1.0f, 0.0f, 0.0f, 1.0f ) )
        cb.setPerDraw( 1, texMvp, Color( 1.0f, 1.0f, 1.0f, 0.85f ) )
        cb.setPerDraw( 2, blueMvp, Color( 0.3f, 0.4f, 1.0f, 0.5f ) )
        cb.drawItem( SLang.RenderPipeline.PROG_PFLAT, 2, SLang.RenderPipeline.MESH_QUAD, 0, 1, 3000, 0.3f )
        cb.drawItem( SLang.RenderPipeline.PROG_PTEX, 1, SLang.RenderPipeline.MESH_QUAD, 0, 1, 3000, 0.5f )
        cb.drawItem( SLang.RenderPipeline.PROG_PFLAT, 0, SLang.RenderPipeline.MESH_TRIANGLE, 0, 0, 2000, 0.0f )
        cb.postProcess( 0, 1.0f, 1.0f, 1.0f )
        cb.blitFinal()
        cb.readback( pixels )
        cb.end()
        Console.println( "[cb] recorded " + cb.commandCount.toString() + " commands (overflow=" + cb.overflowCount.toString() + ")" )
        if cb.commandCount != 11 || cb.overflowCount != 0
        {
            Console.println( "[cb] FAIL: commandCount expect 11, overflow expect 0" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }

        # ── 2 整理：DrawItem 段排序（3 项；透明远->近）──────────────
        Int32 sorted = cb.sortDrawItems()
        Console.println( "[cb] sortDrawItems -> " + sorted.toString() + " draw items sorted" )
        if sorted != 3
        {
            Console.println( "[cb] FAIL: sortDrawItems expect 3" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }

        # ── 3 提交渲染：SLMC 打包整包提交，C 侧逐 opcode 回放 ───────
        if !pipe.executeCommandBuffer( cb )
        {
            Console.println( "[cb] FAIL: executeCommandBuffer - " + SLang.Render.errorString() )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }

        # 统计断言：3 DrawItem + PostProcess + Blit 各计一次 draw call
        Int32 statDraws = pipe.stat( SLang.RenderPipeline.STAT_DRAW_CALLS )
        Int32 statOpaque = pipe.stat( SLang.RenderPipeline.STAT_OPAQUE_DRAWS )
        Int32 statTransp = pipe.stat( SLang.RenderPipeline.STAT_TRANSPARENT_DRAWS )
        Console.println( "[cb] stats: draws=" + statDraws.toString() + " opaque=" + statOpaque.toString() + " transp=" + statTransp.toString() )
        if statDraws != 5 || statOpaque != 1 || statTransp != 2
        {
            Console.println( "[cb] FAIL: stats expect draws=5 opaque=1 transp=2" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }

        # 像素断言（回读 top-left 坐标，与 A2 同源采样/阈值）
        # 背景（左上角，远离三角与 quad）
        Int32 kr = RenderTestHelpers.sampleChannel( pixels, 256, 4, 4, 0 )
        Int32 kg = RenderTestHelpers.sampleChannel( pixels, 256, 4, 4, 1 )
        Int32 kb = RenderTestHelpers.sampleChannel( pixels, 256, 4, 4, 2 )
        Console.println( "[cb] corner  RGB=(" + kr.toString() + "," + kg.toString() + "," + kb.toString() + ")" )
        if kr < 9 || kr > 21 || kg < 9 || kg > 21 || kb < 19 || kb > 33
        {
            Console.println( "[cb] FAIL: corner should be clear color" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }
        # 三角内部（左下区域，不受 quad 影响）
        Int32 triR = RenderTestHelpers.sampleChannel( pixels, 256, 51, 184, 0 )
        Int32 triG = RenderTestHelpers.sampleChannel( pixels, 256, 51, 184, 1 )
        Int32 triB = RenderTestHelpers.sampleChannel( pixels, 256, 51, 184, 2 )
        Console.println( "[cb] tri     RGB=(" + triR.toString() + "," + triG.toString() + "," + triB.toString() + ")" )
        if triR < 240 || triG > 15 || triB > 15
        {
            Console.println( "[cb] FAIL: triangle should be red" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }
        # 贴图独占点（quad 右下带：NDC(0.70,0.15) 在贴图 quad
        # [0.175..0.725]x[0.075..0.625] 内、蓝 quad 与三角外；
        # u≈0.955 -> 期望 RGB≈(181,42,154)）
        Int32 qr = RenderTestHelpers.sampleChannel( pixels, 256, 217, 108, 0 )
        Int32 qg = RenderTestHelpers.sampleChannel( pixels, 256, 217, 108, 1 )
        Int32 qb = RenderTestHelpers.sampleChannel( pixels, 256, 217, 108, 2 )
        Console.println( "[cb] quadtex RGB=(" + qr.toString() + "," + qg.toString() + "," + qb.toString() + ")" )
        if qr < 110 || qb < 110 || qg < 35 || qg > 90
        {
            Console.println( "[cb] FAIL: textured quad pixel missing" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }
        # 重叠点（两 quad 交叠区：NDC(0.55,0.40) 同在贴图 quad
        # [0.175..0.725]x[0.075..0.625] 与蓝 quad [0.425..0.675]x[0.225..0.475]
        # 内、三角外；正确序 = 贴图(z0.5 远)先画 -> 蓝(z0.3 近)后画 ->
        # 蓝分量主导，期望 RGB≈(103,91,192)；错误序蓝先画被贴图盖 -> b≈130 判别失败）
        Int32 br = RenderTestHelpers.sampleChannel( pixels, 256, 198, 76, 0 )
        Int32 bg = RenderTestHelpers.sampleChannel( pixels, 256, 198, 76, 1 )
        Int32 bb = RenderTestHelpers.sampleChannel( pixels, 256, 198, 76, 2 )
        Console.println( "[cb] overlap RGB=(" + br.toString() + "," + bg.toString() + "," + bb.toString() + ")" )
        if bb < 150 || ( bb - br ) < 40
        {
            Console.println( "[cb] FAIL: overlap should be blue-dominant (sort direction wrong)" )
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
        Console.println( "[cb] Phase CB: PASS (record 11 -> sort 3 -> execute: pixels + stats + overlap all ok)" )
        ret true
    }

    # ── Phase INST：GPU 实例化合批（N1：64 实例一次 draw）────────
    # 验收（AIPrompt.md N1）：同 mesh + 同材质的 64 对象合一次真 GPU
    # instanced draw —— drawCalls 不随对象数线性涨；合批与逐 draw 像素一致。
    #   场景 A（合批）：64×setPerDraw 先行 + 连续 64×drawItem（槽 0..63
    #     递增、prog/mesh/texDesc 同、不透明）-> C 侧回放 RLE 合并为
    #     1 次 instanced draw（baseSlot=0、instanceCount=64）；
    #   场景 B（对照）：setPerDraw/drawItem 交替 64 次（SetPerDraw 命令
    #     打断 RLE 连续性）-> 64 次独立 draw；
    #   统计断言：A draws=3（1 合并+post+blit）/opaque=1/instances=64；
    #     B draws=66/opaque=64/instances=64；
    #   像素断言（双保险）：A 帧 64 槽中心 = 槽差异化纯色（PFLAT 无灯光
    #     ambient=1 输出 = uColor[obj]，实例索引错位立即可见）+ A/B 全帧
    #     262144 字节逐点一致（合批与逐 draw 数值等价）。
    #   几何：8x8 网格 quad，scale 0.105（格宽 0.25 不重叠），
    #     tx=-0.875+col*0.25 / ty=0.875-row*0.25，slot=row*8+col，
    #     槽中心屏幕坐标 (16+col*32, 16+row*32)。

    # INST 辅助：槽 s 的网格 MVP（列主序平移在 m03/m13）


    # ── Phase INST：GPU 实例化合批（N1：64 实例一次 draw）────────
    # 验收（AIPrompt.md N1）：同 mesh + 同材质的 64 对象合一次真 GPU
    # instanced draw —— drawCalls 不随对象数线性涨；合批与逐 draw 像素一致。
    #   场景 A（合批）：64×setPerDraw 先行 + 连续 64×drawItem（槽 0..63
    #     递增、prog/mesh/texDesc 同、不透明）-> C 侧回放 RLE 合并为
    #     1 次 instanced draw（baseSlot=0、instanceCount=64）；
    #   场景 B（对照）：setPerDraw/drawItem 交替 64 次（SetPerDraw 命令
    #     打断 RLE 连续性）-> 64 次独立 draw；
    #   统计断言：A draws=3（1 合并+post+blit）/opaque=1/instances=64；
    #     B draws=66/opaque=64/instances=64；
    #   像素断言（双保险）：A 帧 64 槽中心 = 槽差异化纯色（PFLAT 无灯光
    #     ambient=1 输出 = uColor[obj]，实例索引错位立即可见）+ A/B 全帧
    #     262144 字节逐点一致（合批与逐 draw 数值等价）。
    #   几何：8x8 网格 quad，scale 0.105（格宽 0.25 不重叠），
    #     tx=-0.875+col*0.25 / ty=0.875-row*0.25，slot=row*8+col，
    #     槽中心屏幕坐标 (16+col*32, 16+row*32)。

    # INST 辅助：槽 s 的网格 MVP（列主序平移在 m03/m13）
    public static Float32_4x4 instSlotMvp( Int32 s )
    {
        Int32 col = s % 8
        Int32 row = s / 8
        Float32 tx = col.toFloat32() * 0.25f - 0.875f
        Float32 ty = 0.875f - row.toFloat32() * 0.25f
        ret Float32_4x4( 0.105f, 0.0f, 0.0f, tx,
                         0.0f, 0.105f, 0.0f, ty,
                         0.0f, 0.0f, 1.0f, 0.0f,
                         0.0f, 0.0f, 0.0f, 1.0f )
    }

    # INST 辅助：槽 s 的差异化颜色（r/g 按列/行、b 按槽号渐变）


    # INST 辅助：槽 s 的差异化颜色（r/g 按列/行、b 按槽号渐变）
    public static Color instSlotColor( Int32 s )
    {
        Int32 col = s % 8
        Int32 row = s / 8
        ret Color( ( col.toFloat32() + 0.5f ) / 8.0f,
                   ( row.toFloat32() + 0.5f ) / 8.0f,
                   0.25f + s.toFloat32() / 128.0f,
                   1.0f )
    }



    public static bool runInstancing()
    {
        Console.println( "-- Phase INST: GPU instancing (64 instances / 1 draw vs 64 draws, 256x256) --" )
        SLang.RenderPipeline pipe = SLang.RenderPipeline.create( 256, 256 )
        if pipe == null
        {
            Console.println( "[inst] FAIL: pipeline create - " + SLang.Render.errorString() )
            ret false
        }
        Int64 pixelsA = Memory.alloc( 256 * 256 * 4 )
        Int64 pixelsB = Memory.alloc( 256 * 256 * 4 )
        if pixelsA == 0 || pixelsB == 0
        {
            Console.println( "[inst] FAIL: pixel alloc" )
            if pixelsA != 0
            {
                Memory.free( pixelsA )
            }
            if pixelsB != 0
            {
                Memory.free( pixelsB )
            }
            pipe.destroy()
            ret false
        }

        # ── 场景 A：64×setPerDraw 先行 + 连续 64×drawItem（RLE 合 1 draw）──
        CommandBuffer cbA = CommandBuffer()
        cbA.name = "cb-inst-a"
        cbA.begin()
        cbA.setRenderTargets( SLang.RenderPipeline.TARGET_SCENE, 0, 0, 256, 256, 3, Color( 0.0f, 0.0f, 0.0f, 1.0f ) )
        int s = 0
        while ( s < 64 )
        {
            cbA.setPerDraw( s, instSlotMvp( s ), instSlotColor( s ) )
            s = s + 1
        }
        s = 0
        while ( s < 64 )
        {
            cbA.drawItem( SLang.RenderPipeline.PROG_PFLAT, s, SLang.RenderPipeline.MESH_QUAD, 0, 0, 2000, 0.0f )
            s = s + 1
        }
        cbA.postProcess( 0, 1.0f, 1.0f, 1.0f )
        cbA.blitFinal()
        cbA.readback( pixelsA )
        cbA.end()
        if cbA.commandCount != 132 || cbA.overflowCount > 0
        {
            Console.println( "[inst] FAIL: stream A count=" + cbA.commandCount.toString() )
            Memory.free( pixelsA )
            Memory.free( pixelsB )
            pipe.destroy()
            ret false
        }
        if pipe.executeCommandBuffer( cbA ) == false
        {
            Console.println( "[inst] FAIL: execute A - " + SLang.Render.errorString() )
            Memory.free( pixelsA )
            Memory.free( pixelsB )
            pipe.destroy()
            ret false
        }
        Int32 drawsA = pipe.stat( SLang.RenderPipeline.STAT_DRAW_CALLS )
        Int32 opaqueA = pipe.stat( SLang.RenderPipeline.STAT_OPAQUE_DRAWS )
        Int32 instA = pipe.stat( SLang.RenderPipeline.STAT_INSTANCE_COUNT )
        Console.println( "[inst] A draws=" + drawsA.toString() + " opaque=" + opaqueA.toString() + " instances=" + instA.toString() )
        if drawsA != 3 || opaqueA != 1 || instA != 64
        {
            Console.println( "[inst] FAIL: A expect draws=3 opaque=1 instances=64 (RLE merge broken)" )
            Memory.free( pixelsA )
            Memory.free( pixelsB )
            pipe.destroy()
            ret false
        }

        # ── 场景 B：setPerDraw/drawItem 交替（打断 RLE -> 64 独立 draw）──
        CommandBuffer cbB = CommandBuffer()
        cbB.name = "cb-inst-b"
        cbB.begin()
        cbB.setRenderTargets( SLang.RenderPipeline.TARGET_SCENE, 0, 0, 256, 256, 3, Color( 0.0f, 0.0f, 0.0f, 1.0f ) )
        s = 0
        while ( s < 64 )
        {
            cbB.setPerDraw( s, instSlotMvp( s ), instSlotColor( s ) )
            cbB.drawItem( SLang.RenderPipeline.PROG_PFLAT, s, SLang.RenderPipeline.MESH_QUAD, 0, 0, 2000, 0.0f )
            s = s + 1
        }
        cbB.postProcess( 0, 1.0f, 1.0f, 1.0f )
        cbB.blitFinal()
        cbB.readback( pixelsB )
        cbB.end()
        if cbB.commandCount != 132 || cbB.overflowCount > 0
        {
            Console.println( "[inst] FAIL: stream B count=" + cbB.commandCount.toString() )
            Memory.free( pixelsA )
            Memory.free( pixelsB )
            pipe.destroy()
            ret false
        }
        if pipe.executeCommandBuffer( cbB ) == false
        {
            Console.println( "[inst] FAIL: execute B - " + SLang.Render.errorString() )
            Memory.free( pixelsA )
            Memory.free( pixelsB )
            pipe.destroy()
            ret false
        }
        Int32 drawsB = pipe.stat( SLang.RenderPipeline.STAT_DRAW_CALLS )
        Int32 opaqueB = pipe.stat( SLang.RenderPipeline.STAT_OPAQUE_DRAWS )
        Int32 instB = pipe.stat( SLang.RenderPipeline.STAT_INSTANCE_COUNT )
        Console.println( "[inst] B draws=" + drawsB.toString() + " opaque=" + opaqueB.toString() + " instances=" + instB.toString() )
        if drawsB != 66 || opaqueB != 64 || instB != 64
        {
            Console.println( "[inst] FAIL: B expect draws=66 opaque=64 instances=64" )
            Memory.free( pixelsA )
            Memory.free( pixelsB )
            pipe.destroy()
            ret false
        }

        # ── 像素断言 1：A 帧 64 槽中心 = 槽差异化纯色（容差 ±3）────
        s = 0
        Int32 badSlots = 0
        while ( s < 64 )
        {
            Int32 col = s % 8
            Int32 row = s / 8
            Int32 px = 16 + col * 32
            Int32 py = 16 + row * 32
            Int32 er = int( ( col.toFloat32() + 0.5f ) / 8.0f * 255.0f + 0.5f )
            Int32 eg = int( ( row.toFloat32() + 0.5f ) / 8.0f * 255.0f + 0.5f )
            Int32 eb = int( ( 0.25f + s.toFloat32() / 128.0f ) * 255.0f + 0.5f )
            Int32 pr = RenderTestHelpers.sampleChannel( pixelsA, 256, px, py, 0 )
            Int32 pg = RenderTestHelpers.sampleChannel( pixelsA, 256, px, py, 1 )
            Int32 pb = RenderTestHelpers.sampleChannel( pixelsA, 256, px, py, 2 )
            if pr < er - 3 || pr > er + 3 || pg < eg - 3 || pg > eg + 3 || pb < eb - 3 || pb > eb + 3
            {
                if badSlots < 4
                {
                    Console.println( "[inst] FAIL: slot " + s.toString() + " (" + px.toString() + "," + py.toString() + ") got (" + pr.toString() + "," + pg.toString() + "," + pb.toString() + ") expect (" + er.toString() + "," + eg.toString() + "," + eb.toString() + ")" )
                }
                badSlots = badSlots + 1
            }
            s = s + 1
        }
        if badSlots > 0
        {
            Console.println( "[inst] FAIL: " + badSlots.toString() + " slot centers mismatch (instance slot routing broken)" )
            Memory.free( pixelsA )
            Memory.free( pixelsB )
            pipe.destroy()
            ret false
        }
        Int32 r0 = RenderTestHelpers.sampleChannel( pixelsA, 256, 16, 16, 0 )
        Int32 g0 = RenderTestHelpers.sampleChannel( pixelsA, 256, 16, 16, 1 )
        Int32 b0 = RenderTestHelpers.sampleChannel( pixelsA, 256, 16, 16, 2 )
        Int32 r63 = RenderTestHelpers.sampleChannel( pixelsA, 256, 240, 240, 0 )
        Int32 g63 = RenderTestHelpers.sampleChannel( pixelsA, 256, 240, 240, 1 )
        Int32 b63 = RenderTestHelpers.sampleChannel( pixelsA, 256, 240, 240, 2 )
        Console.println( "[inst] slot0  RGB=(" + r0.toString() + "," + g0.toString() + "," + b0.toString() + ")  slot63 RGB=(" + r63.toString() + "," + g63.toString() + "," + b63.toString() + ")" )

        # ── 像素断言 2：A/B 全帧 262144 字节逐点一致（合批 = 逐 draw）──
        Int32 off = 0
        Int32 mism = 0
        while ( off < 262144 )
        {
            if Memory.readUInt8( pixelsA, off ) != Memory.readUInt8( pixelsB, off )
            {
                if mism < 4
                {
                    Console.println( "[inst] FAIL: byte " + off.toString() + " A=" + Memory.readUInt8( pixelsA, off ).toString() + " B=" + Memory.readUInt8( pixelsB, off ).toString() )
                }
                mism = mism + 1
            }
            off = off + 1
        }
        if mism > 0
        {
            Console.println( "[inst] FAIL: " + mism.toString() + " bytes differ between batched and per-draw" )
            Memory.free( pixelsA )
            Memory.free( pixelsB )
            pipe.destroy()
            ret false
        }
        Console.println( "[inst] A/B full-frame compare: 262144 bytes identical" )

        Memory.free( pixelsA )
        Memory.free( pixelsB )
        pipe.destroy()
        Console.println( "[inst] Phase INST: PASS (64 instances -> 1 instanced draw, pixel-identical to 64 draws)" )
        ret true
    }
}
