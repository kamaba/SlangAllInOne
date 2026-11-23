import Tensora;
import Core;
import Std;

# AsyncTest —— Tensora 异步计算层：协程 / Isolate / Future 协调
AsyncTest
{
    static check( string name, bool cond )
    {
        if cond
        {
            global.println( "[AsyncTest] " + name + " : OK" )
        }
        else
        {
            global.println( "[AsyncTest] " + name + " : FAIL" )
        }
    }

    static bool closeTo( Float32 a, Float32 b )
    {
        Float32 d = a - b
        if d < 0.0f
        {
            d = -d
        }
        ret d < 0.0001f
    }

    static Tensor mat( Array<Float32> v, Int32 r, Int32 c )
    {
        ret Tensor.matrix( v, r, c )
    }

    # ── 协程模式 ──────────────────────────────────────────
    static coroutineTest()
    {
        Tensor a = AsyncTest.mat( [ 1.0f, 2.0f, 3.0f, 4.0f ], 2, 2 )
        Tensor b = AsyncTest.mat( [ 10.0f, 20.0f, 30.0f, 40.0f ], 2, 2 )
        TensorJob j = TensorAsync.addAsync( a, b, EComputeMode.Coro )
        Tensor r = j.result() as Tensor
        AsyncTest.check( "coroutine add status", j.status == AsyncStatus.Done && j.isDone )
        AsyncTest.check( "coroutine add [0,0]=11", r != null && AsyncTest.closeTo( r.at( 0, 0 ), 11.0f ) )
        AsyncTest.check( "coroutine add [1,1]=44", r != null && AsyncTest.closeTo( r.at( 1, 1 ), 44.0f ) )
    }

    # ── Isolate 模式：后台线程矩阵乘 ──────────────────────
    static isolateTest()
    {
        Tensor a = AsyncTest.mat( [ 1.0f, 2.0f, 3.0f, 4.0f ], 2, 2 )
        Tensor b = AsyncTest.mat( [ 5.0f, 6.0f, 7.0f, 8.0f ], 2, 2 )
        TensorJob j = TensorAsync.matmulAsync( a, b, EComputeMode.Iso )
        Tensor r = j.result() as Tensor
        AsyncTest.check( "isolate matmul shape", r != null && r.rows() == 2 && r.cols() == 2 )
        AsyncTest.check( "isolate matmul [0,0]=19", r != null && AsyncTest.closeTo( r.at( 0, 0 ), 19.0f ) )
        AsyncTest.check( "isolate matmul [1,1]=50", r != null && AsyncTest.closeTo( r.at( 1, 1 ), 50.0f ) )
    }

    # ── 标量 / 激活算子 ───────────────────────────────────
    static scaleReluTest()
    {
        Tensor a = AsyncTest.mat( [ -1.0f, 2.0f, -3.0f, 4.0f ], 2, 2 )
        TensorJob js = TensorAsync.scaleAsync( a, 2.0f, EComputeMode.Iso )
        Tensor rs = js.result() as Tensor
        AsyncTest.check( "isolate scale", rs != null && AsyncTest.closeTo( rs.at( 0, 0 ), -2.0f ) && AsyncTest.closeTo( rs.at( 1, 1 ), 8.0f ) )

        TensorJob jr = TensorAsync.reluAsync( a, EComputeMode.Coro )
        Tensor rr = jr.result() as Tensor
        AsyncTest.check( "coroutine relu", rr != null && AsyncTest.closeTo( rr.at( 0, 0 ), 0.0f ) && AsyncTest.closeTo( rr.at( 1, 1 ), 4.0f ) )
    }

    # ── waitAll：混合模式聚合 ─────────────────────────────
    static waitAllTest()
    {
        Tensor a = AsyncTest.mat( [ 1.0f, 2.0f, 3.0f, 4.0f ], 2, 2 )
        Tensor b = AsyncTest.mat( [ 10.0f, 20.0f, 30.0f, 40.0f ], 2, 2 )
        Array<TensorJob> jobs = Array<TensorJob>( 2 )
        jobs[0] = TensorAsync.addAsync( a, b, EComputeMode.Coro )
        jobs[1] = TensorAsync.mulAsync( a, b, EComputeMode.Iso )
        Array<Tensor> rs = TensorAsync.waitAll( jobs )
        AsyncTest.check( "waitAll count", rs.length == 2 )
        AsyncTest.check( "waitAll add[0,0]=11", rs[0] != null && AsyncTest.closeTo( rs[0].at( 0, 0 ), 11.0f ) )
        AsyncTest.check( "waitAll mul[1,1]=160", rs[1] != null && AsyncTest.closeTo( rs[1].at( 1, 1 ), 160.0f ) )
    }

    # ── waitAny：混合模式首个完成 ─────────────────────────
    static waitAnyTest()
    {
        Tensor a = AsyncTest.mat( [ 1.0f, 2.0f, 3.0f, 4.0f ], 2, 2 )
        Array<TensorJob> jobs = Array<TensorJob>( 2 )
        jobs[0] = TensorAsync.scaleAsync( a, 1.0f, EComputeMode.Coro )
        jobs[1] = TensorAsync.scaleAsync( a, 2.0f, EComputeMode.Iso )
        TensorJob winner = TensorAsync.waitAny( jobs )
        AsyncTest.check( "waitAny returns done job", winner != null && winner.isDone )
    }

    # ── 取消与结果缓存 ────────────────────────────────────
    static cancelTest()
    {
        Tensor a = AsyncTest.mat( [ 1.0f, 2.0f, 3.0f, 4.0f ], 2, 2 )
        TensorJob j = TensorAsync.addAsync( a, a, EComputeMode.Coro )
        bool ok = j.cancel()
        AsyncTest.check( "cancel accepted or finished", ok || j.isDone )
    }

    static tryResultTest()
    {
        Tensor a = AsyncTest.mat( [ 1.0f, 2.0f, 3.0f, 4.0f ], 2, 2 )
        TensorJob j = TensorAsync.addAsync( a, a, EComputeMode.Coro )
        Tensor r = j.result() as Tensor
        object cached = j.tryResult()
        Tensor c = cached as Tensor
        AsyncTest.check( "tryResult cached", c != null && AsyncTest.closeTo( c.at( 0, 0 ), 2.0f ) && r != null )
    }

    static fun()
    {
        global.println( "===== AsyncTest =====" )
        AsyncTest.coroutineTest()
        AsyncTest.isolateTest()
        AsyncTest.scaleReluTest()
        AsyncTest.waitAllTest()
        AsyncTest.waitAnyTest()
        AsyncTest.cancelTest()
        AsyncTest.tryResultTest()
    }
}
