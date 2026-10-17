//****************************************************************************
//  sl_gpu_runtime.c — CUDA runtime support for SimpleLanguage AOT GPU dlls.
//
//  Two symbol families:
//    mgpu*  — required by MLIR `--gpu-to-llvm` generated host code
//             (module load / function lookup / stream / launch).
//    slgpu* — SL host-wrapper staging helpers (device malloc, HtoD, DtoH,
//             free) so kernels receive device pointers, not host pointers.
//
//  Implementation notes:
//    - Driver API loaded dynamically from nvcuda.dll (no CUDA SDK link
//      dependency; cuda.lib not needed at link time).
//    - CUDA context: primary context of device 0, made current on every
//      entry point (cheap after the first call).
//    - DLL entry `sl_gpu_entry` runs the .CRT section manually so the
//      llvm.global_ctors chain (kernels_load) executes even though the dll
//      is linked with a custom entry point instead of the CRT startup.
//****************************************************************************

#include <windows.h>
#include <stdio.h>

// ---------------------------------------------------------------------------
// CUDA driver API (dynamically resolved)
// ---------------------------------------------------------------------------
typedef int CUresult;
typedef unsigned long long CUdeviceptr;
typedef struct CUmod_st*  CUmodule;
typedef struct CUfunc_st* CUfunction;
typedef struct CUstream_st* CUstream;
typedef struct CUctx_st*   CUcontext;

static CUresult (*p_cuInit)(unsigned flags);
static CUresult (*p_cuModuleLoadData)(CUmodule*, const void*);
static CUresult (*p_cuModuleUnload)(CUmodule);
static CUresult (*p_cuModuleGetFunction)(CUfunction*, CUmodule, const char*);
static CUresult (*p_cuStreamCreate)(CUstream*, unsigned flags);
static CUresult (*p_cuStreamDestroy)(CUstream);
static CUresult (*p_cuStreamSynchronize)(CUstream);
static CUresult (*p_cuLaunchKernel)(CUfunction,
                                    unsigned, unsigned, unsigned,
                                    unsigned, unsigned, unsigned,
                                    unsigned sharedMemBytes, CUstream,
                                    void** params, void** extra);
static CUresult (*p_cuMemAlloc)(CUdeviceptr*, unsigned long long);
static CUresult (*p_cuMemFree)(CUdeviceptr);
static CUresult (*p_cuMemcpyHtoD)(CUdeviceptr, const void*, unsigned long long);
static CUresult (*p_cuMemcpyDtoH)(void*, CUdeviceptr, unsigned long long);
static CUresult (*p_cuCtxGetCurrent)(CUcontext*);
static CUresult (*p_cuDevicePrimaryCtxRetain)(CUcontext*, int);
static CUresult (*p_cuCtxSetCurrent)(CUcontext);

static int g_loaded = 0;      /* nvcuda procs resolved */
static CUcontext g_ctx = 0;   /* retained primary context */

static void trace(const char* msg)
{
#ifdef SLGPU_TRACE
    fprintf(stderr, "[slgpu] %s\n", msg);
#else
    (void)msg;
#endif
}

static void trace_result(const char* what, CUresult r)
{
#ifdef SLGPU_TRACE
    if (r != 0)
        fprintf(stderr, "[slgpu] %s failed: CUresult=%d\n", what, r);
#else
    (void)what; (void)r;
#endif
}

/* Resolve nvcuda.dll + ensure a CUDA context is current on this thread. */
static int ensure_cuda(void)
{
    if (!g_loaded)
    {
        trace("loading nvcuda.dll");
        HMODULE nv = LoadLibraryA("nvcuda.dll");
        if (!nv)
        {
            trace("nvcuda.dll not found");
            return 0;
        }
#define RESOLVE(var, name) \
        *(void**)&var = (void*)GetProcAddress(nv, name); \
        if (!(var)) { trace("missing proc " name); return 0; }

        RESOLVE(p_cuInit,                  "cuInit")
        RESOLVE(p_cuModuleLoadData,        "cuModuleLoadData")
        RESOLVE(p_cuModuleUnload,          "cuModuleUnload")
        RESOLVE(p_cuModuleGetFunction,     "cuModuleGetFunction")
        RESOLVE(p_cuStreamCreate,          "cuStreamCreate")
        RESOLVE(p_cuStreamDestroy,         "cuStreamDestroy")
        RESOLVE(p_cuStreamSynchronize,     "cuStreamSynchronize")
        RESOLVE(p_cuLaunchKernel,          "cuLaunchKernel")
        RESOLVE(p_cuMemAlloc,              "cuMemAlloc_v2")
        RESOLVE(p_cuMemFree,               "cuMemFree_v2")
        RESOLVE(p_cuMemcpyHtoD,            "cuMemcpyHtoD_v2")
        RESOLVE(p_cuMemcpyDtoH,            "cuMemcpyDtoH_v2")
        RESOLVE(p_cuCtxGetCurrent,         "cuCtxGetCurrent")
        RESOLVE(p_cuDevicePrimaryCtxRetain,"cuDevicePrimaryCtxRetain")
        RESOLVE(p_cuCtxSetCurrent,         "cuCtxSetCurrent")
#undef RESOLVE
        trace("calling cuInit");
        if (p_cuInit(0) != 0)
        {
            trace("cuInit failed");
            return 0;
        }
        trace("cuInit ok");
        g_loaded = 1;
    }

    /* every entry point: make sure the primary context is current */
    CUcontext cur = 0;
    if (p_cuCtxGetCurrent(&cur) != 0 || !cur)
    {
        if (!g_ctx)
        {
            trace("retaining primary ctx");
            if (p_cuDevicePrimaryCtxRetain(&g_ctx, 0) != 0)
            {
                trace("cuDevicePrimaryCtxRetain failed");
                return 0;
            }
            trace("primary ctx retained");
        }
        p_cuCtxSetCurrent(g_ctx);
    }
    return 1;
}

