
    # ===================================================================
    # RenderCamera —— 管线相机门面（多相机渲染）
    # ----------------------------------------------------------------------------
    # 槽 0 为默认相机（RenderPipeline.setCamera 写入，不经过本类）。
    # 新建相机经 RenderPipeline.addCamera(depth)：depth 升序决定
    # 绘制次序（小 depth 先画）。每相机独立：
    #   cullingMask  —— 按位对应 layer 0..31（-1 = 全部）
    #   extents      —— 正交视域（NDC 前的世界系包围盒）
    #   viewport     —— 输出目标内像素视口
    #   clearColor   —— 本相机清屏色
    #   clearFlags   —— 位 1 = 清颜色、位 2 = 清深度（叠加相机可清 0）
    # ===================================================================
    import Math
    
    namespace SLang
    {
    public class RenderCamera
    {
        Int64 _pipe = 0
        Int64 _id = 0

        _init_( Int64 pipe, Int64 id )
        {
            this._pipe = pipe
            this._id = id
        }

        get Int64 handle()
        {
            ret this._id
        }

        get bool isValid()
        {
            ret this._id != 0 && this._pipe != 0
        }

        public bool setEnabled( bool enabled )
        {
            if this.isValid == false
            {
                ret false
            }
            ret RenderCamera.ffiCameraSetEnabled( this._pipe, this._id, enabled ? 1 : 0 )
        }

        public bool setDepth( Int32 depth )
        {
            if this.isValid == false
            {
                ret false
            }
            ret RenderCamera.ffiCameraSetDepth( this._pipe, this._id, depth )
        }

        public bool setCullMask( Int32 mask )
        {
            if this.isValid == false
            {
                ret false
            }
            ret RenderCamera.ffiCameraSetCullMask( this._pipe, this._id, mask )
        }

        # setExtents(l, r, b, t) —— 正交视域
        public bool setExtents( Float32 l, Float32 r, Float32 b, Float32 t )
        {
            if this.isValid == false
            {
                ret false
            }
            ret RenderCamera.ffiCameraSetExtents( this._pipe, this._id, l, r, b, t )
        }

        # setViewport(x, y, w, h) —— 输出目标内像素视口
        public bool setViewport( Int32 x, Int32 y, Int32 w, Int32 h )
        {
            if this.isValid == false
            {
                ret false
            }
            ret RenderCamera.ffiCameraSetViewport( this._pipe, this._id, x, y, w, h )
        }

        public bool setClearColor( Float32 r, Float32 g, Float32 b, Float32 a )
        {
            if this.isValid == false
            {
                ret false
            }
            ret RenderCamera.ffiCameraSetClearColor( this._pipe, this._id, r, g, b, a )
        }

        # setClearFlags(flags) —— 位 1 = 清颜色，位 2 = 清深度
        public bool setClearFlags( Int32 flags )
        {
            if this.isValid == false
            {
                ret false
            }
            ret RenderCamera.ffiCameraSetClearFlags( this._pipe, this._id, flags )
        }

        public bool destroy()
        {
            if this.isValid == false
            {
                ret false
            }
            bool ok = RenderCamera.ffiCameraDestroy( this._pipe, this._id )
            if ok
            {
                this._id = 0
            }
            ret ok
        }

        # ── FFI 绑定 ──────────────────────────────────────────────

        @DllStaticImport( "sl_render_lib", "slr_camera_set_enabled", "i64,i64,i32->bool" )
        static bool ffiCameraSetEnabled( Int64 p, Int64 cam, Int32 enabled )
        {
            ret false
        }

        @DllStaticImport( "sl_render_lib", "slr_camera_set_depth", "i64,i64,i32->bool" )
        static bool ffiCameraSetDepth( Int64 p, Int64 cam, Int32 depth )
        {
            ret false
        }

        @DllStaticImport( "sl_render_lib", "slr_camera_set_cull_mask", "i64,i64,i32->bool" )
        static bool ffiCameraSetCullMask( Int64 p, Int64 cam, Int32 mask )
        {
            ret false
        }

        @DllStaticImport( "sl_render_lib", "slr_camera_set_extents", "i64,i64,f32,f32,f32,f32->bool" )
        static bool ffiCameraSetExtents( Int64 p, Int64 cam, Float32 l, Float32 r, Float32 b, Float32 t )
        {
            ret false
        }

        @DllStaticImport( "sl_render_lib", "slr_camera_set_viewport", "i64,i64,i32,i32,i32,i32->bool" )
        static bool ffiCameraSetViewport( Int64 p, Int64 cam, Int32 x, Int32 y, Int32 w, Int32 h )
        {
            ret false
        }

        @DllStaticImport( "sl_render_lib", "slr_camera_set_clear_color", "i64,i64,f32,f32,f32,f32->bool" )
        static bool ffiCameraSetClearColor( Int64 p, Int64 cam, Float32 r, Float32 g, Float32 b, Float32 a )
        {
            ret false
        }

        @DllStaticImport( "sl_render_lib", "slr_camera_set_clear_flags", "i64,i64,i32->bool" )
        static bool ffiCameraSetClearFlags( Int64 p, Int64 cam, Int32 flags )
        {
            ret false
        }

        @DllStaticImport( "sl_render_lib", "slr_camera_destroy", "i64,i64->bool" )
        static bool ffiCameraDestroy( Int64 p, Int64 cam )
        {
            ret false
        }
    }
    }