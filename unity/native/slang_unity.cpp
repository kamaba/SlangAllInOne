// slang_unity.cpp - SLang <-> Unity native binding layer (C++, C ABI).
//
// v2 (2026-11-09): direct Unity Native Plugin API path.
//
//   * UnityPluginLoad(IUnityInterfaces*) attaches IUnityLog + IUnityGraphics +
//     IUnityGraphicsD3D11. SL logs therefore go straight into the Unity Console
//     from C++; C# no longer forwards a single log line.
//   * A render event callback is exported (slu_get_render_event_func) and wired
//     once via CommandBuffer.IssuePluginEvent: the ENGINE calls C++ on the
//     render thread every frame, with zero C# in the hot path.
//   * slu_frame(dt, out9) fuses step + state read + hot-reload mtime check into
//     ONE P/Invoke per frame (the only managed->native crossing per frame).
//   * Everything engine-object related that Unity does not export (Transform)
//     is applied by C# with ONE SetPositionAndRotation call; color is written
//     only when the C++ dirty flag says it changed.
//
// Outside Unity (CLI/verification) no IUnityLog is present: logs fall back to
// OutputDebugStringA + stdout, so the same DLL still works with slang.exe.
//
// All mutable state is a POD in a shared section.

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <d3d11.h>

#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <string>
#include <vector>

#include "IUnityInterface.h"
#include "IUnityLog.h"
#include "IUnityGraphics.h"
#include "IUnityGraphicsD3D11.h"

#define SLU_API extern "C" __declspec(dllexport)

#define SLU_LOG_CAP       32
#define SLU_LOG_LEN       512
#define SLU_NAME_LEN      64
#define SLU_PATH_LEN      512
#define SLU_STATE_DOUBLES 9
#define SLU_DIAG_COUNT    6

/* v3 object-mirror layout. Declared before SlUState so the object table
 * can be a member of the shared state section (see g_state below). */
#define SLU_MAX_OBJECTS  64
#define SLU_OBJ_NAME_LEN 64
#define SLU_OBJ_STRIDE   20

struct SlUObject
{
    long long handle;
    int       used;
    int       pending;
    int       active;
    int       activeDirty;
    int       colorDirty;
    int       fovDirty;
    int       playing;
    double    spin;
    double    bobAmp;
    double    bobSpeed;
    double    baseX;
    double    baseY;
    double    baseZ;
    double    posX;
    double    posY;
    double    posZ;
    double    rotX;
    double    rotY;
    double    rotZ;
    double    scaleX;
    double    scaleY;
    double    scaleZ;
    double    colorR;
    double    colorG;
    double    colorB;
    double    colorA;
    double    fov;
    double    volume;
    char      name[SLU_OBJ_NAME_LEN];
};

/* slu_frame() return flags */
#define SLU_FLAG_RELOAD   0x01
#define SLU_FLAG_COLOR    0x02
#define SLU_FLAG_BOOTED   0x04
#define SLU_FLAG_UNITYLOG 0x08

struct SlUState
{
    volatile LONG lock;
    int           frameCount;
    int           runCode;
    int           booted;
    double        time;
    double        angleY;
    double        spin;
    double        bobAmp;
    double        bobSpeed;
    double        baseX;
    double        baseY;
    double        baseZ;
    double        colorR;
    double        colorG;
    double        colorB;
    double        posX;
    double        posY;
    double        posZ;
    char          target[SLU_NAME_LEN];
    char          lastTag[SLU_NAME_LEN];
    char          logs[SLU_LOG_CAP][SLU_LOG_LEN];
    int           logHead;
    int           logCount;
    HMODULE       vmDll;

    /* v2 fields (appended at the tail) */
    IUnityLog*            unityLog;
    IUnityGraphics*       unityGraphics;
    IUnityGraphicsD3D11*  gfxD3D11;
    int                   renderer;
    int                   hasDevice;
    int                   colorDirty;
    int                   needReload;
    int                   unityLogUsed;
    volatile LONG         gfxEvents;
    volatile LONG         renderEventCount;
    unsigned long long    slbMtime;
    char                  slbPath[SLU_PATH_LEN];
    DWORD                 ownerPid;
};

#pragma section(".slushare", read, write, shared)
__declspec(allocate(".slushare")) static SlUState g_state = {};
#pragma comment(linker, "/SECTION:.slushare,RWS")

static HMODULE g_selfModule = NULL;
static IUnityGraphicsDeviceEventCallback g_gfxCallback = NULL;

