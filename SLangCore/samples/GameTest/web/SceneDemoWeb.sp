Project
{
    # SceneDemoWeb 入口：泵帧循环在 web 版 QTHost.pumpWeb()（.sp 无 import
    # 平面，不能直接调 Console/OS——历史坑：sp 只能转发同模块类方法）。
    _main_()
    {
        QTHost.pumpWeb()
    }
    _before_()
    {
    }
    _after_()
    {
    }
}
