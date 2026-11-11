/* =========================================================================
 * sl_texture.c —— 纹理注册表（对应 SL 侧 UnityRenderTexture）
 *
 * 全局纹理槽表 s_textures：句柄 1 起始，RGBA8 top-down 像素契约
 * （上传前统一翻行为 bottom-up 行序，交由 RHI 后端原样入显存——
 * GL t=0 与 D3D11 v=0 均指首行，采样语义跨后端一致）。
 * 文件解码走 WIC（PNG/JPEG/BMP/TIFF），零 SDK .lib 依赖
 * （windowscodecs/uuid 由 pragma 注入）。
 * ========================================================================= */
#include <wincodec.h>
#pragma comment(lib, "windowscodecs.lib")
#pragma comment(lib, "uuid.lib")
#include "sl_render_internal.h"

slr_texres s_textures[SLR_MAX_TEX];

slr_texres* tex_from_handle(int64_t h)
{
    int i = (int)(h - 1);
    if (h <= 0 || i >= SLR_MAX_TEX || !s_textures[i].used) return NULL;
    return &s_textures[i];
}

/* 纹理注册：top-down RGBA8 像素块 -> 翻行(bottom-up) -> RHI 上传 ->
 * 注册表占位。调用方须已 rhi_enter。返回句柄（0 = 失败）。 */
static int64_t texture_register(int w, int h, const unsigned char* topdown)
{
    int i;
    unsigned char* flipped;
    int stride, y;
    void* rhi_tex;
    stride = w * 4;
    flipped = (unsigned char*)malloc((size_t)stride * (size_t)h);
    if (!flipped) { set_error(SLR_E_MEMORY); return 0; }
    /* SL/WIC 契约 top-down：翻成 bottom-up（GL/D3D11 纹理首行语义）再上传 */
    for (y = 0; y < h; y++)
        memcpy(flipped + (size_t)(h - 1 - y) * stride, topdown + (size_t)y * stride, (size_t)stride);
    rhi_tex = g_rhi->texture_create(w, h, flipped);
    free(flipped);
    if (!rhi_tex) return 0;
    for (i = 0; i < SLR_MAX_TEX; i++)
    {
        if (s_textures[i].used) continue;
        memset(&s_textures[i], 0, sizeof(slr_texres));
        s_textures[i].used = 1; s_textures[i].w = w; s_textures[i].h = h;
        s_textures[i].rhi_tex = rhi_tex;
        return (int64_t)(i + 1);
    }
    g_rhi->texture_destroy(rhi_tex);
    set_error(SLR_E_LIMIT);
    return 0;
}

int64_t slr_texture_create_rgba(int w, int h, int64_t data_ptr)
{
    unsigned char* src;
    int64_t handle;
    if (w <= 0 || h <= 0 || !data_ptr) { set_error(SLR_E_BAD_PARAM); return 0; }
    if (!rhi_enter()) return 0;
    src = (unsigned char*)(intptr_t)data_ptr;
    handle = texture_register(w, h, src);
    rhi_exit();
    return handle;
}

/* 从图片文件创建纹理：WIC 解码 -> 转 32bppRGBA -> 上传。
 * path 为 UTF-8（SL string 契约）；支持 PNG/JPEG/BMP/TIFF 等 WIC 解码器。 */
int64_t slr_texture_load_file(const char* path_utf8)
{
    int64_t handle = 0;
    IWICImagingFactory* factory = NULL;
    IWICBitmapDecoder* decoder = NULL;
    IWICBitmapFrameDecode* frame = NULL;
    IWICFormatConverter* conv = NULL;
    UINT w = 0, h = 0;
    unsigned char* pixels = NULL;
    wchar_t wpath[MAX_PATH * 2];
    int wlen;
    HRESULT hr;
    int com_init = 0;

    if (!path_utf8 || !path_utf8[0]) { set_error(SLR_E_BAD_PARAM); return 0; }
    if (!s_ready) { set_error(SLR_E_NOT_INITIALIZED); return 0; }

    wlen = MultiByteToWideChar(CP_UTF8, 0, path_utf8, -1, wpath, (int)(sizeof(wpath) / sizeof(wchar_t)) - 1);
    if (wlen <= 0) { set_error_detail(SLR_E_IMAGE, "bad path encoding"); return 0; }

    /* COM 初始化：已初始化（任意 apartment）可直接用 */
    hr = CoInitializeEx(NULL, COINIT_MULTITHREADED);
    if (SUCCEEDED(hr)) com_init = 1;

    hr = CoCreateInstance(&CLSID_WICImagingFactory, NULL, CLSCTX_INPROC_SERVER,
                          &IID_IWICImagingFactory, (void**)&factory);
    if (FAILED(hr) || !factory) { set_error_detail(SLR_E_IMAGE, "WIC factory"); goto done; }

    hr = factory->lpVtbl->CreateDecoderFromFilename(factory, wpath, NULL, GENERIC_READ,
                                                    WICDecodeMetadataCacheOnDemand, &decoder);
    if (FAILED(hr) || !decoder) { set_error_detail(SLR_E_IMAGE, "open file"); goto done; }

    hr = decoder->lpVtbl->GetFrame(decoder, 0, &frame);
    if (FAILED(hr) || !frame) { set_error_detail(SLR_E_IMAGE, "frame"); goto done; }

    hr = factory->lpVtbl->CreateFormatConverter(factory, &conv);
    if (FAILED(hr) || !conv) { set_error_detail(SLR_E_IMAGE, "converter"); goto done; }

    hr = conv->lpVtbl->Initialize(conv, (IWICBitmapSource*)frame,
                                  &GUID_WICPixelFormat32bppRGBA,
                                  WICBitmapDitherTypeNone, NULL, 0.0,
                                  WICBitmapPaletteTypeCustom);
    if (FAILED(hr)) { set_error_detail(SLR_E_IMAGE, "convert format"); goto done; }

    hr = conv->lpVtbl->GetSize(conv, &w, &h);
    if (FAILED(hr) || w == 0 || h == 0 || w > 8192 || h > 8192)
    { set_error_detail(SLR_E_IMAGE, "size"); goto done; }

    pixels = (unsigned char*)malloc((size_t)w * (size_t)h * 4);
    if (!pixels) { set_error(SLR_E_MEMORY); goto done; }

    hr = conv->lpVtbl->CopyPixels(conv, NULL, w * 4, (UINT)w * (UINT)h * 4, pixels);
    if (FAILED(hr)) { set_error_detail(SLR_E_IMAGE, "copy pixels"); goto done; }

    if (!rhi_enter()) goto done;
    handle = texture_register((int)w, (int)h, pixels);
    rhi_exit();

done:
    if (pixels) free(pixels);
    if (conv) conv->lpVtbl->Release(conv);
    if (frame) frame->lpVtbl->Release(frame);
    if (decoder) decoder->lpVtbl->Release(decoder);
    if (factory) factory->lpVtbl->Release(factory);
    if (com_init) CoUninitialize();
    return handle;
}

int slr_texture_destroy(int64_t tex)
{
    slr_texres* t;
    if (!rhi_enter()) return 0;
    t = tex_from_handle(tex);
    if (!t) { set_error(SLR_E_TEXTURE); rhi_exit(); return 0; }
    g_rhi->texture_destroy(t->rhi_tex);
    memset(t, 0, sizeof(slr_texres));
    rhi_exit();
    return 1;
}

int slr_texture_count(void)
{
    int i, n = 0;
    for (i = 0; i < SLR_MAX_TEX; i++) if (s_textures[i].used) n++;
    return n;
}
