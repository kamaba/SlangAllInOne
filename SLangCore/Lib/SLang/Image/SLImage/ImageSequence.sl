# =========================================================================
# Image/ImageSequence.sl —— 多帧图像序列遍历（仿 Pillow ImageSequence）
#
# 对标 https://www.runoob.com/pillow/imagesequence-module.html 的核心 API：
#   ImageSequence.Iterator(im)   -> Image.ImageSequence.iterator( doc )   遍历帧
#   ImageSequence.all_frames(im) -> Image.ImageSequence.allFrames( doc )   全帧列表
#   seek(frame)                  -> ImageSequenceIterator.seek( frame )     跳到指定帧
#   tell()                       -> ImageSequenceIterator.tell()            当前帧序号
#   n_frames                     -> ImageSequenceIterator.nFrames           总帧数
#
# 数据源：GifDocument（Gif.decode / Gif.decodeFile 的拆解产物）。
# 静态单帧图（ImageBuffer）经 framesOfImage 包装成单帧序列（Pillow all_frames
# 对非动画图返回单元素列表的语义）。
#
# 迭代协议：ImageSequenceIterator 实现 Core.IIterable<GifFrame> +
# Core.IIterator<GifFrame>（自迭代，iterator() 返回 this），可直接：
#   Image.ImageSequenceIterator it = Image.ImageSequenceIterator( doc )
#   for f in it { ... }        # f : GifFrame
# 游标语义：_index = -1 为首帧之前；moveNext 先加后取；seek(k) 定位到 k 并
# 使 current 立即可用（与 Pillow seek 后 tell() == k 一致）。
# =========================================================================

namespace Image
{
    # ── 帧游标（可 for-in / 手动 moveNext / seek + tell）────────
    public class ImageSequenceIterator interface Core.IIterable<GifFrame>, Core.IIterator<GifFrame>
    {
        # 被遍历文档（null / 无效 = 空迭代器）
        GifDocument _doc = null
        # 当前游标：-1 = 首帧之前（reset 态）；有效域 [0, nFrames)
        Int32 _index = -1
        # 当前帧（moveNext / seek 成功后有效，否则 null）
        GifFrame _current = null

        _init_()
        {
            this._doc = null
            this._index = -1
            this._current = null
        }

        _init_( GifDocument doc )
        {
            this._doc = null
            this._index = -1
            this._current = null
            if doc != null && doc.frames != null
            {
                this._doc = doc
            }
        }

        public get bool isValid()
        {
            ret this._doc != null && this._doc.isValid
        }

        # 帧总数（Pillow n_frames；无效文档返回 0）
        public get Int32 nFrames()
        {
            if this._doc == null || this._doc.frames == null
            {
                ret 0
            }
            ret this._doc.frames.length
        }

        # 当前帧序号（Pillow tell()；-1 = 尚未开始 / 游标已复位）
        public Int32 tell()
        {
            ret this._index
        }

        # 跳到指定帧（Pillow seek(frame) 的安全版：越界返回 false 且游标不动，
        # Pillow 越界抛 EOFError）；成功后 current / tell() 立即反映该帧
        public bool seek( Int32 frame )
        {
            if this._doc == null || this._doc.frames == null
            {
                ret false
            }
            if frame < 0 || frame >= this._doc.frames.length
            {
                ret false
            }
            this._index = frame
            this._current = this._doc.frames[ frame ]
            ret true
        }

        # ── 迭代协议（Core.IIterator<GifFrame>）──────────────
        override void reset()
        {
            this._index = -1
            this._current = null
        }

        override bool moveNext()
        {
            if this._doc == null || this._doc.frames == null
            {
                this._index = -1
                this._current = null
                ret false
            }
            Int32 nxt = this._index + 1
            if nxt >= this._doc.frames.length
            {
                ret false
            }
            this._index = nxt
            this._current = this._doc.frames[ nxt ]
            ret this._current != null
        }

        override get GifFrame current()
        {
            ret this._current
        }

        override get Core.IIterator<GifFrame> iterator()
        {
            this.reset()
            ret this
        }

        override string toString()
        {
            ret "ImageSequenceIterator"
        }
    }

    # ── 门面（全静态，对标 Pillow ImageSequence 模块函数）──────
    public class ImageSequence
    {
        # ═══════════════════════════════════════════════════
        # 1) Iterator（创建帧迭代器）
        # ═══════════════════════════════════════════════════

