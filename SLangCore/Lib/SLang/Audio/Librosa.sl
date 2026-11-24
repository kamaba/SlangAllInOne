# =========================================================================
# Audio/Librosa.sl —— librosa 1.0.1 分析层门面（namespace Audio）
#
# C 契约：../cvm_audio_lib/vm_sl_audio.h 的 sla_lr_*（第 2 组导出，
# 16 个，普通 C ABI），实现为 third_party/librosa 的纯 C 移植
# （sl_librosa.c，上游 ISC 许可，逐算法对齐 librosa 1.0.1）。
# 覆盖：stft / istft / melspectrogram / mfcc / chroma_stft /
#       estimate_tuning / spectral_centroid / bandwidth / rolloff /
#       flatness / rms / zero_crossing_rate / tempo / 标量换算。
#
# 分层（同 AudioFfi.sl）：
#   1) lib* 直接映射层 —— @DllStaticImport 薄封装，绑定失败走函数体
#      兜底（false/0/""），ensureReady() == false 即兜底征兆；
#   2) LibrosaMatrix —— 原生矩阵包装（row-major f32，复数矩阵为
#      re/im 交错），元素级 readFloat32 访问零拷贝；
#   3) 便利层 —— AudioBuffer 进 / LibrosaMatrix|Array<Float32> 出，
#      尺寸全部先验计算（rows/cols 公式与 C 层一致）：
#        stft:   rows = 1 + nFft/2, cols = 1 + frames/hop
#        melspec:rows = nMels,      cols 同 stft
#        mfcc:   rows = nMfcc
#        chroma: rows = 12
#        向量:    n = cols（谱特征）或 1 + frames/hop（rms/zcr）
#
# 内存模型：输入 AudioBuffer 取 0 声道转 mono 原生块（逐样本
# writeF32 搬运，<= MAX_INPUT_SAMPLES）；输出块 Memory.alloc 预分配、
# C 填充；LibrosaMatrix 持有输出块所有权，free() 归还。
# 默认参数（librosa 对齐）：nFft=2048 hop=512 nMels=128 nMfcc=20。
# =========================================================================

namespace Audio
{
    # ── 原生矩阵包装（row-major f32；复数 = re/im 交错） ──────────
    public class LibrosaMatrix
    {
        public Int64 ptr = 0
        public Int32 rows = 0
        public Int32 cols = 0
        public bool complex = false

        _init_()
        {
            this.ptr = 0
            this.rows = 0
            this.cols = 0
            this.complex = false
        }

        _init_( Int64 _ptr, Int32 _rows, Int32 _cols, bool _complex )
        {
            this.ptr = _ptr
            this.rows = _rows
            this.cols = _cols
            this.complex = _complex
        }

        public Int32 rowCount()
        {
            ret this.rows
        }

        public Int32 colCount()
        {
            ret this.cols
        }

        public bool isValid()
        {
            ret this.ptr != 0 && this.rows > 0 && this.cols > 0
        }

        # 元素值（复数矩阵取实部）
        public Float32 at( Int32 r, Int32 c )
        {
            Int32 off = this._offset( r, c, 0 )
            if off < 0
            {
                ret 0.0f
            }
            ret Memory.readFloat32( this.ptr, off )
        }

        # 虚部（仅复数矩阵；实矩阵恒 0）
        public Float32 imag( Int32 r, Int32 c )
        {
            if !this.complex
            {
                ret 0.0f
            }
            Int32 off = this._offset( r, c, 4 )
            if off < 0
            {
                ret 0.0f
            }
            ret Memory.readFloat32( this.ptr, off + 4 )
        }

        public void setValue( Int32 r, Int32 c, Float32 v )
        {
            Int32 off = this._offset( r, c, 0 )
            if off < 0
            {
                ret
            }
            Memory.writeF32( this.ptr, off, v )
        }

        # 拷贝出实部矩阵（rows*cols <= Librosa.MAX_INLINE_ELEMS；
        # 复数矩阵仅取实部）
        public Array<Float32> toRealArray()
        {
            if !this.isValid()
            {
                ret null
            }
            Int64 n = this.rows
            n = n * this.cols
            if n > Librosa.MAX_INLINE_ELEMS
            {
                ret null
            }
            Int32 cnt = SystemConvertInt32( n )
            Array<Float32> res = Array<Float32>( cnt )
            Int32 i = 0
            while i < cnt
            {
                Int32 r = i / this.cols
                Int32 c = i - r * this.cols
                res[ i ] = this.at( r, c )
                i = i + 1
            }
            ret res
        }

