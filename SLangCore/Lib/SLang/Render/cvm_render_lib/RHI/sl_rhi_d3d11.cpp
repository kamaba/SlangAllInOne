/* =========================================================================
 * sl_rhi_d3d11.cpp —— RHI 后端：Windows Direct3D 11
 *
 * （C++ 编译单元：COM 接口原生 `obj->Method()` 调用；跨编译单元符号
 *   经 sl_render_internal.h 的 extern "C" 保持 C 链接）
 *
 * 与 GL 后端渲染完全一致效果的 D3D11 实现（同一像素契约）：
 *   - 零构建依赖：d3d11.dll / d3dcompiler_47.dll 运行期 LoadLibrary 解析
 *     （不链接 d3d11.lib，任何机器有系统 D3D11 即可用）；
 *   - HLSL SM5 着色器与 GLSL 六组逐组对应（FLAT/TEX/PFLAT/PTEX/BLIT/POST）
 *     + 清屏专用 CLEAR（D3D11 Clear* 只能整目标清，相机局部清屏用
 *     "清屏 quad"模拟：视口 = 相机矩形，clip z=1 覆写深度为远平面）；
 *   - PerDraw 常量缓冲（float4x4[64] + float4[64]，列主序内存与 GL
 *     std140 布局一致）+ PerObj 小缓冲传 uObjIndex（SM5 支持动态索引）；
 *   - 回读：staging 纹理 CopyResource + Map，行序天然 top-down 直接拷贝。
 *
 * 与 GL 的语义差异处理（保证同效果）：
 *   - 纹理行序：上传数据首行 = 图像底部（sl_texture.c 统一翻转），
 *     D3D11 纹理 v=0 即首行，采样结果与 GL t=0 一致；
 *   - 渲染目标纹理 v=0 = 图像顶部：全屏三角形 V 翻转（blit/post 恒等采样）；
 *   - 相机视口 GL 左下原点 -> D3D11 TopLeftY = target_h - (y + h)；
 *   - 深度语义：GL DEPTH_COMPONENT24 + LESS -> D24_UNORM_S8 + LESS。
 * ========================================================================= */
#include "sl_render_internal.h"
#include <d3d11.h>

/* ===================================================================== */
/* 运行期解析符号（零 .lib 依赖）                                          */
/* ===================================================================== */
typedef HRESULT (WINAPI *PFN_D3D11CreateDevice)(
    IDXGIAdapter*, D3D_DRIVER_TYPE, HMODULE, UINT,
    const D3D_FEATURE_LEVEL*, UINT, UINT,
    ID3D11Device**, D3D_FEATURE_LEVEL*, ID3D11DeviceContext**);

typedef HRESULT (WINAPI *PFN_D3DCompile)(
    LPCSTR, SIZE_T, LPCSTR, const D3D_SHADER_MACRO*, ID3DInclude*,
    LPCSTR, LPCSTR, UINT, UINT, ID3DBlob**, ID3DBlob**);

static PFN_D3D11CreateDevice p_D3D11CreateDevice = NULL;
static PFN_D3DCompile        p_D3DCompile = NULL;
static HMODULE s_hd3d = NULL;
static HMODULE s_hfxc = NULL;

/* ===================================================================== */
/* 后端私有状态                                                           */
/* ===================================================================== */
struct SlrRhiTarget           /* D3D11 渲染目标 = 颜色纹理 + RTV/SRV + 可选深度 */
{
    int w, h;
    ID3D11Texture2D* tex;                 /* 颜色纹理（回读 CopyResource 源）*/
    ID3D11RenderTargetView* rtv;
    ID3D11ShaderResourceView* srv;
    ID3D11Texture2D* dtex;                /* 深度纹理（可选）*/
    ID3D11DepthStencilView* dsv;
};

typedef struct                  /* D3D11 纹理 = 纹理 + SRV */
{
    ID3D11Texture2D* tex;
    ID3D11ShaderResourceView* srv;
} D3dTexture;

static ID3D11Device*        s_dev = NULL;
static ID3D11DeviceContext* s_ctx = NULL;
static D3D_FEATURE_LEVEL    s_fl = (D3D_FEATURE_LEVEL)0;
static CRITICAL_SECTION     s_lock;
static int                  s_lock_init = 0;
static char                 s_adapter_name[128] = "unknown";

/* 着色器（槽位与 SLR_PROG_* 对应）+ 清屏专用 */
static ID3D11VertexShader*   s_vs[SLR_PROG_COUNT];
static ID3D11PixelShader*    s_ps[SLR_PROG_COUNT];
static ID3D11VertexShader*   s_vs_clear = NULL;
static ID3D11PixelShader*    s_ps_clear = NULL;

/* 网格（0 三角 1 四边形 2 全屏三角[D3D V翻转] 3 v1 大三角）*/
static ID3D11Buffer* s_vb[4];
static UINT          s_vb_count[4];
/* 动态网格（mesh id = 4+slot；DYNAMIC 缓冲按需重建，Map 整块重传）*/
static ID3D11Buffer* s_vb_custom[SLR_CUSTOM_MESHES];
static UINT          s_vb_custom_count[SLR_CUSTOM_MESHES];
static UINT          s_vb_custom_cap[SLR_CUSTOM_MESHES];
/* 描述符槽表（SRV；管线层帧级写槽，free_shared 前向引用故声明于此）*/
static ID3D11ShaderResourceView* s_desc_srv[SLR_DESC_TEX_SLOTS];

/* 常量缓冲：b0 PerDraw / b1 PerObj / b2 PerV1 / b3 PerFx / b4 PerLight */
static ID3D11Buffer* s_cb_draw = NULL;   /* 7168B：mat4[64] + vec4[64] + wmat[128] */
static ID3D11Buffer* s_cb_obj = NULL;    /* 16B  : int uObjIndex + pad     */
static ID3D11Buffer* s_cb_v1 = NULL;     /* 80B  : float4x4 + float4       */
static ID3D11Buffer* s_cb_fx = NULL;     /* 16B  : 后处理参数 / 清屏色     */
static ID3D11Buffer* s_cb_light = NULL;  /* 96B  : LightBlock（光照块）    */

/* 管线状态对象 */
static ID3D11InputLayout*       s_layout = NULL;
static ID3D11SamplerState*      s_samp = NULL;
static ID3D11RasterizerState*   s_rs = NULL;
static ID3D11DepthStencilState* s_ds_opaque = NULL;  /* LESS + 写         */
static ID3D11DepthStencilState* s_ds_trans = NULL;   /* LESS + 不写       */
static ID3D11DepthStencilState* s_ds_clearW = NULL;  /* ALWAYS + 写       */
static ID3D11DepthStencilState* s_ds_clearNW = NULL; /* ALWAYS + 不写     */
static ID3D11BlendState*        s_bs_none = NULL;    /* 无混合            */
static ID3D11BlendState*        s_bs_alpha = NULL;   /* 标准透明混合      */
static ID3D11BlendState*        s_bs_nowrite = NULL; /* 颜色写屏蔽        */

/* 回读 staging 缓存（按尺寸复用）*/
static ID3D11Texture2D* s_stage = NULL;
static int s_stage_w = 0, s_stage_h = 0;

/* 常量缓冲上传辅助结构 */
typedef struct { int obj; float pad[3]; } D3dPerObj;               /* 16B  */
typedef struct { float mvp[16]; float color[4]; } D3dPerV1;        /* 80B  */

/* ===================================================================== */
/* HLSL 着色器（SM5；cbuffer 布局与 GLSL std140 逐字节一致，列主序）       */
/* ===================================================================== */
static const char* HLSL_VS_SCENE =
    "cbuffer PerV1 : register(b2) { float4x4 uMVP; float4 uColor; };\n"
    "struct VSIn { float2 pos : POSITION; float2 uv : TEXCOORD0; };\n"
    "struct VSOut { float4 sv : SV_POSITION; float2 uv : TEXCOORD0; };\n"
    "VSOut vsScene(VSIn i) { VSOut o; o.uv = i.uv;\n"
    "  o.sv = mul(uMVP, float4(i.pos, 0.0, 1.0)); return o; }\n";

