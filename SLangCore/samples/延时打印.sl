# 延时打印：await 挂起 200ms（协程最小示例，不阻塞调度）
import Std

DelayPrint
{
    static Fun()
    {
        start = Environment.sys.nowMillis()
        Console.print("wait 200ms ...")
        await Coroutine.delay(200)
        cost = Environment.sys.nowMillis() - start
        Console.println("delay done, cost=$cost ms")
    }
}
