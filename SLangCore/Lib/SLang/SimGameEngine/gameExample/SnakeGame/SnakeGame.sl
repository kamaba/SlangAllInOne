import SimGameEngine;
import Std;
import Math;
import Core;

# SnakeGame - greedy snake (QT window via QTHost, engine ortho bake render,
# InputSystem C state table). 2026-11-19: UI state machine (menu / playing /
# game-over overlays via QTHost, styled score bar, best-score tracking) +
# sound effects via SnakeSfx (SLangAudio one-shots). All state static; heavy
# math in C. Pitfall forms: no cross-module chains, consts never passed as
# args, loop compares use locals, triple && split. Methods ordered before
# run/start (single-pass call-link resolution: references must come after
# definitions).
public class SnakeGame
{
    static Int32 GRID = 16
    static Int32 CELL = 10
    static Int32 OUTW = 320
    static Int32 OUTH = 320
    static Int32 STEP_MS = 150

    static RenderSystem rs = null
    static Scene scene = null
    static MeshRef bgDarkRef = null
    static MeshRef bgLightRef = null
    static MeshRef snakeRef = null
    # RHI 动态网格槽只有 4 个（SLR_CUSTOM_MESHES=4）；烘焙组必须 ≤4。
    # 蛇头与蛇身共用同一材质组（同一颜色），避免第 5 组与棋盘深色组
    # 落在同一 slot 互相覆盖 —— 那会让食物（第 5 组）顶点覆盖棋盘、
    # 且食物因 z 相同被深度测试剔除而不显示。
    static MeshRef foodRef = null
    static Int64 pixels = 0
    static InputSystem input = null
    # 像素自检（首帧后第 30 帧打印一次采样点，验证 FairyUI 真渲染进画布）
    static Int32 dbgFrame = 0
    # 帧率显示（Ctrl+Home 切换菜单栏，菜单「显示帧率」切换 FPS label）
    # 每 500ms 统计一次帧数换算 FPS，避免每帧刷新文本
    static Int64 fpsWinMs = 0
    static Int32 fpsFrames = 0

    static List<Int32> body = List<Int32>( 0 )
    static Int32 dirX = 1
    static Int32 dirY = 0
    static Int32 pendX = 1
    static Int32 pendY = 0
    static Int32 foodIdx = 0
    static Int32 foodSeed = 12345
    static bool alive = true
    static Int32 moveAcc = 0
    static Int32 growLeft = 0
    static Int32 score = 0
    # 2026-11-19: UI 状态机（0 菜单 / 1 游戏 / 2 暂停 / 3 结束 / 4 排行榜）
    # + best 最高分 + 本局时间（PLAY 态累计，暂停冻结）
    static Int32 best = 0
    static Int32 state = 0
    static Int32 STATE_MENU = 0
    static Int32 STATE_PLAY = 1
    static Int32 STATE_PAUSED = 2
    static Int32 STATE_OVER = 3
    static Int32 STATE_RANK = 4
    static Int64 playMs = 0
    static Int64 lastTickMs = 0
    # 屏幕自动适配（2026-11-19，SceneDemo 动态分辨率同款）：每帧探测顶层
    # 窗口客户区，变化时重排 QT 控件（信息条/方形画布/覆盖层）并同步渲染
    # 分辨率（rs.resize + 像素块重分配）；画布恒方形 → aspect=1 不破 NDC。
    static Int32 renderW = 320
    static Int32 lastWinW = 0
    static Int32 lastWinH = 0

    # create a colored mesh node; returns its MeshRef so caller stores it.
    # (method call NOT used as an argument anywhere - results land in locals)
    static MeshRef makeNode( string name, Float32_3 color )
    {
        GameObject node = scene.createObject( name )
        node.layer = 0
        MeshRef mr = MeshRef()
        mr.meshKind = 1
        node.addComponent( mr )
        MaterialRef mat = MaterialRef()
        MaterialData md = MaterialData()
        md.color = color
        mat.material = md
        node.addComponent( mat )
        ret mr
    }

