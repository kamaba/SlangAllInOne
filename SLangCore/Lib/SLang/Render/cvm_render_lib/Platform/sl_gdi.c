/* =========================================================================
 * sl_gdi.c —— Windows 系统 GDI 绘图兼容层（render CVM 原生实现）
 *
 * 与 WinDraw.sl 那种纯 SL 软光栅不同：本文件直接调用 Windows GDI
 * （CreateDIBSection / HDC / GDI pen-brush / TextOutW）在离屏 32bpp DIB
 * 上作图，再把 GDI 原生 BGRA 位流转成库统一的 top-down RGBA8 契约。
 *
 * 约定：
 *   - 句柄 = SlrGdiCanvas*（非零 IR 指针），SL 侧用 Int64 承载；
 *   - 颜色 = 0xAARRGGBB（与库像素契约一致）；GDI 画刷只吃 RGB，
 *     v1 采用「非透明像素 alpha 统一置 255」策略（clear 的 alpha 生效）；
 *   - DIB 用负高度创建（top-down），与 RGBA8 top-down 契约一致；
 *     GDI 内存字节序为 BGRA，to_rgba 负责交换 R/B；
 *   - 非 Windows 平台全部导出安全降级（返回 0/false），不编 GDI 头。
 * ========================================================================= */
#include "vm_sl_render.h"
#include "sl_render_internal.h"

#if defined(_WIN32)

typedef struct SlrGdiCanvas
{
    int w;
    int h;
    HDC hdc;
    HBITMAP bitmap;
    HBITMAP oldBitmap;
    unsigned char* bits;
} SlrGdiCanvas;

static void slr_gdi_apply_opaque( SlrGdiCanvas* c )
{
    int total = c->w * c->h;
    int i = 0;
    while ( i < total )
    {
        unsigned char* p = c->bits + i * 4;
        if ( p[0] != 0 || p[1] != 0 || p[2] != 0 )
        {
            p[3] = 255;
        }
        i += 1;
    }
}

static COLORREF slr_gdi_color( int rgba )
{
    unsigned int v = (unsigned int)rgba;
    return RGB( ( v >> 16 ) & 255, ( v >> 8 ) & 255, v & 255 );
}

/* style_info -> GDI pen style（0..4 -> PS_*） */
static int slr_gdi_pen_style( int s )
{
    switch ( s )
    {
        case 1: return PS_DASH;
        case 2: return PS_DOT;
        case 3: return PS_DASHDOT;
        case 4: return PS_DASHDOTDOT;
    }
    return PS_SOLID;
}

/* 造笔：style_info = (width << 8) | pen_style。GDI 硬限制：非实线装饰笔
 * 宽度必须 1（宽>1 自动回实线）——非 solid 显式钳 width=1 保持虚线语义。 */
static HPEN slr_gdi_make_pen( int style_info, int rgba )
{
    int width = ( style_info >> 8 ) & 255;
    int style = slr_gdi_pen_style( style_info & 255 );
    if ( width < 1 )
    {
        width = 1;
    }
    if ( width > 32 )
    {
        width = 32;
    }
    if ( style != PS_SOLID && width > 1 )
    {
        width = 1;
    }
    return CreatePen( style, width, slr_gdi_color( rgba ) );
}

/* float 对数组 -> POINT 数组（GDI 折线/多边形/贝塞尔共用） */
static POINT* slr_gdi_to_points( const float* points, int count )
{
    POINT* pts = (POINT*)malloc( (size_t)count * sizeof( POINT ) );
    int i = 0;
    if ( pts == 0 )
    {
        return 0;
    }
    while ( i < count )
    {
        pts[i].x = (LONG)points[i * 2];
        pts[i].y = (LONG)points[i * 2 + 1];
        i += 1;
    }
    return pts;
}

static SlrGdiCanvas* slr_gdi_get( int64_t handle )
{
    SlrGdiCanvas* c = (SlrGdiCanvas*)(intptr_t)handle;
    if ( c == 0 || c->bits == 0 || c->hdc == 0 )
    {
        set_error( SLR_E_BAD_HANDLE );
        return 0;
    }
    return c;
}