BOOL APIENTRY DllMain(HMODULE hModule, DWORD reason, LPVOID reserved)
{
    (void)reserved;
    if (reason == DLL_PROCESS_ATTACH)
    {
        g_selfModule = hModule;
        DisableThreadLibraryCalls(hModule);
    }
    return TRUE;
}

static void slu_lock(void)
{
    while (InterlockedCompareExchange(&g_state.lock, 1, 0) != 0)
    {
        Sleep(0);
    }
}

static void slu_unlock(void)
{
    InterlockedExchange(&g_state.lock, 0);
}

/* Engine interface pointers live in a shared section, so they are only valid
 * in the process that called UnityPluginLoad. A CLI process loading the same
 * DLL path sees the same section: guard every dereference with ownerPid. */
static int slu_engine_owned(void)
{
    return g_state.ownerPid == GetCurrentProcessId();
}

/* Caller must hold the lock. */
static void slu_push_log_locked(const char* msg)
{
    int slot;
    if (msg == NULL)
    {
        return;
    }
    slot = (g_state.logHead + g_state.logCount) % SLU_LOG_CAP;
    std::memset(g_state.logs[slot], 0, SLU_LOG_LEN);
    std::strncpy(g_state.logs[slot], msg, SLU_LOG_LEN - 1);
    if (g_state.logCount < SLU_LOG_CAP)
    {
        g_state.logCount = g_state.logCount + 1;
    }
    else
    {
        g_state.logHead = (g_state.logHead + 1) % SLU_LOG_CAP;
    }

    if (g_state.unityLog != NULL && slu_engine_owned())
    {
        /* Direct engine call: C++ -> Unity Console, no C# involvement. */
        g_state.unityLog->Log(kUnityLogTypeLog, msg, "slang_unity.cpp", 0);
        g_state.unityLogUsed = g_state.unityLogUsed + 1;
    }
    else
    {
        OutputDebugStringA(msg);
        OutputDebugStringA("\n");
        std::fputs(msg, stdout);
        std::fputs("\n", stdout);
        std::fflush(stdout);
    }
}

static void slu_push_log(const char* msg)
{
    slu_lock();
    slu_push_log_locked(msg);
    slu_unlock();
}

static void slu_copy_name(char* dst, int cap, const char* src)
{
    std::memset(dst, 0, (size_t)cap);
    if (src != NULL)
    {
        std::strncpy(dst, src, (size_t)cap - 1);
    }
}

static std::string slu_self_dir(void)
{
    std::vector<wchar_t> buf(MAX_PATH + 1, 0);
    std::string out;
    DWORD n = GetModuleFileNameW(g_selfModule, &buf[0], (DWORD)buf.size() - 1);
    if (n == 0)
    {
        return out;
    }
    std::wstring full(&buf[0]);
    size_t pos = full.find_last_of(L"\\/");
    if (pos != std::wstring::npos)
    {
        full = full.substr(0, pos);
    }
    int need = WideCharToMultiByte(CP_UTF8, 0, full.c_str(), -1, NULL, 0, NULL, NULL);
    if (need > 1)
    {
        std::vector<char> tmp((size_t)need, 0);
        WideCharToMultiByte(CP_UTF8, 0, full.c_str(), -1, &tmp[0], need, NULL, NULL);
        out.assign(&tmp[0]);
    }
    return out;
}

static HMODULE slu_load_vm_dll(void)
{
    std::string dir;
    std::string path;
    if (g_state.vmDll != NULL && slu_engine_owned())
    {
        return g_state.vmDll;
    }
    g_state.vmDll = NULL;
    dir = slu_self_dir();
    if (!dir.empty())
    {
        path = dir + "\\csimple_lang_dll.dll";
        g_state.vmDll = LoadLibraryA(path.c_str());
    }
    if (g_state.vmDll == NULL)
    {
        g_state.vmDll = LoadLibraryA("csimple_lang_dll.dll");
    }
    return g_state.vmDll;
}

static unsigned long long slu_file_mtime(const char* utf8Path)
{
    std::vector<wchar_t> wide;
    WIN32_FILE_ATTRIBUTE_DATA fad;
    ULARGE_INTEGER stamp;
    int need = MultiByteToWideChar(CP_UTF8, 0, utf8Path, -1, NULL, 0);
    if (need <= 0)
    {
        return 0;
    }
    wide.resize((size_t)need, 0);
    MultiByteToWideChar(CP_UTF8, 0, utf8Path, -1, &wide[0], need);
    if (!GetFileAttributesExW(&wide[0], GetFileExInfoStandard, &fad))
    {
        return 0;
    }
    stamp.HighPart = fad.ftLastWriteTime.dwHighDateTime;
    stamp.LowPart = fad.ftLastWriteTime.dwLowDateTime;
    return stamp.QuadPart;
}

