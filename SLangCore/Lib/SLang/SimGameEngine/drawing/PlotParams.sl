# ============================================================================
# PlotParams — 图形参数对象（R par() 等价，SimGameEngine 基础绘图 / doc/24）
# ----------------------------------------------------------------------------
# 一个 PlotParams 实例 = 一次绘图的「图形参数」：画布尺寸 / 边距 / 前景背景 /
# 线型线宽 / 点符号 / 字体缩放 / 标题坐标轴 / 坐标范围 / 网格开关 / 图例位置。
# DrawChart 每个工厂函数都接受可选 params（null = 全部取默认值）。
# 纯数据 + 简单 setter，无 C 依赖、无跨模块调用。
# ============================================================================

public class PlotParams
{
    # 画布与边距
    public Int32 width = 720
    public Int32 height = 480
    public Int32 marginLeft = 56
    public Int32 marginRight = 18
    public Int32 marginTop = 34
    public Int32 marginBottom = 38

    # 颜色（打包 RGB）
    public Int32 foreground = 0
    public Int32 background = 0
    public Int32 gridColor = 0
    public Int32 seriesColor = 0

    # 线型 / 线宽 / 点符号 / 字符缩放（R lty/lwd/pch/cex）
    public Int32 lineType = 0
    public Int32 lineWidth = 1
    public Int32 pointSymbol = 1
    public Int32 charScale = 1
    # plot() 图形类型（R type=p/l/b/s）
    public Int32 plotType = 2

    # 标题与轴标签（R main/xlab/ylab）
    public string main = ""
    public string xlab = ""
    public string ylab = ""

    # 坐标范围（auto=true 时由数据自动推算；R xlim/ylim）
    public bool autoX = true
    public bool autoY = true
    public Float32 xlimLow = 0.0f
    public Float32 xlimHigh = 1.0f
    public Float32 ylimLow = 0.0f
    public Float32 ylimHigh = 1.0f

    # 网格 / 刻度数 / 图例位置
    public bool grid = false
    public Int32 ticks = 5
    public Int32 legendPos = 0

    public string lastError = ""

    _init_()
    {
        this.foreground = DrawTypes.black()
        this.background = DrawTypes.white()
        this.gridColor = DrawTypes.lightGray()
        this.seriesColor = DrawTypes.palette( 1 )
    }

    # ── 工厂（R par() 语义：无参取当前默认）──
    public static PlotParams par()
    {
        ret PlotParams.create()
    }

    public static PlotParams create()
    {
        ret PlotParams()
    }

    # ── 尺寸 / 边距 ──
    public void setSize( Int32 w, Int32 h )
    {
        if w >= 64 && w <= 8192 { this.width = w }
        if h >= 64 && h <= 8192 { this.height = h }
    }

    public void setMargins( Int32 left, Int32 top, Int32 right, Int32 bottom )
    {
        if left >= 0 && left < this.width / 2 { this.marginLeft = left }
        if top >= 0 && top < this.height / 2 { this.marginTop = top }
        if right >= 0 && right < this.width / 2 { this.marginRight = right }
        if bottom >= 0 && bottom < this.height / 2 { this.marginBottom = bottom }
    }

    # ── 颜色 ──
    public void setColors( Int32 fg, Int32 bg, Int32 gridC, Int32 seriesC )
    {
        this.foreground = fg
        this.background = bg
        this.gridColor = gridC
        this.seriesColor = seriesC
    }

    public void setColor( Int32 c )
    {
        this.seriesColor = c
    }

    # ── 线型 / 点 / 字体 ──
    public void setLine( Int32 style, Int32 width )
    {
        if style >= DrawTypes.LTY_SOLID && style <= DrawTypes.LTY_DASHDOT
        {
            this.lineType = style
        }
        if width >= 1 && width <= 8
        {
            this.lineWidth = width
        }
    }

    public void setPoint( Int32 symbol, Int32 scale )
    {
        if symbol >= DrawTypes.PCH_NONE && symbol <= DrawTypes.PCH_PIXEL
        {
            this.pointSymbol = symbol
        }
        if scale >= 1 && scale <= 6
        {
            this.charScale = scale
        }
    }

    public void setPlotType( Int32 type )
    {
        if type >= DrawTypes.PLOT_POINTS && type <= DrawTypes.PLOT_STEPS
        {
            this.plotType = type
        }
    }

    # ── 标题 / 轴标签 ──
    public void setLabels( string mainTitle, string xLabel, string yLabel )
    {
        this.main = mainTitle
        this.xlab = xLabel
        this.ylab = yLabel
    }

    # ── 坐标范围 ──
    public void setXlim( Float32 lo, Float32 hi )
    {
        if hi <= lo
        {
            this.lastError = "xlim: high must be greater than low"
            ret
        }
        this.autoX = false
        this.xlimLow = lo
        this.xlimHigh = hi
    }

    public void setYlim( Float32 lo, Float32 hi )
    {
        if hi <= lo
        {
            this.lastError = "ylim: high must be greater than low"
            ret
        }
        this.autoY = false
        this.ylimLow = lo
        this.ylimHigh = hi
    }

    public void autoScale()
    {
        this.autoX = true
        this.autoY = true
    }

    # ── 网格 / 刻度 / 图例 ──
    public void setGrid( bool on, Int32 count )
    {
        this.grid = on
        if count >= 2 && count <= 12
        {
            this.ticks = count
        }
    }

    public void setLegendPos( Int32 pos )
    {
        if pos >= DrawTypes.LEGEND_TOPRIGHT && pos <= DrawTypes.LEGEND_BOTTOMLEFT
        {
            this.legendPos = pos
        }
    }
}
