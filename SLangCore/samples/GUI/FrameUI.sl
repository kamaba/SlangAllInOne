# 历史示例（早期宿主 GUI）：import CSharp.System 与 import Tkinter 所指模块均已随
# 宿主迁移移除（2026-10-13 起 import 为硬错误），Canvas / Button / Behaviour 宿主类
# 亦不再提供；保留作语法参考，当前编译器下不可编译。

PromptUI extends Behaviour
{
    _init_()
    {
        this._root = { };
        this._root.add( Button("您好") );
    }
}

MainFrame extends Behaviour
{
    _init_()
    {

    }
}