typedef int (__cdecl *SlRunBinaryFn)(const unsigned char* data, long long dataSize,
    const char* baseDir, int flags, const char** programArgs, int programArgCount);
typedef int (__cdecl *SlCliMainFn)(int argc, char** argv);

/* ------------------------------------------------------------------------- */
/* Unity Native Plugin API entry points (called by the ENGINE, not by C#)     */
/* ------------------------------------------------------------------------- */

static void UNITY_INTERFACE_API slu_on_gfx_device_event(UnityGfxDeviceEventType eventType)
{
    if (eventType == kUnityGfxDeviceEventInitialize)
    {
        InterlockedIncrement(&g_state.gfxEvents);
    }
}

static void UNITY_INTERFACE_API slu_on_render_event(int eventId)
{
    (void)eventId;
    if (!slu_engine_owned())
    {
        return;
    }
    InterlockedIncrement(&g_state.renderEventCount);
    if (g_state.gfxD3D11 != NULL && g_state.hasDevice == 0)
    {
        /* Called on the render thread, which is where GetDevice() is legal. */
        ID3D11Device* device = g_state.gfxD3D11->GetDevice();
        if (device != NULL)
        {
            g_state.hasDevice = 1;
        }
    }
}

extern "C" void UNITY_INTERFACE_EXPORT UNITY_INTERFACE_API UnityPluginLoad(IUnityInterfaces* interfaces)
{
    char line[SLU_LOG_LEN];
    if (interfaces == NULL)
    {
        return;
    }
    g_state.ownerPid = GetCurrentProcessId();
    g_state.unityLog = interfaces->Get<IUnityLog>();
    g_state.unityGraphics = interfaces->Get<IUnityGraphics>();
    g_state.gfxD3D11 = interfaces->Get<IUnityGraphicsD3D11>();
    if (g_state.unityGraphics != NULL)
    {
        g_state.renderer = (int)g_state.unityGraphics->GetRenderer();
        g_gfxCallback = &slu_on_gfx_device_event;
        g_state.unityGraphics->RegisterDeviceEventCallback(g_gfxCallback);
    }
    std::snprintf(line, sizeof(line),
        "[native] UnityPluginLoad: IUnityLog=%d renderer=%d D3D11=%d",
        g_state.unityLog != NULL ? 1 : 0,
        g_state.renderer,
        g_state.gfxD3D11 != NULL ? 1 : 0);
    slu_push_log(line);
}

extern "C" void UNITY_INTERFACE_EXPORT UNITY_INTERFACE_API UnityPluginUnload()
{
    if (g_state.unityGraphics != NULL && g_gfxCallback != NULL)
    {
        g_state.unityGraphics->UnregisterDeviceEventCallback(g_gfxCallback);
    }
    g_gfxCallback = NULL;
    g_state.unityLog = NULL;
    g_state.unityGraphics = NULL;
    g_state.gfxD3D11 = NULL;
}

/* ------------------------------------------------------------------------- */
/* Host face (Unity C# / verification harness)                                */
/* ------------------------------------------------------------------------- */

SLU_API const char* slu_version(void)
{
    return "slang-unity-native/2.0";
}

SLU_API void* slu_get_render_event_func(void)
{
    return (void*)&slu_on_render_event;
}

SLU_API int slu_diag(int* out6)
{
    if (out6 == NULL)
    {
        return 0;
    }
    slu_lock();
    out6[0] = (g_state.unityLog != NULL && slu_engine_owned()) ? 1 : 0;
    out6[1] = g_state.renderer;
    out6[2] = g_state.hasDevice;
    out6[3] = (int)g_state.renderEventCount;
    out6[4] = g_state.frameCount;
    out6[5] = g_state.gfxEvents;
    slu_unlock();
    return SLU_DIAG_COUNT;
}

SLU_API void slu_reset(void)
{
    slu_lock();
    std::memset(&g_state, 0, sizeof(g_state));
    g_state.spin = 0.0;
    g_state.baseY = 1.0;
    g_state.colorR = 1.0;
    g_state.colorG = 1.0;
    g_state.colorB = 1.0;
    g_state.posY = 1.0;
    slu_unlock();
}

/* Boot runs the module once in the full CLI binary, which performs the
 * complete assembly rewrite pass and resolves Core/Std module references
 * from <exe>/lib. The child shares state with this process through the
 * .slushare section of the very same DLL path. */
