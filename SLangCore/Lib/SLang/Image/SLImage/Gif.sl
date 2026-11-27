# =========================================================================
# Image/Gif.sl —— GIF 动画拆解 / 合成
#
# 拆解（GIF -> 普通图）：C 层 stb 解码动画（处置语义已合成到整画布），
#   每帧独立 RGBA8 ImageBuffer + 延迟毫秒，装进 GifDocument。
# 合成（普通图 -> GIF）：向 GifEncoder 逐帧喂 ImageBuffer，build()/save()
#   一次性产出 GIF89a（C 层自有编码器：全局调色板量化 + LZW + NETSCAPE）。
#
# 类型：
#   GifFrame    一帧（整画布 RGBA8 ImageBuffer + delayMs）
#   GifDocument 逻辑画布尺寸 + loopCount（NETSCAPE 原值）+ 帧列表
#   GifEncoder  命令式编码器（new -> addFrame* -> build/save，一次性）
#   Gif         门面：decode/decodeFile/decodeFrames/encode/save + 自持
#               13 个 sli_gif_* FFI 绑定（契约见 ../cvm_image_lib/vm_sl_image.h）
#
# 循环语义：loopCount = -1 不写 NETSCAPE 循环扩展（播一遍即停）；
#           0 = 无限循环；n > 0 = 播放 n+1 次（NETSCAPE u16 原值）。
# 延迟语义：毫秒，编码端四舍五入到厘秒（GCE u16）。
# 内存路径约束：单帧 w*h*4 与字节流均 <= ImageFfi.MAX_INLINE_BYTES（4 MiB）。
# =========================================================================

namespace Image
{
    # ── 一帧 ───────────────────────────────────────────────
    public class GifFrame
    {
        # 整画布帧（尺寸须等于所属文档的 width × height）
        public ImageBuffer image = null
        # 帧延迟（毫秒，>= 0；编码端换算厘秒写入 GCE）
        public Int32 delayMs = 0

        _init_()
        {
            this.image = null
            this.delayMs = 0
        }

        _init_( ImageBuffer _image )
        {
            this.image = _image
            this.delayMs = 0
        }

        _init_( ImageBuffer _image, Int32 _delayMs )
        {
            this.image = _image
            this.delayMs = _delayMs
        }

        public get bool isValid()
        {
            if this.image == null
            {
                ret false
            }
            ret this.image.isValid
        }
    }

    # ── 动画文档（拆解产物 / 合成入参）────────────────────
    public class GifDocument
    {
        public Int32 width = 0
        public Int32 height = 0
        # NETSCAPE 循环数原值（-1 = 无循环扩展）
        public Int32 loopCount = -1
        # 帧列表（List 动态容器，addFrame 递增填入；解码路径一次填满）
        public List<GifFrame> frames = null

        _init_()
        {
            this.width = 0
            this.height = 0
            this.loopCount = -1
            this.frames = List<GifFrame>()
        }

        _init_( Int32 _width, Int32 _height )
        {
            this.width = _width
            this.height = _height
            this.loopCount = -1
            this.frames = List<GifFrame>()
        }

        public get bool isValid()
        {
            if this.width <= 0 || this.height <= 0
            {
                ret false
            }
            if this.frames == null
            {
                ret false
            }
            ret this.frames.length > 0
        }

        public get Int32 frameCount()
        {
            if this.frames == null
            {
                ret 0
            }
            ret this.frames.length
        }

        # 越界 / 空槽返回 null
        public GifFrame frameAt( Int32 index )
        {
            if this.frames == null
            {
                ret null
            }
            if index < 0 || index >= this.frames.length
            {
                ret null
            }
            ret this.frames[ index ]
        }

        # 追加一帧（延迟 0）
        public bool addFrame( ImageBuffer image )
        {
            ret this.addFrameWithDelay( image, 0 )
        }

