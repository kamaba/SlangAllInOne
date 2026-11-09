/*
 * sl_cuda_lib.c —— SLCuda 模块原生实现（产物 sl_cuda_lib.dll）
 * ==========================================================================
 * 位于 NVIDIA CUDA 驱动 API（nvcuda.dll，随显卡驱动安装）之上的一层
 * **扁平 C ABI 包装**，供 Cuda.sl 通过 @DllStaticImport 静态绑定直调
 * （opcode 77）。
 *
 * 设计取舍：
 *   1) **零 Toolkit 依赖**：构建期只需要 MSVC（本工程无任何外部
 *      include / lib），全部驱动符号运行期从 nvcuda.dll 解析。
 *      选驱动 API 而非运行时 API（cudart）正是为此——cudart.dll
 *      属于 CUDA Toolkit，量产部署还得额外分发；nvcuda.dll 则是
 *      装了 N 卡驱动就有。
 *   2) **句柄化**：CUcontext / CUstream / CUevent / CUmodule /
 *      CUfunction 一律换成 Int64 句柄（x64 下指针与 u64 等宽），
 *      CUdeviceptr 本身就是 u64，直接以 Int64 位模式承载。
 *   3) **粘性错误码 + 符号级回退**：每个入口先清 last_error；
 *      失败路径分三层——nvcuda.dll 缺失（SLC_E_DRIVER_MISSING）/
 *      cuInit 未跑（SLC_E_NOT_INITIALIZED）/ CUresult 原值透传。
 *      错误文本优先用驱动自带的 cuGetErrorString（老驱动缺失该
 *      符号时回退本库内置码表）。
 *   4) **隐式上下文**：首个需要上下文的调用自动 retain 默认设备的
 *      primary context 并置为当前（与 Runtime API 行为对齐）；
 *      slc_device_set 可换设备。v1 retain 后不 release——进程退出
 *      由驱动统一回收，注释见 slc_bind_ctx。
 *
 * 线程安全：符号解析 / 主上下文缓存用临界区保护；返回字符串用
 *          线程局部缓冲。CUcontext 的"当前"语义是线程级的，多线程
 *          并发调用时各线程首次会各自触发一次 ensure_ctx（幂等）。
 */

#include "vm_sl_cuda.h"

#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#include <stdlib.h>
#include <string.h>
#include <stdio.h>

/* ========================================================================
 * CUDA 驱动 API 最小类型面（等价 cuda.h 的公开子集，手写声明）
 * ======================================================================== */

typedef int                 CUresult;
typedef int                 CUdevice;
typedef unsigned long long  CUdeviceptr;
struct CUctx_st;    typedef struct CUctx_st*    CUcontext;
struct CUstream_st; typedef struct CUstream_st* CUstream;
struct CUevent_st;  typedef struct CUevent_st*  CUevent;
struct CUmod_st;    typedef struct CUmod_st*    CUmodule;
struct CUfunc_st;   typedef struct CUfunc_st*   CUfunction;

typedef CUresult (WINAPI *PFN_cuInit)(unsigned int);
typedef CUresult (WINAPI *PFN_cuDriverGetVersion)(int*);
typedef CUresult (WINAPI *PFN_cuGetErrorString)(CUresult, const char**);
typedef CUresult (WINAPI *PFN_cuDeviceGetCount)(int*);
typedef CUresult (WINAPI *PFN_cuDeviceGet)(CUdevice*, int);
typedef CUresult (WINAPI *PFN_cuDeviceGetName)(char*, int, CUdevice);
typedef CUresult (WINAPI *PFN_cuDeviceTotalMem_v2)(size_t*, CUdevice);
typedef CUresult (WINAPI *PFN_cuDeviceGetAttribute)(int*, int, CUdevice);
typedef CUresult (WINAPI *PFN_cuDevicePrimaryCtxRetain)(CUcontext*, CUdevice);
typedef CUresult (WINAPI *PFN_cuCtxSetCurrent)(CUcontext);
typedef CUresult (WINAPI *PFN_cuCtxGetCurrent)(CUcontext*);
typedef CUresult (WINAPI *PFN_cuCtxGetDevice)(CUdevice*);
typedef CUresult (WINAPI *PFN_cuCtxSynchronize)(void);
typedef CUresult (WINAPI *PFN_cuMemAlloc_v2)(CUdeviceptr*, size_t);
typedef CUresult (WINAPI *PFN_cuMemAllocManaged)(CUdeviceptr*, size_t, unsigned int);
typedef CUresult (WINAPI *PFN_cuMemFree_v2)(CUdeviceptr);
typedef CUresult (WINAPI *PFN_cuMemsetD8_v2)(CUdeviceptr, unsigned char, size_t);
typedef CUresult (WINAPI *PFN_cuMemcpyHtoD_v2)(CUdeviceptr, const void*, size_t);
typedef CUresult (WINAPI *PFN_cuMemcpyDtoH_v2)(void*, CUdeviceptr, size_t);
typedef CUresult (WINAPI *PFN_cuMemcpyDtoD_v2)(CUdeviceptr, CUdeviceptr, size_t);
typedef CUresult (WINAPI *PFN_cuMemcpyHtoDAsync_v2)(CUdeviceptr, const void*, size_t, CUstream);
typedef CUresult (WINAPI *PFN_cuMemcpyDtoHAsync_v2)(void*, CUdeviceptr, size_t, CUstream);
typedef CUresult (WINAPI *PFN_cuMemGetInfo_v2)(size_t*, size_t*);
typedef CUresult (WINAPI *PFN_cuStreamCreate)(CUstream*, unsigned int);
typedef CUresult (WINAPI *PFN_cuStreamDestroy_v2)(CUstream);
typedef CUresult (WINAPI *PFN_cuStreamSynchronize)(CUstream);
typedef CUresult (WINAPI *PFN_cuEventCreate)(CUevent*, unsigned int);
typedef CUresult (WINAPI *PFN_cuEventDestroy_v2)(CUevent);
typedef CUresult (WINAPI *PFN_cuEventRecord)(CUevent, CUstream);
typedef CUresult (WINAPI *PFN_cuEventSynchronize)(CUevent);
typedef CUresult (WINAPI *PFN_cuEventElapsedTime)(float*, CUevent, CUevent);
typedef CUresult (WINAPI *PFN_cuModuleLoadData)(CUmodule*, const void*);
typedef CUresult (WINAPI *PFN_cuModuleUnload)(CUmodule);
typedef CUresult (WINAPI *PFN_cuModuleGetFunction)(CUfunction*, CUmodule, const char*);
typedef CUresult (WINAPI *PFN_cuLaunchKernel)(CUfunction,
    unsigned int, unsigned int, unsigned int,
    unsigned int, unsigned int, unsigned int,
    unsigned int, CUstream, void**, void**);