        # 释放原生块（幂等）
        public void free()
        {
            if this.ptr != 0
            {
                Memory.free( this.ptr )
                this.ptr = 0
                this.rows = 0
                this.cols = 0
            }
        }

        override string toString()
        {
            string kind = "real"
            if this.complex
            {
                kind = "complex"
            }
            ret "LibrosaMatrix(" + kind + ", " + this.rows.toString() + "x" + this.cols.toString() + ")"
        }

        # 字节偏移（越界返回 -1；extra 仅复数虚部使用）
        Int32 _offset( Int32 r, Int32 c, Int32 extra )
        {
            if !this.isValid()
            {
                ret -1
            }
            if r < 0 || r >= this.rows
            {
                ret -1
            }
            if c < 0 || c >= this.cols
            {
                ret -1
            }
            Int32 stride = 1
            if this.complex
            {
                stride = 2
            }
            Int64 idx = r
            idx = idx * this.cols + c
            Int64 bytes = idx * stride * 4 + extra
            ret SystemConvertInt32( bytes )
        }
    }

    # ── librosa 门面（静态） ────────────────────────────────────────
    public class Librosa
    {
        # 尺寸墙：stft/mel/mfcc/chroma 单侧矩阵 float 元素上限
        public static const Int32 MAX_MATRIX_ELEMS = 16777216

        # 尺寸墙：toRealArray 拷贝上限（同 AudioFfi.MAX_INLINE_BYTES 语义）
        public static const Int32 MAX_INLINE_ELEMS = 1048576

        # 尺寸墙：AudioBuffer -> mono 原生块样本上限（约 90s@48kHz）
        public static const Int32 MAX_INPUT_SAMPLES = 4194304

        # librosa 默认参数（便利层不带参时的缺省）
        public static const Int32 DEFAULT_NFFT = 2048
        public static const Int32 DEFAULT_HOP = 512
        public static const Int32 DEFAULT_NMELS = 128
        public static const Int32 DEFAULT_NMFCC = 20

        # sla_lr_scalar op（vm_sl_audio.h SLA_LRS_*）
        public static const Int32 OP_HZ_TO_MEL = 1
        public static const Int32 OP_MEL_TO_HZ = 2
        public static const Int32 OP_HZ_TO_MEL_HTK = 3
        public static const Int32 OP_MEL_TO_HZ_HTK = 4
        public static const Int32 OP_HZ_TO_MIDI = 5
        public static const Int32 OP_MIDI_TO_HZ = 6
        public static const Int32 OP_POWER_TO_DB = 7
        public static const Int32 OP_DB_TO_POWER = 8
        public static const Int32 OP_AMP_TO_DB = 9
        public static const Int32 OP_DB_TO_AMP = 10

        # sla_lr_vecs op（vm_sl_audio.h SLA_LRV_*）
        public static const Int32 VEC_CENTROID = 1
        public static const Int32 VEC_BANDWIDTH = 2
        public static const Int32 VEC_ROLLOFF = 3
        public static const Int32 VEC_FLATNESS = 4

        static bool _ready = false
        static bool _checked = false

        # librosa 层无状态：就绪 == FFI 绑定可用（version 串非空）
        public static bool ensureReady()
        {
            if Librosa._checked
            {
                ret Librosa._ready
            }
            Librosa._ready = Librosa.libVersionString() != ""
            Librosa._checked = true
            ret Librosa._ready
        }

        public static void shutdown()
        {
            Librosa._ready = false
            Librosa._checked = false
        }

        # 最近一次错误文本（SLA_OK 时返回空串）
        public static string lastErrorText()
        {
            Int32 code = Librosa.libLastError()
            if code == 0
            {
                ret ""
            }
            string s = Librosa.libErrorString( code )
            if s == null
            {
                ret ""
            }
            ret s
        }

        # ═══════════════════════════════════════════════════
        # 1) lib* 直接映射层（16 个 sla_lr_*）
        # ═══════════════════════════════════════════════════

        @DllStaticImport( "sl_audio_lib", "sla_lr_last_error", "->i32" )
        public static Int32 libLastError()
        {
            ret 0
        }

