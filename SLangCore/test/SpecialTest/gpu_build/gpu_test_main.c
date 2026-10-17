// gpu_test_main.c — harness for the gpu_spike2.dll experiment.
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>

typedef long long (*host_fn)(void* a, void* b, void* c, long long n);

static double now_ms(void)
{
    LARGE_INTEGER f, t;
    QueryPerformanceFrequency(&f);
    QueryPerformanceCounter(&t);
    return t.QuadPart * 1000.0 / f.QuadPart;
}

int main(void)
{
    printf("m0: LoadLibrary...\n"); fflush(stdout);
    HMODULE h = LoadLibraryA("gpu_spike2.dll");
    if (!h) { printf("LoadLibrary failed: %lu\n", GetLastError()); return 1; }
    printf("m1: GetProcAddress...\n"); fflush(stdout);
    host_fn f = (host_fn)GetProcAddress(h, "host_vecadd_staged");
    if (!f) { printf("GetProcAddress failed\n"); return 1; }

    long long n = 1000000;
    double* a = (double*)malloc(n * sizeof(double));
    double* b = (double*)malloc(n * sizeof(double));
    double* c = (double*)malloc(n * sizeof(double));
    for (long long i = 0; i < n; i++) { a[i] = (double)i; b[i] = 2.0; c[i] = -1.0; }

    printf("m2: call host fn...\n"); fflush(stdout);
    double t0 = now_ms();
    long long r = f(a, b, c, n);
    double t1 = now_ms();
    printf("m3: host fn returned\n"); fflush(stdout);

    long long bad = 0;
    for (long long i = 0; i < n; i++)
        if (c[i] != (double)i + 2.0) bad++;

    printf("ret=%lld time=%.3fms bad=%lld c[0]=%.1f c[1]=%.1f c[n-1]=%.1f\n",
           r, t1 - t0, bad, c[0], c[1], c[n - 1]);
    return bad ? 2 : 0;
}
