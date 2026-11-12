// 经典 Phong 光照模型（URP / Universal RP）
// 与 URP/BlinnPhong.shader 对比看高光形状差异；支持多光源与阴影。
Shader "SLang/URP/Phong"
{
    Properties
    {
        _BaseMap ("Albedo (RGB)", 2D) = "white" {}
        _BaseColor ("Tint", Color) = (1,1,1,1)
        _SpecColor ("Specular Color", Color) = (1,1,1,1)
        _Shininess ("Shininess 高光指数", Range(1,256)) = 32
        _SpecIntensity ("Spec Intensity", Range(0,2)) = 0.8
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
                float4 _SpecColor;
                float _Shininess;
                float _SpecIntensity;
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

            float3 ShadePhong(float3 albedo, float3 N, float3 L, float3 V,
                              float3 lightColor)
            {
                float NdotL = dot(N, L);
                float3 diffuse = DiffuseLambert(albedo, lightColor, NdotL);
                float3 spec = SpecularPhong(lightColor * _SpecColor.rgb,
                                            N, L, V, _Shininess, _SpecIntensity)
                              * step(0.0, NdotL);
                return diffuse + spec;
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
                float3 V = normalize(_WorldSpaceCameraPos.xyz - input.positionWS);

                float4 shadowCoord = TransformWorldToShadowCoord(input.positionWS);
                Light mainLight = GetMainLight(shadowCoord);
                float3 mainColor = mainLight.color * mainLight.shadowAttenuation
                                   * mainLight.distanceAttenuation;
                float3 color = ShadePhong(albedo, N, normalize(mainLight.direction),
                                          V, mainColor);

                uint lightCount = GetAdditionalLightsCount();
                for (uint i = 0u; i < lightCount; ++i)
                {
                    Light addLight = GetAdditionalLight(i, input.positionWS);
                    float3 addColor = addLight.color * addLight.distanceAttenuation
                                      * addLight.shadowAttenuation;
                    color += ShadePhong(albedo, N, normalize(addLight.direction),
                                        V, addColor);
                }

                color += albedo * (SampleSH(N) + _Ambient * 0.25);
                color = MixFog(color, input.fogFactor);
                return float4(color, 1.0);
            }
            ENDHLSL
        }
    }
    FallBack Off
}
