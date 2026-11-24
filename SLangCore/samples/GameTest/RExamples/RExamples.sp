Project
{
    # smoke = 12 张图表无窗口像素断言；无参数 = QT 图库窗口。
    _main_()
    {
        Array<Object> args = global._inputArgs
        if args.length > 0
        {
            string a0 = args[0].toString()
            if a0 == "smoke"
            {
                RExamples.smoke()
                ret
            }
        }
        RExamples.run()
    }
    _before_()
    {
    }
    _after_()
    {
    }
}
