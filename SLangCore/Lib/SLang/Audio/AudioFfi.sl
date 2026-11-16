# =========================================================================
# Audio/AudioFfi.sl —— C 层 sl_audio_lib.dll 的 FFI 静态绑定 + 内存搬运
#
# C 契约：../cvm_audio_lib/vm_sl_audio.h（34 个 sla_* 导出，普通 C ABI）
# 后端：  minimp4 / minimp3（CC0 公有领域，MP4 解封装 + MP3 解码）+
#         Media Foundation AAC 解码 MFT（系统组件）+ waveOut 播放
#         （winmm + 库自持服务线程 + 环形缓冲，全内部实现零外部依赖）
# PCM 契约：恒 interleaved S16LE（decode / stream / playback 统一），
#           采样率 / 声道数保持源值；句柄 1 起始，0 = 无效
#
# 分层（同 Image/ImageFfi.sl）：
#   1) lib* 直接映射层 —— @DllStaticImport 薄封装，绑定失败走函数体兜底
#      （false/0/""，ensureReady() == false 即兜底征兆）
#   2) 格式映射 —— EAudioFormat / ESampleFormat 与 SLA_FMT_* 显式逐值
#      映射（值不恒等，必须走本层转换）
#   3) 便利层 —— probeFile / probeMem（AudioInfo 组装）
#
# 已知缺口（v1 约束，与 Image 模块同款）：VM 没有 Array<UInt8> <->
# 原生指针的批量互转系统方法，内存路径用 Memory.alloc + 逐字节
# writeI8/readUInt8 搬运，故设 MAX_INLINE_BYTES = 4 MiB 上限；S16 采样
# 用 readInt16/writeI16 半字搬运（减半循环次数）。大音频请走文件路径
# API（probeFile / libDecodeFile 直通 C 层零搬运），或 AudioClip 句柄
# 路径（PCM 留在 C 侧，仅播放时原生块直转）。
# =========================================================================

namespace Audio
{
    public class AudioFfi
    {
        # 内存搬运上限（4 MiB）：*Mem / s16Bytes 路径的尺寸墙
        public static const Int32 MAX_INLINE_BYTES = 4194304

        # 原生块直转上限（64 MiB）：enqueueClip / toAudioBuffer 的
        # AudioClip 句柄路径尺寸墙（PCM 经 C 侧临时块，不经 SL 字节环）
        public static const Int32 MAX_NATIVE_BYTES = 67108864

        # probe 输出块大小（vm_sl_audio.h SLA_PROBE_OUT_BYTES）：
        # 6 x int32 = srcFormat / sampleRate / channels / bitsPerSample /
        # frameCountLo / frameCountHi
        public static const Int32 PROBE_OUT_BYTES = 24

        # fmt_hint 常量（sla_decode_* / sla_stream_create 入参）
        public static const Int32 HINT_AUTO    = 0
        public static const Int32 HINT_PCM_S16 = 2
        public static const Int32 HINT_PCM_U8  = 3
        public static const Int32 HINT_PCM_F32 = 4
        public static const Int32 HINT_MP3     = 5
        public static const Int32 HINT_AAC_ADTS = 6

        static bool _ready = false

        # ── 生命周期 ─────────────────────────────────────────
        public static bool ensureReady()
        {
            if AudioFfi._ready
            {
                ret true
            }
            AudioFfi._ready = AudioFfi.libInit()
            ret AudioFfi._ready
        }

        public static void shutdown()
        {
            if AudioFfi._ready
            {
                AudioFfi.libUninit()
                AudioFfi._ready = false
            }
        }

        # 最近一次错误文本（SLA_OK 时返回空串）
        public static string lastErrorText()
        {
            Int32 code = AudioFfi.libLastError()
            if code == 0
            {
                ret ""
            }
            string s = AudioFfi.libErrorString( code )
            if s == null
            {
                ret ""
            }
            ret s
        }

        # 最近一次错误详情（粘性 detail，与 lastErrorText 配套）
        public static string lastErrorDetailText()
        {
            string s = AudioFfi.libErrorDetail()
            if s == null
            {
                ret ""
            }
            ret s
        }

        # ═══════════════════════════════════════════════════
        # 1) lib* 直接映射层（34 个 sla_*）
        # ═══════════════════════════════════════════════════

        # ── 生命周期 / 诊断 ──

        @DllStaticImport( "sl_audio_lib", "sla_init", "->bool" )
        public static bool libInit()
        {
            ret false
        }