        @DllStaticImport( "sl_audio_lib", "sla_lr_error_string", "i32->utf8" )
        public static string libErrorString( Int32 code )
        {
            ret ""
        }

        @DllStaticImport( "sl_audio_lib", "sla_lr_version_string", "->utf8" )
        public static string libVersionString()
        {
            ret ""
        }

        @DllStaticImport( "sl_audio_lib", "sla_lr_scalar", "i32,f64,f64->f64" )
        public static Float64 libScalar( Int32 op, Float64 x, Float64 ref )
        {
            ret 0.0
        }

        @DllStaticImport( "sl_audio_lib", "sla_lr_hz_to_note", "f64->utf8" )
        public static string libHzToNote( Float64 hz )
        {
            ret ""
        }

        @DllStaticImport( "sl_audio_lib", "sla_lr_stft", "ptr,i64,i32,i32,ptr->bool" )
        public static bool libStft( Int64 yPtr, Int64 n, Int32 nFft, Int32 hop, Int64 outPtr )
        {
            ret false
        }

        @DllStaticImport( "sl_audio_lib", "sla_lr_istft", "ptr,i64,i64,i32,i64,ptr->i64" )
        public static Int64 libIstft( Int64 reimPtr, Int64 rows, Int64 cols, Int32 hop, Int64 length, Int64 dstPtr )
        {
            ret 0
        }

        @DllStaticImport( "sl_audio_lib", "sla_lr_melspec", "ptr,i64,i64,i32,i32,ptr->bool" )
        public static bool libMelspec( Int64 reimPtr, Int64 rows, Int64 cols, Int32 sr, Int32 nMels, Int64 outPtr )
        {
            ret false
        }

        @DllStaticImport( "sl_audio_lib", "sla_lr_mfcc", "ptr,i64,i64,i32,ptr->bool" )
        public static bool libMfcc( Int64 melPtr, Int64 melRows, Int64 cols, Int32 nMfcc, Int64 outPtr )
        {
            ret false
        }

        @DllStaticImport( "sl_audio_lib", "sla_lr_chroma", "ptr,i64,i64,i32,ptr->bool" )
        public static bool libChroma( Int64 reimPtr, Int64 rows, Int64 cols, Int32 sr, Int64 outPtr )
        {
            ret false
        }

        @DllStaticImport( "sl_audio_lib", "sla_lr_tuning", "ptr,i64,i64,i32,ptr->bool" )
        public static bool libTuning( Int64 reimPtr, Int64 rows, Int64 cols, Int32 sr, Int64 outF64Ptr )
        {
            ret false
        }

        @DllStaticImport( "sl_audio_lib", "sla_lr_vecs", "ptr,i64,i64,i32,i32,ptr->i64" )
        public static Int64 libVecs( Int64 reimPtr, Int64 rows, Int64 cols, Int32 sr, Int32 op, Int64 dstPtr )
        {
            ret 0
        }

        @DllStaticImport( "sl_audio_lib", "sla_lr_rms", "ptr,i64,i32,i32,ptr->i64" )
        public static Int64 libRms( Int64 yPtr, Int64 n, Int32 frameLen, Int32 hop, Int64 dstPtr )
        {
            ret 0
        }

        @DllStaticImport( "sl_audio_lib", "sla_lr_zcr", "ptr,i64,i32,i32,ptr->i64" )
        public static Int64 libZcr( Int64 yPtr, Int64 n, Int32 frameLen, Int32 hop, Int64 dstPtr )
        {
            ret 0
        }

        @DllStaticImport( "sl_audio_lib", "sla_lr_tempo", "ptr,i64,i32,i32,ptr->bool" )
        public static bool libTempo( Int64 yPtr, Int64 n, Int32 sr, Int32 hop, Int64 outF64Ptr )
        {
            ret false
        }

        # ═══════════════════════════════════════════════════
        # 2) 内部搬运辅助
        # ═══════════════════════════════════════════════════

        # AudioBuffer -> mono f32 原生块（取 0 声道；失败 0）
        static Int64 _monoPtr( AudioBuffer buf )
        {
            if buf == null
            {
                ret 0
            }
            Int32 frames = buf.frameCount()
            if frames <= 0
            {
                ret 0
            }
            if frames > Librosa.MAX_INPUT_SAMPLES
            {
                ret 0
            }
            Int64 p = Memory.alloc( frames * 4 )
            if p == 0
            {
                ret 0
            }
            Int32 i = 0
            while i < frames
            {
                Memory.writeF32( p, i * 4, buf.getSample( i, 0 ) )
                i = i + 1
            }
            ret p
        }