    static void buildNodes()
    {
        Float32_3 cDark = Float32_3( 0.10f, 0.12f, 0.10f )
        Float32_3 cLight = Float32_3( 0.17f, 0.20f, 0.17f )
        Float32_3 cBody = Float32_3( 0.20f, 0.75f, 0.30f )
        Float32_3 cFood = Float32_3( 0.95f, 0.30f, 0.25f )
        bgDarkRef = makeNode( "BGDark", cDark )
        bgLightRef = makeNode( "BGLight", cLight )
        snakeRef = makeNode( "SnakeBody", cBody )
        foodRef = makeNode( "SnakeFood", cFood )
    }

    static void spawnFood()
    {
        Int32 n = GRID * GRID
        Int32 cand = 0
        Int32 guard = 0
        while guard < n
        {
            foodSeed = foodSeed * 31 + 7
            Int32 m = foodSeed % n
            if m < 0
            {
                m = m + n
            }
            cand = m
            if !bodyHas( cand )
            {
                foodIdx = cand
                ret
            }
            guard = guard + 1
        }
        foodIdx = cand
    }

    static bool bodyHas( Int32 idx )
    {
        Int32 n = body.length
        Int32 i = 0
        Int32 hit = 0
        while i < n
        {
            Int32 v = body[i]
            if v == idx
            {
                hit = 1
                i = n
            }
            else
            {
                i = i + 1
            }
        }
        ret hit == 1
    }

    static void keyPressed( Int32 key )
    {
        EngineFfi.libInputSetKey( key, 1 )
    }

    static void keyReleased( Int32 key )
    {
        EngineFfi.libInputSetKey( key, 0 )
    }

    # 菜单「显示帧率」动作回调（SIG_TRIGGERED trampoline，无参 void）
    static void toggleFpsMenu()
    {
        QTHost.toggleFpsLabel()
    }

    # 2026-11-19 第四轮：QT 信息条移除，状态提示全部走 FairyGUI
    # （updateInfo/setInfo/lastInfo 撤销）

    # start a fresh round (FairyUI hud on, reset play clock, start jingle)
    static void startGame()
    {
        resetGame()
        state = STATE_PLAY
        playMs = 0
        SnakeFairy.setState( STATE_PLAY )
        SnakeSfx.startJingle()
    }

    # death transition: best 更新 + 死亡音效 + 记入排行榜 + 结束界面
    static void onDied()
    {
        state = STATE_OVER
        if score > best
        {
            best = score
        }
        SnakeSfx.die()
        Int32 sec = SystemConvertInt32( playMs / 1000 )
        SnakeFairy.recordScore( score, sec )
        SnakeFairy.setState( STATE_OVER )
    }

    # 2026-11-19 第五轮：键盘边沿改走引擎 InputSystem 的 wasPressed
    # （C 表按下沿 + 自动重复去重 + endFrame 清边沿），游戏侧不再手写
    # prev 边沿、不再直读 QT。

