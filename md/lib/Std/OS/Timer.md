# OS/Timer.sl

> 源文件：`OS/Timer.sl`

## class `Timer`

- **说明**：Timer 提供高精度时钟和延时功能，类似 Dart 的 Stopwatch、C# 的 Stopwatch、Swift 的 DispatchSourceTimer 用法: OS.Timer t = new() t.start() ... 执行代码 ... Int64 elapsed = t.elapsed Console.println("耗时: " + elapsed.toString() + "ms") OS.Timer.sleep(500)  # 阻塞当前线程 500ms；协程内非阻塞等待请用 Coroutine.delay Int64 now = OS.Timer.now()  # Unix 毫秒时间戳 Int64 clock = OS.Timer.clock()  # 高精度单调时钟

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `Int64 _startMillis = 0` | 单调时钟起点（毫秒） |
| 字段 | `Int64 _stopMillis = 0` | 停止时记录的终点 |
| 字段 | `bool _isRunning = false` | 是否正在运行 |
| 方法 | `Int64 clock()` | 高精度单调时钟（毫秒），用于基准测试 类似 C# Stopwatch.GetTimestamp() / Dart DateTime.now().millisecondsSinceEpoch |
| 方法 | `Int64 now()` | Unix 时间戳（毫秒） 类似 C# DateTimeOffset.UtcNow.ToUnixTimeMilliseconds() / Dart DateTime.now().millisecondsSinceEpoch |
| 方法 | `void sleep(int milliseconds)` | 真阻塞睡眠指定毫秒数：冻结调用线程（单线程 VM 下会连带暂停协程调度器） 类似 C# Thread.Sleep(ms) / Swift Thread.sleep(for:) 协程内非阻塞等待请用 Coroutine.delay(ms) |
| 方法 | `void start()` | 开始计时 类似 C# Stopwatch.Start() / Dart Stopwatch.start() |
| 方法 | `void stop()` | 停止计时 类似 C# Stopwatch.Stop() / Dart Stopwatch.stop() |
| 方法 | `void reset()` | 重置计时器 类似 C# Stopwatch.Reset() / Dart Stopwatch.reset() |
| 方法 | `void restart()` | 重启计时器（等价于 reset + start） 类似 C# Stopwatch.Restart() |
| 属性 | `get Int64 elapsed()` | 已耗时（毫秒） 如果正在运行，返回从 start 到当前的毫秒数 如果已停止，返回从 start 到 stop 的毫秒数 类似 C# Stopwatch.ElapsedMilliseconds / Dart Stopwatch.elapsedMilliseconds |
| 属性 | `get bool isRunning()` | 是否正在运行 类似 C# Stopwatch.IsRunning / Dart Stopwatch.isRunning |
