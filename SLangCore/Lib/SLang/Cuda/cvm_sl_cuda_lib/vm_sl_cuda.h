#ifndef VM_SL_CUDA_H
#define VM_SL_CUDA_H

/* ==========================================================================
 * vm_sl_cuda.h —— SLCuda 模块原生层导出声明（sl_cuda_lib.dll）
 * --------------------------------------------------------------------------
 * 本库是 NVIDIA CUDA **驱动 API**（nvcuda.dll，随显卡驱动安装于
 * System32，与 CUDA Toolkit 无关）的一层扁平 C ABI 包装：
 *
 *   - 量产机器只需装 NVIDIA 驱动即可使用（nvcuda.dll 由驱动提供）；
 *     构建期不依赖 CUDA Toolkit（无 cuda.h / cudart.lib），
 *     全部驱动符号在运行期 LoadLibrary("nvcuda.dll") + GetProcAddress
 *     解析，因此 sl_cuda_lib.dll 自包含、随模块分发无额外依赖。
 *   - 把 CUcontext / CUstream / CUevent / CUmodule / CUfunction 收敛为
 *     SL 侧可承载的 Int64 句柄（0 恒为无效），CUdeviceptr 直接用
 *     Int64（u64 位模式）承载，让 Cuda.sl 能通过
 *
 *     @DllStaticImport( "sl_cuda_lib", "slc_memcpy_h2d", "i64,ptr,i64->bool" )
 *     static bool libMemcpyH2D( Int64 dst, Int64 src, Int64 bytes ) { ret false }
 *
 *     走 opcode 77 静态绑定直调，无需任何 Adaptor / 委托转发。
 *   - 主机侧大块数据（tensor 等）不走 FFI 传值：SL 侧用 Core 的
 *     Memory.alloc / writeF32 系列先组好原生内存块，把块地址（ptr）
 *     交给 slc_memcpy_h2d / slc_memcpy_d2h 整块搬运。
 *
 * 导出命名约定：统一前缀 slc_（SimpleLanguage CUDA）。
 * 调用约定：x64 cdecl（Windows x64 唯一），与 cvm sl_ffi_call 的
 *          INT 类（含指针 / utf8）/ DBL 类分类调度对齐。
 *
 * 参数个数上限：6（SL_FFI_MAX_ARGS），所有导出函数均满足。
 *
 * 错误约定（与 SLangMysql 的 slm_* 对齐的 bool 语义）：
 *   - "成功与否"类导出（init / device_set / ctx_sync / memcpy 族 /
 *     mem_info / memset8 / mem_free / stream 族 / event 族 /
 *     module_unload / kernel_launch）：int32_t 1 = 成功，0 = 失败，
 *     失败原因写入粘性 last_error；
 *   - 返回句柄的函数：0 = 失败（原因经 slc_last_error /
 *     slc_error_string 取得）；
 *   - 查询类（driver_version / device_count / device_attr /
 *     device_get）：失败时 0 / -1；
 *   - 例外：slc_stream_create / slc_event_create 返回 0 可能是
 *     "默认流"（CU_STREAM_LEGACY 语义：传给 sync/record 均合法），
 *     失败与否以 slc_last_error() 是否被清零为准——每次调用入口都会
 *     先清粘性码，故调用后立刻查询即可分辨。
 *   - cuDevicePrimaryCtxRetain：注意 nvcuda.dll 只导出无 _v2 后缀的
 *     符号（与 MemAlloc 族不同），解析名不要带 _v2。
 *
 * 上下文约定：
 *   - cuInit 由 slc_init 显式完成（幂等，重复调用安全）；
 *   - 首个需要上下文的调用（alloc / memcpy / launch ...）会自动
 *     retain 当前默认设备（slc_device_set 可切换，初始 0 号）的
 *     primary context 并置为当前线程上下文——与 Runtime API 的
 *     隐式上下文行为对齐，v1 不做 release（进程退出由驱动回收）。
 *
 * 返回字符串内存约定：
 *   - const char* 返回值一律指向本库线程局部缓冲，调用方不得 free；
 *     SL 侧（VM）在返回瞬间即拷走内容，只需保证"返回那一刻有效"。
 * ========================================================================== */

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#if defined(_WIN32) && defined(_MSC_VER)
#  define SLC_API __declspec(dllexport)
#else
#  define SLC_API
#endif

