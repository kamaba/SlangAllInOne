# =========================================================================
# SLangCuda —— CUDA GPU 计算库（NVIDIA 驱动 API 风味，零 Toolkit 依赖）
#
# 用法（对照 Python numba / PyCUDA 的心智模型）：
#
#   SLang.Cuda.initialize()                       # cuInit，幂等
#   SLang.CudaDevice dev = SLang.Cuda.device( 0 ) # 查询设备
#   dev.makeCurrent()                             # 绑定主上下文
#
#   SLang.CudaBuffer a = SLang.CudaBuffer.alloc( 1024 * 4 )
#   Int64 host = Memory.allocArray( 1024, "f32" ) # 主机侧原生块
#   Memory.writeF32( host, 0, 1.5 )
#   a.upload( host, 1024 * 4 )                    # H2D
#   ...
#   a.download( host, 1024 * 4 )                  # D2H
#   a.free()
#
#   SLang.CudaKernel k = SLang.CudaKernel.fromPtx( ptx, "vec_add" )
#   SLang.CudaKernelArgs args = SLang.CudaKernelArgs( 4 )
#   args.addPtr( a.devicePointer() )
#   ...
#   k.launch1D( 1024, 256, stream, args )         # GPU 内核
#
# 底层链路：
#   Cuda.sl ──@DllStaticImport(CallFFIStatic 77)──> sl_cuda_lib.dll
#             ──运行期 LoadLibrary──────────> nvcuda.dll（NVIDIA 驱动，
#                                               CUDA 驱动 API：cu*）
# sl_cuda_lib.dll 把 CUcontext / CUstream / CUmodule / CUfunction 收敛为
# Int64 句柄，CUdeviceptr 以 Int64 位模式承载；主机大块数据不走 FFI
# 传值，而是先经 Core 的 Memory.alloc 组原生块，再整块 memcpy。
#
# 错误处理以返回值表达（null / false / 0），原因经 Cuda.lastError() /
# Cuda.errorString() 取得（粘性：每次原生入口调用先清零）。
#
# 注意：所有类型必须是 namespace 下的顶级类型（不能嵌套在类内）。
# =========================================================================

namespace SLang
{
    # ===================================================================
    # Cuda —— 入口类 + 低层绑定
    #
    # lib* 系列是 sl_cuda_lib.dll 的直接映射（函数体 = DLL 不可用时的
    # 兜底返回值），通常不必直接使用；initialize() / device() 等门面
    # 供业务使用。含 ptr 形参的绑定必须手写 sig（FFI 短名）。
    # ===================================================================
    public class Cuda
    {
        # ── 设备属性常量（CUdevice_attribute，与 cuda.h 逐值一致）──

        public static Int32 ATTR_MAX_THREADS_PER_BLOCK = 1
        public static Int32 ATTR_MAX_SHARED_PER_BLOCK = 8
        public static Int32 ATTR_WARP_SIZE = 10
        public static Int32 ATTR_MAX_REGISTERS_PER_BLOCK = 12
        public static Int32 ATTR_CLOCK_RATE_KHZ = 13
        public static Int32 ATTR_SM_COUNT = 16
        public static Int32 ATTR_MEM_CLOCK_RATE_KHZ = 36
        public static Int32 ATTR_L2_CACHE_SIZE = 38
        public static Int32 ATTR_CC_MAJOR = 75
        public static Int32 ATTR_CC_MINOR = 76
        public static Int32 ATTR_GLOBAL_MEM_BUS_WIDTH = 90

        # ── 事件标志（cuEventCreate flags）──

        public static Int32 EVENT_DEFAULT = 0
        public static Int32 EVENT_BLOCKING_SYNC = 1
        # 计时是默认行为（flags=0）；0x2 是 CU_EVENT_DISABLE_TIMING，
        # 置位后事件传给 elapsedMs 会报 400（invalid resource handle）。

        # ── 低层：错误 / 版本 ────────────────────────────────────

