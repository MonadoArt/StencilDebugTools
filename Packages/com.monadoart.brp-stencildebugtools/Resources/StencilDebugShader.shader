Shader "Unlit/StencilDebugShader"
{
    Properties {
    _NumberAtlas ("Number Atlas", 2D) = "white" {}
    _TileCount ("Tiling Amount X", Float) = 32
    _BgOpacity ("Background Opacity", Range(0,1)) = 0.2
    _NumberRotation ("Number Rotation (Degrees)", Range(-90,90)) = 0
    _ShowNumbers ("Show Numbers", Float) = 1
    }
    SubShader
    {
    Tags { "RenderType"="Transparent" "Queue" = "Transparent+1000" }
    LOD 100
    GrabPass {}

        CGINCLUDE
        #pragma vertex vert
        #pragma fragment frag
        #include "UnityCG.cginc"
        sampler2D _NumberAtlas;
        sampler2D _GrabTexture;
        float4 _NumberAtlas_TexelSize;
        float _TileCount;
        float _BgOpacity;
        float _NumberRotation;
        float _ShowNumbers;


        struct appdata {
            float4 vertex : POSITION;
            float2 uv : TEXCOORD0;
        };
        struct v2f {
            float2 uv : TEXCOORD0;
            float4 vertex : SV_POSITION;
            float4 screenPos : TEXCOORD1;
        };
        v2f vert (appdata v) {
            v2f o;
            o.vertex = UnityObjectToClipPos(v.vertex);
            o.uv = v.uv;
            o.screenPos = ComputeScreenPos(o.vertex);
            return o;
        }


        // Helper to get screen-space UV (0-1)
        float2 GetScreenUV(float4 screenPos) {
            return (screenPos.xy / screenPos.w);
        }

        // HSV to RGB conversion
        fixed3 HSVtoRGB(float h, float s, float v) {
            float4 K = float4(1.0, 2.0/3.0, 1.0/3.0, 3.0);
            float3 p = abs(frac(float3(h, h, h) + K.xyz) * 6.0 - K.www);
            return v * lerp(K.xxx, saturate(p - K.xxx), s);
        }

        fixed4 SampleNumber(float2 meshUV, int number, float2 screenUV) {
            // If _ShowNumbers < 0.5, only show background
            if (_ShowNumbers < 0.5) {
                fixed4 sceneCol = tex2D(_GrabTexture, screenUV);
                float baseHue = (number - 1) / 24.0;
                float hue = (number % 2 == 0) ? baseHue : fmod(baseHue + 0.5, 1.0);
                float sat = 0.8;
                float val = 1.0;
                fixed3 stencilColor = HSVtoRGB(hue, sat, val);
                fixed3 cellBg = lerp(sceneCol.rgb, stencilColor, _BgOpacity);
                return fixed4(cellBg, 1.0);
            }
            int atlasSize = 16; // 16x16 grid for 256 numbers
            // Apply rotation to meshUV for number orientation
            float angle = radians(_NumberRotation);
            float2 center = float2(0.5, 0.5);
            float2 uvRel = meshUV - center;
            float cosA = cos(angle);
            float sinA = sin(angle);
            float2 rotUV = float2(
                uvRel.x * cosA - uvRel.y * sinA,
                uvRel.x * sinA + uvRel.y * cosA
            ) + center;

            float2 tileUV = frac(rotUV * _TileCount); // tile across mesh
            int numX = number % atlasSize;
            int numY = atlasSize - 1 - (number / atlasSize);
            float2 cellUV = tileUV * (1.0 - _NumberAtlas_TexelSize.xy);
            float2 atlasUV = (float2(numX, numY) + cellUV + 0.5 * _NumberAtlas_TexelSize.xy) / atlasSize;
            fixed4 numCol = tex2D(_NumberAtlas, atlasUV);
            fixed4 sceneCol = tex2D(_GrabTexture, screenUV);
            // Procedural HSV color: 24 distinct hues, alternate opposite side for high contrast
            float baseHue = (number - 1) / 24.0;
            float hue = (number % 2 == 0) ? baseHue : fmod(baseHue + 0.5, 1.0);
            float sat = 0.8;
            float val = 1.0;
            fixed3 stencilColor = HSVtoRGB(hue, sat, val);
            // Fill cell with stencil color at adjustable opacity
            fixed3 cellBg = lerp(sceneCol.rgb, stencilColor, _BgOpacity);
            // Desaturate number color starting at 0.75 bg opacity, to 50% saturation at max
            float desatBlend = saturate((_BgOpacity - 0.75) / 0.25);
            float lum = dot(HSVtoRGB(hue, sat, val), float3(0.299, 0.587, 0.114));
            float numberSat;
            float numberVal = val;
            // theAdjust number color for visibility based on stencil background luminance
            float stencilLum = dot(stencilColor, float3(0.299, 0.587, 0.114));
            float intensity = abs(stencilLum - 0.5) * 2.0; // 0 (mid) to 1 (extreme)
            if (stencilLum < 0.5) {
                // Dark stencil color: lerp toward white (high value, low saturation)
                numberVal = lerp(numberVal, 1.0, intensity);
                numberSat = lerp(numberSat, 0.0, intensity);
            } else {
                // Bright stencil color: boost saturation and brightness for vivid numbers
                // Extra logic for green hues
                if (hue > 0.25 && hue < 0.45) {
                    numberVal = lerp(numberVal, 1.0, intensity);
                    numberSat = lerp(numberSat, 1.0, intensity);
                } else {
                    numberVal = lerp(numberVal, 1.0, intensity);
                    numberSat = lerp(numberSat, 1.0, intensity);
                }
            }
            // Transition number color from original to dark/saturated as bg opacity increases
            float transition = saturate((_BgOpacity - 0.6) / 0.4);
            float origSat = sat;
            float origVal = 0.8; // original brightness at 80%
            float targetSat = 1.0;
            float targetVal = 0.5;
            float lerpedSat = lerp(origSat, targetSat, transition);
            float lerpedVal = lerp(origVal, targetVal, transition);
            fixed3 numberColor = HSVtoRGB(hue, lerpedSat, lerpedVal);
            if (numCol.a < 0.1) {
                return fixed4(cellBg, 1.0);
            }
            // Blend number over cell background using atlas alpha
            fixed3 outCol = lerp(cellBg, numberColor, numCol.a);
            return fixed4(outCol, 1.0);
        }
        ENDCG

        //Passes
        Pass { Stencil { Ref 0 Comp Equal } Blend SrcAlpha OneMinusSrcAlpha ZTest Always ZWrite Off ColorMask RGBA CGPROGRAM fixed4 frag (v2f i) : SV_Target { discard; return fixed4(0,0,0,0); } ENDCG }
        Pass { Stencil { Ref 1 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 1, screenUV); } ENDCG }
        Pass { Stencil { Ref 2 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 2, screenUV); } ENDCG }
        Pass { Stencil { Ref 3 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 3, screenUV); } ENDCG }
        Pass { Stencil { Ref 4 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 4, screenUV); } ENDCG }
        Pass { Stencil { Ref 5 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 5, screenUV); } ENDCG }
        Pass { Stencil { Ref 6 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 6, screenUV); } ENDCG }
        Pass { Stencil { Ref 7 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 7, screenUV); } ENDCG }
        Pass { Stencil { Ref 8 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 8, screenUV); } ENDCG }
        Pass { Stencil { Ref 9 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 9, screenUV); } ENDCG }
        Pass { Stencil { Ref 10 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 10, screenUV); } ENDCG }
        Pass { Stencil { Ref 11 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 11, screenUV); } ENDCG }
        Pass { Stencil { Ref 12 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 12, screenUV); } ENDCG }
        Pass { Stencil { Ref 13 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 13, screenUV); } ENDCG }
        Pass { Stencil { Ref 14 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 14, screenUV); } ENDCG }
        Pass { Stencil { Ref 15 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 15, screenUV); } ENDCG }
        Pass { Stencil { Ref 16 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 16, screenUV); } ENDCG }
        Pass { Stencil { Ref 17 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 17, screenUV); } ENDCG }
        Pass { Stencil { Ref 18 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 18, screenUV); } ENDCG }
        Pass { Stencil { Ref 19 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 19, screenUV); } ENDCG }
        Pass { Stencil { Ref 20 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 20, screenUV); } ENDCG }
        Pass { Stencil { Ref 21 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 21, screenUV); } ENDCG }
        Pass { Stencil { Ref 22 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 22, screenUV); } ENDCG }
        Pass { Stencil { Ref 23 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 23, screenUV); } ENDCG }
        Pass { Stencil { Ref 24 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 24, screenUV); } ENDCG }
        Pass { Stencil { Ref 25 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 25, screenUV); } ENDCG }
        Pass { Stencil { Ref 26 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 26, screenUV); } ENDCG }
        Pass { Stencil { Ref 27 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 27, screenUV); } ENDCG }
        Pass { Stencil { Ref 28 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 28, screenUV); } ENDCG }
        Pass { Stencil { Ref 29 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 29, screenUV); } ENDCG }
        Pass { Stencil { Ref 30 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 30, screenUV); } ENDCG }
        Pass { Stencil { Ref 31 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 31, screenUV); } ENDCG }
        Pass { Stencil { Ref 32 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 32, screenUV); } ENDCG }
        Pass { Stencil { Ref 33 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 33, screenUV); } ENDCG }
        Pass { Stencil { Ref 34 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 34, screenUV); } ENDCG }
        Pass { Stencil { Ref 35 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 35, screenUV); } ENDCG }
        Pass { Stencil { Ref 36 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 36, screenUV); } ENDCG }
        Pass { Stencil { Ref 37 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 37, screenUV); } ENDCG }
        Pass { Stencil { Ref 38 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 38, screenUV); } ENDCG }
        Pass { Stencil { Ref 39 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 39, screenUV); } ENDCG }
        Pass { Stencil { Ref 40 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 40, screenUV); } ENDCG }
        Pass { Stencil { Ref 41 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 41, screenUV); } ENDCG }
        Pass { Stencil { Ref 42 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 42, screenUV); } ENDCG }
        Pass { Stencil { Ref 43 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 43, screenUV); } ENDCG }
        Pass { Stencil { Ref 44 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 44, screenUV); } ENDCG }
        Pass { Stencil { Ref 45 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 45, screenUV); } ENDCG }
        Pass { Stencil { Ref 46 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 46, screenUV); } ENDCG }
        Pass { Stencil { Ref 47 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 47, screenUV); } ENDCG }
        Pass { Stencil { Ref 48 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 48, screenUV); } ENDCG }
        Pass { Stencil { Ref 49 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 49, screenUV); } ENDCG }
        Pass { Stencil { Ref 50 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 50, screenUV); } ENDCG }
        Pass { Stencil { Ref 51 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 51, screenUV); } ENDCG }
        Pass { Stencil { Ref 52 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 52, screenUV); } ENDCG }
        Pass { Stencil { Ref 53 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 53, screenUV); } ENDCG }
        Pass { Stencil { Ref 54 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 54, screenUV); } ENDCG }
        Pass { Stencil { Ref 55 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 55, screenUV); } ENDCG }
        Pass { Stencil { Ref 56 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 56, screenUV); } ENDCG }
        Pass { Stencil { Ref 57 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 57, screenUV); } ENDCG }
        Pass { Stencil { Ref 58 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 58, screenUV); } ENDCG }
        Pass { Stencil { Ref 59 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 59, screenUV); } ENDCG }
        Pass { Stencil { Ref 60 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 60, screenUV); } ENDCG }
        Pass { Stencil { Ref 61 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 61, screenUV); } ENDCG }
        Pass { Stencil { Ref 62 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 62, screenUV); } ENDCG }
        Pass { Stencil { Ref 63 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 63, screenUV); } ENDCG }
        Pass { Stencil { Ref 64 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 64, screenUV); } ENDCG }
        Pass { Stencil { Ref 65 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 65, screenUV); } ENDCG }
        Pass { Stencil { Ref 66 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 66, screenUV); } ENDCG }
        Pass { Stencil { Ref 67 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 67, screenUV); } ENDCG }
        Pass { Stencil { Ref 68 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 68, screenUV); } ENDCG }
        Pass { Stencil { Ref 69 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 69, screenUV); } ENDCG }
        Pass { Stencil { Ref 70 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 70, screenUV); } ENDCG }
        Pass { Stencil { Ref 71 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 71, screenUV); } ENDCG }
        Pass { Stencil { Ref 72 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 72, screenUV); } ENDCG }
        Pass { Stencil { Ref 73 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 73, screenUV); } ENDCG }
        Pass { Stencil { Ref 74 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 74, screenUV); } ENDCG }
        Pass { Stencil { Ref 75 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 75, screenUV); } ENDCG }
        Pass { Stencil { Ref 76 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 76, screenUV); } ENDCG }
        Pass { Stencil { Ref 77 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 77, screenUV); } ENDCG }
        Pass { Stencil { Ref 78 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 78, screenUV); } ENDCG }
        Pass { Stencil { Ref 79 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 79, screenUV); } ENDCG }
        Pass { Stencil { Ref 80 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 80, screenUV); } ENDCG }
        Pass { Stencil { Ref 81 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 81, screenUV); } ENDCG }
        Pass { Stencil { Ref 82 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 82, screenUV); } ENDCG }
        Pass { Stencil { Ref 83 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 83, screenUV); } ENDCG }
        Pass { Stencil { Ref 84 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 84, screenUV); } ENDCG }
        Pass { Stencil { Ref 85 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 85, screenUV); } ENDCG }
        Pass { Stencil { Ref 86 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 86, screenUV); } ENDCG }
        Pass { Stencil { Ref 87 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 87, screenUV); } ENDCG }
        Pass { Stencil { Ref 88 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 88, screenUV); } ENDCG }
        Pass { Stencil { Ref 89 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 89, screenUV); } ENDCG }
        Pass { Stencil { Ref 90 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 90, screenUV); } ENDCG }
        Pass { Stencil { Ref 91 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 91, screenUV); } ENDCG }
        Pass { Stencil { Ref 92 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 92, screenUV); } ENDCG }
        Pass { Stencil { Ref 93 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 93, screenUV); } ENDCG }
        Pass { Stencil { Ref 94 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 94, screenUV); } ENDCG }
        Pass { Stencil { Ref 95 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 95, screenUV); } ENDCG }
        Pass { Stencil { Ref 96 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 96, screenUV); } ENDCG }
        Pass { Stencil { Ref 97 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 97, screenUV); } ENDCG }
        Pass { Stencil { Ref 98 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 98, screenUV); } ENDCG }
        Pass { Stencil { Ref 99 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 99, screenUV); } ENDCG }
        Pass { Stencil { Ref 100 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 100, screenUV); } ENDCG }
        Pass { Stencil { Ref 101 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 101, screenUV); } ENDCG }
        Pass { Stencil { Ref 102 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 102, screenUV); } ENDCG }
        Pass { Stencil { Ref 103 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 103, screenUV); } ENDCG }
        Pass { Stencil { Ref 104 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 104, screenUV); } ENDCG }
        Pass { Stencil { Ref 105 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 105, screenUV); } ENDCG }
        Pass { Stencil { Ref 106 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 106, screenUV); } ENDCG }
        Pass { Stencil { Ref 107 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 107, screenUV); } ENDCG }
        Pass { Stencil { Ref 108 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 108, screenUV); } ENDCG }
        Pass { Stencil { Ref 109 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 109, screenUV); } ENDCG }
        Pass { Stencil { Ref 110 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 110, screenUV); } ENDCG }
        Pass { Stencil { Ref 111 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 111, screenUV); } ENDCG }
        Pass { Stencil { Ref 112 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 112, screenUV); } ENDCG }
        Pass { Stencil { Ref 113 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 113, screenUV); } ENDCG }
        Pass { Stencil { Ref 114 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 114, screenUV); } ENDCG }
        Pass { Stencil { Ref 115 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 115, screenUV); } ENDCG }
        Pass { Stencil { Ref 116 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 116, screenUV); } ENDCG }
        Pass { Stencil { Ref 117 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 117, screenUV); } ENDCG }
        Pass { Stencil { Ref 118 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 118, screenUV); } ENDCG }
        Pass { Stencil { Ref 119 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 119, screenUV); } ENDCG }
        Pass { Stencil { Ref 120 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 120, screenUV); } ENDCG }
        Pass { Stencil { Ref 121 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 121, screenUV); } ENDCG }
        Pass { Stencil { Ref 122 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 122, screenUV); } ENDCG }
        Pass { Stencil { Ref 123 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 123, screenUV); } ENDCG }
        Pass { Stencil { Ref 124 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 124, screenUV); } ENDCG }
        Pass { Stencil { Ref 125 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 125, screenUV); } ENDCG }
        Pass { Stencil { Ref 126 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 126, screenUV); } ENDCG }
        Pass { Stencil { Ref 127 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 127, screenUV); } ENDCG }
        Pass { Stencil { Ref 128 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 128, screenUV); } ENDCG }
        Pass { Stencil { Ref 129 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 129, screenUV); } ENDCG }
        Pass { Stencil { Ref 130 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 130, screenUV); } ENDCG }
        Pass { Stencil { Ref 131 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 131, screenUV); } ENDCG }
        Pass { Stencil { Ref 132 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 132, screenUV); } ENDCG }
        Pass { Stencil { Ref 133 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 133, screenUV); } ENDCG }
        Pass { Stencil { Ref 134 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 134, screenUV); } ENDCG }
        Pass { Stencil { Ref 135 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 135, screenUV); } ENDCG }
        Pass { Stencil { Ref 136 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 136, screenUV); } ENDCG }
        Pass { Stencil { Ref 137 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 137, screenUV); } ENDCG }
        Pass { Stencil { Ref 138 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 138, screenUV); } ENDCG }
        Pass { Stencil { Ref 139 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 139, screenUV); } ENDCG }
        Pass { Stencil { Ref 140 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 140, screenUV); } ENDCG }
        Pass { Stencil { Ref 141 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 141, screenUV); } ENDCG }
        Pass { Stencil { Ref 142 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 142, screenUV); } ENDCG }
        Pass { Stencil { Ref 143 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 143, screenUV); } ENDCG }
        Pass { Stencil { Ref 144 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 144, screenUV); } ENDCG }
        Pass { Stencil { Ref 145 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 145, screenUV); } ENDCG }
        Pass { Stencil { Ref 146 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 146, screenUV); } ENDCG }
        Pass { Stencil { Ref 147 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 147, screenUV); } ENDCG }
        Pass { Stencil { Ref 148 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 148, screenUV); } ENDCG }
        Pass { Stencil { Ref 149 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 149, screenUV); } ENDCG }
        Pass { Stencil { Ref 150 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 150, screenUV); } ENDCG }
        Pass { Stencil { Ref 151 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 151, screenUV); } ENDCG }
        Pass { Stencil { Ref 152 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 152, screenUV); } ENDCG }
        Pass { Stencil { Ref 153 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 153, screenUV); } ENDCG }
        Pass { Stencil { Ref 154 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 154, screenUV); } ENDCG }
        Pass { Stencil { Ref 155 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 155, screenUV); } ENDCG }
        Pass { Stencil { Ref 156 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 156, screenUV); } ENDCG }
        Pass { Stencil { Ref 157 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 157, screenUV); } ENDCG }
        Pass { Stencil { Ref 158 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 158, screenUV); } ENDCG }
        Pass { Stencil { Ref 159 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 159, screenUV); } ENDCG }
        Pass { Stencil { Ref 160 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 160, screenUV); } ENDCG }
        Pass { Stencil { Ref 161 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 161, screenUV); } ENDCG }
        Pass { Stencil { Ref 162 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 162, screenUV); } ENDCG }
        Pass { Stencil { Ref 163 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 163, screenUV); } ENDCG }
        Pass { Stencil { Ref 164 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 164, screenUV); } ENDCG }
        Pass { Stencil { Ref 165 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 165, screenUV); } ENDCG }
        Pass { Stencil { Ref 166 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 166, screenUV); } ENDCG }
        Pass { Stencil { Ref 167 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 167, screenUV); } ENDCG }
        Pass { Stencil { Ref 168 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 168, screenUV); } ENDCG }
        Pass { Stencil { Ref 169 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 169, screenUV); } ENDCG }
        Pass { Stencil { Ref 170 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 170, screenUV); } ENDCG }
        Pass { Stencil { Ref 171 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 171, screenUV); } ENDCG }
        Pass { Stencil { Ref 172 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 172, screenUV); } ENDCG }
        Pass { Stencil { Ref 173 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 173, screenUV); } ENDCG }
        Pass { Stencil { Ref 174 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 174, screenUV); } ENDCG }
        Pass { Stencil { Ref 175 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 175, screenUV); } ENDCG }
        Pass { Stencil { Ref 176 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 176, screenUV); } ENDCG }
        Pass { Stencil { Ref 177 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 177, screenUV); } ENDCG }
        Pass { Stencil { Ref 178 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 178, screenUV); } ENDCG }
        Pass { Stencil { Ref 179 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 179, screenUV); } ENDCG }
        Pass { Stencil { Ref 180 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 180, screenUV); } ENDCG }
        Pass { Stencil { Ref 181 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 181, screenUV); } ENDCG }
        Pass { Stencil { Ref 182 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 182, screenUV); } ENDCG }
        Pass { Stencil { Ref 183 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 183, screenUV); } ENDCG }
        Pass { Stencil { Ref 184 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 184, screenUV); } ENDCG }
        Pass { Stencil { Ref 185 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 185, screenUV); } ENDCG }
        Pass { Stencil { Ref 186 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 186, screenUV); } ENDCG }
        Pass { Stencil { Ref 187 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 187, screenUV); } ENDCG }
        Pass { Stencil { Ref 188 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 188, screenUV); } ENDCG }
        Pass { Stencil { Ref 189 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 189, screenUV); } ENDCG }
        Pass { Stencil { Ref 190 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 190, screenUV); } ENDCG }
        Pass { Stencil { Ref 191 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 191, screenUV); } ENDCG }
        Pass { Stencil { Ref 192 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 192, screenUV); } ENDCG }
        Pass { Stencil { Ref 193 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 193, screenUV); } ENDCG }
        Pass { Stencil { Ref 194 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 194, screenUV); } ENDCG }
        Pass { Stencil { Ref 195 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 195, screenUV); } ENDCG }
        Pass { Stencil { Ref 196 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 196, screenUV); } ENDCG }
        Pass { Stencil { Ref 197 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 197, screenUV); } ENDCG }
        Pass { Stencil { Ref 198 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 198, screenUV); } ENDCG }
        Pass { Stencil { Ref 199 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 199, screenUV); } ENDCG }
        Pass { Stencil { Ref 200 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 200, screenUV); } ENDCG }
        Pass { Stencil { Ref 201 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 201, screenUV); } ENDCG }
        Pass { Stencil { Ref 202 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 202, screenUV); } ENDCG }
        Pass { Stencil { Ref 203 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 203, screenUV); } ENDCG }
        Pass { Stencil { Ref 204 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 204, screenUV); } ENDCG }
        Pass { Stencil { Ref 205 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 205, screenUV); } ENDCG }
        Pass { Stencil { Ref 206 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 206, screenUV); } ENDCG }
        Pass { Stencil { Ref 207 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 207, screenUV); } ENDCG }
        Pass { Stencil { Ref 208 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 208, screenUV); } ENDCG }
        Pass { Stencil { Ref 209 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 209, screenUV); } ENDCG }
        Pass { Stencil { Ref 210 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 210, screenUV); } ENDCG }
        Pass { Stencil { Ref 211 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 211, screenUV); } ENDCG }
        Pass { Stencil { Ref 212 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 212, screenUV); } ENDCG }
        Pass { Stencil { Ref 213 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 213, screenUV); } ENDCG }
        Pass { Stencil { Ref 214 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 214, screenUV); } ENDCG }
        Pass { Stencil { Ref 215 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 215, screenUV); } ENDCG }
        Pass { Stencil { Ref 216 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 216, screenUV); } ENDCG }
        Pass { Stencil { Ref 217 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 217, screenUV); } ENDCG }
        Pass { Stencil { Ref 218 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 218, screenUV); } ENDCG }
        Pass { Stencil { Ref 219 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 219, screenUV); } ENDCG }
        Pass { Stencil { Ref 220 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 220, screenUV); } ENDCG }
        Pass { Stencil { Ref 221 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 221, screenUV); } ENDCG }
        Pass { Stencil { Ref 222 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 222, screenUV); } ENDCG }
        Pass { Stencil { Ref 223 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 223, screenUV); } ENDCG }
        Pass { Stencil { Ref 224 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 224, screenUV); } ENDCG }
        Pass { Stencil { Ref 225 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 225, screenUV); } ENDCG }
        Pass { Stencil { Ref 226 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 226, screenUV); } ENDCG }
        Pass { Stencil { Ref 227 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 227, screenUV); } ENDCG }
        Pass { Stencil { Ref 228 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 228, screenUV); } ENDCG }
        Pass { Stencil { Ref 229 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 229, screenUV); } ENDCG }
        Pass { Stencil { Ref 230 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 230, screenUV); } ENDCG }
        Pass { Stencil { Ref 231 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 231, screenUV); } ENDCG }
        Pass { Stencil { Ref 232 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 232, screenUV); } ENDCG }
        Pass { Stencil { Ref 233 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 233, screenUV); } ENDCG }
        Pass { Stencil { Ref 234 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 234, screenUV); } ENDCG }
        Pass { Stencil { Ref 235 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 235, screenUV); } ENDCG }
        Pass { Stencil { Ref 236 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 236, screenUV); } ENDCG }
        Pass { Stencil { Ref 237 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 237, screenUV); } ENDCG }
        Pass { Stencil { Ref 238 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 238, screenUV); } ENDCG }
        Pass { Stencil { Ref 239 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 239, screenUV); } ENDCG }
        Pass { Stencil { Ref 240 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 240, screenUV); } ENDCG }
        Pass { Stencil { Ref 241 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 241, screenUV); } ENDCG }
        Pass { Stencil { Ref 242 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 242, screenUV); } ENDCG }
        Pass { Stencil { Ref 243 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 243, screenUV); } ENDCG }
        Pass { Stencil { Ref 244 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 244, screenUV); } ENDCG }
        Pass { Stencil { Ref 245 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 245, screenUV); } ENDCG }
        Pass { Stencil { Ref 246 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 246, screenUV); } ENDCG }
        Pass { Stencil { Ref 247 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 247, screenUV); } ENDCG }
        Pass { Stencil { Ref 248 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 248, screenUV); } ENDCG }
        Pass { Stencil { Ref 249 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 249, screenUV); } ENDCG }
        Pass { Stencil { Ref 250 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 250, screenUV); } ENDCG }
        Pass { Stencil { Ref 251 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 251, screenUV); } ENDCG }
        Pass { Stencil { Ref 252 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 252, screenUV); } ENDCG }
        Pass { Stencil { Ref 253 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 253, screenUV); } ENDCG }
        Pass { Stencil { Ref 254 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 254, screenUV); } ENDCG }
        Pass { Stencil { Ref 255 Comp Equal } ZTest Always ZWrite Off ColorMask RGB CGPROGRAM fixed4 frag (v2f i) : SV_Target { float2 screenUV = GetScreenUV(i.screenPos); return SampleNumber(i.uv, 255, screenUV); } ENDCG }
    }
}
