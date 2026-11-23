# ============================================================================
# BasicDraw —— 统一基础绘图接口层（v5.1）
# ----------------------------------------------------------------------------
# 用户点名的基础图形一套 API、双底层实现：
#   线 / 点 / 圆 / 三角形 / 三角边 / 四边形 / 多边形 / 椭圆 / 曲线 / 贝塞尔 /
#   折线 / 方向箭头 / 虚线（点线 / 点划线 / 双点划线）
#
# 后端（create 第 3 参选一，两后端输出同为 RGBA8 top-down 像素块）：
#   BACKEND_GDI(0) —— Windows GDI 原生（GdiCanvas 直通）：
#     GDI 已有的原语零三角化直调；v5.1 在 C 侧补齐 GDI 缺失原语——
#     折线 Polyline / 描边多边形 Polygon(NULL_BRUSH) / 贝塞尔 PolyBezier /
#     圆弧 Arc / 批量点 SetPixel / 装饰笔 PS_DASH|PS_DOT|PS_DASHDOT|
#     PS_DASHDOTDOT（非实线笔宽 GDI 硬限制 1，宽>1 自动回实线）。
#   BACKEND_RHI(1) —— RHI 管线三角化（GDI 不支持 / 非 Windows 场景）：
#     RenderPipeline MESH_CUSTOM 4 槽 × 4096 顶点（pos2+uv2）；
#     逐图元颜色经 256×1 调色板纹理（PTEX 采样 uColor×纹理）实现，
#     无需逐对象 setColor；圆 / 椭圆 / 曲线 / 贝塞尔 / 圆弧 SL 侧离散化，
#     虚线 SL 侧拆段（实线宽 1 与 GDI 行为对齐）；opaque 段关深度测试 +
#     稳定插入排序 → 画家序 = 图元累加序。
#
# 坐标：顶行在前（top-down）像素坐标，两后端一致；颜色 0xAARRGGBB。
# 像素中心约定：RHI 顶点取 (x+0.5, h-y-0.5)（宽 1 横线恰好铺满 y 行，
# 与 GDI 行为一致）；填充图元边界半像素差异由测试用内点采样规避。
# 方向箭头 = 线 + 三角头组合（两后端同构）。
# 圆弧方向：统一屏幕系角度递增（y 向下视觉顺时针）；GDI 侧 SetArcDirection
# (AD_CLOCKWISE) 对齐，RHI 侧 atan2 反推 a0/a1 后按递增方向离散化。
# ============================================================================
import Core;
import Std;
import Math;

public class BasicDraw
{
    # ── 后端 ──
    public static Int32 BACKEND_GDI = 0
    public static Int32 BACKEND_RHI = 1

    # ── 笔样式（与 GdiCanvas 共用编码 styleInfo=(width<<8)|penStyle）──
    public static Int32 PEN_SOLID = 0
    public static Int32 PEN_DASH = 1
    public static Int32 PEN_DOT = 2
    public static Int32 PEN_DASHDOT = 3
    public static Int32 PEN_DASHDOTDOT = 4

    # RHI 顶点容量：4 槽 × 4096 顶点（每顶点 pos2+uv2 = 16 字节）
    public static Int32 RHI_SLOT_VERTS = 4096
    public static Int32 RHI_MAX_VERTS = 16384

    # RHI 调色板容量（256×1 RGBA8 纹理；超额图元丢弃并返回 false）
    public static Int32 PALETTE_MAX = 256

    # ── 状态 ──
    Int32 _backend = 0
    Int32 _w = 0
    Int32 _h = 0
    GdiCanvas _gdi = null
    SLang.RenderPipeline _pipe = null
    SLang.RenderTexture _palette = null
    Int64 _verts = 0
    Int32 _vertCount = 0
    Int64 _palData = 0
    List<Int32> _palColors = null
    bool _palDirty = false
    Int64 _pixels = 0
    bool _dirty = false
    bool _rendered = false
    # clear 语义支持：历史顶点峰值（曾上传过的槽范围）+ 退化三角形缓冲
    # （3 顶点重合零面积，用于覆盖清空旧槽 GPU 数据——uploadMesh 拒绝
    # cnt<=0，无法直接清槽，改传退化网格使旧图元不再产生像素）
    Int32 _peakVerts = 0
    Int64 _degenPtr = 0

    public void _init_()
    {
    }

    # ================================ 生命周期 ================================

    public static BasicDraw create( Int32 width, Int32 height, Int32 backend )
    {
        if width < 1 || width > 8192
        {
            ret null
        }
        if height < 1 || height > 8192
        {
            ret null
        }
        BasicDraw d = BasicDraw()
        d._backend = backend
        d._w = width
        d._h = height
        if backend == BasicDraw.BACKEND_GDI
        {
            GdiCanvas g = GdiCanvas.create( width, height )
            if g == null || g.isReady() == false
            {
                ret null
            }
            d._gdi = g
            ret d
        }
        if backend == BasicDraw.BACKEND_RHI
        {
            if SLang.Render.currentBackend() == "none"
            {
                if SLang.Render.initialize() == false
                {
                    ret null
                }
            }
            SLang.RenderPipeline p = SLang.RenderPipeline.create( width, height )
            if p == null
            {
                ret null
            }
            p.setCamera( -1, 0.0f, SystemConvertFloat32( width ), 0.0f, SystemConvertFloat32( height ) )
            p.setClearColor( 0.0f, 0.0f, 0.0f, 0.0f )
            d._pipe = p
            d._verts = Memory.alloc( BasicDraw.RHI_MAX_VERTS * 16 )
            d._palData = Memory.alloc( BasicDraw.PALETTE_MAX * 4 )
            d._pixels = Memory.alloc( width * height * 4 )
            d._degenPtr = Memory.alloc( 48 )
            if d._verts == 0
            {
                ret null
            }
            if d._palData == 0
            {
                ret null
            }
            if d._pixels == 0
            {
                ret null
            }
            if d._degenPtr == 0
            {
                ret null
            }
            # 退化三角形：3 顶点全零（pos 0,0 / uv 0,0），零面积不出像素
            Int32 zi = 0
            while zi < 48
            {
                Memory.writeI8( d._degenPtr, zi, 0 )
                zi += 1
            }
            d._palColors = List<Int32>()
            SLang.RenderTexture pal = SLang.RenderTexture.createRgba( d._palData, BasicDraw.PALETTE_MAX, 1 )
            if pal == null
            {
                ret null
            }
            d._palette = pal
            Int32 slot = 0
            while slot < 4
            {
                # 4 槽自定义网格对象由 pipeline 自持（destroy 释放），这里仅配置
                SLang.RenderObject obj = p.addObject( SLang.RenderPipeline.MESH_CUSTOM + slot )
                obj.setLayer( 0 )
                obj.setQueue( 2000 )
                obj.setColor( 1.0f, 1.0f, 1.0f, 1.0f )
                obj.setTexture( pal )
                slot += 1
            }
            ret d
        }
        ret null
    }

