#define ROOT_SIGNATURE \
    "RootFlags(ALLOW_INPUT_ASSEMBLER_INPUT_LAYOUT)," \
    "CBV(b0)"

struct Camera {
    float4x4 mat;
};

struct VSInput {
    float3 position : POSITION;
};

struct VSOutput {
    float4 position : SV_Position;
};

ConstantBuffer<Camera> camera : register(b0);

[RootSignature(ROOT_SIGNATURE)]
VSOutput vsMain(VSInput input) {
    VSOutput output;

    output.position = float4(input.position, 1.0);
    output.position = mul(output.position, camera.mat);

    return output;
}

[RootSignature(ROOT_SIGNATURE)]
void psMain(float4 position : SV_Position, out float4 out_color : SV_Target0) {
    out_color = float4(0.75, 0.0, 0.0, 1.0);
}