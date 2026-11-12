// 半 Phong + 法线贴图（URP / Universal RP）——实际项目里最实用的一支
// 把世界空间 TBN 传到片元，每个光源的方向都在片元里逐光转到切线空间，
// 这样主光、附加光、视线和法线贴图始终处于同一坐标系。
// 法线贴图解码自带 DXT5nm/BC5 兼容处理，不依赖 SurfaceInput.hlsl。
Shader "SLang/URP/BlinnPhongNormalMap"
{
    Properties
    {
        _BaseMap ("Albedo (RGB)", 2D) = "white" {}
        [NoScaleOffset] _BumpMap ("Normal Map", 2D) = "bump" {}
        _BumpScale ("Normal Strength", Range(0,2)) = 1
        [Toggle(_NORMAL_PACKED_ON)] _NormalPacked ("法线贴图为压缩格式 BC5/DXT5nm", Float) = 1
        _BaseColor ("Tint", Color) = (1,1,1,1)
        _SpecColor ("Specular Color", Color) = (1,1,1,1)
        _Shininess ("Shininess", Range(1,256)) = 64
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
            #pragma shader_feature _NORMAL_PACKED_ON

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "SLangLighting.hlsl"

            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);
            TEXTURE2D(_BumpMap);
            SAMPLER(sampler_BumpMap);

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseMap_ST;
                float4 _BaseColor;
                float4 _SpecColor;
                float _BumpScale;
                float _NormalPacked;
                float _Shininess;
                float _SpecIntensity;
                float _Ambient;
            CBUFFER_END

            // Unity 把「Normal Map」类型纹理压成 BC5/DXT5nm 时，
            // 法线 x 存 alpha、y 存 green；普通 RGB 法线贴图则用 xyz。
            // 用材质开关显式选择，避免依赖各平台宏定义差异：
            // 贴图按 Normal Map 导入 -> 开；按 Default 导入的 RGB 法线 -> 关。
            float3 DecodeNormal(float4 packed)
            {
                float3 n;
                #ifdef _NORMAL_PACKED_ON
                    n.xy = packed.wy * 2.0 - 1.0;
                    n.z = sqrt(saturate(1.0 - dot(n.xy, n.xy)));
                #else
                    n = packed.xyz * 2.0 - 1.0;
                #endif
                return n;
            }

            // 单个光源在切线空间着色。L/V/N 都已是切线空间。
            float3 ShadeOneLight(float3 albedo, float3 N, float3 L, float3 V,
                                 float3 lightColor)
            {
                float NdotL = dot(N, L);
                float3 diffuse = DiffuseLambert(albedo, lightColor, NdotL);
                float3 spec = SpecularBlinnPhong(lightColor * _SpecColor.rgb,
                                                 N, L, V, _Shininess, _SpecIntensity)
                              * step(0.0, NdotL);
                return diffuse + spec;
            }

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
                float4 tangentOS : TANGENT;
                float2 uv : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 normalWS : TEXCOORD1;
                float3 tangentWS : TEXCOORD2;
                float3 bitangentWS : TEXCOORD3;
                float3 positionWS : TEXCOORD4;
                float fogFactor : TEXCOORD5;
            };

            Varyings vert (Attributes input)
            {
                Varyings o;
                VertexPositionInputs pos = GetVertexPositionInputs(input.positionOS.xyz);
                // 传 tangentOS 会自动算出 bitangentWS 并处理镜像缩放手性。
                VertexNormalInputs nrm = GetVertexNormalInputs(input.normalOS, input.tangentOS);
                o.positionCS = pos.positionCS;
                o.positionWS = pos.positionWS;
                o.normalWS = nrm.normalWS;
                o.tangentWS = nrm.tangentWS;
                o.bitangentWS = nrm.bitangentWS;
                o.uv = TRANSFORM_TEX(input.uv, _BaseMap);
                o.fogFactor = ComputeFogFactor(pos.positionCS.z);
                return o;
            }

            float4 frag (Varyings input) : SV_Target
            {
                float3 albedo = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uv).rgb
                                * _BaseColor.rgb;

                float3 geomN = normalize(input.normalWS);
                // 以 T/B/N 为「行」，mul(M, worldDir) 即投影到切线空间。
                float3x3 worldToTangent = float3x3(normalize(input.tangentWS),
                                                   normalize(input.bitangentWS),
                                                   geomN);

                float3 normalTS = DecodeNormal(
                    SAMPLE_TEXTURE2D(_BumpMap, sampler_BumpMap, input.uv));
                normalTS.xy *= _BumpScale;
                float3 N = normalize(normalTS);
                float3 V = normalize(mul(worldToTangent,
                                         _WorldSpaceCameraPos.xyz - input.positionWS));

                // 球谐环境光必须用世界空间法线。
                float3 color = albedo * (SampleSH(geomN) + _Ambient * 0.25);

                // 主光：世界方向 -> 切线空间，带阴影。
                float4 shadowCoord = TransformWorldToShadowCoord(input.positionWS);
                Light mainLight = GetMainLight(shadowCoord);
                float3 L = normalize(mul(worldToTangent, mainLight.direction));
                float3 mainColor = mainLight.color * mainLight.shadowAttenuation
                                   * mainLight.distanceAttenuation;
                color += ShadeOneLight(albedo, N, L, V, mainColor);

                // 附加光：每盏光各自转换方向，不能复用主光的 L。
                uint lightCount = GetAdditionalLightsCount();
                for (uint i = 0u; i < lightCount; ++i)
                {
                    Light addLight = GetAdditionalLight(i, input.positionWS);
                    float3 addL = normalize(mul(worldToTangent, addLight.direction));
                    float3 addColor = addLight.color * addLight.distanceAttenuation
                                      * addLight.shadowAttenuation;
                    color += ShadeOneLight(albedo, N, addL, V, addColor);
                }

                color = MixFog(color, input.fogFactor);
                return float4(color, 1.0);
            }
            ENDHLSL
        }
    }
    FallBack Off
}