SLR_API int64_t slr_gdi_create( int w, int h )
{
    SlrGdiCanvas* c;
    HDC screen;
    BITMAPINFO bmi;
    if ( w <= 0 || h <= 0 || w > 8192 || h > 8192 )
    {
        set_error( SLR_E_BAD_PARAM );
        return 0;
    }
    c = (SlrGdiCanvas*)calloc( 1, sizeof( SlrGdiCanvas ) );
    if ( c == 0 )
    {
        set_error( SLR_E_MEMORY );
        return 0;
    }
    screen = GetDC( 0 );
    if ( screen == 0 )
    {
        free( c );
        set_error( SLR_E_WINDOW );
        return 0;
    }
    c->hdc = CreateCompatibleDC( screen );
    if ( c->hdc == 0 )
    {
        ReleaseDC( 0, screen );
        free( c );
        set_error( SLR_E_WINDOW );
        return 0;
    }
    memset( &bmi, 0, sizeof( bmi ) );
    bmi.bmiHeader.biSize = sizeof( BITMAPINFOHEADER );
    bmi.bmiHeader.biWidth = w;
    bmi.bmiHeader.biHeight = -h;              /* top-down DIB */
    bmi.bmiHeader.biPlanes = 1;
    bmi.bmiHeader.biBitCount = 32;
    bmi.bmiHeader.biCompression = BI_RGB;
    c->bitmap = CreateDIBSection( c->hdc, &bmi, DIB_RGB_COLORS,
        (void**)&c->bits, 0, 0 );
    ReleaseDC( 0, screen );
    if ( c->bitmap == 0 || c->bits == 0 )
    {
        DeleteDC( c->hdc );
        free( c );
        set_error( SLR_E_MEMORY );
        return 0;
    }
    c->oldBitmap = (HBITMAP)SelectObject( c->hdc, c->bitmap );
    c->w = w;
    c->h = h;
    SetBkMode( c->hdc, TRANSPARENT );
    slr_gdi_clear( (int64_t)(intptr_t)c, 0 );
    return (int64_t)(intptr_t)c;
}

SLR_API int slr_gdi_destroy( int64_t handle )
{
    SlrGdiCanvas* c = slr_gdi_get( handle );
    if ( c == 0 )
    {
        return 0;
    }
    if ( c->oldBitmap != 0 )
    {
        SelectObject( c->hdc, c->oldBitmap );
    }
    if ( c->bitmap != 0 )
    {
        DeleteObject( c->bitmap );
    }
    DeleteDC( c->hdc );
    free( c );
    return 1;
}

SLR_API int slr_gdi_size( int64_t handle, int* w, int* h )
{
    SlrGdiCanvas* c = slr_gdi_get( handle );
    if ( c == 0 || w == 0 || h == 0 )
    {
        set_error( SLR_E_BAD_PARAM );
        return 0;
    }
    *w = c->w;
    *h = c->h;
    return 1;
}

SLR_API int64_t slr_gdi_bits( int64_t handle )
{
    SlrGdiCanvas* c = slr_gdi_get( handle );
    if ( c == 0 )
    {
        return 0;
    }
    return (int64_t)(intptr_t)c->bits;
}

SLR_API int slr_gdi_clear( int64_t handle, int rgba )
{
    SlrGdiCanvas* c = slr_gdi_get( handle );
    int total;
    int i = 0;
    unsigned int v;
    unsigned char b, g, r, a;
    if ( c == 0 )
    {
        return 0;
    }
    v = (unsigned int)rgba;
    b = (unsigned char)( v & 255 );
    g = (unsigned char)( ( v >> 8 ) & 255 );
    r = (unsigned char)( ( v >> 16 ) & 255 );
    a = (unsigned char)( ( v >> 24 ) & 255 );
    total = c->w * c->h;
    while ( i < total )
    {
        unsigned char* p = c->bits + i * 4;
        p[0] = b;
        p[1] = g;
        p[2] = r;
        p[3] = a;
        i += 1;
    }
    return 1;
}

SLR_API int slr_gdi_set_pixel( int64_t handle, int x, int y, int rgba )
{
    SlrGdiCanvas* c = slr_gdi_get( handle );
    if ( c == 0 || x < 0 || y < 0 || x >= c->w || y >= c->h )
    {
        return 0;
    }
    SetPixel( c->hdc, x, y, slr_gdi_color( rgba ) );
    slr_gdi_apply_opaque( c );
    return 1;
}

