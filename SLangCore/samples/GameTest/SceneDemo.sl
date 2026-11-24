import Core;
import Std;
import Math;
import SimGameEngine;
import SLangRender;

# SceneDemo（doc/19）：按路径加载场景 + 脚本随帧循环跑 + O 键导出 JSON。
# 键位 1/2/3/4 切场景，WASD 移动相机，左键拖拽平移视角，滚轮缩放，O 导出，
# Esc 退出。
public class SceneDemo
{
    static SceneManager sm = null
    static RenderSystem rs = null
    static Int64 pixels = 0
    static string baseDir = ""
    static string lastInfo = ""
    static bool prev1 = false
    static bool prev2 = false
    static bool prev3 = false
    static bool prev4 = false
    static bool prev5 = false
    static bool prevO = false
    # 相机操作状态（SL 侧权威值，每帧写回 rs.cameraCenter/viewSize——
    # 跨模块只整块赋值，不直写字段分量）
    static Float32 camX = 0.0f
    static Float32 camY = 2.5f
    static Float32 camView = 7.0f
    static Int32 prevMx = 0
    static Int32 prevMy = 0
    static bool prevMDown = false
    static bool prevRMDown = false
    # 镜头方向（Alt+左键拖拽旋转）：yaw/pitch 弧度。yaw=0/pitch=0 = 正对 -Z。
    static Float32 camYaw = 0.0f
    static Float32 camPitch = 0.0f
    static Int32 KEY_ALT = 16777264   # Qt::Key_Alt = 0x01000230
    static Int32 KEY_SHIFT = 16777248 # Qt::Key_Shift = 0x01000020
    static Int32 KEY_CTRL = 16777249  # Qt::Key_Control = 0x01000021
    static Int32 KEY_HOME = 16777232  # Qt::Key_Home = 0x01000010
    static Float32 ROT_SPEED = 0.008f  # 每像素弧度
    static bool prevHome = false       # Ctrl+Home 边沿检测
    # 编辑器 Gizmo（引擎层 GizmoSystem：XYZ 轴箭头 / 旋转环 / 缩放柄 +
    # 相机·光源 2D/3D 图标）。G 键循环 move→rotate→scale→none。
    static GizmoSystem gs = null
    public static bool showAxes = true
    static bool prevG = false
    # 动态分辨率状态（Unity OnResize 语义：窗口变 → 渲染目标/像素块/
    # 显示 label 同步变）
    static Int32 renderW = 480
    static Int32 renderH = 480
    # FairyGUI XML 包适配（XML 数据 → 图集 uvRect/九宫格 → 自定义 UI 网格）
    static FairyPackage fairyPkg = null
    static FairyUIRenderer fairyRenderer = null
    static string fairyDir = ""
    static string fairyInfo = "ui=off"
    static bool uiVisible = false
    static bool useFui = false
    static bool prevF = false
    static bool prevU = false
    # ── 主入口菜单（FairyGUI）：启动显示，点场景按钮进入 ────
    static FairyPackage menuPkg = null
    static FairyUIRenderer menuRenderer = null
    static string menuDir = ""
    static string menuInfo = "menu=off"
    static bool inMenu = true
    static bool prevInMenu = true
    static bool prevClick = false
    static bool prevM = false

    # 单位圆网格上传（自定义槽 0）：27 材质球共用该网格，各自 MVP/颜色不同
    static void initBallMesh()
    {
        List<Float32_3> verts = List<Float32_3>( 240 )
        Int32 seg = 40
        Int32 i = 0
        while i < seg
        {
            Float32 a0 = i.toFloat32() * 0.1570796f
            Float32 a1 = ( i + 1 ).toFloat32() * 0.1570796f
            Float32_3 c = Float32_3( 0.0f, 0.0f, 0.0f )
            Float32_3 p0 = Float32_3( Mathf.cos( a0 ), Mathf.sin( a0 ), 0.0f )
            Float32_3 p1 = Float32_3( Mathf.cos( a1 ), Mathf.sin( a1 ), 0.0f )
            verts.add( c )
            verts.add( p0 )
            verts.add( p1 )
            i = i + 1
        }
        bool ok = SceneDemo.rs.uploadMeshXyz( 0, verts )
        Console.println( "[scene] ball mesh upload ok=" + ok.toString() )
    }