/* ========================================================================
 * 全局状态
 * ======================================================================== */

static CRITICAL_SECTION s_lock;
static int              s_lock_ready = 0;

static HMODULE          s_nvcuda = NULL;   /* LoadLibrary 一次，永不卸载 */
static int              s_load_failed = 0; /* 驱动缺失后不再重试 */
static int              s_cu_ready = 0;    /* cuInit 成功过 */

static PFN_cuInit                  p_cuInit;
static PFN_cuDriverGetVersion      p_cuDriverGetVersion;
static PFN_cuGetErrorString        p_cuGetErrorString;        /* 可选（老驱动缺失） */
static PFN_cuDeviceGetCount        p_cuDeviceGetCount;
static PFN_cuDeviceGet             p_cuDeviceGet;
static PFN_cuDeviceGetName         p_cuDeviceGetName;
static PFN_cuDeviceTotalMem_v2     p_cuDeviceTotalMem_v2;
static PFN_cuDeviceGetAttribute    p_cuDeviceGetAttribute;
static PFN_cuDevicePrimaryCtxRetain p_cuDevicePrimaryCtxRetain;
static PFN_cuCtxSetCurrent         p_cuCtxSetCurrent;
static PFN_cuCtxGetCurrent         p_cuCtxGetCurrent;
static PFN_cuCtxGetDevice          p_cuCtxGetDevice;
static PFN_cuCtxSynchronize        p_cuCtxSynchronize;
static PFN_cuMemAlloc_v2           p_cuMemAlloc_v2;
static PFN_cuMemAllocManaged       p_cuMemAllocManaged;       /* 可选（CUDA 6 前） */
static PFN_cuMemFree_v2            p_cuMemFree_v2;
static PFN_cuMemsetD8_v2           p_cuMemsetD8_v2;
static PFN_cuMemcpyHtoD_v2         p_cuMemcpyHtoD_v2;
static PFN_cuMemcpyDtoH_v2         p_cuMemcpyDtoH_v2;
static PFN_cuMemcpyDtoD_v2         p_cuMemcpyDtoD_v2;
static PFN_cuMemcpyHtoDAsync_v2    p_cuMemcpyHtoDAsync_v2;
static PFN_cuMemcpyDtoHAsync_v2    p_cuMemcpyDtoHAsync_v2;
static PFN_cuMemGetInfo_v2         p_cuMemGetInfo_v2;
static PFN_cuStreamCreate          p_cuStreamCreate;
static PFN_cuStreamDestroy_v2      p_cuStreamDestroy_v2;
static PFN_cuStreamSynchronize     p_cuStreamSynchronize;
static PFN_cuEventCreate           p_cuEventCreate;
static PFN_cuEventDestroy_v2       p_cuEventDestroy_v2;
static PFN_cuEventRecord           p_cuEventRecord;
static PFN_cuEventSynchronize      p_cuEventSynchronize;
static PFN_cuEventElapsedTime      p_cuEventElapsedTime;
static PFN_cuModuleLoadData        p_cuModuleLoadData;
static PFN_cuModuleUnload          p_cuModuleUnload;
static PFN_cuModuleGetFunction     p_cuModuleGetFunction;
static PFN_cuLaunchKernel          p_cuLaunchKernel;

/* 粘性错误码：每个入口先清零；0 = 无错 */
static __declspec(thread) int t_last = 0;

/* 主上下文缓存：下标 = 设备序号（v1 支持最多 16 卡）。
   首次绑定时 retain，永不 release——平衡点：release 时机无法与
   SL 侧对象生命周期对齐（没有析构钩子），泄漏的仅是每卡一份
   primary context 引用，进程退出由驱动回收。 */
#define SLC_MAX_DEVICES 16
static CUcontext s_primary[SLC_MAX_DEVICES];
static int       s_default_dev = 0;

/* 返回字符串的线程局部缓冲 */
static __declspec(thread) char t_buf[512];

/* 记录并返回错误码（供"返回 rc"形态的函数一行完成） */
static int fail(int rc) { t_last = rc; return rc; }

/* bool 语义转换：CUresult 0（成功）-> 1，非 0 -> 0。
   SL 侧 @DllStaticImport sig 标 ->bool 的入口统一经此出口，
   错误细节仍走粘性 last_error（slc_last_error / slc_error_string）。 */