SLR_API int slr_gdi_get_pixel( int64_t handle, int x, int y )
{
    SlrGdiCanvas* c = slr_gdi_get( handle );
    unsigned char* p;
    if ( c == 0 || x < 0 || y < 0 || x >= c->w || y >= c->h )
    {
        return -1;
    }
    p = c->bits + ( y * c->w + x ) * 4;   /* DIB: B,G,R,A */
    return ( (int)p[3] << 24 ) | ( (int)p[2] << 16 ) | ( (int)p[1] << 8 ) | (int)p[0];
}

SLR_API int slr_gdi_line( int64_t handle, int x0, int y0, int x1, int y1, int rgba )
{
    SlrGdiCanvas* c = slr_gdi_get( handle );
    HPEN pen;
    HPEN oldPen;
    if ( c == 0 )
    {
        return 0;
    }
    pen = CreatePen( PS_SOLID, 1, slr_gdi_color( rgba ) );
    oldPen = (HPEN)SelectObject( c->hdc, pen );
    MoveToEx( c->hdc, x0, y0, 0 );
    LineTo( c->hdc, x1, y1 );
    SelectObject( c->hdc, oldPen );
    DeleteObject( pen );
    slr_gdi_apply_opaque( c );
    return 1;
}

SLR_API int slr_gdi_rect( int64_t handle, int x0, int y0, int x1, int y1, int rgba )
{
    SlrGdiCanvas* c = slr_gdi_get( handle );
    HBRUSH oldBrush;
    HPEN pen;
    HPEN oldPen;
    if ( c == 0 )
    {
        return 0;
    }
    oldBrush = (HBRUSH)SelectObject( c->hdc, GetStockObject( NULL_BRUSH ) );
    pen = CreatePen( PS_SOLID, 1, slr_gdi_color( rgba ) );
    oldPen = (HPEN)SelectObject( c->hdc, pen );
    Rectangle( c->hdc, x0, y0, x1, y1 );
    SelectObject( c->hdc, oldPen );
    DeleteObject( pen );
    SelectObject( c->hdc, oldBrush );
    slr_gdi_apply_opaque( c );
    return 1;
}

SLR_API int slr_gdi_fill_rect( int64_t handle, int x0, int y0, int x1, int y1, int rgba )
{
    SlrGdiCanvas* c = slr_gdi_get( handle );
    HBRUSH brush;
    HBRUSH oldBrush;
    HPEN pen;
    HPEN oldPen;
    RECT rc;
    if ( c == 0 )
    {
        return 0;
    }
    rc.left = x0;
    rc.top = y0;
    rc.right = x1;
    rc.bottom = y1;
    brush = CreateSolidBrush( slr_gdi_color( rgba ) );
    oldBrush = (HBRUSH)SelectObject( c->hdc, brush );
    pen = CreatePen( PS_SOLID, 1, slr_gdi_color( rgba ) );
    oldPen = (HPEN)SelectObject( c->hdc, pen );
    FillRect( c->hdc, &rc, brush );
    SelectObject( c->hdc, oldPen );
    DeleteObject( pen );
    SelectObject( c->hdc, oldBrush );
    DeleteObject( brush );
    slr_gdi_apply_opaque( c );
    return 1;
}

SLR_API int slr_gdi_ellipse( int64_t handle, int x0, int y0, int x1, int y1, int rgba )
{
    SlrGdiCanvas* c = slr_gdi_get( handle );
    HBRUSH oldBrush;
    HPEN pen;
    HPEN oldPen;
    if ( c == 0 )
    {
        return 0;
    }
    oldBrush = (HBRUSH)SelectObject( c->hdc, GetStockObject( NULL_BRUSH ) );
    pen = CreatePen( PS_SOLID, 1, slr_gdi_color( rgba ) );
    oldPen = (HPEN)SelectObject( c->hdc, pen );
    Ellipse( c->hdc, x0, y0, x1, y1 );
    SelectObject( c->hdc, oldPen );
    DeleteObject( pen );
    SelectObject( c->hdc, oldBrush );
    slr_gdi_apply_opaque( c );
    return 1;
}

