import SLangQT;
import Core;
import Std;
import Math;

# ============================================================================
# GUIDemo —— samples\GUI 三个历史示例的 SLQT（SLangQT）复刻（2026-11-06）
# ----------------------------------------------------------------------------
# 历史示例（早期 Tkinter 风格宿主 Canvas / Button / Behaviour，随宿主迁移已
# 移除，仅存语法参考）与本文的对应关系：
#   Canvas绘图.sl        -> buildChordSvg()   400x400：椭圆上 15 点两两连线（弦艺术）
#   Canvas绘图_套圆.sl    -> buildRingSvg()    800x600：以 (310,250) 为心 26 个渐宽同心圆
#   FrameUI.sl           -> "您好" 按钮行      Button("您好") + clicked 信号绑定
#
# SLQT 未绑定 QPainter 画布，绘图走 QSvgWidget（Qt6Svg）通道：SLang 侧生成
# SVG 字符串（旧宿主 createOval -> <ellipse>/<circle>、createLine -> <line>），
# loadData() 交给 Qt 渲染 —— 与旧 Canvas 等价的显示路径。
#
# 对原示例两处历史笔误的修正（原文件头已注明其不可编译）：
#   1) rads = angle * Pi 应为度转弧度 angle * Pi / 180（原式 15 点将重合于一点）；
#   2) raidus / raidous 拼写统一为 radius。
# 同心圆的 k += j、j += 0.3 用整数十分位双累加器精确复刻（1.0, 2.0, 3.3 ...），
# 规避浮点累积误差；弦艺术点坐标按原例 toInt() 取整（SystemConvertInt32）。
#
# 环境要点（2026-11-06 实测）：信号绑定链（createCallback/connect 的原生 AV）
# 对 C VM 与 lib\*.slb 的批次一致性强敏感 —— 混批（VM 11-03 + Core slb 11-05）
# 必崩；scripts\build-packages.ps1 重建 win32-debug 包后一切正常（本示例经
# backend=qt 真实窗口 + clicked 信号实测通过）。另注意：slang compile 的
# StageReferencedModules 会从 out\export\SLangQT\ 取 slang_qt.dll 铺进包槽，
# 若该处是 STUB 产物则运行静默降级 backend=stub（假绿），真实运行前需确保
# out\export\SLangQT\slang_qt.dll 为 Qt 后端或 re-deploy（deploy-qt.ps1）。
# ============================================================================

public class GUIDemo
{
    # ── FrameUI.sl：Button("您好") 的 clicked 信号处理器 ──────────────────
    # 硬约定：信号 handler 传全限定引用（GUIDemo.onHello），此处为被引用方。
    public static void onHello()
    {
        Console.println( "[FrameUI] Button( 您好 ) clicked" )
        SLang.QT.ffi_messageboxInfo( 0, "FrameUI", "您好！—— 来自 SLangQT 复刻的 FrameUI 示例" )
    }

    # ── Canvas绘图.sl：15 点两两连线（弦艺术）的 SVG ──────────────────────
    # 等价旧代码：createOval(外框椭圆) + 双重循环 createLine(点对连线)
    static string buildChordSvg()
    {
        Float32 aspect = 0.85f
        int MAXPTS = 15
        Float32 radius = ( 400.0f - 30.0f ) / ( aspect * 2.0f ) - 20.0f
        Float32 step = 360.0f / 15.0f
        Float32 angle = 0.0f

        # 点表：cos/sin 取自 Math 模块 Mathf（FFI math_lib 真实实现），坐标取整
        List<string> xs = List<string>()
        List<string> ys = List<string>()
        int i = 0
        while ( i < MAXPTS )
        {
            Float32 rads = angle * Mathf.Pi / 180.0f
            Int32 px = int( 200.0f + Mathf.cos( rads ) * radius )
            Int32 py = int( 200.0f - Mathf.sin( rads ) * radius * aspect )
            xs.add( px.toString() )
            ys.add( py.toString() )
            angle = angle + step
            i = i + 1
        }

        string svg = "<svg xmlns='http://www.w3.org/2000/svg' width='400' height='400'>"
        svg = svg + "<rect width='400' height='400' fill='white'/>"

        # 外框椭圆（旧例 createOval(xc-r, yc-r, xc+r, yc+r)，纵向压缩 aspect）
        Int32 rx = int( radius )
        Int32 ry = int( radius * aspect )
        svg = svg + "<ellipse cx='200' cy='200' rx='" + rx.toString() + "' ry='" + ry.toString() + "' fill='none' stroke='black'/>"

        # 两两连线：C(15,2) = 105 条（旧例双重循环 j 从 i 起，零长线略去）
        i = 0
        while ( i < MAXPTS )
        {
            int j = i + 1
            while ( j < MAXPTS )
            {
                svg = svg + "<line x1='" + xs[i] + "' y1='" + ys[i] + "' x2='" + xs[j] + "' y2='" + ys[j] + "' stroke='black'/>"
                j = j + 1
            }
            i = i + 1
        }
        svg = svg + "</svg>"
        ret svg
    }