    static void frameTick()
    {
        # ── 统一输入管线（每帧帧首）：QT 事件已由桥写进引擎 C 表（键盘
        #    事件驱动），鼠标由桥采样注入；游戏侧只读引擎 InputSystem ──
        QTHost.pumpMouse()
        QTHost.pumpKeyboard()
        Int32 kUp = InputSystem.KEY_UP
        Int32 kDn = InputSystem.KEY_DOWN
        Int32 kLf = InputSystem.KEY_LEFT
        Int32 kRt = InputSystem.KEY_RIGHT
        Int32 kR = 82
        # Qt::Key_Return = 0x01000004，Key_Space = 0x20（菜单开始键）
        Int32 kEnt = 16777220
        Int32 kSpace = 32
        bool pUp = input.wasPressed( kUp )
        bool pDn = input.wasPressed( kDn )
        bool pLf = input.wasPressed( kLf )
        bool pRt = input.wasPressed( kRt )
        bool pR = input.wasPressed( kR )
        bool pEnt = input.wasPressed( kEnt )
        bool pSpace = input.wasPressed( kSpace )
        # ── 屏幕自动适配：窗口尺寸变化 → 重排控件 + 渲染分辨率跟随 ──
        bool winChanged = false
        Int32 ww = QTHost.windowWidth()
        Int32 wh = QTHost.windowHeight()
        if ww > 0
        {
            if ww != lastWinW || wh != lastWinH
            {
                winChanged = true
            }
        }
        if winChanged
        {
            lastWinW = ww
            lastWinH = wh
            # 方形画布 (10,10) 起步：边长 = min(ww,wh) - 20；下限 160 保证可玩
            Int32 side = ww - 20
            Int32 vs = wh - 20
            if vs < side
            {
                side = vs
            }
            if side < 160
            {
                side = 160
            }
            QTHost.layoutUi( side )
            # 渲染分辨率跟随画布（钳 128..1024；变化才重建，句柄保留）
            Int32 rw = side
            if rw < 128
            {
                rw = 128
            }
            if rw > 1024
            {
                rw = 1024
            }
            if rw != renderW
            {
                Int64 oldPix = pixels
                rs.resize( rw, rw )
                Memory.free( oldPix )
                Int64 np = Memory.alloc( rw * rw * 4 )
                pixels = np
                renderW = rw
            }
        }
        # ── Ctrl+F12 场景层级检视器（切换显示 + 选中轮询）──
        Int32 kF12 = InputSystem.KEY_F12
        Int32 kCtrl = InputSystem.KEY_CTRL
        if input.wasPressed( kF12 )
        {
            if input.isDown( kCtrl )
            {
                SceneInspector.toggle( scene )
            }
        }
        SceneInspector.poll()
        # ── Ctrl+Home 顶部菜单栏显示切换（菜单第一项「显示帧率」）──
        # 字面量 Qt::Key_Home = 0x01000010（与 QTHost.pumpKeyboard 同值；
        # 不走 InputSystem.KEY_HOME 常量以规避跨模块新字段的解析缓存依赖）
        Int32 kHome = 16777232
        if input.wasPressed( kHome )
        {
            if input.isDown( kCtrl )
            {
                QTHost.toggleMenuBar()
            }
        }
        # ── 帧率统计（每 500ms 换算 FPS，仅 label 显示时刷新文本）──
        Int64 nowMs = SystemTimerNowMillis()
        fpsFrames = fpsFrames + 1
        Int64 fpsSpan = nowMs - fpsWinMs
        if fpsSpan >= 500
        {
            if QTHost.fpsLabelVisible()
            {
                # 帧数 × 1000 / 毫秒 = FPS（Int64 除后转 Int32）
                Int64 fps64 = fpsFrames * 1000 / fpsSpan
                Int32 fps = SystemConvertInt32( fps64 )
                QTHost.setFpsText( "FPS: " + fps.toString() )
            }
            fpsFrames = 0
            fpsWinMs = nowMs
        }
        # ── 本局时间（PLAY 态累计；暂停/结束冻结；dt 钳制防卡顿跳变）──
        Int64 dt = nowMs - lastTickMs
        lastTickMs = nowMs
        if dt < 0
        {
            dt = 0
        }
        if dt > 200
        {
            dt = 200
        }
        if state == STATE_PLAY
        {
            playMs = playMs + dt
        }
        # ── 状态机：菜单（Enter/Space/开始按钮）→ 游戏（空格暂停）→
        #    结束（R 重开 / 返回按钮）→ 排行榜 ──
        if state == STATE_MENU
        {
            if pEnt || pSpace
            {
                startGame()
            }
        }
        if state == STATE_PLAY
        {
            if pSpace
            {
                state = STATE_PAUSED
                SnakeFairy.setState( STATE_PAUSED )
            }
        }
        if state == STATE_PAUSED
        {
            if pSpace
            {
                state = STATE_PLAY
                SnakeFairy.setState( STATE_PLAY )
            }
        }
        if state == STATE_OVER
        {
            if pR
            {
                startGame()
            }
        }
        # ── FairyGUI 鼠标交互（动作码：1 开始 2 排行榜 3 声音 4 背景乐
        #    5 退出 6 返回）──
        Int32 act = SnakeFairy.handleMouse( renderW, renderW )
        if act == 1
        {
            if state == STATE_MENU
            {
                startGame()
            }
        }
        if act == 2
        {
            if state == STATE_MENU
            {
                state = STATE_RANK
                SnakeFairy.setState( STATE_RANK )
            }
        }
        if act == 3
        {
            bool on1 = SnakeFairy.toggleSfx()
            SnakeSfx.setSfxEnabled( on1 )
        }
        if act == 4
        {
            bool on2 = SnakeFairy.toggleBgm()
            SnakeSfx.setBgmEnabled( on2 )
        }
        if act == 5
        {
            # HUD 右上「返回」按钮：回主界面（不再退出应用）
            if state == STATE_PLAY
            {
                state = STATE_MENU
                SnakeFairy.setState( STATE_MENU )
            }
            if state == STATE_PAUSED
            {
                state = STATE_MENU
                SnakeFairy.setState( STATE_MENU )
            }
        }
        if act == 6
        {
            if state == STATE_RANK
            {
                state = STATE_MENU
                SnakeFairy.setState( STATE_MENU )
            }
            if state == STATE_OVER
            {
                state = STATE_MENU
                SnakeFairy.setState( STATE_MENU )
            }
        }
        if state == STATE_PLAY
        {
            # 屏幕 Y 经 RHI 行翻转：grid y 增大 = 屏幕向上。
            # 故 ↑ 对应 dirY=+1（grid y 增），↓ 对应 dirY=-1；并禁止 180° 反向。
            if pUp
            {
                if dirY != 0 - 1
                {
                    pendX = 0
                    pendY = 1
                    SnakeSfx.move()
                }
            }
            if pDn
            {
                if dirY != 1
                {
                    pendX = 0
                    pendY = 0 - 1
                    SnakeSfx.move()
                }
            }
            if pLf
            {
                if dirX != 1
                {
                    pendX = 0 - 1
                    pendY = 0
                    SnakeSfx.move()
                }
            }
            if pRt
            {
                if dirX != 0 - 1
                {
                    pendX = 1
                    pendY = 0
                    SnakeSfx.move()
                }
            }
            moveAcc = moveAcc + 16
            if moveAcc >= STEP_MS
            {
                moveAcc = moveAcc - STEP_MS
                stepSnake()
            }
        }
        SnakeSfx.update()
        # Go3D：菜单态更新软渲染立方体（GoWrapper 内容源）
        if state == STATE_MENU
        {
            Int64 nowGo = SystemTimerNowMillis()
            Go3DDemo.update( nowGo )
        }
        rebuildVerts()
        rs.sync( scene )
        # FairyUI（引擎 UI 叠加相机 layer 31）：sync 之后、frame 之前提交
        SnakeFairy.draw( rs )
        if state == STATE_PLAY
        {
            SnakeFairy.updateHud( playMs, score )
        }
        if state == STATE_PAUSED
        {
            SnakeFairy.updateHud( playMs, score )
        }
        rs.frame( 0.0f, pixels )
        Int32 w2 = renderW
        QTHost.blit( pixels, w2, w2 )
        dbgFrame = dbgFrame + 1
        input.endFrame()
    }

