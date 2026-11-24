import SLangQT;
import SLangRender;

Project
{
    # GLRenderTest —— SLangRender 离屏 GL 渲染 + SLangQT 窗口填充端到端：
    # Phase A 纯 GL（无 QT 依赖，headless 可跑）：初始化 / 渲染 / 回读 /
    #          像素采样校验（红色帧 -> 蓝色帧的颜色变化验证）
    # Phase B QT 窗口（需真实 Qt 后端；stub 后端 SKIP）：QTimer 16ms 帧循环
    #          -> renderFrame(颜色随时间正弦变化) -> QLabel.setPixmapRgba
    #          填充（renderTexture 通道）
    _main_()
    {
        # 参数 basicdraw = 只跑 RenderTestBasicDraw（点/线/圆/三角等全覆盖），
        # 不进入 GLRenderTest 全相位与 QT 帧循环。
        Array<Object> args = global._inputArgs
        if args.length > 0
        {
            string a0 = args[0].toString()
            if a0 == "basicdraw"
            {
                bool ok = RenderTestBasicDraw.runBasicDraw()
                ret
            }
        }
        RenderTest.main()
    }

    _before_()
    {
    }

    _after_()
    {
    }
}
