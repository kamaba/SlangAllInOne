//============================================================================
// SlBlinnPhong.hlsl —— Blinn-Phong（半程向量高光 + 菲涅尔加权边缘光）
// 提炼自 RenderTest/shader/BlinnPhong.shader（Unity URP），零 Unity 依赖。
//
// Unity 原型：ShadeBlinnPhong = DiffuseLambert + SpecularBlinnPhong
//   （H = normalize(L + V)，step(0, NdotL) 门控高光）；
//   边缘光 = RimLight(_RimColor, N, V, _RimPower, _RimStrength)
//            * (0.5 + 0.5 * FresnelSchlick(dot(N, V), 0.04))。
// 2D 管线映射：V = (0,0,1)；漫反射沿用内建 v3.3 基座（SceneBaseLight）；
//   高光把内建 FS_PHONG 的 R 换为 H（其余公式逐字一致）；
//   _RimColor 取 Unity 默认 (0.35, 0.7, 1.0) 固化进本文件。
//
// uSpec[i.obj] 分量语义（xy 与内建 FS_PHONG_*.xy 一致，zw 本效果新增）：
//   .x = 高光强度   .y = 光泽度（shininess）
//   .z = 边缘光强度（0 = 关闭，对应 Unity _RimStrength）
//   .w = 边缘光幂（对应 _RimPower，建议 0.5 ~ 8）
//
// 变体契约 / 重新生成：同 SlLambert.hlsl 头注释。
//============================================================================

struct SlVsIn
{
    float2 pos : POSITION;
    float2 uv  : TEXCOORD0;
};

struct SlPsIn
{
    float4 pos   : SV_POSITION;
    float2 uv    : TEXCOORD0;
    float2 world : TEXCOORD1;
    float2 nrm   : TEXCOORD2;
    nointerpolation int obj : TEXCOORD3;   // 实例槽号（flat 传递给 frag）
};

#ifndef SL_FLAT
Texture2D    uTex     : register(t0);
SamplerState uSampler : register(s0);
#endif

// 场景顶点：与内建 VS_PSCENE 数学逐字一致（PerDraw 布局见共享核心）；
// 实例槽 = uObjIndex 基槽 + SV_InstanceID（单 draw 多实例连续排布）
SlPsIn vert(SlVsIn i, uint iid : SV_InstanceID)
{
    SlPsIn o;
    o.uv = i.uv;
    int obj = uObjIndex + (int)iid;
    int k = obj * 2;
    o.world = float2(dot(i.pos, uWMat[k].xy), dot(i.pos, uWMat[k].zw))
              + uWMat[k + 1].xy;
    o.nrm = uWMat[k + 1].zw;
    o.pos = mul(uMVP[obj], float4(i.pos, 0.0, 1.0));
    o.obj = obj;
    return o;
}

// Blinn-Phong：v3.3 漫反射基座 + H 半程高光 + 菲涅尔加权边缘光
float4 frag(SlPsIn i) : SV_Target
{
#ifdef SL_FLAT
    float4 base = uColor[i.obj];
#else
    float4 base = uColor[i.obj] * uTex.Sample(uSampler, i.uv);
#endif
    float3 light = SceneBaseLight(i.nrm, i.world);

    float3 N = normalize(float3(i.nrm, 0.75));
    float3 V = float3(0.0, 0.0, 1.0);
    float4 sp = uSpec[i.obj];
    float shin = max(sp.y, 0.001);

    if (uDirColor.a > 0.5)
    {
        float3 L = normalize(float3(uDirDir.xy, 0.6));
        float ndl = dot(N, L);
        // N2a：直射高光挂 shadow map 衰减（漫反射在 SceneBaseLight 内已挂）
        float shAtten = ShadowAttenuation(i.world);
        if (ndl > 0.0)   // Unity：step(0, NdotL) 门控高光
        {
            float3 H = normalize(L + V);
            light += uDirColor.rgb * pow(max(dot(N, H), 0.0), shin) * sp.x * shAtten;
        }
    }
    if (uSpotColor.a > 0.5)
    {
        float cone = SpotConeAtt(i.world);
        float2 toF = i.world - uSpotPosRange.xy;
        float d = length(toF);
        float3 L2 = normalize(float3(-toF / max(d, 1e-4), 0.6));
        if (dot(N, L2) > 0.0)
        {
            float3 H2 = normalize(L2 + V);
            light += uSpotColor.rgb * cone
                      * pow(max(dot(N, H2), 0.0), shin) * sp.x;
        }
    }

    // 菲涅尔加权边缘光（Unity：RimLight * (0.5 + 0.5 * fres)，_RimColor 默认色）
    if (sp.z > 0.0)
    {
        float3 rimColor = float3(0.35, 0.70, 1.00);
        float fres = FresnelSchlick(saturate(dot(N, V)), 0.04);
        float rim = pow(1.0 - saturate(dot(N, V)), max(sp.w, 0.001));
        light += rimColor * (rim * sp.z) * (0.5 + 0.5 * fres);
    }
    return float4(base.rgb * light, base.a);
}
