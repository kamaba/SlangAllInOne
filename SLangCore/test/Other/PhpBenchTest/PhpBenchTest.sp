import Std

Project
{
    _main_()
    {
        Console.println("===== PhpBenchTest start =====")
        PhpBench.fun()
        BenchCollector.generateReport()
        Console.println("===== PhpBenchTest end =====")
    }
}