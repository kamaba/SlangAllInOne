# 斐波那契数列：循环 + 字符串插值（输出前 10 项）
import Std

Fib
{
    static Fun()
    {
        a = 1
        b = 1
        line = ""
        for i = 1, i <= 10, i++
        {
            line = line + "$a "
            sum = a + b
            a = b
            b = sum
        }
        Console.println(line)
    }
}