static int slu_run_vm_child(const char* slbPath)
{
    char dllPath[MAX_PATH];
    char exePath[MAX_PATH];
    char cmd[2048];
    char* slash;
    STARTUPINFOA si;
    PROCESS_INFORMATION pi;
    DWORD code = 0;
    HMODULE self = NULL;

    if (!GetModuleHandleExA(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
                            GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                            (LPCSTR)&slu_run_vm_child, &self) || self == NULL)
    {
        return -7;
    }
    if (GetModuleFileNameA(self, dllPath, MAX_PATH) == 0) { return -7; }
    slash = std::strrchr(dllPath, '\\');
    if (slash == NULL) { return -7; }
    std::snprintf(exePath, sizeof(exePath), "%.*s\\csimple_lang.exe",
                  (int)(slash - dllPath), dllPath);
    std::snprintf(cmd, sizeof(cmd), "\"%s\" run --no-banner \"%s\"",
                  exePath, slbPath);

    ZeroMemory(&si, sizeof(si));
    si.cb = sizeof(si);
    si.dwFlags = STARTF_USESHOWWINDOW;
    si.wShowWindow = SW_HIDE;
    ZeroMemory(&pi, sizeof(pi));
    if (!CreateProcessA(NULL, cmd, NULL, NULL, FALSE, CREATE_NO_WINDOW,
                        NULL, NULL, &si, &pi))
    {
        return -8;
    }
    WaitForSingleObject(pi.hProcess, INFINITE);
    GetExitCodeProcess(pi.hProcess, &code);
    CloseHandle(pi.hThread);
    CloseHandle(pi.hProcess);
    return (int)code;
}

/* Run an SLB module on the C VM. slbPathUtf8 is a NUL-terminated UTF-8 path. */
SLU_API int slu_boot(const char* slbPathUtf8)
{
    std::string slbPath;
    std::string baseDir;
    std::vector<unsigned char> bytes;
    std::ifstream in;
    std::streampos size;
    HMODULE vm;
    unsigned long long mtime;
    int rc;

    if (slbPathUtf8 == NULL || slbPathUtf8[0] == '\0')
    {
        slu_push_log("[native] slu_boot: empty slb path");
        return -1;
    }
    slbPath.assign(slbPathUtf8);
    size_t slash = slbPath.find_last_of("\\/");
    baseDir = (slash == std::string::npos) ? std::string(".") : slbPath.substr(0, slash);

    in.open(slbPath.c_str(), std::ios::binary);
    if (!in.is_open())
    {
        slu_push_log("[native] slu_boot: cannot open slb");
        return -2;
    }
    in.seekg(0, std::ios::end);
    size = in.tellg();
    in.seekg(0, std::ios::beg);
    if (size <= 0)
    {
        in.close();
        slu_push_log("[native] slu_boot: empty slb");
        return -3;
    }
    bytes.resize((size_t)size);
    in.read((char*)&bytes[0], size);
    if (in.gcount() != size)
    {
        in.close();
        slu_push_log("[native] slu_boot: short read");
        return -4;
    }
    in.close();

    vm = slu_load_vm_dll();
    if (vm == NULL)
    {
        slu_push_log("[native] slu_boot: csimple_lang_dll.dll not found");
        return -5;
    }
    /* IL2CPP / iOS / WebGL constraint from md/unity3d/08: interpreter only. */
    _putenv_s("SL_JIT", "0");

    /* Full CLI binary performs the complete assembly rewrite pass. */
    rc = slu_run_vm_child(slbPath.c_str());

    mtime = slu_file_mtime(slbPath.c_str());
    slu_lock();
    slu_copy_name(g_state.slbPath, SLU_PATH_LEN, slbPath.c_str());
    g_state.slbMtime = mtime;
    g_state.runCode = rc;
    g_state.booted = 1;
    g_state.needReload = 0;
    g_state.colorDirty = 1;
    slu_unlock();
    {
        char line[SLU_LOG_LEN];
        std::snprintf(line, sizeof(line), "[native] slu_boot rc=%d bytes=%lld vm=0x%p",
            rc, (long long)bytes.size(), (void*)vm);
        slu_push_log(line);
    }
    return rc;
}

/* ONE call per frame: advance + read state + (throttled) hot-reload check.
 * out9 = posX,posY,posZ, rotX,rotY,rotZ, colorR,colorG,colorB
 * returns SLU_FLAG_* bits. */
