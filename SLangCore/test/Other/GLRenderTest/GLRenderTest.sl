import SLangQT;
import SLangRender;
import Math;
import Std;

# ============================================================================
# GLRenderTest —— SLangRender 离屏 GL 渲染 + SLangQT 窗口填充端到端
# ----------------------------------------------------------------------------
# Phase A 纯 GL（headless，无 QT 依赖）：
#   initialize -> RenderContext(256x256) -> renderFrame(红) ->
#   中心像素=红 / 角落=背景 采样断言 -> renderFrame(蓝) ->
#   中心像素=蓝（颜色变化验证） -> frameCount >= 2
# Phase B QT 窗口（需真实 Qt 后端；stub 后端 SKIP）：
#   QT 窗口 + QLabel -> QTimer 16ms 帧循环 -> renderFrame(RGB 随时间
#   正弦相位错开变化) -> QLabel.setPixmapRgba 填充（renderTexture 通道）
#   -> 2.5s 自动退出 -> 帧数统计断言（>= 60 渲染帧 + >= 60 次填充）
# 汇总判定：Phase A 必须 PASS；Phase B SKIP（stub）不算失败。
# ============================================================================
public class GLRenderTest
{
    static SLang.QApplication _app = null
    static SLang.QLabel _label = null
    static SLang.RenderContext _ctx = null
    static Int64 _pixels = 0
    static Int32 _texW = 256
    static Int32 _texH = 256

    static Float32 _t = 0.0f
    static Int32 _glFrames = 0
    static Int32 _pixOk = 0

    # 帧循环 tick：颜色随时间正弦变化（RGB 相位错开 120 度），
    # 渲染一帧并填充进 QT 窗口
    public static void onTick()
    {
        _t = _t + 0.13f
        Float32 r = 0.5f + 0.5f * Mathf.sin( _t )
        Float32 g = 0.5f + 0.5f * Mathf.sin( _t + 2.0944f )
        Float32 b = 0.5f + 0.5f * Mathf.sin( _t + 4.1888f )
        if _ctx.renderFrame( r, g, b, _pixels )
        {
            _glFrames = _glFrames + 1
            if _label.setPixmapRgba( _pixels, _texW, _texH )
            {
                _pixOk = _pixOk + 1
            }
        }
    }

    public static void onQuit()
    {
        if _app != null
        {
            _app.quit()
        }
    }

    public static void main()
    {
        Console.println( "========== GLRenderTest (SLangRender offscreen GL + QT window fill) ==========" )

        # ── Phase A: 纯 GL 离屏渲染（headless，不依赖 QT）──────────
        bool phaseA = runPureGL()

        # ── Phase B: QT 窗口填充（真实 Qt 后端；stub SKIP）──────────
        Int32 phaseB = runQtWindow()

        # ── 汇总 ────────────────────────────────────────────────────
        string bText = "FAIL"
        if phaseB == 2
        {
            bText = "PASS"
        }
        elif phaseB == 1
        {
            bText = "SKIP"
        }
        Console.println( "========== GLRenderTest summary ==========" )
        Console.println( "phase A (pure GL)   : " + ( phaseA ? "PASS" : "FAIL" ) )
        Console.println( "phase B (QT window) : " + bText )
        if phaseA && phaseB != 0
        {
            Console.println( "GLRenderTest: PASS" )
        }
        else
        {
            Console.println( "GLRenderTest: FAIL" )
        }
    }

    # 采样像素通道：pixels 块内 (x,y) 像素的 c 通道（0=R 1=G 2=B 3=A）
    static Int32 sampleChannel( Int64 pixels, Int32 w, Int32 x, Int32 y, Int32 c )
    {
        Int32 off = ( y * w + x ) * 4 + c
        ret Memory.readUInt8( pixels, off )
    }

