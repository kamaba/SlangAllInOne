# ============================================================================
# Glyph — 字形轮廓数据（纯数据容器，TTF 二次曲线已展平为折线）
# ----------------------------------------------------------------------------
# 坐标单位 = 字体 units（由 Font.unitsPerEm 换算到像素）；每条轮廓闭合后
# 记录末端下标，光栅化按偶奇规则跨轮廓填充（天然支持 O/日 等孔洞）。
# ============================================================================

import Core;
import Std;

public class Glyph
{
    Int32 _gid = 0
    List<Float32> _xs = null
    List<Float32> _ys = null
    List<Int32> _ends = null
    Float32 _advance = 0.0f
    Int32 _xMin = 0
    Int32 _yMin = 0
    Int32 _xMax = 0
    Int32 _yMax = 0

    public void _init_()
    {
        this._gid = 0
        this._xs = List<Float32>( 64 )
        this._ys = List<Float32>( 64 )
        this._ends = List<Int32>( 4 )
        this._advance = 0.0f
        this._xMin = 0
        this._yMin = 0
        this._xMax = 0
        this._yMax = 0
    }

    public Int32 glyphId()
    {
        ret this._gid
    }

    public void setGlyphId( Int32 value )
    {
        this._gid = value
    }

    public Int32 pointCount()
    {
        ret this._xs.length
    }

    public Int32 contourCount()
    {
        ret this._ends.length
    }

    public Float32 xAt( Int32 i )
    {
        if i < 0 || i >= this._xs.length
        {
            ret 0.0f
        }
        Float32 v = this._xs[i]
        ret v
    }

    public Float32 yAt( Int32 i )
    {
        if i < 0 || i >= this._ys.length
        {
            ret 0.0f
        }
        Float32 v = this._ys[i]
        ret v
    }

    public Int32 contourEndAt( Int32 i )
    {
        if i < 0 || i >= this._ends.length
        {
            ret -1
        }
        Int32 v = this._ends[i]
        ret v
    }

    public Float32 advance()
    {
        ret this._advance
    }

    public void setAdvance( Float32 value )
    {
        this._advance = value
    }

    public Int32 xMin() { ret this._xMin }
    public Int32 yMin() { ret this._yMin }
    public Int32 xMax() { ret this._xMax }
    public Int32 yMax() { ret this._yMax }

    public bool isEmpty()
    {
        ret this._xs.length == 0
    }

    public void addPoint( Float32 x, Float32 y )
    {
        this._xs.add( x )
        this._ys.add( y )
        Int32 xi = x.toInt32()
        Int32 yi = y.toInt32()
        if this._xs.length == 1
        {
            this._xMin = xi
            this._xMax = xi
            this._yMin = yi
            this._yMax = yi
            ret
        }
        if xi < this._xMin { this._xMin = xi }
        if xi > this._xMax { this._xMax = xi }
        if yi < this._yMin { this._yMin = yi }
        if yi > this._yMax { this._yMax = yi }
    }

    public void closeContour()
    {
        Int32 last = this._xs.length - 1
        if last >= 0
        {
            this._ends.add( last )
        }
    }

    public string toString()
    {
        string a = "Glyph(gid=" + this._gid.toString()
        string b = ",pts=" + this._xs.length.toString()
        string c = ",contours=" + this._ends.length.toString()
        ret a + b + c + ")"
    }
}