SLU_API int slu_frame(double dt, double* out9)
{
    int flags = 0;
    int frames = 0;
    unsigned long long mtime = 0;

    if (g_state.slbPath[0] != '\0' && (g_state.frameCount % 30) == 0)
    {
        mtime = slu_file_mtime(g_state.slbPath);
    }

    slu_lock();
    if (dt < 0.0) { dt = 0.0; }
    if (dt > 0.25) { dt = 0.25; }
    g_state.time = g_state.time + dt;
    g_state.angleY = std::fmod(g_state.angleY + g_state.spin * dt, 360.0);
    g_state.posX = g_state.baseX;
    g_state.posY = g_state.baseY + g_state.bobAmp * std::sin(g_state.time * g_state.bobSpeed);
    g_state.posZ = g_state.baseZ;
    g_state.frameCount = g_state.frameCount + 1;
    frames = g_state.frameCount;

    if (mtime != 0 && g_state.slbMtime != 0 && mtime != g_state.slbMtime)
    {
        g_state.slbMtime = mtime;
        g_state.needReload = 1;
    }
    if (g_state.needReload) { flags |= SLU_FLAG_RELOAD; g_state.needReload = 0; }
    if (g_state.colorDirty) { flags |= SLU_FLAG_COLOR; g_state.colorDirty = 0; }
    if (g_state.booted)     { flags |= SLU_FLAG_BOOTED; }
    if (g_state.unityLog != NULL && slu_engine_owned()) { flags |= SLU_FLAG_UNITYLOG; }

    if (out9 != NULL)
    {
        out9[0] = g_state.posX;
        out9[1] = g_state.posY;
        out9[2] = g_state.posZ;
        out9[3] = 0.0;
        out9[4] = g_state.angleY;
        out9[5] = 0.0;
        out9[6] = g_state.colorR;
        out9[7] = g_state.colorG;
        out9[8] = g_state.colorB;
    }
    slu_unlock();
    (void)frames;
    return flags;
}

/* ---- legacy split API (kept for v1 verification / compatibility) -------- */

SLU_API int slu_step(double dt)
{
    slu_frame(dt, NULL);
    return g_state.frameCount;
}

SLU_API int slu_get_state(double* out9)
{
    int frames;
    if (out9 == NULL)
    {
        return -1;
    }
    slu_lock();
    out9[0] = g_state.posX;
    out9[1] = g_state.posY;
    out9[2] = g_state.posZ;
    out9[3] = 0.0;
    out9[4] = g_state.angleY;
    out9[5] = 0.0;
    out9[6] = g_state.colorR;
    out9[7] = g_state.colorG;
    out9[8] = g_state.colorB;
    frames = g_state.frameCount;
    slu_unlock();
    (void)frames;
    return SLU_STATE_DOUBLES;
}

SLU_API int slu_pop_log(char* buf, int cap)
{
    int n = 0;
    if (buf == NULL || cap <= 0)
    {
        return 0;
    }
    buf[0] = '\0';
    slu_lock();
    if (g_state.logCount > 0)
    {
        const char* src = g_state.logs[g_state.logHead];
        size_t len = std::strlen(src);
        if (len > (size_t)(cap - 1))
        {
            len = (size_t)(cap - 1);
        }
        std::memcpy(buf, src, len);
        buf[len] = '\0';
        n = (int)len;
        g_state.logHead = (g_state.logHead + 1) % SLU_LOG_CAP;
        g_state.logCount = g_state.logCount - 1;
    }
    slu_unlock();
    return n;
}

SLU_API int slu_frame_count(void)
{
    return g_state.frameCount;
}

SLU_API int slu_last_run_code(void)
{
    return g_state.runCode;
}

/* ------------------------------------------------------------------------- */
/* SL face: called directly from .sl through @DllImport (SL -> C++)           */
/* ------------------------------------------------------------------------- */

SLU_API int slu_probe(void)
{
    return 20261109;
}

SLU_API int slu_log(const char* msg)
{
    if (msg == NULL)
    {
        return -1;
    }
    {
        char line[SLU_LOG_LEN];
        std::snprintf(line, sizeof(line), "[SL->C++] %s", msg);
        slu_push_log(line);
    }
    return 0;
}

SLU_API int slu_bind_target(const char* name)
{
    slu_lock();
    slu_copy_name(g_state.target, SLU_NAME_LEN, name);
    slu_unlock();
    {
        char line[SLU_LOG_LEN];
        std::snprintf(line, sizeof(line), "[SL->C++] bind target: %s",
            name == NULL ? "(null)" : name);
        slu_push_log(line);
    }
    return 0;
}

