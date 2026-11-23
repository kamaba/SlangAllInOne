import Core;
import Std;

# ─────────────────────────────────────────────────────────────
# Tensora/Async.sl —— 协程 + Isolate 异步计算层
#
# 三层能力：
#   1. TensorJob（Future）：统一封装协程任务（Core.Task）与 Isolate 结果端口
#      （Std.ReceivePort），对外提供 result / tryResult / cancel 同一组接口。
#   2. Isolate 工作器：张量算子在后台 OS 线程执行，结果经 SendPort 回传。
#      Tensor 对象本身不可跨 isolate 发送，发送前拆为可发送的
#      dims(List<Int32>) + data(List<Float32>)，接收端重建（深拷贝语义）。
#      注意：当前 C VM 的 isolate 消息通道不支持 Array<T>，载荷一律用 List<T>。
#   3. 协调器：submit / matmulAsync 等提交入口，waitAll / waitAny 协作式
#      聚合（挂起当前协程，不阻塞 OS 线程）。
#
# 约定：所有等待操作须在协程上下文调用（root 直接调用时退化为阻塞等待）。
# ─────────────────────────────────────────────────────────────

#! 任务状态常量（与 TensorJob.status 对应）。 !#
public class AsyncStatus extends Object
{
    public static const Int32 Pending   = 0
    public static const Int32 Running   = 1
    public static const Int32 Done      = 2
    public static const Int32 Failed    = 3
    public static const Int32 Cancelled = 4
}

#! 执行模式常量：协程（同线程协作式）/ Isolate（后台线程隔离）。 !#
public class EComputeMode extends Object
{
    public static const Int32 Coro = 0
    public static const Int32 Iso  = 1
}

#! 内置异步算子编号。 !#
public class EAsyncOp extends Object
{
    public static const Int32 Add    = 1
    public static const Int32 Sub    = 2
    public static const Int32 Mul    = 3
    public static const Int32 MatMul = 4
    public static const Int32 Scale  = 5
    public static const Int32 Relu   = 6
}

# ───────────────────────── Future ────────────────────────────

#!
 * 异步计算句柄。由 TensorAsync 的提交方法返回；同一 job 只消费一次结果，
 * 之后 result()/tryResult() 均返回缓存的张量。
!#
public class TensorJob extends Object
{
    Int32 _mode = 0
    Int32 _status = 0
    object _task = null
    ReceivePort _port = null
    Isolate _isolate = null
    object _value = null

    public void _init_( Int32 mode )
    {
        this._mode = mode
        this._status = AsyncStatus.Pending
    }

    #! 绑定协程任务（内部入口，由 TensorAsync 调用）。 !#
    public void _attachTask( object task )
    {
        this._task = task
        this._status = AsyncStatus.Running
    }

    #! 绑定 isolate 与回传端口（内部入口，由 TensorAsync 调用）。 !#
    public void _attachIsolate( Isolate iso, ReceivePort port )
    {
        this._isolate = iso
        this._port = port
        this._status = AsyncStatus.Running
    }

    #! 任务状态，取 AsyncStatus 常量值。 !#
    get Int32 status()
    {
        ret this._status
    }

    get bool isDone()
    {
        ret this._status == AsyncStatus.Done
    }

    get bool isFailed()
    {
        ret this._status == AsyncStatus.Failed
    }

    #!
     * 阻塞当前协程直到任务完成，返回计算出的 Tensor（失败返回 null）。
     * 结果被缓存，重复调用返回同一张量。
    !#
    public object result()
    {
        if this._value != null
        {
            ret this._value
        }
        object raw = null
        if this._mode == EComputeMode.Coro
        {
            Task tq = this._task as Task
            if tq == null
            {
                this._status = AsyncStatus.Failed
                ret null
            }
            raw = tq.awaitTask()
        }
        else
        {
            if this._port == null
            {
                this._status = AsyncStatus.Failed
                ret null
            }
            raw = this._port.recv()
        }
        if raw == null
        {
            this._status = AsyncStatus.Failed
            ret null
        }
        List<object> rsp = raw as List<object>
        Tensor outTensor = TensorAsync.unpackTensor( rsp )
        this._value = outTensor
        this._status = AsyncStatus.Done
        ret this._value
    }

    #!
     * 非阻塞取结果：任务未完成返回 null；完成则返回 Tensor 并缓存。
     * 协程模式以 Task.status == 4（Dead）判定完成。
    !#
    public object tryResult()
    {
        if this._value != null
        {
            ret this._value
        }
        object raw = null
        if this._mode == EComputeMode.Coro
        {
            Task tq = this._task as Task
            if tq == null
            {
                ret null
            }
            if tq.status == 4
            {
                raw = tq.awaitTask()
            }
        }
        else
        {
            if this._port == null
            {
                ret null
            }
            raw = this._port.tryRecv()
        }
        if raw == null
        {
            ret null
        }
        List<object> rsp = raw as List<object>
        Tensor outTensor = TensorAsync.unpackTensor( rsp )
        this._value = outTensor
        this._status = AsyncStatus.Done
        ret this._value
    }

