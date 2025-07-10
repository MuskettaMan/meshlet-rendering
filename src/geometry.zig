const std = @import("std");
const mesh_data = @import("mesh_data.zig");
const Resource = @import("dx12_state.zig").Resource;
const dx12_state = @import("dx12_state.zig");
const Dx12State = dx12_state.Dx12State;
const zwindows = @import("zwindows");
const hrPanicOnFail = zwindows.hrPanicOnFail;
const zmesh = @import("zmesh");
const zcgltf = zmesh.io.zcgltf;

const KB = 1024;
const MB = KB * 1024;
const GB = MB * 1024;

const VERTEX_BUFFER_SIZE = 16 * MB;
const INDEX_BUFFER_SIZE = 16 * MB;
const MESHLET_BUFFER_SIZE = 2 * MB;
const MESHLET_DATA_BUFFER_SIZE = 8 * MB;

pub const Geometry = struct {
    meshes: std.ArrayList(mesh_data.Mesh),

    vertex_buffer_resource: Resource,
    index_buffer_resource: Resource,
    meshlet_buffer_resource: Resource,
    meshlet_data_buffer_resource: Resource,

    dx12: *Dx12State,

    total_vertex_count: u32 = 0,
    total_index_count: u32 = 0,
    total_meshlet_count: u32 = 0,
    total_meshlet_data_count: u32 = 0,

    pub fn init(allocator: std.mem.Allocator, dx12: *Dx12State) !Geometry {
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();

        const arenaAllocator = arena.allocator();

        const all_meshes = std.ArrayList(mesh_data.Mesh).init(allocator);

        const vertex_buffer_resource = dx12_state.createResourceWithSize(std.unicode.utf8ToUtf16LeAllocZ(arenaAllocator, "VertexBuffer") catch unreachable, VERTEX_BUFFER_SIZE, .DEFAULT, dx12.device);
        const index_buffer_resource = dx12_state.createResourceWithSize(std.unicode.utf8ToUtf16LeAllocZ(arenaAllocator, "IndexBuffer") catch unreachable, INDEX_BUFFER_SIZE, .DEFAULT, dx12.device);
        const meshlet_buffer_resource = dx12_state.createResourceWithSize(std.unicode.utf8ToUtf16LeAllocZ(arenaAllocator, "MeshletBuffer") catch unreachable, MESHLET_BUFFER_SIZE, .DEFAULT, dx12.device);
        const meshlet_data_buffer_resource = dx12_state.createResourceWithSize(std.unicode.utf8ToUtf16LeAllocZ(arenaAllocator, "MeshletDataBuffer") catch unreachable, MESHLET_DATA_BUFFER_SIZE, .DEFAULT, dx12.device);

        return Geometry{ .meshes = all_meshes, .vertex_buffer_resource = vertex_buffer_resource, .index_buffer_resource = index_buffer_resource, .meshlet_buffer_resource = meshlet_buffer_resource, .meshlet_data_buffer_resource = meshlet_data_buffer_resource, .dx12 = dx12 };
    }

    pub fn deinit(self: *const Geometry) void {
        self.meshes.deinit();

        self.vertex_buffer_resource.deinit();
        self.index_buffer_resource.deinit();
        self.meshlet_buffer_resource.deinit();
        self.meshlet_data_buffer_resource.deinit();
    }

    pub fn loadMesh(self: *Geometry, allocator: std.mem.Allocator, data: *zcgltf.Data) !void {
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();

        const arenaAllocator = arena.allocator();

        var all_vertices = std.ArrayList(mesh_data.Vertex).init(arenaAllocator);
        var all_indices = std.ArrayList(u32).init(arenaAllocator);
        var all_meshlets = std.ArrayList(mesh_data.Meshlet).init(arenaAllocator);
        var all_meshlets_data = std.ArrayList(u32).init(arenaAllocator);

        try mesh_data.loadOptimizedMesh(allocator, data, &self.meshes, &all_vertices, &all_indices, &all_meshlets, &all_meshlets_data);

        const total_vertex_count: u32 = @intCast(all_vertices.items.len);
        const total_index_count: u32 = @intCast(all_indices.items.len);
        const total_meshlet_count: u32 = @intCast(all_meshlets.items.len);
        const total_meshlet_data_count: u32 = @intCast(all_meshlets_data.items.len);

        hrPanicOnFail(self.dx12.command_allocators[0].Reset());
        hrPanicOnFail(self.dx12.command_list.Reset(self.dx12.command_allocators[0], null));

        dx12_state.copyBuffer(mesh_data.Vertex, std.unicode.utf8ToUtf16LeAllocZ(arenaAllocator, "VertexUploadBuffer") catch unreachable, &all_vertices, &self.vertex_buffer_resource, @sizeOf(mesh_data.Vertex) * self.total_vertex_count, self.dx12);
        dx12_state.copyBuffer(u32, std.unicode.utf8ToUtf16LeAllocZ(arenaAllocator, "IndexUploadBuffer") catch unreachable, &all_indices, &self.index_buffer_resource, @sizeOf(u32) * self.total_vertex_count, self.dx12);
        dx12_state.copyBuffer(mesh_data.Meshlet, std.unicode.utf8ToUtf16LeAllocZ(arenaAllocator, "MeshletUploadBuffer") catch unreachable, &all_meshlets, &self.meshlet_buffer_resource, @sizeOf(mesh_data.Meshlet) * self.total_vertex_count, self.dx12);
        dx12_state.copyBuffer(u32, std.unicode.utf8ToUtf16LeAllocZ(arenaAllocator, "MeshletDataUploadBuffer") catch unreachable, &all_meshlets_data, &self.meshlet_data_buffer_resource, @sizeOf(u32) * self.total_vertex_count, self.dx12);

        self.total_vertex_count += total_vertex_count;
        self.total_index_count += total_index_count;
        self.total_meshlet_count += total_meshlet_count;
        self.total_meshlet_data_count += total_meshlet_data_count;
    }
};
