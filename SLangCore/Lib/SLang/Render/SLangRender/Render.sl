# =========================================================================
# SLangRender —— 离屏 GPU 渲染库（Windows OpenGL 3.3 core，零 SDK 依赖）
#
# 用法（renderTexture 通道：渲染到 FBO 纹理 -> 回读 RGBA8 像素块 -> 上层
# 窗口填充显示，如 QT QLabel.setPixmapRgba）：
#
#   SLang.Render.initialize()                      # 隐藏窗口 + WGL 3.3 上下文
#   SLang.RenderContext ctx = SLang.RenderContext.create( 256, 256 )
#   Int64 pixels = Memory.alloc( 256 * 256 * 4 )   # RGBA8 原生块
#   ctx.renderFrame( 1.0f, 0.0f, 0.0f, pixels )    # 红三角形 + 回读
#   # 采样：Memory.readUInt8( pixels, (y*256+x)*4 + 0 ) 即 R 分量
#   label.setPixmapRgba( pixels, 256, 256 )        # QT 窗口填充（SLangQT）
#   ctx.destroy()
#
# 底层链路（渲染中间层，多驱动同效果）：
#   Render.sl ──@DllStaticImport(CallFFIStatic 77)──> sl_render_lib.dll
#               ──RHI 抽象层──> 后端驱动：
#                 "gl"    -> opengl32.dll（WGL + GL 3.3 core，默认）
#                 "d3d11" -> d3d11.dll + d3dcompiler_47.dll（运行期加载）
#                 （后续："vk" Vulkan、"gles" EGL/GLES 3.0）
# sl_render_lib.dll 把渲染目标收敛为 Int64 句柄；像素出口是回读
# （行序已翻转为 top-down），与 QImage Format_RGBA8888 布局一致。
#
# 错误处理以返回值表达（false / 0），原因经 Render.lastError() /
# Render.errorString() 取得（粘性：每次原生入口调用先清零）。
#
# 注意：所有类型必须是 namespace 下的顶级类型（不能嵌套在类内）。
# =========================================================================

namespace SLang
{
    # ===================================================================
    # Render —— 入口类 + 低层绑定
    #
    # lib* 系列是 sl_render_lib.dll 的直接映射（函数体 = DLL 不可用时的
    # 兜底返回值），通常不必直接使用；initialize() / rendererInfo() 等
    # 门面供业务使用。含 ptr / f32 形参的绑定必须手写 sig（FFI 短名）。
    # ===================================================================
    public class Render
    {
        # ── 错误码常量（与 vm_sl_render.h 逐值一致）────────────────

        public static Int32 OK = 0
        public static Int32 E_OPENGL_MISSING = -1
        public static Int32 E_WINDOW = -2
        public static Int32 E_PIXEL_FORMAT = -3
        public static Int32 E_CONTEXT = -4
        public static Int32 E_NO_ARB = -5
        public static Int32 E_GL_SYMBOL = -6
        public static Int32 E_NOT_INITIALIZED = -7
        public static Int32 E_BAD_HANDLE = -8
        public static Int32 E_BAD_PARAM = -9
        public static Int32 E_FBO = -10
        public static Int32 E_SHADER = -11
        public static Int32 E_MEMORY = -12
        public static Int32 E_CONTEXT_CURRENT = -13
        public static Int32 E_BACKEND = -20

        # ── 低层：错误 / 设备信息 ──────────────────────────────────

        @DllStaticImport( "sl_render_lib", "slr_last_error", "->i32" )
        public static Int32 libLastError()
        {
            ret 0
        }

        @DllStaticImport( "sl_render_lib", "slr_error_string", "i32->utf8" )
        public static string libErrorString( Int32 err )
        {
            ret "sl_render_lib not available"
        }

        # ── 低层：初始化 / 反初始化 ────────────────────────────────

        # slr_init 返回 1=成功 / 0=失败，sig 用 ->bool 直取（Cuda 库同款约定）
        @DllStaticImport( "sl_render_lib", "slr_init", "->bool" )
        public static bool libInit()
        {
            ret false
        }

        # slr_init_backend —— 指定后端初始化（"gl" / "d3d11" / 后续 "vk" / "gles"）
        @DllStaticImport( "sl_render_lib", "slr_init_backend", "utf8->bool" )
        public static bool libInitBackend( string backend )
        {
            ret false
        }

