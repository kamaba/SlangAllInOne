# RenderFFI —— 原生 FFI 静态绑定单点（doc/05 §3.2 规则 11 / D8）
#
# 本模块全部【新增】后端调用集中在此，用 @DllStaticImport 声明（装配期
# 绑定、零 SL 帧开销）；其它 .sl 禁止出现 SystemCallExternalFunction /
# SystemFFICallXxx / FFI attribute。存量调用按 doc/04 §5 批次迁移至此。
#
# 绑定规范（硬约束）：
#   - sig 必须用 FFI 短名（i32/i64/f32/f64/bool/ptr/utf8）；
#   - 返回 void 省略返回段（禁止 "->void"）；含 ptr 的签名必须手写 sig；
#   - 每个绑定必须提供 fallback 体（查询类返回 0/false、创建类返回 0
#     句柄）—— 无后端 DLL 时引擎可继续 Software 降级而不是崩溃；
#   - @DllStaticImport 函数保持一行转发形态，不参与自动 inline；
#   - FFI 参数 <= 6，超限描述符打包（Memory.alloc + writeXxx -> ptr）。
#
# Unity 对应概念：无（引擎原生层接入点；SLang.Render 侧的 slr_* 直连）。

public class RenderFFI
{
    # ── 命令流（D1 真录制）─────────────────────────────────
    # slr_cmd_execute_stream(pipe, streamPtr, commandCount)：
    # CommandBuffer 录制的 SLMC 命令流整包提交（布局 doc/04 §3.6），
    # C 侧逐 opcode 回放到当前 RHI 后端。调用方：
    # SLang.RenderPipeline.executeCommandBuffer（打包 + 提交 + 释放）。
    @DllStaticImport( "sl_render_lib", "slr_cmd_execute_stream", "i64,ptr,i32->bool" )
    public static bool ffiCmdExecuteStream( Int64 pipe, Int64 streamPtr, Int32 commandCount )
    {
        ret false
    }

    # ── 资源占用计数（Environment.Render 资源查明；0 = 未占用/DLL 缺失）──
    # slr_context_count() / slr_pipeline_count() / slr_texture_count()：
    # 全局注册表 used 槽位计数（上限 SLR_MAX_CTX=16 / SLR_MAX_PIPES=32 /
    # SLR_MAX_TEX=64，C 侧 sl_render.c）。调用方：Environment.Render.query。
    @DllStaticImport( "sl_render_lib", "slr_context_count", "->i32" )
    public static Int32 ffiContextCount()
    {
        ret 0
    }

    @DllStaticImport( "sl_render_lib", "slr_pipeline_count", "->i32" )
    public static Int32 ffiPipelineCount()
    {
        ret 0
    }

    @DllStaticImport( "sl_render_lib", "slr_texture_count", "->i32" )
    public static Int32 ffiTextureCount()
    {
        ret 0
    }

    # ── Windows 系统 GDI 兼容层（cvm_render_lib/Platform/sl_gdi.c）──
    # 真 GDI：CreateDIBSection + HDC + GDI pen/brush/TextOutW；
    # 句柄 = C 侧 SlrGdiCanvas*（Int64 承载），颜色 = 0xAARRGGBB。
    @DllStaticImport( "sl_render_lib", "slr_gdi_create", "i32,i32->i64" )
    public static Int64 ffiGdiCreate( Int32 w, Int32 h ) { ret 0 }

    @DllStaticImport( "sl_render_lib", "slr_gdi_destroy", "i64->bool" )
    public static bool ffiGdiDestroy( Int64 canvas ) { ret false }

    @DllStaticImport( "sl_render_lib", "slr_gdi_size", "i64,ptr->bool" )
    public static bool ffiGdiSize( Int64 canvas, Int64 dstPtr ) { ret false }

    @DllStaticImport( "sl_render_lib", "slr_gdi_bits", "i64->i64" )
    public static Int64 ffiGdiBits( Int64 canvas ) { ret 0 }

    @DllStaticImport( "sl_render_lib", "slr_gdi_clear", "i64,i32->bool" )
    public static bool ffiGdiClear( Int64 canvas, Int32 color ) { ret false }

    @DllStaticImport( "sl_render_lib", "slr_gdi_set_pixel", "i64,i32,i32,i32->bool" )
    public static bool ffiGdiSetPixel( Int64 canvas, Int32 x, Int32 y, Int32 color ) { ret false }

    @DllStaticImport( "sl_render_lib", "slr_gdi_get_pixel", "i64,i32,i32->i32" )
    public static Int32 ffiGdiGetPixel( Int64 canvas, Int32 x, Int32 y ) { ret -1 }

    @DllStaticImport( "sl_render_lib", "slr_gdi_line", "i64,i32,i32,i32,i32,i32->bool" )
    public static bool ffiGdiLine( Int64 canvas, Int32 x0, Int32 y0, Int32 x1, Int32 y1, Int32 color ) { ret false }

