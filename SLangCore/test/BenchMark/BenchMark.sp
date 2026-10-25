import Std

Project
{
    _main_()
    {
        Console.println("===== BenchMark _main_ start =====")
        nowMs = Environment.sys.nowMillis()

        #HelloWorld.fun()
        Fibonacci.fun()
        
        Loop.fun()
        Levenshtein.fun()
        DataTypes.fun()
        StringBench.fun()
        RegExpBench.fun()

        NQueens.fun()
        Sieve.fun()
        QuickSort.fun()
        MatrixMul.fun()
        BinaryTreeBench.fun()
        Mandelbrot.fun()
        

        nowMs = Environment.sys.nowMillis() - nowMs
         Console.println("===== BenchMark _main_ end [$nowMs.toString() ms] =====")
    }
    _before_()
    {
    }
    _after_()
    {
    }
}
