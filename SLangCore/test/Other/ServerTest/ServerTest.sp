Project
{
    _main_()
    {
        # SLangServer P0~P4.5 验收套件（SERVER_DESIGN.md §8；2026-10-25 自
        # NetTest/ExpendTest 迁出独立用例集，宿主选择器 ServerTest）：
        #   P0 探针=纯语言层无端口  P0 引擎 S=19371-19374
        #   P1=19401-19408  P1.5=19411-19413  P2=19421-19424
        #   P3=19431-19435  P4=19441-19443   P4.5=纯协程无端口
        ServerProbeTest.fun()
        ServerCoreTest.fun()
        ServerP1Test.fun()
        ServerP15Test.fun()
        ServerP2Test.fun()
        ServerP3Test.fun()
        ServerP4Test.fun()
        ServerP45Test.fun()
    }
    _before_()
    {
    }
    _after_()
    {
    }
}