        @DllStaticImport( "sl_audio_lib", "sla_uninit", "->bool" )
        public static bool libUninit()
        {
            ret false
        }

        @DllStaticImport( "sl_audio_lib", "sla_last_error", "->i32" )
        public static Int32 libLastError()
        {
            ret 0
        }

        @DllStaticImport( "sl_audio_lib", "sla_error_string", "i32->utf8" )
        public static string libErrorString( Int32 code )
        {
            ret ""
        }

        @DllStaticImport( "sl_audio_lib", "sla_error_detail", "->utf8" )
        public static string libErrorDetail()
        {
            ret ""
        }

        @DllStaticImport( "sl_audio_lib", "sla_version_string", "->utf8" )
        public static string libVersionString()
        {
            ret ""
        }

        @DllStaticImport( "sl_audio_lib", "sla_backend_list", "->utf8" )
        public static string libBackendList()
        {
            ret ""
        }

        # ── 探测（输出 24 字节块，布局见 PROBE_OUT_BYTES）──

        @DllStaticImport( "sl_audio_lib", "sla_probe_file", "utf8,ptr->bool" )
        public static bool libProbeFile( string path, Int64 outPtr )
        {
            ret false
        }

        @DllStaticImport( "sl_audio_lib", "sla_probe_mem", "ptr,i64,ptr->bool" )
        public static bool libProbeMem( Int64 dataPtr, Int64 size, Int64 outPtr )
        {
            ret false
        }

        # ── 整段解码（dec 句柄 1 起始；0 = 失败）──

        @DllStaticImport( "sl_audio_lib", "sla_decode_file", "utf8,i32->i64" )
        public static Int64 libDecodeFile( string path, Int32 fmtHint )
        {
            ret 0
        }

        @DllStaticImport( "sl_audio_lib", "sla_decode_mem", "ptr,i64,i32->i64" )
        public static Int64 libDecodeMem( Int64 dataPtr, Int64 size, Int32 fmtHint )
        {
            ret 0
        }

        @DllStaticImport( "sl_audio_lib", "sla_dec_sample_rate", "i64->i32" )
        public static Int32 libDecSampleRate( Int64 dec )
        {
            ret 0
        }

        @DllStaticImport( "sl_audio_lib", "sla_dec_channels", "i64->i32" )
        public static Int32 libDecChannels( Int64 dec )
        {
            ret 0
        }

        @DllStaticImport( "sl_audio_lib", "sla_dec_source_format", "i64->i32" )
        public static Int32 libDecSourceFormat( Int64 dec )
        {
            ret 0
        }

        @DllStaticImport( "sl_audio_lib", "sla_dec_frame_count", "i64->i64" )
        public static Int64 libDecFrameCount( Int64 dec )
        {
            ret 0
        }

        @DllStaticImport( "sl_audio_lib", "sla_dec_copy_i16", "i64,ptr,i64->i64" )
        public static Int64 libDecCopyI16( Int64 dec, Int64 dstPtr, Int64 capFrames )
        {
            ret 0
        }

        @DllStaticImport( "sl_audio_lib", "sla_dec_free", "i64->bool" )
        public static bool libDecFree( Int64 dec )
        {
            ret false
        }

        # ── 流式解码（stm 句柄）──

        @DllStaticImport( "sl_audio_lib", "sla_stream_create", "i32,i32,i32->i64" )
        public static Int64 libStreamCreate( Int32 fmtHint, Int32 sampleRate, Int32 channels )
        {
            ret 0
        }

        @DllStaticImport( "sl_audio_lib", "sla_stream_feed", "i64,ptr,i64->i64" )
        public static Int64 libStreamFeed( Int64 stm, Int64 dataPtr, Int64 size )
        {
            ret 0
        }

        @DllStaticImport( "sl_audio_lib", "sla_stream_read_i16", "i64,ptr,i64->i64" )
        public static Int64 libStreamReadI16( Int64 stm, Int64 dstPtr, Int64 capFrames )
        {
            ret 0
        }

        @DllStaticImport( "sl_audio_lib", "sla_stream_sample_rate", "i64->i32" )
        public static Int32 libStreamSampleRate( Int64 stm )
        {
            ret 0
        }

        @DllStaticImport( "sl_audio_lib", "sla_stream_channels", "i64->i32" )
        public static Int32 libStreamChannels( Int64 stm )
        {
            ret 0
        }