static int ok(int rc) { return rc == 0 ? 1 : 0; }

/* 句柄/查询类的失败透传：CUresult 写入粘性码后返回 0。
   （SL 侧随后经 slc_last_error / slc_error_string 取原因） */
static int64_t fail_h(int rc) { t_last = rc; return 0; }

/* ========================================================================
 * 驱动加载
 * ======================================================================== */

static void* resolve(const char* name, int optional)
{
    void* p = (void*)GetProcAddress(s_nvcuda, name);
    if (p == NULL && !optional)
    {
        s_load_failed = 1;
    }
    return p;
}

/* PTX JIT 编译器定位（见下方实现）：须在加载 nvcuda.dll 之前完成，
   部分驱动在 cuInit 时即探测并缓存 JIT 位置。 */
static void slc_load_jit_compiler(void);

/* 成功返回 0；把 nvcuda.dll 装入并解析全部必需符号（幂等）。 */
static int slc_load_driver(void)
{
    if (s_load_failed)    { return SLC_E_DRIVER_MISSING; }
    if (s_nvcuda != NULL) { return 0; }

    /* JIT 先行：nvcuda 初始化/cuModuleLoadData 时按搜索序定位
       nvptxJitCompiler64.dll，这里先把包含它的目录补进搜索链。 */
    slc_load_jit_compiler();

    EnterCriticalSection(&s_lock);
    if (s_nvcuda == NULL && !s_load_failed)
    {
        s_nvcuda = LoadLibraryW(L"nvcuda.dll");
        if (s_nvcuda == NULL)
        {
            s_load_failed = 1;
        }
        else
        {
            /* 必需符号：缺失任何一个即视为驱动不可用 */
            p_cuInit                      = (PFN_cuInit)resolve("cuInit", 0);
            p_cuDriverGetVersion          = (PFN_cuDriverGetVersion)resolve("cuDriverGetVersion", 0);
            p_cuGetErrorString            = (PFN_cuGetErrorString)resolve("cuGetErrorString", 1);
            p_cuDeviceGetCount            = (PFN_cuDeviceGetCount)resolve("cuDeviceGetCount", 0);
            p_cuDeviceGet                 = (PFN_cuDeviceGet)resolve("cuDeviceGet", 0);
            p_cuDeviceGetName             = (PFN_cuDeviceGetName)resolve("cuDeviceGetName", 0);
            p_cuDeviceTotalMem_v2         = (PFN_cuDeviceTotalMem_v2)resolve("cuDeviceTotalMem_v2", 0);
            p_cuDeviceGetAttribute        = (PFN_cuDeviceGetAttribute)resolve("cuDeviceGetAttribute", 0);
            p_cuDevicePrimaryCtxRetain     = (PFN_cuDevicePrimaryCtxRetain)resolve("cuDevicePrimaryCtxRetain", 0);
            p_cuCtxSetCurrent             = (PFN_cuCtxSetCurrent)resolve("cuCtxSetCurrent", 0);
            p_cuCtxGetCurrent             = (PFN_cuCtxGetCurrent)resolve("cuCtxGetCurrent", 0);
            p_cuCtxGetDevice              = (PFN_cuCtxGetDevice)resolve("cuCtxGetDevice", 0);
            p_cuCtxSynchronize            = (PFN_cuCtxSynchronize)resolve("cuCtxSynchronize", 0);
            p_cuMemAlloc_v2               = (PFN_cuMemAlloc_v2)resolve("cuMemAlloc_v2", 0);
            p_cuMemAllocManaged           = (PFN_cuMemAllocManaged)resolve("cuMemAllocManaged", 1);
            p_cuMemFree_v2                = (PFN_cuMemFree_v2)resolve("cuMemFree_v2", 0);
            p_cuMemsetD8_v2               = (PFN_cuMemsetD8_v2)resolve("cuMemsetD8_v2", 0);
            p_cuMemcpyHtoD_v2             = (PFN_cuMemcpyHtoD_v2)resolve("cuMemcpyHtoD_v2", 0);
            p_cuMemcpyDtoH_v2             = (PFN_cuMemcpyDtoH_v2)resolve("cuMemcpyDtoH_v2", 0);
            p_cuMemcpyDtoD_v2             = (PFN_cuMemcpyDtoD_v2)resolve("cuMemcpyDtoD_v2", 0);
            p_cuMemcpyHtoDAsync_v2        = (PFN_cuMemcpyHtoDAsync_v2)resolve("cuMemcpyHtoDAsync_v2", 0);
            p_cuMemcpyDtoHAsync_v2        = (PFN_cuMemcpyDtoHAsync_v2)resolve("cuMemcpyDtoHAsync_v2", 0);
            p_cuMemGetInfo_v2             = (PFN_cuMemGetInfo_v2)resolve("cuMemGetInfo_v2", 0);
            p_cuStreamCreate              = (PFN_cuStreamCreate)resolve("cuStreamCreate", 0);
            p_cuStreamDestroy_v2          = (PFN_cuStreamDestroy_v2)resolve("cuStreamDestroy_v2", 0);
            p_cuStreamSynchronize         = (PFN_cuStreamSynchronize)resolve("cuStreamSynchronize", 0);
            p_cuEventCreate               = (PFN_cuEventCreate)resolve("cuEventCreate", 0);
            p_cuEventDestroy_v2           = (PFN_cuEventDestroy_v2)resolve("cuEventDestroy_v2", 0);
            p_cuEventRecord               = (PFN_cuEventRecord)resolve("cuEventRecord", 0);
            p_cuEventSynchronize          = (PFN_cuEventSynchronize)resolve("cuEventSynchronize", 0);
            p_cuEventElapsedTime          = (PFN_cuEventElapsedTime)resolve("cuEventElapsedTime", 0);
            p_cuModuleLoadData            = (PFN_cuModuleLoadData)resolve("cuModuleLoadData", 0);
            p_cuModuleUnload              = (PFN_cuModuleUnload)resolve("cuModuleUnload", 0);
            p_cuModuleGetFunction         = (PFN_cuModuleGetFunction)resolve("cuModuleGetFunction", 0);
            p_cuLaunchKernel              = (PFN_cuLaunchKernel)resolve("cuLaunchKernel", 0);
        }
    }
    LeaveCriticalSection(&s_lock);

    return s_load_failed ? SLC_E_DRIVER_MISSING : 0;
}

