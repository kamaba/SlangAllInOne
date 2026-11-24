# =========================================================================
# Stats/PlotIo.sl —— 输出与预览（终端 ASCII / 像素画像）
#
# 用法见 doc/02-Usage.md §5；实现说明见 doc/01-Design.md §5.6。
# 核心输出通道（上屏/落盘）不在此文件：PlotCanvas.pixelPtr()+width/height
# 直接对喂 slQT QLabel.setPixmapRgba（见 Usage §5.2）。
# =========================================================================

import Core;
import Std;

namespace StatsPlot
{
    public class PlotIo
    {
        # 每列自顶向下首个非白像素行号（纯白列 = 画布高）；测试/自绘用
        public static List<Int32> heightProfile( PlotCanvas c, Int32 step )
        {
            List<Int32> tops = List<Int32>()
            Int32 w = c.width()
            Int32 h = c.height()
            Int32 st = step
            if st < 1
            {
                st = 1
            }
            Int32 x = 0
            while x < w
            {
                Int32 top = h
                Int32 y = 0
                bool found = false
                while y < h
                {
                    if c.pixelAt( x, y ) != c.rgb( 255, 255, 255 )
                    {
                        top = y
                        found = true
                    }
                    if found
                    {
                        break
                    }
                    y = y + 1
                }
                tops.add( top )
                x = x + st
            }
            ret tops
        }

        # 终端 ASCII 预览：抽样列 × 24 行，按“暗区深度”映射 10 级灰度字符
        public static string ascii( PlotCanvas c )
        {
            string chars = " .:-=+*#%@"
            Int32 w = c.width()
            Int32 h = c.height()
            if w == 0 || h == 0
            {
                ret ""
            }
            Int32 step = w / 96
            if step < 1
            {
                step = 1
            }
            Int32 rows = 24
            Int32 rowStep = h / rows
            if rowStep < 1
            {
                rowStep = 1
            }
            List<Int32> tops = PlotIo.heightProfile( c, step )
            string s = ""
            Int32 sy = 0
            while sy < rows
            {
                Int32 ypx = sy * rowStep
                Int32 cx = 0
                while cx < tops.length
                {
                    Int32 level = 0
                    if ypx >= tops._getItem_( cx )
                    {
                        Int32 depth = ( ypx - tops._getItem_( cx ) ) * 10 / rowStep
                        if depth < 0
                        {
                            depth = 0
                        }
                        if depth > 9
                        {
                            depth = 9
                        }
                        level = depth
                    }
                    s = s + chars.slice( level, level + 1 )
                    cx = cx + 1
                }
                s = s + "\n"
                sy = sy + 1
            }
            ret s
        }
    }
}