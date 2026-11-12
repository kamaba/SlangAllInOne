//-----------------------------------------------------------------------------
// SLangLighting.hlsl - 纯 HLSL 光照函数库
//
// 不依赖任何 Unity 头文件，内置管线 (HLSLPROGRAM) 与 URP 都能直接编译。
// 用法：把本文件放在 shader 同目录，然后 #include "SLangLighting.hlsl"
// 也可以只把需要的函数抄进自己的 shader，做成零依赖的单文件。
//
// 覆盖的光照模型：
//   DiffuseLambert        Lambert 漫反射
//   DiffuseHalfLambert    Half-Lambert（包裹式漫反射，暗部不死黑）
//   SpecularPhong         Phong：反射向量 R 与视线 V 的夹角
//   SpecularBlinnPhong    Blinn-Phong /「半 Phong」：半程向量 H 与法线 N 的夹角
//   NormalizeBlinnPhong   Blinn-Phong 高光能量归一化系数
//   FresnelSchlick        Schlick 菲涅尔近似
//   RimLight              边缘光
//   ToonRamp              阶梯化漫反射（卡通渲染）
//   ToonRampSmooth        带柔和过渡的阶梯化
//-----------------------------------------------------------------------------
#ifndef SLANG_LIGHTING_HLSL_INCLUDED
#define SLANG_LIGHTING_HLSL_INCLUDED

//--- 漫反射 -----------------------------------------------------------------

float3 DiffuseLambert(float3 albedo, float3 lightColor, float NdotL)
{
    return albedo * lightColor * saturate(NdotL);
}

// Valve 在 Half-Life 2 里用的写法：把 [-1,1] 压到 [0,1] 再平方，
// 背光面仍有层次，适合卡通、皮肤、布料。
float3 DiffuseHalfLambert(float3 albedo, float3 lightColor, float NdotL)
{
    float wrap = NdotL * 0.5 + 0.5;
    return albedo * lightColor * (wrap * wrap);
}

//--- 高光 -------------------------------------------------------------------

// 经典 Phong。L 指向光源，所以入射方向是 -L；reflect 得到反射向量 R。
// R 与 V 越接近，高光越强。缺点：视角掠射时高光会突然断掉。
float3 SpecularPhong(float3 lightColor, float3 N, float3 L, float3 V,
                     float shininess, float intensity)
{
    float3 R = reflect(-L, N);
    float spec = pow(saturate(dot(R, V)), max(shininess, 1.0));
    return lightColor * spec * intensity;
}

// 半 Phong（Blinn-Phong）：H = normalize(L + V)，用 dot(N, H) 代替 dot(R, V)。
// 少一次 reflect、高光更宽更柔、大角度下不突变，是现在最常用的经验模型。
// 注意：同一个 shininess 下 Blinn-Phong 的高光比 Phong 更宽，
// 视觉对齐时通常把 Blinn 的指数设为 Phong 的 2~4 倍。
float3 SpecularBlinnPhong(float3 lightColor, float3 N, float3 L, float3 V,
                          float shininess, float intensity)
{
    float3 H = normalize(L + V);
    float spec = pow(saturate(dot(N, H)), max(shininess, 1.0));
    return lightColor * spec * intensity;
}

// 可选：能量归一化，指数变化时高光总亮度大致守恒。
float NormalizeBlinnPhong(float shininess)
{
    return (shininess + 8.0) / 8.0;
}

//--- 边缘 / 菲涅尔 -----------------------------------------------------------

float FresnelSchlick(float cosTheta, float f0)
{
    return f0 + (1.0 - f0) * pow(1.0 - saturate(cosTheta), 5.0);
}

float3 RimLight(float3 rimColor, float3 N, float3 V, float power, float strength)
{
    float rim = pow(1.0 - saturate(dot(N, V)), max(power, 0.001));
    return rimColor * rim * strength;
}

//--- 卡通阶梯 ---------------------------------------------------------------

// steps=3 时得到 0 / 0.5 / 1 三档明暗。
float ToonRamp(float NdotL, float steps)
{
    float s = max(steps, 2.0);
    float band = floor(saturate(NdotL) * (s - 1.0) + 0.0001);
    return saturate(band / (s - 1.0));
}

// 阶梯边界带一点过渡，feather 建议 0.01 ~ 0.3。
float ToonRampSmooth(float NdotL, float steps, float feather)
{
    float s = max(steps, 2.0);
    float v = saturate(NdotL) * (s - 1.0);
    float band = floor(v);
    float f = smoothstep(1.0 - max(feather, 0.001), 1.0, frac(v));
    return saturate((band + f) / (s - 1.0));
}

#endif // SLANG_LIGHTING_HLSL_INCLUDED
