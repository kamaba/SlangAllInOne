Project
{
    println( txt )
    {
        SystemPrintln( txt )
    }
    print( text )
    {
        SystemPrint( text )
    }
    _main_()
    {
        SystemPrintln( "===== TensoraTest _main_ start =====" )

        TensorTest.fun()
        BackendTest.fun()
        CpuSimdTest.fun()
        AutogradTest.fun()
        CnnTest.fun()
        NnTest.fun()
        ClassicMlTest.fun()
        DataTest.fun()
        TtsTest.fun()
        TransformerModelTest.fun()
        CudaBackendTest.fun()
        OnnxMemTest.fun()
        OnnxModelTest.fun()
        TensorOpsTest.fun()

        SystemPrintln( "===== TensoraTest _main_ end =====" )
    }
    _test_()
    {
        # 单跑某一个用例时在这里加：例如 TensorTest.fun()
        BackendTest.fun()
        CpuSimdTest.fun()
    }
    _before_()
    {
    }
    _after_()
    {
    }
}