static const char* HLSL_PS_FLAT =
    "cbuffer PerV1 : register(b2) { float4x4 uMVP; float4 uColor; };\n"
    "struct PSIn { float4 sv : SV_POSITION; float2 uv : TEXCOORD0; };\n"
    "float4 psFlat(PSIn i) : SV_Target { return uColor; }\n";

static const char* HLSL_PS_TEX =
    "cbuffer PerV1 : register(b2) { float4x4 uMVP; float4 uColor; };\n"
    "Texture2D tex0 : register(t0); SamplerState samp0 : register(s0);\n"
    "struct PSIn { float4 sv : SV_POSITION; float2 uv : TEXCOORD0; };\n"
    "float4 psTex(PSIn i) : SV_Target { return uColor * tex0.Sample(samp0, i.uv); }\n";

static const char* HLSL_VS_PIPE =
    "cbuffer PerDraw : register(b0) { float4x4 uMVP[64]; float4 uColor[64]; float4 uWMat[128]; float4 uSpec[64]; };\n"
    "cbuffer PerObj : register(b1) { int uObjIndex; float3 _pad; };\n"
    "struct VSIn { float2 pos : POSITION; float2 uv : TEXCOORD0; };\n"
    "struct VSOut { float4 sv : SV_POSITION; float2 uv : TEXCOORD0; float2 world : TEXCOORD1; float2 nrm : TEXCOORD2; };\n"
    "VSOut vsPipe(VSIn i) { VSOut o; o.uv = i.uv;\n"
    "  int k = uObjIndex * 2;\n"
    "  o.world = float2(dot(i.pos, uWMat[k].xy), dot(i.pos, uWMat[k].zw)) + uWMat[k + 1].xy;\n"
    "  o.nrm = uWMat[k + 1].zw;\n"
    "  o.sv = mul(uMVP[uObjIndex], float4(i.pos, 0.0, 1.0)); return o; }\n";

/* 管线片元光照（与 GL/GLES 后端公式逐字一致，跨后端同效果）*/
static const char* HLSL_PS_PIPE_FLAT =
    "cbuffer PerDraw : register(b0) { float4x4 uMVP[64]; float4 uColor[64]; float4 uWMat[128]; float4 uSpec[64]; };\n"
    "cbuffer PerObj : register(b1) { int uObjIndex; float3 _pad; };\n"
    "cbuffer PerLight : register(b4) {\n"
    "  float4 uAmbient; float4 uDirColor; float4 uDirDir;\n"
    "  float4 uSpotColor; float4 uSpotPosRange; float4 uSpotDirCos; };\n"
    "struct PSIn { float4 sv : SV_POSITION; float2 uv : TEXCOORD0; float2 world : TEXCOORD1; float2 nrm : TEXCOORD2; };\n"
    "float4 psPipeFlat(PSIn i) : SV_Target {\n"
    "  float4 base = uColor[uObjIndex];\n"
    "  float3 light = uAmbient.xxx;\n"
    "  if (uDirColor.a > 0.5) light += uDirColor.rgb * max(dot(i.nrm, uDirDir.xy), 0.0);\n"
    "  if (uSpotColor.a > 0.5) {\n"
    "    float2 toF = i.world - uSpotPosRange.xy;\n"
    "    float d = length(toF);\n"
    "    float att = clamp(1.0 - d / max(uSpotPosRange.z, 1e-4), 0.0, 1.0);\n"
    "    att *= att;\n"
    "    float ca = dot(toF, uSpotDirCos.xy) / max(d, 1e-4);\n"
    "    float ce = uSpotDirCos.z;\n"
    "    light += uSpotColor.rgb * att * smoothstep(ce, ce + (1.0 - ce) * 0.5, ca);\n"
    "  }\n"
    "  return float4(base.rgb * light, base.a); }\n";

static const char* HLSL_PS_PIPE_TEX =
    "cbuffer PerDraw : register(b0) { float4x4 uMVP[64]; float4 uColor[64]; float4 uWMat[128]; float4 uSpec[64]; };\n"
    "cbuffer PerObj : register(b1) { int uObjIndex; float3 _pad; };\n"
    "cbuffer PerLight : register(b4) {\n"
    "  float4 uAmbient; float4 uDirColor; float4 uDirDir;\n"
    "  float4 uSpotColor; float4 uSpotPosRange; float4 uSpotDirCos; };\n"
    "Texture2D tex0 : register(t0); SamplerState samp0 : register(s0);\n"
    "struct PSIn { float4 sv : SV_POSITION; float2 uv : TEXCOORD0; float2 world : TEXCOORD1; float2 nrm : TEXCOORD2; };\n"
    "float4 psPipeTex(PSIn i) : SV_Target {\n"
    "  float4 base = uColor[uObjIndex] * tex0.Sample(samp0, i.uv);\n"
    "  float3 light = uAmbient.xxx;\n"
    "  if (uDirColor.a > 0.5) light += uDirColor.rgb * max(dot(i.nrm, uDirDir.xy), 0.0);\n"
    "  if (uSpotColor.a > 0.5) {\n"
    "    float2 toF = i.world - uSpotPosRange.xy;\n"
    "    float d = length(toF);\n"
    "    float att = clamp(1.0 - d / max(uSpotPosRange.z, 1e-4), 0.0, 1.0);\n"
    "    att *= att;\n"
    "    float ca = dot(toF, uSpotDirCos.xy) / max(d, 1e-4);\n"
    "    float ce = uSpotDirCos.z;\n"
    "    light += uSpotColor.rgb * att * smoothstep(ce, ce + (1.0 - ce) * 0.5, ca);\n"
    "  }\n"
    "  return float4(base.rgb * light, base.a); }\n";

/* v3.4 Phong 光照模型（与 GL/GLES 后端公式逐字一致）：
 * v3.3 光照 + 伪 3D 高光（N=normalize(float3(nrm,0.75))，V=(0,0,1)，
 * R=reflect(-L,N)，spec=pow(max(dot(R,V),0),shin)*strength）*/
static const char* HLSL_PS_PHONG_FLAT =
    "cbuffer PerDraw : register(b0) { float4x4 uMVP[64]; float4 uColor[64]; float4 uWMat[128]; float4 uSpec[64]; };\n"
    "cbuffer PerObj : register(b1) { int uObjIndex; float3 _pad; };\n"
    "cbuffer PerLight : register(b4) {\n"
    "  float4 uAmbient; float4 uDirColor; float4 uDirDir;\n"
    "  float4 uSpotColor; float4 uSpotPosRange; float4 uSpotDirCos; };\n"
    "struct PSIn { float4 sv : SV_POSITION; float2 uv : TEXCOORD0; float2 world : TEXCOORD1; float2 nrm : TEXCOORD2; };\n"
    "float4 psPhongFlat(PSIn i) : SV_Target {\n"
    "  float4 base = uColor[uObjIndex];\n"
    "  float3 light = uAmbient.xxx;\n"
    "  float3 N = normalize(float3(i.nrm, 0.75));\n"
    "  float3 V = float3(0.0, 0.0, 1.0);\n"
    "  float2 sp = uSpec[uObjIndex].xy;\n"
    "  float shin = max(sp.y, 0.001);\n"
    "  if (uDirColor.a > 0.5) {\n"
    "    light += uDirColor.rgb * max(dot(i.nrm, uDirDir.xy), 0.0);\n"
    "    float3 L = normalize(float3(uDirDir.xy, 0.6));\n"
    "    float3 R = reflect(-L, N);\n"
    "    light += uDirColor.rgb * pow(max(dot(R, V), 0.0), shin) * sp.x;\n"
    "  }\n"
    "  if (uSpotColor.a > 0.5) {\n"
    "    float2 toF = i.world - uSpotPosRange.xy;\n"
    "    float d = length(toF);\n"
    "    float att = clamp(1.0 - d / max(uSpotPosRange.z, 1e-4), 0.0, 1.0);\n"
    "    att *= att;\n"
    "    float ca = dot(toF, uSpotDirCos.xy) / max(d, 1e-4);\n"
    "    float ce = uSpotDirCos.z;\n"
    "    float cone = smoothstep(ce, ce + (1.0 - ce) * 0.5, ca);\n"
    "    light += uSpotColor.rgb * att * cone;\n"
    "    float3 L2 = normalize(float3(-toF / max(d, 1e-4), 0.6));\n"
    "    float3 R2 = reflect(-L2, N);\n"
    "    light += uSpotColor.rgb * att * cone * pow(max(dot(R2, V), 0.0), shin) * sp.x;\n"
    "  }\n"
    "  return float4(base.rgb * light, base.a); }\n";