    # 示例根目录：兼容「在示例目录运行」「在工作区根运行」「在 publish/release 运行」
    static string findProjectDir()
    {
        string cwd = IO.Directory.getCurrentDirectory()
        if File.exists( cwd + "/assets/scenes/MaterialBall.scene.json" )
        {
            ret cwd
        }
        string ws = cwd + "/SlangAllInOne/SLangCore/samples/GameTest"
        if File.exists( ws + "/assets/scenes/MaterialBall.scene.json" )
        {
            ret ws
        }
        string publishDir = cwd + "/../.."
        if File.exists( publishDir + "/assets/scenes/MaterialBall.scene.json" )
        {
            ret publishDir
        }
        ret "D:/project/lang/SlangAllInOne/SLangCore/samples/GameTest"
    }

    static string findSceneDir()
    {
        ret SceneDemo.findProjectDir() + "/assets/scenes"
    }

    static string findFairyDir()
    {
        ret SceneDemo.findProjectDir() + "/assets/fairygui/Demo"
    }

    static void initFairyUI()
    {
        SceneDemo.fairyDir = SceneDemo.findFairyDir()
        FairyPackage p = FairyPackage()
        bool ok = false
        if SceneDemo.useFui
        {
            ok = p.loadFui( SceneDemo.fairyDir )
        }
        else
        {
            ok = p.load( SceneDemo.fairyDir )
        }
        if !ok
        {
            SceneDemo.fairyInfo = "ui=ERR " + p.lastError
            Console.println( "[fairy] load failed: " + p.lastError )
            ret
        }
        SceneDemo.fairyPkg = p
        FairyUIRenderer r = FairyUIRenderer()
        r.pkg = p
        SceneDemo.fairyRenderer = r
        string fmt = "xml"
        if SceneDemo.useFui
        {
            fmt = "fui"
        }
        SceneDemo.fairyInfo = "ui=" + fmt + ":" + p.quads.length.toString() + "q"
        Console.println( "[fairy] loaded " + fmt + " " + p.name + " quads=" + p.quads.length.toString() + " sprites=" + p.sprites.length.toString() )
    }

    static string findMainMenuDir()
    {
        ret SceneDemo.findProjectDir() + "/assets/fairygui/MainMenu"
    }

    static void initMenuUI()
    {
        SceneDemo.menuDir = SceneDemo.findMainMenuDir()
        FairyPackage p = FairyPackage()
        bool ok = p.load( SceneDemo.menuDir )
        if !ok
        {
            SceneDemo.menuInfo = "menu=ERR " + p.lastError
            Console.println( "[menu] load failed: " + p.lastError )
            ret
        }
        FairyUIRenderer r = FairyUIRenderer()
        r.pkg = p
        SceneDemo.menuPkg = p
        SceneDemo.menuRenderer = r
        SceneDemo.menuInfo = "menu=" + p.quads.length.toString() + "q"
        Console.println( "[menu] loaded quads=" + p.quads.length.toString() )
    }

    # 菜单点击：渲染面局部像素 → 设计坐标 → 命中名字 → 场景号
    static void tryMenuClick()
    {
        if SceneDemo.menuRenderer == null
        {
            ret
        }
        # Qt 报告的是窗口客户区坐标；渲染 QLabel 位于 (8,52)
        Int32 lx = QTHost.mouseLocalX() - 8
        Int32 ly = QTHost.mouseLocalY() - 52
        Int32 rw = SceneDemo.renderW
        Int32 rh = SceneDemo.renderH
        string hit = SceneDemo.menuRenderer.hitTestLocal( lx, ly, rw, rh )
        Int32 idx = FairyUIRenderer.menuIndex( hit, "menu_" )
        SceneDemo.menuInfo = "menu=hit:" + hit + " @" + lx.toString() + "," + ly.toString() + " idx=" + idx.toString()
        if idx < 0 || idx > 4
        {
            ret
        }
        SceneDemo.inMenu = false
        SceneDemo.loadScene( idx )
    }

