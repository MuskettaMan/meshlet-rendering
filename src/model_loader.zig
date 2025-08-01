const std = @import("std");
const zmath = @import("zmath");
const zmesh = @import("zmesh");
const zcgltf = zmesh.io.zcgltf;
const Vertex = @import("mesh_data.zig").Vertex;

pub const Node = struct {
    mesh: u32,
    transform: zmath.Mat,
};

pub const CPUMesh = struct {
    vertices: std.ArrayList(Vertex),
    indices: std.ArrayList(u32),

    pub fn init(allocator: std.mem.Allocator) !CPUMesh {
        return .{
            .vertices = std.ArrayList(Vertex).init(allocator),
            .indices = std.ArrayList(u32).init(allocator),
        };
    }

    pub fn deinit(self: *CPUModel) !void {
        self.meshes.deinit();
        self.scene.deinit();
    }
};

pub const CPUModel = struct {
    meshes: std.ArrayList(CPUMesh),
    scene: std.ArrayList(Node),

    pub fn init(allocator: std.mem.Allocator) !CPUModel {
        return .{
            .meshes = std.ArrayList(CPUMesh).init(allocator),
            .scene = std.ArrayList(Node).init(allocator),
        };
    }

    pub fn deinit(self: *CPUModel) !void {
        self.meshes.deinit();
        self.scene.deinit();
    }
};

pub fn load(path: [:0]const u8, allocator: std.mem.Allocator) !CPUModel {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const arenaAllocator = arena.allocator();

    const data = zcgltf.parseAndLoadFile(path) catch unreachable;

    var model = try CPUModel.init(allocator);

    for (0..data.meshes_count) |mesh_index| {
        var mesh = try CPUMesh.init(allocator);

        var mesh_positions = std.ArrayList([3]f32).init(arenaAllocator);
        var mesh_normals = std.ArrayList([3]f32).init(arenaAllocator);

        zcgltf.appendMeshPrimitive(data, @intCast(mesh_index), 0, &mesh.indices, &mesh_positions, &mesh_normals, null, null) catch unreachable;

        try mesh.vertices.resize(mesh_positions.items.len);
        for (0..mesh.vertices.items.len) |i| {
            mesh.vertices.items[i] = .{
                .position = mesh_positions.items[i],
                .normal = mesh_normals.items[i],
            };
        }

        try model.meshes.append(mesh);
    }

    for (0..data.nodes_count) |node_index| {
        const gltf_node = &data.nodes.?[node_index];
        if (gltf_node.mesh == null) {
            continue;
        }

        const node = try model.scene.addOne();

        node.transform = zmath.matFromArr(gltf_node.transformWorld());

        node.mesh = @intCast((@intFromPtr(gltf_node.mesh) - @intFromPtr(data.meshes)) / @sizeOf(@TypeOf(gltf_node.mesh.?.*)));
    }

    return model;
}
