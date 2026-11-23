import Std;
import Core;

# SnakeGameWeb - browser (WebGL + WASM) port of the SnakeGame core gameplay.
# Runs inside the ASYNCIFY wasm VM (csimple_lang_async): OS.Timer.sleep
# yields to the JS event loop, so the host page renders WebGL frames from
# the printed lines and feeds keyboard input through a MEMFS file.
#
# Channels (see web/game.js):
#   input  /work/snake/input.keys - JS appends key chars (U/D/L/R/S/P/Q),
#          SL consumes them each tick then truncates the file to empty.
#   output one "F|..." frame line per tick via Console.println (JS receives
#          it through the Module.print line callback):
#            F|state|score|len|fx,fy|x1,y1;x2,y2;...|evt
#          state 0 menu / 1 play / 2 paused / 3 over;
#          evt: "" none / M move step / E eat / D die / S round start.
#          Q quits the loop (main returns -> callMain returns; used by the
#          Node smoke test).
#
# Pitfall forms mirrored from desktop SnakeGame.sl: all-static members with
# explicit initializers, Int32 (not int), method names avoid get/set/data/
# label, array subscripts copied to locals, methods ordered before run()
# (single-pass call-link resolution: references must come after definitions).
public class SnakeGameWeb
{
    static Int32 GRID = 16
    static Int32 STEP_MS = 150
    static Int32 FRAME_MS = 16
    static string INPUT_PATH = "/work/snake/input.keys"

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
    static Int32 state = 0
    static Int32 STATE_MENU = 0
    static Int32 STATE_PLAY = 1
    static Int32 STATE_PAUSED = 2
    static Int32 STATE_OVER = 3
    static bool quitFlag = false
    static string lastEvt = ""
    static Int64 lastLoopMs = 0

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

    static void emitFrame( string evt )
    {
        string line = "F|" + state.toString() + "|" + score.toString() + "|" + body.length.toString()
        Int32 fx = foodIdx % GRID
        Int32 fy = foodIdx / GRID
        line = line + "|" + fx.toString() + "," + fy.toString() + "|"
        Int32 i = 0
        Int32 n = body.length
        while i < n
        {
            Int32 idx = body[i]
            Int32 sx = idx % GRID
            Int32 sy = idx / GRID
            line = line + sx.toString() + "," + sy.toString()
            if i < n - 1
            {
                line = line + ";"
            }
            i = i + 1
        }
        line = line + "|" + evt
        Console.println( line )
    }

    static void startGame()
    {
        resetGame()
        state = STATE_PLAY
        lastEvt = "S"
    }

    static void onDied()
    {
        state = STATE_OVER
        if score > best
        {
            best = score
        }
        lastEvt = "D"
    }

    static void stepSnake()
    {
        # plain move evt first; eat/die below overwrite it in the same step
        lastEvt = "M"
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
            lastEvt = "E"
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

    static void applyInput()
    {
        if !File.exists( INPUT_PATH )
        {
            ret
        }
        string keys = File.readAllText( INPUT_PATH )
        File.writeAllText( INPUT_PATH, "" )
        UInt8Array bytes = keys.toUInt8Array()
        Int32 n = bytes.length
        Int32 i = 0
        while i < n
        {
            Int32 c = bytes[i]
            # Q(81) - quit: host/smoke asks the VM to finish
            if c == 81
            {
                quitFlag = true
            }
            # S(83) - start (menu) / restart (over)
            if c == 83
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
            # P(80) - pause toggle (nested else: two flat ifs would toggle
            # twice within the same key and net to zero)
            if c == 80
            {
                if state == STATE_PLAY
                {
                    state = STATE_PAUSED
                }
                else
                {
                    if state == STATE_PAUSED
                    {
                        state = STATE_PLAY
                    }
                }
            }
            # arrows only in PLAY (desktop parity), 180-degree reversal banned
            if state == STATE_PLAY
            {
                # U(85) up: screen y flips through the render readback, so
                # grid y grows upward (desktop line-mapping identical)
                if c == 85
                {
                    if dirY != 0 - 1
                    {
                        pendX = 0
                        pendY = 1
                    }
                }
                # D(68) down
                if c == 68
                {
                    if dirY != 1
                    {
                        pendX = 0
                        pendY = 0 - 1
                    }
                }
                # L(76) left
                if c == 76
                {
                    if dirX != 1
                    {
                        pendX = 0 - 1
                        pendY = 0
                    }
                }
                # R(82) right
                if c == 82
                {
                    if dirX != 0 - 1
                    {
                        pendX = 1
                        pendY = 0
                    }
                }
            }
            i = i + 1
        }
    }

    public static void run()
    {
        resetGame()
        state = STATE_MENU
        emitFrame( "" )
        lastLoopMs = OS.Timer.clock()
        bool running = true
        while running
        {
            applyInput()
            if quitFlag
            {
                running = false
            }
            else
            {
                # real-clock dt accumulation (desktop parity): sleep jitter on
                # the wasm side must not scale the snake step rate
                Int64 nowMs = OS.Timer.clock()
                Int64 dt = nowMs - lastLoopMs
                lastLoopMs = nowMs
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
                    moveAcc = moveAcc + SystemConvertInt32( dt )
                    if moveAcc >= STEP_MS
                    {
                        moveAcc = moveAcc - STEP_MS
                        stepSnake()
                    }
                }
                emitFrame( lastEvt )
                lastEvt = ""
                OS.Timer.sleep( FRAME_MS )
            }
        }
        Console.println( "BYE" )
    }
}
