# 全并字母：小写容器糖 list()、for-in 遍历、元素合并
import Std

MergeLetters
{
    static Fun()
    {
        left = list()
        left.add("a")
        left.add("c")
        left.add("e")
        right = list()
        right.add("b")
        right.add("d")
        all = list()
        for v in left
        {
            all.add(v)
        }
        for v in right
        {
            all.add(v)
        }
        result = ""
        for i = 0, i < all.length, i++
        {
            result = result + (all[i] as string)
        }
        Console.println("merged: $result")
    }
}