    static void loadScene( Int32 idx )
    {
        string name = "MaterialBall.scene.json"
        if idx == 1
        {
            name = "ShapeGallery.scene.json"
        }
        elif idx == 2
        {
            name = "PureTest.scene.json"
        }
        elif idx == 3
        {
            name = "MaterialGallery.scene.json"
        }
        elif idx == 4
        {
            name = "RotateTest.scene.json"
        }
        string path = SceneDemo.baseDir + "/" + name
        Scene loaded = SceneDemo.sm.load( path )
        if loaded == null
        {
            Console.println( "[scene] load failed: " + SceneDemo.sm.lastError )
        }
        else
        {
            Console.println( "[scene] loaded " + loaded.name )
            SceneDemo.createAxisNodes( loaded )
        }
        # 场景 5 = 旋转测试：初始相机俯视 45°（pitch=-0.785）看地面+正方形；
        # 其余场景恢复正视角（yaw/pitch=0）。焦点对准场景中心 (0,0)。
        if idx == 4
        {
            SceneDemo.camX = 0.0f
            SceneDemo.camY = 0.0f
            SceneDemo.camView = 9.0f
            SceneDemo.camYaw = 0.0f
            SceneDemo.camPitch = 0.0f - 0.785398f
        }
        else
        {
            SceneDemo.camYaw = 0.0f
            SceneDemo.camPitch = 0.0f
        }
        SceneDemo.updateInfo()
    }

    static void updateInfo()
    {
        string n = "none"
        Scene cur = SceneDemo.sm.activeScene
        if cur != null
        {
            n = cur.name
        }
        string nn = SceneDemo.sm.nodeCount.toString()
        string sn = SceneDemo.sm.scriptCount.toString()
        string ln = SceneDemo.rs.lightCount.toString()
        string on = SceneDemo.rs.lastSubmitted.toString()
        string s = SceneDemo.menuInfo + "   Scene: " + n + "   nodes=" + nn + "   scripts=" + sn + "   lights=" + ln + "   objs=" + on
        string yaw = SceneDemo.camYaw.toString()
        string pit = SceneDemo.camPitch.toString()
        string alt = QTHost.keyDown( SceneDemo.KEY_ALT ).toString()
        string mb = QTHost.mouseDown( 1 ).toString()
        string rmb = QTHost.mouseDown( 2 ).toString()
        string mxy = QTHost.mouseX().toString() + "," + QTHost.mouseY().toString()
        string gizmoMode = "none"
        if SceneDemo.gs != null
        {
            Int32 gm = SceneDemo.gs.currentMode()
            if gm == GizmoTypes.MODE_MOVE
            {
                gizmoMode = "move"
            }
            elif gm == GizmoTypes.MODE_ROTATE
            {
                gizmoMode = "rotate"
            }
            elif gm == GizmoTypes.MODE_SCALE
            {
                gizmoMode = "scale"
            }
        }
        s = s + "   cam=" + SceneDemo.camView.toString() + " yaw=" + yaw + " pitch=" + pit + " alt=" + alt + " lmb=" + mb + " rmb=" + rmb + " xy=" + mxy + " gizmo=" + gizmoMode
        if SceneDemo.inMenu
        {
            s = "CLICK A SCENE  |  " + s
        }
        if !SceneDemo.sm.ok
        {
            s = s + "   ERR: " + SceneDemo.sm.lastError
        }
        if s != SceneDemo.lastInfo
        {
            SceneDemo.lastInfo = s
            QTHost.setInfo( s )
        }
    }

    # ── 动态分辨率（每帧调用）：探测窗口客户区尺寸，变化时重建渲染
    # 目标（rs.resize → slr_pipeline_resize，对象句柄保留）、重分配
    # 像素块、label 同步缩到新尺寸（顶部 60px 留信息条）。钳 [64,2048]。
    static void updateRenderTarget()
    {
        Int32 ww = QTHost.windowW()
        Int32 wh = QTHost.windowH()
        if ww < 80 || wh < 80
        {
            ret
        }
        Int32 w = ww - 16
        Int32 h = wh - 60
        if w < 64
        {
            w = 64
        }
        if h < 64
        {
            h = 64
        }
        if w > 2048
        {
            w = 2048
        }
        if h > 2048
        {
            h = 2048
        }
        if w == SceneDemo.renderW && h == SceneDemo.renderH
        {
            ret
        }
        bool ok = SceneDemo.rs.resize( w, h )
        if ok
        {
            Int64 old = SceneDemo.pixels
            if old != 0
            {
                Memory.free( old )
            }
            SceneDemo.pixels = Memory.alloc( w * h * 4 )
            SceneDemo.renderW = w
            SceneDemo.renderH = h
            QTHost.resizeView( w, h )
            Console.println( "[scene] render target " + w.toString() + "x" + h.toString() )
        }
    }

