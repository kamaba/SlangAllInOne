// Lambert / Half-Lambert（URP / Universal RP）
// 带主光阴影 + 逐像素附加光循环 + 球谐环境光，SRP Batcher 兼容。
Shader "SLang/URP/Lambert"
{
    Properties
    {
        _BaseMap ("Albedo (RGB)", 2D) = "white" {}
        _BaseColor ("Tint", Color) = (1,1,1,1)
        [Toggle(_HALFLAMBERT_ON)] _HalfLambert ("Half-Lambert 柔化暗部", Float) = 0
        _Ambient ("Ambient 强度", Range(0,1)) = 0.15
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "Queue"="Geometry" "RenderPipeline"="UniversalPipeline" }
        LOD 100

        Pass
        {
            Name "UniversalForward"
            Tags { "LightMode"="UniversalForward" }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma shader_feature _HALFLAMBERT_ON
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile_fragment _ _SHADOWS_SOFT
            #pragma multi_compile_fog

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "SLangLighting.hlsl"

            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseMap_ST;
                float4 _BaseColor;
                float _Ambient;
            CBUFFER_END

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
                float2 uv : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 normalWS : TEXCOORD1;
                float3 positionWS : TEXCOORD2;
                float fogFactor : TEXCOORD3;
            };

            float3 ShadeOneLight(float3 albedo, float3 lightColor, float NdotL)
            {
                #ifdef _HALFLAMBERT_ON
                    return DiffuseHalfLambert(albedo, lightColor, NdotL);
                #else
                    return DiffuseLambert(albedo, lightColor, NdotL);
                #endif
            }

            Varyings vert (Attributes input)
            {
                Varyings o;
                VertexPositionInputs pos = GetVertexPositionInputs(input.positionOS.xyz);
                VertexNormalInputs nrm = GetVertexNormalInputs(input.normalOS);
                o.positionCS = pos.positionCS;
                o.positionWS = pos.positionWS;
                o.normalWS = nrm.normalWS;
                o.uv = TRANSFORM_TEX(input.uv, _BaseMap);
                o.fogFactor = ComputeFogFactor(pos.positionCS.z);
                return o;
            }

            float4 frag (Varyings input) : SV_Target
            {
                float3 albedo = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uv).rgb
                                * _BaseColor.rgb;
                float3 N = normalize(input.normalWS);

                // 主光：带阴影坐标，shadowAttenuation / distanceAttenuation 一并计入。
                float4 shadowCoord = TransformWorldToShadowCoord(input.positionWS);
                Light mainLight = GetMainLight(shadowCoord);
                float3 mainColor = mainLight.color * mainLight.shadowAttenuation
                                   * mainLight.distanceAttenuation;
                float3 color = ShadeOneLight(albedo, mainColor, dot(N, mainLight.direction));

                // 附加光（点光 / 聚光），逐像素循环。
                uint lightCount = GetAdditionalLightsCount();
                for (uint i = 0u; i < lightCount; ++i)
                {
                    Light addLight = GetAdditionalLight(i, input.positionWS);
                    float3 addColor = addLight.color * addLight.distanceAttenuation
                                      * addLight.shadowAttenuation;
                    color += ShadeOneLight(albedo, addColor, dot(N, addLight.direction));
                }

                // 环境光：球谐 + 可调常量，避免纯黑背光面。
                color += albedo * (SampleSH(N) + _Ambient * 0.25);

                color = MixFog(color, input.fogFactor);
                return float4(color, 1.0);
            }
            ENDHLSL
        }
    }
    FallBack Off
}
