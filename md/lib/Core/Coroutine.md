# Coroutine.sl

> 源文件：`Coroutine.sl`

## class `CoroutineStatus`

- **说明**：SLang 标准库类型 CoroutineStatus（详见源文件）。

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `public static const Int32 Created   = 0` | 字段 static（类型见签名）。 |
| 字段 | `public static const Int32 Ready     = 1` | 字段 static（类型见签名）。 |
| 字段 | `public static const Int32 Running   = 2` | 字段 static（类型见签名）。 |
| 字段 | `public static const Int32 Suspended = 3` | 字段 static（类型见签名）。 |
| 字段 | `public static const Int32 Dead      = 4` | 字段 static（类型见签名）。 |

## class `CoroutineBlockReason`

- **说明**：SLang 标准库类型 CoroutineBlockReason（详见源文件）。

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `public static const Int32 None  = 0` | 字段 static（类型见签名）。 |
| 字段 | `public static const Int32 Yield = 1` | 字段 static（类型见签名）。 |
| 字段 | `public static const Int32 Sched = 2` | 字段 static（类型见签名）。 |
| 字段 | `public static const Int32 Await = 3` | 字段 static（类型见签名）。 |
| 字段 | `public static const Int32 Delay = 4` | 字段 static（类型见签名）。 |
| 字段 | `public static const Int32 IO    = 5` | 字段 static（类型见签名）。 |

## class `Task`

- **说明**：SLang 标准库类型 Task（详见源文件）。

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `Int64 _handle = 0` | 字段 _handle（类型见签名）。 |
| 方法 | `object awaitTask()` | 运行 / 调用（awaitTask）。 |
| 方法 | `bool cancel()` | 判断状态是否（cancel）。 |
| 属性 | `get Int32 status()` | 获取 status 的值。 |
| 属性 | `get Int32 blockedReason()` | 获取 blockedReason 的值。 |
| 属性 | `get bool isDead()` | 获取 isDead 的值。 |
| 属性 | `get Int64 handle()` | 获取 handle 的值。 |

## class `Coroutine`

- **说明**：SLang 标准库类型 Coroutine（详见源文件）。

| 类型 | 签名 | 说明 |
|------|------|------|
| 方法 | `Task spawnClosure0(object closure)` | 执行 spawnClosure0(closure)，行为详见源实现。 |
| 方法 | `Task spawnClosure1(object closure, object arg0)` | 执行 spawnClosure1(closure, arg0)，行为详见源实现。 |
| 方法 | `Task spawnClosure2(object closure, object arg0, object arg1)` | 执行 spawnClosure2(closure, arg0, arg1)，行为详见源实现。 |
| 方法 | `Task spawnClosure3(object closure, object arg0, object arg1, object arg2)` | 执行 spawnClosure3(closure, arg0, arg1, arg2)，行为详见源实现。 |
| 方法 | `Task spawnClosure(object closure, Array&lt;object&gt; objs)` | 执行 spawnClosure(closure, objs)，行为详见源实现。 |
| 方法 | `void yieldNow()` | 执行 yieldNow()。 |
| 方法 | `void delay(Int64 millis)` | 执行 delay(millis)，行为详见源实现。 |
| 方法 | `void waitUntil(Function predicate)` | 执行 waitUntil(predicate)，行为详见源实现。 |
| 方法 | `Task current()` | 迭代器 / 订阅控制（current）。 |
| 方法 | `Int32 status(Task cor)` | 执行 status(cor)，行为详见源实现。 |
| 方法 | `Int32 blockedReason(Task cor)` | 执行 blockedReason(cor)，行为详见源实现。 |
| 方法 | `object awaitTask(Task cor)` | 运行 / 调用（awaitTask）。 |
| 方法 | `object __awaitCall(object v)` | 执行 __awaitCall(v)，行为详见源实现。 |
| 方法 | `object __awaitSpawn0(Function f)` | 执行 __awaitSpawn0(f)，行为详见源实现。 |
| 方法 | `object __awaitSpawn1(Function f, object a0)` | 执行 __awaitSpawn1(f, a0)，行为详见源实现。 |
| 方法 | `object __awaitSpawn2(Function f, object a0, object a1)` | 执行 __awaitSpawn2(f, a0, a1)，行为详见源实现。 |
| 方法 | `object __awaitSpawn3(Function f, object a0, object a1, object a2)` | 执行 __awaitSpawn3(f, a0, a1, a2)，行为详见源实现。 |
| 方法 | `void waitAll2(Task c0, Task c1)` | 执行 waitAll2(c0, c1)，行为详见源实现。 |
| 方法 | `void waitAll3(Task c0, Task c1, Task c2)` | 执行 waitAll3(c0, c1, c2)，行为详见源实现。 |
| 方法 | `void waitAll(params Array&lt;Task&gt; cors)` | 执行 waitAll(cors)，行为详见源实现。 |
| 方法 | `Task waitAny2(Task c0, Task c1)` | 执行 waitAny2(c0, c1)，行为详见源实现。 |
| 方法 | `Task waitAny3(Task c0, Task c1, Task c2)` | 执行 waitAny3(c0, c1, c2)，行为详见源实现。 |
| 方法 | `Task waitAny(params Task[] cors)` | 执行 waitAny(cors)，行为详见源实现。 |
| 方法 | `Task nextCompleted2(Task c0, Task c1)` | 迭代器 / 订阅控制（nextCompleted2）。 |
| 方法 | `Task nextCompleted3(Task c0, Task c1, Task c2)` | 迭代器 / 订阅控制（nextCompleted3）。 |
| 方法 | `bool waitTimeout(Task cor, Int64 millis)` | 执行 waitTimeout(cor, millis)，行为详见源实现。 |
| 方法 | `bool cancel(Task cor)` | 判断状态是否（cancel）。 |
