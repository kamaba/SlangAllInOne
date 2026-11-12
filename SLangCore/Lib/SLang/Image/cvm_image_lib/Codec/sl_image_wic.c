/* =========================================================================
 * sl_image_wic.c —— Codec：Windows Imaging Component（系统组件）
 *
 * 覆盖 stb 不支持的格式：TIFF / ICO / WebP（系统装了 WebP 编解码器时）
 * + JPEG 长尾兜底（渐进 12bpc 等）。编码补 TIFF。
 * 纯 C + vtbl 调用（.c 单元内 COM 必须 lpVtbl，见 sl_texture.c 同款）。
 * 依赖全部系统自带：windowscodecs.lib / uuid.lib / ole32.lib（pragma 注入）。
 * COM 初始化走 MTA；若线程已是别的 apartment（RPC_E_CHANGED_MODE）
 * 直接继续使用（与 sl_texture.c 一致），仅 SUCCEEDED 时才配对 Uninit。
 * ========================================================================= */
#include <wincodec.h>
#include <objidl.h>
#include <windows.h>
#pragma comment(lib, "windowscodecs.lib")
#pragma comment(lib, "uuid.lib")
#pragma comment(lib, "ole32.lib")

#include "../sl_image_internal.h"

/* WebP 容器 GUID（{989D266B-...}，本机 SDK 头未必声明，自带常量比对） */
static const GUID k_guidContainerWebp =
{ 0x989d266b, 0x5ac9, 0x47e4, { 0x90, 0x2e, 0xf6, 0xb3, 0xe7, 0xa2, 0xf6, 0xe6 } };

static int guid_eq(const GUID* a, const GUID* b)
{
    return memcmp(a, b, sizeof(GUID)) == 0;
}

/* 容器 GUID -> SLI_FMT_*（0=未知） */
static int container_to_fmt(const GUID* g)
{
    if (guid_eq(g, &GUID_ContainerFormatPng))  return SLI_FMT_PNG;
    if (guid_eq(g, &GUID_ContainerFormatJpeg)) return SLI_FMT_JPEG;
    if (guid_eq(g, &GUID_ContainerFormatBmp))  return SLI_FMT_BMP;
    if (guid_eq(g, &GUID_ContainerFormatGif))  return SLI_FMT_GIF;
    if (guid_eq(g, &GUID_ContainerFormatTiff)) return SLI_FMT_TIFF;
    if (guid_eq(g, &GUID_ContainerFormatIco))  return SLI_FMT_ICO;
    if (guid_eq(g, &k_guidContainerWebp))      return SLI_FMT_WEBP;
    return SLI_FMT_UNKNOWN;
}

int sli_wic_available(void)
{
    IWICImagingFactory* factory = NULL;
    HRESULT hr;
    int ok = 0;
    int com_init = 0;
    hr = CoInitializeEx(NULL, COINIT_MULTITHREADED);
    if (SUCCEEDED(hr)) com_init = 1;
    hr = CoCreateInstance(&CLSID_WICImagingFactory, NULL, CLSCTX_INPROC_SERVER,
                          &IID_IWICImagingFactory, (void**)&factory);
    if (SUCCEEDED(hr) && factory)
    {
        ok = 1;
        factory->lpVtbl->Release(factory);
    }
    if (com_init) CoUninitialize();
    return ok;
}