/* 通用前置检查：驱动在 + cuInit 跑过。成功返回 0。 */
static int slc_ready(void)
{
    int rc = slc_load_driver();
    if (rc != 0)            { return fail(rc); }
    if (s_cu_ready == 0)    { return fail(SLC_E_NOT_INITIALIZED); }
    return 0;
}

/* ========================================================================
 * PTX JIT 编译器预载（CUDA 12.8+ 驱动把 JIT 从 nvcuda.dll 拆分到
 * 独立的 nvptxJitCompiler64.dll；部分驱动包只把它放进 DriverStore
 * 而不落 System32，导致 cuModuleLoadData(PTX) 报 218
 * (CUDA_ERROR_JIT_COMPILER_NOT_FOUND)）。
 *
 * 对策（R610/CUDA 13.3 实测：驱动不复用进程内已加载模块，但按含 PATH
 * 的标准搜索序定位）：找到 DriverStore 中含该 DLL 的目录后双管齐下——
 *   1) 把该目录 prepend 进**进程 PATH**（SetEnvironmentVariable，仅本
 *      进程可见，零系统侵入），nvcuda 的搜索序随后命中；
 *   2) 同时把 DLL 按完整路径预载进进程——对使用裸名 LoadLibrary 的
 *      老驱动直接命中已加载模块。
 * 时机：必须发生在 LoadLibrary(nvcuda) 之前（部分驱动在 cuInit 时
 * 即探测并缓存 JIT 位置）。若 JIT DLL 确实不存在，两条路径都空转，
 * PTX 加载报 218 透出，设备/内存/流等非 PTX 能力不受影响。
 * ======================================================================== */

static void slc_load_jit_compiler(void)
{
    static int        done = 0;
    HANDLE            find;
    WIN32_FIND_DATAW  fd;
    wchar_t           jitPath[MAX_PATH];
    wchar_t           dirPath[MAX_PATH];
    DWORD             need, dirLen;
    wchar_t*          buf;

    if (done) { return; }
    done = 1;

    /* 已加载 / 默认搜索序可命中：无需干预 */
    if (GetModuleHandleW(L"nvptxJitCompiler64.dll") != NULL) { return; }
    if (LoadLibraryW(L"nvptxJitCompiler64.dll") != NULL)     { return; }

    /* DriverStore\FileRepository\<驱动包>\nvptxJitCompiler64.dll */
    find = FindFirstFileW(L"C:\\Windows\\System32\\DriverStore\\FileRepository\\*",
                          &fd);
    if (find == INVALID_HANDLE_VALUE) { return; }
    do
    {
        if ((fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) == 0) { continue; }
        if (fd.cFileName[0] == L'.') { continue; }

        _snwprintf(dirPath, MAX_PATH - 64,
                   L"C:\\Windows\\System32\\DriverStore\\FileRepository\\%s",
                   fd.cFileName);
        dirPath[MAX_PATH - 65] = L'\0';
        _snwprintf(jitPath, MAX_PATH - 1, L"%s\\nvptxJitCompiler64.dll", dirPath);
        jitPath[MAX_PATH - 1] = L'\0';
        if (GetFileAttributesW(jitPath) == INVALID_FILE_ATTRIBUTES) { continue; }

        /* (2) 预载：对裸名 LoadLibrary 的驱动直接命中已加载模块 */
        LoadLibraryExW(jitPath, NULL, LOAD_WITH_ALTERED_SEARCH_PATH);

        /* (1) 进程 PATH prepend：对按搜索序定位的驱动生效 */
        dirLen = (DWORD)wcslen(dirPath);
        if (dirLen > 0 && dirLen < MAX_PATH - 1)
        {
            need = GetEnvironmentVariableW(L"PATH", NULL, 0);
            if (need == 0)
            {
                SetEnvironmentVariableW(L"PATH", dirPath);
            }
            else
            {
                buf = (wchar_t*)malloc((size_t)(need + dirLen + 4) * sizeof(wchar_t));
                if (buf != NULL)
                {
                    wcscpy(buf, dirPath);
                    buf[dirLen] = L';';
                    if (GetEnvironmentVariableW(L"PATH", buf + dirLen + 1,
                                                need + 2) == 0)
                    {
                        buf[dirLen + 1] = L'\0';
                    }
                    SetEnvironmentVariableW(L"PATH", buf);
                    free(buf);
                }
            }
        }
        break;    /* 命中一个驱动包即止 */
    } while (FindNextFileW(find, &fd));
    FindClose(find);
}

/* 把 dev 的 primary context 绑定为当前线程上下文（懒 retain）。
   返回 0 = 成功。 */