    public bool isReady()
    {
        if this._backend == BasicDraw.BACKEND_GDI
        {
            if this._gdi == null
            {
                ret false
            }
            ret this._gdi.isReady()
        }
        if this._backend == BasicDraw.BACKEND_RHI
        {
            if this._pipe == null || this._verts == 0
            {
                ret false
            }
            ret true
        }
        ret false
    }

    public Int32 width()
    {
        ret this._w
    }

    public Int32 height()
    {
        ret this._h
    }

    public Int32 backend()
    {
        ret this._backend
    }

    public void dispose()
    {
        if this._gdi != null
        {
            this._gdi.dispose()
            this._gdi = null
        }
        if this._pipe != null
        {
            if this._palette != null
            {
                this._palette.destroy()
                this._palette = null
            }
            this._pipe.destroy()
            this._pipe = null
        }
        if this._verts != 0
        {
            Memory.free( this._verts )
            this._verts = 0
        }
        if this._degenPtr != 0
        {
            Memory.free( this._degenPtr )
            this._degenPtr = 0
        }
        if this._palData != 0
        {
            Memory.free( this._palData )
            this._palData = 0
        }
        if this._pixels != 0
        {
            Memory.free( this._pixels )
            this._pixels = 0
        }
    }

    # ================================ 输出 / 呈现 ================================

    # 整块清屏（GDI fillRect 全幅；RHI 记 clear 色，renderFrame 时生效）
    public bool clear( Int32 color )
    {
        if this._backend == BasicDraw.BACKEND_GDI
        {
            if this._gdi == null
            {
                ret false
            }
            ret this._gdi.fillRect( 0, 0, this._w, this._h, color )
        }
        if this._backend == BasicDraw.BACKEND_RHI
        {
            if this._pipe == null
            {
                ret false
            }
            Float32 r = SystemConvertFloat32( ( color >> 16 ) & 255 ) / 255.0f
            Float32 g = SystemConvertFloat32( ( color >> 8 ) & 255 ) / 255.0f
            Float32 b = SystemConvertFloat32( color & 255 ) / 255.0f
            Float32 a = SystemConvertFloat32( ( color >> 24 ) & 255 ) / 255.0f
            this._pipe.setClearColor( r, g, b, a )
            # 清屏 = 丢弃已绘制图元：重置顶点计数与渲染缓存；
            # 历史占用槽在下次 _ensureRendered 时用退化三角形覆盖
            this._vertCount = 0
            this._rendered = false
            this._dirty = true
            ret true
        }
        ret false
    }

    # 读像素（top-down，0xAARRGGBB；RHI 惰性渲染一次后缓存）
    public Int32 pixelAt( Int32 x, Int32 y )
    {
        if x < 0 || x >= this._w
        {
            ret 0
        }
        if y < 0 || y >= this._h
        {
            ret 0
        }
        if this._backend == BasicDraw.BACKEND_GDI
        {
            if this._gdi == null
            {
                ret 0
            }
            ret this._gdi.pixelAt( x, y )
        }
        if this._backend == BasicDraw.BACKEND_RHI
        {
            this._ensureRendered()
            Int32 off = ( y * this._w + x ) * 4
            Int32 r = Memory.readUInt8( this._pixels, off )
            Int32 g = Memory.readUInt8( this._pixels, off + 1 )
            Int32 b = Memory.readUInt8( this._pixels, off + 2 )
            Int32 a = Memory.readUInt8( this._pixels, off + 3 )
            ret ( a << 24 ) | ( r << 16 ) | ( g << 8 ) | b
        }
        ret 0
    }

    # 像素块写出到 dstPtr（RGBA8 top-down，w*h*4 字节）
    public bool toRgba( Int64 dstPtr )
    {
        if dstPtr == 0
        {
            ret false
        }
        if this._backend == BasicDraw.BACKEND_GDI
        {
            if this._gdi == null
            {
                ret false
            }
            ret this._gdi.toRgba( dstPtr )
        }
        if this._backend == BasicDraw.BACKEND_RHI
        {
            this._ensureRendered()
            Int32 n = this._w * this._h * 4
            Int32 i = 0
            while i < n
            {
                Int32 v = Memory.readUInt8( this._pixels, i )
                Memory.writeI8( dstPtr, i, v )
                i += 1
            }
            ret true
        }
        ret false
    }