        @DllStaticImport( "sl_cuda_lib", "slc_last_error", "->i32" )
        public static Int32 libLastError()
        {
            ret 0
        }

        @DllStaticImport( "sl_cuda_lib", "slc_error_string", "i32->utf8" )
        public static string libErrorString( Int32 err )
        {
            ret "sl_cuda_lib not available"
        }

        @DllStaticImport( "sl_cuda_lib", "slc_init", "i32->bool" )
        public static bool libInit( Int32 flags )
        {
            ret false
        }

        @DllStaticImport( "sl_cuda_lib", "slc_driver_version", "->i32" )
        public static Int32 libDriverVersion()
        {
            ret 0
        }

        # ── 低层：设备 ────────────────────────────────────────────

        @DllStaticImport( "sl_cuda_lib", "slc_device_count", "->i32" )
        public static Int32 libDeviceCount()
        {
            ret 0
        }

        @DllStaticImport( "sl_cuda_lib", "slc_device_name", "i32->utf8" )
        public static string libDeviceName( Int32 dev )
        {
            ret ""
        }

        @DllStaticImport( "sl_cuda_lib", "slc_device_total_mem", "i32->i64" )
        public static Int64 libDeviceTotalMem( Int32 dev )
        {
            ret 0
        }

        @DllStaticImport( "sl_cuda_lib", "slc_device_attr", "i32,i32->i32" )
        public static Int32 libDeviceAttr( Int32 dev, Int32 attr )
        {
            ret -1
        }

        @DllStaticImport( "sl_cuda_lib", "slc_device_set", "i32->bool" )
        public static bool libDeviceSet( Int32 dev )
        {
            ret false
        }

        @DllStaticImport( "sl_cuda_lib", "slc_device_get", "->i32" )
        public static Int32 libDeviceGet()
        {
            ret -1
        }

        @DllStaticImport( "sl_cuda_lib", "slc_ctx_sync", "->bool" )
        public static bool libCtxSync()
        {
            ret false
        }

        # ── 低层：设备内存 ────────────────────────────────────────

        @DllStaticImport( "sl_cuda_lib", "slc_mem_alloc", "i64->i64" )
        public static Int64 libMemAlloc( Int64 bytes )
        {
            ret 0
        }

        @DllStaticImport( "sl_cuda_lib", "slc_mem_alloc_managed", "i64,i32->i64" )
        public static Int64 libMemAllocManaged( Int64 bytes, Int32 flags )
        {
            ret 0
        }

        @DllStaticImport( "sl_cuda_lib", "slc_mem_free", "i64->bool" )
        public static bool libMemFree( Int64 ptr )
        {
            ret false
        }

        @DllStaticImport( "sl_cuda_lib", "slc_memset8", "i64,i32,i64->bool" )
        public static bool libMemset8( Int64 ptr, Int32 value, Int64 bytes )
        {
            ret false
        }

        @DllStaticImport( "sl_cuda_lib", "slc_memcpy_h2d", "i64,ptr,i64->bool" )
        public static bool libMemcpyH2D( Int64 dst, Int64 srcPtr, Int64 bytes )
        {
            ret false
        }

        @DllStaticImport( "sl_cuda_lib", "slc_memcpy_d2h", "ptr,i64,i64->bool" )
        public static bool libMemcpyD2H( Int64 dstPtr, Int64 src, Int64 bytes )
        {
            ret false
        }

        @DllStaticImport( "sl_cuda_lib", "slc_memcpy_d2d", "i64,i64,i64->bool" )
        public static bool libMemcpyD2D( Int64 dst, Int64 src, Int64 bytes )
        {
            ret false
        }

        @DllStaticImport( "sl_cuda_lib", "slc_memcpy_h2d_async", "i64,ptr,i64,i64->bool" )
        public static bool libMemcpyH2DAsync( Int64 dst, Int64 srcPtr, Int64 bytes, Int64 stream )
        {
            ret false
        }