        # 原生 f32 块 -> Array<Float32>
        static Array<Float32> _readVec( Int64 p, Int32 n )
        {
            if p == 0 || n <= 0
            {
                ret null
            }
            Array<Float32> r = Array<Float32>( n )
            Int32 i = 0
            while i < n
            {
                r[ i ] = Memory.readFloat32( p, i * 4 )
                i = i + 1
            }
            ret r
        }

        # 参数校验（nFft 2 的幂 / hop 范围）
        static bool _validFft( Int32 nFft, Int32 hop )
        {
            if nFft < 8 || nFft > 32768
            {
                ret false
            }
            if hop < 1 || hop > nFft
            {
                ret false
            }
            ret true
        }

        # stft 复数矩阵分配（失败 0；elems 为 float 元素数）
        static Int64 _allocMatrix( Int32 rows, Int32 cols, Int32 perCell )
        {
            Int64 n = rows
            n = n * cols * perCell
            if n > Librosa.MAX_MATRIX_ELEMS
            {
                ret 0
            }
            if n <= 0
            {
                ret 0
            }
            ret Memory.alloc( SystemConvertInt32( n * 4 ) )
        }

        # ═══════════════════════════════════════════════════
        # 3) 便利层
        # ═══════════════════════════════════════════════════

        # ── STFT / ISTFT ─────────────────────────────────

        # 复数谱矩阵（自定 nFft/hop）
        public static LibrosaMatrix stftWith( AudioBuffer buf, Int32 nFft, Int32 hop )
        {
            if !Librosa.ensureReady()
            {
                ret null
            }
            if buf == null
            {
                ret null
            }
            if !buf.isValid()
            {
                ret null
            }
            if !Librosa._validFft( nFft, hop )
            {
                ret null
            }
            Int32 frames = buf.frameCount()
            Int64 src = Librosa._monoPtr( buf )
            if src == 0
            {
                ret null
            }
            Int32 rows = 1 + nFft / 2
            Int32 cols = 1 + frames / hop
            Int64 outPtr = Librosa._allocMatrix( rows, cols, 2 )
            LibrosaMatrix m = null
            if outPtr != 0
            {
                if Librosa.libStft( src, frames, nFft, hop, outPtr )
                {
                    m = LibrosaMatrix( outPtr, rows, cols, true )
                }
                else
                {
                    Memory.free( outPtr )
                }
            }
            Memory.free( src )
            ret m
        }

        # 复数谱矩阵（librosa 默认 nFft=2048 hop=512）
        public static LibrosaMatrix stft( AudioBuffer buf )
        {
            ret Librosa.stftWith( buf, Librosa.DEFAULT_NFFT, Librosa.DEFAULT_HOP )
        }

        # 逆变换（length<=0 用默认全长 hop*(cols-1)）；
        # sampleRate 回填进产物 AudioBuffer（声道恒 1）
        public static AudioBuffer istft( LibrosaMatrix m, Int32 hop, Int32 length, Int32 sampleRate )
        {
            if !Librosa.ensureReady()
            {
                ret null
            }
            if m == null
            {
                ret null
            }
            if !m.isValid()
            {
                ret null
            }
            if !m.complex
            {
                ret null
            }
            if hop < 1
            {
                ret null
            }
            if length <= 0
            {
                length = hop * ( m.cols - 1 )
            }
            if length <= 0 || length > Librosa.MAX_INPUT_SAMPLES
            {
                ret null
            }
            Int64 outPtr = Memory.alloc( length * 4 )
            if outPtr == 0
            {
                ret null
            }
            Int64 got = Librosa.libIstft( m.ptr, m.rows, m.cols, hop, length, outPtr )
            AudioBuffer buf = null
            if got == length
            {
                buf = AudioBuffer( sampleRate, 1, length )
                Int32 i = 0
                while i < length
                {
                    buf.setSample( i, 0, Memory.readFloat32( outPtr, i * 4 ) )
                    i = i + 1
                }
            }
            Memory.free( outPtr )
            ret buf
        }