SLR_API int slr_gdi_fill_ellipse( int64_t handle, int x0, int y0, int x1, int y1, int rgba )
{
    SlrGdiCanvas* c = slr_gdi_get( handle );
    HBRUSH brush;
    HBRUSH oldBrush;
    HPEN pen;
    HPEN oldPen;
    if ( c == 0 )
    {
        return 0;
    }
    brush = CreateSolidBrush( slr_gdi_color( rgba ) );
    oldBrush = (HBRUSH)SelectObject( c->hdc, brush );
    pen = CreatePen( PS_SOLID, 1, slr_gdi_color( rgba ) );
    oldPen = (HPEN)SelectObject( c->hdc, pen );
    Ellipse( c->hdc, x0, y0, x1, y1 );
    SelectObject( c->hdc, oldPen );
    DeleteObject( pen );
    SelectObject( c->hdc, oldBrush );
    DeleteObject( brush );
    slr_gdi_apply_opaque( c );
    return 1;
}

SLR_API int slr_gdi_polygon( int64_t handle, const float* points, int count,
                             int stroke, int fill )
{
    SlrGdiCanvas* c = slr_gdi_get( handle );
    POINT* pts;
    HBRUSH brush;
    HBRUSH oldBrush;
    HPEN pen;
    HPEN oldPen;
    int i = 0;
    if ( c == 0 || points == 0 || count < 3 || count > 4096 )
    {
        set_error( SLR_E_BAD_PARAM );
        return 0;
    }
    pts = (POINT*)malloc( (size_t)count * sizeof( POINT ) );
    if ( pts == 0 )
    {
        set_error( SLR_E_MEMORY );
        return 0;
    }
    while ( i < count )
    {
        pts[i].x = (LONG)points[i * 2];
        pts[i].y = (LONG)points[i * 2 + 1];
        i += 1;
    }
    brush = CreateSolidBrush( slr_gdi_color( fill ) );
    oldBrush = (HBRUSH)SelectObject( c->hdc, brush );
    pen = CreatePen( PS_SOLID, 1, slr_gdi_color( stroke ) );
    oldPen = (HPEN)SelectObject( c->hdc, pen );
    Polygon( c->hdc, pts, count );
    SelectObject( c->hdc, oldPen );
    DeleteObject( pen );
    SelectObject( c->hdc, oldBrush );
    DeleteObject( brush );
    free( pts );
    slr_gdi_apply_opaque( c );
    return 1;
}

SLR_API int slr_gdi_blit( int64_t dst, int64_t src, int x, int y )
{
    SlrGdiCanvas* d = slr_gdi_get( dst );
    SlrGdiCanvas* s = slr_gdi_get( src );
    if ( d == 0 || s == 0 )
    {
        return 0;
    }
    BitBlt( d->hdc, x, y, s->w, s->h, s->hdc, 0, 0, SRCCOPY );
    slr_gdi_apply_opaque( d );
    return 1;
}

SLR_API int slr_gdi_text( int64_t handle, const char* utf8, int x, int y,
                          int height, int rgba )
{
    SlrGdiCanvas* c = slr_gdi_get( handle );
    int wideCount;
    WCHAR* wide;
    HFONT font;
    HFONT oldFont;
    if ( c == 0 || utf8 == 0 || height < 4 || height > 512 )
    {
        set_error( SLR_E_BAD_PARAM );
        return 0;
    }
    wideCount = MultiByteToWideChar( CP_UTF8, 0, utf8, -1, 0, 0 );
    if ( wideCount <= 0 )
    {
        set_error( SLR_E_BAD_PARAM );
        return 0;
    }
    wide = (WCHAR*)malloc( (size_t)wideCount * sizeof( WCHAR ) );
    if ( wide == 0 )
    {
        set_error( SLR_E_MEMORY );
        return 0;
    }
    MultiByteToWideChar( CP_UTF8, 0, utf8, -1, wide, wideCount );
    font = CreateFontW( height, 0, 0, 0, FW_NORMAL, 0, 0, 0,
        DEFAULT_CHARSET, OUT_TT_PRECIS, CLIP_DEFAULT_PRECIS,
        ANTIALIASED_QUALITY, DEFAULT_PITCH | FF_DONTCARE, 0 );
    oldFont = (HFONT)SelectObject( c->hdc, font );
    SetTextColor( c->hdc, slr_gdi_color( rgba ) );
    SetBkMode( c->hdc, TRANSPARENT );
    TextOutW( c->hdc, x, y, wide, wideCount - 1 );
    SelectObject( c->hdc, oldFont );
    DeleteObject( font );
    free( wide );
    slr_gdi_apply_opaque( c );
    return 1;
}