    @DllStaticImport( "sl_render_lib", "slr_gdi_rect", "i64,i32,i32,i32,i32,i32->bool" )
    public static bool ffiGdiRect( Int64 canvas, Int32 x0, Int32 y0, Int32 x1, Int32 y1, Int32 color ) { ret false }

    @DllStaticImport( "sl_render_lib", "slr_gdi_fill_rect", "i64,i32,i32,i32,i32,i32->bool" )
    public static bool ffiGdiFillRect( Int64 canvas, Int32 x0, Int32 y0, Int32 x1, Int32 y1, Int32 color ) { ret false }

    @DllStaticImport( "sl_render_lib", "slr_gdi_ellipse", "i64,i32,i32,i32,i32,i32->bool" )
    public static bool ffiGdiEllipse( Int64 canvas, Int32 x0, Int32 y0, Int32 x1, Int32 y1, Int32 color ) { ret false }

    @DllStaticImport( "sl_render_lib", "slr_gdi_fill_ellipse", "i64,i32,i32,i32,i32,i32->bool" )
    public static bool ffiGdiFillEllipse( Int64 canvas, Int32 x0, Int32 y0, Int32 x1, Int32 y1, Int32 color ) { ret false }

    @DllStaticImport( "sl_render_lib", "slr_gdi_polygon", "i64,ptr,i32,i32,i32->bool" )
    public static bool ffiGdiPolygon( Int64 canvas, Int64 pointsPtr, Int32 count, Int32 stroke, Int32 fill ) { ret false }

    @DllStaticImport( "sl_render_lib", "slr_gdi_blit", "i64,i64,i32,i32->bool" )
    public static bool ffiGdiBlit( Int64 dst, Int64 src, Int32 x, Int32 y ) { ret false }

    @DllStaticImport( "sl_render_lib", "slr_gdi_text", "i64,utf8,i32,i32,i32,i32->bool" )
    public static bool ffiGdiText( Int64 canvas, string text, Int32 x, Int32 y, Int32 height, Int32 color ) { ret false }

    @DllStaticImport( "sl_render_lib", "slr_gdi_to_rgba", "i64,ptr->bool" )
    public static bool ffiGdiToRgba( Int64 canvas, Int64 dstPtr ) { ret false }

    @DllStaticImport( "sl_render_lib", "slr_gdi_create_texture", "i64->i64" )
    public static Int64 ffiGdiCreateTexture( Int64 canvas ) { ret 0 }

    @DllStaticImport( "sl_render_lib", "slr_gdi_update_texture", "i64,i64->bool" )
    public static bool ffiGdiUpdateTexture( Int64 canvas, Int64 tex ) { ret false }

    # ── v5.1：BasicDraw 基础图形 GDI 原生补齐 ──
    # style_info = (width << 8) | pen_style（宽 1..32，样式 0=solid
    # 1=dash 2=dot 3=dashdot 4=dashdotdot）；非实线笔宽钳 1。
    # lineEx 因 6 参上限走 ptr：coords = 4 浮点 [x0,y0,x1,y1]。
    @DllStaticImport( "sl_render_lib", "slr_gdi_line_ex", "i64,ptr,i32,i32->bool" )
    public static bool ffiGdiLineEx( Int64 canvas, Int64 coordsPtr, Int32 styleInfo, Int32 rgba ) { ret false }

    @DllStaticImport( "sl_render_lib", "slr_gdi_polyline", "i64,ptr,i32,i32,i32->bool" )
    public static bool ffiGdiPolyline( Int64 canvas, Int64 pointsPtr, Int32 count, Int32 styleInfo, Int32 rgba ) { ret false }

    @DllStaticImport( "sl_render_lib", "slr_gdi_poly_closed", "i64,ptr,i32,i32,i32->bool" )
    public static bool ffiGdiPolyClosed( Int64 canvas, Int64 pointsPtr, Int32 count, Int32 styleInfo, Int32 rgba ) { ret false }

    @DllStaticImport( "sl_render_lib", "slr_gdi_bezier", "i64,ptr,i32,i32->bool" )
    public static bool ffiGdiBezier( Int64 canvas, Int64 pointsPtr, Int32 count, Int32 rgba ) { ret false }

    @DllStaticImport( "sl_render_lib", "slr_gdi_arc", "i64,ptr,i32->bool" )
    public static bool ffiGdiArc( Int64 canvas, Int64 coordsPtr, Int32 rgba ) { ret false }

    @DllStaticImport( "sl_render_lib", "slr_gdi_points", "i64,ptr,i32,i32->bool" )
    public static bool ffiGdiPoints( Int64 canvas, Int64 pointsPtr, Int32 count, Int32 rgba ) { ret false }
}