        @DllStaticImport( "sl_cuda_lib", "slc_memcpy_d2h_async", "ptr,i64,i64,i64->bool" )
        public static bool libMemcpyD2HAsync( Int64 dstPtr, Int64 src, Int64 bytes, Int64 stream )
        {
            ret false
        }

        @DllStaticImport( "sl_cuda_lib", "slc_mem_info", "ptr,ptr->bool" )
        public static bool libMemInfo( Int64 freePtr, Int64 totalPtr )
        {
            ret false
        }

        # ── 低层：流 ──────────────────────────────────────────────

        @DllStaticImport( "sl_cuda_lib", "slc_stream_create", "i32->i64" )
        public static Int64 libStreamCreate( Int32 flags )
        {
            ret 0
        }

        @DllStaticImport( "sl_cuda_lib", "slc_stream_destroy", "i64->bool" )
        public static bool libStreamDestroy( Int64 stream )
        {
            ret false
        }

        @DllStaticImport( "sl_cuda_lib", "slc_stream_sync", "i64->bool" )
        public static bool libStreamSync( Int64 stream )
        {
            ret false
        }

        # ── 低层：事件 ────────────────────────────────────────────

        @DllStaticImport( "sl_cuda_lib", "slc_event_create", "i32->i64" )
        public static Int64 libEventCreate( Int32 flags )
        {
            ret 0
        }

        @DllStaticImport( "sl_cuda_lib", "slc_event_destroy", "i64->bool" )
        public static bool libEventDestroy( Int64 event )
        {
            ret false
        }

        @DllStaticImport( "sl_cuda_lib", "slc_event_record", "i64,i64->bool" )
        public static bool libEventRecord( Int64 event, Int64 stream )
        {
            ret false
        }

        @DllStaticImport( "sl_cuda_lib", "slc_event_sync", "i64->bool" )
        public static bool libEventSync( Int64 event )
        {
            ret false
        }

        @DllStaticImport( "sl_cuda_lib", "slc_event_elapsed_ms", "i64,i64->f64" )
        public static Float64 libEventElapsedMs( Int64 start, Int64 end )
        {
            ret -1.0
        }

        # ── 低层：模块 / 内核 ────────────────────────────────────

        @DllStaticImport( "sl_cuda_lib", "slc_module_load_data", "utf8->i64" )
        public static Int64 libModuleLoadData( string image )
        {
            ret 0
        }

        @DllStaticImport( "sl_cuda_lib", "slc_module_unload", "i64->bool" )
        public static bool libModuleUnload( Int64 module )
        {
            ret false
        }

        @DllStaticImport( "sl_cuda_lib", "slc_module_get_function", "i64,utf8->i64" )
        public static Int64 libModuleGetFunction( Int64 module, string name )
        {
            ret 0
        }

        @DllStaticImport( "sl_cuda_lib", "slc_kernel_launch", "i64,ptr,ptr->bool" )
        public static bool libKernelLaunch( Int64 func, Int64 configPtr, Int64 paramsPtr )
        {
            ret false
        }

        # ── 门面：初始化 / 版本 ──────────────────────────────────

        # initialize() —— cuInit(flags=0)，幂等，程序入口调用一次
        public static bool initialize()
        {
            ret Cuda.libInit( 0 )
        }

        # 驱动版本号原值（如 12080）
        public static Int32 driverVersion()
        {
            ret Cuda.libDriverVersion()
        }

        # 驱动版本文本（"12.8" 形态；不可用时 "unknown"）
        public static string driverVersionText()
        {
            Int32 v = Cuda.libDriverVersion()
            if v <= 0
            {
                ret "unknown"
            }
            Int32 major = v / 1000
            Int32 sub = ( v - major * 1000 ) / 10
            ret SystemConvertString( major ) + "." + SystemConvertString( sub )
        }

        # ── 门面：设备 ────────────────────────────────────────────

        public static Int32 deviceCount()
        {
            ret Cuda.libDeviceCount()
        }