        # 追加一帧（指定延迟毫秒）；image 尺寸须等于画布尺寸
        public bool addFrameWithDelay( ImageBuffer image, Int32 delayMs )
        {
            if this.frames == null
            {
                ret false
            }
            if image == null || !image.isValid
            {
                ret false
            }
            if this.width <= 0 || this.height <= 0
            {
                ret false
            }
            if image.width != this.width || image.height != this.height
            {
                ret false
            }
            if delayMs < 0
            {
                delayMs = 0
            }
            this.frames.add( GifFrame( image, delayMs ) )
            ret true
        }
    }

    # ── 门面 + 自持 FFI 绑定 ───────────────────────────────
    public class Gif
    {
        # ═══════════════════════════════════════════════════
        # 1) lib* 直接映射层（13 个 sli_gif_*）
        # ═══════════════════════════════════════════════════

        # ── 拆解（句柄 1 起始；0 = 失败）──
        @DllStaticImport( "sl_image_lib", "sli_gif_decode_file", "utf8->i64" )
        public static Int64 libGifDecodeFile( string path )
        {
            ret 0
        }

        @DllStaticImport( "sl_image_lib", "sli_gif_decode_mem", "ptr,i64->i64" )
        public static Int64 libGifDecodeMem( Int64 dataPtr, Int64 size )
        {
            ret 0
        }

        @DllStaticImport( "sl_image_lib", "sli_gif_width", "i64->i32" )
        public static Int32 libGifWidth( Int64 gif )
        {
            ret 0
        }

        @DllStaticImport( "sl_image_lib", "sli_gif_height", "i64->i32" )
        public static Int32 libGifHeight( Int64 gif )
        {
            ret 0
        }

        @DllStaticImport( "sl_image_lib", "sli_gif_frame_count", "i64->i32" )
        public static Int32 libGifFrameCount( Int64 gif )
        {
            ret 0
        }

        # NETSCAPE 原值；-1 = 无扩展
        @DllStaticImport( "sl_image_lib", "sli_gif_loop_count", "i64->i32" )
        public static Int32 libGifLoopCount( Int64 gif )
        {
            ret -1
        }

        # 每帧延迟毫秒；越界 / 句柄无效返回 -1
        @DllStaticImport( "sl_image_lib", "sli_gif_frame_delay", "i64,i32->i32" )
        public static Int32 libGifFrameDelay( Int64 gif, Int32 frame )
        {
            ret -1
        }

        # 单帧像素整块拷出（dstPtr 缓冲 = w*h*4）
        @DllStaticImport( "sl_image_lib", "sli_gif_frame_pixels", "i64,i32,ptr,i64->bool" )
        public static bool libGifFramePixels( Int64 gif, Int32 frame, Int64 dstPtr, Int64 capBytes )
        {
            ret false
        }

        @DllStaticImport( "sl_image_lib", "sli_gif_free", "i64->bool" )
        public static bool libGifFree( Int64 gif )
        {
            ret false
        }

        # ── 合成 ──
        @DllStaticImport( "sl_image_lib", "sli_gif_encode_new", "i32,i32,i32->i64" )
        public static Int64 libGifEncodeNew( Int32 width, Int32 height, Int32 loopCount )
        {
            ret 0
        }

        @DllStaticImport( "sl_image_lib", "sli_gif_encode_add_frame", "i64,ptr,i32->bool" )
        public static bool libGifEncodeAddFrame( Int64 enc, Int64 pixelsPtr, Int32 delayMs )
        {
            ret false
        }

        # 一次性终点：合成 GIF 字节流 -> blob 句柄（此后编码器句柄失效）
        @DllStaticImport( "sl_image_lib", "sli_gif_encode_finish", "i64->i64" )
        public static Int64 libGifEncodeFinish( Int64 enc )
        {
            ret 0
        }

        @DllStaticImport( "sl_image_lib", "sli_gif_encode_free", "i64->bool" )
        public static bool libGifEncodeFree( Int64 enc )
        {
            ret false
        }

        # ═══════════════════════════════════════════════════
        # 2) 拆解（GIF -> GifDocument / 帧列表）
        # ═══════════════════════════════════════════════════

