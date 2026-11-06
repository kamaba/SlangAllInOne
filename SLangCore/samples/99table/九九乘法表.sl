# 九九乘法表：双重循环 + 字符串插值
import Std

NineTable
{
    static Fun()
    {
        for i = 1, i <= 9, i++
        {
            line = ""
            for j = 1, j <= i, j++
            {
                v = j * i
                seg = "$j x $i = $v   "
                line = line + seg
            }
            Console.println(line)
        }
    }
}