    # 新分配像素块并填充（调用方负责 Memory.free）
    public Int64 toRgbaBlock()
    {
        Int64 dst = Memory.alloc( this._w * this._h * 4 )
        if dst == 0
        {
            ret 0
        }
        if this.toRgba( dst ) == false
        {
            Memory.free( dst )
            ret 0
        }
        ret dst
    }

    # 快照为 RHI 纹理（一次性上传，后续绘制不自动同步）
    public SLang.RenderTexture createTexture()
    {
        if this._backend == BasicDraw.BACKEND_GDI
        {
            if this._gdi == null
            {
                ret null
            }
            ret this._gdi.createTexture()
        }
        if this._backend == BasicDraw.BACKEND_RHI
        {
            this._ensureRendered()
            ret SLang.RenderTexture.createRgba( this._pixels, this._w, this._h )
        }
        ret null
    }

    # ================================ 基础图形 ================================

    # ── 点 ──
    public bool point( Int32 x, Int32 y, Int32 color )
    {
        if this._backend == BasicDraw.BACKEND_GDI
        {
            List<Float32> xs = List<Float32>()
            xs.add( SystemConvertFloat32( x ) )
            List<Float32> ys = List<Float32>()
            ys.add( SystemConvertFloat32( y ) )
            if this._gdi == null
            {
                ret false
            }
            ret this._gdi.points( xs, ys, color )
        }
        if this._backend == BasicDraw.BACKEND_RHI
        {
            Float32 cx = SystemConvertFloat32( x ) + 0.5f
            Float32 cy = SystemConvertFloat32( y ) + 0.5f
            ret this._emitQuad( cx - 0.5f, cy - 0.5f, cx + 0.5f, cy - 0.5f, cx + 0.5f, cy + 0.5f, cx - 0.5f, cy + 0.5f, color )
        }
        ret false
    }

    public bool points( List<Float32> xs, List<Float32> ys, Int32 color )
    {
        if this._backend == BasicDraw.BACKEND_GDI
        {
            if this._gdi == null
            {
                ret false
            }
            ret this._gdi.points( xs, ys, color )
        }
        if this._backend == BasicDraw.BACKEND_RHI
        {
            if xs == null || ys == null
            {
                ret false
            }
            Int32 n = xs.length
            if n < 1 || n != ys.length
            {
                ret false
            }
            bool ok = true
            Int32 i = 0
            while i < n
            {
                Float32 vx = xs[i]
                Float32 vy = ys[i]
                if this.point( vx as Int32, vy as Int32, color ) == false
                {
                    ok = false
                }
                i += 1
            }
            ret ok
        }
        ret false
    }

    # ── 线（宽 1 实线）──
    public bool line( Int32 x0, Int32 y0, Int32 x1, Int32 y1, Int32 color )
    {
        ret this.lineEx( x0, y0, x1, y1, 1, BasicDraw.PEN_SOLID, color )
    }

    # ── 线（带笔宽与样式：实线/虚线/点线/点划线/双点划线）──
    # GDI：非实线笔宽钳 1（GDI 硬限制）；RHI 同语义（虚线固定 1px 拆段）。
    public bool lineEx( Int32 x0, Int32 y0, Int32 x1, Int32 y1, Int32 width, Int32 penStyle, Int32 color )
    {
        if this._backend == BasicDraw.BACKEND_GDI
        {
            if this._gdi == null
            {
                ret false
            }
            Int32 si = GdiCanvas.styleInfo( width, penStyle )
            ret this._gdi.lineEx( x0, y0, x1, y1, si, color )
        }
        if this._backend == BasicDraw.BACKEND_RHI
        {
            if this._pipe == null
            {
                ret false
            }
            Float32 fx0 = SystemConvertFloat32( x0 ) + 0.5f
            Float32 fy0 = SystemConvertFloat32( y0 ) + 0.5f
            Float32 fx1 = SystemConvertFloat32( x1 ) + 0.5f
            Float32 fy1 = SystemConvertFloat32( y1 ) + 0.5f
            if penStyle == BasicDraw.PEN_SOLID
            {
                Float32 hw = SystemConvertFloat32( width ) * 0.5f
                ret this._strokeSeg( fx0, fy0, fx1, fy1, hw, color )
            }
            ret this._strokeDashed( fx0, fy0, fx1, fy1, penStyle, color )
        }
        ret false
    }

    # ── 虚线糖方法（1px PEN_DASH）──
    public bool dashedLine( Int32 x0, Int32 y0, Int32 x1, Int32 y1, Int32 color )
    {
        ret this.lineEx( x0, y0, x1, y1, 1, BasicDraw.PEN_DASH, color )
    }

    # ── 折线（宽 1 实线；开放）──
    public bool polyline( List<Float32> xs, List<Float32> ys, Int32 color )
    {
        ret this.polylineEx( xs, ys, 1, BasicDraw.PEN_SOLID, color )
    }

    public bool polylineEx( List<Float32> xs, List<Float32> ys, Int32 width, Int32 penStyle, Int32 color )
    {
        if xs == null || ys == null
        {
            ret false
        }
        Int32 n = xs.length
        if n < 2 || n != ys.length
        {
            ret false
        }
        if this._backend == BasicDraw.BACKEND_GDI
        {
            if this._gdi == null
            {
                ret false
            }
            Int32 si = GdiCanvas.styleInfo( width, penStyle )
            ret this._gdi.polyline( xs, ys, si, color )
        }
        if this._backend == BasicDraw.BACKEND_RHI
        {
            if this._pipe == null
            {
                ret false
            }
            bool ok = true
            Int32 i = 0
            while i < n - 1
            {
                Int32 ni = i + 1
                Float32 x0 = xs[i]
                Float32 y0 = ys[i]
                Float32 x1 = xs[ni]
                Float32 y1 = ys[ni]
                if this.lineEx( x0 as Int32, y0 as Int32, x1 as Int32, y1 as Int32, width, penStyle, color ) == false
                {
                    ok = false
                }
                i += 1
            }
            ret ok
        }
        ret false
    }