    # ── 编辑器 Gizmo（引擎层 GizmoSystem）─────────────────
    # 坐标轴脚本每帧把各节点局部位置报给 pushAxisAt，GizmoSystem 按当前
    # mode（G 键循环 move/rotate/scale）在三色缓冲累积几何；相机/光图标
    # 每帧在场景锚点位置追加。begin/end 包裹脚本 tick，endFrame 写回 MeshRef。
    static void beginAxisFrame()
    {
        if SceneDemo.gs != null
        {
            SceneDemo.gs.beginFrame()
        }
    }

    # 坐标轴脚本回调：按当前模式在 p 处累积变换 gizmo 几何
    static void pushAxisAt( Float32_3 p )
    {
        if SceneDemo.gs == null || !SceneDemo.showAxes
        {
            ret
        }
        SceneDemo.gs.drawTransform( p )
    }

    # 相机 / 光源图标：编辑器形象演示（场景锚点固定位置）
    static void pushEditorIcons()
    {
        if SceneDemo.gs == null || !SceneDemo.showAxes
        {
            ret
        }
        Float32_3 camP = Float32_3( 0.0f - 4.5f, 3.6f, 0.0f )
        Float32_3 litP = Float32_3( 4.5f, 3.6f, 0.0f )
        SceneDemo.gs.drawCamera( camP, false )
        Int32 lt = GizmoTypes.LIGHT_SPOT
        SceneDemo.gs.drawLight( litP, lt, false )
    }

    static void endAxisFrame()
    {
        if SceneDemo.gs != null
        {
            SceneDemo.gs.endFrame()
        }
    }

    # 菜单「显示辅助 Gizmo」动作回调（SIG_TRIGGERED trampoline，无参 void）
    static void toggleGizmoMenu()
    {
        SceneDemo.showAxes = !SceneDemo.showAxes
    }

    # loadScene 后绑定 gizmo 节点到新场景（GizmoSystem 内部建六色 MeshRef）
    static void createAxisNodes( Scene scene )
    {
        if SceneDemo.gs != null
        {
            SceneDemo.gs.attach( scene )
        }
    }