SLU_API int slu_set_spin(double degPerSec)
{
    slu_lock();
    g_state.spin = degPerSec;
    slu_unlock();
    return 0;
}

SLU_API int slu_set_color(double r, double g, double b)
{
    slu_lock();
    g_state.colorR = r;
    g_state.colorG = g;
    g_state.colorB = b;
    g_state.colorDirty = 1;
    slu_unlock();
    return 0;
}

SLU_API int slu_set_bob(double amplitude, double speed)
{
    slu_lock();
    g_state.bobAmp = amplitude;
    g_state.bobSpeed = speed;
    slu_unlock();
    return 0;
}

SLU_API int slu_set_base_position(double x, double y, double z)
{
    slu_lock();
    g_state.baseX = x;
    g_state.baseY = y;
    g_state.baseZ = z;
    g_state.posX = x;
    g_state.posY = y;
    g_state.posZ = z;
    slu_unlock();
    return 0;
}

SLU_API int slu_add_tag(const char* tag)
{
    slu_lock();
    slu_copy_name(g_state.lastTag, SLU_NAME_LEN, tag);
    slu_unlock();
    return 0;
}

SLU_API const char* slu_target(void)
{
    return g_state.target;
}

/* ------------------------------------------------------------------------- */
/* v3: Unity engine object mirror.                                            */
/* SL classes (GameObject / Transform / Camera / AudioSource / Renderer)     */
/* hold opaque handles; C++ owns the state table and emits ONE batched       */
/* snapshot per frame, which C# applies to real UnityEngine objects.          */
/* ------------------------------------------------------------------------- */

/* Object table shares the RWS section with g_state, so the short-lived
 * CLI child and the Unity host see one table (same DLL path -> shared page).
 * SlUObject / SLU_MAX_OBJECTS are declared above, before SlUState. */
__declspec(allocate(".slushare")) static SlUObject g_objects[SLU_MAX_OBJECTS] = {};

static SlUObject* slu_obj_by_handle(long long h)
{
    int i;
    if (h <= 0 || h > SLU_MAX_OBJECTS)
    {
        return NULL;
    }
    i = (int)h - 1;
    if (g_objects[i].used && g_objects[i].handle == h)
    {
        return &g_objects[i];
    }
    return NULL;
}

static SlUObject* slu_obj_find_or_create(const char* name, int createIfMissing)
{
    int i;
    int freeSlot = -1;
    SlUObject* o;
    if (name == NULL || name[0] == '\0')
    {
        return NULL;
    }
    for (i = 0; i < SLU_MAX_OBJECTS; i++)
    {
        if (g_objects[i].used && std::strcmp(g_objects[i].name, name) == 0)
        {
            return &g_objects[i];
        }
        if (!g_objects[i].used && freeSlot < 0)
        {
            freeSlot = i;
        }
    }
    if (!createIfMissing || freeSlot < 0)
    {
        return NULL;
    }
    o = &g_objects[freeSlot];
    std::memset(o, 0, sizeof(*o));
    o->used = 1;
    o->pending = 1;
    o->active = 1;
    o->activeDirty = 1;
    o->handle = (long long)(freeSlot + 1);
    o->scaleX = 1.0;
    o->scaleY = 1.0;
    o->scaleZ = 1.0;
    o->colorR = 1.0;
    o->colorG = 1.0;
    o->colorB = 1.0;
    o->colorA = 1.0;
    o->fov = 60.0;
    o->volume = 1.0;
    std::strncpy(o->name, name, SLU_OBJ_NAME_LEN - 1);
    return o;
}

/* ---- object / GameObject ------------------------------------------------ */

SLU_API long long slu_obj_find(const char* name)
{
    SlUObject* o;
    slu_lock();
    o = slu_obj_find_or_create(name, 1);
    slu_unlock();
    return o == NULL ? 0 : o->handle;
}

SLU_API long long slu_obj_create(const char* name)
{
    return slu_obj_find(name);
}

SLU_API int slu_obj_valid(long long h)
{
    return slu_obj_by_handle(h) == NULL ? 0 : 1;
}

SLU_API const char* slu_obj_name(long long h)
{
    SlUObject* o = slu_obj_by_handle(h);
    return o == NULL ? "" : o->name;
}

SLU_API int slu_obj_set_active(long long h, int active)
{
    SlUObject* o = slu_obj_by_handle(h);
    if (o == NULL) { return -1; }
    o->active = active != 0 ? 1 : 0;
    o->activeDirty = 1;
    return 0;
}

