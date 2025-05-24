#define ROOT_SIGNATURE \
    "RootFlags(ALLOW_INPUT_ASSEMBLER_INPUT_LAYOUT)," \
    "CBV(b0)," \
    "CBV(b1)"

struct Camera {
    float4x4 view;
    float4x4 proj;
};

struct Instance {
    float4x4 model;
};

struct VSInput {
    float3 position : POSITION;
};

struct VSOutput {
    float4 position : SV_Position;
};

ConstantBuffer<Camera> camera : register(b0);
ConstantBuffer<Instance> instance : register(b1);

[RootSignature(ROOT_SIGNATURE)]
VSOutput vsMain(VSInput input) {
    VSOutput output;

    float4x4 vp = mul(camera.view, camera.proj);
    float4x4 mvp = mul(instance.model, vp);

    output.position = float4(input.position, 1.0);
    output.position = mul(output.position, mvp);

    return output;
}

[RootSignature(ROOT_SIGNATURE)]
void psMain(float4 position : SV_Position, out float4 out_color : SV_Target0) {
    out_color = float4(0.75, 0.0, 0.0, 1.0);
}