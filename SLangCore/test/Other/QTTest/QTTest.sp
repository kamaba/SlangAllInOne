import SLangQT;

Project
{
    # QTTest —— slQT 端到端 smoke（headless：STUB 原生 DLL 即可跑，验证 FFI 绑定 /
    # 工厂 / 类层级 / 信号连接 bind_id；真实 Qt 窗口见 ../cvm/README 的 Qt 版）。
    _main_()
    {
        QTTest.main()
    }

    _before_()
    {
    }

    _after_()
    {
    }
}
