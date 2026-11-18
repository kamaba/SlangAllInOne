import Std

Fibonacci
{
    static fun()
    {
        total = 0L
        for r = 0, r < 10, r++
        {
            nowMs = Environment.sys.nowMillis()
            sum = 0L
            for i = 0, i < 22, i++
            {
                sum += Fibonacci.fib(i)
            }
            nowMs = Environment.sys.nowMillis() - nowMs
            total += nowMs
            Console.println("fib round " + r.toString() + " sum=" + sum.toString() + " [" + nowMs.toString() + " ms]")
        }
        Console.println("fib total [" + total.toString() + " ms]")
    }

    static int fib( int n)
    {
        ret n <= 1 ? n : Fibonacci.fib(n - 1) + fib(n - 2)
    }
}