/* ------------------------------------------------------------------ */
/* 本库合成错误码（负值；CUresult 原值恒 >= 0，互不冲突）              */
/* ------------------------------------------------------------------ */

#define SLC_E_DRIVER_MISSING  (-1)   /* nvcuda.dll 不存在 / 符号缺失 */
#define SLC_E_NOT_INITIALIZED (-2)   /* slc_init 尚未成功调用        */
#define SLC_E_BAD_HANDLE      (-3)   /* 句柄非法                     */
#define SLC_E_BAD_PARAM       (-4)   /* 参数非法（0 字节 / 越界等）  */
#define SLC_E_NO_DEVICE       (-5)   /* 无可用 CUDA 设备             */

/* ------------------------------------------------------------------ */
/* 错误 / 版本                                                         */
/* ------------------------------------------------------------------ */

/* 粘性最近错误码：0 = 无错。每次 slc_ 入口调用都会先清零再执行。 */
SLC_API int32_t     slc_last_error(void);
/* 错误码转文本；err == 0 时取 last_error。永不返回 NULL。 */
SLC_API const char* slc_error_string(int32_t err);

/* 初始化驱动（flags 恒传 0）。幂等：重复调用安全。 */
SLC_API int32_t     slc_init(int32_t flags);

/* 驱动版本号（如 12080 -> 12.8）；0 = 失败（未初始化 / 无驱动）。 */
SLC_API int32_t     slc_driver_version(void);

/* ------------------------------------------------------------------ */
/* 设备                                                                */
/* ------------------------------------------------------------------ */

/* 设备数量；0 = 无设备或未初始化（区分见 slc_last_error）。 */
SLC_API int32_t     slc_device_count(void);

/* 设备名（线程局部缓冲）；ordinal 非法返回空串。 */
SLC_API const char* slc_device_name(int32_t dev);

/* 设备全局显存字节数；0 = 失败。 */
SLC_API int64_t     slc_device_total_mem(int32_t dev);

/* 设备属性（CUdevice_attribute 值直传，见 Cuda.sl ATTR_* 常量表）。
   返回属性值（非负）；-1 = 失败。 */
SLC_API int32_t     slc_device_attr(int32_t dev, int32_t attr);

/* 切换默认设备并绑定其 primary context 为当前上下文。 */
SLC_API int32_t     slc_device_set(int32_t dev);

/* 当前上下文所在设备序号；-1 = 无上下文（未初始化 / 未绑定）。 */
SLC_API int32_t     slc_device_get(void);

/* 阻塞等待当前上下文全部 GPU 工作完成（cuCtxSynchronize）。 */
SLC_API int32_t     slc_ctx_sync(void);

/* ------------------------------------------------------------------ */
/* 设备内存                                                            */
/* ------------------------------------------------------------------ */

/* 分配设备内存，返回 CUdeviceptr；0 = 失败。 */
SLC_API int64_t     slc_mem_alloc(int64_t bytes);

/* 分配统一内存（managed，flags=0 即 CU_MEM_ATTACH_GLOBAL）；
   旧驱动不支持时失败并置 last_error。返回 0 = 失败。 */
SLC_API int64_t     slc_mem_alloc_managed(int64_t bytes, int32_t flags);

/* 释放设备内存（含 managed）。重复 free 由驱动返回错误码。 */
SLC_API int32_t     slc_mem_free(int64_t ptr);

/* 按字节填充设备内存（value 取低 8 位）。 */
SLC_API int32_t     slc_memset8(int64_t ptr, int32_t value, int64_t bytes);

