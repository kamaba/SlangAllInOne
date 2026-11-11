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
        GLRenderTest.main()
    }

    _before_()
    {
    }

    _after_()
    {
    }
}
