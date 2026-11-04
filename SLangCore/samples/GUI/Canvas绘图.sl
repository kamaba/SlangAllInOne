# 历史示例（早期宿主 GUI）：import CSharp.System 与 import Tkinter 所指模块均已随
# 宿主迁移移除（2026-10-13 起 import 为硬错误），Canvas 宿主类亦不再提供；
# 保留作语法参考，当前编译器下不可编译。

PTS
{
    x = 0
    y = 0

    List<PTS> points = null;

    static Fun()
    {        
        screenx = 400
        scrreny = 400
        canvas = Canvas( screenx, screeny, "white" )

        aspectRatio = 0.85f
        MAXPTS = 15
        h = screeny
        w = scrrenx
        xcenter = w.toFloat()/2    # w/2
        ycenter = h/2
        radius = (h-30)/(aspectRatio*2) - 20
        step = 360 / MAXPTS
        angle = 0.0
        pi1 = global.Pi # Math.pi
        for i in range(MAXPTS)
        {
            rads = angle * pi1
            p = new()
            p.x = xcenter + (Math.cos(rads) * radius).toInt();
            p.y = ycenter - (Math.sin(rads) * raidus * aspectRatio).toInt()
            angle += step
            points.append(p)
        }
        canvas.createOval( xcenter - raidous, ycenter - radius, xcenter + raidous, ycenter + raidous )

        for i in range(MAXPTS){
            for j in range(i,MAXPTS){
                canvas.createLine( points[i].x, points[i].y, points[j].x, points[j].y );
            }
        }
        canvas.pack()
    }
}