import SimGameEngine;
import Std;
import Math;
import Core;

# SnakeGame - greedy snake (QT window via QTHost, engine ortho bake render,
# InputSystem C state table). All state static; heavy math in C. Pitfall
# forms: no cross-module chains, consts never passed as args, loop compares
# use locals, triple && split. Methods ordered before run/start (single-pass
# call-link resolution: references must come after definitions).
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
    static string lastInfo = ""

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

    static void updateInfo()
    {
        string text = "Score: " + score.toString() + "    Len: " + body.length.toString()
        if !alive
        {
            text = text + "    GAME OVER - press R to restart"
        }
        if text != lastInfo
        {
            lastInfo = text
            QTHost.setInfo( text )
        }
    }

    # 轮询式按键边沿（绕开 SIG_KEY_* FFI trampoline 跨模块回调不稳）
    static bool prevUp = false
    static bool prevDn = false
    static bool prevLf = false
    static bool prevRt = false
    static bool prevR = false

    static void frameTick()
    {
        Int32 kUp = InputSystem.KEY_UP
        Int32 kDn = InputSystem.KEY_DOWN
        Int32 kLf = InputSystem.KEY_LEFT
        Int32 kRt = InputSystem.KEY_RIGHT
        Int32 kR = 82
        Int32 dUp = QTHost.keyDown( kUp )
        Int32 dDn = QTHost.keyDown( kDn )
        Int32 dLf = QTHost.keyDown( kLf )
        Int32 dRt = QTHost.keyDown( kRt )
        Int32 dR = QTHost.keyDown( kR )
        bool pUp = dUp == 1 && !prevUp
        bool pDn = dDn == 1 && !prevDn
        bool pLf = dLf == 1 && !prevLf
        bool pRt = dRt == 1 && !prevRt
        bool pR = dR == 1 && !prevR
        prevUp = dUp == 1
        prevDn = dDn == 1
        prevLf = dLf == 1
        prevRt = dRt == 1
        prevR = dR == 1
        # 屏幕 Y 经 RHI 行翻转：grid y 增大 = 屏幕向上。
        # 故 ↑ 对应 dirY=+1（grid y 增），↓ 对应 dirY=-1；并禁止 180° 反向。
        if pUp
        {
            if dirY != 0 - 1
            {
                pendX = 0
                pendY = 1
            }
        }
        if pDn
        {
            if dirY != 1
            {
                pendX = 0
                pendY = 0 - 1
            }
        }
        if pLf
        {
            if dirX != 1
            {
                pendX = 0 - 1
                pendY = 0
            }
        }
        if pRt
        {
            if dirX != 0 - 1
            {
                pendX = 1
                pendY = 0
            }
        }
        if pR
        {
            resetGame()
        }
        if alive
        {
            moveAcc = moveAcc + 16
            if moveAcc >= STEP_MS
            {
                moveAcc = moveAcc - STEP_MS
                stepSnake()
            }
        }
        rebuildVerts()
        rs.sync( scene )
        rs.frame( 0.0f, pixels )
        Int32 w2 = OUTW
        Int32 h2 = OUTH
        QTHost.blit( pixels, w2, h2 )
        SnakeGame.updateInfo()
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
            ret
        }
        Int32 nidx = ny * GRID + nx
        if bodyHas( nidx )
        {
            alive = false
            ret
        }
        body.insert( 0, nidx )
        if nidx == foodIdx
        {
            score = score + 10
            growLeft = growLeft + 1
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
        rs.viewSize = 80.0f
        scene = Scene( "Snake" )
        buildNodes()
        input = InputSystem()
        pixels = Memory.alloc( OUTW * OUTH * 4 )
        resetGame()
        QTHost.startHost( SnakeGame.frameTick, SnakeGame.keyPressed, SnakeGame.keyReleased )
    }

    public static void run()
    {
        SnakeGame g = SnakeGame()
        g.start()
    }
}