SLR_API int slr_gdi_to_rgba( int64_t handle, int64_t dst_ptr )
{
    SlrGdiCanvas* c = slr_gdi_get( handle );
    unsigned char* dst;
    int total;
    int i = 0;
    if ( c == 0 || dst_ptr == 0 )
    {
        set_error( SLR_E_BAD_PARAM );
        return 0;
    }
    dst = (unsigned char*)(intptr_t)dst_ptr;
    total = c->w * c->h;
    while ( i < total )
    {
        unsigned char* src = c->bits + i * 4;
        dst[i * 4] = src[2];
        dst[i * 4 + 1] = src[1];
        dst[i * 4 + 2] = src[0];
        dst[i * 4 + 3] = src[3];
        i += 1;
    }
    return 1;
}

SLR_API int64_t slr_gdi_create_texture( int64_t handle )
{
    SlrGdiCanvas* c = slr_gdi_get( handle );
    unsigned char* tmp;
    int64_t tex;
    if ( c == 0 )
    {
        return 0;
    }
    tmp = (unsigned char*)malloc( (size_t)c->w * (size_t)c->h * 4 );
    if ( tmp == 0 )
    {
        set_error( SLR_E_MEMORY );
        return 0;
    }
    slr_gdi_to_rgba( handle, (int64_t)(intptr_t)tmp );
    tex = slr_texture_create_rgba( c->w, c->h, (int64_t)(intptr_t)tmp );
    free( tmp );
    return tex;
}

SLR_API int slr_gdi_update_texture( int64_t handle, int64_t tex )
{
    SlrGdiCanvas* c = slr_gdi_get( handle );
    unsigned char* tmp;
    int ok;
    if ( c == 0 || tex == 0 )
    {
        return 0;
    }
    tmp = (unsigned char*)malloc( (size_t)c->w * (size_t)c->h * 4 );
    if ( tmp == 0 )
    {
        set_error( SLR_E_MEMORY );
        return 0;
    }
    slr_gdi_to_rgba( handle, (int64_t)(intptr_t)tmp );
    ok = slr_texture_update_rgba( tex, (int64_t)(intptr_t)tmp );
    free( tmp );
    return ok;
}

/* =============== v5.1：BasicDraw 基础图形 GDI 原生补齐 ===============
 * style_info = (width << 8) | pen_style（见 vm_sl_render.h v5.1 注释）。
 * 全部真 GDI：CreatePen（宽/样式）/ Polyline / Polygon(NULL_BRUSH) /
 * PolyBezier / Arc / SetPixel；非 Windows 平台安全降级。 */

/* 线段（带笔宽与样式：实线/虚线/点线/点划线/双点划线）
 * coords = 4 浮点 [x0,y0,x1,y1]（FFI 参数上限 6，故打包传 ptr） */
SLR_API int slr_gdi_line_ex( int64_t handle, const float* coords,
                             int style_info, int rgba )
{
    SlrGdiCanvas* c = slr_gdi_get( handle );
    HPEN pen;
    HPEN oldPen;
    if ( c == 0 || coords == 0 )
    {
        set_error( SLR_E_BAD_PARAM );
        return 0;
    }
    pen = slr_gdi_make_pen( style_info, rgba );
    oldPen = (HPEN)SelectObject( c->hdc, pen );
    MoveToEx( c->hdc, (int)coords[0], (int)coords[1], 0 );
    LineTo( c->hdc, (int)coords[2], (int)coords[3] );
    SelectObject( c->hdc, oldPen );
    DeleteObject( pen );
    slr_gdi_apply_opaque( c );
    return 1;
}

/* 折线（开放）：GDI Polyline */
SLR_API int slr_gdi_polyline( int64_t handle, const float* points, int count,
                              int style_info, int rgba )
{
    SlrGdiCanvas* c = slr_gdi_get( handle );
    POINT* pts;
    HPEN pen;
    HPEN oldPen;
    if ( c == 0 || points == 0 || count < 2 || count > 4096 )
    {
        set_error( SLR_E_BAD_PARAM );
        return 0;
    }
    pts = slr_gdi_to_points( points, count );
    if ( pts == 0 )
    {
        set_error( SLR_E_MEMORY );
        return 0;
    }
    pen = slr_gdi_make_pen( style_info, rgba );
    oldPen = (HPEN)SelectObject( c->hdc, pen );
    Polyline( c->hdc, pts, count );
    SelectObject( c->hdc, oldPen );
    DeleteObject( pen );
    free( pts );
    slr_gdi_apply_opaque( c );
    return 1;
}