    #!
     * 请求取消。协程为协作式取消（下一调度点生效）；isolate 立即终止并
     * 关闭回传端口。已完成的任务返回 false。
    !#
    public bool cancel()
    {
        if this._status == AsyncStatus.Done
        {
            ret false
        }
        if this._mode == EComputeMode.Coro
        {
            Task tc = this._task as Task
            if tc == null
            {
                ret false
            }
            bool ok = tc.cancel()
            if ok
            {
                this._status = AsyncStatus.Cancelled
            }
            ret ok
        }
        if this._isolate != null
        {
            this._isolate.kill( 0 )
        }
        if this._port != null
        {
            this._port.close()
        }
        this._status = AsyncStatus.Cancelled
        ret true
    }
}

# ───────────────── 提交 / 协调 / 算子执行 ────────────────────

#!
 * Tensora 异步计算入口：提交、协调与内置算子。
 * 所有方法为静态方法；submit 可提交任意自定义闭包（协程模式）。
!#
public class TensorAsync extends Object
{
    #! ── 序列化：Tensor <-> 可发送消息 ── !#

    #! 张量打包为 [ dims:List<Int32>, data:List<Float32> ]（深拷贝）。 !#
    static List<object> packTensor( Tensor t )
    {
        List<object> p = new()
        Shape sh = t.shape()
        List<Int32> dims = new()
        for i = 0, i < sh.dims.length, i++
        {
            dims.add( sh.dims[i] )
        }
        p.add( dims )
        List<Float32> vals = new()
        Array<Float32> src = t.storage
        for i = 0, i < src.length, i++
        {
            vals.add( src[i] )
        }
        p.add( vals )
        ret p
    }

    #! 从打包消息重建张量（null 消息返回 null）。 !#
    static Tensor unpackTensor( List<object> p )
    {
        if p == null
        {
            ret null
        }
        List<Int32> dims = p._getItem_( 0 ) as List<Int32>
        List<Float32> vals = p._getItem_( 1 ) as List<Float32>
        if dims == null
        {
            ret null
        }
        if vals == null
        {
            ret null
        }
        Array<Int32> dimsArr = Array<Int32>( dims.length )
        for i = 0, i < dims.length, i++
        {
            dimsArr[i] = dims._getItem_( i )
        }
        Array<Float32> valsArr = Array<Float32>( vals.length )
        for i = 0, i < vals.length, i++
        {
            valsArr[i] = vals._getItem_( i )
        }
        Shape sh = Shape( dimsArr )
        Tensor outTensor = Tensor( valsArr, sh )
        ret outTensor
    }

    #! ── 算子 ── !#

    static Tensor execute( Int32 op, Tensor a, Tensor b, Float32 scale )
    {
        if op == EAsyncOp.Add
        {
            ret a.add( b )
        }
        if op == EAsyncOp.Sub
        {
            ret a.sub( b )
        }
        if op == EAsyncOp.Mul
        {
            ret a.mul( b )
        }
        if op == EAsyncOp.MatMul
        {
            ret a.matmul( b )
        }
        if op == EAsyncOp.Scale
        {
            ret a.scale( scale )
        }
        if op == EAsyncOp.Relu
        {
            ret Activation.relu( a )
        }
        ret a.clone()
    }

    #!
     * 执行作业体，返回打包结果。layout（List<object>，回传端口另参传入）：
     *   [0]=op [1]=打包的 a [2]=打包的 b（可 null）
     *   [3]=标量参数（单元素 List<Float32>）
    !#
    static object executeJob( object arg )
    {
        List<object> job = arg as List<object>
        if job == null
        {
            ret null
        }
        Int32 op = job._getItem_( 0 ) as Int32
        List<object> pa = job._getItem_( 1 ) as List<object>
        Tensor a = TensorAsync.unpackTensor( pa )
        if a == null
        {
            ret null
        }
        Tensor b = null
        bool needB = false
        if op == EAsyncOp.Add
        {
            needB = true
        }
        if op == EAsyncOp.Sub
        {
            needB = true
        }
        if op == EAsyncOp.Mul
        {
            needB = true
        }
        if op == EAsyncOp.MatMul
        {
            needB = true
        }
        if needB
        {
            b = TensorAsync.unpackTensor( job._getItem_( 2 ) as List<object> )
            if b == null
            {
                ret null
            }
        }
        List<Float32> sv = job._getItem_( 3 ) as List<Float32>
        Float32 sc = 0.0f
        if sv != null
        {
            sc = sv._getItem_( 0 )
        }
        Tensor r = TensorAsync.execute( op, a, b, sc )
        ret TensorAsync.packTensor( r )
    }

