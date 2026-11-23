import SimGameEngine;
import Std;
import Math;
import Core;

# SnakeGameBehaviour - web 版游戏逻辑层（2026-11-22 架构纠正）。
# 只写"使用 SimGameEngine 的逻辑"：Behaviour 生命周期（Application.tick
# 驱动）+ InputSystem 输入 + EngineTime 统一时间 + RenderSystem 场景 +
# FairyGUI（SnakeFairy）UI + SLangAudio（SnakeSfx）音效。
# 不出现：宿主循环（WebHost 泵）、像素呈现（sle_web_blit 归宿主）、
# 帧协议、QT 桥 —— 与桌面版 SnakeGame.sl 同构但宿主解耦。
#
# 移植自桌面 SnakeGame.sl：棋盘烘焙网格（checkerboard 双组）+ 蛇/食物
# 顶点动态重建；RHI 动态网格槽 4 个 → 烘焙组必须 ≤4（蛇头蛇身同组）。
# SL 坑位（project_memory）：方法按依赖顺序排（单趟调用链解析）；
# 循环比较用局部变量；三重 && 拆分；常量不做实参。
public class SnakeGameBehaviour extends Behaviour
{
    # ── 引擎系统（宿主 WebHost 注入，游戏层不创建）──────────
    # 注意：Behaviour 子类上的【实例字段 + 跨模块类型】成员解析在
    # MetaCore 阶段失败（doc/10 §6 跨模块基类槽位问题）——沿用桌面版
    # SnakeGame.sl 的成熟形态：static 字段。
    public static RenderSystem rs = null
    public static InputSystem input = null
    public static Scene scene = null

    # ── 游戏常量（与桌面版一致）────────────────────────────
    static Int32 GRID = 16
    static Int32 CELL = 10
    static Int32 STEP_MS = 150

    # ── 场景烘焙节点 ───────────────────────────────────────
    static MeshRef bgDarkRef = null
    static MeshRef bgLightRef = null
    static MeshRef snakeRef = null
    static MeshRef foodRef = null

    # ── 游戏状态 ──────────────────────────────────────────
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
    static Int32 best = 0
    # UI 状态机（0 菜单 / 1 游戏 / 2 暂停 / 3 结束 / 4 排行榜）
    static Int32 state = 0
    static Int32 STATE_MENU = 0
    static Int32 STATE_PLAY = 1
    static Int32 STATE_PAUSED = 2
    static Int32 STATE_OVER = 3
    static Int32 STATE_RANK = 4
    static Int64 playMs = 0

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

    static void startGame()
    {
        resetGame()
        state = STATE_PLAY
        playMs = 0
        SnakeFairy.setState( STATE_PLAY )
        SnakeSfx.startJingle()
    }

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
        SnakeSfx.move()
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

    # ── FairyUI 鼠标动作分派（返回码语义见 SnakeFairy.handleMouse）──
    static void mouseAct( Int32 act )
    {
        if act == 1
        {
            if state == STATE_MENU
            {
                startGame()
            }
            if state == STATE_OVER
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
            SnakeFairy.toggleSfx()
        }
        if act == 4
        {
            SnakeFairy.toggleBgm()
        }
        if act == 5
        {
            if state == STATE_PLAY || state == STATE_PAUSED
            {
                state = STATE_RANK
                SnakeFairy.setState( STATE_RANK )
            }
        }
        if act == 6
        {
            if state == STATE_RANK
            {
                state = STATE_MENU
                SnakeFairy.setState( STATE_MENU )
            }
        }
    }

    # ── 生命周期：start（首帧前）/ update（每帧）───────────
    override void awake()
    {
        Console.println( "[SnakeGameBehaviour] awake (hook dispatch live)" )
    }

    override void start()
    {
        Console.println( "[SnakeGameBehaviour] start begin (scene ready=" +
            ( scene != null ).toString() + ")" )
        buildNodes()
        # FairyUI 鼠标查询统一走引擎 InputSystem（注入引用）
        SnakeFairy.setInput( input )
        resetGame()
        # 音效（无声卡/缺资源静音降级，不阻断游戏）+ 背景乐
        SnakeSfx.init()
        SnakeSfx.setBgmEnabled( true )
        # FairyUI 菜单/HUD/排行榜（缺资源降级：无 UI 但游戏可玩）
        SnakeFairy.load()
        state = STATE_MENU
        SnakeFairy.setState( STATE_MENU )
        Console.println( "[SnakeGameBehaviour] ready (menu)" )
    }
    override void update()
    {
        # ── 输入边沿（引擎 InputSystem C 表；JS 宿主每事件注入）──
        Int32 kUp = InputSystem.KEY_UP
        Int32 kDn = InputSystem.KEY_DOWN
        Int32 kLf = InputSystem.KEY_LEFT
        Int32 kRt = InputSystem.KEY_RIGHT
        Int32 kR = 82
        Int32 kEnt = 16777220
        Int32 kSpace = 32
        bool pUp = input.wasPressed( kUp )
        bool pDn = input.wasPressed( kDn )
        bool pLf = input.wasPressed( kLf )
        bool pRt = input.wasPressed( kRt )
        bool pR = input.wasPressed( kR )
        bool pEnt = input.wasPressed( kEnt )
        bool pSpace = input.wasPressed( kSpace )
        # ── 统一时间：EngineTime.deltaTime（Application.tick 实测秒）──
        Int32 dtMs = SystemConvertInt32( EngineTime.deltaTime * 1000.0f )
        Int64 dtL = SystemConvertInt64( dtMs )
        # ── FairyUI 鼠标（引擎输入表坐标；JS 侧 +10 补偿桌面布局偏移）──
        Int32 act = SnakeFairy.handleMouse( 320, 320 )
        mouseAct( act )
        # ── 状态机 ────────────────────────────────────────────
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
            # 步进累积（统一时间驱动；单 if 与桌面帧节奏一致）
            moveAcc = moveAcc + dtMs
            if moveAcc >= STEP_MS
            {
                moveAcc = moveAcc - STEP_MS
                stepSnake()
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
        if state == STATE_PLAY || state == STATE_PAUSED
        {
            playMs = playMs + dtL
        }
        SnakeSfx.update()
        rebuildVerts()
        # 引擎渲染数据收集 + FairyUI 叠加相机提交（sync 后、frame 前）
        rs.sync( scene )
        SnakeFairy.draw( rs )
        if state == STATE_PLAY
        {
            SnakeFairy.updateHud( playMs, score )
        }
        if state == STATE_PAUSED
        {
            SnakeFairy.updateHud( playMs, score )
        }
    }
}
