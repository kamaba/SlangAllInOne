# ============================================================================
# GdiCanvas —— Windows 系统 GDI 离屏画布门面
# ----------------------------------------------------------------------------
# 本文件不含任何软光栅：所有绘图经 RenderFFI 直调 sl_render_lib.dll 的
# slr_gdi_*（cvm_render_lib/Platform/sl_gdi.c），由 Windows GDI 的
# CreateDIBSection + HDC + pen/brush/TextOutW 真正执行。
# 画布像素：C 侧 DIB 为 BGRA（top-down）；对外 toRgba / createTexture
# 一律转成本库 RGBA8 top-down 契约。
# 非 Windows 平台 create() 返回未就绪画布，所有绘制安全 no-op。
# ============================================================================

import Core;
import Std;

public class GdiCanvas
{
    Int64 _handle = 0
    Int32 _w = 0
    Int32 _h = 0

    public void _init_()
    {
        this._handle = 0
        this._w = 0
        this._h = 0
    }

    public static GdiCanvas create( Int32 width, Int32 height )
    {
        GdiCanvas c = GdiCanvas()
        if width <= 0 || height <= 0
        {
            ret c
        }
        c._w = width
        c._h = height
        c._handle = RenderFFI.ffiGdiCreate( width, height )
        ret c
    }

    public bool isReady()
    {
        ret this._handle != 0
    }

    public Int64 handle()
    {
        ret this._handle
    }

    public Int32 width()
    {
        ret this._w
    }

    public Int32 height()
    {
        ret this._h
    }

    public void dispose()
    {
        if this._handle != 0
        {
            RenderFFI.ffiGdiDestroy( this._handle )
            this._handle = 0
        }
    }

    # 颜色 0xAARRGGBB（高位 alpha；与库像素契约一致）
    public static Int32 rgba( Int32 r, Int32 g, Int32 b, Int32 a )
    {
        ret ( a << 24 ) | ( r << 16 ) | ( g << 8 ) | b
    }

    public static Int32 rgb( Int32 r, Int32 g, Int32 b )
    {
        ret GdiCanvas.rgba( r, g, b, 255 )
    }

    public static Int32 alphaOf( Int32 color )
    {
        ret ( color >> 24 ) & 255
    }

    # ── v5.1 笔样式常量（styleInfo = (width<<8)|penStyle，宽 1..32）──
    public static Int32 PEN_SOLID = 0
    public static Int32 PEN_DASH = 1
    public static Int32 PEN_DOT = 2
    public static Int32 PEN_DASHDOT = 3
    public static Int32 PEN_DASHDOTDOT = 4

    # 组合 styleInfo：宽 1..32 钳位（GDI 非实线笔宽强制 1，C 侧再钳一道）
    public static Int32 styleInfo( Int32 width, Int32 penStyle )
    {
        Int32 w = width
        if w < 1
        {
            w = 1
        }
        if w > 32
        {
            w = 32
        }
        Int32 s = penStyle
        if s < 0 || s > 4
        {
            s = 0
        }
        ret ( w << 8 ) | s
    }

    public bool clear( Int32 color )
    {
        if this._handle == 0
        {
            ret false
        }
        ret RenderFFI.ffiGdiClear( this._handle, color )
    }

    public bool setPixel( Int32 x, Int32 y, Int32 color )
    {
        if this._handle == 0
        {
            ret false
        }
        ret RenderFFI.ffiGdiSetPixel( this._handle, x, y, color )
    }

    public Int32 pixelAt( Int32 x, Int32 y )
    {
        if this._handle == 0 || x < 0 || y < 0 || x >= this._w || y >= this._h
        {
            ret -1
        }
        ret RenderFFI.ffiGdiGetPixel( this._handle, x, y )
    }

    public bool line( Int32 x0, Int32 y0, Int32 x1, Int32 y1, Int32 color )
    {
        if this._handle == 0
        {
            ret false
        }
        ret RenderFFI.ffiGdiLine( this._handle, x0, y0, x1, y1, color )
    }

    public bool rect( Int32 x0, Int32 y0, Int32 x1, Int32 y1, Int32 color )
    {
        if this._handle == 0
        {
            ret false
        }
        ret RenderFFI.ffiGdiRect( this._handle, x0, y0, x1, y1, color )
    }