    # ── 相机操作（每帧调用，写回 SL 侧权威值）────────────────────
    # W/S 前后（世界 Y），A/D 左右（世界 X），每帧固定步长（60Hz 定时器）；
    # 左键按住拖拽 = 平移视角（内容跟随鼠标，全局坐标差值换算世界步长）；
    # 滚轮缩放（每格 ×0.85，上限 40 下限 1.5）。
    static void updateCamera()
    {
        Float32 step = 0.16f
        if QTHost.keyDown( 87 ) == 1
        {
            SceneDemo.camY = SceneDemo.camY + step
        }
        if QTHost.keyDown( 83 ) == 1
        {
            SceneDemo.camY = SceneDemo.camY - step
        }
        if QTHost.keyDown( 65 ) == 1
        {
            SceneDemo.camX = SceneDemo.camX - step
        }
        if QTHost.keyDown( 68 ) == 1
        {
            SceneDemo.camX = SceneDemo.camX + step
        }
        Int32 md = QTHost.mouseDown( 1 )
        Int32 rmb = QTHost.mouseDown( 2 )
        Int32 mx = QTHost.mouseX()
        Int32 my = QTHost.mouseY()
        Int32 altRaw = QTHost.keyDown( SceneDemo.KEY_ALT )
        Int32 shiftRaw = QTHost.keyDown( SceneDemo.KEY_SHIFT )
        Int32 alt = 0
        if altRaw == 1 || shiftRaw == 1
        {
            alt = 1
        }
        # 右键拖拽始终旋转（走左键同款鼠标过滤器路径，不依赖修饰键）
        if rmb == 1
        {
            alt = 1
        }
        if (md == 1 && SceneDemo.prevMDown) || (rmb == 1 && SceneDemo.prevRMDown)
        {
            Int32 dxi = mx - SceneDemo.prevMx
            Int32 dyi = my - SceneDemo.prevMy
            if alt == 1
            {
                # 拖拽 = 旋转镜头方向（yaw 随水平，pitch 随垂直）。
                # pitch 用 +dy：鼠标下拖 → pitch 增大 → 相机上仰 → 场景内容下移，
                # 与「直接操纵场景」直觉一致（原 -dy 上下相反，已修正）。
                SceneDemo.camYaw = SceneDemo.camYaw + dxi.toFloat32() * SceneDemo.ROT_SPEED
                SceneDemo.camPitch = SceneDemo.camPitch + dyi.toFloat32() * SceneDemo.ROT_SPEED
                if SceneDemo.camPitch > 1.55f
                {
                    SceneDemo.camPitch = 1.55f
                }
                if SceneDemo.camPitch < 0.0f - 1.55f
                {
                    SceneDemo.camPitch = 0.0f - 1.55f
                }
            }
            else
            {
                # 普通左键拖拽 = 平移视角
                Int32 rh = SceneDemo.renderH
                Float32 wpp = SceneDemo.camView * 2.0f / rh.toFloat32()
                Float32 dxw = dxi.toFloat32() * wpp
                Float32 dyw = dyi.toFloat32() * wpp
                SceneDemo.camX = SceneDemo.camX - dxw
                SceneDemo.camY = SceneDemo.camY + dyw
            }
        }
        SceneDemo.prevMDown = md == 1
        SceneDemo.prevRMDown = rmb == 1
        SceneDemo.prevMx = mx
        SceneDemo.prevMy = my
        Int32 wn = QTHost.mouseWheelTake()
        while wn != 0
        {
            if wn > 0
            {
                SceneDemo.camView = SceneDemo.camView * 0.85f
            }
            else
            {
                SceneDemo.camView = SceneDemo.camView / 0.85f
            }
            if SceneDemo.camView < 1.5f
            {
                SceneDemo.camView = 1.5f
            }
            if SceneDemo.camView > 40.0f
            {
                SceneDemo.camView = 40.0f
            }
            # wn 可能为负（向下滚缩小）：必须朝 0 递进，否则负数
            # 越来越负 → while wn != 0 死循环卡死（向上滚放大正常）。
            if wn > 0
            {
                wn = wn - 1
            }
            else
            {
                wn = wn + 1
            }
        }
        Float32 cx = SceneDemo.camX
        Float32 cy = SceneDemo.camY
        Float32_3 cc = Float32_3( cx, cy, 0.0f )
        SceneDemo.rs.cameraCenter = cc
        SceneDemo.rs.viewSize = SceneDemo.camView
        # 镜头方向写回渲染系统：eye 取相机观察中心（正交下 eye.z 仅深度序）
        SceneDemo.rs.cameraEye = cc
        SceneDemo.rs.camYaw = SceneDemo.camYaw
        SceneDemo.rs.camPitch = SceneDemo.camPitch
        SceneDemo.rs.useViewRotation = true
    }