/* 闭合折线（仅描边多边形/三角边/四边形边框）：NULL_BRUSH + Polygon */
SLR_API int slr_gdi_poly_closed( int64_t handle, const float* points, int count,
                                 int style_info, int rgba )
{
    SlrGdiCanvas* c = slr_gdi_get( handle );
    POINT* pts;
    HBRUSH oldBrush;
    HPEN pen;
    HPEN oldPen;
    if ( c == 0 || points == 0 || count < 2 || count > 4096 )
    {
        set_error( SLR_E_BAD_PARAM );
        return 0;
    }
    pts = slr_gdi_to_points( points, count );
    if ( pts == 0 )
    {
        set_error( SLR_E_MEMORY );
        return 0;
    }
    oldBrush = (HBRUSH)SelectObject( c->hdc, GetStockObject( NULL_BRUSH ) );
    pen = slr_gdi_make_pen( style_info, rgba );
    oldPen = (HPEN)SelectObject( c->hdc, pen );
    Polygon( c->hdc, pts, count );
    SelectObject( c->hdc, oldPen );
    DeleteObject( pen );
    SelectObject( c->hdc, oldBrush );
    free( pts );
    slr_gdi_apply_opaque( c );
    return 1;
}

/* 贝塞尔：GDI PolyBezier（count = 3k+1 控制点，首点起点 + 每段 3 控制点） */
SLR_API int slr_gdi_bezier( int64_t handle, const float* points, int count, int rgba )
{
    SlrGdiCanvas* c = slr_gdi_get( handle );
    POINT* pts;
    HPEN pen;
    HPEN oldPen;
    HBRUSH oldBrush;
    if ( c == 0 || points == 0 || count < 4 || count > 4096 || ( ( count - 1 ) % 3 ) != 0 )
    {
        set_error( SLR_E_BAD_PARAM );
        return 0;
    }
    pts = slr_gdi_to_points( points, count );
    if ( pts == 0 )
    {
        set_error( SLR_E_MEMORY );
        return 0;
    }
    oldBrush = (HBRUSH)SelectObject( c->hdc, GetStockObject( NULL_BRUSH ) );
    pen = slr_gdi_make_pen( 1, rgba );
    oldPen = (HPEN)SelectObject( c->hdc, pen );
    PolyBezier( c->hdc, pts, count );
    SelectObject( c->hdc, oldPen );
    DeleteObject( pen );
    SelectObject( c->hdc, oldBrush );
    free( pts );
    slr_gdi_apply_opaque( c );
    return 1;
}

/* 圆弧（曲线）：GDI Arc——coords = 8 浮点 [bbox x0,y0,x1,y1, 射线起点 sx,sy, 射线终点 ex,ey] */
SLR_API int slr_gdi_arc( int64_t handle, const float* coords, int rgba )
{
    SlrGdiCanvas* c = slr_gdi_get( handle );
    HPEN pen;
    HPEN oldPen;
    HBRUSH oldBrush;
    if ( c == 0 || coords == 0 )
    {
        set_error( SLR_E_BAD_PARAM );
        return 0;
    }
    oldBrush = (HBRUSH)SelectObject( c->hdc, GetStockObject( NULL_BRUSH ) );
    pen = slr_gdi_make_pen( 1, rgba );
    oldPen = (HPEN)SelectObject( c->hdc, pen );
    /* 屏幕系角度递增方向（y-down 顺时针），与 BasicDraw RHI 侧语义一致 */
    SetArcDirection( c->hdc, AD_CLOCKWISE );
    Arc( c->hdc, (int)coords[0], (int)coords[1], (int)coords[2], (int)coords[3],
         (int)coords[4], (int)coords[5], (int)coords[6], (int)coords[7] );
    SetArcDirection( c->hdc, AD_COUNTERCLOCKWISE );
    SelectObject( c->hdc, oldPen );
    DeleteObject( pen );
    SelectObject( c->hdc, oldBrush );
    slr_gdi_apply_opaque( c );
    return 1;
}

