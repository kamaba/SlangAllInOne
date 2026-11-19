import SLangQT;
import Std;
import Core;

# QTHost - QT host facade in pure FFI-handle form (SnakeGame, 2026-11-17).
# Why this exists: SimGameEngine (transitively brings SLangRender namespace
# SLang) + SLangQT (namespace SLang) referenced by one module -> the import
# plane name "SLang" clashes -> ANY member declaration typed `SLang.Xxx`
# raises MetaCoreMemberNameImportConflict (call expressions are fine).
# Workaround: NO wrapped-object members here - QT objects are kept as
# Int64 handles and driven via QTFFI static exports directly.
public class QTHost
{
    static Int64 appHandle = 0
    static Int64 keyWHandle = 0
    static Int64 labelHandle = 0
    static Int64 timerHandle = 0
    # 场景层级检视器（Ctrl+F12；SceneInspector 驱动，QTHost 只出包装）
    static Int64 insTreeHandle = 0
    static Int64 insTextHandle = 0
    static bool insVisible = false
    # 顶部菜单栏 + 帧率显示（Ctrl+Home 切换菜单显示；第一个菜单「显示帧率」）
    static Int64 menuBarHandle = 0
    static Int64 fpsMenuHandle = 0
    static Int64 fpsActionHandle = 0
    static Int64 fpsLabelHandle = 0
    static bool menuVisible = false
    static bool fpsVisible = false

    # key bridge (int payload = Qt::Key) -> engine input state table (C)
    static void keyPressedBridge( Int32 key )
    {
        QTHost.ffiInputSetKey( key, 1 )
    }

    static void keyReleasedBridge( Int32 key )
    {
        QTHost.ffiInputSetKey( key, 0 )
    }

    # direct write into sle_input table (dll-name binding, no module import)
    static void inputSetKey( Int32 key, Int32 down )
    {
        QTHost.ffiInputSetKey( key, down )
    }

    @DllStaticImport( "sl_sim_engine_lib", "sle_input_set_key", "i32,i32->i32" )
    public static Int32 ffiInputSetKey( Int32 key, Int32 down )
    {
        ret 0 - 1
    }

    # startHost - build window + wire handlers; exec blocks in Qt loop.
    # handlers: frame = static void(); keyPress/Release = static void( int key )
    # toggleFps = static void() —— 菜单「显示帧率」动作触发回调
    public static void startHost( Function frameHandler, Function keyPressHandler, Function keyReleaseHandler, Function toggleFpsHandler )
    {
        appHandle = SLang.QT.ffi_appCreate()
        # 单一顶层窗口 = SlangKeyWidget（键盘事件源）。原实现另建一个
        # ffi_widgetCreate(0) 的普通 QWidget 当"标题窗口"，两个 parent=0
        # 窗口几何完全重合；盖在上面的空 QWidget 把挂了 label 的键盘窗口
        # 整个遮住 -> 截图只见空白标题窗，游戏画面永远不可见。
        keyWHandle = SLang.QT.ffi_keyWidgetCreate( 0 )
        SLang.QT.ffi_widgetSetText( keyWHandle, "SnakeGame - SimGameEngine + SLangQT" )
        SLang.QT.ffi_widgetSetGeometry( keyWHandle, 80, 80, 500, 500 )
        # 2026-11-19 第四轮：QT 侧只保留游戏画布这一个控件——主菜单/HUD/
        # 排行榜/暂停/结束全部由引擎 FairyGUI（UI 叠加相机）渲染进画布，
        # QT 信息条与覆盖层全部移除（「该用 UI 的地方都用 UI，只有游戏
        # 中心用正常画布」）
        labelHandle = SLang.QT.ffi_labelCreate( keyWHandle )
        SLang.QT.ffi_widgetSetGeometry( labelHandle, 10, 10, 480, 480 )
        # 场景层级检视器（Ctrl+F12 切换）：左树（节点名层级）+ 右侧节点详情
        # （组件/Transform 等）。创建即隐藏，不占事件；显示时盖在画布上层。
        insTreeHandle = SLang.QT.ffi_treeCreate( keyWHandle )
        SLang.QT.ffi_treeSetHeader( insTreeHandle, "Scene Hierarchy" )
        SLang.QT.ffi_widgetSetGeometry( insTreeHandle, 10, 10, 220, 470 )
        insTextHandle = SLang.QT.ffi_texteditCreate( keyWHandle )
        SLang.QT.ffi_widgetSetGeometry( insTextHandle, 240, 10, 230, 470 )
        SLang.QT.ffi_texteditSetReadonly( insTextHandle, true )
        SLang.QT.ffi_widgetHide( insTreeHandle )
        SLang.QT.ffi_widgetHide( insTextHandle )
        # 顶部菜单栏（Ctrl+Home 切换显示）：QMenuBar 作为 keyWHandle 子控件
        # 放到窗口最顶部；第一个菜单项「显示帧率」→ toggleFpsHandler。
        # 帧率显示 QLabel 挂在画布右上角，默认隐藏。
        menuBarHandle = SLang.QT.ffi_menubarCreate()
        SLang.QT.ffi_widgetSetParent( menuBarHandle, keyWHandle )
        SLang.QT.ffi_widgetSetGeometry( menuBarHandle, 0, 0, 500, 26 )
        fpsMenuHandle = SLang.QT.ffi_menuCreate( menuBarHandle, "显示帧率" )
        fpsActionHandle = SLang.QT.ffi_menuAddAction( fpsMenuHandle, "显示帧率" )
        SLang.QT.connect( fpsActionHandle, SLang.QT.SIG_TRIGGERED, toggleFpsHandler )
        SLang.QT.ffi_widgetHide( menuBarHandle )
        fpsLabelHandle = SLang.QT.ffi_labelCreate( keyWHandle )
        SLang.QT.ffi_widgetSetGeometry( fpsLabelHandle, 360, 30, 130, 24 )
        SLang.QT.ffi_widgetSetText( fpsLabelHandle, "FPS: --" )
        SLang.QT.ffi_widgetHide( fpsLabelHandle )
        SLang.QT.connect( keyWHandle, SLang.QT.SIG_KEY_PRESSED, keyPressHandler )
        SLang.QT.connect( keyWHandle, SLang.QT.SIG_KEY_RELEASED, keyReleaseHandler )
        SLang.QT.ffi_widgetShow( keyWHandle )
        SLang.QT.ffi_widgetShow( labelHandle )
        timerHandle = SLang.QT.timer( 16, false, frameHandler )
        SLang.QT.ffi_timerStart( timerHandle, 16 )
        SLang.QT.ffi_appExec()
    }