    #! Isolate worker 入口：执行作业并把打包结果送回请求方端口。 !#
    public static void tensorWorker( SendPort reply, List<object> job )
    {
        if reply == null
        {
            ret
        }
        object res = TensorAsync.executeJob( job )
        reply.send( res )
    }

    #! ── 提交 ── !#

    #!
     * 协程提交：在后台协作式任务中执行闭包 fn(arg)，返回 TensorJob。
     * fn 须返回打包张量（可用 TensorAsync.executeJob 形态）；建议直接用
     * 下方 matmulAsync / addAsync 等高层入口。
    !#
    public static TensorJob submit( Function fn, object arg )
    {
        TensorJob j = TensorJob( EComputeMode.Coro )
        Task t = spawn fn( arg )
        j._attachTask( t )
        ret j
    }

    #! 构造算子作业消息（op 编号 + 打包张量 + 标量），全部使用可发送的 List。 !#
    static List<object> makeJob( Int32 op, Tensor a, Tensor b, Float32 scale )
    {
        List<object> job = new()
        job.add( op )
        job.add( TensorAsync.packTensor( a ) )
        if b != null
        {
            job.add( TensorAsync.packTensor( b ) )
        }
        else
        {
            job.add( null )
        }
        List<Float32> sv = new()
        sv.add( scale )
        job.add( sv )
        ret job
    }

    #!
     * 按模式提交内置算子。mode 取 EComputeMode.Coro / Iso。
     * Isolate 模式下创建回传端口、启动后台 isolate，立即返回（不等待）。
    !#
    public static TensorJob submitOp( Int32 op, Tensor a, Tensor b, Float32 scale, Int32 mode )
    {
        List<object> job = TensorAsync.makeJob( op, a, b, scale )
        if mode == EComputeMode.Coro
        {
            function fn = function( object x )
            {
                ret TensorAsync.executeJob( x )
            }
            ret TensorAsync.submit( fn, job )
        }
        ReceivePort rp = ReceivePort()
        SendPort sp = rp.sendPort
        function worker = function( SendPort reply, List<object> payload )
        {
            TensorAsync.tensorWorker( reply, payload )
        }
        Isolate iso = Isolate.spawn( worker( sp, job ) )
        TensorJob j = TensorJob( EComputeMode.Iso )
        j._attachIsolate( iso, rp )
        ret j
    }

    #! ── 高层异步算子 ── !#

    public static TensorJob addAsync( Tensor a, Tensor b, Int32 mode )
    {
        ret TensorAsync.submitOp( EAsyncOp.Add, a, b, 0.0f, mode )
    }

    public static TensorJob subAsync( Tensor a, Tensor b, Int32 mode )
    {
        ret TensorAsync.submitOp( EAsyncOp.Sub, a, b, 0.0f, mode )
    }

    public static TensorJob mulAsync( Tensor a, Tensor b, Int32 mode )
    {
        ret TensorAsync.submitOp( EAsyncOp.Mul, a, b, 0.0f, mode )
    }

    public static TensorJob matmulAsync( Tensor a, Tensor b, Int32 mode )
    {
        ret TensorAsync.submitOp( EAsyncOp.MatMul, a, b, 0.0f, mode )
    }

    public static TensorJob scaleAsync( Tensor a, Float32 scale, Int32 mode )
    {
        ret TensorAsync.submitOp( EAsyncOp.Scale, a, null, scale, mode )
    }

    public static TensorJob reluAsync( Tensor a, Int32 mode )
    {
        ret TensorAsync.submitOp( EAsyncOp.Relu, a, null, 0.0f, mode )
    }

    #! ── 协调 ── !#

    #!
     * 等待全部任务完成，按输入顺序返回 Tensor 数组。
     * 协程模式下经 await 逐个收敛；isolate 模式下端口 recv 挂起当前协程。
    !#
    public static Array<Tensor> waitAll( Array<TensorJob> jobs )
    {
        TensorAsync.checkJobs( jobs )
        Array<Tensor> results = Array<Tensor>( jobs.length )
        for i = 0, i < jobs.length, i++
        {
            TensorJob j = jobs[i]
            results[i] = j.result() as Tensor
        }
        ret results
    }

    #!
     * 非阻塞轮询，返回第一个完成的任务（无完成则让出后继续轮询）。
     * 适用于协程与 isolate 混合的模式。
    !#
    public static TensorJob waitAny( Array<TensorJob> jobs )
    {
        TensorAsync.checkJobs( jobs )
        while ( true )
        {
            for i = 0, i < jobs.length, i++
            {
                TensorJob j = jobs[i]
                object v = j.tryResult()
                if v != null
                {
                    ret j
                }
            }
            Coroutine.delay( 1 )
        }
        ret null
    }

    #! 空/非法作业数组的统一防御（抛错由调用方处理，这里仅提前返回）。 !#
    static void checkJobs( Array<TensorJob> jobs )
    {
        if jobs == null
        {
            ret
        }
    }
}