static const char* HLSL_PS_PHONG_TEX =
    "cbuffer PerDraw : register(b0) { float4x4 uMVP[64]; float4 uColor[64]; float4 uWMat[128]; float4 uSpec[64]; };\n"
    "cbuffer PerObj : register(b1) { int uObjIndex; float3 _pad; };\n"
    "cbuffer PerLight : register(b4) {\n"
    "  float4 uAmbient; float4 uDirColor; float4 uDirDir;\n"
    "  float4 uSpotColor; float4 uSpotPosRange; float4 uSpotDirCos; };\n"
    "Texture2D tex0 : register(t0); SamplerState samp0 : register(s0);\n"
    "struct PSIn { float4 sv : SV_POSITION; float2 uv : TEXCOORD0; float2 world : TEXCOORD1; float2 nrm : TEXCOORD2; };\n"
    "float4 psPhongTex(PSIn i) : SV_Target {\n"
    "  float4 base = uColor[uObjIndex] * tex0.Sample(samp0, i.uv);\n"
    "  float3 light = uAmbient.xxx;\n"
    "  float3 N = normalize(float3(i.nrm, 0.75));\n"
    "  float3 V = float3(0.0, 0.0, 1.0);\n"
    "  float2 sp = uSpec[uObjIndex].xy;\n"
    "  float shin = max(sp.y, 0.001);\n"
    "  if (uDirColor.a > 0.5) {\n"
    "    light += uDirColor.rgb * max(dot(i.nrm, uDirDir.xy), 0.0);\n"
    "    float3 L = normalize(float3(uDirDir.xy, 0.6));\n"
    "    float3 R = reflect(-L, N);\n"
    "    light += uDirColor.rgb * pow(max(dot(R, V), 0.0), shin) * sp.x;\n"
    "  }\n"
    "  if (uSpotColor.a > 0.5) {\n"
    "    float2 toF = i.world - uSpotPosRange.xy;\n"
    "    float d = length(toF);\n"
    "    float att = clamp(1.0 - d / max(uSpotPosRange.z, 1e-4), 0.0, 1.0);\n"
    "    att *= att;\n"
    "    float ca = dot(toF, uSpotDirCos.xy) / max(d, 1e-4);\n"
    "    float ce = uSpotDirCos.z;\n"
    "    float cone = smoothstep(ce, ce + (1.0 - ce) * 0.5, ca);\n"
    "    light += uSpotColor.rgb * att * cone;\n"
    "    float3 L2 = normalize(float3(-toF / max(d, 1e-4), 0.6));\n"
    "    float3 R2 = reflect(-L2, N);\n"
    "    light += uSpotColor.rgb * att * cone * pow(max(dot(R2, V), 0.0), shin) * sp.x;\n"
    "  }\n"
    "  return float4(base.rgb * light, base.a); }\n";

static const char* HLSL_VS_FULL =
    "struct VSIn { float2 pos : POSITION; float2 uv : TEXCOORD0; };\n"
    "struct VSOut { float4 sv : SV_POSITION; float2 uv : TEXCOORD0; };\n"
    "VSOut vsFull(VSIn i) { VSOut o; o.uv = i.uv;\n"
    "  o.sv = float4(i.pos, 0.0, 1.0); return o; }\n";

static const char* HLSL_PS_BLIT =
    "Texture2D tex0 : register(t0); SamplerState samp0 : register(s0);\n"
    "struct PSIn { float4 sv : SV_POSITION; float2 uv : TEXCOORD0; };\n"
    "float4 psBlit(PSIn i) : SV_Target { return tex0.Sample(samp0, i.uv); }\n";

static const char* HLSL_PS_POST =
    "cbuffer PerFx : register(b3) { float4 uParams; };\n"
    "Texture2D tex0 : register(t0); SamplerState samp0 : register(s0);\n"
    "struct PSIn { float4 sv : SV_POSITION; float2 uv : TEXCOORD0; };\n"
    "float4 psPost(PSIn i) : SV_Target {\n"
    "  float3 c = tex0.Sample(samp0, i.uv).rgb;\n"
    "  c *= uParams.x;\n"
    "  float l = dot(c, float3(0.299, 0.587, 0.114));\n"
    "  c = lerp(float3(l, l, l), c, uParams.y);\n"
    "  float2 d = i.uv - float2(0.5, 0.5);\n"
    "  c *= 1.0 - uParams.z * (d.x * d.x + d.y * d.y) * 2.67;\n"
    "  return float4(c, 1.0); }\n";

/* 清屏 quad：clip z=1 -> NDC z=1 -> 深度写为远平面 1.0（模拟局部清深度）*/
static const char* HLSL_VS_CLEAR =
    "struct VSIn { float2 pos : POSITION; float2 uv : TEXCOORD0; };\n"
    "struct VSOut { float4 sv : SV_POSITION; float2 uv : TEXCOORD0; };\n"
    "VSOut vsClear(VSIn i) { VSOut o; o.uv = i.uv;\n"
    "  o.sv = float4(i.pos, 1.0, 1.0); return o; }\n";

static const char* HLSL_PS_CLEAR =
    "cbuffer PerFx : register(b3) { float4 uColor; };\n"
    "struct PSIn { float4 sv : SV_POSITION; float2 uv : TEXCOORD0; };\n"
    "float4 psClear(PSIn i) : SV_Target { return uColor; }\n";

/* ===================================================================== */
/* 着色器编译辅助                                                         */
/* ===================================================================== */
static ID3DBlob* d3d_compile(const char* src, const char* entry, const char* target)
{
    ID3DBlob* code = NULL;
    ID3DBlob* err = NULL;
    HRESULT hr = p_D3DCompile(src, strlen(src), NULL, NULL, NULL,
                              entry, target, 0, 0, &code, &err);
    if (FAILED(hr))
    {
        if (err)
        {
            set_error_detail(SLR_E_SHADER, (const char*)err->GetBufferPointer());
            err->Release();
        }
        else
        {
            set_error_detail(SLR_E_SHADER, "D3DCompile failed (no message)");
        }
        if (code) code->Release();
        return NULL;
    }
    if (err) err->Release();
    return code;
}

/* 常量缓冲 Map(WRITE_DISCARD) 更新 */
static void d3d_cb_update(ID3D11Buffer* buf, const void* data, UINT bytes)
{
    D3D11_MAPPED_SUBRESOURCE mr;
    if (SUCCEEDED(s_ctx->Map(buf, 0, D3D11_MAP_WRITE_DISCARD, 0, &mr)))
    {
        memcpy(mr.pData, data, bytes);
        s_ctx->Unmap(buf, 0);
    }
}

/* 编译 + 创建 + 释放 blob（一体，防泄漏）*/
static ID3D11VertexShader* d3d_make_vs(const char* src, const char* entry)
{
    ID3DBlob* b = d3d_compile(src, entry, "vs_5_0");
    ID3D11VertexShader* vs = NULL;
    if (!b) return NULL;
    if (FAILED(s_dev->CreateVertexShader(b->GetBufferPointer(), b->GetBufferSize(), NULL, &vs)))
        set_error_detail(SLR_E_SHADER, "CreateVertexShader failed");
    b->Release();
    return vs;
}

static ID3D11PixelShader* d3d_make_ps(const char* src, const char* entry)
{
    ID3DBlob* b = d3d_compile(src, entry, "ps_5_0");
    ID3D11PixelShader* ps = NULL;
    if (!b) return NULL;
    if (FAILED(s_dev->CreatePixelShader(b->GetBufferPointer(), b->GetBufferSize(), NULL, &ps)))
        set_error_detail(SLR_E_SHADER, "CreatePixelShader failed");
    b->Release();
    return ps;
}

