Project
{
    _main_()
    {
        # 运行模式由参数决定（参数经系统注入的 global._inputArgs 读取）：
        #   -- smoke  = 无窗口冒烟
        #   -- web    = H5 网页版（浏览器 canvas + 分辨率选择 + FPS）
        #   无参数    = QT 窗口示例
        Array<Object> args = global._inputArgs
        if args.length > 0
        {
            string a0 = args[0].toString()
            if a0 == "smoke"
            {
                SceneSmokeTest.run()
                ret
            }
            if a0 == "web"
            {
                SceneDemoWebUI.runWebUI()
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