        # ── mel 频谱 / MFCC / chroma ──────────────────────

        # mel 功率谱（输入复数谱矩阵；rows=nMels）
        public static LibrosaMatrix melspectrogramOfStft( LibrosaMatrix m, Int32 sr, Int32 nMels )
        {
            if !Librosa.ensureReady()
            {
                ret null
            }
            if m == null
            {
                ret null
            }
            if !m.isValid()
            {
                ret null
            }
            if !m.complex
            {
                ret null
            }
            if nMels < 2 || nMels > 512
            {
                ret null
            }
            Int64 outPtr = Librosa._allocMatrix( nMels, m.cols, 1 )
            LibrosaMatrix r = null
            if outPtr != 0
            {
                if Librosa.libMelspec( m.ptr, m.rows, m.cols, sr, nMels, outPtr )
                {
                    r = LibrosaMatrix( outPtr, nMels, m.cols, false )
                }
                else
                {
                    Memory.free( outPtr )
                }
            }
            ret r
        }

        # mel 功率谱（一步到位；librosa 默认参数）
        public static LibrosaMatrix melspectrogram( AudioBuffer buf )
        {
            LibrosaMatrix s = Librosa.stft( buf )
            if s == null
            {
                ret null
            }
            LibrosaMatrix r = Librosa.melspectrogramOfStft( s, buf.sampleRate, Librosa.DEFAULT_NMELS )
            s.free()
            ret r
        }

        # mel 功率谱（自定 nFft/hop/nMels）
        public static LibrosaMatrix melspectrogramWith( AudioBuffer buf, Int32 nFft, Int32 hop, Int32 nMels )
        {
            LibrosaMatrix s = Librosa.stftWith( buf, nFft, hop )
            if s == null
            {
                ret null
            }
            LibrosaMatrix r = Librosa.melspectrogramOfStft( s, buf.sampleRate, nMels )
            s.free()
            ret r
        }

        # MFCC（输入 mel 功率谱矩阵；rows=nMfcc <= mel 行数）
        public static LibrosaMatrix mfccOfMel( LibrosaMatrix mel, Int32 nMfcc )
        {
            if !Librosa.ensureReady()
            {
                ret null
            }
            if mel == null
            {
                ret null
            }
            if !mel.isValid()
            {
                ret null
            }
            if nMfcc < 1 || nMfcc > 128
            {
                ret null
            }
            if nMfcc > mel.rows
            {
                ret null
            }
            Int64 outPtr = Librosa._allocMatrix( nMfcc, mel.cols, 1 )
            LibrosaMatrix r = null
            if outPtr != 0
            {
                if Librosa.libMfcc( mel.ptr, mel.rows, mel.cols, nMfcc, outPtr )
                {
                    r = LibrosaMatrix( outPtr, nMfcc, mel.cols, false )
                }
                else
                {
                    Memory.free( outPtr )
                }
            }
            ret r
        }

        # MFCC（一步到位；librosa 默认参数）
        public static LibrosaMatrix mfcc( AudioBuffer buf )
        {
            LibrosaMatrix mel = Librosa.melspectrogram( buf )
            if mel == null
            {
                ret null
            }
            LibrosaMatrix r = Librosa.mfccOfMel( mel, Librosa.DEFAULT_NMFCC )
            mel.free()
            ret r
        }

        # MFCC（自定 nFft/hop/nMels/nMfcc）
        public static LibrosaMatrix mfccWith( AudioBuffer buf, Int32 nFft, Int32 hop, Int32 nMels, Int32 nMfcc )
        {
            LibrosaMatrix mel = Librosa.melspectrogramWith( buf, nFft, hop, nMels )
            if mel == null
            {
                ret null
            }
            LibrosaMatrix r = Librosa.mfccOfMel( mel, nMfcc )
            mel.free()
            ret r
        }

        # chroma（输入复数谱矩阵；rows=12，行序 C..B）
        public static LibrosaMatrix chromaOfStft( LibrosaMatrix m, Int32 sr )
        {
            if !Librosa.ensureReady()
            {
                ret null
            }
            if m == null
            {
                ret null
            }
            if !m.isValid()
            {
                ret null
            }
            if !m.complex
            {
                ret null
            }
            Int64 outPtr = Librosa._allocMatrix( 12, m.cols, 1 )
            LibrosaMatrix r = null
            if outPtr != 0
            {
                if Librosa.libChroma( m.ptr, m.rows, m.cols, sr, outPtr )
                {
                    r = LibrosaMatrix( outPtr, 12, m.cols, false )
                }
                else
                {
                    Memory.free( outPtr )
                }
            }
            ret r
        }

