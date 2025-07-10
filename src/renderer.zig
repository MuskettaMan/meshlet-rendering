const std = @import("std");
const MeshletPass = @import("meshlet_pass.zig").MeshletPass;
const Geometry = @import("geometry.zig").Geometry;
const dx12_state = @import("dx12_state.zig");
const Dx12State = dx12_state.Dx12State;
const zwindows = @import("zwindows");
const windows = zwindows.windows;
const d3d12 = zwindows.d3d12;
const CbvSrvHeap = @import("dx12_state.zig").CbvSrvHeap;
const Resource = @import("dx12_state.zig").Resource;
const Descriptor = @import("dx12_state.zig").Descriptor;
const Camera = @import("camera.zig").Camera;
const zmath = @import("zmath");
const zmesh = @import("zmesh");
const zcgltf = zmesh.io.zcgltf;

pub const Renderer = struct {
    dx12: Dx12State,
    meshlet_pass: MeshletPass,
    geometry: Geometry,

    default_heap: CbvSrvHeap,
    camera_resource: Resource,
    instance_resource: Resource,

    camera_descriptor: Descriptor,
    instance_descriptor: Descriptor,

    pub fn init(allocator: std.mem.Allocator, window: windows.HWND) !Renderer {
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();
        const arenaAllocator = arena.allocator();

        var dx12 = Dx12State.init(window) catch {
            windows.ExitProcess(0);
        };

        var paths = std.ArrayList([:0]const u8).init(allocator);
        defer paths.deinit();
        try paths.append("content/DragonAttenuation.glb");

        const data = zcgltf.parseAndLoadFile(paths.items[0]) catch unreachable;
        defer zcgltf.free(data);

        var geometry = try Geometry.init(allocator, &dx12);

        try geometry.loadMesh(allocator, data);

        const meshlet_pass = MeshletPass.init(&dx12, &geometry);

        var camera_resource = dx12_state.createResource(Camera, std.unicode.utf8ToUtf16LeAllocZ(arenaAllocator, "CameraBuffer") catch unreachable, .UPLOAD, dx12.device, true);

        var instance_resource = dx12_state.createResource(zmath.Mat, std.unicode.utf8ToUtf16LeAllocZ(arenaAllocator, "InstanceBuffer") catch unreachable, .UPLOAD, dx12.device, true);

        var default_heap = CbvSrvHeap.init(16, dx12.device);

        const camera_descriptor = default_heap.allocate();
        const camera_cbv_desc: d3d12.CONSTANT_BUFFER_VIEW_DESC = .{ .BufferLocation = camera_resource.resource.GetGPUVirtualAddress(), .SizeInBytes = @intCast(camera_resource.buffer_size) };
        dx12.device.CreateConstantBufferView(&camera_cbv_desc, camera_descriptor.cpu_handle);

        const instance_descriptor = default_heap.allocate();
        const instance_cbv_desc: d3d12.CONSTANT_BUFFER_VIEW_DESC = .{ .BufferLocation = instance_resource.resource.GetGPUVirtualAddress(), .SizeInBytes = @intCast(instance_resource.buffer_size) };
        dx12.device.CreateConstantBufferView(&instance_cbv_desc, instance_descriptor.cpu_handle);

        return Renderer{
            .dx12 = dx12,
            .meshlet_pass = meshlet_pass,
            .geometry = geometry,
            .default_heap = default_heap,
            .camera_resource = camera_resource,
            .instance_resource = instance_resource,
            .camera_descriptor = camera_descriptor,
            .instance_descriptor = instance_descriptor,
        };
    }

    pub fn deinit(self: *Renderer) void {
        self.dx12.deinit();
        self.meshlet_pass.deinit();
        self.geometry.deinit();

        self.default_heap.deinit();
        self.camera_resource.deinit();
        self.instance_resource.deinit();
    }
};
