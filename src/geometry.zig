const std = @import("std");
const mesh_data = @import("mesh_data.zig");
const Resource = @import("dx12_state.zig").Resource;
const dx12_state = @import("dx12_state.zig");
const Dx12State = dx12_state.Dx12State;
const zwindows = @import("zwindows");
const hrPanicOnFail = zwindows.hrPanicOnFail;

pub const Geometry = struct {
    meshes: std.ArrayList(mesh_data.Mesh),

    vertex_buffer_resource: Resource,
    index_buffer_resource: Resource,
    meshlet_buffer_resource: Resource,
    meshlet_data_buffer_resource: Resource,

    total_vertex_count: u32,
    total_index_count: u32,
    total_meshlet_count: u32,
    total_meshlet_data_count: u32,

    pub fn init(allocator: std.mem.Allocator, paths: *const std.ArrayList([:0]const u8), dx12: *const Dx12State) !Geometry {
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();

        const arenaAllocator = arena.allocator();

        var all_meshes = std.ArrayList(mesh_data.Mesh).init(allocator);

        var all_vertices = std.ArrayList(mesh_data.Vertex).init(arenaAllocator);
        var all_indices = std.ArrayList(u32).init(arenaAllocator);
        var all_meshlets = std.ArrayList(mesh_data.Meshlet).init(arenaAllocator);
        var all_meshlets_data = std.ArrayList(u32).init(arenaAllocator);

        //for (paths.items, 0..) |_, i| {
            try mesh_data.loadOptimizedMesh(allocator, &paths.items[0], &all_meshes, &all_vertices, &all_indices, &all_meshlets, &all_meshlets_data);
        //}

        const total_vertex_count: u32 = @intCast(all_vertices.items.len);
        const total_index_count: u32 = @intCast(all_indices.items.len);
        const total_meshlet_count: u32 = @intCast(all_meshlets.items.len);
        const total_meshlet_data_count: u32 = @intCast(all_meshlets_data.items.len);

        const vertex_buffer_resource = dx12_state.createResourceWithSize(std.unicode.utf8ToUtf16LeAllocZ(arenaAllocator, "VertexBuffer") catch unreachable, @sizeOf(mesh_data.Vertex) * total_vertex_count, .DEFAULT, dx12.device);
        const index_buffer_resource = dx12_state.createResourceWithSize(std.unicode.utf8ToUtf16LeAllocZ(arenaAllocator, "IndexBuffer") catch unreachable, @sizeOf(u32) * total_index_count, .DEFAULT, dx12.device);
        const meshlet_buffer_resource = dx12_state.createResourceWithSize(std.unicode.utf8ToUtf16LeAllocZ(arenaAllocator, "MeshletBuffer") catch unreachable, @sizeOf(mesh_data.Meshlet) * total_meshlet_count, .DEFAULT, dx12.device);
        const meshlet_data_buffer_resource = dx12_state.createResourceWithSize(std.unicode.utf8ToUtf16LeAllocZ(arenaAllocator, "MeshletDataBuffer") catch unreachable, @sizeOf(u32) * total_meshlet_data_count, .DEFAULT, dx12.device);

        hrPanicOnFail(dx12.command_allocators[0].Reset());
        hrPanicOnFail(dx12.command_list.Reset(dx12.command_allocators[0], null));

        dx12_state.copyBuffer(mesh_data.Vertex, std.unicode.utf8ToUtf16LeAllocZ(arenaAllocator, "VertexUploadBuffer") catch unreachable, &all_vertices, &vertex_buffer_resource, dx12);
        dx12_state.copyBuffer(u32, std.unicode.utf8ToUtf16LeAllocZ(arenaAllocator, "IndexUploadBuffer") catch unreachable, &all_indices, &index_buffer_resource, dx12);
        dx12_state.copyBuffer(mesh_data.Meshlet, std.unicode.utf8ToUtf16LeAllocZ(arenaAllocator, "MeshletUploadBuffer") catch unreachable, &all_meshlets, &meshlet_buffer_resource, dx12);
        dx12_state.copyBuffer(u32, std.unicode.utf8ToUtf16LeAllocZ(arenaAllocator, "MeshletDataUploadBuffer") catch unreachable, &all_meshlets_data, &meshlet_data_buffer_resource, dx12);

        return Geometry{
            .meshes = all_meshes,
            .vertex_buffer_resource = vertex_buffer_resource,
            .index_buffer_resource = index_buffer_resource,
            .meshlet_buffer_resource = meshlet_buffer_resource,
            .meshlet_data_buffer_resource = meshlet_data_buffer_resource,
            .total_vertex_count = total_vertex_count,
            .total_index_count = total_index_count,
            .total_meshlet_count = total_meshlet_count,
            .total_meshlet_data_count = total_meshlet_data_count,
        };
    }

    pub fn deinit(self: *const Geometry) void {
        self.meshes.deinit();

        self.vertex_buffer_resource.deinit();
        self.index_buffer_resource.deinit();
        self.meshlet_buffer_resource.deinit();
        self.meshlet_data_buffer_resource.deinit();
    }
};