        # ImageSequence.Iterator(im)：文档 -> 帧迭代器（空 / 无效文档得空迭代器，
        # 不返回 null，遍历安全）
        public static ImageSequenceIterator iterator( GifDocument doc )
        {
            ret ImageSequenceIterator( doc )
        }

        # GIF 字节流 -> 帧迭代器（= Iterator(Image.open(bytes))）
        public static ImageSequenceIterator iteratorOf( Array<UInt8> bytes )
        {
            ret ImageSequenceIterator( Image.Gif.decode( bytes ) )
        }

        # GIF 文件 -> 帧迭代器（= Iterator(Image.open(path))）
        public static ImageSequenceIterator iteratorOfFile( string path )
        {
            ret ImageSequenceIterator( Image.Gif.decodeFile( path ) )
        }

        # ═══════════════════════════════════════════════════
        # 2) all_frames（全帧收集）
        # ═══════════════════════════════════════════════════

        # ImageSequence.all_frames(im)：文档 -> 全帧列表（空 / 无效文档得空列表）
        public static List<GifFrame> allFrames( GifDocument doc )
        {
            List<GifFrame> result = List<GifFrame>()
            if doc == null || doc.frames == null
            {
                ret result
            }
            Int32 i = 0
            while i < doc.frames.length
            {
                GifFrame f = doc.frames[ i ]
                if f != null
                {
                    result.add( f )
                }
                i = i + 1
            }
            ret result
        }

        # GIF 字节流 -> 全帧列表（decode + allFrames 一步到位）
        public static List<GifFrame> allFramesOf( Array<UInt8> bytes )
        {
            ret ImageSequence.allFrames( Image.Gif.decode( bytes ) )
        }

        # 只要帧图（丢弃延迟元数据）：文档 -> List<ImageBuffer>
        public static List<ImageBuffer> allImages( GifDocument doc )
        {
            List<ImageBuffer> result = List<ImageBuffer>()
            if doc == null || doc.frames == null
            {
                ret result
            }
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

        # 静态单帧图 -> 单帧序列（Pillow all_frames 对非动画图的语义：
        # 返回单元素列表；帧图 clone 一份隔离原输入）
        public static List<GifFrame> framesOfImage( ImageBuffer image )
        {
            List<GifFrame> result = List<GifFrame>()
            if image == null || !image.isValid
            {
                ret result
            }
            ImageBuffer copy = image.clone()
            if copy != null && copy.isValid
            {
                result.add( GifFrame( copy, 0 ) )
            }
            ret result
        }

        # ═══════════════════════════════════════════════════
        # 3) n_frames 门面（帧计数）
        # ═══════════════════════════════════════════════════

        # 文档帧数（无效文档 0）；静态图恒 1（Pillow n_frames 语义）
        public static Int32 frameCount( GifDocument doc )
        {
            if doc == null || doc.frames == null
            {
                ret 0
            }
            ret doc.frames.length
        }

        public static Int32 frameCountOfImage( ImageBuffer image )
        {
            if image == null || !image.isValid
            {
                ret 0
            }
            ret 1
        }

        # ═══════════════════════════════════════════════════
        # 4) 帧落盘（教程示例：frame.save(f'frame_{i}.png')）
        # ═══════════════════════════════════════════════════

        # 单帧按格式落盘（quality 仅有损格式有效）
        public static bool saveFrame( GifFrame frame, string path, EImageFormat format, Int32 quality )
        {
            if frame == null || frame.image == null || path == null || path == ""
            {
                ret false
            }
            ret ImageIO.save( frame.image, path, format, quality )
        }

        # 单帧按扩展名推断格式落盘（如 frame_0.png）
        public static bool saveFrame( GifFrame frame, string path )
        {
            if frame == null || frame.image == null || path == null || path == ""
            {
                ret false
            }
            ret ImageIO.save( frame.image, path, 100 )
        }

        # 全部落盘：每帧写 {prefix}{i}.png，返回成功帧数
        public static Int32 saveAllFrames( GifDocument doc, string prefix )
        {
            if doc == null || doc.frames == null || prefix == null || prefix == ""
            {
                ret 0
            }
            Int32 saved = 0
            Int32 i = 0
            while i < doc.frames.length
            {
                GifFrame f = doc.frames[ i ]
                if f != null && f.image != null
                {
                    if ImageIO.save( f.image, prefix + i.toString() + ".png", EImageFormat.Png, 100 )
                    {
                        saved = saved + 1
                    }
                }
                i = i + 1
            }
            ret saved
        }

        override string toString()
        {
            ret "ImageSequence"
        }
    }
}