    public bool fillRect( Int32 x0, Int32 y0, Int32 x1, Int32 y1, Int32 color )
    {
        if this._handle == 0
        {
            ret false
        }
        ret RenderFFI.ffiGdiFillRect( this._handle, x0, y0, x1, y1, color )
    }

    public bool ellipse( Int32 x0, Int32 y0, Int32 x1, Int32 y1, Int32 color )
    {
        if this._handle == 0
        {
            ret false
        }
        ret RenderFFI.ffiGdiEllipse( this._handle, x0, y0, x1, y1, color )
    }

    public bool fillEllipse( Int32 x0, Int32 y0, Int32 x1, Int32 y1, Int32 color )
    {
        if this._handle == 0
        {
            ret false
        }
        ret RenderFFI.ffiGdiFillEllipse( this._handle, x0, y0, x1, y1, color )
    }

    # 多边形：x/y 两列 Float32，先打成 x0,y0,x1,y1... 的 ptr 交 GDI Polygon
    public bool fillPolygon( List<Float32> xs, List<Float32> ys, Int32 stroke, Int32 fill )
    {
        if this._handle == 0 || xs == null || ys == null
        {
            ret false
        }
        Int32 n = xs.length
        if n < 3 || n != ys.length || n > 4096
        {
            ret false
        }
        Int64 ptr = Memory.alloc( n * 8 )
        if ptr == 0
        {
            ret false
        }
        Int32 i = 0
        while i < n
        {
            Float32 vx = xs[i]
            Float32 vy = ys[i]
            Memory.writeF32( ptr, i * 8, vx )
            Memory.writeF32( ptr, i * 8 + 4, vy )
            i += 1
        }
        bool ok = RenderFFI.ffiGdiPolygon( this._handle, ptr, n, stroke, fill )
        Memory.free( ptr )
        ret ok
    }

    # GDI BitBlt：把 src 整张画布拷到本画布 (x,y)
    public bool blit( GdiCanvas src, Int32 x, Int32 y )
    {
        if this._handle == 0 || src == null || src._handle == 0
        {
            ret false
        }
        ret RenderFFI.ffiGdiBlit( this._handle, src._handle, x, y )
    }

    # ── v5.1 基础图形门面（BasicDraw 的 GDI 直通层）──

    # 带笔宽/样式的线段（虚线/点线/点划线）
    public bool lineEx( Int32 x0, Int32 y0, Int32 x1, Int32 y1, Int32 styleInfo, Int32 color )
    {
        if this._handle == 0
        {
            ret false
        }
        Int64 ptr = Memory.alloc( 16 )
        if ptr == 0
        {
            ret false
        }
        Memory.writeF32( ptr, 0, SystemConvertFloat32( x0 ) )
        Memory.writeF32( ptr, 4, SystemConvertFloat32( y0 ) )
        Memory.writeF32( ptr, 8, SystemConvertFloat32( x1 ) )
        Memory.writeF32( ptr, 12, SystemConvertFloat32( y1 ) )
        bool ok = RenderFFI.ffiGdiLineEx( this._handle, ptr, styleInfo, color )
        Memory.free( ptr )
        ret ok
    }

    # 点列打包（x,y 对平铺；调用方负责 free）
    Int64 _packPoints( List<Float32> xs, List<Float32> ys, Int32 n )
    {
        Int64 ptr = Memory.alloc( n * 8 )
        if ptr == 0
        {
            ret 0
        }
        Int32 i = 0
        while i < n
        {
            Float32 vx = xs[i]
            Float32 vy = ys[i]
            Memory.writeF32( ptr, i * 8, vx )
            Memory.writeF32( ptr, i * 8 + 4, vy )
            i += 1
        }
        ret ptr
    }

    # 折线（开放）
    public bool polyline( List<Float32> xs, List<Float32> ys, Int32 styleInfo, Int32 color )
    {
        if this._handle == 0 || xs == null || ys == null
        {
            ret false
        }
        Int32 n = xs.length
        if n < 2 || n != ys.length || n > 4096
        {
            ret false
        }
        Int64 ptr = this._packPoints( xs, ys, n )
        if ptr == 0
        {
            ret false
        }
        bool ok = RenderFFI.ffiGdiPolyline( this._handle, ptr, n, styleInfo, color )
        Memory.free( ptr )
        ret ok
    }