        # device(ordinal) —— 查询并缓存设备信息；失败返回 null
        public static CudaDevice device( Int32 ordinal )
        {
            Int32 n = Cuda.libDeviceCount()
            if ordinal < 0 || ordinal >= n
            {
                ret null
            }
            ret CudaDevice( ordinal )
        }

        # 默认设备（0 号）；无卡返回 null
        public static CudaDevice defaultDevice()
        {
            if Cuda.libDeviceCount() <= 0
            {
                ret null
            }
            ret CudaDevice( 0 )
        }

        # setDevice(ordinal) —— 切换默认设备并绑定其主上下文
        public static bool setDevice( Int32 ordinal )
        {
            ret Cuda.libDeviceSet( ordinal )
        }

        # 当前上下文所在设备序号（-1 = 无上下文）
        public static Int32 currentDevice()
        {
            ret Cuda.libDeviceGet()
        }

        # 阻塞等待当前设备全部 GPU 工作完成
        public static bool synchronize()
        {
            ret Cuda.libCtxSync()
        }

        # ── 门面：显存余量 ────────────────────────────────────────

        public static Int64 memFreeBytes()
        {
            Int64 fr = Memory.alloc( 8 )
            Int64 tot = Memory.alloc( 8 )
            Int64 v = 0
            if fr != 0 && tot != 0
            {
                if Cuda.libMemInfo( fr, tot )
                {
                    v = Memory.readInt64( fr, 0 )
                }
            }
            if fr != 0
            {
                Memory.free( fr )
            }
            if tot != 0
            {
                Memory.free( tot )
            }
            ret v
        }

        public static Int64 memTotalBytes()
        {
            Int64 fr = Memory.alloc( 8 )
            Int64 tot = Memory.alloc( 8 )
            Int64 v = 0
            if fr != 0 && tot != 0
            {
                if Cuda.libMemInfo( fr, tot )
                {
                    v = Memory.readInt64( tot, 0 )
                }
            }
            if fr != 0
            {
                Memory.free( fr )
            }
            if tot != 0
            {
                Memory.free( tot )
            }
            ret v
        }

        # ── 门面：诊断 ────────────────────────────────────────────

        # 最近一次原生调用的错误码（0 = 无错，粘性）
        public static Int32 lastError()
        {
            ret Cuda.libLastError()
        }

        # 最近一次错误的文本
        public static string errorString()
        {
            ret Cuda.libErrorString( 0 )
        }

        # 指定错误码的文本
        public static string errorStringOf( Int32 err )
        {
            ret Cuda.libErrorString( err )
        }
    }

    # ===================================================================
    # CudaDevice —— 设备信息（构造时一次性查询缓存）
    # ===================================================================
    public class CudaDevice
    {
        public Int32 ordinal = 0
        public string name = ""
        public Int64 totalMemory = 0
        public Int32 ccMajor = 0
        public Int32 ccMinor = 0
        public Int32 smCount = 0
        public Int32 clockRateKHz = 0
        public Int32 memoryClockRateKHz = 0
        public Int32 warpSize = 0
        public Int32 maxThreadsPerBlock = 0
        public Int32 maxSharedPerBlock = 0
        public Int32 l2CacheSize = 0
        public Int32 memoryBusWidth = 0