    # blit - engine frame pixels (RGBA8 top-down) onto the label
    public static void blit( Int64 ptr, Int32 w, Int32 h )
    {
        SLang.QT.ffi_labelSetPixmapRgba( labelHandle, ptr, w, h )
    }

    # ── 统一输入桥（2026-11-19 第五轮；QT 只作事件源，游戏侧只读引擎
    # InputSystem 门面）──────────────────────────────────────────────
    # 键盘：QT 键盘信号（keyPressed/keyReleasedBridge）→ C 表直写（事件
    #   驱动，按下沿由 C 侧自动重复去重保证）。
    # 鼠标：QT 仅提供轮询 FFI → 每帧帧首由游戏主循环调 pumpMouse 采样
    #   注入（按钮 down 变化沿 + 坐标 + 滚轮累计）。
    # 本文件不再对外暴露任何 QT 输入查询接口——查询一律走引擎
    # InputSystem（isDown/wasPressed/mouseDown/mousePressed/...）。
    # 鼠标注入走 dll-name 直绑（本文件不 import SimGameEngine——规避
    # 双 SLang namespace 冲突；与 ffiInputSetKey 同模式）。按钮槽位约定
    # 与引擎 InputSystem 一致：1=左键 2=右键（0..7）。
    @DllStaticImport( "sl_sim_engine_lib", "sle_input_set_mouse_button", "i32,i32->i32" )
    public static Int32 ffiInputSetMouseButton( Int32 button, Int32 down )
    {
        ret 0 - 1
    }

    @DllStaticImport( "sl_sim_engine_lib", "sle_input_set_mouse_pos", "i32,i32->i32" )
    public static Int32 ffiInputSetMousePos( Int32 x, Int32 y )
    {
        ret 0 - 1
    }

    @DllStaticImport( "sl_sim_engine_lib", "sle_input_set_mouse_wheel", "i32->i32" )
    public static Int32 ffiInputSetMouseWheel( Int32 delta )
    {
        ret 0 - 1
    }

    static Int32 prevLeft = 0
    static Int32 prevRight = 0

    public static void pumpMouse()
    {
        # 坐标源必须用 localX/Y（e->position() = 窗口客户区口径，与
        # SceneDemo 命中测试同款）；ffi_mouseX/Y 是全局屏幕坐标——
        # 用它命中测试永远映射不到 UI（2026-11-19 点击无反应根因）
        Int32 mx = SLang.QT.ffi_mouseLocalX()
        Int32 my = SLang.QT.ffi_mouseLocalY()
        QTHost.ffiInputSetMousePos( mx, my )
        Int32 dl = SLang.QT.ffi_mouseDown( 1 )
        Int32 dr = SLang.QT.ffi_mouseDown( 2 )
        Int32 btnL = 1
        Int32 btnR = 2
        if dl != prevLeft
        {
            Int32 ld = 0
            if dl == 1
            {
                ld = 1
            }
            QTHost.ffiInputSetMouseButton( btnL, ld )
            prevLeft = dl
        }
        if dr != prevRight
        {
            Int32 rd = 0
            if dr == 1
            {
                rd = 1
            }
            QTHost.ffiInputSetMouseButton( btnR, rd )
            prevRight = dr
        }
        Int32 w = SLang.QT.ffi_mouseWheelTake()
        if w != 0
        {
            QTHost.ffiInputSetMouseWheel( w )
        }
    }

