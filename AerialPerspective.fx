#include "../../shader/sdPBRcommon.fxsub"
#include "../../shader/sdPBRGBuffer.fxsub"

// �p�����[�^����p�I�u�W�F�N�g
float3 XYZ : CONTROLOBJECT < string name = "(self)"; string item = "XYZ";>;	// ���W
float Rx : CONTROLOBJECT < string name = "(self)"; string item="Rx";>;
float Ry : CONTROLOBJECT < string name = "(self)"; string item="Ry";>;
float Rz : CONTROLOBJECT < string name = "(self)"; string item="Rz";>;
float Scale : CONTROLOBJECT < string name = "(self)"; string item = "Si";>;	// �X�P�[��
float Tr : CONTROLOBJECT < string name = "(self)"; string item = "Tr";>;	// ���ߓx
float3 CameraPosition: POSITION < string Object = "Camera"; >;	// �J�������W

//���낢��ݒ�p/////////////////////////////////////////////////////////

// �t�H�O�̐F
static float3 FogColor = HSVtoRGB(float3(0.6+Rx, 0.2+Ry, 0.8+Rz));

// �z���W��
static float Absorptivity  = 0.000003 * exp(XYZ.x * 0.01);

// �W���Ƒ�C�̖��x�̊֌W
static float DensityFactor = 0.0000048 * exp(XYZ.y * 0.05);

// ����ȏ㋗��������Ă���ꍇ�A���̋������Ƃ��Čv�Z����
static float MaxDistance = XYZ.z <= 0.0 ? 1e15 : XYZ.z;

//�ݒ肱���܂ňȉ��̓R�[�h�ł�////////////////////////////////////////

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

// World��Ԃɂ����郌�C�̌��������߂�B
void GetRayDir(float2 coord, out float3 oRayDir) {
    float2 p = (coord.xy - 0.5) * 2.0;
    oRayDir = normalize(
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

    float3 rayDir;
    GetRayDir(coord, rayDir);

    float3 targetPos = CameraPosition + rayDir * depth;

    // Lambert-Beer �̖@���ɂ��ƁA���ˌ��̋����� I�A���ߌ��̋����� T�A�Ώۂ̓_�܂ł̋����� d �Ƃ����
    //   log T = log I - �Ã�d
    // �Ƃ����֌W�����藧�B������ �� �͋z���W���ŁA�� �͑�C�̖��x�B
    // ���̎��ł͑�C�̖��x�����ł��邱�Ƃ����肵�Ă��邪�A���ۂɂ͕W���ɂ���đ�C�̖��x���ς��B
    // �����ŁA��C�̖��x���ȉ��̂悤�ɕW�� h �̊֐��Ƃ��ĕ\����Ɖ��肷��B
    //   ��(h) = exp(-Dh)      (D �͒萔)
    // ���̎��� Lambert-Beer �̎��̓���Đϕ�����Ɠ��ߌ��̋��������߂���B
    //   log T = ��[0,1] (log I - �� ��(lerp(h_t, h_c, x)) d) dx
    //         = log I + (��/D) d (exp(-D h_c) - exp(-D h_t)) / (h_c - h_t)
    // ������ h_t �͑Ώۂ̓_�̕W����\���Ah_c �̓J�����̕W����\���B

    float h_c = max(CameraPosition.y * Scale, 0);
    float h_t = max(targetPos.y * Scale, 0);
    float dist = min(depth, MaxDistance) * Scale;

    float a;
    if (abs(h_t - h_c) < 0.01) {
        a = -Absorptivity * exp(-DensityFactor * h_t) * dist;
    } else {
        a = (Absorptivity / DensityFactor) * dist
            * (exp(-DensityFactor * h_c) - exp(-DensityFactor * h_t))
            / (h_c - h_t);
    }

    float3 outColor = lerp(FogColor, inColor, exp(a));
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
