#define ROOT_SIGNATURE \
    "RootFlags(ALLOW_INPUT_ASSEMBLER_INPUT_LAYOUT), " \
    "CBV(b0), " \
    "CBV(b1), " \
    "RootConstants(b2, num32BitConstants = 2), " \
    "DescriptorTable(SRV(t0, numDescriptors = 4))"

struct RootConst {
    uint vertex_offset;
    uint meshlet_offset;
};

struct Camera {
    float4x4 view;
    float4x4 proj;
};

struct Instance {
    float4x4 model;
};

struct InputVertex {
    float3 position : POSITION;
};

struct OutputVertex {
    float4 position : SV_POSITION;
};

ConstantBuffer<Camera> camera : register(b0);
ConstantBuffer<Instance> instance : register(b1);
ConstantBuffer<RootConst> root_const : register(b2);

StructuredBuffer<InputVertex> vertices : register(t0);
StructuredBuffer<uint32_t> indices : register(t1);
StructuredBuffer<uint64_t> meshlets : register(t2);
Buffer<uint32_t> meshlets_data : register(t3);

#define NUM_THREADS 32
#define MAX_NUM_VERTICES 64
#define MAX_NUM_TRIANGLES 64

[RootSignature(ROOT_SIGNATURE)]
[outputtopology("triangle")]
[numthreads(NUM_THREADS, 1, 1)]
void msMain(
    uint group_index : SV_GroupIndex, 
    uint3 group_id : SV_GroupID, 
    out vertices OutputVertex out_vertices[MAX_NUM_VERTICES], 
    out indices uint3 out_triangles[MAX_NUM_TRIANGLES]
) {
    SetMeshOutputCounts(3, 1);

    out_vertices[0] = OutputVertex(float4(0.0, 0.5, 0.0, 1.0));
    out_vertices[1] = OutputVertex(float4(0.5, -0.5, 0.0, 1.0));
    out_vertices[2] = OutputVertex(float4(-0.5, -0.5, 0.0, 1.0));

    out_triangles[0] = uint3(0, 1, 2);
}

[RootSignature(ROOT_SIGNATURE)]
void psMain(float3 barycentrics : SV_Barycentrics, OutputVertex vertex, out float4 out_color : SV_Target0) {
    out_color = float4(0.75, 0.0, 0.0, 1.0);
}