const std = @import("std");
const Descriptor = @import("dx12_state.zig").Descriptor;
const CbvSrvHeap = @import("dx12_state.zig").CbvSrvHeap;
const d3d12 = @import("zwindows").d3d12;
const Geometry = @import("geometry.zig").Geometry;
const mesh_data = @import("mesh_data.zig");
const Dx12State = @import("dx12_state.zig").Dx12State;

pub const MeshletResources = struct {
    heap: CbvSrvHeap,
    vertex_buffer_descriptor: Descriptor,
    index_buffer_descriptor: Descriptor,
    meshlet_buffer_descriptor: Descriptor,
    meshlet_data_buffer_descriptor: Descriptor,

    pub fn init(geometry: *const Geometry, dx12: *const Dx12State) MeshletResources {
        var heap = CbvSrvHeap.init(4, dx12.device);

        const vertex_srv_desc = d3d12.SHADER_RESOURCE_VIEW_DESC.initStructuredBuffer(0, @intCast(geometry.vertex_buffer_resource.buffer_size / @sizeOf(mesh_data.Vertex)), @sizeOf(mesh_data.Vertex));
        const vertex_buffer_descriptor = heap.allocate();
        dx12.device.CreateShaderResourceView(geometry.vertex_buffer_resource.resource, &vertex_srv_desc, vertex_buffer_descriptor.cpu_handle);

        const index_srv_desc = d3d12.SHADER_RESOURCE_VIEW_DESC.initTypedBuffer(.R32_UINT, 0, @intCast(geometry.index_buffer_resource.buffer_size / @sizeOf(u32)));
        const index_buffer_descriptor = heap.allocate();
        dx12.device.CreateShaderResourceView(geometry.index_buffer_resource.resource, &index_srv_desc, index_buffer_descriptor.cpu_handle);

        const meshlet_srv_desc = d3d12.SHADER_RESOURCE_VIEW_DESC.initStructuredBuffer(0, @intCast(geometry.meshlet_buffer_resource.buffer_size / @sizeOf(mesh_data.Meshlet)), @sizeOf(mesh_data.Meshlet));
        const meshlet_buffer_descriptor = heap.allocate();
        dx12.device.CreateShaderResourceView(geometry.meshlet_buffer_resource.resource, &meshlet_srv_desc, meshlet_buffer_descriptor.cpu_handle);

        const meshlet_data_srv_desc = d3d12.SHADER_RESOURCE_VIEW_DESC.initTypedBuffer(.R32_UINT, 0, @intCast(geometry.meshlet_data_buffer_resource.buffer_size / @sizeOf(u32)));
        const meshlet_data_buffer_descriptor = heap.allocate();
        dx12.device.CreateShaderResourceView(geometry.meshlet_data_buffer_resource.resource, &meshlet_data_srv_desc, meshlet_data_buffer_descriptor.cpu_handle);

        return MeshletResources{
            .heap = heap,
            .vertex_buffer_descriptor = vertex_buffer_descriptor,
            .index_buffer_descriptor = index_buffer_descriptor,
            .meshlet_buffer_descriptor = meshlet_buffer_descriptor,
            .meshlet_data_buffer_descriptor = meshlet_data_buffer_descriptor,
        };
    }

    pub fn deinit(self: *MeshletResources) void {
        self.heap.deinit();
    }
};