        # chroma（一步到位；librosa 默认参数）
        public static LibrosaMatrix chroma( AudioBuffer buf )
        {
            LibrosaMatrix s = Librosa.stft( buf )
            if s == null
            {
                ret null
            }
            LibrosaMatrix r = Librosa.chromaOfStft( s, buf.sampleRate )
            s.free()
            ret r
        }

        # ── 调音估计 ──────────────────────────────────────

        # 调音偏差 [-0.5,0.5)（输入复数谱矩阵；无有效峰值返回 0）
        public static Float64 tuningOfStft( LibrosaMatrix m, Int32 sr )
        {
            if !Librosa.ensureReady()
            {
                ret 0.0
            }
            if m == null
            {
                ret 0.0
            }
            if !m.isValid()
            {
                ret 0.0
            }
            if !m.complex
            {
                ret 0.0
            }
            Int64 p = Memory.alloc( 8 )
            if p == 0
            {
                ret 0.0
            }
            Float64 v = 0.0
            if Librosa.libTuning( m.ptr, m.rows, m.cols, sr, p )
            {
                v = Memory.readFloat64( p, 0 )
            }
            Memory.free( p )
            ret v
        }

        # ── 谱向量特征（逐帧，长度 = stft cols） ──────────

        static Array<Float32> _vecsOfStft( LibrosaMatrix m, Int32 sr, Int32 op )
        {
            if !Librosa.ensureReady()
            {
                ret null
            }
            if m == null
            {
                ret null
            }
            if !m.isValid()
            {
                ret null
            }
            if !m.complex
            {
                ret null
            }
            Int64 p = Memory.alloc( m.cols * 4 )
            if p == 0
            {
                ret null
            }
            Array<Float32> r = null
            Int64 got = Librosa.libVecs( m.ptr, m.rows, m.cols, sr, op, p )
            if got == m.cols
            {
                r = Librosa._readVec( p, m.cols )
            }
            Memory.free( p )
            ret r
        }

        public static Array<Float32> centroidOfStft( LibrosaMatrix m, Int32 sr )
        {
            ret Librosa._vecsOfStft( m, sr, Librosa.VEC_CENTROID )
        }

        public static Array<Float32> bandwidthOfStft( LibrosaMatrix m, Int32 sr )
        {
            ret Librosa._vecsOfStft( m, sr, Librosa.VEC_BANDWIDTH )
        }

        public static Array<Float32> rolloffOfStft( LibrosaMatrix m, Int32 sr )
        {
            ret Librosa._vecsOfStft( m, sr, Librosa.VEC_ROLLOFF )
        }

        public static Array<Float32> flatnessOfStft( LibrosaMatrix m )
        {
            ret Librosa._vecsOfStft( m, 22050, Librosa.VEC_FLATNESS )
        }

        public static Array<Float32> spectralCentroid( AudioBuffer buf )
        {
            LibrosaMatrix s = Librosa.stft( buf )
            if s == null
            {
                ret null
            }
            Array<Float32> r = Librosa.centroidOfStft( s, buf.sampleRate )
            s.free()
            ret r
        }

        public static Array<Float32> spectralBandwidth( AudioBuffer buf )
        {
            LibrosaMatrix s = Librosa.stft( buf )
            if s == null
            {
                ret null
            }
            Array<Float32> r = Librosa.bandwidthOfStft( s, buf.sampleRate )
            s.free()
            ret r
        }

        public static Array<Float32> spectralRolloff( AudioBuffer buf )
        {
            LibrosaMatrix s = Librosa.stft( buf )
            if s == null
            {
                ret null
            }
            Array<Float32> r = Librosa.rolloffOfStft( s, buf.sampleRate )
            s.free()
            ret r
        }

        public static Array<Float32> spectralFlatness( AudioBuffer buf )
        {
            LibrosaMatrix s = Librosa.stft( buf )
            if s == null
            {
                ret null
            }
            Array<Float32> r = Librosa.flatnessOfStft( s )
            s.free()
            ret r
        }

        # ── 时域向量特征 ──────────────────────────────────

