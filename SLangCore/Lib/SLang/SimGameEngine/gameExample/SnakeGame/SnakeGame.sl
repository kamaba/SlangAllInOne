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
    static MeshRef bgRef = null
    static MeshRef snakeRef = null
    static MeshRef foodRef = null
    static Int64 pixels = 0
    static InputSystem input = null

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

    static void buildNodes()
    {
        GameObject bgNode = scene.createObject( "SnakeBG" )
        bgNode.layer = 0
        bgRef = MeshRef()
        bgRef.meshKind = 1
        bgNode.addComponent( bgRef )
        MaterialRef bmr = MaterialRef()
        MaterialData bmd = MaterialData()
        Float32_3 bcol = Float32_3( 0.12f, 0.14f, 0.12f )
        bmd.color = bcol
        bmr.material = bmd
        bgNode.addComponent( bmr )
        GameObject snNode = scene.createObject( "SnakeBody" )
        snNode.layer = 0
        snakeRef = MeshRef()
        snakeRef.meshKind = 1
        snNode.addComponent( snakeRef )
        MaterialRef smr = MaterialRef()
        MaterialData smd = MaterialData()
        Float32_3 scol = Float32_3( 0.2f, 0.85f, 0.3f )
        smd.color = scol
        smr.material = smd
        snNode.addComponent( smr )
        GameObject fdNode = scene.createObject( "SnakeFood" )
        fdNode.layer = 0
        foodRef = MeshRef()
        foodRef.meshKind = 1
        fdNode.addComponent( foodRef )
        MaterialRef fmr = MaterialRef()
        MaterialData fmd = MaterialData()
        Float32_3 fcol = Float32_3( 0.9f, 0.25f, 0.2f )
        fmd.color = fcol
        fmr.material = fmd
        fdNode.addComponent( fmr )
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

    static void frameTick()
    {
        Int32 kUp = InputSystem.KEY_UP
        Int32 kDn = InputSystem.KEY_DOWN
        Int32 kLf = InputSystem.KEY_LEFT
        Int32 kRt = InputSystem.KEY_RIGHT
        if input.wasPressed( kUp )
        {
            if dirY != 1
            {
                pendX = 0
                pendY = 0 - 1
            }
        }
        if input.wasPressed( kDn )
        {
            if dirY != 0 - 1
            {
                pendX = 0
                pendY = 1
            }
        }
        if input.wasPressed( kLf )
        {
            if dirX != 1
            {
                pendX = 0 - 1
                pendY = 0
            }
        }
        if input.wasPressed( kRt )
        {
            if dirX != 0 - 1
            {
                pendX = 1
                pendY = 0
            }
        }
        Int32 kR = 82
        if input.wasPressed( kR )
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
        List<Float32_3> bg = List<Float32_3>( 0 )
        List<Float32_3> sn = List<Float32_3>( 0 )
        List<Float32_3> fd = List<Float32_3>( 0 )
        Int32 g2 = GRID
        Int32 gy = 0
        while gy < g2
        {
            Int32 gx = 0
            while gx < g2
            {
                pushCell( bg, gx, gy )
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
        bgRef.setVertices( bg )
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