/* ===================================================================== */
/* 共享资源构建（设备成功后一次）                                          */
/* ===================================================================== */
static int d3d_make_shared(void)
{
    static const float tri[] = {          /* 与 GL 后端逐字节一致 */
        -0.5f, -0.35f, 0.0f, 0.0f,
         0.5f, -0.35f, 1.0f, 0.0f,
         0.0f,  0.65f, 0.5f, 1.0f,
    };
    static const float quad[] = {
        -0.5f, -0.5f, 0.0f, 0.0f,
         0.5f, -0.5f, 1.0f, 0.0f,
         0.5f,  0.5f, 1.0f, 1.0f,
        -0.5f, -0.5f, 0.0f, 0.0f,
         0.5f,  0.5f, 1.0f, 1.0f,
        -0.5f,  0.5f, 0.0f, 1.0f,
    };
    static const float fs_tri[] = {       /* D3D 专属：V 翻转（RT 行序差异）*/
        -1.0f, -1.0f, 0.0f, 1.0f,
         3.0f, -1.0f, 2.0f, 1.0f,
        -1.0f,  3.0f, 0.0f, -1.0f,
    };
    static const float ctx_tri[] = {
        -0.8f, -0.6f, 0.0f, 0.0f,
         0.8f, -0.6f, 1.0f, 0.0f,
         0.0f,  0.9f, 0.5f, 1.0f,
    };
    const float* datas[4] = { tri, quad, fs_tri, ctx_tri };
    const UINT   counts[4] = { 3, 6, 3, 3 };
    D3D11_INPUT_ELEMENT_DESC layout[2];
    D3D11_BUFFER_DESC bd;
    D3D11_SUBRESOURCE_DATA sd;
    D3D11_SAMPLER_DESC samp;
    D3D11_RASTERIZER_DESC rsd;
    D3D11_DEPTH_STENCIL_DESC dsd;
    D3D11_BLEND_DESC bsd;
    ID3DBlob* blob;
    ID3D11Buffer* cbs[4];
    int i;

    memset(s_vs, 0, sizeof(s_vs));
    memset(s_ps, 0, sizeof(s_ps));

    /* ---- 着色器（六组程序槽 + 清屏专用）---- */
    if (!(s_vs[SLR_PROG_FLAT] = d3d_make_vs(HLSL_VS_SCENE, "vsScene"))) return 0;
    if (!(s_ps[SLR_PROG_FLAT] = d3d_make_ps(HLSL_PS_FLAT, "psFlat"))) return 0;
    if (!(s_ps[SLR_PROG_TEX]  = d3d_make_ps(HLSL_PS_TEX, "psTex"))) return 0;
    if (!(s_vs[SLR_PROG_PFLAT] = d3d_make_vs(HLSL_VS_PIPE, "vsPipe"))) return 0;
    if (!(s_ps[SLR_PROG_PFLAT] = d3d_make_ps(HLSL_PS_PIPE_FLAT, "psPipeFlat"))) return 0;
    if (!(s_ps[SLR_PROG_PTEX]  = d3d_make_ps(HLSL_PS_PIPE_TEX, "psPipeTex"))) return 0;
    if (!(s_ps[SLR_PROG_PHONG_FLAT] = d3d_make_ps(HLSL_PS_PHONG_FLAT, "psPhongFlat"))) return 0;
    if (!(s_ps[SLR_PROG_PHONG_TEX]  = d3d_make_ps(HLSL_PS_PHONG_TEX, "psPhongTex"))) return 0;
    if (!(s_vs[SLR_PROG_BLIT] = d3d_make_vs(HLSL_VS_FULL, "vsFull"))) return 0;
    if (!(s_ps[SLR_PROG_BLIT] = d3d_make_ps(HLSL_PS_BLIT, "psBlit"))) return 0;
    if (!(s_ps[SLR_PROG_POST] = d3d_make_ps(HLSL_PS_POST, "psPost"))) return 0;
    if (!(s_vs_clear = d3d_make_vs(HLSL_VS_CLEAR, "vsClear"))) return 0;
    if (!(s_ps_clear = d3d_make_ps(HLSL_PS_CLEAR, "psClear"))) return 0;
    s_vs[SLR_PROG_TEX]  = s_vs[SLR_PROG_FLAT];    /* 同一 VS 复用 */
    s_vs[SLR_PROG_PTEX] = s_vs[SLR_PROG_PFLAT];
    s_vs[SLR_PROG_PHONG_FLAT] = s_vs[SLR_PROG_PFLAT];   /* Phong 复用管线 VS（world/nrm 输出已够用）*/
    s_vs[SLR_PROG_PHONG_TEX]  = s_vs[SLR_PROG_PFLAT];
    s_vs[SLR_PROG_POST] = s_vs[SLR_PROG_BLIT];

    /* ---- 输入布局（pos2 + uv2，stride 16B，与 GL 一致）---- */
    memset(layout, 0, sizeof(layout));
    layout[0].SemanticName = "POSITION";
    layout[0].Format = DXGI_FORMAT_R32G32_FLOAT;
    layout[0].InputSlotClass = D3D11_INPUT_PER_VERTEX_DATA;
    layout[1].SemanticName = "TEXCOORD";
    layout[1].Format = DXGI_FORMAT_R32G32_FLOAT;
    layout[1].AlignedByteOffset = 8;
    layout[1].InputSlotClass = D3D11_INPUT_PER_VERTEX_DATA;
    if (!(blob = d3d_compile(HLSL_VS_SCENE, "vsScene", "vs_5_0"))) return 0;
    if (FAILED(s_dev->CreateInputLayout(layout, 2, blob->GetBufferPointer(), blob->GetBufferSize(), &s_layout)))
    {
        blob->Release();
        set_error_detail(SLR_E_SHADER, "CreateInputLayout failed");
        return 0;
    }
    blob->Release();

    /* ---- 静态网格 ---- */
    memset(&bd, 0, sizeof(bd));
    bd.Usage = D3D11_USAGE_DEFAULT;
    bd.BindFlags = D3D11_BIND_VERTEX_BUFFER;
    for (i = 0; i < 4; i++)
    {
        bd.ByteWidth = counts[i] * 16;
        memset(&sd, 0, sizeof(sd));
        sd.pSysMem = datas[i];
        if (FAILED(s_dev->CreateBuffer(&bd, &sd, &s_vb[i])))
        {
            set_error_detail(SLR_E_SHADER, "mesh vertex buffer");
            return 0;
        }
        s_vb_count[i] = counts[i];
    }

    /* ---- 常量缓冲（DYNAMIC + WRITE_DISCARD）---- */
    bd.Usage = D3D11_USAGE_DYNAMIC;
    bd.BindFlags = D3D11_BIND_CONSTANT_BUFFER;
    bd.CPUAccessFlags = D3D11_CPU_ACCESS_WRITE;
    bd.ByteWidth = sizeof(SlrPerDraw);        /* PerDraw：mat4[64]+vec4[64]+wmat[128] */
    if (FAILED(s_dev->CreateBuffer(&bd, NULL, &s_cb_draw))) goto fail_cb;
    bd.ByteWidth = 16;                         /* PerObj / PerFx             */
    if (FAILED(s_dev->CreateBuffer(&bd, NULL, &s_cb_obj))) goto fail_cb;
    if (FAILED(s_dev->CreateBuffer(&bd, NULL, &s_cb_fx))) goto fail_cb;
    bd.ByteWidth = 80;                         /* PerV1：mat4 + vec4         */
    if (FAILED(s_dev->CreateBuffer(&bd, NULL, &s_cb_v1))) goto fail_cb;
    bd.ByteWidth = sizeof(SlrLightBlock);      /* PerLight：6 vec4 光照块    */
    if (FAILED(s_dev->CreateBuffer(&bd, NULL, &s_cb_light))) goto fail_cb;

    /* 槽位常驻绑定：b0 PerDraw / b1 PerObj / b2 PerV1 / b3 PerFx / b4 PerLight
     *（VS 与 PS 两阶段同名寄存器都用到 PerDraw/PerObj）*/
    cbs[0] = s_cb_draw; cbs[1] = s_cb_obj; cbs[2] = s_cb_v1; cbs[3] = s_cb_fx;
    s_ctx->VSSetConstantBuffers(0, 4, cbs);
    s_ctx->PSSetConstantBuffers(0, 4, cbs);
    cbs[0] = s_cb_light;
    s_ctx->VSSetConstantBuffers(4, 1, cbs);
    s_ctx->PSSetConstantBuffers(4, 1, cbs);

    /* ---- 采样器：线性 + CLAMP（与 GL 纹理参数一致）---- */
    memset(&samp, 0, sizeof(samp));
    samp.Filter = D3D11_FILTER_MIN_MAG_MIP_LINEAR;
    samp.AddressU = D3D11_TEXTURE_ADDRESS_CLAMP;
    samp.AddressV = D3D11_TEXTURE_ADDRESS_CLAMP;
    samp.AddressW = D3D11_TEXTURE_ADDRESS_CLAMP;
    samp.ComparisonFunc = D3D11_COMPARISON_NEVER;
    samp.MaxLOD = D3D11_FLOAT32_MAX;
    if (FAILED(s_dev->CreateSamplerState(&samp, &s_samp))) goto fail_cb;
    s_ctx->PSSetSamplers(0, 1, &s_samp);

    /* ---- 光栅化：实心 + 不剔除 + 无 scissor（GL 默认态）---- */
    memset(&rsd, 0, sizeof(rsd));
    rsd.FillMode = D3D11_FILL_SOLID;
    rsd.CullMode = D3D11_CULL_NONE;
    rsd.DepthClipEnable = TRUE;
    if (FAILED(s_dev->CreateRasterizerState(&rsd, &s_rs))) goto fail_cb;

    /* ---- 深度状态：不透明 LESS+写 / 透明 LESS+不写 / 清屏 ALWAYS ---- */
    memset(&dsd, 0, sizeof(dsd));
    dsd.DepthEnable = TRUE;
    dsd.DepthWriteMask = D3D11_DEPTH_WRITE_MASK_ALL;
    dsd.DepthFunc = D3D11_COMPARISON_LESS;
    if (FAILED(s_dev->CreateDepthStencilState(&dsd, &s_ds_opaque))) goto fail_cb;
    dsd.DepthWriteMask = D3D11_DEPTH_WRITE_MASK_ZERO;
    if (FAILED(s_dev->CreateDepthStencilState(&dsd, &s_ds_trans))) goto fail_cb;
    dsd.DepthWriteMask = D3D11_DEPTH_WRITE_MASK_ALL;
    dsd.DepthFunc = D3D11_COMPARISON_ALWAYS;
    if (FAILED(s_dev->CreateDepthStencilState(&dsd, &s_ds_clearW))) goto fail_cb;
    dsd.DepthWriteMask = D3D11_DEPTH_WRITE_MASK_ZERO;
    if (FAILED(s_dev->CreateDepthStencilState(&dsd, &s_ds_clearNW))) goto fail_cb;

    /* ---- 混合状态：无混合 / 标准透明 / 颜色写屏蔽（仅清深度用）---- */
    memset(&bsd, 0, sizeof(bsd));
    bsd.RenderTarget[0].RenderTargetWriteMask = D3D11_COLOR_WRITE_ENABLE_ALL;
    if (FAILED(s_dev->CreateBlendState(&bsd, &s_bs_none))) goto fail_cb;
    bsd.RenderTarget[0].BlendEnable = TRUE;
    bsd.RenderTarget[0].SrcBlend = D3D11_BLEND_SRC_ALPHA;
    bsd.RenderTarget[0].DestBlend = D3D11_BLEND_INV_SRC_ALPHA;
    bsd.RenderTarget[0].BlendOp = D3D11_BLEND_OP_ADD;
    /* GL glBlendFunc 对 RGB 与 A 用同一因子：精确对齐 alpha 通道行为 */
    bsd.RenderTarget[0].SrcBlendAlpha = D3D11_BLEND_SRC_ALPHA;
    bsd.RenderTarget[0].DestBlendAlpha = D3D11_BLEND_INV_SRC_ALPHA;
    bsd.RenderTarget[0].BlendOpAlpha = D3D11_BLEND_OP_ADD;
    bsd.RenderTarget[0].RenderTargetWriteMask = D3D11_COLOR_WRITE_ENABLE_ALL;
    if (FAILED(s_dev->CreateBlendState(&bsd, &s_bs_alpha))) goto fail_cb;
    memset(&bsd, 0, sizeof(bsd));
    bsd.RenderTarget[0].RenderTargetWriteMask = 0;
    if (FAILED(s_dev->CreateBlendState(&bsd, &s_bs_nowrite))) goto fail_cb;

    return 1;

fail_cb:
    set_error_detail(SLR_E_SHADER, "D3D11 state object creation failed");
    return 0;
}