    # 闭合折线（描边多边形/三角边/四边形边框）
    public bool polyClosed( List<Float32> xs, List<Float32> ys, Int32 styleInfo, Int32 color )
    {
        if this._handle == 0 || xs == null || ys == null
        {
            ret false
        }
        Int32 n = xs.length
        if n < 3 || n != ys.length || n > 4096
        {
            ret false
        }
        Int64 ptr = this._packPoints( xs, ys, n )
        if ptr == 0
        {
            ret false
        }
        bool ok = RenderFFI.ffiGdiPolyClosed( this._handle, ptr, n, styleInfo, color )
        Memory.free( ptr )
        ret ok
    }

    # 贝塞尔（每段 3 控制点：4 点单段 / 7 点两段 / …，固定实线宽 1）
    public bool bezier( List<Float32> xs, List<Float32> ys, Int32 color )
    {
        if this._handle == 0 || xs == null || ys == null
        {
            ret false
        }
        Int32 n = xs.length
        if n < 4 || n != ys.length || n > 4096 || ( n - 1 ) % 3 != 0
        {
            ret false
        }
        Int64 ptr = this._packPoints( xs, ys, n )
        if ptr == 0
        {
            ret false
        }
        bool ok = RenderFFI.ffiGdiBezier( this._handle, ptr, n, color )
        Memory.free( ptr )
        ret ok
    }

    # 圆弧/椭圆弧：bbox 矩形 + 起/终射线点（8 浮点）
    public bool arc( List<Float32> coords, Int32 color )
    {
        if this._handle == 0 || coords == null
        {
            ret false
        }
        if coords.length < 8
        {
            ret false
        }
        Int64 ptr = Memory.alloc( 32 )
        if ptr == 0
        {
            ret false
        }
        Int32 i = 0
        while i < 8
        {
            Float32 v = coords[i]
            Memory.writeF32( ptr, i * 4, v )
            i += 1
        }
        bool ok = RenderFFI.ffiGdiArc( this._handle, ptr, color )
        Memory.free( ptr )
        ret ok
    }

    # 批量点
    public bool points( List<Float32> xs, List<Float32> ys, Int32 color )
    {
        if this._handle == 0 || xs == null || ys == null
        {
            ret false
        }
        Int32 n = xs.length
        if n < 1 || n != ys.length || n > 65536
        {
            ret false
        }
        Int64 ptr = this._packPoints( xs, ys, n )
        if ptr == 0
        {
            ret false
        }
        bool ok = RenderFFI.ffiGdiPoints( this._handle, ptr, n, color )
        Memory.free( ptr )
        ret ok
    }

    # GDI TextOutW（系统默认字体；UTF-8 字符串，C 侧转宽字符）
    public bool drawText( string text, Int32 x, Int32 y, Int32 height, Int32 color )
    {
        if this._handle == 0 || text == null
        {
            ret false
        }
        ret RenderFFI.ffiGdiText( this._handle, text, x, y, height, color )
    }

    # 把 GDI 的 BGRA 位流转成 RGBA8 top-down 写入调用方块（w*h*4）
    public bool toRgba( Int64 dstPtr )
    {
        if this._handle == 0 || dstPtr == 0
        {
            ret false
        }
        ret RenderFFI.ffiGdiToRgba( this._handle, dstPtr )
    }

    # 便捷：新建 RGBA8 块（调用方负责 Memory.free）
    public Int64 toRgbaBlock()
    {
        if this._handle == 0
        {
            ret 0
        }
        Int64 dst = Memory.alloc( this._w * this._h * 4 )
        if dst == 0 || !this.toRgba( dst )
        {
            if dst != 0
            {
                Memory.free( dst )
            }
            ret 0
        }
        ret dst
    }

    public SLang.RenderTexture createTexture()
    {
        if this._handle == 0
        {
            ret null
        }
        Int64 tex = RenderFFI.ffiGdiCreateTexture( this._handle )
        if tex == 0
        {
            ret null
        }
        ret SLang.RenderTexture( tex, this._w, this._h )
    }

    public bool updateTexture( SLang.RenderTexture tex )
    {
        if this._handle == 0 || tex == null
        {
            ret false
        }
        Int64 th = tex.handle
        ret RenderFFI.ffiGdiUpdateTexture( this._handle, th )
    }
}