/* ---- 解码公共通道：decoder -> 首帧 -> 32bppRGBA -> 堆块 ---- */
static unsigned char* wic_decode_decoder(IWICBitmapDecoder* decoder,
                                          int* w, int* h, int* src_fmt)
{
    IWICImagingFactory* factory = NULL;
    IWICBitmapFrameDecode* frame = NULL;
    IWICFormatConverter* conv = NULL;
    GUID container;
    UINT ww = 0, hh = 0;
    unsigned char* pixels = NULL;
    HRESULT hr;

    hr = decoder->lpVtbl->GetContainerFormat(decoder, &container);
    if (FAILED(hr)) { sli_set_error_detail(SLI_E_DECODE, "wic container"); goto done; }
    *src_fmt = container_to_fmt(&container);

    hr = decoder->lpVtbl->GetFrame(decoder, 0, &frame);
    if (FAILED(hr) || !frame) { sli_set_error_detail(SLI_E_DECODE, "wic frame"); goto done; }

    hr = CoCreateInstance(&CLSID_WICImagingFactory, NULL, CLSCTX_INPROC_SERVER,
                          &IID_IWICImagingFactory, (void**)&factory);
    if (FAILED(hr) || !factory) { sli_set_error_detail(SLI_E_DECODE, "wic factory"); goto done; }

    hr = factory->lpVtbl->CreateFormatConverter(factory, &conv);
    if (FAILED(hr) || !conv) { sli_set_error_detail(SLI_E_DECODE, "wic converter"); goto done; }

    hr = conv->lpVtbl->Initialize(conv, (IWICBitmapSource*)frame,
                                   &GUID_WICPixelFormat32bppRGBA,
                                   WICBitmapDitherTypeNone, NULL, 0.0,
                                   WICBitmapPaletteTypeCustom);
    if (FAILED(hr)) { sli_set_error_detail(SLI_E_DECODE, "wic convert format"); goto done; }

    hr = conv->lpVtbl->GetSize(conv, &ww, &hh);
    if (FAILED(hr) || ww == 0 || hh == 0 ||
        ww > SLI_MAX_DIM || hh > SLI_MAX_DIM ||
        (int64_t)ww * (int64_t)hh > (int64_t)SLI_MAX_PIXELS)
    {
        sli_set_error_detail(SLI_E_DECODE, "wic size %ux%u", (unsigned)ww, (unsigned)hh);
        goto done;
    }

    pixels = (unsigned char*)malloc((size_t)ww * (size_t)hh * 4);
    if (!pixels) { sli_set_error(SLI_E_MEMORY); goto done; }

    hr = conv->lpVtbl->CopyPixels(conv, NULL, (UINT)ww * 4,
                                  (UINT)ww * (UINT)hh * 4, pixels);
    if (FAILED(hr))
    {
        sli_set_error_detail(SLI_E_DECODE, "wic copy pixels");
        free(pixels);
        pixels = NULL;
        goto done;
    }
    *w = (int)ww;
    *h = (int)hh;

done:
    if (conv) conv->lpVtbl->Release(conv);
    if (frame) frame->lpVtbl->Release(frame);
    if (factory) factory->lpVtbl->Release(factory);
    return pixels;
}

unsigned char* sli_wic_decode_file(const wchar_t* wpath, int* w, int* h, int* src_fmt)
{
    IWICImagingFactory* factory = NULL;
    IWICBitmapDecoder* decoder = NULL;
    unsigned char* pixels = NULL;
    HRESULT hr;
    int com_init = 0;

    *w = 0; *h = 0; *src_fmt = SLI_FMT_UNKNOWN;
    if (!wpath || !wpath[0]) { sli_set_error(SLI_E_BAD_PARAM); return NULL; }

    hr = CoInitializeEx(NULL, COINIT_MULTITHREADED);
    if (SUCCEEDED(hr)) com_init = 1;

    hr = CoCreateInstance(&CLSID_WICImagingFactory, NULL, CLSCTX_INPROC_SERVER,
                          &IID_IWICImagingFactory, (void**)&factory);
    if (FAILED(hr) || !factory) { sli_set_error_detail(SLI_E_DECODE, "wic factory"); goto done; }

    hr = factory->lpVtbl->CreateDecoderFromFilename(factory, wpath, NULL, GENERIC_READ,
                                                     WICDecodeMetadataCacheOnDemand, &decoder);
    if (FAILED(hr) || !decoder)
    {
        sli_set_error_detail(SLI_E_DECODE, "wic open file (0x%lx)", (unsigned long)hr);
        goto done;
    }
    pixels = wic_decode_decoder(decoder, w, h, src_fmt);

done:
    if (decoder) decoder->lpVtbl->Release(decoder);
    if (factory) factory->lpVtbl->Release(factory);
    if (com_init) CoUninitialize();
    return pixels;
}

