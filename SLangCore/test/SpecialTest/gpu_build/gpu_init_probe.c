// gpu_init_probe.c — isolate nvcuda load + cuInit + ctx + cuMemAlloc.
#include <windows.h>
#include <stdio.h>

typedef int CUresult;
typedef unsigned long long CUdeviceptr;
typedef struct CUctx_st* CUcontext;
typedef int CUdevice;

int main(void)
{
    HMODULE nv = LoadLibraryA("nvcuda.dll");
    printf("step1: nvcuda=%p\n", (void*)nv); fflush(stdout);
    if (!nv) return 1;

    CUresult (*p_cuInit)(unsigned) = (void*)GetProcAddress(nv, "cuInit");
    CUresult (*p_cuRetain)(CUcontext*, int) =
        (void*)GetProcAddress(nv, "cuDevicePrimaryCtxRetain");
    CUresult (*p_cuSet)(CUcontext) = (void*)GetProcAddress(nv, "cuCtxSetCurrent");
    CUresult (*p_cuGet)(CUcontext*) = (void*)GetProcAddress(nv, "cuCtxGetCurrent");
    CUresult (*p_cuAlloc)(CUdeviceptr*, unsigned long long) =
        (void*)GetProcAddress(nv, "cuMemAlloc_v2");
    CUresult (*p_cuAllocOld)(CUdeviceptr*, unsigned long long) =
        (void*)GetProcAddress(nv, "cuMemAlloc");
    CUresult (*p_cuFree)(CUdeviceptr) = (void*)GetProcAddress(nv, "cuMemFree_v2");
    CUresult (*p_cuCtxCreate)(CUcontext*, unsigned, CUdevice) =
        (void*)GetProcAddress(nv, "cuCtxCreate_v2");
    CUresult (*p_cuDevCount)(int*) = (void*)GetProcAddress(nv, "cuDeviceGetCount");
    printf("step2: procs resolved\n"); fflush(stdout);

    CUresult r = p_cuInit(0);
    printf("step3: cuInit=%d\n", r); fflush(stdout);

    int count = -1;
    p_cuDevCount(&count);
    printf("step4: deviceCount=%d\n", count); fflush(stdout);

    /* path A: explicit context */
    CUcontext ectx = 0;
    r = p_cuCtxCreate(&ectx, 0, 0);
    printf("step5: ctxCreate=%d ctx=%p\n", r, (void*)ectx); fflush(stdout);
    if (ectx)
    {
        CUdeviceptr d = 0;
        r = p_cuAllocOld(&d, 8 * 1024 * 1024);
        printf("step6a: alloc(explicit ctx, OLD unversioned)=%d d=%llx\n", r, d); fflush(stdout);
        if (d) p_cuFree(d);
        d = 0;
        r = p_cuAlloc(&d, 8 * 1024 * 1024);
        printf("step6b: alloc(explicit ctx, v2)=%d d=%llx\n", r, d); fflush(stdout);
        if (d) p_cuFree(d);
    }

    /* path B: primary context */
    CUcontext ctx = 0;
    r = p_cuRetain(&ctx, 0);
    printf("step7: retain=%d ctx=%p\n", r, (void*)ctx); fflush(stdout);
    r = p_cuSet(ctx);
    printf("step8: setCurrent=%d\n", r); fflush(stdout);
    CUdeviceptr d2 = 0;
    r = p_cuAlloc(&d2, 4096);
    printf("step9: alloc(primary ctx, 4K)=%d d=%llx\n", r, d2); fflush(stdout);
    if (d2) p_cuFree(d2);

    printf("done\n"); fflush(stdout);
    return 0;
}
