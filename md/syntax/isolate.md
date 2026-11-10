# 隔离并发（isolate / spawn）

`isolate` 提供**线程级隔离并发**：用 `isolated spawn` 启动一个独立执行流（线程），它通过**通道（channel）**与**共享内存（shared memory）**两种方式与主线程 / 彼此通信。相比单线程协作式并发，isolate 适合 CPU 密集或需要真正并行的工作。

## 1. 三种通信机制

- **返回值通道**：`spawn` 的返回值就是被调函数**第一次 `reply`** 的内容。
- **显式通道**：`send(channel, value)` / `receive(channel)` 配对传递数据，通道有容量上限（默认 1024），满则阻塞。
- **共享内存**：`shared mem` / `shm` 在多个执行流间共享同一块内存，适合大块数据零拷贝交换。

> isolate 与「协程（Coroutine）」的区别：协程是单线程内的协作式切换；isolate 是真正的多线程并行。两者的选择见 [`coroutine.md`](./coroutine.md)。

## 2. 基础：spawn 一个函数

```sl
isolated spawn worker()
{
    # 这个线程里可以独立工作
    reply("done")        # 第一次 reply 即 spawn 的返回值
}

function main()
{
    var result = isolated spawn worker()
    Console.println(result)   # done
}

main()
```

- `isolated spawn 函数名(参数)` 启动一个线程执行该函数，调用点**立即拿到「第一次 `reply` 的值」作为返回**。
- 传入参数**最多 8 个**（超出会编译报错）。
- 函数体内可用全局 `reply` / `send` / `receive` / `join`。

## 3. 函数内联（inline spawn）

也可以不单独定义函数，直接把代码块写在 `isolated spawn { }` 里：

```sl
function main()
{
    var r = isolated spawn
    {
        # 线程体
        reply(compute())
    }
    Console.println(r)
}

main()
```

## 4. 线程生命周期

- 线程启动后独立运行，**不受外层函数退出影响**（会持续运行直到自身结束或出错）。
- 子线程里再 `isolated spawn` 会产生更深一层线程；`join()` 会等待**本层所有子线程**结束。
- 所有线程结束后，共享内存按引用计数自动回收。

## 5. 通道：send / receive / reply / join

```sl
isolated spawn producer()
{
    send("queue", 1)
    send("queue", 2)
    send("queue", 3)
    reply("produced")
}

isolated spawn consumer()
{
    var a = receive("queue")
    var b = receive("queue")
    var c = receive("queue")
    reply(a + b + c)
}
```

- `send(channel, value)`：向某条命名通道发送；`receive(channel)`：从该通道取一个值（无数据则阻塞等待）。
- `reply(value)`：向「调用方」回传；**第一个 reply 成为 spawn 的返回值**。
- `clear(channel)`：丢弃该通道里已排队但尚未接收的数据。
- `join()`：等待当前线程产生的所有子线程结束。
- 通道有容量上限，写满会阻塞直到有消费方取走。

## 6. 共享内存（shared memory）

当需要在执行流间共享大块数据而避免反复拷贝时，用共享内存：

> 用 `shared mem`（或 `shm`）声明一块被多个执行流共享的内存区域；该区域按**引用计数**管理：
> 所有引用它的执行流都结束后才真正释放，不会泄漏。具体申请、读写与同步 API 以 Core 标准库与运行文档为准
> （不同构建形态下可用形态可能不同）。

- 共享内存按**引用计数**管理：所有引用它的执行流都结束后才真正释放。
- 适合「生产者写入、消费者读取」的大数据交换；小数据优先用通道更直观。
- 共享内存不自带锁，多写竞争需要自行用 channel / 标志协调。

## 7. 异常传播

- 子线程中抛出的异常会**传播到调用方**：`spawn` 处会收到该异常，按普通异常规则处理（`try / catch`）。
- 共享内存已分配的情况下异常退出，引用计数归零后由运行时回收，不会泄漏。

## 8. 完整示例

```sl
isolated spawn sumWorker(int from, int to)
{
    int total = 0
    for (int i = from, i <= to, i = i + 1)
    {
        total = total + i
    }
    reply(total)
}

function main()
{
    var a = isolated spawn sumWorker(1, 100)
    var b = isolated spawn sumWorker(101, 200)
    Console.println("part1=" + a)     # 5050
    Console.println("part2=" + b)     # 15050
}

main()
```

> 运行 / 工程配置：并发相关开关与调度细节见 [`../project/`](../project/) 下的工程与运行文档。

## 9. 常见错误

- 参数超过 8 个：`Error isolated spawn 调用参数过多（最多 8 个）`。
- `send` / `receive` 不匹配导致死锁：确保每一对 `send` 都有对应的 `receive`，注意通道容量上限。
- 在子线程外使用 `reply` / `receive`：这些全局只在 `isolated spawn` 的函数体内可用。
- 误把 isolate 当协程：`isolate` 是真线程并行，协程是单线程协作；需要协作式切换请用 [`coroutine.md`](./coroutine.md)。
- 共享内存竞争：共享区无内置锁，多执行流同时写需自行协调。