// ---------------------------------------------------------------------------
// mgpu* — called by MLIR gpu-to-llvm generated host code
// ---------------------------------------------------------------------------

static void ensure_ctors(void); /* fwd: lazy llvm.global_ctors execution */

void* mgpuModuleLoad(const void* data, long long size)
{
    (void)size;
    ensure_ctors();
    if (!ensure_cuda()) return 0;
    CUmodule m = 0;
    CUresult r = p_cuModuleLoadData(&m, data);
    trace_result("cuModuleLoadData", r);
    if (r == 0) trace("cuModuleLoadData ok");
    return r == 0 ? m : 0;
}

void mgpuModuleUnload(void* m)
{
    ensure_ctors();
    if (m) p_cuModuleUnload((CUmodule)m);
}

void* mgpuModuleGetFunction(void* m, const char* name)
{
    ensure_ctors();
    if (!m) return 0;
    CUfunction f = 0;
    CUresult r = p_cuModuleGetFunction(&f, (CUmodule)m, name);
    trace_result("cuModuleGetFunction", r);
    return r == 0 ? f : 0;
}

void* mgpuStreamCreate(void)
{
    ensure_ctors();
    if (!ensure_cuda()) return 0;
    CUstream s = 0;
    CUresult r = p_cuStreamCreate(&s, 0);
    trace_result("cuStreamCreate", r);
    return r == 0 ? s : 0;
}

void mgpuLaunchKernel(void* fn,
                      long long gx, long long gy, long long gz,
                      long long bx, long long by, long long bz,
                      int sharedMemBytes, void* stream,
                      void** params, void** extra, long long paramCount)
{
    (void)paramCount;
    ensure_ctors();
    if (!fn) { trace("mgpuLaunchKernel: null function"); return; }
    if (!ensure_cuda()) return;
    CUresult r = p_cuLaunchKernel((CUfunction)fn,
                                  (unsigned)gx, (unsigned)gy, (unsigned)gz,
                                  (unsigned)bx, (unsigned)by, (unsigned)bz,
                                  (unsigned)sharedMemBytes, (CUstream)stream,
                                  params, extra);
    trace_result("cuLaunchKernel", r);
}

void mgpuStreamSynchronize(void* s)
{
    ensure_ctors();
    if (s) p_cuStreamSynchronize((CUstream)s);
}

void mgpuStreamDestroy(void* s)
{
    ensure_ctors();
    if (s) p_cuStreamDestroy((CUstream)s);
}

// ---------------------------------------------------------------------------
// slgpu* — SL host-wrapper staging helpers (called from emitted MLIR)
// ---------------------------------------------------------------------------

void* slgpuMalloc(long long bytes)
{
    ensure_ctors();
    if (!ensure_cuda()) return 0;
    CUdeviceptr d = 0;
    if (bytes <= 0) return 0;
    CUresult r = p_cuMemAlloc(&d, (unsigned long long)bytes);
    trace_result("cuMemAlloc", r);
    return r == 0 ? (void*)d : 0;
}

void slgpuMemcpyHtoD(void* dst, const void* src, long long bytes)
{
    ensure_ctors();
    if (!dst || !src || bytes <= 0) return;
    p_cuMemcpyHtoD((CUdeviceptr)dst, src, (unsigned long long)bytes);
}

void slgpuMemcpyDtoH(void* dst, const void* src, long long bytes)
{
    ensure_ctors();
    if (!dst || !src || bytes <= 0) return;
    p_cuMemcpyDtoH(dst, (CUdeviceptr)src, (unsigned long long)bytes);
}

void slgpuFree(void* p)
{
    ensure_ctors();
    if (p) p_cuMemFree((CUdeviceptr)p);
}

// ---------------------------------------------------------------------------
// Lazy ctor execution: the llvm.global_ctors chain (kernels_load) must NOT
// run inside DllMain (loader lock); it runs on the first runtime call.
// ---------------------------------------------------------------------------

static void run_crt_init(void)
{
    HMODULE h = 0;
    if (!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
                            GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                            (LPCWSTR)(void*)&run_crt_init, &h))
        return;

    IMAGE_DOS_HEADER* dos = (IMAGE_DOS_HEADER*)h;
    IMAGE_NT_HEADERS* nt = (IMAGE_NT_HEADERS*)((char*)h + dos->e_lfanew);
    IMAGE_SECTION_HEADER* sec = IMAGE_FIRST_SECTION(nt);
    for (int i = 0; i < nt->FileHeader.NumberOfSections; i++, sec++)
    {
        if (memcmp(sec->Name, ".CRT", 4) != 0)
            continue;
        char* base = (char*)h + sec->VirtualAddress;
        char* end  = base + sec->Misc.VirtualSize;
        for (void** p = (void**)base; (char*)p + sizeof(void*) <= end; p++)
        {
            if (*p)
            {
                trace("running CRT init entry");
                ((void (*)(void))*p)();
            }
        }
    }
}

static void ensure_ctors(void)
{
    static int done = 0;
    if (!done)
    {
        done = 1;
        run_crt_init();
    }
}

BOOL WINAPI sl_gpu_entry(HINSTANCE hinst, DWORD reason, LPVOID reserved)
{
    (void)reserved;
    if (reason == DLL_PROCESS_ATTACH)
        DisableThreadLibraryCalls(hinst);
    return TRUE;
}