static void d3d_free_shared(void)
{
    int i;
    /* s_vs[TEX]/[PTEX]/[POST] 为别名指针，先清空防重复 Release */
    s_vs[SLR_PROG_TEX] = NULL;
    s_vs[SLR_PROG_PTEX] = NULL;
    s_vs[SLR_PROG_POST] = NULL;
    for (i = 0; i < SLR_PROG_COUNT; i++)
    {
        if (s_ps[i]) { s_ps[i]->Release(); s_ps[i] = NULL; }
        if (s_vs[i]) { s_vs[i]->Release(); s_vs[i] = NULL; }
    }
    if (s_vs_clear) { s_vs_clear->Release(); s_vs_clear = NULL; }
    if (s_ps_clear) { s_ps_clear->Release(); s_ps_clear = NULL; }
    if (s_layout) { s_layout->Release(); s_layout = NULL; }
    for (i = 0; i < 4; i++)
    {
        if (s_vb[i]) { s_vb[i]->Release(); s_vb[i] = NULL; }
        s_vb_count[i] = 0;
    }
    for (i = 0; i < SLR_CUSTOM_MESHES; i++)
    {
        if (s_vb_custom[i]) { s_vb_custom[i]->Release(); s_vb_custom[i] = NULL; }
        s_vb_custom_count[i] = 0;
        s_vb_custom_cap[i] = 0;
    }
    if (s_cb_draw) { s_cb_draw->Release(); s_cb_draw = NULL; }
    if (s_cb_light) { s_cb_light->Release(); s_cb_light = NULL; }
    if (s_cb_obj) { s_cb_obj->Release(); s_cb_obj = NULL; }
    if (s_cb_v1) { s_cb_v1->Release(); s_cb_v1 = NULL; }
    if (s_cb_fx) { s_cb_fx->Release(); s_cb_fx = NULL; }
    if (s_samp) { s_samp->Release(); s_samp = NULL; }
    if (s_rs) { s_rs->Release(); s_rs = NULL; }
    if (s_ds_opaque) { s_ds_opaque->Release(); s_ds_opaque = NULL; }
    if (s_ds_trans) { s_ds_trans->Release(); s_ds_trans = NULL; }
    if (s_ds_clearW) { s_ds_clearW->Release(); s_ds_clearW = NULL; }
    if (s_ds_clearNW) { s_ds_clearNW->Release(); s_ds_clearNW = NULL; }
    if (s_bs_none) { s_bs_none->Release(); s_bs_none = NULL; }
    if (s_bs_alpha) { s_bs_alpha->Release(); s_bs_alpha = NULL; }
    if (s_bs_nowrite) { s_bs_nowrite->Release(); s_bs_nowrite = NULL; }
    if (s_stage) { s_stage->Release(); s_stage = NULL; }
    s_stage_w = s_stage_h = 0;
    /* 描述符槽表清空（纹理已先销毁，防悬空 SRV 指针）*/
    memset(s_desc_srv, 0, sizeof(s_desc_srv));
}

