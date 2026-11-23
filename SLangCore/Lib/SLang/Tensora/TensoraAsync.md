# Tensora 异步计算

Tensora 提供两套异步执行方式与统一的 Future 句柄：

| 模式 | 常量 | 执行位置 | 适用场景 |
|------|------|----------|----------|
| 协程 | `EComputeMode.Coro` | 同一 OS 线程，协作式调度 | 细粒度算子、需要频繁 `yield` / 等待、开销敏感 |
| Isolate | `EComputeMode.Iso` | 独立 OS 线程 + 独立 VM 实例 | CPU 密集大张量计算，需与主线程并行 |

两种方式返回同一种句柄 `TensorJob`，可用同一组方法等待、轮询、取消。

## 常量

| 类 | 常量 | 值 | 说明 |
|----|------|----|------|
| `EComputeMode` | `Coro` / `Iso` | 0 / 1 | 提交时的执行模式 |
| `AsyncStatus` | `Pending` / `Running` / `Done` / `Failed` / `Cancelled` | 0..4 | 任务状态 |
| `EAsyncOp` | `Add` / `Sub` / `Mul` / `MatMul` / `Scale` / `Relu` | 1..6 | 内置算子编号（一般无需直接使用） |

## 提交算子

```sl
public static TensorJob addAsync( Tensor a, Tensor b, Int32 mode )
public static TensorJob subAsync( Tensor a, Tensor b, Int32 mode )
public static TensorJob mulAsync( Tensor a, Tensor b, Int32 mode )
public static TensorJob matmulAsync( Tensor a, Tensor b, Int32 mode )
public static TensorJob scaleAsync( Tensor a, Float32 scale, Int32 mode )
public static TensorJob reluAsync( Tensor a, Int32 mode )
public static TensorJob submitOp( Int32 op, Tensor a, Tensor b, Float32 scale, Int32 mode )
```

提交是**非阻塞**的：调用后立即返回 `TensorJob`，计算在后台进行。

## 使用示例

```sl
import Tensora

# 协程模式：两个张量相加
Tensor a = Tensor.matrix( [ 1.0f, 2.0f, 3.0f, 4.0f ], 2, 2 )
Tensor b = Tensor.matrix( [ 10.0f, 20.0f, 30.0f, 40.0f ], 2, 2 )
TensorJob j1 = TensorAsync.addAsync( a, b, EComputeMode.Coro )
Tensor r1 = j1.result() as Tensor        # 挂起当前协程直到完成

# Isolate 模式：后台线程矩阵乘
TensorJob j2 = TensorAsync.matmulAsync( a, b, EComputeMode.Iso )
Tensor r2 = j2.result() as Tensor
```

### 聚合多个任务

```sl
Array<TensorJob> jobs = Array<TensorJob>( 2 )
jobs[0] = TensorAsync.addAsync( a, b, EComputeMode.Coro )
jobs[1] = TensorAsync.matmulAsync( a, b, EComputeMode.Iso )

Array<Tensor> all = TensorAsync.waitAll( jobs )   # 按输入顺序返回结果
TensorJob first = TensorAsync.waitAny( jobs )     # 第一个完成的任务
```

`waitAll` / `waitAny` 支持两种模式混合，等待期间挂起当前协程而不是阻塞 OS 线程。

### 轮询与取消

```sl
object ready = j2.tryResult()       # 未完成返回 null，完成返回 Tensor
if ready != null
{
    Tensor done = ready as Tensor
}
j1.cancel()                         # 协程协作式取消 / isolate 立即终止
```

## TensorJob 接口

| 成员 | 签名 | 说明 |
|------|------|------|
| 状态 | `get Int32 status()` | 取 `AsyncStatus` 常量值 |
| 判定 | `get bool isDone()` / `get bool isFailed()` | 完成 / 失败判定 |
| 等待 | `public object result()` | 阻塞当前协程直到完成，返回 `Tensor`；失败返回 `null` |
| 轮询 | `public object tryResult()` | 非阻塞；未完成返回 `null` |
| 取消 | `public bool cancel()` | 已完成任务返回 `false` |

结果会被缓存：同一 `TensorJob` 重复调用 `result()` / `tryResult()` 返回同一张量，不会重复消费。

## 自定义协程任务

```sl
public static TensorJob submit( Function fn, object arg )
```

`fn` 须返回一个打包张量（结构为 `[ dims:List<Int32>, data:List<Float32> ]`）。一般业务直接使用上面的内置算子入口即可。

## 注意事项与已知坑

1. **跨 Isolate 的载荷只能用 `List<T>`**。当前版本 isolate 消息通道不支持 `Array<T>`，发送 `Array<T>` 会导致进程直接退出且无错误输出。Tensor 对象本身也不能直接发送——`TensorAsync` 已自动完成拆包与重建，调用方无需处理。
2. **深拷贝语义**。传进 isolate 的张量在 worker 中是副本，worker 侧修改不会影响原张量；结果同样以副本回传。大张量会有额外拷贝与序列化开销。
3. **等待位置**。`result()` / `waitAll()` / `waitAny()` 建议在协程上下文中调用；在普通入口直接调用会退化为阻塞等待。
4. **小算子不必开 Isolate**。线程创建 + 消息序列化成本远高于几元素张量的计算成本，小数据优先 `EComputeMode.Coro`。
5. **取消是协作式的**。协程在下一个调度点才响应取消；已经完成的任务 `cancel()` 返回 `false`。Isolate 模式会立即终止后台线程并关闭回传端口，之后不要再对该任务调用 `result()`。
6. **Isolate 入口限制**。自定义 isolate 入口只能是闭包或静态函数，且捕获环境必须全部可发送（数值、字符串、`List` / `Map` / `Set`、`SendPort`、`Capability` 等）；不要捕获 `ReceivePort` 或张量对象。