    static bool runPureGL()
    {
        Console.println( "-- Phase A: pure offscreen GL (256x256 RGBA8) --" )

        if SLang.Render.initialize() == false
        {
            Console.println( "[GL] FAIL: initialize - " + SLang.Render.errorString() )
            ret false
        }
        Console.println( "[GL] renderer: " + SLang.Render.rendererInfo() )
        Console.println( "[GL] version : " + SLang.Render.versionInfo() )

        SLang.RenderContext ctx = SLang.RenderContext.create( 256, 256 )
        if ctx == null
        {
            Console.println( "[GL] FAIL: context create - " + SLang.Render.errorString() )
            ret false
        }
        _ctx = ctx
        _pixels = Memory.alloc( 256 * 256 * 4 )
        if _pixels == 0
        {
            Console.println( "[GL] FAIL: pixel buffer alloc" )
            ctx.destroy()
            ret false
        }

        # 帧 1：红色三角形 —— 中心像素应为纯红，角落应为背景色
        if ctx.renderFrame( 1.0f, 0.0f, 0.0f, _pixels ) == false
        {
            Console.println( "[GL] FAIL: renderFrame red - " + SLang.Render.errorString() )
            ret false
        }
        Int32 cr = sampleChannel( _pixels, 256, 128, 128, 0 )
        Int32 cg = sampleChannel( _pixels, 256, 128, 128, 1 )
        Int32 cb = sampleChannel( _pixels, 256, 128, 128, 2 )
        Console.println( "[GL] red frame center  RGB=(" + cr.toString() + "," + cg.toString() + "," + cb.toString() + ")" )
        if cr < 250 || cg > 5 || cb > 5
        {
            Console.println( "[GL] FAIL: center should be red" )
            ret false
        }

        # 背景固定 (0.06,0.06,0.10) -> (15,15,25)，容差 ±5
        Int32 kr = sampleChannel( _pixels, 256, 4, 4, 0 )
        Int32 kg = sampleChannel( _pixels, 256, 4, 4, 1 )
        Int32 kb = sampleChannel( _pixels, 256, 4, 4, 2 )
        Console.println( "[GL] red frame corner  RGB=(" + kr.toString() + "," + kg.toString() + "," + kb.toString() + ")" )
        if kr < 10 || kr > 20 || kb < 20 || kb > 30
        {
            Console.println( "[GL] FAIL: corner should be background" )
            ret false
        }

        # 帧 2：蓝色三角形 —— 中心像素应变为纯蓝（颜色变化验证）
        if ctx.renderFrame( 0.0f, 0.0f, 1.0f, _pixels ) == false
        {
            Console.println( "[GL] FAIL: renderFrame blue - " + SLang.Render.errorString() )
            ret false
        }
        Int32 br = sampleChannel( _pixels, 256, 128, 128, 0 )
        Int32 bg = sampleChannel( _pixels, 256, 128, 128, 1 )
        Int32 bb = sampleChannel( _pixels, 256, 128, 128, 2 )
        Console.println( "[GL] blue frame center RGB=(" + br.toString() + "," + bg.toString() + "," + bb.toString() + ")" )
        if br > 5 || bb < 250
        {
            Console.println( "[GL] FAIL: center should be blue (color shift broken)" )
            ret false
        }

        Int64 frames = ctx.frameCount()
        Console.println( "[GL] frameCount=" + frames.toString() )
        if frames < 2
        {
            Console.println( "[GL] FAIL: frame count" )
            ret false
        }

        Console.println( "[GL] Phase A: PASS (triangle rendered, color shifted, pixels read back)" )
        ret true
    }

    # 返回：2 = PASS，1 = SKIP（stub 后端 / GL 未就绪），0 = FAIL
    static Int32 runQtWindow()
    {
        string kind = SLang.QT.backendKind()
        if kind != "qt"
        {
            Console.println( "-- Phase B: skipped (backend=" + kind + "; build+deploy the Qt backend to enable) --" )
            ret 1
        }
        if _ctx == null || _pixels == 0
        {
            Console.println( "-- Phase B: skipped (Phase A did not init GL) --" )
            ret 1
        }

        Console.println( "-- Phase B: QT window fill (QTimer 16ms frame loop, color-shifting triangle) --" )

        _app = SLang.QT.newApp()
        SLang.QWidget host = SLang.QT.newWidget( 0 )
        host.setTitle( "SLangRender -> QT (color-shifting triangle)" )
        host.resize( 296, 316 )
        _label = SLang.QT.newLabel( host.handle, "" )
        _label.setGeometry( 10, 10, 276, 296 )
        host.show()

        # 5s 自动退出（真实窗口模式下用户可看到颜色渐变三角形动画）
        SLang.QTimer quitT = SLang.QT.newTimer( 5000, true, GLRenderTest.onQuit )
        SLang.QTimer animT = SLang.QT.newTimer( 16, false, GLRenderTest.onTick )
        _app.exec()

        Console.println( "[QT] glFrames=" + _glFrames.toString() + " pixOk=" + _pixOk.toString() )

        animT.delete()
        quitT.delete()
        host.delete()

        if _glFrames < 60 || _pixOk < 60
        {
            Console.println( "[QT] FAIL: frame loop too slow (need >= 60 rendered + 60 filled)" )
            ret 0
        }
        Console.println( "[QT] Phase B: PASS (renderTexture filled into QT window each frame)" )
        ret 2
    }
}