/* ===================================================================== */
/* 渲染目标 / 纹理                                                         */
/* ===================================================================== */
static SlrRhiTarget* d3d_target_create(int w, int h, int with_depth)
{
    D3D11_TEXTURE2D_DESC td;
    D3D11_SHADER_RESOURCE_VIEW_DESC sv;
    D3D11_DEPTH_STENCIL_VIEW_DESC dv;
    SlrRhiTarget* t = (SlrRhiTarget*)malloc(sizeof(SlrRhiTarget));
    if (!t) { set_error(SLR_E_MEMORY); return NULL; }
    memset(t, 0, sizeof(*t));
    t->w = w; t->h = h;

    memset(&td, 0, sizeof(td));
    td.Width = (UINT)w;
    td.Height = (UINT)h;
    td.MipLevels = 1;
    td.ArraySize = 1;
    td.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
    td.SampleDesc.Count = 1;
    td.Usage = D3D11_USAGE_DEFAULT;
    td.BindFlags = D3D11_BIND_RENDER_TARGET | D3D11_BIND_SHADER_RESOURCE;
    if (FAILED(s_dev->CreateTexture2D(&td, NULL, &t->tex))) goto fail;
    if (FAILED(s_dev->CreateRenderTargetView(t->tex, NULL, &t->rtv))) goto fail;

    memset(&sv, 0, sizeof(sv));
    sv.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
    sv.ViewDimension = D3D11_SRV_DIMENSION_TEXTURE2D;
    sv.Texture2D.MostDetailedMip = 0;
    sv.Texture2D.MipLevels = 1;
    if (FAILED(s_dev->CreateShaderResourceView(t->tex, &sv, &t->srv))) goto fail;

    if (with_depth)
    {
        td.Format = DXGI_FORMAT_D24_UNORM_S8_UINT;
        td.BindFlags = D3D11_BIND_DEPTH_STENCIL;
        if (FAILED(s_dev->CreateTexture2D(&td, NULL, &t->dtex))) goto fail;
        memset(&dv, 0, sizeof(dv));
        dv.Format = DXGI_FORMAT_D24_UNORM_S8_UINT;
        dv.ViewDimension = D3D11_DSV_DIMENSION_TEXTURE2D;
        if (FAILED(s_dev->CreateDepthStencilView(t->dtex, &dv, &t->dsv))) goto fail;
    }
    return t;

fail:
    if (t->dsv) t->dsv->Release();
    if (t->dtex) t->dtex->Release();
    if (t->srv) t->srv->Release();
    if (t->rtv) t->rtv->Release();
    if (t->tex) t->tex->Release();
    free(t);
    set_error_detail(SLR_E_FBO, "D3D11 render target creation failed");
    return NULL;
}

static void d3d_target_destroy(SlrRhiTarget* t)
{
    if (!t) return;
    if (t->dsv) t->dsv->Release();
    if (t->dtex) t->dtex->Release();
    if (t->srv) t->srv->Release();
    if (t->rtv) t->rtv->Release();
    if (t->tex) t->tex->Release();
    free(t);
}

/* rgba 首行 = 图像底部（sl_texture.c 已统一翻转）：
 * D3D11 纹理 v=0 即首行 -> 采样语义与 GL t=0 一致，直接建纹理带初值 */
static void* d3d_texture_create(int w, int h, const unsigned char* rgba)
{
    D3D11_TEXTURE2D_DESC td;
    D3D11_SUBRESOURCE_DATA sd;
    D3D11_SHADER_RESOURCE_VIEW_DESC sv;
    D3dTexture* t = (D3dTexture*)malloc(sizeof(D3dTexture));
    if (!t) { set_error(SLR_E_MEMORY); return NULL; }
    memset(t, 0, sizeof(*t));

    memset(&td, 0, sizeof(td));
    td.Width = (UINT)w;
    td.Height = (UINT)h;
    td.MipLevels = 1;
    td.ArraySize = 1;
    td.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
    td.SampleDesc.Count = 1;
    td.Usage = D3D11_USAGE_DEFAULT;
    td.BindFlags = D3D11_BIND_SHADER_RESOURCE;
    memset(&sd, 0, sizeof(sd));
    sd.pSysMem = rgba;
    sd.SysMemPitch = (UINT)(w * 4);
    if (FAILED(s_dev->CreateTexture2D(&td, &sd, &t->tex)))
    {
        free(t);
        set_error_detail(SLR_E_TEXTURE, "D3D11 texture creation failed");
        return NULL;
    }
    memset(&sv, 0, sizeof(sv));
    sv.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
    sv.ViewDimension = D3D11_SRV_DIMENSION_TEXTURE2D;
    sv.Texture2D.MostDetailedMip = 0;
    sv.Texture2D.MipLevels = 1;
    if (FAILED(s_dev->CreateShaderResourceView(t->tex, &sv, &t->srv)))
    {
        t->tex->Release();
        free(t);
        set_error_detail(SLR_E_TEXTURE, "D3D11 SRV creation failed");
        return NULL;
    }
    return t;
}

static void d3d_texture_destroy(void* tex)
{
    D3dTexture* t = (D3dTexture*)tex;
    if (!t) return;
    if (t->srv) t->srv->Release();
    if (t->tex) t->tex->Release();
    free(t);
}

/* ===================================================================== */
/* 管线 pass                                                              */
/* ===================================================================== */
static void d3d_unbind_srv(void)
{
    ID3D11ShaderResourceView* nullsrv = NULL;
    s_ctx->PSSetShaderResources(0, 1, &nullsrv);
}

static void d3d_full_viewport(int w, int h)
{
    D3D11_VIEWPORT vp;
    vp.TopLeftX = 0.0f;
    vp.TopLeftY = 0.0f;
    vp.Width = (FLOAT)w;
    vp.Height = (FLOAT)h;
    vp.MinDepth = 0.0f;
    vp.MaxDepth = 1.0f;
    s_ctx->RSSetViewports(1, &vp);
}

static void d3d_set_state(int transparent)
{
    s_ctx->RSSetState(s_rs);
    s_ctx->IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
    s_ctx->IASetInputLayout(s_layout);
    if (transparent)
    {
        s_ctx->OMSetBlendState(s_bs_alpha, NULL, 0xFFFFFFFF);
        s_ctx->OMSetDepthStencilState(s_ds_trans, 0);
    }
    else
    {
        s_ctx->OMSetBlendState(s_bs_none, NULL, 0xFFFFFFFF);
        s_ctx->OMSetDepthStencilState(s_ds_opaque, 0);
    }
}

/* 阶段 1：整幅清 + 不透明初始状态 */
static void d3d_begin_scene(SlrRhiTarget* t, int w, int h, const float* clear)
{
    d3d_unbind_srv();
    s_ctx->OMSetRenderTargets(1, &t->rtv, t->dsv);
    d3d_full_viewport(w, h);
    s_ctx->ClearRenderTargetView(t->rtv, clear);
    if (t->dsv) s_ctx->ClearDepthStencilView(t->dsv, D3D11_CLEAR_DEPTH, 1.0f, 0);
    d3d_set_state(0);
}

/* 阶段 7/9 逐相机：视口（GL 左下原点 -> D3D 顶部原点换算）+ 局部清屏。
 * Clear* 只能整目标清 -> 用"清屏 quad"模拟：视口即相机矩形，画 clip z=1
 * 的全屏三角，深度 ALWAYS 写 1.0（= 远平面），颜色按需写屏蔽。 */
static void d3d_camera_begin(SlrRhiTarget* t, int x, int y, int w, int h,
                             int target_h, int clear_flags, const float* clear)
{
    D3D11_VIEWPORT vp;
    float fx[4];
    UINT stride = 16, offset = 0;
    vp.TopLeftX = (FLOAT)x;
    vp.TopLeftY = (FLOAT)(target_h - (y + h));
    vp.Width = (FLOAT)w;
    vp.Height = (FLOAT)h;
    vp.MinDepth = 0.0f;
    vp.MaxDepth = 1.0f;
    d3d_unbind_srv();
    s_ctx->OMSetRenderTargets(1, &t->rtv, t->dsv);
    s_ctx->RSSetViewports(1, &vp);
    if (clear_flags)
    {
        fx[0] = clear[0]; fx[1] = clear[1]; fx[2] = clear[2]; fx[3] = clear[3];
        d3d_cb_update(s_cb_fx, fx, sizeof(fx));
        s_ctx->RSSetState(s_rs);
        s_ctx->IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
        s_ctx->IASetInputLayout(s_layout);
        s_ctx->OMSetBlendState((clear_flags & SLR_CLEAR_COLOR) ? s_bs_none : s_bs_nowrite,
                               NULL, 0xFFFFFFFF);
        s_ctx->OMSetDepthStencilState((clear_flags & SLR_CLEAR_DEPTH) ? s_ds_clearW : s_ds_clearNW, 0);
        s_ctx->VSSetShader(s_vs_clear, NULL, 0);
        s_ctx->PSSetShader(s_ps_clear, NULL, 0);
        s_ctx->IASetVertexBuffers(0, 1, &s_vb[2], &stride, &offset);
        s_ctx->Draw(3, 0);
    }
}

