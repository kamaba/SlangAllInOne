// 卡通 / Cel Shading（URP / Universal RP）
// 阶梯化漫反射 + 硬边高光 + 背面外扩描边。
// 两个 Pass 的 UnityPerMaterial 布局刻意保持完全一致，避免 SRP Batcher 报错。
// 描边在对象空间沿法线外扩，非均匀缩放下宽度会变形。
Shader "SLang/URP/Toon"
{
    Properties
    {
        _BaseMap ("Albedo (RGB)", 2D) = "white" {}
        _BaseColor ("Tint", Color) = (1,1,1,1)
        _ShadowColor ("Shadow Tint", Color) = (0.55,0.55,0.7,1)
        _Steps ("明暗档数", Range(2,8)) = 3
        _Feather ("档位过渡", Range(0.001,0.3)) = 0.02
        _SpecColor ("Specular Color", Color) = (1,1,1,1)
        _Shininess ("Shininess", Range(1,256)) = 48
        _SpecThreshold ("高光阈值", Range(0,1)) = 0.5
        _Ambient ("Ambient 强度", Range(0,1)) = 0.15
        [Header(Outline)]
        _OutlineColor ("Outline Color", Color) = (0,0,0,1)
        _OutlineWidth ("Outline Width", Range(0,0.05)) = 0.008
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "Queue"="Geometry" "RenderPipeline"="UniversalPipeline" }
        LOD 100

        //--- 描边 Pass：Cull Front，沿法线外扩 ---
        Pass
        {
            Name "OUTLINE"
            Tags { "LightMode"="SRPDefaultUnlit" }
            Cull Front
            ZWrite On

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseMap_ST;
                float4 _BaseColor;
                float4 _ShadowColor;
                float4 _SpecColor;
                float4 _OutlineColor;
                float _Steps;
                float _Feather;
                float _Shininess;
                float _SpecThreshold;
                float _Ambient;
                float _OutlineWidth;
            CBUFFER_END

            struct Attributes { float4 positionOS : POSITION; float3 normalOS : NORMAL; };
            struct Varyings { float4 positionCS : SV_POSITION; };

            Varyings vert (Attributes input)
            {
                Varyings o;
                input.positionOS.xyz += input.normalOS * _OutlineWidth;
                o.positionCS = TransformObjectToHClip(input.positionOS.xyz);
                return o;
            }

            float4 frag (Varyings input) : SV_Target { return _OutlineColor; }
            ENDHLSL
        }

        //--- 主体 Pass：阶梯光照 ---
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

            // 与描边 Pass 完全相同的布局顺序。
            CBUFFER_START(UnityPerMaterial)
                float4 _BaseMap_ST;
                float4 _BaseColor;
                float4 _ShadowColor;
                float4 _SpecColor;
                float4 _OutlineColor;
                float _Steps;
                float _Feather;
                float _Shininess;
                float _SpecThreshold;
                float _Ambient;
                float _OutlineWidth;
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

                float3 color = albedo * (SampleSH(N) + _Ambient * 0.25);

                float4 shadowCoord = TransformWorldToShadowCoord(input.positionWS);
                Light mainLight = GetMainLight(shadowCoord);
                float3 L = normalize(mainLight.direction);
                float3 lightColor = mainLight.color * mainLight.shadowAttenuation
                                    * mainLight.distanceAttenuation;

                float ramp = ToonRampSmooth(dot(N, L), _Steps, _Feather);
                float3 litTint = lerp(_ShadowColor.rgb, float3(1,1,1), ramp);
                color += albedo * litTint * lightColor;

                // 硬边高光：step 直接切出亮斑，不做渐变。
                float3 H = normalize(L + V);
                float specRaw = pow(saturate(dot(N, H)), _Shininess);
                color += step(_SpecThreshold, specRaw)
                         * _SpecColor.rgb * lightColor
                         * step(0.0, dot(N, L));

                // 附加光用同一套阶梯规则。
                uint lightCount = GetAdditionalLightsCount();
                for (uint i = 0u; i < lightCount; ++i)
                {
                    Light addLight = GetAdditionalLight(i, input.positionWS);
                    float3 addColor = addLight.color * addLight.distanceAttenuation
                                      * addLight.shadowAttenuation;
                    float addRamp = ToonRampSmooth(dot(N, addLight.direction),
                                                   _Steps, _Feather);
                    color += albedo * lerp(_ShadowColor.rgb, float3(1,1,1), addRamp)
                             * addColor;
                }

                color = MixFog(color, input.fogFactor);
                return float4(color, 1.0);
            }
            ENDHLSL
        }
    }
    FallBack Off
}