        _init_( Int32 ordinal )
        {
            this.ordinal = ordinal
            this.name = Cuda.libDeviceName( ordinal )
            this.totalMemory = Cuda.libDeviceTotalMem( ordinal )
            this.ccMajor = Cuda.libDeviceAttr( ordinal, Cuda.ATTR_CC_MAJOR )
            this.ccMinor = Cuda.libDeviceAttr( ordinal, Cuda.ATTR_CC_MINOR )
            this.smCount = Cuda.libDeviceAttr( ordinal, Cuda.ATTR_SM_COUNT )
            this.clockRateKHz = Cuda.libDeviceAttr( ordinal, Cuda.ATTR_CLOCK_RATE_KHZ )
            this.memoryClockRateKHz = Cuda.libDeviceAttr( ordinal, Cuda.ATTR_MEM_CLOCK_RATE_KHZ )
            this.warpSize = Cuda.libDeviceAttr( ordinal, Cuda.ATTR_WARP_SIZE )
            this.maxThreadsPerBlock = Cuda.libDeviceAttr( ordinal, Cuda.ATTR_MAX_THREADS_PER_BLOCK )
            this.maxSharedPerBlock = Cuda.libDeviceAttr( ordinal, Cuda.ATTR_MAX_SHARED_PER_BLOCK )
            this.l2CacheSize = Cuda.libDeviceAttr( ordinal, Cuda.ATTR_L2_CACHE_SIZE )
            this.memoryBusWidth = Cuda.libDeviceAttr( ordinal, Cuda.ATTR_GLOBAL_MEM_BUS_WIDTH )
        }

        # 计算能力文本（"7.5" 形态）
        public string computeCapability()
        {
            ret SystemConvertString( this.ccMajor ) + "." + SystemConvertString( this.ccMinor )
        }

        # 任意设备属性（CUdevice_attribute 值直传）
        public Int32 attr( Int32 attrId )
        {
            ret Cuda.libDeviceAttr( this.ordinal, attrId )
        }

        # 绑定本设备主上下文为当前上下文
        public bool makeCurrent()
        {
            ret Cuda.libDeviceSet( this.ordinal )
        }

        # 等待本设备全部 GPU 工作完成
        public bool synchronize()
        {
            this.makeCurrent()
            ret Cuda.libCtxSync()
        }

        override string toString()
        {
            string s = "CudaDevice(" + SystemConvertString( this.ordinal ) + ", " + this.name
            s = s + ", cc " + this.computeCapability()
            s = s + ", " + SystemConvertString( this.smCount ) + " SMs"
            s = s + ", " + this.totalMemory.toString() + " bytes)"
            ret s
        }
    }

    # ===================================================================
    # CudaBuffer —— 设备内存块
    #
    # 主机侧数据经 Core 的 Memory.alloc / writeF32 系列组装原生块后，
    # 由 upload / download 整块搬运（H2D / D2H）。
    # ===================================================================
    public class CudaBuffer
    {
        Int64 _ptr = 0
        Int64 _bytes = 0

        _init_( Int64 ptr, Int64 bytes )
        {
            this._ptr = ptr
            this._bytes = bytes
        }

        # 设备指针（CUdeviceptr，可作内核参数）
        get Int64 devicePointer()
        {
            ret this._ptr
        }

        get Int64 sizeBytes()
        {
            ret this._bytes
        }

        get bool isValid()
        {
            ret this._ptr != 0
        }

        # ── 分配 / 释放 ──────────────────────────────────────────

        # alloc(bytes) —— 设备内存；失败返回 null
        public static CudaBuffer alloc( Int64 bytes )
        {
            Int64 p = Cuda.libMemAlloc( bytes )
            if p == 0
            {
                ret null
            }
            ret CudaBuffer( p, bytes )
        }

        # allocManaged(bytes) —— 统一内存（flags=0，CU_MEM_ATTACH_GLOBAL）
        public static CudaBuffer allocManaged( Int64 bytes )
        {
            Int64 p = Cuda.libMemAllocManaged( bytes, 0 )
            if p == 0
            {
                ret null
            }
            ret CudaBuffer( p, bytes )
        }

        public void free()
        {
            if this._ptr != 0
            {
                Cuda.libMemFree( this._ptr )
                this._ptr = 0
            }
        }

        # ── 搬运 ──────────────────────────────────────────────────

        # upload(srcPtr, bytes) —— 主机块 -> 设备（bytes 上限为块大小）
        public bool upload( Int64 srcPtr, Int64 bytes )
        {
            if this._ptr == 0 || bytes < 0 || bytes > this._bytes
            {
                ret false
            }
            ret Cuda.libMemcpyH2D( this._ptr, srcPtr, bytes )
        }