        @DllStaticImport( "sl_render_lib", "slr_uninit", "->bool" )
        public static bool libUninit()
        {
            ret false
        }

        @DllStaticImport( "sl_render_lib", "slr_backend_list", "->utf8" )
        public static string libBackendList()
        {
            ret "gl"
        }

        @DllStaticImport( "sl_render_lib", "slr_current_backend", "->utf8" )
        public static string libCurrentBackend()
        {
            ret "none"
        }

        @DllStaticImport( "sl_render_lib", "slr_renderer_string", "->utf8" )
        public static string libRendererString()
        {
            ret "unknown"
        }

        @DllStaticImport( "sl_render_lib", "slr_version_string", "->utf8" )
        public static string libVersionString()
        {
            ret "unknown"
        }

        # ── 低层：渲染目标 ─────────────────────────────────────────

        @DllStaticImport( "sl_render_lib", "slr_context_create", "i32,i32->i64" )
        public static Int64 libContextCreate( Int32 w, Int32 h )
        {
            ret 0
        }

        @DllStaticImport( "sl_render_lib", "slr_context_destroy", "i64->bool" )
        public static bool libContextDestroy( Int64 ctx )
        {
            ret false
        }

        @DllStaticImport( "sl_render_lib", "slr_context_resize", "i64,i32,i32->bool" )
        public static bool libContextResize( Int64 ctx, Int32 w, Int32 h )
        {
            ret false
        }

        @DllStaticImport( "sl_render_lib", "slr_context_width", "i64->i32" )
        public static Int32 libContextWidth( Int64 ctx )
        {
            ret 0
        }

        @DllStaticImport( "sl_render_lib", "slr_context_height", "i64->i32" )
        public static Int32 libContextHeight( Int64 ctx )
        {
            ret 0
        }

        @DllStaticImport( "sl_render_lib", "slr_frame_count", "i64->i64" )
        public static Int64 libFrameCount( Int64 ctx )
        {
            ret 0
        }

        # ── 低层：渲染 / 回读 ──────────────────────────────────────

        @DllStaticImport( "sl_render_lib", "slr_clear", "i64,f32,f32,f32,f32->bool" )
        public static bool libClear( Int64 ctx, Float32 r, Float32 g, Float32 b, Float32 a )
        {
            ret false
        }

        @DllStaticImport( "sl_render_lib", "slr_draw_triangle", "i64,f32,f32,f32->bool" )
        public static bool libDrawTriangle( Int64 ctx, Float32 r, Float32 g, Float32 b )
        {
            ret false
        }

        @DllStaticImport( "sl_render_lib", "slr_read_pixels", "i64,ptr->bool" )
        public static bool libReadPixels( Int64 ctx, Int64 dstPtr )
        {
            ret false
        }

        @DllStaticImport( "sl_render_lib", "slr_render_frame", "i64,f32,f32,f32,ptr->bool" )
        public static bool libRenderFrame( Int64 ctx, Float32 r, Float32 g, Float32 b, Int64 dstPtr )
        {
            ret false
        }

        # ── 门面：初始化 / 设备信息 ────────────────────────────────

        # initialize() —— 默认后端（"gl"）：隐藏窗口 + WGL 3.3 core 上下文 +
        # 三角形管线，幂等，程序入口调用一次；失败时 false（原因见 lastError()）
        public static bool initialize()
        {
            ret Render.libInit()
        }

        # initializeBackend(backend) —— 指定 RHI 后端初始化（"gl" / "d3d11"；
        # 运行期加载对应驱动，渲染效果与默认后端一致）。已初始化时先反初始化
        # 再切换；已是该后端则幂等成功。
        public static bool initializeBackend( string backend )
        {
            ret Render.libInitBackend( backend )
        }

        # backendList() —— 可用后端列表（逗号分隔，如 "gl,d3d11"）
        public static string backendList()
        {
            ret Render.libBackendList()
        }

        # currentBackend() —— 当前后端名（未初始化为 "none"）
        public static string currentBackend()
        {
            ret Render.libCurrentBackend()
        }

        # 反初始化（销毁全部渲染目标与 GL 资源；进程退出前可省略）
        public static bool uninitialize()
        {
            ret Render.libUninit()
        }

        # GL_RENDERER 字符串（如 "NVIDIA GeForce RTX ..."）
        public static string rendererInfo()
        {
            ret Render.libRendererString()
        }

