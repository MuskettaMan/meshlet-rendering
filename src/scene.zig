const std = @import("std");
const mesh_data = @import("mesh_data.zig");
const zwindows = @import("zwindows");
const d3d12 = zwindows.d3d12;
const zmath = @import("zmath");
const Dx12State = @import("dx12_state.zig").Dx12State;
const dx12_state = @import("dx12_state.zig");
const Resource = @import("dx12_state.zig").Resource;
const Descriptor = @import("dx12_state.zig").Descriptor;
const CbvSrvHeap = @import("dx12_state.zig").CbvSrvHeap;
const Camera = @import("camera.zig").Camera;
const hrPanicOnFail = zwindows.hrPanicOnFail;

pub const Scene = struct {
    all_meshes: std.ArrayList(mesh_data.Mesh),
    all_vertices: std.ArrayList(mesh_data.Vertex),
    all_indices: std.ArrayList(u32),
    all_meshlets: std.ArrayList(mesh_data.Meshlet),
    all_meshlets_data: std.ArrayList(u32),

    root_signature: *d3d12.IRootSignature,
    pipeline: *d3d12.IPipelineState,

    camera_resource: Resource,
    instance_resource: Resource,

    meshlet_heap: CbvSrvHeap,

    camera: Camera,

    camera_descriptor: Descriptor,
    instance_descriptor: Descriptor,
    vertex_buffer_resource: Resource,
    vertex_buffer_descriptor: Descriptor,
    index_buffer_resource: Resource,
    index_buffer_descriptor: Descriptor,
    meshlet_buffer_resource: Resource,
    meshlet_buffer_descriptor: Descriptor,
    meshlet_data_buffer_resource: Resource,
    meshlet_data_buffer_descriptor: Descriptor,

    pub fn init(allocator: std.mem.Allocator, arenaAllocator: std.mem.Allocator, dx12: *Dx12State) !Scene {
        var all_meshes = std.ArrayList(mesh_data.Mesh).init(allocator);
        var all_vertices = std.ArrayList(mesh_data.Vertex).init(allocator);
        var all_indices = std.ArrayList(u32).init(allocator);
        var all_meshlets = std.ArrayList(mesh_data.Meshlet).init(allocator);
        var all_meshlets_data = std.ArrayList(u32).init(allocator);

        //const path: [:0]const u8 = "content/Cube/Cube.gltf";
        const path: [:0]const u8 = "content/DragonAttenuation.glb";
        try mesh_data.loadOptimizedMesh(allocator, &path, 1, &all_meshes, &all_vertices, &all_indices, &all_meshlets, &all_meshlets_data);

        const root_signature: *d3d12.IRootSignature, const pipeline: *d3d12.IPipelineState = blk: {
            const ms_cso = @embedFile("./shaders/main.ms.cso");
            const ps_cso = @embedFile("./shaders/main.ps.cso");

            var mesh_state_desc = d3d12.MESH_SHADER_PIPELINE_STATE_DESC.initDefault();
            mesh_state_desc.RTVFormats[0] = .R8G8B8A8_UNORM;
            mesh_state_desc.DepthStencilState = d3d12.DEPTH_STENCIL_DESC1.initDefault();
            mesh_state_desc.DSVFormat = .D32_FLOAT;
            mesh_state_desc.NumRenderTargets = 1;
            mesh_state_desc.MS = .{ .pShaderBytecode = ms_cso, .BytecodeLength = ms_cso.len };
            mesh_state_desc.PS = .{ .pShaderBytecode = ps_cso, .BytecodeLength = ps_cso.len };

            var stream = d3d12.PIPELINE_MESH_STATE_STREAM.init(mesh_state_desc);

            var root_signature: *d3d12.IRootSignature = undefined;
            hrPanicOnFail(dx12.device.CreateRootSignature(0, mesh_state_desc.MS.pShaderBytecode.?, mesh_state_desc.MS.BytecodeLength, &d3d12.IID_IRootSignature, @ptrCast(&root_signature)));

            var pipeline: *d3d12.IPipelineState = undefined;
            hrPanicOnFail(dx12.device.CreatePipelineState(&d3d12.PIPELINE_STATE_STREAM_DESC{ .SizeInBytes = @sizeOf(@TypeOf(stream)), .pPipelineStateSubobjectStream = @ptrCast(&stream) }, &d3d12.IID_IPipelineState, @ptrCast(&pipeline)));

            break :blk .{ root_signature, pipeline };
        };

        const camera = Camera.init();

        var camera_resource = dx12_state.createResource(Camera, std.unicode.utf8ToUtf16LeAllocZ(arenaAllocator, "CameraBuffer") catch unreachable, .UPLOAD, dx12.device, true);

        var instance_resource = dx12_state.createResource(zmath.Mat, std.unicode.utf8ToUtf16LeAllocZ(arenaAllocator, "InstanceBuffer") catch unreachable, .UPLOAD, dx12.device, true);

        var meshlet_heap = CbvSrvHeap.init(16, dx12.device);

        const camera_descriptor = meshlet_heap.allocate();
        const camera_cbv_desc: d3d12.CONSTANT_BUFFER_VIEW_DESC = .{ .BufferLocation = camera_resource.resource.GetGPUVirtualAddress(), .SizeInBytes = @intCast(camera_resource.buffer_size) };
        dx12.device.CreateConstantBufferView(&camera_cbv_desc, camera_descriptor.cpu_handle);

        const instance_descriptor = meshlet_heap.allocate();
        const instance_cbv_desc: d3d12.CONSTANT_BUFFER_VIEW_DESC = .{ .BufferLocation = instance_resource.resource.GetGPUVirtualAddress(), .SizeInBytes = @intCast(instance_resource.buffer_size) };
        dx12.device.CreateConstantBufferView(&instance_cbv_desc, instance_descriptor.cpu_handle);

        const vertex_buffer_resource = dx12_state.createResourceWithSize(std.unicode.utf8ToUtf16LeAllocZ(arenaAllocator, "VertexBuffer") catch unreachable, @sizeOf(mesh_data.Vertex) * all_vertices.items.len, .DEFAULT, dx12.device);
        const vertex_srv_desc = d3d12.SHADER_RESOURCE_VIEW_DESC.initStructuredBuffer(0, @as(u32, @intCast(all_vertices.items.len)), @sizeOf(mesh_data.Vertex));
        const vertex_buffer_descriptor = meshlet_heap.allocate();
        dx12.device.CreateShaderResourceView(vertex_buffer_resource.resource, &vertex_srv_desc, vertex_buffer_descriptor.cpu_handle);

        const index_buffer_resource = dx12_state.createResourceWithSize(std.unicode.utf8ToUtf16LeAllocZ(arenaAllocator, "IndexBuffer") catch unreachable, @sizeOf(u32) * all_indices.items.len, .DEFAULT, dx12.device);
        const index_srv_desc = d3d12.SHADER_RESOURCE_VIEW_DESC.initTypedBuffer(.R32_UINT, 0, @as(u32, @intCast(all_indices.items.len)));
        const index_buffer_descriptor = meshlet_heap.allocate();
        dx12.device.CreateShaderResourceView(index_buffer_resource.resource, &index_srv_desc, index_buffer_descriptor.cpu_handle);

        const meshlet_buffer_resource = dx12_state.createResourceWithSize(std.unicode.utf8ToUtf16LeAllocZ(arenaAllocator, "MeshletBuffer") catch unreachable, @sizeOf(mesh_data.Meshlet) * all_meshlets.items.len, .DEFAULT, dx12.device);
        const meshlet_srv_desc = d3d12.SHADER_RESOURCE_VIEW_DESC.initStructuredBuffer(0, @as(u32, @intCast(all_meshlets.items.len)), @sizeOf(mesh_data.Meshlet));
        const meshlet_buffer_descriptor = meshlet_heap.allocate();
        dx12.device.CreateShaderResourceView(meshlet_buffer_resource.resource, &meshlet_srv_desc, meshlet_buffer_descriptor.cpu_handle);

        const meshlet_data_buffer_resource = dx12_state.createResourceWithSize(std.unicode.utf8ToUtf16LeAllocZ(arenaAllocator, "MeshletDataBuffer") catch unreachable, @sizeOf(u32) * all_meshlets_data.items.len, .DEFAULT, dx12.device);
        const meshlet_data_srv_desc = d3d12.SHADER_RESOURCE_VIEW_DESC.initTypedBuffer(.R32_UINT, 0, @as(u32, @intCast(all_meshlets_data.items.len)));
        const meshlet_data_buffer_descriptor = meshlet_heap.allocate();
        dx12.device.CreateShaderResourceView(meshlet_data_buffer_resource.resource, &meshlet_data_srv_desc, meshlet_data_buffer_descriptor.cpu_handle);

        hrPanicOnFail(dx12.command_allocators[0].Reset());
        hrPanicOnFail(dx12.command_list.Reset(dx12.command_allocators[0], null));

        dx12_state.copyBuffer(mesh_data.Vertex, std.unicode.utf8ToUtf16LeAllocZ(arenaAllocator, "VertexUploadBuffer") catch unreachable, &all_vertices, &vertex_buffer_resource, dx12);
        dx12_state.copyBuffer(u32, std.unicode.utf8ToUtf16LeAllocZ(arenaAllocator, "IndexUploadBuffer") catch unreachable, &all_indices, &index_buffer_resource, dx12);
        dx12_state.copyBuffer(mesh_data.Meshlet, std.unicode.utf8ToUtf16LeAllocZ(arenaAllocator, "MeshletUploadBuffer") catch unreachable, &all_meshlets, &meshlet_buffer_resource, dx12);
        dx12_state.copyBuffer(u32, std.unicode.utf8ToUtf16LeAllocZ(arenaAllocator, "MeshletDataUploadBuffer") catch unreachable, &all_meshlets_data, &meshlet_data_buffer_resource, dx12);

        return Scene{
            .all_meshes = all_meshes,
            .all_vertices = all_vertices,
            .all_indices = all_indices,
            .all_meshlets = all_meshlets,
            .all_meshlets_data = all_meshlets_data,
            .root_signature = root_signature,
            .pipeline = pipeline,
            .camera_resource = camera_resource,
            .instance_resource = instance_resource,
            .meshlet_heap = meshlet_heap,
            .camera = camera,
            .camera_descriptor = camera_descriptor,
            .instance_descriptor = instance_descriptor,
            .vertex_buffer_resource = vertex_buffer_resource,
            .vertex_buffer_descriptor = vertex_buffer_descriptor,
            .index_buffer_resource = index_buffer_resource,
            .index_buffer_descriptor = index_buffer_descriptor,
            .meshlet_buffer_resource = meshlet_buffer_resource,
            .meshlet_buffer_descriptor = meshlet_buffer_descriptor,
            .meshlet_data_buffer_resource = meshlet_data_buffer_resource,
            .meshlet_data_buffer_descriptor = meshlet_data_buffer_descriptor,
        };
    }

    pub fn deinit(self: *Scene) void {
        _ = self.pipeline.Release();
        _ = self.root_signature.Release();

        self.meshlet_heap.deinit();

        self.all_meshes.deinit();
        self.all_vertices.deinit();
        self.all_indices.deinit();
        self.all_meshlets.deinit();
        self.all_meshlets_data.deinit();
    }
};
