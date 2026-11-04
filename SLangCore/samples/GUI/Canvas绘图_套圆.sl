# 历史示例（早期宿主 GUI）：import CSharp.System 与 import Tkinter 所指模块均已随
# 宿主迁移移除（2026-10-13 起 import 为硬错误），Canvas 宿主类亦不再提供；
# 保留作语法参考，当前编译器下不可编译。

PTS
{

    x1 = [[12,7,3],[4,5,6],[7,8,9]];        # array<int>(9,3);  
    x = 0
    y = 0

    List<PTS> points = new();

    static Fun()
    {        
        canvas = Canvas( width=800, height=600, bg="white" )   #参数，输入参数名称
        canvas.pack( )
        
        k = 1
        j = 1
        for i in range(0,26)
        {
            canvas.createOval( 310- k, 250 - k, 310 + k, 250 + k, width = 1 )
            k += j
            j += 0.3
        }
    }
}