static int slc_bind_ctx(int dev)
{
    CUcontext ctx;
    CUdevice  d;
    int       rc;

    if (dev < 0 || dev >= SLC_MAX_DEVICES) { return fail(SLC_E_BAD_PARAM); }

    rc = slc_ready();
    if (rc != 0) { return rc; }

    if (s_primary[dev] == NULL)
    {
        EnterCriticalSection(&s_lock);
        if (s_primary[dev] == NULL)
        {
            rc = p_cuDeviceGet(&d, dev);
            if (rc != 0)
            {
                LeaveCriticalSection(&s_lock);
                return fail(rc);
            }
            rc = p_cuDevicePrimaryCtxRetain(&ctx, d);
            if (rc != 0)
            {
                LeaveCriticalSection(&s_lock);
                return fail(rc);
            }
            s_primary[dev] = ctx;
        }
        LeaveCriticalSection(&s_lock);
    }
    return fail(p_cuCtxSetCurrent(s_primary[dev]));
}

/* 当前线程无上下文时绑默认设备（首个需要上下文的调用走这里）。
   返回 0 = 成功（或已有上下文）。 */
static int slc_ensure_ctx(void)
{
    CUcontext cur = NULL;
    int       rc;

    rc = slc_ready();
    if (rc != 0) { return rc; }

    if (p_cuCtxGetCurrent(&cur) == 0 && cur != NULL) { return 0; }
    return slc_bind_ctx(s_default_dev);
}

/* ========================================================================
 * 错误 / 版本
 * ======================================================================== */

/* 常见 CUresult 码表（cuGetErrorString 缺失/未初始化时的回退）。
   与 cuda.h 逐值一致；驱动自带 cuGetErrorString 优先于此表。 */
static const char* cuerr_text(int32_t err)
{
    switch (err)
    {
        case 0:   return "success";
        case 1:   return "invalid value";
        case 2:   return "out of memory";
        case 3:   return "driver not initialized";
        case 4:   return "driver deinitialized";
        case 100: return "no CUDA-capable device is detected";
        case 101: return "invalid device ordinal";
        case 200: return "invalid device image";
        case 201: return "invalid context";
        case 202: return "map failed";
        case 203: return "unmap failed";
        case 204: return "array is mapped";
        case 205: return "already mapped";
        case 206: return "no binary for GPU (no suitable kernel image)";
        case 207: return "already acquired";
        case 208: return "not mapped";
        case 211: return "ECC uncorrectable";
        case 212: return "unsupported limit";
        case 213: return "context already in use";
        case 214: return "peer access unsupported";
        case 218: return "invalid PTX (a PTX JIT compilation failed)";
        case 219: return "invalid source";
        case 220: return "file not found";
        case 221: return "shared object init failed";
        case 222: return "unsupported PTX version";
        case 400: return "invalid handle / invalid resource handle";
        case 500: return "not found";
        case 600: return "not ready";
        case 700: return "illegal instruction during kernel execution";
        case 701: return "misaligned address during kernel execution";
        case 702: return "invalid address space during kernel execution";
        case 703: return "invalid program counter during kernel execution";
        case 708: return "illegal memory access during kernel execution";
        case 719: return "launch failed (unspecified)";
        case 999: return "unknown error";
        default:  break;
    }
    if (err == SLC_E_DRIVER_MISSING) { return "nvcuda.dll not found (no NVIDIA driver?)"; }
    if (err == SLC_E_NOT_INITIALIZED) { return "CUDA not initialized (call Cuda.initialize() first)"; }
    if (err == SLC_E_BAD_HANDLE)    { return "invalid handle"; }
    if (err == SLC_E_BAD_PARAM)     { return "invalid parameter"; }
    if (err == SLC_E_NO_DEVICE)     { return "no CUDA device"; }
    return NULL;
}

SLC_API int32_t slc_last_error(void)
{
    return t_last;
}

SLC_API const char* slc_error_string(int32_t err)
{
    const char* s;

    if (err == 0) { err = t_last; }
    if (err == 0) { return "success"; }

    /* 首选驱动自带文本（新驱动全量覆盖，含硬件断言细节） */
    if (p_cuGetErrorString != NULL && err > 0)
    {
        if (p_cuGetErrorString((CUresult)err, &s) == 0 && s != NULL && s[0] != '\0')
        {
            return s;
        }
    }

    s = cuerr_text(err);
    if (s != NULL) { return s; }

    _snprintf(t_buf, sizeof(t_buf) - 1, "CUDA error %d", (int)err);
    return t_buf;
}

SLC_API int32_t slc_init(int32_t flags)
{
    int rc = slc_load_driver();    /* 内含 JIT 定位（先于 nvcuda 加载） */
    t_last = 0;
    if (rc != 0) { return fail(rc); }
    rc = p_cuInit((unsigned int)flags);
    if (rc == 0) { s_cu_ready = 1; }
    t_last = rc;
    return ok(rc);
}

SLC_API int32_t slc_driver_version(void)
{
    int v = 0;
    int rc = slc_ready();
    t_last = 0;
    if (rc != 0) { return 0; }
    if (p_cuDriverGetVersion(&v) != 0) { return 0; }
    return v;
}

/* ========================================================================
 * 设备
 * ======================================================================== */

SLC_API int32_t slc_device_count(void)
{
    int n = 0;
    int rc = slc_ready();
    t_last = 0;
    if (rc != 0) { return 0; }
    if (p_cuDeviceGetCount(&n) != 0 || n < 0) { return 0; }
    return n;
}