    # ── 键盘轮询注入（2026-11-19 第六轮）────────────────────────────
    # QT 键盘回调（SIG_KEY_PRESSED trampoline 重入 VM）不可靠——C++
    # slang_qt_qt.cpp 已定性并给出 slqt_be_key_down 轮询表。改与鼠标同款
    # 逐帧轮询：读 ffi_keyDown(Qt::Key) → 写引擎 C 表。键码直接用 Qt::Key
    # 枚举值，sle_input_set_key / sle_input_pressed 共用同一个 sle_input_slot
    # 压缩映射（方向键→134..137、Enter→133、Space 32 直取），天然一致。
    # 边沿由 C 侧 down && !prev 去重，按住连发不会误触发 wasPressed。
    static void pumpKeyboard()
    {
        QTHost.pumpKey( 16777235 )   # Up    0x01000013
        QTHost.pumpKey( 16777237 )   # Down  0x01000015
        QTHost.pumpKey( 16777234 )   # Left  0x01000012
        QTHost.pumpKey( 16777236 )   # Right 0x01000014
        QTHost.pumpKey( 32 )         # Space 0x20
        QTHost.pumpKey( 82 )         # R     0x52
        QTHost.pumpKey( 16777220 )   # Return 0x01000004
        QTHost.pumpKey( 16777249 )   # Ctrl   0x01000021
        QTHost.pumpKey( 16777334 )   # F12    0x01000076
        QTHost.pumpKey( 16777232 )   # Home   0x01000010
    }

    static void pumpKey( Int32 key )
    {
        Int32 dn = SLang.QT.ffi_keyDown( key )
        QTHost.ffiInputSetKey( key, dn )
    }

    # ── 菜单栏 / 帧率显示操作（Ctrl+Home 切换菜单；菜单动作切换 FPS）──

    public static void toggleMenuBar()
    {
        if menuVisible
        {
            SLang.QT.ffi_widgetHide( menuBarHandle )
            menuVisible = false
        }
        else
        {
            SLang.QT.ffi_widgetShow( menuBarHandle )
            menuVisible = true
        }
    }

    public static void toggleFpsLabel()
    {
        if fpsVisible
        {
            SLang.QT.ffi_widgetHide( fpsLabelHandle )
            fpsVisible = false
        }
        else
        {
            SLang.QT.ffi_widgetShow( fpsLabelHandle )
            fpsVisible = true
        }
    }

    public static void setFpsText( string text )
    {
        SLang.QT.ffi_widgetSetText( fpsLabelHandle, text )
    }

    public static bool fpsLabelVisible()
    {
        ret fpsVisible
    }

    # 退出应用（窗口 X / 系统关闭走本通道；SL 侧预留）
    public static void quitApp()
    {
        SLang.QT.ffi_appQuit()
    }

    # ── 场景层级检视器包装（SceneInspector 消费；本文件不 import
    # SimGameEngine，引擎类型一律不出现）────────────────────────────

    public static bool inspectorVisible()
    {
        ret insVisible
    }

    public static void inspectorShow()
    {
        SLang.QT.ffi_widgetShow( insTreeHandle )
        SLang.QT.ffi_widgetShow( insTextHandle )
        insVisible = true
    }

    public static void inspectorHide()
    {
        SLang.QT.ffi_widgetHide( insTreeHandle )
        SLang.QT.ffi_widgetHide( insTextHandle )
        insVisible = false
    }

    public static void insTreeClear()
    {
        SLang.QT.ffi_treeClear( insTreeHandle )
    }

    public static void insTreeAddPath( string path )
    {
        SLang.QT.ffi_treeAddPath( insTreeHandle, path )
    }

    public static void insTreeExpandAll()
    {
        SLang.QT.ffi_treeExpandAll( insTreeHandle )
    }

    public static string insTreeSelectedPath()
    {
        ret SLang.QT.ffi_treeSelectedPath( insTreeHandle )
    }

    public static void insTextSetText( string t )
    {
        SLang.QT.ffi_texteditSetText( insTextHandle, t )
    }

    # ── Screen auto-fit (2026-11-19, SceneDemo dynamic-resolution pattern) ──

    # top-level window client size (pixel); stub/error returns 0, caller
    # must check > 0 before using
    public static Int32 windowWidth()
    {
        ret SLang.QT.ffi_widgetWidth( keyWHandle )
    }

    public static Int32 windowHeight()
    {
        ret SLang.QT.ffi_widgetHeight( keyWHandle )
    }

    # re-layout on window resize: 画布 (10,10) 起步方形铺满
    public static void layoutUi( Int32 side )
    {
        SLang.QT.ffi_widgetSetGeometry( labelHandle, 10, 10, side, side )
    }
}