    # ── 圆 ──
    public bool circle( Int32 cx, Int32 cy, Int32 r, Int32 color )
    {
        if r < 1
        {
            ret false
        }
        ret this.ellipse( cx - r, cy - r, cx + r, cy + r, color )
    }

    public bool fillCircle( Int32 cx, Int32 cy, Int32 r, Int32 color )
    {
        if r < 1
        {
            ret false
        }
        ret this.fillEllipse( cx - r, cy - r, cx + r, cy + r, color )
    }

    # ── 椭圆（外接矩形 bbox 描边/填充）──
    public bool ellipse( Int32 x0, Int32 y0, Int32 x1, Int32 y1, Int32 color )
    {
        if this._backend == BasicDraw.BACKEND_GDI
        {
            if this._gdi == null
            {
                ret false
            }
            ret this._gdi.ellipse( x0, y0, x1, y1, color )
        }
        if this._backend == BasicDraw.BACKEND_RHI
        {
            if this._pipe == null
            {
                ret false
            }
            Float32 cx = SystemConvertFloat32( x0 + x1 ) * 0.5f
            Float32 cy = SystemConvertFloat32( y0 + y1 ) * 0.5f
            Float32 rx = SystemConvertFloat32( x1 - x0 ) * 0.5f
            Float32 ry = SystemConvertFloat32( y1 - y0 ) * 0.5f
            if rx <= 0.0f || ry <= 0.0f
            {
                ret false
            }
            bool ok = true
            Float32 a = 0.0f
            while a < 6.2831853f
            {
                Float32 nx = a + 0.1308997f
                Float32 c0 = Mathf.cos( a )
                Float32 s0 = Mathf.sin( a )
                Float32 c1 = Mathf.cos( nx )
                Float32 s1 = Mathf.sin( nx )
                if this._strokeSeg( cx + rx * c0, cy + ry * s0, cx + rx * c1, cy + ry * s1, 0.5f, color ) == false
                {
                    ok = false
                }
                a = nx
            }
            ret ok
        }
        ret false
    }

    public bool fillEllipse( Int32 x0, Int32 y0, Int32 x1, Int32 y1, Int32 color )
    {
        if this._backend == BasicDraw.BACKEND_GDI
        {
            if this._gdi == null
            {
                ret false
            }
            ret this._gdi.fillEllipse( x0, y0, x1, y1, color )
        }
        if this._backend == BasicDraw.BACKEND_RHI
        {
            if this._pipe == null
            {
                ret false
            }
            Float32 cx = SystemConvertFloat32( x0 + x1 ) * 0.5f
            Float32 cy = SystemConvertFloat32( y0 + y1 ) * 0.5f
            Float32 rx = SystemConvertFloat32( x1 - x0 ) * 0.5f
            Float32 ry = SystemConvertFloat32( y1 - y0 ) * 0.5f
            if rx <= 0.0f || ry <= 0.0f
            {
                ret false
            }
            bool ok = true
            Int32 steps = 48
            Int32 i = 0
            while i < steps
            {
                Float32 a0 = 6.2831853f * SystemConvertFloat32( i ) / 48.0f
                Float32 a1 = 6.2831853f * SystemConvertFloat32( i + 1 ) / 48.0f
                Float32 px0 = cx + rx * Mathf.cos( a0 )
                Float32 py0 = cy + ry * Mathf.sin( a0 )
                Float32 px1 = cx + rx * Mathf.cos( a1 )
                Float32 py1 = cy + ry * Mathf.sin( a1 )
                if this._emitTri( cx, cy, px0, py0, px1, py1, color ) == false
                {
                    ok = false
                }
                i += 1
            }
            ret ok
        }
        ret false
    }

    # ── 三角形（三角边 = 描边三边）──
    public bool triangle( Int32 x0, Int32 y0, Int32 x1, Int32 y1, Int32 x2, Int32 y2, Int32 color )
    {
        if this._backend == BasicDraw.BACKEND_GDI
        {
            if this._gdi == null
            {
                ret false
            }
            List<Float32> xs = List<Float32>()
            xs.add( SystemConvertFloat32( x0 ) )
            xs.add( SystemConvertFloat32( x1 ) )
            xs.add( SystemConvertFloat32( x2 ) )
            List<Float32> ys = List<Float32>()
            ys.add( SystemConvertFloat32( y0 ) )
            ys.add( SystemConvertFloat32( y1 ) )
            ys.add( SystemConvertFloat32( y2 ) )
            Int32 si = GdiCanvas.styleInfo( 1, BasicDraw.PEN_SOLID )
            ret this._gdi.polyClosed( xs, ys, si, color )
        }
        if this._backend == BasicDraw.BACKEND_RHI
        {
            bool e0 = this.line( x0, y0, x1, y1, color )
            bool e1 = this.line( x1, y1, x2, y2, color )
            bool e2 = this.line( x2, y2, x0, y0, color )
            if e0 == false
            {
                ret false
            }
            if e1 == false
            {
                ret false
            }
            ret e2
        }
        ret false
    }

