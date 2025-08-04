const std = @import("std");
const mesh_data = @import("mesh_data.zig");
const Resource = @import("dx12_state.zig").Resource;
const dx12_state = @import("dx12_state.zig");
const Dx12State = dx12_state.Dx12State;
const zwindows = @import("zwindows");
const hrPanicOnFail = zwindows.hrPanicOnFail;
const zmesh = @import("zmesh");
const zcgltf = zmesh.io.zcgltf;
const ModelLoader = @import("model_loader.zig");
const W = std.unicode.utf8ToUtf16LeStringLiteral;

const KB = 1024;
const MB = KB * 1024;
const GB = MB * 1024;

const VERTEX_BUFFER_SIZE = 128 * MB;
const INDEX_BUFFER_SIZE = 128 * MB;
const MESHLET_BUFFER_SIZE = 16 * MB;
const MESHLET_DATA_BUFFER_SIZE = 32 * MB;

pub const MeshHandle = u32;

pub const Mesh = struct {
    start: u32,
    length: u32,
};

pub const Geometry = struct {
    primitives: std.ArrayList(mesh_data.Primitive),
    meshes: std.ArrayList(Mesh),

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

        const primitives = std.ArrayList(mesh_data.Primitive).init(allocator);
        const meshes = std.ArrayList(Mesh).init(allocator);

        const vertex_buffer_resource = dx12_state.createResourceWithSize(std.unicode.utf8ToUtf16LeAllocZ(arenaAllocator, "VertexBuffer") catch unreachable, VERTEX_BUFFER_SIZE, .DEFAULT, dx12.device);
        const index_buffer_resource = dx12_state.createResourceWithSize(std.unicode.utf8ToUtf16LeAllocZ(arenaAllocator, "IndexBuffer") catch unreachable, INDEX_BUFFER_SIZE, .DEFAULT, dx12.device);
        const meshlet_buffer_resource = dx12_state.createResourceWithSize(std.unicode.utf8ToUtf16LeAllocZ(arenaAllocator, "MeshletBuffer") catch unreachable, MESHLET_BUFFER_SIZE, .DEFAULT, dx12.device);
        const meshlet_data_buffer_resource = dx12_state.createResourceWithSize(std.unicode.utf8ToUtf16LeAllocZ(arenaAllocator, "MeshletDataBuffer") catch unreachable, MESHLET_DATA_BUFFER_SIZE, .DEFAULT, dx12.device);

        return Geometry{ .primitives = primitives, .meshes = meshes, .vertex_buffer_resource = vertex_buffer_resource, .index_buffer_resource = index_buffer_resource, .meshlet_buffer_resource = meshlet_buffer_resource, .meshlet_data_buffer_resource = meshlet_data_buffer_resource, .dx12 = dx12 };
    }

    pub fn deinit(self: *const Geometry) void {
        self.meshes.deinit();
        self.primitives.deinit();

        self.vertex_buffer_resource.deinit();
        self.index_buffer_resource.deinit();
        self.meshlet_buffer_resource.deinit();
        self.meshlet_data_buffer_resource.deinit();
    }

    pub fn loadMesh(self: *Geometry, allocator: std.mem.Allocator, cpuMesh: *ModelLoader.CPUMesh) !MeshHandle {
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();

        const arenaAllocator = arena.allocator();

        var all_vertices = std.ArrayList(mesh_data.Vertex).init(arenaAllocator);
        var all_indices = std.ArrayList(u32).init(arenaAllocator);
        var all_meshlets = std.ArrayList(mesh_data.Meshlet).init(arenaAllocator);
        var all_meshlets_data = std.ArrayList(u32).init(arenaAllocator);

        const mesh = Mesh{ .start = @intCast(self.primitives.items.len), .length = @intCast(cpuMesh.primitives.items.len) };
        try self.meshes.append(mesh);

        // Used for offset into GPU buffer (where to start writing)
        const total_vertex_count: u32 = self.total_vertex_count;
        const total_index_count: u32 = self.total_index_count;
        const total_meshlet_count: u32 = self.total_meshlet_count;
        const total_meshlet_data_count: u32 = self.total_meshlet_data_count;

        for (cpuMesh.primitives.items) |*primitive| {
            try mesh_data.loadOptimizedMesh(allocator, primitive, &self.primitives, &all_vertices, &all_indices, &all_meshlets, &all_meshlets_data);

            const prim = &self.primitives.items[self.primitives.items.len - 1];

            prim.vertex_offset += self.total_vertex_count;
            prim.index_offset += self.total_index_count;
            prim.meshlet_offset += self.total_meshlet_count;
        }

        for (all_meshlets.items) |*meshlet| {
            meshlet.data_offset += total_meshlet_data_count;
        }

        self.total_vertex_count += @intCast(all_vertices.items.len);
        self.total_index_count += @intCast(all_indices.items.len);
        self.total_meshlet_count += @intCast(all_meshlets.items.len);
        self.total_meshlet_data_count += @intCast(all_meshlets_data.items.len);

        std.debug.assert(@sizeOf(mesh_data.Vertex) * self.total_vertex_count < VERTEX_BUFFER_SIZE);
        std.debug.assert(@sizeOf(u32) * self.total_index_count < INDEX_BUFFER_SIZE);
        std.debug.assert(@sizeOf(mesh_data.Meshlet) * self.total_meshlet_count < MESHLET_BUFFER_SIZE);
        std.debug.assert(@sizeOf(u32) * self.total_meshlet_data_count < MESHLET_DATA_BUFFER_SIZE);

        dx12_state.copyBuffer(mesh_data.Vertex, W("VertexUploadBuffer"), &all_vertices, &self.vertex_buffer_resource, @sizeOf(mesh_data.Vertex) * total_vertex_count, self.dx12);
        dx12_state.copyBuffer(u32, W("IndexUploadBuffer"), &all_indices, &self.index_buffer_resource, @sizeOf(u32) * total_index_count, self.dx12);
        dx12_state.copyBuffer(mesh_data.Meshlet, W("MeshletUploadBuffer"), &all_meshlets, &self.meshlet_buffer_resource, @sizeOf(mesh_data.Meshlet) * total_meshlet_count, self.dx12);
        dx12_state.copyBuffer(u32, W("MeshletDataUploadBuffer"), &all_meshlets_data, &self.meshlet_data_buffer_resource, @sizeOf(u32) * total_meshlet_data_count, self.dx12);
        return @intCast(self.meshes.items.len - 1);
    }
};
