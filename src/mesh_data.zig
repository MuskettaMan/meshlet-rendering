const zmath = @import("zmath");
const zmesh = @import("zmesh");
const std = @import("std");

const assert = std.debug.assert;
const zcgltf = zmesh.io.zcgltf;

pub const max_num_meshlet_vertices: usize = 64;
pub const max_num_meshlet_triangles: usize = 64;

pub const Vertex = struct {
    position: [3]f32,
    normal: [3]f32,
};

pub const Mesh = struct {
    index_offset: u32,
    vertex_offset: u32,
    meshlet_offset: u32,
    num_indices: u32,
    num_vertices: u32,
    num_meshlets: u32,
};

pub const Meshlet = struct {
    data_offset: u32 align(8),
    num_vertices: u16,
    num_triangles: u16,
};
comptime {
    assert(@sizeOf(Meshlet) == 8);
    assert(@alignOf(Meshlet) == 8);
}

pub fn loadOptimizedMesh(allocator: std.mem.Allocator, path: *const [:0]const u8, mesh_index: u32, all_meshes: *std.ArrayList(Mesh), all_vertices: *std.ArrayList(Vertex), all_indices: *std.ArrayList(u32), all_meshlets: *std.ArrayList(Meshlet), all_meshlets_data: *std.ArrayList(u32)) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const arenaAllocator = arena.allocator();

    const data = zcgltf.parseAndLoadFile(path.*) catch unreachable;
    defer zcgltf.free(data);

    var mesh_indices = std.ArrayList(u32).init(arenaAllocator);
    var mesh_positions = std.ArrayList([3]f32).init(arenaAllocator);
    var mesh_normals = std.ArrayList([3]f32).init(arenaAllocator);

    zcgltf.appendMeshPrimitive(data, mesh_index, 0, &mesh_indices, &mesh_positions, &mesh_normals, null, null) catch unreachable;

    var mesh_vertices = std.ArrayList(Vertex).init(arenaAllocator);
    try mesh_vertices.resize(mesh_positions.items.len);
    for (0..mesh_vertices.items.len) |i| {
        mesh_vertices.items[i] = .{
            .position = mesh_positions.items[i],
            .normal = mesh_normals.items[i],
        };
    }

    var remap = std.ArrayList(u32).init(arenaAllocator);
    try remap.resize(mesh_indices.items.len);

    const num_unique_vertices = zmesh.opt.generateVertexRemap(remap.items, mesh_indices.items, Vertex, mesh_vertices.items);

    var optimized_vertices = std.ArrayList(Vertex).init(arenaAllocator);
    try optimized_vertices.resize(num_unique_vertices);

    zmesh.opt.remapVertexBuffer(Vertex, optimized_vertices.items, mesh_vertices.items, remap.items);

    var optimized_indices = std.ArrayList(u32).init(arenaAllocator);
    try optimized_indices.resize(mesh_indices.items.len);
    zmesh.opt.remapIndexBuffer(optimized_indices.items, mesh_indices.items, remap.items);

    zmesh.opt.optimizeVertexCache(optimized_indices.items, optimized_indices.items, optimized_vertices.items.len);
    const num_optimized_vertices = zmesh.opt.optimizeVertexFetch(Vertex, optimized_vertices.items, optimized_indices.items, optimized_vertices.items);
    assert(num_optimized_vertices == optimized_vertices.items.len);

    const max_num_meshlets = zmesh.opt.buildMeshletsBound(optimized_indices.items.len, max_num_meshlet_vertices, max_num_meshlet_triangles);

    var meshlets = std.ArrayList(zmesh.opt.Meshlet).init(arenaAllocator);
    var meshlets_vertices = std.ArrayList(u32).init(arenaAllocator);
    var meshlets_triangles = std.ArrayList(u8).init(arenaAllocator);

    try meshlets.resize(max_num_meshlets);
    try meshlets_vertices.resize(max_num_meshlets * max_num_meshlet_vertices);
    try meshlets_triangles.resize(max_num_meshlets * max_num_meshlet_triangles * 3);

    const num_meshlets = zmesh.opt.buildMeshlets(meshlets.items, meshlets_vertices.items, meshlets_triangles.items, optimized_indices.items, Vertex, optimized_vertices.items, max_num_meshlet_vertices, max_num_meshlet_triangles, 0.0);
    assert(num_meshlets <= max_num_meshlets);
    try meshlets.resize(num_meshlets);

    try all_meshes.append(.{
        .index_offset = @as(u32, @intCast(all_indices.items.len)),
        .vertex_offset = @as(u32, @intCast(all_vertices.items.len)),
        .meshlet_offset = @as(u32, @intCast(all_meshlets.items.len)),
        .num_indices = @as(u32, @intCast(optimized_indices.items.len)),
        .num_vertices = @as(u32, @intCast(optimized_vertices.items.len)),
        .num_meshlets = @as(u32, @intCast(meshlets.items.len)),
    });

    for (meshlets.items) |src_meshlet| {
        const meshlet = Meshlet{
            .data_offset = @as(u32, @intCast(all_meshlets_data.items.len)),
            .num_vertices = @as(u16, @intCast(src_meshlet.vertex_count)),
            .num_triangles = @as(u16, @intCast(src_meshlet.triangle_count)),
        };
        try all_meshlets.append(meshlet);

        for (0..src_meshlet.vertex_count) |i| {
            try all_meshlets_data.append(meshlets_vertices.items[src_meshlet.vertex_offset + i]);
        }

        for (0..src_meshlet.triangle_count) |i| {
            const index0 = @as(u10, @intCast(meshlets_triangles.items[src_meshlet.triangle_offset + i * 3 + 0]));
            const index1 = @as(u10, @intCast(meshlets_triangles.items[src_meshlet.triangle_offset + i * 3 + 1]));
            const index2 = @as(u10, @intCast(meshlets_triangles.items[src_meshlet.triangle_offset + i * 3 + 2]));
            const prim = @as(u32, @intCast(index0)) | (@as(u32, @intCast(index1)) << 10 | @as(u32, @intCast(index2)) << 20);
            try all_meshlets_data.append(prim);
        }
    }

    try all_indices.appendSlice(optimized_indices.items);
    try all_vertices.appendSlice(optimized_vertices.items);
}