    public bool fillTriangle( Int32 x0, Int32 y0, Int32 x1, Int32 y1, Int32 x2, Int32 y2, Int32 color )
    {
        if this._backend == BasicDraw.BACKEND_GDI
        {
            if this._gdi == null
            {
                ret false
            }
            List<Float32> xs = List<Float32>()
            xs.add( SystemConvertFloat32( x0 ) )
            xs.add( SystemConvertFloat32( x1 ) )
            xs.add( SystemConvertFloat32( x2 ) )
            List<Float32> ys = List<Float32>()
            ys.add( SystemConvertFloat32( y0 ) )
            ys.add( SystemConvertFloat32( y1 ) )
            ys.add( SystemConvertFloat32( y2 ) )
            ret this._gdi.fillPolygon( xs, ys, -1, color )
        }
        if this._backend == BasicDraw.BACKEND_RHI
        {
            Float32 fx0 = SystemConvertFloat32( x0 ) + 0.5f
            Float32 fy0 = SystemConvertFloat32( y0 ) + 0.5f
            Float32 fx1 = SystemConvertFloat32( x1 ) + 0.5f
            Float32 fy1 = SystemConvertFloat32( y1 ) + 0.5f
            Float32 fx2 = SystemConvertFloat32( x2 ) + 0.5f
            Float32 fy2 = SystemConvertFloat32( y2 ) + 0.5f
            ret this._emitTri( fx0, fy0, fx1, fy1, fx2, fy2, color )
        }
        ret false
    }

    # ── 四边形（4 点描边/填充）──
    public bool quad( List<Float32> xs, List<Float32> ys, Int32 color )
    {
        if this._backend == BasicDraw.BACKEND_GDI
        {
            if this._gdi == null
            {
                ret false
            }
            if xs == null || ys == null
            {
                ret false
            }
            if xs.length != 4 || ys.length != 4
            {
                ret false
            }
            Int32 si = GdiCanvas.styleInfo( 1, BasicDraw.PEN_SOLID )
            ret this._gdi.polyClosed( xs, ys, si, color )
        }
        if this._backend == BasicDraw.BACKEND_RHI
        {
            if this._pipe == null
            {
                ret false
            }
            if xs == null || ys == null
            {
                ret false
            }
            if xs.length != 4 || ys.length != 4
            {
                ret false
            }
            bool ok = true
            Int32 i = 0
            while i < 4
            {
                Int32 j = i + 1
                if j == 4
                {
                    j = 0
                }
                Float32 x0 = xs[i]
                Float32 y0 = ys[i]
                Float32 x1 = xs[j]
                Float32 y1 = ys[j]
                if this.line( x0 as Int32, y0 as Int32, x1 as Int32, y1 as Int32, color ) == false
                {
                    ok = false
                }
                i += 1
            }
            ret ok
        }
        ret false
    }

    public bool fillQuad( List<Float32> xs, List<Float32> ys, Int32 color )
    {
        if xs == null || ys == null
        {
            ret false
        }
        if xs.length != 4 || ys.length != 4
        {
            ret false
        }
        if this._backend == BasicDraw.BACKEND_GDI
        {
            if this._gdi == null
            {
                ret false
            }
            ret this._gdi.fillPolygon( xs, ys, -1, color )
        }
        if this._backend == BasicDraw.BACKEND_RHI
        {
            Float32 ax = xs[0]
            Float32 ay = ys[0]
            Float32 bx = xs[1]
            Float32 by = ys[1]
            Float32 cx = xs[2]
            Float32 cy = ys[2]
            Float32 dx = xs[3]
            Float32 dy = ys[3]
            ret this._emitQuad( ax, ay, bx, by, cx, cy, dx, dy, color )
        }
        ret false
    }

    # ── 矩形 ──
    public bool rect( Int32 x0, Int32 y0, Int32 x1, Int32 y1, Int32 color )
    {
        if this._backend == BasicDraw.BACKEND_GDI
        {
            if this._gdi == null
            {
                ret false
            }
            ret this._gdi.rect( x0, y0, x1, y1, color )
        }
        if this._backend == BasicDraw.BACKEND_RHI
        {
            bool e0 = this.line( x0, y0, x1, y0, color )
            bool e1 = this.line( x1, y0, x1, y1, color )
            bool e2 = this.line( x1, y1, x0, y1, color )
            bool e3 = this.line( x0, y1, x0, y0, color )
            if e0 == false
            {
                ret false
            }
            if e1 == false
            {
                ret false
            }
            if e2 == false
            {
                ret false
            }
            ret e3
        }
        ret false
    }

    public bool fillRect( Int32 x0, Int32 y0, Int32 x1, Int32 y1, Int32 color )
    {
        if this._backend == BasicDraw.BACKEND_GDI
        {
            if this._gdi == null
            {
                ret false
            }
            ret this._gdi.fillRect( x0, y0, x1, y1, color )
        }
        if this._backend == BasicDraw.BACKEND_RHI
        {
            Float32 ax = SystemConvertFloat32( x0 ) + 0.5f
            Float32 ay = SystemConvertFloat32( y0 ) + 0.5f
            Float32 bx = SystemConvertFloat32( x1 ) + 0.5f
            Float32 by = SystemConvertFloat32( y1 ) + 0.5f
            ret this._emitQuad( ax, ay, bx, ay, bx, by, ax, by, color )
        }
        ret false
    }

    # ── 多边形（描边 = 闭合折线；填充 RHI 为扇形三角化，凸多边形精确）──
    public bool polygon( List<Float32> xs, List<Float32> ys, Int32 color )
    {
        if this._backend == BasicDraw.BACKEND_GDI
        {
            if this._gdi == null
            {
                ret false
            }
            if xs == null || ys == null
            {
                ret false
            }
            Int32 si = GdiCanvas.styleInfo( 1, BasicDraw.PEN_SOLID )
            ret this._gdi.polyClosed( xs, ys, si, color )
        }
        if this._backend == BasicDraw.BACKEND_RHI
        {
            if this._pipe == null
            {
                ret false
            }
            if xs == null || ys == null
            {
                ret false
            }
            Int32 n = xs.length
            if n < 3 || n != ys.length
            {
                ret false
            }
            bool ok = true
            Int32 i = 0
            while i < n
            {
                Int32 j = i + 1
                if j == n
                {
                    j = 0
                }
                Float32 x0 = xs[i]
                Float32 y0 = ys[i]
                Float32 x1 = xs[j]
                Float32 y1 = ys[j]
                if this.line( x0 as Int32, y0 as Int32, x1 as Int32, y1 as Int32, color ) == false
                {
                    ok = false
                }
                i += 1
            }
            ret ok
        }
        ret false
    }