        @DllStaticImport( "sl_audio_lib", "sla_stream_source_format", "i64->i32" )
        public static Int32 libStreamSourceFormat( Int64 stm )
        {
            ret 0
        }

        @DllStaticImport( "sl_audio_lib", "sla_stream_frames_out", "i64->i64" )
        public static Int64 libStreamFramesOut( Int64 stm )
        {
            ret 0
        }

        @DllStaticImport( "sl_audio_lib", "sla_stream_free", "i64->bool" )
        public static bool libStreamFree( Int64 stm )
        {
            ret false
        }

        # ── 播放（ply 句柄，waveOut + 库自持线程）──

        @DllStaticImport( "sl_audio_lib", "sla_device_available", "->bool" )
        public static bool libDeviceAvailable()
        {
            ret false
        }

        @DllStaticImport( "sl_audio_lib", "sla_player_create", "i32,i32->i64" )
        public static Int64 libPlayerCreate( Int32 sampleRate, Int32 channels )
        {
            ret 0
        }

        @DllStaticImport( "sl_audio_lib", "sla_player_enqueue", "i64,ptr,i64->i64" )
        public static Int64 libPlayerEnqueue( Int64 ply, Int64 pcmPtr, Int64 frames )
        {
            ret 0
        }

        @DllStaticImport( "sl_audio_lib", "sla_player_pause", "i64,i32->bool" )
        public static bool libPlayerPause( Int64 ply, Int32 paused )
        {
            ret false
        }

        @DllStaticImport( "sl_audio_lib", "sla_player_stop", "i64->bool" )
        public static bool libPlayerStop( Int64 ply )
        {
            ret false
        }

        @DllStaticImport( "sl_audio_lib", "sla_player_position", "i64->i64" )
        public static Int64 libPlayerPosition( Int64 ply )
        {
            ret 0
        }

        @DllStaticImport( "sl_audio_lib", "sla_player_volume", "i64,i32->bool" )
        public static bool libPlayerVolume( Int64 ply, Int32 vol0100 )
        {
            ret false
        }

        @DllStaticImport( "sl_audio_lib", "sla_player_buffered", "i64->i64" )
        public static Int64 libPlayerBuffered( Int64 ply )
        {
            ret 0
        }

        @DllStaticImport( "sl_audio_lib", "sla_player_free", "i64->bool" )
        public static bool libPlayerFree( Int64 ply )
        {
            ret false
        }

        # ═══════════════════════════════════════════════════
        # 2) 格式映射：SLA_FMT_* <-> EAudioFormat / ESampleFormat
        #    （值不恒等：EAudioFormat 是粗粒度容器枚举，SLA_FMT 是
        #     C 侧源格式 id；映射按“载荷编解码”归并，细节看 srcFormatId）
        # ═══════════════════════════════════════════════════

        # SLA_FMT_* -> EAudioFormat（按载荷归并；mp4 家族按内部编码归类）
        public static EAudioFormat srcIdToFormat( Int32 srcId )
        {
            if srcId == 1
            {
                ret EAudioFormat.Wav
            }
            if srcId == 2 || srcId == 3 || srcId == 4
            {
                ret EAudioFormat.Wav
            }
            if srcId == 5 || srcId == 8
            {
                ret EAudioFormat.Mp3
            }
            if srcId == 6 || srcId == 9 || srcId == 10
            {
                ret EAudioFormat.Aac
            }
            if srcId == 7
            {
                ret EAudioFormat.Wav
            }
            ret EAudioFormat.Unknown
        }

        # ESampleFormat -> fmt_hint（裸 PCM 流必须显式指定位深）
        public static Int32 sampleFormatToHint( ESampleFormat fmt )
        {
            if fmt == ESampleFormat.S16
            {
                ret AudioFfi.HINT_PCM_S16
            }
            if fmt == ESampleFormat.U8
            {
                ret AudioFfi.HINT_PCM_U8
            }
            if fmt == ESampleFormat.F32
            {
                ret AudioFfi.HINT_PCM_F32
            }
            ret AudioFfi.HINT_AUTO
        }

        # bits / srcId -> ESampleFormat（probe 块 [3] bitsPerSample）
        public static ESampleFormat bitsToSampleFormat( Int32 bits, Int32 srcId )
        {
            if srcId == 4
            {
                ret ESampleFormat.F32
            }
            if bits == 8
            {
                ret ESampleFormat.U8
            }
            if bits == 16
            {
                ret ESampleFormat.S16
            }
            if bits == 24
            {
                ret ESampleFormat.S24
            }
            if bits == 32
            {
                ret ESampleFormat.S32
            }
            ret ESampleFormat.S16
        }