        static Array<Float32> _framesOfBuf( AudioBuffer buf, Int32 frameLen, Int32 hop, bool isRms )
        {
            if !Librosa.ensureReady()
            {
                ret null
            }
            if buf == null
            {
                ret null
            }
            if !buf.isValid()
            {
                ret null
            }
            if frameLen < 8 || frameLen > 65536
            {
                ret null
            }
            if hop < 1 || hop > frameLen
            {
                ret null
            }
            Int32 frames = buf.frameCount()
            Int64 src = Librosa._monoPtr( buf )
            if src == 0
            {
                ret null
            }
            Int32 cols = 1 + frames / hop
            Int64 p = Memory.alloc( cols * 4 )
            Array<Float32> r = null
            if p != 0
            {
                Int64 got = 0
                if isRms
                {
                    got = Librosa.libRms( src, frames, frameLen, hop, p )
                }
                else
                {
                    got = Librosa.libZcr( src, frames, frameLen, hop, p )
                }
                if got == cols
                {
                    r = Librosa._readVec( p, cols )
                }
            }
            Memory.free( src )
            if p != 0
            {
                Memory.free( p )
            }
            ret r
        }

        # RMS（librosa 默认 frame=2048 hop=512）
        public static Array<Float32> rms( AudioBuffer buf )
        {
            ret Librosa._framesOfBuf( buf, Librosa.DEFAULT_NFFT, Librosa.DEFAULT_HOP, true )
        }

        # 过零率（librosa 默认 frame=2048 hop=512）
        public static Array<Float32> zeroCrossingRate( AudioBuffer buf )
        {
            ret Librosa._framesOfBuf( buf, Librosa.DEFAULT_NFFT, Librosa.DEFAULT_HOP, false )
        }

        # ── 节奏 ─────────────────────────────────────────

        # BPM 估计（librosa.feature.tempo 默认参数；失败 0）
        public static Float64 tempo( AudioBuffer buf )
        {
            if !Librosa.ensureReady()
            {
                ret 0.0
            }
            if buf == null
            {
                ret 0.0
            }
            if !buf.isValid()
            {
                ret 0.0
            }
            Int32 frames = buf.frameCount()
            Int64 src = Librosa._monoPtr( buf )
            if src == 0
            {
                ret 0.0
            }
            Int64 p = Memory.alloc( 8 )
            Float64 v = 0.0
            if p != 0
            {
                if Librosa.libTempo( src, frames, buf.sampleRate, Librosa.DEFAULT_HOP, p )
                {
                    v = Memory.readFloat64( p, 0 )
                }
                Memory.free( p )
            }
            Memory.free( src )
            ret v
        }

        # ── 标量换算（librosa.core.convert / spectrum） ──

        public static Float64 hzToMel( Float64 hz )
        {
            ret Librosa.libScalar( Librosa.OP_HZ_TO_MEL, hz, 0.0 )
        }

        public static Float64 melToHz( Float64 mel )
        {
            ret Librosa.libScalar( Librosa.OP_MEL_TO_HZ, mel, 0.0 )
        }

        public static Float64 hzToMidi( Float64 hz )
        {
            ret Librosa.libScalar( Librosa.OP_HZ_TO_MIDI, hz, 0.0 )
        }

        public static Float64 midiToHz( Float64 midi )
        {
            ret Librosa.libScalar( Librosa.OP_MIDI_TO_HZ, midi, 0.0 )
        }

        public static Float64 powerToDb( Float64 x, Float64 ref )
        {
            ret Librosa.libScalar( Librosa.OP_POWER_TO_DB, x, ref )
        }

        public static Float64 dbToPower( Float64 db, Float64 ref )
        {
            ret Librosa.libScalar( Librosa.OP_DB_TO_POWER, db, ref )
        }

        public static Float64 amplitudeToDb( Float64 x, Float64 ref )
        {
            ret Librosa.libScalar( Librosa.OP_AMP_TO_DB, x, ref )
        }

        public static Float64 dbToAmplitude( Float64 db, Float64 ref )
        {
            ret Librosa.libScalar( Librosa.OP_DB_TO_AMP, db, ref )
        }

        # 音名（"C#4" 风格；绑定失败空串）
        public static string hzToNote( Float64 hz )
        {
            ret Librosa.libHzToNote( hz )
        }
    }
}