    static void frameTick()
    {
        Int32 k1 = QTHost.keyDown( 49 )
        Int32 k2 = QTHost.keyDown( 50 )
        Int32 k3 = QTHost.keyDown( 51 )
        Int32 k4 = QTHost.keyDown( 52 )
        Int32 k5 = QTHost.keyDown( 53 )
        Int32 ko = QTHost.keyDown( 79 )
        Int32 ke = QTHost.keyDown( 16777216 )
        Int32 kg = QTHost.keyDown( 71 )
        Int32 kf = QTHost.keyDown( 70 )
        Int32 ku = QTHost.keyDown( 85 )
        Int32 km = QTHost.keyDown( 77 )
        Int32 kh = QTHost.keyDown( SceneDemo.KEY_HOME )
        Int32 kc = QTHost.keyDown( SceneDemo.KEY_CTRL )
        bool p1 = k1 == 1 && !SceneDemo.prev1
        bool p2 = k2 == 1 && !SceneDemo.prev2
        bool p3 = k3 == 1 && !SceneDemo.prev3
        bool p4 = k4 == 1 && !SceneDemo.prev4
        bool p5 = k5 == 1 && !SceneDemo.prev5
        bool po = ko == 1 && !SceneDemo.prevO
        bool pg = kg == 1 && !SceneDemo.prevG
        bool pf = kf == 1 && !SceneDemo.prevF
        bool pu = ku == 1 && !SceneDemo.prevU
        bool pm = km == 1 && !SceneDemo.prevM
        SceneDemo.prev1 = k1 == 1
        SceneDemo.prev2 = k2 == 1
        SceneDemo.prev3 = k3 == 1
        SceneDemo.prev4 = k4 == 1
        SceneDemo.prev5 = k5 == 1
        SceneDemo.prevO = ko == 1
        SceneDemo.prevG = kg == 1
        SceneDemo.prevF = kf == 1
        SceneDemo.prevU = ku == 1
        SceneDemo.prevM = km == 1
        # Ctrl+Home：Home 按下沿且 Ctrl 处于按下 → 切换顶部菜单栏显示
        bool ph = kh == 1 && !SceneDemo.prevHome
        if ph && kc == 1
        {
            QTHost.toggleMenuBar()
        }
        SceneDemo.prevHome = kh == 1
        if pg
        {
            # G 键循环 gizmo 模式：move → rotate → scale → none → move
            # 切到非 none 时自动恢复 showAxes（菜单开关关掉后 G 键仍能重新打开）
            Int32 m = GizmoTypes.MODE_NONE
            if SceneDemo.gs != null
            {
                Int32 cm = SceneDemo.gs.currentMode()
                if cm == GizmoTypes.MODE_NONE
                {
                    m = GizmoTypes.MODE_MOVE
                }
                elif cm == GizmoTypes.MODE_MOVE
                {
                    m = GizmoTypes.MODE_ROTATE
                }
                elif cm == GizmoTypes.MODE_ROTATE
                {
                    m = GizmoTypes.MODE_SCALE
                }
                SceneDemo.gs.setMode( m )
            }
            if m != GizmoTypes.MODE_NONE
            {
                SceneDemo.showAxes = true
            }
        }
        if pf
        {
            SceneDemo.useFui = !SceneDemo.useFui
            SceneDemo.initFairyUI()
            SceneDemo.rs.clearUi()
        }
        if pu
        {
            SceneDemo.uiVisible = !SceneDemo.uiVisible
            SceneDemo.rs.clearUi()
        }
        if p1
        {
            SceneDemo.loadScene( 0 )
            SceneDemo.inMenu = false
        }
        if p2
        {
            SceneDemo.loadScene( 1 )
            SceneDemo.inMenu = false
        }
        if p3
        {
            SceneDemo.loadScene( 2 )
            SceneDemo.inMenu = false
        }
        if p4
        {
            SceneDemo.loadScene( 3 )
            SceneDemo.inMenu = false
        }
        if p5
        {
            SceneDemo.loadScene( 4 )
            SceneDemo.inMenu = false
        }
        if pm
        {
            SceneDemo.inMenu = true
        }
        if po
        {
            string outPath = SceneDemo.baseDir + "/exported.scene.json"
            bool saved = SceneDemo.sm.save( outPath, null )
            Console.println( "[scene] export ok=" + saved.toString() )
        }
        if ke == 1
        {
            OS.Kernel.exit( 0 )
        }
        SceneDemo.updateRenderTarget()
        Int32 click = QTHost.mouseDown( 1 )
        bool pclick = click == 1 && !SceneDemo.prevClick
        SceneDemo.prevClick = click == 1
        if SceneDemo.inMenu && pclick
        {
            SceneDemo.tryMenuClick()
        }
        if SceneDemo.inMenu != SceneDemo.prevInMenu
        {
            # UI 对象是持久槽，sync() 不回收；切菜单/场景时必须清掉，
            # 否则旧菜单画面会一直盖在新场景上。
            SceneDemo.rs.clearUi()
            SceneDemo.prevInMenu = SceneDemo.inMenu
        }
        SceneDemo.updateCamera()
        SceneDemo.beginAxisFrame()
        SceneDemo.sm.tick( -1.0f )
        SceneDemo.pushEditorIcons()
        SceneDemo.endAxisFrame()
        SceneDemo.rs.sync( SceneDemo.sm.activeScene )
        # FairyGUI UI 网格必须在 sync() 之后提交（sync 开头会回收上一帧
        # RenderObject），且顶点 xy 已是 NDC，不受 3D 相机旋转影响。
        if SceneDemo.inMenu
        {
            if SceneDemo.menuRenderer != null
            {
                Int32 rw = SceneDemo.renderW
                Int32 rh = SceneDemo.renderH
                if rh > 0
                {
                    SceneDemo.menuRenderer.aspect = rw.toFloat32() / rh.toFloat32()
                }
                bool menuOk = SceneDemo.menuRenderer.draw( SceneDemo.rs )
                if menuOk
                {
                    SceneDemo.menuInfo = "menu=" + SceneDemo.menuRenderer.lastQuads.toString() + "q/" + SceneDemo.menuRenderer.lastVerts.toString() + "v"
                }
                else
                {
                    SceneDemo.menuInfo = "menu=ERR " + SceneDemo.menuRenderer.lastError
                }
            }
        }
        elif SceneDemo.uiVisible && SceneDemo.fairyRenderer != null
        {
            Int32 rw = SceneDemo.renderW
            Int32 rh = SceneDemo.renderH
            if rh > 0
            {
                SceneDemo.fairyRenderer.aspect = rw.toFloat32() / rh.toFloat32()
            }
            bool uiOk = SceneDemo.fairyRenderer.draw( SceneDemo.rs )
            if uiOk
            {
                SceneDemo.fairyInfo = "ui=" + SceneDemo.fairyRenderer.lastQuads.toString() + "q/" + SceneDemo.fairyRenderer.lastVerts.toString() + "v"
            }
            else
            {
                SceneDemo.fairyInfo = "ui=ERR " + SceneDemo.fairyRenderer.lastError
            }
        }
        Int64 pp = SceneDemo.pixels
        SceneDemo.rs.frame( 0.0f - 1.0f, pp )
        Int32 w = SceneDemo.renderW
        Int32 h = SceneDemo.renderH
        QTHost.blit( pp, w, h )
        SceneDemo.updateInfo()
    }