/* 主机块 -> 设备（srcHost 为 SL 侧 Memory.alloc 块地址）。 */
SLC_API int32_t     slc_memcpy_h2d(int64_t dst, const void* srcHost, int64_t bytes);

/* 设备 -> 主机块（dstHost 为 SL 侧 Memory.alloc 块地址）。 */
SLC_API int32_t     slc_memcpy_d2h(void* dstHost, int64_t src, int64_t bytes);

/* 设备 -> 设备。 */
SLC_API int32_t     slc_memcpy_d2d(int64_t dst, int64_t src, int64_t bytes);

/* 流式异步版（stream 为 0 时等价同步版，走默认流）。 */
SLC_API int32_t     slc_memcpy_h2d_async(int64_t dst, const void* srcHost,
                                         int64_t bytes, int64_t stream);
SLC_API int32_t     slc_memcpy_d2h_async(void* dstHost, int64_t src,
                                         int64_t bytes, int64_t stream);

/* 显存余量查询：向 freeOut / totalOut 指向的两个 8 字节槽各写一个
   u64 字节数（SL 侧 Memory.alloc(8) x2 后 readInt64 读回）。 */
SLC_API int32_t     slc_mem_info(void* freeOut, void* totalOut);

/* ------------------------------------------------------------------ */
/* 流                                                                  */
/* ------------------------------------------------------------------ */

/* 创建流，返回句柄（0 亦可能是默认流，见文件头"错误约定"）。 */
SLC_API int64_t     slc_stream_create(int32_t flags);

/* 销毁流。 */
SLC_API int32_t     slc_stream_destroy(int64_t stream);

/* 阻塞等待流上全部工作完成。 */
SLC_API int32_t     slc_stream_sync(int64_t stream);

/* ------------------------------------------------------------------ */
/* 事件（计时需用 flags=2 创建，见 CU_EVENT_TIMING）                   */
/* ------------------------------------------------------------------ */

SLC_API int64_t     slc_event_create(int32_t flags);
SLC_API int32_t     slc_event_destroy(int64_t event);
/* stream 传 0 = 默认流。 */
SLC_API int32_t     slc_event_record(int64_t event, int64_t stream);
SLC_API int32_t     slc_event_sync(int64_t event);
/* 两计时事件间隔毫秒；失败返回 -1.0（原因见 last_error）。 */
SLC_API double      slc_event_elapsed_ms(int64_t start, int64_t end);

/* ------------------------------------------------------------------ */
/* 模块 / 内核（PTX JIT 路径）                                         */
/* ------------------------------------------------------------------ */

/* 从 PTX 文本（NUL 结尾 utf8）加载模块（驱动 JIT 编译），返回句柄；
   0 = 失败。image 生命周期仅调用期有效（驱动即时拷贝）。 */
SLC_API int64_t     slc_module_load_data(const char* image);

/* 卸载模块（其 CUfunction 句柄随之失效）。 */
SLC_API int32_t     slc_module_unload(int64_t module);

/* 取模块内 .entry 内核句柄；0 = 未找到。 */
SLC_API int64_t     slc_module_get_function(int64_t module, const char* name);

/* 启动内核。config 指向 40 字节启动描述块（SL 侧 Memory.alloc(40) 组装）：
     偏移  0  i32 gridX      偏移 12  i32 blockX
     偏移  4  i32 gridY      偏移 16  i32 blockY
     偏移  8  i32 gridZ      偏移 20  i32 blockZ
     偏移 24  i32 sharedBytes 偏移 28  i32 保留（0）
     偏移 32  i64 stream 句柄（0 = 默认流）
   params 指向内核参数指针数组（每项 8 字节，指向各参数值槽；
   参数个数 / 各槽宽度由内核签名决定，驱动按签名读取，
   本库不感知）。extra 恒传 NULL（不走 value 槽形态）。 */
SLC_API int32_t     slc_kernel_launch(int64_t func, const void* config,
                                      const void* params);

#ifdef __cplusplus
}
#endif

#endif /* VM_SL_CUDA_H */