    public bool fillPolygon( List<Float32> xs, List<Float32> ys, Int32 color )
    {
        if xs == null || ys == null
        {
            ret false
        }
        Int32 n = xs.length
        if n < 3 || n != ys.length
        {
            ret false
        }
        if this._backend == BasicDraw.BACKEND_GDI
        {
            if this._gdi == null
            {
                ret false
            }
            ret this._gdi.fillPolygon( xs, ys, -1, color )
        }
        if this._backend == BasicDraw.BACKEND_RHI
        {
            bool ok = true
            Int32 i = 1
            while i < n - 1
            {
                Int32 ni = i + 1
                Float32 x0 = xs[0]
                Float32 y0 = ys[0]
                Float32 x1 = xs[i]
                Float32 y1 = ys[i]
                Float32 x2 = xs[ni]
                Float32 y2 = ys[ni]
                if this._emitTri( x0, y0, x1, y1, x2, y2, color ) == false
                {
                    ok = false
                }
                i += 1
            }
            ret ok
        }
        ret false
    }

    # ── 贝塞尔（点数 n ≥ 4 且 (n-1)%3==0；每段 3 控制点）──
    public bool bezier( List<Float32> xs, List<Float32> ys, Int32 color )
    {
        if xs == null || ys == null
        {
            ret false
        }
        Int32 n = xs.length
        if n < 4
        {
            ret false
        }
        if n != ys.length
        {
            ret false
        }
        if ( n - 1 ) % 3 != 0
        {
            ret false
        }
        if this._backend == BasicDraw.BACKEND_GDI
        {
            if this._gdi == null
            {
                ret false
            }
            ret this._gdi.bezier( xs, ys, color )
        }
        if this._backend == BasicDraw.BACKEND_RHI
        {
            if this._pipe == null
            {
                ret false
            }
            bool ok = true
            Int32 seg = 0
            Int32 segs = ( n - 1 ) / 3
            while seg < segs
            {
                Int32 b = seg * 3
                Int32 b1 = b + 1
                Int32 b2 = b + 2
                Int32 b3 = b + 3
                Float32 p0x = xs[b]
                Float32 p0y = ys[b]
                Float32 p1x = xs[b1]
                Float32 p1y = ys[b1]
                Float32 p2x = xs[b2]
                Float32 p2y = ys[b2]
                Float32 p3x = xs[b3]
                Float32 p3y = ys[b3]
                Float32 px = p0x + 0.5f
                Float32 py = p0y + 0.5f
                Int32 st = 1
                while st <= 16
                {
                    Float32 t = SystemConvertFloat32( st ) / 16.0f
                    Float32 u = 1.0f - t
                    # 注意：伯恩斯坦基权重量 w0..w3 —— 不能叫 b1/b2，
                    # 会遮蔽外层同名 Int32 控制点索引（同名重复声明运行时错乱）
                    Float32 w0 = u * u * u
                    Float32 w1 = 3.0f * u * u * t
                    Float32 w2 = 3.0f * u * t * t
                    Float32 w3 = t * t * t
                    Float32 qx = w0 * p0x + w1 * p1x + w2 * p2x + w3 * p3x + 0.5f
                    Float32 qy = w0 * p0y + w1 * p1y + w2 * p2y + w3 * p3y + 0.5f
                    if this._strokeSeg( px, py, qx, qy, 0.5f, color ) == false
                    {
                        ok = false
                    }
                    px = qx
                    py = qy
                    st += 1
                }
                seg += 1
            }
            ret ok
        }
        ret false
    }

    # ── 圆弧（GDI Arc 语义：bbox + 起始/终止射线点）──
    # coords = 8 浮点 [x0,y0,x1,y1, sx,sy, ex,ey]
    public bool arc( List<Float32> coords, Int32 color )
    {
        if coords == null
        {
            ret false
        }
        if coords.length < 8
        {
            ret false
        }
        if this._backend == BasicDraw.BACKEND_GDI
        {
            if this._gdi == null
            {
                ret false
            }
            ret this._gdi.arc( coords, color )
        }
        if this._backend == BasicDraw.BACKEND_RHI
        {
            if this._pipe == null
            {
                ret false
            }
            Float32 bx0 = coords[0]
            Float32 by0 = coords[1]
            Float32 bx1 = coords[2]
            Float32 by1 = coords[3]
            Float32 sx = coords[4]
            Float32 sy = coords[5]
            Float32 ex = coords[6]
            Float32 ey = coords[7]
            Float32 cx = ( bx0 + bx1 ) * 0.5f
            Float32 cy = ( by0 + by1 ) * 0.5f
            Float32 rx = ( bx1 - bx0 ) * 0.5f
            Float32 ry = ( by1 - by0 ) * 0.5f
            if rx <= 0.0f || ry <= 0.0f
            {
                ret false
            }
            # 屏幕系角度递增方向扫弧（y 向下视觉顺时针；GDI 侧 AD_CLOCKWISE 同语义）
            Float32 a0 = Mathf.atan2( sy - cy, sx - cx )
            Float32 a1 = Mathf.atan2( ey - cy, ex - cx )
            Float32 delta = a1 - a0
            while delta < 0.0f
            {
                delta += 6.2831853f
            }
            bool ok = true
            Float32 px = cx + rx * Mathf.cos( a0 ) + 0.5f
            Float32 py = cy + ry * Mathf.sin( a0 ) + 0.5f
            Int32 st = 1
            while st <= 32
            {
                Float32 t = SystemConvertFloat32( st ) / 32.0f
                Float32 a = a0 + delta * t
                Float32 qx = cx + rx * Mathf.cos( a ) + 0.5f
                Float32 qy = cy + ry * Mathf.sin( a ) + 0.5f
                if this._strokeSeg( px, py, qx, qy, 0.5f, color ) == false
                {
                    ok = false
                }
                px = qx
                py = qy
                st += 1
            }
            ret ok
        }
        ret false
    }