SLC_API const char* slc_device_name(int32_t dev)
{
    CUdevice d;
    int rc;
    t_buf[0] = '\0';
    t_last = 0;
    if (slc_load_driver() != 0) { return ""; }
    if (s_cu_ready == 0) { fail(SLC_E_NOT_INITIALIZED); return ""; }
    if (dev < 0 || (rc = p_cuDeviceGet(&d, dev)) != 0) { fail(rc != 0 ? rc : 101); return ""; }
    if ((rc = p_cuDeviceGetName(t_buf, (int)sizeof(t_buf) - 1, d)) != 0)
    {
        t_buf[0] = '\0';
        fail(rc);
    }
    return t_buf;
}

SLC_API int64_t slc_device_total_mem(int32_t dev)
{
    CUdevice d;
    size_t   bytes = 0;
    int      rc;
    t_last = 0;
    if (slc_load_driver() != 0) { return 0; }
    if (s_cu_ready == 0) { fail(SLC_E_NOT_INITIALIZED); return 0; }
    if (dev < 0 || (rc = p_cuDeviceGet(&d, dev)) != 0) { return fail_h(rc != 0 ? rc : 101); }
    if ((rc = p_cuDeviceTotalMem_v2(&bytes, d)) != 0) { return fail_h(rc); }
    return (int64_t)bytes;
}

SLC_API int32_t slc_device_attr(int32_t dev, int32_t attr)
{
    CUdevice d;
    int      v = -1;
    int      rc;
    t_last = 0;
    if (slc_load_driver() != 0) { return -1; }
    if (s_cu_ready == 0) { fail(SLC_E_NOT_INITIALIZED); return -1; }
    if (dev < 0 || (rc = p_cuDeviceGet(&d, dev)) != 0) { fail(rc != 0 ? rc : 101); return -1; }
    if ((rc = p_cuDeviceGetAttribute(&v, attr, d)) != 0) { fail(rc); return -1; }
    return v;
}

SLC_API int32_t slc_device_set(int32_t dev)
{
    int count = 0;
    t_last = 0;
    if (slc_load_driver() != 0) { return 0; }
    if (s_cu_ready == 0)        { fail(SLC_E_NOT_INITIALIZED); return 0; }
    if (dev < 0 || dev >= SLC_MAX_DEVICES) { return 0; }
    if (p_cuDeviceGetCount(&count) != 0 || dev >= count) { return 0; }
    s_default_dev = dev;
    return ok(slc_bind_ctx(dev));
}

SLC_API int32_t slc_device_get(void)
{
    CUdevice d = -1;
    int      rc = slc_ready();
    t_last = 0;
    if (rc != 0) { return -1; }
    if (p_cuCtxGetDevice(&d) != 0) { return -1; }
    return (int32_t)d;
}

SLC_API int32_t slc_ctx_sync(void)
{
    int rc = slc_ensure_ctx();
    t_last = 0;
    if (rc != 0) { t_last = rc; return 0; }
    rc = p_cuCtxSynchronize();
    t_last = rc;
    return ok(rc);
}

/* ========================================================================
 * 设备内存
 * ======================================================================== */

SLC_API int64_t slc_mem_alloc(int64_t bytes)
{
    CUdeviceptr p = 0;
    int rc = slc_ensure_ctx();
    t_last = 0;
    if (rc != 0)         { t_last = rc; return 0; }
    if (bytes <= 0)      { fail(SLC_E_BAD_PARAM); return 0; }
    if ((rc = p_cuMemAlloc_v2(&p, (size_t)bytes)) != 0) { return fail_h(rc); }
    return (int64_t)p;
}

SLC_API int64_t slc_mem_alloc_managed(int64_t bytes, int32_t flags)
{
    CUdeviceptr p = 0;
    int rc = slc_ensure_ctx();
    t_last = 0;
    if (rc != 0)    { t_last = rc; return 0; }
    if (bytes <= 0) { fail(SLC_E_BAD_PARAM); return 0; }
    if (p_cuMemAllocManaged == NULL) { fail(SLC_E_DRIVER_MISSING); return 0; }
    if ((rc = p_cuMemAllocManaged(&p, (size_t)bytes, (unsigned int)flags)) != 0) { return fail_h(rc); }
    return (int64_t)p;
}

SLC_API int32_t slc_mem_free(int64_t ptr)
{
    int rc = slc_ensure_ctx();
    t_last = 0;
    if (rc != 0)   { t_last = rc; return 0; }
    if (ptr == 0)  { return fail(SLC_E_BAD_HANDLE) != 0; }
    rc = p_cuMemFree_v2((CUdeviceptr)ptr);
    t_last = rc;
    return ok(rc);
}

SLC_API int32_t slc_memset8(int64_t ptr, int32_t value, int64_t bytes)
{
    int rc = slc_ensure_ctx();
    t_last = 0;
    if (rc != 0) { t_last = rc; return 0; }
    if (ptr == 0 || bytes <= 0) { fail(SLC_E_BAD_PARAM); return 0; }
    rc = p_cuMemsetD8_v2((CUdeviceptr)ptr, (unsigned char)(value & 0xFF), (size_t)bytes);
    t_last = rc;
    return ok(rc);
}

SLC_API int32_t slc_memcpy_h2d(int64_t dst, const void* srcHost, int64_t bytes)
{
    int rc = slc_ensure_ctx();
    t_last = 0;
    if (rc != 0) { t_last = rc; return 0; }
    if (dst == 0 || srcHost == NULL || bytes < 0) { fail(SLC_E_BAD_PARAM); return 0; }
    rc = p_cuMemcpyHtoD_v2((CUdeviceptr)dst, srcHost, (size_t)bytes);
    t_last = rc;
    return ok(rc);
}