        # GIF 句柄 -> GifDocument；总是释放句柄（_takeImage 同款语义）
        static GifDocument _takeGif( Int64 gif )
        {
            if gif == 0
            {
                ret null
            }
            GifDocument doc = null
            Int32 w = Image.Gif.libGifWidth( gif )
            Int32 h = Image.Gif.libGifHeight( gif )
            Int32 n = Image.Gif.libGifFrameCount( gif )
            if w > 0 && h > 0 && n > 0
            {
                Int32 need = w * h * 4
                if need > 0 && need <= ImageFfi.MAX_INLINE_BYTES
                {
                    Int64 dst = Memory.alloc( need )
                    if dst != 0
                    {
                        doc = GifDocument( w, h )
                        doc.loopCount = Image.Gif.libGifLoopCount( gif )
                        Int32 i = 0
                        bool all = true
                        while i < n && all
                        {
                            if Image.Gif.libGifFramePixels( gif, i, dst, need )
                            {
                                ImageBuffer buf = ImageBuffer( w, h )
                                Array<UInt8> px = buf.pixelBytes()
                                Int32 j = 0
                                while j < need
                                {
                                    px[ j ] = SystemConvertUInt8( Memory.readUInt8( dst, j ) )
                                    j = j + 1
                                }
                                Int32 delay = Image.Gif.libGifFrameDelay( gif, i )
                                if delay < 0
                                {
                                    delay = 0
                                }
                                doc.frames.add( GifFrame( buf, delay ) )
                            }
                            else
                            {
                                all = false
                            }
                            i = i + 1
                        }
                        if !all
                        {
                            doc = null
                        }
                        Memory.free( dst )
                    }
                }
            }
            Image.Gif.libGifFree( gif )
            ret doc
        }

        # 文件路径拆解（推荐入口，直通 C 层零搬运）；失败返回 null
        public static GifDocument decodeFile( string path )
        {
            if !ImageFfi.ensureReady()
            {
                ret null
            }
            if path == null || path == ""
            {
                ret null
            }
            ret Image.Gif._takeGif( Image.Gif.libGifDecodeFile( path ) )
        }

        # 内存字节流拆解（<= MAX_INLINE_BYTES 单帧）；失败返回 null
        public static GifDocument decode( Array<UInt8> bytes )
        {
            if !ImageFfi.ensureReady()
            {
                ret null
            }
            if bytes == null || bytes.length < 8
            {
                ret null
            }
            Int64 src = ImageFfi._copyIn( bytes, bytes.length )
            if src == 0
            {
                ret null
            }
            Int64 gif = Image.Gif.libGifDecodeMem( src, bytes.length )
            Memory.free( src )
            ret Image.Gif._takeGif( gif )
        }

        # 便捷拆解：只要帧图列表（丢弃延迟 / 循环元数据）
        public static List<ImageBuffer> decodeFrames( Array<UInt8> bytes )
        {
            GifDocument doc = Image.Gif.decode( bytes )
            if doc == null || doc.frames == null
            {
                ret null
            }
            List<ImageBuffer> result = List<ImageBuffer>()
            Int32 i = 0
            while i < doc.frames.length
            {
                GifFrame f = doc.frames[ i ]
                if f != null && f.image != null
                {
                    result.add( f.image )
                }
                i = i + 1
            }
            ret result
        }

        # ═══════════════════════════════════════════════════
        # 3) 合成（GifDocument -> GIF）
        # ═══════════════════════════════════════════════════

        # 文档 -> 编码器句柄（0 = 无效文档 / 槽耗尽）
        static Int64 _newEncoderOf( GifDocument doc )
        {
            if doc == null
            {
                ret 0
            }
            if doc.width <= 0 || doc.height <= 0
            {
                ret 0
            }
            if doc.frames == null || doc.frames.length == 0
            {
                ret 0
            }
            Int32 loop = doc.loopCount
            if loop < -1
            {
                loop = -1
            }
            ret Image.Gif.libGifEncodeNew( doc.width, doc.height, loop )
        }