    # ── 曲线糖方法：圆上从 a0 弧度逆时针（视觉）扫到 a1 弧度 ──
    public bool curve( Int32 cx, Int32 cy, Int32 r, Float32 a0, Float32 a1, Int32 color )
    {
        if r < 1
        {
            ret false
        }
        Float32 fcx = SystemConvertFloat32( cx )
        Float32 fcy = SystemConvertFloat32( cy )
        Float32 fr = SystemConvertFloat32( r )
        List<Float32> c = List<Float32>()
        c.add( fcx - fr )
        c.add( fcy - fr )
        c.add( fcx + fr )
        c.add( fcy + fr )
        c.add( fcx + fr * Mathf.cos( a0 ) )
        c.add( fcy + fr * Mathf.sin( a0 ) )
        c.add( fcx + fr * Mathf.cos( a1 ) )
        c.add( fcy + fr * Mathf.sin( a1 ) )
        ret this.arc( c, color )
    }

    # ── 方向箭头：主线 + 三角头（两后端同构）──
    public bool arrow( Int32 x0, Int32 y0, Int32 x1, Int32 y1, Int32 headSize, Int32 color )
    {
        if headSize < 2
        {
            ret false
        }
        Float32 fx0 = SystemConvertFloat32( x0 ) + 0.5f
        Float32 fy0 = SystemConvertFloat32( y0 ) + 0.5f
        Float32 fx1 = SystemConvertFloat32( x1 ) + 0.5f
        Float32 fy1 = SystemConvertFloat32( y1 ) + 0.5f
        Float32 hs = SystemConvertFloat32( headSize )
        Float32 dx = fx1 - fx0
        Float32 dy = fy1 - fy0
        Float32 len = Mathf.sqrt( dx * dx + dy * dy )
        if len < 1.0f
        {
            ret this.point( x1, y1, color )
        }
        Float32 ux = dx / len
        Float32 uy = dy / len
        Float32 bx = fx1 - ux * hs
        Float32 by = fy1 - uy * hs
        # 头底两侧点（垂直方向 ±hs/2）
        Float32 c0x = bx - uy * hs * 0.5f
        Float32 c0y = by + ux * hs * 0.5f
        Float32 c1x = bx + uy * hs * 0.5f
        Float32 c1y = by - ux * hs * 0.5f
        bool okLine = false
        bool okHead = false
        if this._backend == BasicDraw.BACKEND_GDI
        {
            if this._gdi == null
            {
                ret false
            }
            Int32 bxi = bx as Int32
            Int32 byi = by as Int32
            okLine = this._gdi.line( x0, y0, bxi, byi, color )
            List<Float32> xs = List<Float32>()
            xs.add( fx1 )
            xs.add( c0x )
            xs.add( c1x )
            List<Float32> ys = List<Float32>()
            ys.add( fy1 )
            ys.add( c0y )
            ys.add( c1y )
            okHead = this._gdi.fillPolygon( xs, ys, -1, color )
        }
        elif this._backend == BasicDraw.BACKEND_RHI
        {
            if this._pipe == null
            {
                ret false
            }
            okLine = this._strokeSeg( fx0, fy0, bx, by, 0.5f, color )
            okHead = this._emitTri( fx1, fy1, c0x, c0y, c1x, c1y, color )
        }
        ret okLine && okHead
    }

    # ================================ RHI 内部 ================================

    # 调色板登记（返回索引；满 256 返回 -1）
    Int32 _paletteIndex( Int32 color )
    {
        Int32 idx = -1
        Int32 n = this._palColors.length
        Int32 i = 0
        while i < n
        {
            Int32 c = this._palColors[i]
            if idx < 0 && c == color
            {
                idx = i
            }
            i += 1
        }
        if idx >= 0
        {
            ret idx
        }
        if n >= BasicDraw.PALETTE_MAX
        {
            ret -1
        }
        this._palColors.add( color )
        Int32 off = n * 4
        Memory.writeI8( this._palData, off, ( color >> 16 ) & 255 )
        Memory.writeI8( this._palData, off + 1, ( color >> 8 ) & 255 )
        Memory.writeI8( this._palData, off + 2, color & 255 )
        Memory.writeI8( this._palData, off + 3, ( color >> 24 ) & 255 )
        this._palDirty = true
        ret n
    }

    # 写单顶点（屏幕 top-down 浮点坐标 → world y 翻转；uv = 调色板 texel 中心）
    void _writeVert( Int32 idx, Float32 sx, Float32 sy, Int32 palIdx )
    {
        Int32 off = idx * 16
        Float32 wy = SystemConvertFloat32( this._h ) - sy
        Float32 u = ( SystemConvertFloat32( palIdx ) + 0.5f ) / 256.0f
        Memory.writeF32( this._verts, off, sx )
        Memory.writeF32( this._verts, off + 4, wy )
        Memory.writeF32( this._verts, off + 8, u )
        Memory.writeF32( this._verts, off + 12, 0.5f )
    }

