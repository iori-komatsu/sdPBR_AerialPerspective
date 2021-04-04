#include "../../shader/sdPBRcommon.fxsub"
#include "../../shader/sdPBRGBuffer.fxsub"

// パラメータ操作用オブジェクト
float3 XYZ  : CONTROLOBJECT < string name = "(self)"; string item = "XYZ";  >; // 座標
float3 Rxyz : CONTROLOBJECT < string name = "(self)"; string item = "Rxyz"; >; // 回転
float  Si   : CONTROLOBJECT < string name = "(self)"; string item = "Si";   >; // スケール
float  Tr   : CONTROLOBJECT < string name = "(self)"; string item = "Tr";   >; // 透過度

// フォグの色
static float3 FogColor = HSVtoRGB(float3(0.6, 0.2, 0.8) + Rxyz);

// 吸光係数
static float Absorptivity = 0.00003 * exp(XYZ.x * 0.01);

// 標高と大気の密度の関係
static float DensityFactor = 0.000048 * exp(XYZ.y * 0.05);

// 元の色とフォグ色を混ぜるときに最低でもこの割合だけは元の色を残す
static float MinOriginalColorMixRatio = saturate(XYZ.z * 0.01);

// スケール (アクセサリの Si はUIで指定された値の10倍が取得されるので、もとに戻す)
static float Scale = Si * 0.1;

//-------------------------------------------------------------------------------------------------

float3 CameraPos : POSITION < string Object = "Camera"; >;

float4x4 ViewMatrix	: VIEW;
float4x4 ProjectionMatrix : PROJECTION;

float2 ViewportSize : VIEWPORTPIXELSIZE;
static const float2 ViewportOffset = (float2(0.5, 0.5) / ViewportSize);

float4 ClearColor = float4(0, 0, 0, 0);
float ClearDepth = 1.0;

float Script : STANDARDSGLOBAL <
    string ScriptOutput = "color";
    string ScriptClass = "scene";
    string ScriptOrder = "postprocess";
> = 0.8;

texture2D DepthBuffer : RENDERDEPTHSTENCILTARGET <
    float2 ViewPortRatio = {1.0,1.0};
    string Format = "D24S8";
>;

texture2D ScnMap : RENDERCOLORTARGET <
    float2 ViewPortRatio = {1.0,1.0};
    int MipLevels = 1;
    string Format = "D3DFMT_A16B16G16R16F" ;
>;
sampler2D ScnSamp = sampler_state {
    MAGFILTER = LINEAR;
    MINFILTER = LINEAR;
    MIPFILTER = LINEAR;
    texture = <ScnMap>;
    AddressU  = CLAMP; AddressV = CLAMP;
};

float4 VS(
    float4 pos : POSITION,
    float2 coord : TEXCOORD0,
    out float2 oCoord: TEXCOORD0
) : POSITION {
    oCoord = coord + ViewportOffset;
    return pos;
}

// World空間におけるレイの向きを求める。
float3 GetRayDir(float2 coord) {
    float2 p = (coord.xy - 0.5) * 2.0;
    return normalize(
          ViewMatrix._13_23_33 / ProjectionMatrix._33
        + ViewMatrix._11_21_31 * p.x / ProjectionMatrix._11
        - ViewMatrix._12_22_32 * p.y / ProjectionMatrix._22
    );
}

float4 PS(float2 coord: TEXCOORD0) : COLOR
{
    float4 inColor = tex2D(ScnSamp, coord);

    int shadingModelId;
    float3 normal;
    float depth;
    float alpha;
    GetFrontMaterialFromGBuffer(coord, shadingModelId, normal, depth, alpha);

    float3 rayDir = GetRayDir(coord);
    float3 targetPos = CameraPos + rayDir * depth;

    // Lambert-Beer の法則によると、入射光の強さを I、透過光の強さを T、対象の点までの距離を d とすると
    //   log T = log I - ερd
    // という関係が成り立つ。ここで ε は吸光係数で、ρ は大気の密度。
    // この式では大気の密度が一定であることを仮定しているが、実際には標高によって大気の密度が変わる。
    // そこで、大気の密度を以下のように標高 h の関数として表せると仮定する。
    //   ρ(h) = exp(-Dh)      (D は定数)
    // この式を Lambert-Beer の式の入れて積分すると透過光の強さが求められる。
    //   log T = ∫[0,1] (log I - ε ρ(lerp(h_t, h_c, x)) d) dx
    //         = log I + (ε/D) d (exp(-D h_c) - exp(-D h_t)) / (h_c - h_t)
    // ただし h_t は対象の点の標高を表し、h_c はカメラの標高を表す。

    float h_c = max(CameraPos.y * Scale, 0);
    float h_t = max(targetPos.y * Scale, 0);
    float dist = depth * Scale;

    float a; // 負の吸光度。値域は -∞ から 0 まで
    if (abs(h_t - h_c) < 0.01) {
        a = -Absorptivity * exp(-DensityFactor * h_t) * dist;
    } else {
        a = (Absorptivity / DensityFactor) * dist
            * (exp(-DensityFactor * h_c) - exp(-DensityFactor * h_t))
            / (h_c - h_t);
    }

    float mixRatio = max(exp(a), MinOriginalColorMixRatio);
    float3 outColor = lerp(FogColor, inColor, mixRatio);
    return float4(outColor, inColor.a);
}

technique postprocessTest <
    string Script =
        "RenderColorTarget0=ScnMap;"
        "RenderDepthStencilTarget=DepthBuffer;"
        "ClearSetColor=ClearColor;"
        "ClearSetDepth=ClearDepth;"
        "Clear=Color;"
        "Clear=Depth;"
        "ScriptExternal=Color;"

        "RenderColorTarget0=;"
        "RenderDepthStencilTarget=;"
        "Pass=Draw1;"
    ;
> {
    pass Draw1 < string Script= "Draw=Buffer;"; > {
        AlphaBlendEnable = FALSE;
        AlphaTestEnable = FALSE;
        VertexShader = compile vs_3_0 VS();
        PixelShader  = compile ps_3_0 PS();
    }
}