    # ── Canvas绘图_套圆.sl：26 个渐宽同心圆的 SVG ──────────────────────────
    # 等价旧代码：k=1, j=1；createOval(310-k, 250-k, 310+k, 250+k)；k+=j，j+=0.3
    # 半径 k 的整数十分位双累加器（kWhole.kTenth / jWhole.jTenth），0.3 步进精确
    static string buildRingSvg()
    {
        string svg = "<svg xmlns='http://www.w3.org/2000/svg' width='800' height='600'>"
        svg = svg + "<rect width='800' height='600' fill='white'/>"

        int kWhole = 1
        int kTenth = 0
        int jWhole = 1
        int jTenth = 0
        int i = 0
        while ( i < 26 )
        {
            svg = svg + "<circle cx='310' cy='250' r='" + kWhole.toString() + "." + kTenth.toString() + "' fill='none' stroke='black'/>"

            # k += j（十分位进位）
            kTenth = kTenth + jTenth
            kWhole = kWhole + jWhole
            if ( kTenth >= 10 )
            {
                kTenth = kTenth - 10
                kWhole = kWhole + 1
            }
            # j += 0.3（十分位进位）
            jTenth = jTenth + 3
            if ( jTenth >= 10 )
            {
                jTenth = jTenth - 10
                jWhole = jWhole + 1
            }
            i = i + 1
        }
        svg = svg + "</svg>"
        ret svg
    }

    # ── 三示例合一窗口 ────────────────────────────────────────────────────
    public static void main()
    {
        Console.println( "========== GUIDemo: historical GUI samples rewritten with SLQT ==========" )
        string kind = SLang.QT.backendKind()
        Console.println( "backend=" + kind + "  platform=" + SLang.QT.appPlatformName() )

        SLang.QApplication app = SLang.QT.newApp()

        # 1) 生成两幅画布 SVG（旧宿主 Canvas 的 createOval / createLine 序列）
        string chordSvg = buildChordSvg()
        string ringSvg = buildRingSvg()

        # 2) 窗口装配：QMainWindow + QGridLayout（2 列：弦艺术 | 同心圆，按钮跨 2 列）
        SLang.QMainWindow win = SLang.QT.newMainWindow()
        win.setTitle( "SLang GUI 历史示例 · SLQT 实现" )
        win.resize( 840, 560 )

        SLang.QWidget panel = SLang.QT.newWidget( 0 )
        SLang.QGridLayout lay = SLang.QT.newGrid( 0 )

        SLang.QLabel t1 = SLang.QT.newLabel( 0, "Canvas绘图.sl —— 15 点两两连线（弦艺术）" )
        SLang.QLabel t2 = SLang.QT.newLabel( 0, "Canvas绘图_套圆.sl —— 26 圈渐宽同心圆" )

        SLang.QSvgWidget chordView = SLang.QT.newSvgWidget( 0 )
        chordView.loadData( chordSvg )
        chordView.setFixedSize( 400, 400 )

        SLang.QSvgWidget ringView = SLang.QT.newSvgWidget( 0 )
        ringView.loadData( ringSvg )
        ringView.setFixedSize( 400, 300 )

        # 3) FrameUI.sl：Button("您好")，clicked 绑定全限定 handler
        SLang.QPushButton helloBtn = SLang.QT.newButton( 0, "您好" )

        lay.addWidgetAt( t1, 0, 0, 1, 1 )
        lay.addWidgetAt( t2, 0, 1, 1, 1 )
        lay.addWidgetAt( chordView, 1, 0, 1, 1 )
        lay.addWidgetAt( ringView, 1, 1, 1, 1 )
        lay.addWidgetAt( helloBtn, 2, 0, 1, 2 )

        panel.setLayout( lay )
        win.setCentralWidget( panel )

        Int64 bindId = helloBtn.clicked( GUIDemo.onHello )
        Console.println( "[FrameUI] clicked bind_id=" + SystemConvertString( bindId as Int32 ) )

        win.show()
        Console.println( "window shown - close it to exit" )
        app.exec()
        Console.println( "========== GUIDemo done ==========" )
    }
}
