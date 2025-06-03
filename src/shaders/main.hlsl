#define ROOT_SIGNATURE \
    "RootFlags(ALLOW_INPUT_ASSEMBLER_INPUT_LAYOUT), " \
    "CBV(b0), " \
    "CBV(b1), " \
    "RootConstants(b2, num32BitConstants = 3), " \
    "DescriptorTable(SRV(t0, numDescriptors = 4))"

struct RootConst {
    uint vertex_offset;
    uint meshlet_offset;
    uint draw_mode;
};

struct Camera {
    float4x4 view;
    float4x4 proj;
    float3 position;
};

struct Instance {
    float4x4 model;
};

struct InputVertex {
    float3 position : POSITION;
    float3 normal: _Normal;
};

struct OutputVertex {
    float4 position : SV_Position;
    float3 color : _Color;
    float3 normal : _Normal;
    float3 worldPosition : _WorldPosition;
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

uint computeHash(uint a) {
    a = (a + 0x7ed55d16) + (a << 12);
    a = (a ^ 0xc761c23c) ^ (a >> 19);
    a = (a + 0x165667b1) + (a << 5);
    a = (a + 0xd3a2646c) ^ (a << 9);
    a = (a + 0xfd7046c5) + (a << 3);
    a = (a ^ 0xb55a4f09) ^ (a >> 16);
    return a;
}

[RootSignature(ROOT_SIGNATURE)]
[outputtopology("triangle")]
[numthreads(NUM_THREADS, 1, 1)]
void msMain(
    uint group_index : SV_GroupIndex, 
    uint3 group_id : SV_GroupID, 
    out vertices OutputVertex out_vertices[MAX_NUM_VERTICES], 
    out indices uint3 out_triangles[MAX_NUM_TRIANGLES]
) {
    const uint thread_index = group_index;
    const uint meshlet_index = group_id.x + root_const.meshlet_offset;

    const uint64_t offset_vertices_triangles = meshlets[meshlet_index];
    const uint data_offset = (uint)offset_vertices_triangles;
    const uint num_vertices = (uint)((offset_vertices_triangles >> 32) & 0xffff);
    const uint num_triangles = (uint)((offset_vertices_triangles >> 48) & 0xffff);

    const uint vertex_offset = data_offset;
    const uint index_offset = data_offset + num_vertices;

    const float4x4 vp = mul(camera.view, camera.proj);

    SetMeshOutputCounts(num_vertices, num_triangles);

    const uint hash = computeHash(meshlet_index);
    const float3 color = float3(hash & 0xff, (hash >> 8) & 0xff, (hash >> 16) & 0xff) / 255.0;

    for(uint i = thread_index; i < num_vertices; i += NUM_THREADS) {
        const uint vertex_index = meshlets_data[vertex_offset + i] + root_const.vertex_offset;

        float4 position = float4(vertices[vertex_index].position, 1.0);
        float3 normal = vertices[vertex_index].normal;

        float4 worldPosition = mul(position, instance.model);

        position = mul(worldPosition, vp);

        out_vertices[i].position = position;
        out_vertices[i].color = color;
        out_vertices[i].normal = normal;
        out_vertices[i].worldPosition = worldPosition.xyz;
    }

    for(uint i = thread_index; i < num_triangles; i += NUM_THREADS) {
        const uint prim = meshlets_data[index_offset + i];
        out_triangles[i] = uint3(prim & 0x3ff, (prim >> 10) & 0x3ff, (prim >> 20) & 0x3ff);
    }
}

[RootSignature(ROOT_SIGNATURE)]
void psMain(float3 barycentrics : SV_Barycentrics, OutputVertex vertex, out float4 out_color : SV_Target0) {
    if(root_const.draw_mode == 0) {
        float3 barys = barycentrics;
        const float3 deltas = fwidth(barys);
        const float3 smoothing = deltas * 1.0;
        const float3 thickness = deltas * 0.01;
        barys = smoothstep(thickness, thickness + smoothing, barys);
        float min_bary = min(barys.x, min(barys.y, barys.z));

        out_color = float4(vertex.color, 1.0);
    } else if(root_const.draw_mode == 1) {
        float3 lightPos = { 10.0f, 10.0f, 10.0f };
        float3 cameraPos = { 0.0f, 0.0f, -10.0f };
        float3 lightColor = { 1.0f, 1.0f, 1.0f };
        float ambientStrength = 0.1f;
        float specularStrength = 0.5f;
        float shininess = 32.0f;

        float3 N = normalize( vertex.normal);
        float3 L = normalize(lightPos - vertex.worldPosition);

        // Ambient component
        float3 ambient = ambientStrength * lightColor;

        // Diffuse component
        float diff = max(dot(N, L), 0.0);
        float3 diffuse = diff * lightColor;

        // Specular component
        float3 V = normalize(cameraPos - vertex.worldPosition);              // View direction
        float3 R = reflect(-L, N);                                     // Reflected light direction
        float spec = pow(max(dot(V, R), 0.0), shininess);
        float3 specular = specularStrength * spec * lightColor;

        // Final color
        float3 color = ambient + diffuse + specular;

        out_color = float4(color, 1.0);
    }
}