
    # ===================================================================
    # RenderTexture —— 贴图门面（top-down RGBA8 上传）
    # ===================================================================
 namespace SLang
 {
    public class RenderTexture
    {
        Int64 _handle = 0
        Int32 _width = 0
        Int32 _height = 0

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

        # createRgba(ptr, w, h) —— ptr 为 Memory.alloc 的 RGBA8 像素块
        #（行主序、顶行在前；C 层内部翻行为 GL bottom-up）
        public static RenderTexture createRgba( Int64 ptr, Int32 width, Int32 height )
        {
            if ptr == 0 || width <= 0 || height <= 0
            {
                ret null
            }
            Int64 h = RenderTexture.ffiTextureCreateRgba( width, height, ptr )
            if h == 0
            {
                ret null
            }
            ret RenderTexture( h, width, height )
        }

        # loadFile(path) —— 从图片文件创建纹理（C 层 WIC 解码，
        # 支持 PNG/JPEG/BMP/TIFF 等；path 为 UTF-8）
        public static RenderTexture loadFile( string path )
        {
            if path == null || path.length() == 0
            {
                ret null
            }
            Int64 h = RenderTexture.ffiTextureLoadFile( path )
            if h == 0
            {
                ret null
            }
            # 尺寸由 C 层注册表管理；门面仅记录句柄，宽高留 0
            ret RenderTexture( h, 0, 0 )
        }

        public bool destroy()
        {
            if this._handle == 0
            {
                ret false
            }
            bool ok = RenderTexture.ffiTextureDestroy( this._handle )
            if ok
            {
                this._handle = 0
            }
            ret ok
        }

        override string toString()
        {
            ret "RenderTexture(" + this._width.toString() + "x" + this._height.toString() + ")"
        }

        # ── FFI 绑定 ──────────────────────────────────────────────

        @DllStaticImport( "sl_render_lib", "slr_texture_create_rgba", "i32,i32,ptr->i64" )
        static Int64 ffiTextureCreateRgba( Int32 w, Int32 h, Int64 dataPtr )
        {
            ret 0
        }

        @DllStaticImport( "sl_render_lib", "slr_texture_load_file", "utf8->i64" )
        static Int64 ffiTextureLoadFile( string path )
        {
            ret 0
        }

        @DllStaticImport( "sl_render_lib", "slr_texture_destroy", "i64->bool" )
        static bool ffiTextureDestroy( Int64 tex )
        {
            ret false
        }
    }

}    