        # GL_VERSION 字符串（如 "3.3.0 NVIDIA 566.36"）
        public static string versionInfo()
        {
            ret Render.libVersionString()
        }

        # ── 门面：诊断 ────────────────────────────────────────────

        # 最近一次原生调用的错误码（0 = 无错，粘性）
        public static Int32 lastError()
        {
            ret Render.libLastError()
        }

        # 最近一次错误的文本
        public static string errorString()
        {
            ret Render.libErrorString( Render.libLastError() )
        }

        # 指定错误码的文本
        public static string errorStringOf( Int32 err )
        {
            ret Render.libErrorString( err )
        }
    }

    # ===================================================================
    # RenderContext —— FBO 离屏渲染目标
    #
    # 像素块布局（readPixels / renderFrame 的 dst）：
    #   RGBA8，每像素 4 字节（R,G,B,A），行主序，顶行在前
    #   （top-down），块大小 = width * height * 4。
    # 与 QT QLabel.setPixmapRgba / QImage Format_RGBA8888 直接对接。
    # ===================================================================
    public class RenderContext
    {
        Int64 _handle = 0
        Int32 _width = 0
        Int32 _height = 0

        # 构造函数直接持有原生句柄（CudaBuffer 同款工厂/构造分工：
        # create() 做原生调用，_init_ 只装配字段）
        _init_( Int64 handle, Int32 width, Int32 height )
        {
            this._handle = handle
            this._width = width
            this._height = height
        }

        get Int64 handle()
        {
            ret this._handle
        }

        get Int32 width()
        {
            ret this._width
        }

        get Int32 height()
        {
            ret this._height
        }

        get bool isValid()
        {
            ret this._handle != 0
        }

        # ── 创建 / 释放 ────────────────────────────────────────────

        # create(width, height) —— FBO 渲染目标；失败返回 null
        # （原因见 Render.lastError()）
        public static RenderContext create( Int32 width, Int32 height )
        {
            Int64 h = Render.libContextCreate( width, height )
            if h == 0
            {
                ret null
            }
            ret RenderContext( h, width, height )
        }

        # resize(width, height) —— 重建 FBO（内容丢失）
        public bool resize( Int32 width, Int32 height )
        {
            if this._handle == 0 || width <= 0 || height <= 0
            {
                ret false
            }
            if Render.libContextResize( this._handle, width, height ) == false
            {
                ret false
            }
            this._width = width
            this._height = height
            ret true
        }

        public void destroy()
        {
            if this._handle != 0
            {
                Render.libContextDestroy( this._handle )
                this._handle = 0
            }
        }

        # 累计 draw 次数（动画帧计数探针）
        public Int64 frameCount()
        {
            if this._handle == 0
            {
                ret 0
            }
            ret Render.libFrameCount( this._handle )
        }

        # ── 渲染 / 回读 ────────────────────────────────────────────

        # clear(r, g, b, a) —— 纯色清屏（各分量 0..1）
        public bool clear( Float32 r, Float32 g, Float32 b, Float32 a )
        {
            if this._handle == 0
            {
                ret false
            }
            ret Render.libClear( this._handle, r, g, b, a )
        }

        # drawTriangle(r, g, b) —— 绘制居中纯色大三角形（各分量 0..1）
        public bool drawTriangle( Float32 r, Float32 g, Float32 b )
        {
            if this._handle == 0
            {
                ret false
            }
            ret Render.libDrawTriangle( this._handle, r, g, b )
        }

        # readPixels(dstPtr) —— 回读当前帧（RGBA8 top-down，
        # width*height*4 字节；dstPtr 为 Memory.alloc 块地址）
        public bool readPixels( Int64 dstPtr )
        {
            if this._handle == 0 || dstPtr == 0
            {
                ret false
            }
            ret Render.libReadPixels( this._handle, dstPtr )
        }

        # renderFrame(r, g, b, dstPtr) —— 帧循环主入口：深色背景清屏
        # + 三角形绘制 + 回读一步完成。dstPtr 为 Memory.alloc 块地址。
        public bool renderFrame( Float32 r, Float32 g, Float32 b, Int64 dstPtr )
        {
            if this._handle == 0 || dstPtr == 0
            {
                ret false
            }
            ret Render.libRenderFrame( this._handle, r, g, b, dstPtr )
        }

        override string toString()
        {
            ret "RenderContext(" + SystemConvertString( this._width ) + "x" + SystemConvertString( this._height ) + ")"
        }
    }
}