SLU_API int slu_obj_active(long long h)
{
    SlUObject* o = slu_obj_by_handle(h);
    return o == NULL ? 0 : o->active;
}

/* ---- Transform ---------------------------------------------------------- */

SLU_API int slu_tr_set_pos(long long h, double x, double y, double z)
{
    SlUObject* o = slu_obj_by_handle(h);
    if (o == NULL) { return -1; }
    o->posX = x; o->posY = y; o->posZ = z;
    o->baseX = x; o->baseY = y; o->baseZ = z;
    return 0;
}

SLU_API double slu_tr_pos(long long h, int axis)
{
    SlUObject* o = slu_obj_by_handle(h);
    if (o == NULL || axis < 0 || axis > 2) { return 0.0; }
    return axis == 0 ? o->posX : (axis == 1 ? o->posY : o->posZ);
}

SLU_API int slu_tr_set_rot(long long h, double x, double y, double z)
{
    SlUObject* o = slu_obj_by_handle(h);
    if (o == NULL) { return -1; }
    o->rotX = x; o->rotY = y; o->rotZ = z;
    return 0;
}

SLU_API double slu_tr_rot(long long h, int axis)
{
    SlUObject* o = slu_obj_by_handle(h);
    if (o == NULL || axis < 0 || axis > 2) { return 0.0; }
    return axis == 0 ? o->rotX : (axis == 1 ? o->rotY : o->rotZ);
}

SLU_API int slu_tr_set_scale(long long h, double x, double y, double z)
{
    SlUObject* o = slu_obj_by_handle(h);
    if (o == NULL) { return -1; }
    o->scaleX = x; o->scaleY = y; o->scaleZ = z;
    return 0;
}

SLU_API double slu_tr_scale(long long h, int axis)
{
    SlUObject* o = slu_obj_by_handle(h);
    if (o == NULL || axis < 0 || axis > 2) { return 0.0; }
    return axis == 0 ? o->scaleX : (axis == 1 ? o->scaleY : o->scaleZ);
}

SLU_API int slu_tr_set_spin(long long h, double degPerSec)
{
    SlUObject* o = slu_obj_by_handle(h);
    if (o == NULL) { return -1; }
    o->spin = degPerSec;
    return 0;
}

SLU_API int slu_tr_set_bob(long long h, double amplitude, double speed)
{
    SlUObject* o = slu_obj_by_handle(h);
    if (o == NULL) { return -1; }
    o->bobAmp = amplitude;
    o->bobSpeed = speed;
    return 0;
}

SLU_API int slu_tr_translate(long long h, double x, double y, double z)
{
    SlUObject* o = slu_obj_by_handle(h);
    if (o == NULL) { return -1; }
    o->posX += x; o->posY += y; o->posZ += z;
    o->baseX = o->posX; o->baseY = o->posY; o->baseZ = o->posZ;
    return 0;
}

/* ---- Camera ------------------------------------------------------------- */

SLU_API long long slu_cam_main(void)
{
    SlUObject* o;
    slu_lock();
    o = slu_obj_find_or_create("Main Camera", 1);
    slu_unlock();
    return o == NULL ? 0 : o->handle;
}

SLU_API int slu_cam_set_fov(long long h, double fov)
{
    SlUObject* o = slu_obj_by_handle(h);
    if (o == NULL) { return -1; }
    o->fov = fov;
    o->fovDirty = 1;
    return 0;
}

SLU_API double slu_cam_fov(long long h)
{
    SlUObject* o = slu_obj_by_handle(h);
    return o == NULL ? 60.0 : o->fov;
}

/* ---- AudioSource -------------------------------------------------------- */

SLU_API long long slu_audio_get(long long h)
{
    return slu_obj_by_handle(h) == NULL ? 0 : h;
}

SLU_API int slu_audio_play(long long h)
{
    SlUObject* o = slu_obj_by_handle(h);
    if (o == NULL) { return -1; }
    o->playing = 1;
    return 0;
}

SLU_API int slu_audio_stop(long long h)
{
    SlUObject* o = slu_obj_by_handle(h);
    if (o == NULL) { return -1; }
    o->playing = 0;
    return 0;
}

SLU_API int slu_audio_set_volume(long long h, double volume)
{
    SlUObject* o = slu_obj_by_handle(h);
    if (o == NULL) { return -1; }
    o->volume = volume;
    return 0;
}

SLU_API double slu_audio_volume(long long h)
{
    SlUObject* o = slu_obj_by_handle(h);
    return o == NULL ? 0.0 : o->volume;
}