unsigned char* sli_wic_decode_mem(const unsigned char* data, int64_t size,
                                   int* w, int* h, int* src_fmt)
{
    IWICImagingFactory* factory = NULL;
    IWICBitmapDecoder* decoder = NULL;
    IStream* stream = NULL;
    HGLOBAL hg = NULL;
    void* view = NULL;
    unsigned char* pixels = NULL;
    HRESULT hr;
    int com_init = 0;

    *w = 0; *h = 0; *src_fmt = SLI_FMT_UNKNOWN;
    if (!data || size <= 0) { sli_set_error(SLI_E_BAD_PARAM); return NULL; }

    hr = CoInitializeEx(NULL, COINIT_MULTITHREADED);
    if (SUCCEEDED(hr)) com_init = 1;

    /* 内存字节 -> IStream（GlobalAlloc 一份，流只读它） */
    hg = GlobalAlloc(GMEM_MOVEABLE, (SIZE_T)size);
    if (!hg) { sli_set_error(SLI_E_MEMORY); goto done; }
    view = GlobalLock(hg);
    if (!view) { GlobalFree(hg); sli_set_error(SLI_E_MEMORY); goto done; }
    memcpy(view, data, (size_t)size);
    GlobalUnlock(hg);

    hr = CreateStreamOnHGlobal(hg, TRUE, &stream);   /* TRUE: Release 时释放 hg */
    if (FAILED(hr) || !stream)
    {
        GlobalFree(hg);
        sli_set_error_detail(SLI_E_DECODE, "wic stream");
        goto done;
    }

    hr = CoCreateInstance(&CLSID_WICImagingFactory, NULL, CLSCTX_INPROC_SERVER,
                          &IID_IWICImagingFactory, (void**)&factory);
    if (FAILED(hr) || !factory) { sli_set_error_detail(SLI_E_DECODE, "wic factory"); goto done; }

    hr = factory->lpVtbl->CreateDecoderFromStream(factory, stream, NULL,
                                                   WICDecodeMetadataCacheOnDemand, &decoder);
    if (FAILED(hr) || !decoder)
    {
        sli_set_error_detail(SLI_E_DECODE, "wic decode stream (0x%lx) "
                             "[WebP 需系统装 WebP Image Extensions]",
                             (unsigned long)hr);
        goto done;
    }
    pixels = wic_decode_decoder(decoder, w, h, src_fmt);

done:
    if (decoder) decoder->lpVtbl->Release(decoder);
    if (factory) factory->lpVtbl->Release(factory);
    if (stream) stream->lpVtbl->Release(stream);
    if (com_init) CoUninitialize();
    return pixels;
}