    # 三角形（屏幕 top-down 浮点坐标）
    bool _emitTri( Float32 x0, Float32 y0, Float32 x1, Float32 y1, Float32 x2, Float32 y2, Int32 color )
    {
        if this._vertCount + 3 > BasicDraw.RHI_MAX_VERTS
        {
            ret false
        }
        Int32 p = this._paletteIndex( color )
        if p < 0
        {
            ret false
        }
        this._writeVert( this._vertCount, x0, y0, p )
        this._writeVert( this._vertCount + 1, x1, y1, p )
        this._writeVert( this._vertCount + 2, x2, y2, p )
        this._vertCount += 3
        this._dirty = true
        ret true
    }

    # 四边形（a-b-c-d 环序，拆 2 个三角形）
    bool _emitQuad( Float32 ax, Float32 ay, Float32 bx, Float32 by, Float32 cx, Float32 cy, Float32 dx, Float32 dy, Int32 color )
    {
        bool t0 = this._emitTri( ax, ay, bx, by, cx, cy, color )
        bool t1 = this._emitTri( ax, ay, cx, cy, dx, dy, color )
        ret t0 && t1
    }

    # 线段条带（起点→终点，半宽 hw；两端平头，与 GDI 几何笔行为一致）
    # 语义与 GDI 光栅对齐：起点像素含（起端帽沿方向延长 0.5 使起点像素中心
    # 落入 quad 内部）、终点像素排他（quad 终边恰过终点像素中心，top-left
    # 边界规则不点亮——与 GDI LineTo/PolyBezier exclusive-end 一致）
    bool _strokeSeg( Float32 x0, Float32 y0, Float32 x1, Float32 y1, Float32 hw, Int32 color )
    {
        Float32 dx = x1 - x0
        Float32 dy = y1 - y0
        Float32 len = Mathf.sqrt( dx * dx + dy * dy )
        if len < 0.0001f
        {
            ret true
        }
        Float32 ux = dx / len
        Float32 uy = dy / len
        Float32 ax = x0 - ux * 0.5f
        Float32 ay = y0 - uy * 0.5f
        Float32 bx = x1
        Float32 by = y1
        Float32 ox = -dy / len * hw
        Float32 oy = dx / len * hw
        ret this._emitQuad( ax + ox, ay + oy, bx + ox, by + oy, bx - ox, by - oy, ax - ox, ay - oy, color )
    }

    # 装饰线拆段（1px：dash 4/4、dot 1/2、dashdot 4,4,1,4、dashdotdot 4,4,1,4,1,4）
    bool _strokeDashed( Float32 x0, Float32 y0, Float32 x1, Float32 y1, Int32 penStyle, Int32 color )
    {
        Float32 dx = x1 - x0
        Float32 dy = y1 - y0
        Float32 len = Mathf.sqrt( dx * dx + dy * dy )
        if len < 0.0001f
        {
            ret true
        }
        Float32 ux = dx / len
        Float32 uy = dy / len
        List<Float32> pat = List<Float32>()
        if penStyle == BasicDraw.PEN_DASH
        {
            pat.add( 4.0f )
            pat.add( 4.0f )
        }
        elif penStyle == BasicDraw.PEN_DOT
        {
            pat.add( 1.0f )
            pat.add( 2.0f )
        }
        elif penStyle == BasicDraw.PEN_DASHDOT
        {
            pat.add( 4.0f )
            pat.add( 4.0f )
            pat.add( 1.0f )
            pat.add( 4.0f )
        }
        else
        {
            pat.add( 4.0f )
            pat.add( 4.0f )
            pat.add( 1.0f )
            pat.add( 4.0f )
            pat.add( 1.0f )
            pat.add( 4.0f )
        }
        Int32 pn = pat.length
        Float32 pos = 0.0f
        Int32 k = 0
        bool ok = true
        while pos < len
        {
            Int32 ki = k % pn
            Float32 run = pat[ki]
            if pos + run > len
            {
                run = len - pos
            }
            if k % 2 == 0
            {
                Float32 qx0 = x0 + ux * pos
                Float32 qy0 = y0 + uy * pos
                Float32 qx1 = x0 + ux * ( pos + run )
                Float32 qy1 = y0 + uy * ( pos + run )
                if this._strokeSeg( qx0, qy0, qx1, qy1, 0.5f, color ) == false
                {
                    ok = false
                }
            }
            pos += run
            k += 1
        }
        ret ok
    }

    # 惰性渲染：调色板同步 + 槽上传 + renderFrame 回读
    void _ensureRendered()
    {
        if this._backend != BasicDraw.BACKEND_RHI
        {
            ret
        }
        if this._pipe == null
        {
            ret
        }
        if this._dirty == false && this._rendered == true
        {
            ret
        }
        if this._palDirty
        {
            if this._palette != null
            {
                this._palette.updatePixels( this._palData )
            }
            this._palDirty = false
        }
        Int32 slot = 0
        while slot < 4
        {
            Int32 lo = slot * BasicDraw.RHI_SLOT_VERTS
            if this._vertCount > lo
            {
                Int32 cnt = this._vertCount - lo
                if cnt > BasicDraw.RHI_SLOT_VERTS
                {
                    cnt = BasicDraw.RHI_SLOT_VERTS
                }
                Int64 slotBase = this._verts + SystemConvertInt64( slot * 65536 )
                this._pipe.uploadMesh( slot, slotBase, cnt )
            }
            elif this._peakVerts > lo
            {
                # 该槽曾被使用、clear 后现为空：退化三角形覆盖 GPU 残留
                this._pipe.uploadMesh( slot, this._degenPtr, 3 )
            }
            slot += 1
        }
        if this._vertCount > this._peakVerts
        {
            this._peakVerts = this._vertCount
        }
        this._pipe.renderFrame( 0.0f, this._pixels )
        this._dirty = false
        this._rendered = true
    }
}