    # ── 网页版（H5）初始化：与 run() 同款引擎装配，但用 D3D11 后端（事件
    # 线程兼容性更好）且不启动 QT 宿主；由 SceneDemoWebUI.runWebUI 调用。
    public static bool webInit( Int32 w, Int32 h )
    {
        SceneDemo.sm = SceneManager()
        SceneDemo.sm.registerScript( "SphereMeshScript", SceneScriptFactories.makeSphereMesh )
        SceneDemo.sm.registerScript( "ShapeMeshScript", SceneScriptFactories.makeShapeMesh )
        SceneDemo.sm.registerScript( "SpinScript", SceneScriptFactories.makeSpin )
        SceneDemo.sm.registerScript( "ProbeScript", SceneScriptFactories.makeProbe )
        SceneDemo.sm.registerScript( "LightSwingScript", SceneScriptFactories.makeLightSwing )
        SceneDemo.sm.registerScript( "AxisGizmoScript", SceneScriptFactories.makeAxis )
        SceneDemo.baseDir = SceneDemo.findSceneDir()
        # WebUI 浏览器渲染：D3D11 后端（无 GL 上下文线程亲和，best fit）
        if SLang.Render.initializeBackend( "d3d11" ) == false
        {
            Console.println( "[scene][web] d3d11 backend failed: " + SLang.Render.errorString() )
            ret false
        }
        SceneDemo.rs = RenderSystem()
        if SceneDemo.rs.init( w, h ) == false
        {
            Console.println( "[scene][web] pipeline init failed: " + SceneDemo.rs.lastError )
            ret false
        }
        SceneDemo.gs = GizmoSystem()
        SceneDemo.rs.volumeSystem = VolumeSystem()
        SceneDemo.pixels = Memory.alloc( w * h * 4 )
        SceneDemo.renderW = w
        SceneDemo.renderH = h
        Float32 cx = SceneDemo.camX
        Float32 cy = SceneDemo.camY
        Float32_3 cc = Float32_3( cx, cy, 0.0f )
        SceneDemo.rs.cameraCenter = cc
        SceneDemo.rs.viewSize = SceneDemo.camView
        SceneDemo.initBallMesh()
        SceneDemo.initFairyUI()
        SceneDemo.initMenuUI()
        # 网页版直接进场景（菜单需要鼠标命中，H5 用场景按钮替代）
        SceneDemo.inMenu = false
        SceneDemo.loadScene( 4 )
        Console.println( "[scene][web] ready " + w.toString() + "x" + h.toString() + " backend=" + SLang.Render.currentBackend() )
        ret true
    }