SLC_API int32_t slc_memcpy_d2h(void* dstHost, int64_t src, int64_t bytes)
{
    int rc = slc_ensure_ctx();
    t_last = 0;
    if (rc != 0) { t_last = rc; return 0; }
    if (dstHost == NULL || src == 0 || bytes < 0) { fail(SLC_E_BAD_PARAM); return 0; }
    rc = p_cuMemcpyDtoH_v2(dstHost, (CUdeviceptr)src, (size_t)bytes);
    t_last = rc;
    return ok(rc);
}

SLC_API int32_t slc_memcpy_d2d(int64_t dst, int64_t src, int64_t bytes)
{
    int rc = slc_ensure_ctx();
    t_last = 0;
    if (rc != 0) { t_last = rc; return 0; }
    if (dst == 0 || src == 0 || bytes < 0) { fail(SLC_E_BAD_PARAM); return 0; }
    rc = p_cuMemcpyDtoD_v2((CUdeviceptr)dst, (CUdeviceptr)src, (size_t)bytes);
    t_last = rc;
    return ok(rc);
}

SLC_API int32_t slc_memcpy_h2d_async(int64_t dst, const void* srcHost,
                                     int64_t bytes, int64_t stream)
{
    int rc = slc_ensure_ctx();
    t_last = 0;
    if (rc != 0) { t_last = rc; return 0; }
    if (dst == 0 || srcHost == NULL || bytes < 0) { fail(SLC_E_BAD_PARAM); return 0; }
    rc = p_cuMemcpyHtoDAsync_v2((CUdeviceptr)dst, srcHost, (size_t)bytes,
                                (CUstream)(void*)(intptr_t)stream);
    t_last = rc;
    return ok(rc);
}

SLC_API int32_t slc_memcpy_d2h_async(void* dstHost, int64_t src,
                                     int64_t bytes, int64_t stream)
{
    int rc = slc_ensure_ctx();
    t_last = 0;
    if (rc != 0) { t_last = rc; return 0; }
    if (dstHost == NULL || src == 0 || bytes < 0) { fail(SLC_E_BAD_PARAM); return 0; }
    rc = p_cuMemcpyDtoHAsync_v2(dstHost, (CUdeviceptr)src, (size_t)bytes,
                                (CUstream)(void*)(intptr_t)stream);
    t_last = rc;
    return ok(rc);
}

SLC_API int32_t slc_mem_info(void* freeOut, void* totalOut)
{
    size_t fr = 0, tot = 0;
    int    rc = slc_ensure_ctx();
    t_last = 0;
    if (rc != 0) { t_last = rc; return 0; }
    if (freeOut == NULL || totalOut == NULL) { fail(SLC_E_BAD_PARAM); return 0; }
    rc = p_cuMemGetInfo_v2(&fr, &tot);
    t_last = rc;
    if (rc != 0) { return 0; }
    *(int64_t*)freeOut  = (int64_t)fr;
    *(int64_t*)totalOut = (int64_t)tot;
    return 1;
}

/* ========================================================================
 * 流
 * ======================================================================== */

SLC_API int64_t slc_stream_create(int32_t flags)
{
    CUstream s = NULL;
    int rc = slc_ensure_ctx();
    t_last = 0;
    if (rc != 0) { t_last = rc; return 0; }
    if ((rc = p_cuStreamCreate(&s, (unsigned int)flags)) != 0) { return fail_h(rc); }
    return (int64_t)(intptr_t)s;
}

SLC_API int32_t slc_stream_destroy(int64_t stream)
{
    int rc = slc_ready();
    t_last = 0;
    if (rc != 0)      { t_last = rc; return 0; }
    if (stream == 0)  { fail(SLC_E_BAD_HANDLE); return 0; }  /* 默认流不可销毁 */
    rc = p_cuStreamDestroy_v2((CUstream)(void*)(intptr_t)stream);
    t_last = rc;
    return ok(rc);
}

SLC_API int32_t slc_stream_sync(int64_t stream)
{
    int rc = slc_ready();
    t_last = 0;
    if (rc != 0) { t_last = rc; return 0; }
    /* stream == 0 = 默认流，合法 */
    rc = p_cuStreamSynchronize((CUstream)(void*)(intptr_t)stream);
    t_last = rc;
    return ok(rc);
}

/* ========================================================================
 * 事件
 * ======================================================================== */

SLC_API int64_t slc_event_create(int32_t flags)
{
    CUevent e = NULL;
    int rc = slc_ensure_ctx();
    t_last = 0;
    if (rc != 0) { t_last = rc; return 0; }
    if ((rc = p_cuEventCreate(&e, (unsigned int)flags)) != 0) { return fail_h(rc); }
    return (int64_t)(intptr_t)e;
}

SLC_API int32_t slc_event_destroy(int64_t event)
{
    int rc = slc_ready();
    t_last = 0;
    if (rc != 0)     { t_last = rc; return 0; }
    if (event == 0)  { fail(SLC_E_BAD_HANDLE); return 0; }
    rc = p_cuEventDestroy_v2((CUevent)(void*)(intptr_t)event);
    t_last = rc;
    return ok(rc);
}

