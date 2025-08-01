const std = @import("std");
const Descriptor = @import("dx12_state.zig").Descriptor;
const CbvSrvHeap = @import("dx12_state.zig").CbvSrvHeap;
const d3d12 = @import("zwindows").d3d12;
const Geometry = @import("geometry.zig").Geometry;
const mesh_data = @import("mesh_data.zig");
const Dx12State = @import("dx12_state.zig").Dx12State;

pub const RasterResources = struct {
    vbv: d3d12.VERTEX_BUFFER_VIEW,
    ibv: d3d12.INDEX_BUFFER_VIEW,

    pub fn init(geometry: *const Geometry) RasterResources {
        const vbv_desc = d3d12.VERTEX_BUFFER_VIEW{
            .BufferLocation = geometry.vertex_buffer_resource.resource.GetGPUVirtualAddress(),
            .SizeInBytes = @intCast(geometry.vertex_buffer_resource.buffer_size),
            .StrideInBytes = @sizeOf(mesh_data.Vertex),
        };

        const ibv_desc = d3d12.INDEX_BUFFER_VIEW{
            .BufferLocation = geometry.index_buffer_resource.resource.GetGPUVirtualAddress(),
            .Format = .R32_UINT,
            .SizeInBytes = @intCast(geometry.index_buffer_resource.buffer_size),
        };

        return RasterResources{
            .vbv = vbv_desc,
            .ibv = ibv_desc,
        };
    }

    //pub fn deinit(self: *RasterResources) void {
    //}
};