        # 逐帧喂入编码器（帧尺寸必须等于画布；统一转紧密 RGBA8）
        static bool _feedEncoder( Int64 enc, GifDocument doc )
        {
            Int32 w = doc.width
            Int32 h = doc.height
            Int32 need = w * h * 4
            bool ok = true
            Int32 i = 0
            while i < doc.frames.length && ok
            {
                GifFrame f = doc.frames[ i ]
                if f == null || f.image == null
                {
                    ok = false
                }
                elif f.image.width != w || f.image.height != h
                {
                    ok = false
                }
                else
                {
                    Array<UInt8> rgba = ImageFfi.rgbaBytesOf( f.image )
                    if rgba == null || rgba.length < need
                    {
                        ok = false
                    }
                    else
                    {
                        Int64 src = ImageFfi._copyIn( rgba, need )
                        if src == 0
                        {
                            ok = false
                        }
                        else
                        {
                            if !Image.Gif.libGifEncodeAddFrame( enc, src, f.delayMs )
                            {
                                ok = false
                            }
                            Memory.free( src )
                        }
                    }
                }
                i = i + 1
            }
            ret ok
        }

        # 合成 GIF 字节流（<= MAX_INLINE_BYTES）；失败返回 null
        public static Array<UInt8> encode( GifDocument doc )
        {
            if !ImageFfi.ensureReady()
            {
                ret null
            }
            Int64 enc = Image.Gif._newEncoderOf( doc )
            if enc == 0
            {
                ret null
            }
            if !Image.Gif._feedEncoder( enc, doc )
            {
                Image.Gif.libGifEncodeFree( enc )
                ret null
            }
            Int64 blob = Image.Gif.libGifEncodeFinish( enc )
            if blob == 0
            {
                ret null
            }
            Array<UInt8> result = null
            Int64 size = ImageFfi.libBlobSize( blob )
            if size > 0 && size <= ImageFfi.MAX_INLINE_BYTES
            {
                Int64 dst = Memory.alloc( SystemConvertInt32( size ) )
                if dst != 0
                {
                    if ImageFfi.libBlobCopy( blob, dst, size )
                    {
                        result = ImageFfi._copyOut( dst, SystemConvertInt32( size ) )
                    }
                    Memory.free( dst )
                }
            }
            ImageFfi.libBlobFree( blob )
            ret result
        }

        # 合成并落盘（blob 直写文件，不受搬运上限约束）；失败返回 false
        public static bool save( GifDocument doc, string path )
        {
            if !ImageFfi.ensureReady()
            {
                ret false
            }
            if path == null || path == ""
            {
                ret false
            }
            Int64 enc = Image.Gif._newEncoderOf( doc )
            if enc == 0
            {
                ret false
            }
            if !Image.Gif._feedEncoder( enc, doc )
            {
                Image.Gif.libGifEncodeFree( enc )
                ret false
            }
            Int64 blob = Image.Gif.libGifEncodeFinish( enc )
            if blob == 0
            {
                ret false
            }
            bool ok = ImageFfi.libBlobSave( blob, path )
            ImageFfi.libBlobFree( blob )
            ret ok
        }
    }

    # ── 命令式编码器（普通图逐帧加入 -> GIF）──────────────
    # 生命周期：new -> addFrame / addFrameWithDelay -> build() / save()
    # build / save 调 finish 一次性合成，之后句柄失效（isValid = false）；
    # close() 显式放弃（幂等，可省略）。
    public class GifEncoder
    {
        Int64 _enc = 0
        Int32 _width = 0
        Int32 _height = 0
        Int32 _added = 0

        # loopCount = -1（不写循环扩展）
        _init_( Int32 width, Int32 height )
        {
            Image.GifEncoder._reset( this )
            if !ImageFfi.ensureReady()
            {
                ret
            }
            if width <= 0 || height <= 0
            {
                ret
            }
            this._width = width
            this._height = height
            this._enc = Image.Gif.libGifEncodeNew( width, height, -1 )
        }