        # ═══════════════════════════════════════════════════
        # 内部搬运辅助（模块内）
        # ═══════════════════════════════════════════════════

        # Array<UInt8> -> 新分配原生块（count 字节，逐字节 writeI8）
        static Int64 _copyIn( Array<UInt8> bytes, Int32 count )
        {
            if bytes == null || count <= 0 || count > bytes.length
            {
                ret 0
            }
            if count > AudioFfi.MAX_INLINE_BYTES
            {
                ret 0
            }
            Int64 ptr = Memory.alloc( count )
            if ptr == 0
            {
                ret 0
            }
            Int32 i = 0
            while i < count
            {
                Memory.writeI8( ptr, i, SystemConvertInt32( bytes[ i ] ) )
                i = i + 1
            }
            ret ptr
        }

        # 原生块 -> 新 Array<UInt8>（count 字节，逐字节 readUInt8）
        static Array<UInt8> _copyOut( Int64 ptr, Int32 count )
        {
            if ptr == 0 || count <= 0
            {
                ret null
            }
            Array<UInt8> result = Array<UInt8>( count )
            Int32 i = 0
            while i < count
            {
                result[ i ] = SystemConvertUInt8( Memory.readUInt8( ptr, i ) )
                i = i + 1
            }
            ret result
        }

        # probe 输出块（24 字节）-> AudioInfo
        static AudioInfo _infoFromProbe( Int64 outPtr, Int64 byteSize )
        {
            AudioInfo info = AudioInfo()
            if outPtr == 0
            {
                ret info
            }
            Int32 srcId = Memory.readInt32( outPtr, 0 )
            info.srcFormatId = srcId
            info.format = AudioFfi.srcIdToFormat( srcId )
            info.sampleRate = Memory.readInt32( outPtr, 1 * 4 )
            info.channels = Memory.readInt32( outPtr, 2 * 4 )
            info.bitDepth = Memory.readInt32( outPtr, 3 * 4 )
            info.sampleFormat = AudioFfi.bitsToSampleFormat( info.bitDepth, srcId )
            info.frameCount = Memory.readInt32( outPtr, 4 * 4 )
            if info.sampleRate > 0
            {
                info.duration = ( 1.0f * info.frameCount ) / info.sampleRate
            }
            info.byteSize = byteSize
            if info.format == EAudioFormat.Wav || info.format == EAudioFormat.Aac
            {
                info.bitrateMode = EBitrateMode.CBR
            }
            ret info
        }

        # ═══════════════════════════════════════════════════
        # 3) 便利层
        # ═══════════════════════════════════════════════════

        # ── 文件路径（零搬运直通 C 层，推荐入口）────────────

        # 探测文件头；失败返回空 AudioInfo（sampleRate == 0 可判）
        public static AudioInfo probeFile( string path )
        {
            if !AudioFfi.ensureReady()
            {
                ret AudioInfo()
            }
            if path == null || path == ""
            {
                ret AudioInfo()
            }
            Int64 probeOut = Memory.alloc( AudioFfi.PROBE_OUT_BYTES )
            if probeOut == 0
            {
                ret AudioInfo()
            }
            AudioInfo info = AudioInfo()
            if AudioFfi.libProbeFile( path, probeOut )
            {
                info = AudioFfi._infoFromProbe( probeOut, 0 )
            }
            Memory.free( probeOut )
            ret info
        }

        # ── 内存 bytes（逐字节搬运，<= MAX_INLINE_BYTES）────

        # 探测内存数据；失败返回空 AudioInfo
        public static AudioInfo probeMem( Array<UInt8> bytes )
        {
            if !AudioFfi.ensureReady()
            {
                ret AudioInfo()
            }
            if bytes == null || bytes.length < 12
            {
                ret AudioInfo()
            }
            Int64 src = AudioFfi._copyIn( bytes, bytes.length )
            if src == 0
            {
                ret AudioInfo()
            }
            Int64 probeOut = Memory.alloc( AudioFfi.PROBE_OUT_BYTES )
            AudioInfo info = AudioInfo()
            if probeOut != 0
            {
                if AudioFfi.libProbeMem( src, bytes.length, probeOut )
                {
                    info = AudioFfi._infoFromProbe( probeOut, bytes.length )
                }
                Memory.free( probeOut )
            }
            Memory.free( src )
            ret info
        }
    }
}
