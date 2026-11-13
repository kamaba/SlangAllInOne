
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

    # ===================================================================
    # RTHandlePool —— P4 RT 句柄池（HDRP RTHandleSystem 思想的桥接落体）
    # -------------------------------------------------------------------
    # 固定容量 RT 表（对齐 C 侧 SLR_MAX_TEX=64），按 (w,h) 键复用：
    #   request(w, h, pixelsPtr) —— 命中同尺寸已池化句柄 -> 直接返回
    #       （reuseCount++，C 侧纹理计数不变）；未命中 -> createRgba
    #       新建并池化。语义：池化即「同尺寸共享同一 RT」，内容以首次
    #       上传为准（当前 C 侧无重上传 API，复用即内容不变）。
    #   releaseAll() —— 销毁全部池化纹理并清表（容量保留）。
    # RenderTexture 保持薄壳（句柄门面）；池只做「谁活着」的记账。
    # ===================================================================
    public class RTHandlePool
    {
        public static Int32 CAP_RTS = 64

        Array<RenderTexture> _rts = null
        Array<Int32> _w = null
        Array<Int32> _h = null
        Int32 _count = 0
        Int32 _reuseCount = 0
        Int32 _requestCount = 0

        public void _init_()
        {
            this._rts = Array<RenderTexture>( RTHandlePool.CAP_RTS )
            this._w = Array<Int32>( RTHandlePool.CAP_RTS )
            this._h = Array<Int32>( RTHandlePool.CAP_RTS )
            Int32 i = 0
            while i < RTHandlePool.CAP_RTS
            {
                this._rts[ i ] = null
                this._w[ i ] = 0
                this._h[ i ] = 0
                i = i + 1
            }
            this._count = 0
            this._reuseCount = 0
            this._requestCount = 0
        }

        # request(w, h, pixelsPtr) —— 请求一个 RT 句柄（同尺寸复用优先）
        # 返回 null：参数非法 / 池满且无同尺寸可复用 / 创建失败
        public RenderTexture request( Int32 w, Int32 h, Int64 pixelsPtr )
        {
            this._requestCount = this._requestCount + 1
            if w <= 0 || h <= 0 || pixelsPtr == 0
            {
                ret null
            }
            Int32 i = 0
            while i < this._count
            {
                RenderTexture t = this._rts[ i ]
                if t != null
                {
                    if t.isValid
                    {
                        if this._w[ i ] == w && this._h[ i ] == h
                        {
                            this._reuseCount = this._reuseCount + 1
                            ret t
                        }
                    }
                }
                i = i + 1
            }
            if this._count >= RTHandlePool.CAP_RTS
            {
                ret null
            }
            RenderTexture nt = RenderTexture.createRgba( pixelsPtr, w, h )
            if nt == null
            {
                ret null
            }
            Int32 idx = this._count
            this._rts[ idx ] = nt
            this._w[ idx ] = w
            this._h[ idx ] = h
            this._count = idx + 1
            ret nt
        }

        # releaseAll() —— 销毁全部池化纹理并清表（容量与统计保留）
        public void releaseAll()
        {
            Int32 i = 0
            while i < this._count
            {
                RenderTexture t = this._rts[ i ]
                if t != null
                {
                    if t.isValid
                    {
                        t.destroy()
                    }
                    this._rts[ i ] = null
                }
                i = i + 1
            }
            this._count = 0
        }

        # count() —— 当前池化纹理数
        public Int32 count()
        {
            ret this._count
        }

        # reuseCount() —— 命中复用次数（累计）
        public Int32 reuseCount()
        {
            ret this._reuseCount
        }

        # requestCount() —— 请求总次数（累计）
        public Int32 requestCount()
        {
            ret this._requestCount
        }

        override string toString()
        {
            ret "RTHandlePool(" + this._count.toString() + "/" + RTHandlePool.CAP_RTS.toString() + ", reuse=" + this._reuseCount.toString() + ")"
        }
    }

}