SLU_API int slu_audio_playing(long long h)
{
    SlUObject* o = slu_obj_by_handle(h);
    return o == NULL ? 0 : o->playing;
}

/* ---- Renderer ----------------------------------------------------------- */

SLU_API int slu_renderer_set_color(long long h, double r, double g, double b)
{
    SlUObject* o = slu_obj_by_handle(h);
    if (o == NULL) { return -1; }
    o->colorR = r; o->colorG = g; o->colorB = b;
    o->colorDirty = 1;
    return 0;
}

SLU_API double slu_renderer_color(long long h, int axis)
{
    SlUObject* o = slu_obj_by_handle(h);
    if (o == NULL || axis < 0 || axis > 2) { return 0.0; }
    return axis == 0 ? o->colorR : (axis == 1 ? o->colorG : o->colorB);
}

/* ---- Time / Debug ------------------------------------------------------- */

SLU_API double slu_time_delta(void)
{
    return 1.0 / 60.0;
}

SLU_API double slu_time_total(void)
{
    return g_state.time;
}

SLU_API int slu_debug_log(const char* msg)
{
    return slu_log(msg);
}

/* ---- ONE batched call per frame (C# host only) --------------------------
 * out layout: out[0] = object count, then 20 doubles per object:
 *  0 handle      1 active      2 pending      3..5  position
 *  6..8 rotation(euler)        9..11 scale   12..15 color rgba
 * 16 fov        17 volume     18 playing     19 dirty flags
 * dirty flags: bit0 color, bit1 fov, bit2 active, bit3 playing
 * returns SLU_FLAG_* (hot reload etc). */
SLU_API int slu_frame_objects(double dt, double* out, int capacity)
{
    int i;
    int count = 0;
    int flags = 0;
    int need = 1 + SLU_OBJ_STRIDE * SLU_MAX_OBJECTS;
    unsigned long long mtime = 0;

    if (out == NULL || capacity < need)
    {
        return -1;
    }
    if (g_state.slbPath[0] != '\0' && (g_state.frameCount % 30) == 0)
    {
        mtime = slu_file_mtime(g_state.slbPath);
    }

    slu_lock();
    if (dt < 0.0) { dt = 0.0; }
    if (dt > 0.25) { dt = 0.25; }
    g_state.time = g_state.time + dt;
    g_state.frameCount = g_state.frameCount + 1;

    if (mtime != 0 && g_state.slbMtime != 0 && mtime != g_state.slbMtime)
    {
        g_state.slbMtime = mtime;
        g_state.needReload = 1;
    }
    if (g_state.needReload) { flags |= SLU_FLAG_RELOAD; g_state.needReload = 0; }
    if (g_state.unityLog != NULL && slu_engine_owned()) { flags |= SLU_FLAG_UNITYLOG; }

    for (i = 0; i < SLU_MAX_OBJECTS; i++)
    {
        SlUObject* o = &g_objects[i];
        double* p;
        int dirty;
        if (!o->used)
        {
            continue;
        }
        if (o->spin != 0.0)
        {
            o->rotY = std::fmod(o->rotY + o->spin * dt, 360.0);
        }
        if (o->bobAmp != 0.0)
        {
            o->posY = o->baseY + o->bobAmp * std::sin(g_state.time * o->bobSpeed);
        }
        p = out + 1 + count * SLU_OBJ_STRIDE;
        p[0]  = (double)o->handle;
        p[1]  = (double)o->active;
        p[2]  = (double)o->pending;
        p[3]  = o->posX;   p[4]  = o->posY;   p[5]  = o->posZ;
        p[6]  = o->rotX;   p[7]  = o->rotY;   p[8]  = o->rotZ;
        p[9]  = o->scaleX; p[10] = o->scaleY; p[11] = o->scaleZ;
        p[12] = o->colorR; p[13] = o->colorG; p[14] = o->colorB; p[15] = o->colorA;
        p[16] = o->fov;
        p[17] = o->volume;
        p[18] = (double)o->playing;
        dirty = 0;
        if (o->colorDirty)  { dirty |= 0x01; }
        if (o->fovDirty)    { dirty |= 0x02; }
        if (o->activeDirty) { dirty |= 0x04; }
        dirty |= 0x08;
        p[19] = (double)dirty;
        o->pending = 0;
        o->colorDirty = 0;
        o->fovDirty = 0;
        o->activeDirty = 0;
        count = count + 1;
    }
    out[0] = (double)count;
    slu_unlock();
    return flags;
}
