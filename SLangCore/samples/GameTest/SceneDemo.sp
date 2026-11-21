Project
{
    _main_()
    {
        # 运行模式由参数决定：slang run SceneDemo.module.slb -- smoke = 无窗口冒烟；
        # 无参数 / 其它参数 = QT 窗口示例。参数经系统注入的 global._inputArgs 读取。
        Array<Object> args = global._inputArgs
        if args.length > 0
        {
            string a0 = args[0].toString()
            if a0 == "smoke"
            {
                SceneSmokeTest.run()
                ret
            }
        }
        SceneDemo.run()
    }
    _before_()
    {
    }
    _after_()
    {
    }
}