static void d3d_upload_perdraw(const void* data, int bytes)
{
    d3d_cb_update(s_cb_draw, data, (UINT)bytes);
}

/* 帧级光照块上传（PerLight，寄存器 b4；PFLAT/PTEX 消费）*/
static void d3d_upload_lights(const void* data, int bytes)
{
    d3d_cb_update(s_cb_light, data, (UINT)bytes);
}

/* ── 描述符表（SRV 槽表，DX11 原生形态）──────────────────────────────
 * desc_write_tex 写槽（管线层帧级填充），desc_bind_tex 绑定到像素
 * 着色器 t0——PSSetShaderResources 即 DX11 的描述符表绑定机制。
 * 槽表声明于静态状态区（free_shared 前向引用）。 */
static int d3d_desc_write_tex(int slot, void* tex)
{
    if (slot < 0 || slot >= SLR_DESC_TEX_SLOTS) return 0;
    s_desc_srv[slot] = tex ? ((D3dTexture*)tex)->srv : NULL;
    return 1;
}

static void d3d_desc_bind_tex(int slot)
{
    ID3D11ShaderResourceView* srv = (slot >= 0 && slot < SLR_DESC_TEX_SLOTS)
                                  ? s_desc_srv[slot] : NULL;
    s_ctx->PSSetShaderResources(0, 1, &srv);
}

static void d3d_draw_item(int prog, int slot, int mesh)
{
    D3dPerObj obj;
    UINT stride = 16, offset = 0;
    ID3D11Buffer* vb;
    UINT vcount;

    /* mesh 0..3 静态网格；4..4+SLR_CUSTOM_MESHES-1 动态网格（mesh_upload 上传）*/
    if (mesh >= 4)
    {
        int c = mesh - 4;
        if (c >= SLR_CUSTOM_MESHES || !s_vb_custom[c]) return; /* 未上传/越界跳过 */
        vb = s_vb_custom[c];
        vcount = s_vb_custom_count[c];
    }
    else
    {
        if (mesh < 0 || mesh > 3) return;
        vb = s_vb[mesh];
        vcount = s_vb_count[mesh];
    }
    if (prog == SLR_PROG_PFLAT || prog == SLR_PROG_PTEX ||
        prog == SLR_PROG_PHONG_FLAT || prog == SLR_PROG_PHONG_TEX)
    {
        obj.obj = slot;
        obj.pad[0] = obj.pad[1] = obj.pad[2] = 0.0f;
        d3d_cb_update(s_cb_obj, &obj, sizeof(obj));
    }
    /* 纹理已由 desc_bind_tex 绑定到 t0（SRV 描述符槽），此处不碰资源 */
    s_ctx->VSSetShader(s_vs[prog], NULL, 0);
    s_ctx->PSSetShader(s_ps[prog], NULL, 0);
    s_ctx->IASetVertexBuffers(0, 1, &vb, &stride, &offset);
    s_ctx->Draw(vcount, 0);
}

/* 动态网格上传（三角形列表 pos2+uv2，stride 16B）：容量不足时重建
 * DYNAMIC 顶点缓冲，之后 Map(WRITE_DISCARD) 整块重传 */
static int d3d_mesh_upload(int slot, const float* verts, int vert_count)
{
    D3D11_BUFFER_DESC bd;
    D3D11_MAPPED_SUBRESOURCE ms;
    UINT bytes;

    if (slot < 0 || slot >= SLR_CUSTOM_MESHES || !verts ||
        vert_count <= 0 || vert_count > SLR_CUSTOM_MAX_VERTS)
    {
        set_error(SLR_E_BAD_PARAM);
        return 0;
    }
    bytes = (UINT)(vert_count * 16);
    if (!s_vb_custom[slot] || s_vb_custom_cap[slot] < bytes)
    {
        if (s_vb_custom[slot]) { s_vb_custom[slot]->Release(); s_vb_custom[slot] = NULL; }
        memset(&bd, 0, sizeof(bd));
        bd.Usage = D3D11_USAGE_DYNAMIC;
        bd.BindFlags = D3D11_BIND_VERTEX_BUFFER;
        bd.CPUAccessFlags = D3D11_CPU_ACCESS_WRITE;
        bd.ByteWidth = (bytes + 0xFF) & ~0xFFu;   /* 256B 对齐减少重建次数 */
        if (FAILED(s_dev->CreateBuffer(&bd, NULL, &s_vb_custom[slot])))
        {
            set_error_detail(SLR_E_MEMORY, "custom vertex buffer");
            return 0;
        }
        s_vb_custom_cap[slot] = bd.ByteWidth;
    }
    if (FAILED(s_ctx->Map(s_vb_custom[slot], 0, D3D11_MAP_WRITE_DISCARD, 0, &ms)))
    {
        set_error_detail(SLR_E_MEMORY, "custom vb Map");
        return 0;
    }
    memcpy(ms.pData, verts, bytes);
    s_ctx->Unmap(s_vb_custom[slot], 0);
    s_vb_custom_count[slot] = (UINT)vert_count;
    return 1;
}

/* 阶段 11：scene -> post（enabled=0 纯拷贝）*/
static void d3d_post_process(SlrRhiTarget* dst, SlrRhiTarget* src, int w, int h,
                             int enabled, float bright, float sat, float vig)
{
    UINT stride = 16, offset = 0;
    float fx[4];
    d3d_unbind_srv();
    s_ctx->OMSetRenderTargets(1, &dst->rtv, NULL);
    d3d_full_viewport(w, h);
    s_ctx->RSSetState(s_rs);
    s_ctx->IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
    s_ctx->IASetInputLayout(s_layout);
    s_ctx->OMSetBlendState(s_bs_none, NULL, 0xFFFFFFFF);
    s_ctx->OMSetDepthStencilState(NULL, 0);
    if (enabled)
    {
        fx[0] = bright; fx[1] = sat; fx[2] = vig; fx[3] = 0.0f;
        d3d_cb_update(s_cb_fx, fx, sizeof(fx));
        s_ctx->VSSetShader(s_vs[SLR_PROG_BLIT], NULL, 0);
        s_ctx->PSSetShader(s_ps[SLR_PROG_POST], NULL, 0);
    }
    else
    {
        s_ctx->VSSetShader(s_vs[SLR_PROG_BLIT], NULL, 0);
        s_ctx->PSSetShader(s_ps[SLR_PROG_BLIT], NULL, 0);
    }
    s_ctx->PSSetShaderResources(0, 1, &src->srv);
    s_ctx->IASetVertexBuffers(0, 1, &s_vb[2], &stride, &offset);
    s_ctx->Draw(3, 0);
}

/* 阶段 12：post -> final 全屏拷贝 */
static void d3d_blit(SlrRhiTarget* dst, SlrRhiTarget* src, int w, int h)
{
    UINT stride = 16, offset = 0;
    d3d_unbind_srv();
    s_ctx->OMSetRenderTargets(1, &dst->rtv, NULL);
    d3d_full_viewport(w, h);
    s_ctx->RSSetState(s_rs);
    s_ctx->IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
    s_ctx->IASetInputLayout(s_layout);
    s_ctx->OMSetBlendState(s_bs_none, NULL, 0xFFFFFFFF);
    s_ctx->OMSetDepthStencilState(NULL, 0);
    s_ctx->VSSetShader(s_vs[SLR_PROG_BLIT], NULL, 0);
    s_ctx->PSSetShader(s_ps[SLR_PROG_BLIT], NULL, 0);
    s_ctx->PSSetShaderResources(0, 1, &src->srv);
    s_ctx->IASetVertexBuffers(0, 1, &s_vb[2], &stride, &offset);
    s_ctx->Draw(3, 0);
}