        # loopCount：-1 无循环 / 0 无限 / n 播放 n+1 次
        _init_( Int32 width, Int32 height, Int32 loopCount )
        {
            Image.GifEncoder._reset( this )
            if !ImageFfi.ensureReady()
            {
                ret
            }
            if width <= 0 || height <= 0
            {
                ret
            }
            Int32 loop = loopCount
            if loop < -1
            {
                loop = -1
            }
            this._width = width
            this._height = height
            this._enc = Image.Gif.libGifEncodeNew( width, height, loop )
        }

        static void _reset( GifEncoder self )
        {
            self._enc = 0
            self._width = 0
            self._height = 0
            self._added = 0
        }

        public get bool isValid()
        {
            ret this._enc != 0
        }

        public get Int32 width()
        {
            ret this._width
        }

        public get Int32 height()
        {
            ret this._height
        }

        # 已加入帧数（build 之后归零）
        public get Int32 frameCount()
        {
            ret this._added
        }

        # 追加一帧（延迟 0）；帧尺寸须等于构造尺寸
        public bool addFrame( ImageBuffer frame )
        {
            ret this.addFrameWithDelay( frame, 0 )
        }

        # 追加一帧（延迟毫秒；编码端 clamp 到 GCE u16 厘秒域）
        public bool addFrameWithDelay( ImageBuffer frame, Int32 delayMs )
        {
            if this._enc == 0
            {
                ret false
            }
            if frame == null || !frame.isValid
            {
                ret false
            }
            if frame.width != this._width || frame.height != this._height
            {
                ret false
            }
            Int32 need = this._width * this._height * 4
            Array<UInt8> rgba = ImageFfi.rgbaBytesOf( frame )
            if rgba == null || rgba.length < need
            {
                ret false
            }
            Int64 src = ImageFfi._copyIn( rgba, need )
            if src == 0
            {
                ret false
            }
            bool ok = Image.Gif.libGifEncodeAddFrame( this._enc, src, delayMs )
            Memory.free( src )
            if ok
            {
                this._added = this._added + 1
            }
            ret ok
        }

        # 一次性合成字节流（此后编码器失效）；失败返回 null
        public Array<UInt8> build()
        {
            if !ImageFfi.ensureReady()
            {
                ret null
            }
            Int64 blob = Image.GifEncoder._finishBlob( this )
            if blob == 0
            {
                ret null
            }
            Array<UInt8> result = null
            Int64 size = ImageFfi.libBlobSize( blob )
            if size > 0 && size <= ImageFfi.MAX_INLINE_BYTES
            {
                Int64 dst = Memory.alloc( SystemConvertInt32( size ) )
                if dst != 0
                {
                    if ImageFfi.libBlobCopy( blob, dst, size )
                    {
                        result = ImageFfi._copyOut( dst, SystemConvertInt32( size ) )
                    }
                    Memory.free( dst )
                }
            }
            ImageFfi.libBlobFree( blob )
            ret result
        }

        # 一次性合成并落盘（blob 直写文件）；失败返回 false
        public bool save( string path )
        {
            if !ImageFfi.ensureReady()
            {
                ret false
            }
            if path == null || path == ""
            {
                ret false
            }
            Int64 blob = Image.GifEncoder._finishBlob( this )
            if blob == 0
            {
                ret false
            }
            bool ok = ImageFfi.libBlobSave( blob, path )
            ImageFfi.libBlobFree( blob )
            ret ok
        }

        # 显式放弃（幂等；build / save 之后已是空操作）
        public void close()
        {
            if this._enc != 0
            {
                Image.Gif.libGifEncodeFree( this._enc )
                Image.GifEncoder._reset( this )
            }
        }

        # 终点辅助：finish 并失效自身句柄；返回 blob（0 = 失败 / 空编码器）
        static Int64 _finishBlob( GifEncoder self )
        {
            if self._enc == 0
            {
                ret 0
            }
            Int64 blob = Image.Gif.libGifEncodeFinish( self._enc )
            Image.GifEncoder._reset( self )
            ret blob
        }
    }
}