/* ---- 编码 TIFF（32bppRGBA -> TIFF 文件字节）---- */
unsigned char* sli_wic_encode_tiff(const unsigned char* rgba,
                                   int w, int h, int64_t* out_size)
{
    IWICImagingFactory* factory = NULL;
    IWICBitmapEncoder* encoder = NULL;
    IWICBitmapFrameEncode* frame = NULL;
    IStream* stream = NULL;
    HGLOBAL hg = NULL;
    STATSTG stat;
    void* view = NULL;
    unsigned char* out = NULL;
    UINT wu = (UINT)w, hu = (UINT)h;
    WICPixelFormatGUID pf = GUID_WICPixelFormat32bppRGBA;
    HRESULT hr;
    int com_init = 0;

    *out_size = 0;
    if (!rgba || w <= 0 || h <= 0) { sli_set_error(SLI_E_BAD_PARAM); return NULL; }

    hr = CoInitializeEx(NULL, COINIT_MULTITHREADED);
    if (SUCCEEDED(hr)) com_init = 1;

    hr = CreateStreamOnHGlobal(NULL, TRUE, &stream);   /* 空流，encoder 写入 */
    if (FAILED(hr) || !stream) { sli_set_error_detail(SLI_E_ENCODE, "wic stream"); goto done; }

    hr = CoCreateInstance(&CLSID_WICImagingFactory, NULL, CLSCTX_INPROC_SERVER,
                          &IID_IWICImagingFactory, (void**)&factory);
    if (FAILED(hr) || !factory) { sli_set_error_detail(SLI_E_ENCODE, "wic factory"); goto done; }

    hr = factory->lpVtbl->CreateEncoder(factory, &GUID_ContainerFormatTiff, NULL, &encoder);
    if (FAILED(hr) || !encoder)
    {
        sli_set_error_detail(SLI_E_ENCODE, "wic tiff encoder");
        goto done;
    }

    hr = encoder->lpVtbl->Initialize(encoder, (IStream*)stream, WICBitmapEncoderNoCache);
    if (FAILED(hr)) { sli_set_error_detail(SLI_E_ENCODE, "wic tiff init"); goto done; }

    hr = encoder->lpVtbl->CreateNewFrame(encoder, &frame, NULL);
    if (FAILED(hr) || !frame) { sli_set_error_detail(SLI_E_ENCODE, "wic tiff frame"); goto done; }

    hr = frame->lpVtbl->Initialize(frame, NULL);
    if (FAILED(hr)) { sli_set_error_detail(SLI_E_ENCODE, "wic tiff frame init"); goto done; }

    hr = frame->lpVtbl->SetSize(frame, wu, hu);
    if (FAILED(hr)) { sli_set_error_detail(SLI_E_ENCODE, "wic tiff size"); goto done; }

    hr = frame->lpVtbl->SetPixelFormat(frame, &pf);
    if (FAILED(hr) || !guid_eq(&pf, &GUID_WICPixelFormat32bppRGBA))
    {
        sli_set_error_detail(SLI_E_ENCODE, "wic tiff pixel format");
        goto done;
    }

    hr = frame->lpVtbl->WritePixels(frame, hu, wu * 4,
                                    (UINT)w * (UINT)h * 4, (BYTE*)rgba);
    if (FAILED(hr)) { sli_set_error_detail(SLI_E_ENCODE, "wic tiff write (0x%lx)", (unsigned long)hr); goto done; }

    hr = frame->lpVtbl->Commit(frame);
    if (FAILED(hr)) { sli_set_error_detail(SLI_E_ENCODE, "wic tiff commit"); goto done; }
    hr = encoder->lpVtbl->Commit(encoder);
    if (FAILED(hr)) { sli_set_error_detail(SLI_E_ENCODE, "wic tiff commit2"); goto done; }

    /* 流内容拷出（GlobalLock 视图只读） */
    memset(&stat, 0, sizeof(stat));
    hr = stream->lpVtbl->Stat(stream, &stat, STATFLAG_NONAME);
    if (FAILED(hr) || stat.cbSize.QuadPart <= 0)
    {
        sli_set_error_detail(SLI_E_ENCODE, "wic tiff stat");
        goto done;
    }
    hr = GetHGlobalFromStream(stream, &hg);
    if (FAILED(hr) || !hg) { sli_set_error_detail(SLI_E_ENCODE, "wic tiff hglobal"); goto done; }
    view = GlobalLock(hg);
    if (!view) { sli_set_error_detail(SLI_E_ENCODE, "wic tiff lock"); goto done; }
    out = (unsigned char*)malloc((size_t)stat.cbSize.QuadPart);
    if (!out) { sli_set_error(SLI_E_MEMORY); goto done; }
    memcpy(out, view, (size_t)stat.cbSize.QuadPart);
    *out_size = (int64_t)stat.cbSize.QuadPart;
    GlobalUnlock(hg);
    hg = NULL;   /* 流持有（fDeleteOnRelease=TRUE），别二次释放 */

done:
    if (view && hg) GlobalUnlock(hg);
    if (frame) frame->lpVtbl->Release(frame);
    if (encoder) encoder->lpVtbl->Release(encoder);
    if (factory) factory->lpVtbl->Release(factory);
    if (stream) stream->lpVtbl->Release(stream);
    if (com_init) CoUninitialize();
    return out;
}