        # upload(srcPtr) —— 全量上传
        public bool upload( Int64 srcPtr )
        {
            ret this.upload( srcPtr, this._bytes )
        }

        # download(dstPtr, bytes) —— 设备 -> 主机块
        public bool download( Int64 dstPtr, Int64 bytes )
        {
            if this._ptr == 0 || bytes < 0 || bytes > this._bytes
            {
                ret false
            }
            ret Cuda.libMemcpyD2H( dstPtr, this._ptr, bytes )
        }

        # download(dstPtr) —— 全量下载
        public bool download( Int64 dstPtr )
        {
            ret this.download( dstPtr, this._bytes )
        }

        # 流式异步版（调用后需 stream.synchronize() 或事件等待）
        public bool uploadAsync( Int64 srcPtr, Int64 bytes, CudaStream stream )
        {
            if this._ptr == 0 || bytes < 0 || bytes > this._bytes
            {
                ret false
            }
            Int64 sh = 0
            if stream != null
            {
                sh = stream.handle
            }
            ret Cuda.libMemcpyH2DAsync( this._ptr, srcPtr, bytes, sh )
        }

        public bool downloadAsync( Int64 dstPtr, Int64 bytes, CudaStream stream )
        {
            if this._ptr == 0 || bytes < 0 || bytes > this._bytes
            {
                ret false
            }
            Int64 sh = 0
            if stream != null
            {
                sh = stream.handle
            }
            ret Cuda.libMemcpyD2HAsync( dstPtr, this._ptr, bytes, sh )
        }

        # ── 填充 ──────────────────────────────────────────────────

        # memset8(value) —— 按字节填充整块
        public bool memset8( Int32 value )
        {
            if this._ptr == 0
            {
                ret false
            }
            ret Cuda.libMemset8( this._ptr, value, this._bytes )
        }

        # memset8(value, bytes) —— 只填前 bytes 字节
        public bool memset8( Int32 value, Int64 bytes )
        {
            if this._ptr == 0 || bytes < 0 || bytes > this._bytes
            {
                ret false
            }
            ret Cuda.libMemset8( this._ptr, value, bytes )
        }

        override string toString()
        {
            ret "CudaBuffer(0x" + this._ptr.toString() + ", " + this._bytes.toString() + " bytes)"
        }
    }

    # ===================================================================
    # CudaStream —— 异步流
    # ===================================================================
    public class CudaStream
    {
        Int64 _handle = 0

        _init_( Int64 handle )
        {
            this._handle = handle
        }

        get Int64 handle()
        {
            ret this._handle
        }

        get bool isValid()
        {
            ret this._handle != 0
        }

        # create() —— 创建非默认流；失败返回 null
        public static CudaStream create()
        {
            Int64 h = Cuda.libStreamCreate( 0 )
            if h == 0
            {
                ret null
            }
            ret CudaStream( h )
        }

        # 等待流上全部工作完成
        public bool synchronize()
        {
            ret Cuda.libStreamSync( this._handle )
        }

        public void destroy()
        {
            if this._handle != 0
            {
                Cuda.libStreamDestroy( this._handle )
                this._handle = 0
            }
        }
    }

    # ===================================================================
    # CudaEvent —— 事件（计时需用 createTiming）
    # ===================================================================
    public class CudaEvent
    {
        Int64 _handle = 0

        _init_( Int64 handle )
        {
            this._handle = handle
        }

        get Int64 handle()
        {
            ret this._handle
        }

        # create() —— 普通事件（flags=0）；失败返回 null
        public static CudaEvent create()
        {
            Int64 h = Cuda.libEventCreate( Cuda.EVENT_DEFAULT )
            if h == 0
            {
                ret null
            }
            ret CudaEvent( h )
        }