    static void stepSnake()
    {
        dirX = pendX
        dirY = pendY
        Int32 head = body[0]
        Int32 hx = head % GRID
        Int32 hy = head / GRID
        Int32 nx = hx + dirX
        Int32 ny = hy + dirY
        if nx < 0
        {
            alive = false
        }
        if ny < 0
        {
            alive = false
        }
        if nx > GRID - 1
        {
            alive = false
        }
        if ny > GRID - 1
        {
            alive = false
        }
        if !alive
        {
            onDied()
            ret
        }
        Int32 nidx = ny * GRID + nx
        if bodyHas( nidx )
        {
            alive = false
            onDied()
            ret
        }
        body.insert( 0, nidx )
        if nidx == foodIdx
        {
            score = score + 10
            growLeft = growLeft + 1
            SnakeSfx.eat()
            spawnFood()
        }
        if growLeft > 0
        {
            growLeft = growLeft - 1
        }
        else
        {
            Int32 last = body.length - 1
            body.removeAt( last )
        }
        # 每步一次移动音（轻量 tick；转向另有轻音效）
        SnakeSfx.move()
    }

    static void rebuildVerts()
    {
        List<Float32_3> bd = List<Float32_3>( 0 )
        List<Float32_3> bl = List<Float32_3>( 0 )
        List<Float32_3> sn = List<Float32_3>( 0 )
        List<Float32_3> fd = List<Float32_3>( 0 )
        Int32 g2 = GRID
        Int32 gy = 0
        while gy < g2
        {
            Int32 gx = 0
            while gx < g2
            {
                Int32 checker = ( gx + gy ) % 2
                if checker == 0
                {
                    pushCell( bd, gx, gy )
                }
                else
                {
                    pushCell( bl, gx, gy )
                }
                gx = gx + 1
            }
            gy = gy + 1
        }
        # 蛇头与蛇身合并到同一顶点列表 —— 同材质同组，烘焙组总数 = 4
        # （棋盘深/浅 + 蛇 + 食物），与 RHI 的 4 个动态槽一一对应。
        Int32 i = 0
        Int32 n = body.length
        while i < n
        {
            Int32 idx = body[i]
            Int32 sx = idx % GRID
            Int32 sy = idx / GRID
            pushCell( sn, sx, sy )
            i = i + 1
        }
        Int32 fx = foodIdx % GRID
        Int32 fy = foodIdx / GRID
        pushCell( fd, fx, fy )
        bgDarkRef.setVertices( bd )
        bgLightRef.setVertices( bl )
        snakeRef.setVertices( sn )
        foodRef.setVertices( fd )
    }