SLC_API int32_t slc_event_record(int64_t event, int64_t stream)
{
    int rc = slc_ready();
    t_last = 0;
    if (rc != 0)    { t_last = rc; return 0; }
    if (event == 0) { fail(SLC_E_BAD_HANDLE); return 0; }
    rc = p_cuEventRecord((CUevent)(void*)(intptr_t)event,
                         (CUstream)(void*)(intptr_t)stream);
    t_last = rc;
    return ok(rc);
}

SLC_API int32_t slc_event_sync(int64_t event)
{
    int rc = slc_ready();
    t_last = 0;
    if (rc != 0)    { t_last = rc; return 0; }
    if (event == 0) { fail(SLC_E_BAD_HANDLE); return 0; }
    rc = p_cuEventSynchronize((CUevent)(void*)(intptr_t)event);
    t_last = rc;
    return ok(rc);
}

SLC_API double slc_event_elapsed_ms(int64_t start, int64_t end)
{
    float ms = -1.0f;
    int   rc = slc_ready();
    t_last = 0;
    if (rc != 0)                { t_last = rc; return -1.0; }
    if (start == 0 || end == 0) { fail(SLC_E_BAD_HANDLE); return -1.0; }
    if ((rc = p_cuEventElapsedTime(&ms, (CUevent)(void*)(intptr_t)start,
                                   (CUevent)(void*)(intptr_t)end)) != 0)
    {
        fail(rc);
        return -1.0;
    }
    return (double)ms;
}

/* ========================================================================
 * 模块 / 内核
 * ======================================================================== */

SLC_API int64_t slc_module_load_data(const char* image)
{
    CUmodule m = NULL;
    int rc = slc_ensure_ctx();
    t_last = 0;
    if (rc != 0)        { t_last = rc; return 0; }
    if (image == NULL || image[0] == '\0') { fail(SLC_E_BAD_PARAM); return 0; }
    if ((rc = p_cuModuleLoadData(&m, image)) != 0) { return fail_h(rc); }
    return (int64_t)(intptr_t)m;
}

SLC_API int32_t slc_module_unload(int64_t module)
{
    int rc = slc_ready();
    t_last = 0;
    if (rc != 0)      { t_last = rc; return 0; }
    if (module == 0)  { fail(SLC_E_BAD_HANDLE); return 0; }
    rc = p_cuModuleUnload((CUmodule)(void*)(intptr_t)module);
    t_last = rc;
    return ok(rc);
}

SLC_API int64_t slc_module_get_function(int64_t module, const char* name)
{
    CUfunction f = NULL;
    int rc = slc_ready();
    t_last = 0;
    if (rc != 0)      { t_last = rc; return 0; }
    if (module == 0 || name == NULL || name[0] == '\0')
    {
        fail(SLC_E_BAD_PARAM);
        return 0;
    }
    if ((rc = p_cuModuleGetFunction(&f, (CUmodule)(void*)(intptr_t)module, name)) != 0)
    {
        return fail_h(rc);
    }
    return (int64_t)(intptr_t)f;
}

/* 启动描述块布局（与 vm_sl_cuda.h 文件头一致）：
   0/4/8   gridX/Y/Z (i32)      12/16/20 blockX/Y/Z (i32)
   24      sharedBytes (i32)     28      保留 (i32)
   32      stream (i64)                     总 40 字节 */
SLC_API int32_t slc_kernel_launch(int64_t func, const void* config,
                                  const void* params)
{
    const char*  c;
    unsigned int gx, gy, gz, bx, by, bz, shared;
    int64_t      stream;
    int          rc = slc_ensure_ctx();
    t_last = 0;
    if (rc != 0) { t_last = rc; return 0; }
    if (func == 0 || config == NULL) { fail(SLC_E_BAD_PARAM); return 0; }

    c = (const char*)config;
    gx     = (unsigned int)*(const int32_t*)(const void*)(c + 0);
    gy     = (unsigned int)*(const int32_t*)(const void*)(c + 4);
    gz     = (unsigned int)*(const int32_t*)(const void*)(c + 8);
    bx     = (unsigned int)*(const int32_t*)(const void*)(c + 12);
    by     = (unsigned int)*(const int32_t*)(const void*)(c + 16);
    bz     = (unsigned int)*(const int32_t*)(const void*)(c + 20);
    shared = (unsigned int)*(const int32_t*)(const void*)(c + 24);
    stream = *(const int64_t*)(const void*)(c + 32);

    if (gx == 0 || gy == 0 || gz == 0 || bx == 0 || by == 0 || bz == 0)
    {
        fail(SLC_E_BAD_PARAM);
        return 0;
    }

    /* params 为 NULL 表示内核无参（kernelParams 允许 NULL 仅当内核
       签名无参；有参内核传 NULL 会被驱动拒绝，正好透传错误码）。 */
    rc = p_cuLaunchKernel((CUfunction)(void*)(intptr_t)func,
                          gx, gy, gz, bx, by, bz, shared,
                          (CUstream)(void*)(intptr_t)stream,
                          (void**)params, NULL);
    t_last = rc;
    return ok(rc);
}

/* ========================================================================
 * DllMain
 * ======================================================================== */

BOOL WINAPI DllMain(HINSTANCE instance, DWORD reason, LPVOID reserved)
{
    (void)instance; (void)reserved;
    switch (reason)
    {
        case DLL_PROCESS_ATTACH:
            InitializeCriticalSection(&s_lock);
            s_lock_ready = 1;
            memset(s_primary, 0, sizeof(s_primary));
            break;
        case DLL_PROCESS_DETACH:
            if (s_lock_ready) { DeleteCriticalSection(&s_lock); }
            break;
        default:
            break;
    }
    return TRUE;
}