        # createTiming() —— 计时事件（计时为默认行为，flags=0；
        # elapsedMs 的前置条件：事件不能用 DISABLE_TIMING 创建）
        public static CudaEvent createTiming()
        {
            Int64 h = Cuda.libEventCreate( Cuda.EVENT_DEFAULT )
            if h == 0
            {
                ret null
            }
            ret CudaEvent( h )
        }

        # record(stream) —— 在流上记录事件（stream 传 null = 默认流）
        public bool record( CudaStream stream )
        {
            if this._handle == 0
            {
                ret false
            }
            Int64 sh = 0
            if stream != null
            {
                sh = stream.handle
            }
            ret Cuda.libEventRecord( this._handle, sh )
        }

        # 阻塞等待事件完成
        public bool synchronize()
        {
            ret Cuda.libEventSync( this._handle )
        }

        public void destroy()
        {
            if this._handle != 0
            {
                Cuda.libEventDestroy( this._handle )
                this._handle = 0
            }
        }

        # elapsedMs(start, end) —— 两个计时事件的间隔毫秒；失败 -1.0
        public static Float64 elapsedMs( CudaEvent start, CudaEvent end )
        {
            if start == null || end == null
            {
                ret -1.0
            }
            ret Cuda.libEventElapsedMs( start.handle, end.handle )
        }
    }

    # ===================================================================
    # CudaKernelArgs —— 内核参数组装器
    #
    # 布局：values 块每参 8 字节值槽（i32/f32 只写低 4 字节）；
    #       ptrs 块每参 8 字节，存对应值槽地址。
    # 驱动按内核签名读取各槽（宽度由签名决定），故槽宽统一 8 无碍。
    # ===================================================================
    public class CudaKernelArgs
    {
        Int64 _values = 0
        Int64 _ptrs = 0
        Int32 _capacity = 0
        Int32 _count = 0

        _init_( Int32 capacity )
        {
            if capacity < 1
            {
                capacity = 1
            }
            this._capacity = capacity
            this._values = Memory.alloc( capacity * 8 )
            this._ptrs = Memory.alloc( capacity * 8 )
        }

        get Int32 count()
        {
            ret this._count
        }

        # 参数指针数组基址（launch 时传给 Cuda.libKernelLaunch）
        get Int64 paramsBlock()
        {
            ret this._ptrs
        }

        # 复位（复用已分配块）
        public void clear()
        {
            this._count = 0
        }

        # ── 各类型参数（槽宽统一 8 字节）─────────────────────────

        # 设备指针 / 句柄（u64 位模式）
        public void addPtr( Int64 value )
        {
            this._addI64( value )
        }

        public void addI64( Int64 value )
        {
            this._addI64( value )
        }

        public void addI32( Int32 value )
        {
            if this._count >= this._capacity
            {
                ret
            }
            Int32 off = this._count * 8
            Memory.writeI32( this._values, off, value )
            Memory.writeI64( this._ptrs, off, this._values + off )
            this._count++
        }

        public void addF32( Float32 value )
        {
            if this._count >= this._capacity
            {
                ret
            }
            Int32 off = this._count * 8
            Memory.writeF32( this._values, off, value )
            Memory.writeI64( this._ptrs, off, this._values + off )
            this._count++
        }

        public void addF64( Float64 value )
        {
            if this._count >= this._capacity
            {
                ret
            }
            Int32 off = this._count * 8
            Memory.writeF64( this._values, off, value )
            Memory.writeI64( this._ptrs, off, this._values + off )
            this._count++
        }

        void _addI64( Int64 value )
        {
            if this._count >= this._capacity
            {
                ret
            }
            Int32 off = this._count * 8
            Memory.writeI64( this._values, off, value )
            Memory.writeI64( this._ptrs, off, this._values + off )
            this._count++
        }

        # 释放原生块（args 生命周期结束）
        public void free()
        {
            if this._values != 0
            {
                Memory.free( this._values )
                this._values = 0
            }
            if this._ptrs != 0
            {
                Memory.free( this._ptrs )
                this._ptrs = 0
            }
            this._count = 0
            this._capacity = 0
        }
    }