/* 阶段 13：回读（staging 天然 top-down，直接逐行拷）*/
static void d3d_readback(SlrRhiTarget* t, int w, int h, int64_t dst_ptr)
{
    unsigned char* buf = (unsigned char*)(intptr_t)dst_ptr;
    D3D11_TEXTURE2D_DESC td;
    D3D11_MAPPED_SUBRESOURCE mr;
    int y;

    if (s_stage_w != w || s_stage_h != h || !s_stage)
    {
        if (s_stage) s_stage->Release();
        s_stage = NULL;
        memset(&td, 0, sizeof(td));
        td.Width = (UINT)w;
        td.Height = (UINT)h;
        td.MipLevels = 1;
        td.ArraySize = 1;
        td.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
        td.SampleDesc.Count = 1;
        td.Usage = D3D11_USAGE_STAGING;
        td.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
        if (FAILED(s_dev->CreateTexture2D(&td, NULL, &s_stage)))
        {
            set_error_detail(SLR_E_MEMORY, "staging texture");
            return;
        }
        s_stage_w = w; s_stage_h = h;
    }
    s_ctx->OMSetRenderTargets(0, NULL, NULL);   /* 解绑 RT 再拷贝（整洁）*/
    s_ctx->CopyResource(s_stage, t->tex);
    if (SUCCEEDED(s_ctx->Map(s_stage, 0, D3D11_MAP_READ, 0, &mr)))
    {
        for (y = 0; y < h; y++)
            memcpy(buf + (size_t)y * (size_t)w * 4,
                   (unsigned char*)mr.pData + (size_t)y * mr.RowPitch,
                   (size_t)w * 4);
        s_ctx->Unmap(s_stage, 0);
    }
}

/* ===================================================================== */
/* v1 直连 pass                                                           */
/* ===================================================================== */
static void d3d_v1_clear(SlrRhiTarget* t, int w, int h, const float* clear)
{
    d3d_unbind_srv();
    s_ctx->OMSetRenderTargets(1, &t->rtv, t->dsv);
    d3d_full_viewport(w, h);
    s_ctx->ClearRenderTargetView(t->rtv, clear);
    if (t->dsv) s_ctx->ClearDepthStencilView(t->dsv, D3D11_CLEAR_DEPTH, 1.0f, 0);
}

static void d3d_v1_draw(SlrRhiTarget* t, int w, int h,
                        int prog, const float* mvp, const float* color, void* tex)
{
    D3dPerV1 v1;
    memcpy(v1.mvp, mvp, sizeof(v1.mvp));
    memcpy(v1.color, color, sizeof(v1.color));
    d3d_cb_update(s_cb_v1, &v1, sizeof(v1));

    d3d_unbind_srv();
    s_ctx->OMSetRenderTargets(1, &t->rtv, t->dsv);
    d3d_full_viewport(w, h);
    /* v1 显式状态：无混合、无深度（与 GL 后端 v1 一致）*/
    s_ctx->RSSetState(s_rs);
    s_ctx->IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
    s_ctx->IASetInputLayout(s_layout);
    s_ctx->OMSetBlendState(s_bs_none, NULL, 0xFFFFFFFF);
    s_ctx->OMSetDepthStencilState(NULL, 0);
    /* v1 直连纹理不走帧级描述符表（自带 tex 参数），此处直绑 t0 SRV */
    {
        ID3D11ShaderResourceView* srv = tex ? ((D3dTexture*)tex)->srv : NULL;
        s_ctx->PSSetShaderResources(0, 1, &srv);
    }
    d3d_draw_item(prog, 0, 3);   /* 网格 3 = v1 居中大三角 */
}

/* ===================================================================== */
/* 设备初始化 / 销毁                                                       */
/* ===================================================================== */
static int d3d_init(void)
{
    HRESULT hr;
    s_hd3d = LoadLibraryA("d3d11.dll");
    if (!s_hd3d) { set_error_detail(SLR_E_BACKEND, "d3d11.dll load failed"); return 0; }
    p_D3D11CreateDevice = (PFN_D3D11CreateDevice)GetProcAddress(s_hd3d, "D3D11CreateDevice");
    if (!p_D3D11CreateDevice)
    {
        set_error_detail(SLR_E_BACKEND, "D3D11CreateDevice not found");
        return 0;
    }
    hr = p_D3D11CreateDevice(NULL, D3D_DRIVER_TYPE_HARDWARE, NULL, 0,
                             NULL, 0, D3D11_SDK_VERSION, &s_dev, &s_fl, &s_ctx);
    if (FAILED(hr))
    {
        /* 回退 WARP 软件光栅器（保证无独显机器也可用）*/
        hr = p_D3D11CreateDevice(NULL, D3D_DRIVER_TYPE_WARP, NULL, 0,
                                 NULL, 0, D3D11_SDK_VERSION, &s_dev, &s_fl, &s_ctx);
    }
    if (FAILED(hr) || !s_dev || !s_ctx)
    {
        set_error_detail(SLR_E_CONTEXT, "D3D11 device creation failed");
        s_dev = NULL; s_ctx = NULL;
        return 0;
    }
    s_hfxc = LoadLibraryA("d3dcompiler_47.dll");
    if (!s_hfxc) s_hfxc = LoadLibraryA("d3dcompiler_43.dll");
    if (!s_hfxc) { set_error_detail(SLR_E_BACKEND, "d3dcompiler_47.dll load failed"); return 0; }
    p_D3DCompile = (PFN_D3DCompile)GetProcAddress(s_hfxc, "D3DCompile");
    if (!p_D3DCompile)
    {
        set_error_detail(SLR_E_BACKEND, "D3DCompile not found");
        return 0;
    }
    if (!s_lock_init)
    {
        InitializeCriticalSection(&s_lock);
        s_lock_init = 1;
    }
    return 1;
}

static void d3d_shutdown(void)
{
    if (s_ctx) { s_ctx->Release(); s_ctx = NULL; }
    if (s_dev) { s_dev->Release(); s_dev = NULL; }
    if (s_hd3d) { FreeLibrary(s_hd3d); s_hd3d = NULL; }
    if (s_hfxc) { FreeLibrary(s_hfxc); s_hfxc = NULL; }
    p_D3D11CreateDevice = NULL;
    p_D3DCompile = NULL;
    if (s_lock_init) { DeleteCriticalSection(&s_lock); s_lock_init = 0; }
}

static void d3d_info(char* renderer, int rcap, char* version, int vcap)
{
    const char* fl = "unknown";
    switch (s_fl)
    {
    case D3D_FEATURE_LEVEL_11_1: fl = "11.1"; break;
    case D3D_FEATURE_LEVEL_11_0: fl = "11.0"; break;
    case D3D_FEATURE_LEVEL_10_1: fl = "10.1"; break;
    case D3D_FEATURE_LEVEL_10_0: fl = "10.0"; break;
    default: break;
    }
    _snprintf(renderer, (size_t)rcap - 1, "Direct3D 11 (FL %s)", fl);
    renderer[rcap - 1] = 0;
    _snprintf(version, (size_t)vcap - 1, "D3D11 / %s", fl);
    version[vcap - 1] = 0;
}

static int d3d_enter(void)
{
    EnterCriticalSection(&s_lock);
    return 1;
}

static void d3d_exit(void) { LeaveCriticalSection(&s_lock); }

/* ===================================================================== */
/* vtable                                                                 */
/* ===================================================================== */
static const SlrRhi s_rhi_d3d11 =
{
    "d3d11",
    d3d_init,
    d3d_shutdown,
    d3d_info,
    d3d_enter,
    d3d_exit,
    d3d_make_shared,
    d3d_free_shared,
    d3d_target_create,
    d3d_target_destroy,
    d3d_texture_create,
    d3d_texture_destroy,
    d3d_mesh_upload,
    d3d_begin_scene,
    d3d_camera_begin,
    d3d_set_state,
    d3d_upload_perdraw,
    d3d_draw_item,
    d3d_post_process,
    d3d_blit,
    d3d_readback,
    d3d_v1_clear,
    d3d_v1_draw,
    d3d_desc_write_tex,
    d3d_desc_bind_tex,
    d3d_upload_lights,
};

const SlrRhi* slr_rhi_d3d11(void) { return &s_rhi_d3d11; }