    static void pushCell( List<Float32_3> sink, Int32 gx, Int32 gy )
    {
        Float32 fx = gx.toFloat32() * CELL.toFloat32()
        Float32 fy = gy.toFloat32() * CELL.toFloat32()
        Float32 cs = CELL.toFloat32()
        Float32 lx = fx
        Float32 ly = fy
        Float32 rx2 = fx + cs
        Float32 uy = fy + cs
        Float32 z = 0.0f
        Float32_3 a = Float32_3( lx, ly, z )
        Float32_3 b = Float32_3( lx, uy, z )
        Float32_3 c = Float32_3( rx2, uy, z )
        Float32_3 d = Float32_3( rx2, ly, z )
        sink.add( a )
        sink.add( b )
        sink.add( c )
        sink.add( a )
        sink.add( c )
        sink.add( d )
    }

    static void resetGame()
    {
        body.clear()
        body.add( 8 * GRID + 7 )
        body.add( 8 * GRID + 6 )
        body.add( 8 * GRID + 5 )
        dirX = 1
        dirY = 0
        pendX = 1
        pendY = 0
        alive = true
        growLeft = 2
        score = 0
        moveAcc = 0
        spawnFood()
    }

    # run/start MUST stay at class tail (single-pass call-link resolution:
    # QTHost.startHost references frameTick/keyPressed/keyReleased defined above)
    static void start()
    {
        rs = RenderSystem()
        rs.init( OUTW, OUTH )
        rs.cameraCenter = Float32_3( 80.0f, 80.0f, 0.0f )
        # viewSize = 纵向半高（Unity orthographicSize 语义）。100 → 世界可视
        # [−20,180]，16×16 网格（160）四周留 20 单位边距：顶部边距（≈48 设计
        # 像素）正好容纳 FairyGUI HUD 顶栏（44 设计像素），互不遮挡。
        rs.viewSize = 100.0f
        scene = Scene( "Snake" )
        buildNodes()
        input = InputSystem()
        # FairyUI 鼠标查询统一走引擎 InputSystem（注入引用）
        SnakeFairy.setInput( input )
        pixels = Memory.alloc( OUTW * OUTH * 4 )
        resetGame()
        # 音效初始化（无声卡 / 缺资源时静音降级，不阻断游戏）+ 背景乐
        SnakeSfx.init()
        SnakeSfx.setBgmEnabled( true )
        # FairyUI 菜单/HUD/排行榜（缺资源时降级：无 UI 但游戏可玩）
        SnakeFairy.load()
        # Go3D 演示：绑定 go3d 元素纹理（CPU 软渲染旋转立方体）
        Go3DDemo.attach( SnakeFairy.pkg() )
        state = STATE_MENU
        SnakeFairy.setState( STATE_MENU )
        QTHost.startHost( SnakeGame.frameTick, SnakeGame.keyPressed, SnakeGame.keyReleased, SnakeGame.toggleFpsMenu )
    }

    public static void run()
    {
        SnakeGame g = SnakeGame()
        g.start()
    }
}