    # ===================================================================
    # CudaKernel —— PTX 模块内的内核（JIT 加载 + 启动）
    #
    # 启动描述块布局（40 字节，与 sl_cuda_lib.c slc_kernel_launch 对齐）：
    #   0/4/8 gridX/Y/Z (i32)   12/16/20 blockX/Y/Z (i32)
    #   24 sharedBytes (i32)    28 保留 (i32)   32 stream (i64)
    # ===================================================================
    public class CudaKernel
    {
        Int64 _module = 0
        Int64 _func = 0
        string _name = ""
        Int64 _cfg = 0

        _init_( Int64 moduleHandle, Int64 funcHandle, string name )
        {
            this._module = moduleHandle
            this._func = funcHandle
            this._name = name
            this._cfg = Memory.alloc( 40 )
        }

        get string name()
        {
            ret this._name
        }

        get Int64 functionHandle()
        {
            ret this._func
        }

        # fromPtx(ptx, entryName) —— 从 PTX 文本加载内核（驱动 JIT）；
        # 失败返回 null（原因见 Cuda.errorString()）
        public static CudaKernel fromPtx( string ptx, string entryName )
        {
            Int64 m = Cuda.libModuleLoadData( ptx )
            if m == 0
            {
                ret null
            }
            Int64 f = Cuda.libModuleGetFunction( m, entryName )
            if f == 0
            {
                Cuda.libModuleUnload( m )
                ret null
            }
            ret CudaKernel( m, f, entryName )
        }

        # launch(grid, block, sharedBytes, stream, args) —— 完整形式。
        # stream 传 null = 默认流；args 传 null = 无参内核。
        # （签名必须单行：SL 语句按行切分，跨行参数表会把续行当独立语句）
        public bool launch( Int32 gridX, Int32 gridY, Int32 gridZ, Int32 blockX, Int32 blockY, Int32 blockZ, Int32 sharedBytes, CudaStream stream, CudaKernelArgs args )
        {
            if this._func == 0 || this._cfg == 0
            {
                ret false
            }
            Memory.writeI32( this._cfg, 0, gridX )
            Memory.writeI32( this._cfg, 4, gridY )
            Memory.writeI32( this._cfg, 8, gridZ )
            Memory.writeI32( this._cfg, 12, blockX )
            Memory.writeI32( this._cfg, 16, blockY )
            Memory.writeI32( this._cfg, 20, blockZ )
            Memory.writeI32( this._cfg, 24, sharedBytes )
            Memory.writeI32( this._cfg, 28, 0 )
            Int64 sh = 0
            if stream != null
            {
                sh = stream.handle
            }
            Memory.writeI64( this._cfg, 32, sh )

            # params 是 SL 保留字，局部变量用 argsPtr 命名
            Int64 argsPtr = 0
            if args != null
            {
                argsPtr = args.paramsBlock
            }
            ret Cuda.libKernelLaunch( this._func, this._cfg, argsPtr )
        }

        # launch1D(total, blockSize, stream, args) —— 一维便捷形式
        # （grid = ceil(total / blockSize)）
        public bool launch1D( Int32 total, Int32 blockSize, CudaStream stream, CudaKernelArgs args )
        {
            if total <= 0 || blockSize <= 0
            {
                ret false
            }
            Int32 grid = ( total + blockSize - 1 ) / blockSize
            ret this.launch( grid, 1, 1, blockSize, 1, 1, 0, stream, args )
        }

        # 卸载模块并释放启动块（内核句柄随之失效）
        public void destroy()
        {
            if this._cfg != 0
            {
                Memory.free( this._cfg )
                this._cfg = 0
            }
            if this._module != 0
            {
                Cuda.libModuleUnload( this._module )
                this._module = 0
            }
            this._func = 0
        }
    }
}