/* 批量点：逐 SetPixel（单次 apply_opaque 收口） */
SLR_API int slr_gdi_points( int64_t handle, const float* points, int count, int rgba )
{
    SlrGdiCanvas* c = slr_gdi_get( handle );
    int i = 0;
    COLORREF cr;
    if ( c == 0 || points == 0 || count < 1 || count > 65536 )
    {
        set_error( SLR_E_BAD_PARAM );
        return 0;
    }
    cr = slr_gdi_color( rgba );
    while ( i < count )
    {
        int x = (int)points[i * 2];
        int y = (int)points[i * 2 + 1];
        if ( x >= 0 && y >= 0 && x < c->w && y < c->h )
        {
            SetPixel( c->hdc, x, y, cr );
        }
        i += 1;
    }
    slr_gdi_apply_opaque( c );
    return 1;
}

#else /* !_WIN32 —— 非 Windows 安全降级 */

SLR_API int64_t slr_gdi_create( int w, int h ) { (void)w; (void)h; set_error( SLR_E_BAD_PARAM ); return 0; }
SLR_API int slr_gdi_destroy( int64_t h ) { (void)h; return 0; }
SLR_API int slr_gdi_size( int64_t h, int* w, int* v ) { (void)h; (void)w; (void)v; return 0; }
SLR_API int64_t slr_gdi_bits( int64_t h ) { (void)h; return 0; }
SLR_API int slr_gdi_clear( int64_t h, int c ) { (void)h; (void)c; return 0; }
SLR_API int slr_gdi_set_pixel( int64_t h, int x, int y, int c ) { (void)h; (void)x; (void)y; (void)c; return 0; }
SLR_API int slr_gdi_get_pixel( int64_t h, int x, int y ) { (void)h; (void)x; (void)y; return -1; }
SLR_API int slr_gdi_line( int64_t h, int x0, int y0, int x1, int y1, int c ) { (void)h; (void)x0; (void)y0; (void)x1; (void)y1; (void)c; return 0; }
SLR_API int slr_gdi_rect( int64_t h, int x0, int y0, int x1, int y1, int c ) { (void)h; (void)x0; (void)y0; (void)x1; (void)y1; (void)c; return 0; }
SLR_API int slr_gdi_fill_rect( int64_t h, int x0, int y0, int x1, int y1, int c ) { (void)h; (void)x0; (void)y0; (void)x1; (void)y1; (void)c; return 0; }
SLR_API int slr_gdi_ellipse( int64_t h, int x0, int y0, int x1, int y1, int c ) { (void)h; (void)x0; (void)y0; (void)x1; (void)y1; (void)c; return 0; }
SLR_API int slr_gdi_fill_ellipse( int64_t h, int x0, int y0, int x1, int y1, int c ) { (void)h; (void)x0; (void)y0; (void)x1; (void)y1; (void)c; return 0; }
SLR_API int slr_gdi_polygon( int64_t h, const float* p, int n, int s, int f ) { (void)h; (void)p; (void)n; (void)s; (void)f; return 0; }
SLR_API int slr_gdi_blit( int64_t d, int64_t s, int x, int y ) { (void)d; (void)s; (void)x; (void)y; return 0; }
SLR_API int slr_gdi_text( int64_t h, const char* s, int x, int y, int height, int c ) { (void)h; (void)s; (void)x; (void)y; (void)height; (void)c; return 0; }
SLR_API int slr_gdi_to_rgba( int64_t h, int64_t d ) { (void)h; (void)d; return 0; }
SLR_API int64_t slr_gdi_create_texture( int64_t h ) { (void)h; return 0; }
SLR_API int slr_gdi_update_texture( int64_t h, int64_t t ) { (void)h; (void)t; return 0; }
SLR_API int slr_gdi_line_ex( int64_t h, const float* c, int s, int r ) { (void)h; (void)c; (void)s; (void)r; return 0; }
SLR_API int slr_gdi_polyline( int64_t h, const float* p, int n, int s, int r ) { (void)h; (void)p; (void)n; (void)s; (void)r; return 0; }
SLR_API int slr_gdi_poly_closed( int64_t h, const float* p, int n, int s, int r ) { (void)h; (void)p; (void)n; (void)s; (void)r; return 0; }
SLR_API int slr_gdi_bezier( int64_t h, const float* p, int n, int r ) { (void)h; (void)p; (void)n; (void)r; return 0; }
SLR_API int slr_gdi_arc( int64_t h, const float* c, int r ) { (void)h; (void)c; (void)r; return 0; }
SLR_API int slr_gdi_points( int64_t h, const float* p, int n, int r ) { (void)h; (void)p; (void)n; (void)r; return 0; }

#endif