    # ── 网页版每帧：主线程渲染一帧 + 处理来自 WebUI 事件线程的请求 ──
    # 由 SceneDemoWebUI 的帧循环调用（非 QT timer）。返回 false 表示请求退出。
    public static bool webFrame()
    {
        if SceneDemoWebUI.requestQuit
        {
            ret false
        }
        # 分辨率变更请求（JS setRes -> 事件线程写 pendingW/H，主线程执行）
        if SceneDemoWebUI.pendingW > 0 && SceneDemoWebUI.pendingH > 0
        {
            Int32 nw = SceneDemoWebUI.pendingW
            Int32 nh = SceneDemoWebUI.pendingH
            SceneDemoWebUI.pendingW = 0
            SceneDemoWebUI.pendingH = 0
            if nw != SceneDemo.renderW || nh != SceneDemo.renderH
            {
                if SceneDemo.rs.resize( nw, nh )
                {
                    if SceneDemo.pixels != 0
                    {
                        Memory.free( SceneDemo.pixels )
                    }
                    SceneDemo.pixels = Memory.alloc( nw * nh * 4 )
                    SceneDemo.renderW = nw
                    SceneDemo.renderH = nh
                    Console.println( "[scene][web] resize -> " + nw.toString() + "x" + nh.toString() )
                }
            }
        }
        # 场景切换请求（JS setScene）
        if SceneDemoWebUI.pendingScene >= 0
        {
            Int32 si = SceneDemoWebUI.pendingScene
            SceneDemoWebUI.pendingScene = -1
            SceneDemo.loadScene( si )
            SceneDemo.inMenu = false
        }
        # 相机写回（网页版无键鼠输入，用当前权威值；滚轮/拖拽预留）
        Float32 cx = SceneDemo.camX
        Float32 cy = SceneDemo.camY
        Float32_3 cc = Float32_3( cx, cy, 0.0f )
        SceneDemo.rs.cameraCenter = cc
        SceneDemo.rs.viewSize = SceneDemo.camView
        SceneDemo.rs.cameraEye = cc
        SceneDemo.rs.camYaw = SceneDemo.camYaw
        SceneDemo.rs.camPitch = SceneDemo.camPitch
        SceneDemo.rs.useViewRotation = true
        # 场景生命周期 + 同步（网页版只渲染核心场景：gizmo/FairyGUI 叠加
        # 走事件线程会触发 0xC0000005，属编辑器辅助层，H5 不需要）
        SceneDemo.sm.tick( -1.0f )
        SceneDemo.rs.sync( SceneDemo.sm.activeScene )
        # 渲染一帧到 RGBA8 像素块，再推给浏览器
        Int64 pp = SceneDemo.pixels
        if SceneDemo.rs.frame( 0.0f - 1.0f, pp )
        {
            SceneDemoWebUI.pushFrame( pp, SceneDemo.renderW, SceneDemo.renderH )
        }
        ret true
    }

    public static void run()
    {
        SceneDemo.sm = SceneManager()
        SceneDemo.sm.registerScript( "SphereMeshScript", SceneScriptFactories.makeSphereMesh )
        SceneDemo.sm.registerScript( "ShapeMeshScript", SceneScriptFactories.makeShapeMesh )
        SceneDemo.sm.registerScript( "SpinScript", SceneScriptFactories.makeSpin )
        SceneDemo.sm.registerScript( "ProbeScript", SceneScriptFactories.makeProbe )
        SceneDemo.sm.registerScript( "LightSwingScript", SceneScriptFactories.makeLightSwing )
        SceneDemo.sm.registerScript( "AxisGizmoScript", SceneScriptFactories.makeAxis )
        Console.println( "[scene] scripts=" + SceneDemo.sm.scriptTypeCount().toString() )
        SceneDemo.baseDir = SceneDemo.findSceneDir()
        Console.println( "[scene] scenes at " + SceneDemo.baseDir )
        SceneDemo.rs = RenderSystem()
        SceneDemo.rs.init( 480, 480 )
        # 编辑器 Gizmo 系统（默认 move 模式；G 键循环切模式）
        SceneDemo.gs = GizmoSystem()
        # Unity VolumeManager 同款：sync 每帧按相机位置 compute + applyPost
        # （场景里有 Volume 组件才生效，doc/14 §4）
        SceneDemo.rs.volumeSystem = VolumeSystem()
        Float32 cx = SceneDemo.camX
        Float32 cy = SceneDemo.camY
        Float32_3 cc = Float32_3( cx, cy, 0.0f )
        SceneDemo.rs.cameraCenter = cc
        SceneDemo.rs.viewSize = SceneDemo.camView
        SceneDemo.pixels = Memory.alloc( 480 * 480 * 4 )
        SceneDemo.initBallMesh()
        SceneDemo.initFairyUI()
        SceneDemo.initMenuUI()
        SceneDemo.loadScene( 4 )
        SceneDemo.inMenu = true
        QTHost.startHost( SceneDemo.frameTick, SceneDemo.toggleGizmoMenu )
    }
}
