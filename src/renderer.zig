const std = @import("std");
const MeshletPass = @import("meshlet_pass.zig").MeshletPass;
const Geometry = @import("geometry.zig").Geometry;
const dx12_state = @import("dx12_state.zig");
const Dx12State = dx12_state.Dx12State;
const zgui = @import("zgui");
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
const hrPanicOnFail = zwindows.hrPanicOnFail;
const Window = @import("win_util.zig").Window;

const DrawMode = enum { Wireframe, Shaded };

pub const Draw = struct {
    mesh: u32,
    transform: zmath.Mat,
};

pub const Instance = struct {
    transform: zmath.Mat,
};

const RootConst = extern struct {
    vertex_offset: u32,
    meshlet_offset: u32,
    draw_mode: u32,
    instance_id: u32,
};

const INSTANCE_COUNT = 64;

pub const Renderer = struct {
    dx12: Dx12State,
    meshlet_pass: MeshletPass,
    geometry: Geometry,

    default_heap: CbvSrvHeap,
    zgui_heap: CbvSrvHeap,
    camera_resource: Resource,
    instances_resource: Resource,

    camera_descriptor: Descriptor,
    instance_descriptor: Descriptor,
    font_descriptor: Descriptor,

    width: u32,
    height: u32,

    draw_mode: DrawMode,

    draws: std.ArrayList(Draw),

    pub fn init(allocator: std.mem.Allocator, window: *const Window) !Renderer {
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();
        const arenaAllocator = arena.allocator();

        var dx12 = Dx12State.init(window.handle) catch {
            windows.ExitProcess(0);
        };

        var zgui_heap = CbvSrvHeap.init(1, dx12.device);
        const font_descriptor = zgui_heap.allocate();

        zgui.backend.init(window, .{
            .device = dx12.device,
            .command_queue = dx12.command_queue,
            .num_frames_in_flight = Dx12State.num_frames,
            .rtv_format = @intFromEnum(Dx12State.rtv_format),
            .dsv_format = @intFromEnum(Dx12State.dsv_format),
            .cbv_srv_heap = zgui_heap.heap,
            .font_srv_cpu_desc_handle = @bitCast(font_descriptor.cpu_handle),
            .font_srv_gpu_desc_handle = @bitCast(font_descriptor.gpu_handle),
        });

        var paths = std.ArrayList([:0]const u8).init(allocator);
        defer paths.deinit();
        try paths.append("content/DragonAttenuation.glb");

        const data = zcgltf.parseAndLoadFile(paths.items[0]) catch unreachable;
        defer zcgltf.free(data);

        var geometry = try Geometry.init(allocator, &dx12);

        try geometry.loadMesh(allocator, data);

        const meshlet_pass = MeshletPass.init(&dx12, &geometry);

        var camera_resource = dx12_state.createResource(Camera, std.unicode.utf8ToUtf16LeAllocZ(arenaAllocator, "CameraBuffer") catch unreachable, .UPLOAD, dx12.device, true);

        var instances_resource = dx12_state.createResource([INSTANCE_COUNT]zmath.Mat, std.unicode.utf8ToUtf16LeAllocZ(arenaAllocator, "InstanceBuffer") catch unreachable, .UPLOAD, dx12.device, true);

        var default_heap = CbvSrvHeap.init(16, dx12.device);

        const camera_descriptor = default_heap.allocate();
        const camera_cbv_desc: d3d12.CONSTANT_BUFFER_VIEW_DESC = .{ .BufferLocation = camera_resource.resource.GetGPUVirtualAddress(), .SizeInBytes = @intCast(camera_resource.buffer_size) };
        dx12.device.CreateConstantBufferView(&camera_cbv_desc, camera_descriptor.cpu_handle);

        const instance_descriptor = default_heap.allocate();
        const instance_cbv_desc: d3d12.CONSTANT_BUFFER_VIEW_DESC = .{ .BufferLocation = instances_resource.resource.GetGPUVirtualAddress(), .SizeInBytes = @intCast(instances_resource.buffer_size) };
        dx12.device.CreateConstantBufferView(&instance_cbv_desc, instance_descriptor.cpu_handle);

        return Renderer{
            .dx12 = dx12,
            .meshlet_pass = meshlet_pass,
            .geometry = geometry,
            .default_heap = default_heap,
            .zgui_heap = zgui_heap,
            .camera_resource = camera_resource,
            .instances_resource = instances_resource,
            .camera_descriptor = camera_descriptor,
            .instance_descriptor = instance_descriptor,
            .font_descriptor = font_descriptor,
            .width = 0,
            .height = 0,
            .draw_mode = DrawMode.Shaded,
            .draws = std.ArrayList(Draw).init(allocator),
        };
    }

    pub fn deinit(self: *Renderer) void {
        self.dx12.deinit();
        self.meshlet_pass.deinit();
        self.geometry.deinit();

        self.default_heap.deinit();
        self.camera_resource.deinit();
        self.instances_resource.deinit();
        self.zgui_heap.deinit();

        self.draws.deinit();

        zgui.backend.deinit();
    }

    pub fn render(self: *Renderer) void {
        const command_allocator = self.dx12.command_allocators[self.dx12.frame_index];
        const command_list = self.dx12.command_list;

        const instances_ptr = @as([*]Instance, @alignCast(@ptrCast(self.instances_resource.map())));
        defer self.instances_resource.unmap();

        hrPanicOnFail(command_allocator.Reset());
        hrPanicOnFail(self.dx12.command_list.Reset(command_allocator, null));

        self.dx12.command_list.RSSetViewports(1, &.{.{
            .TopLeftX = 0.0,
            .TopLeftY = 0.0,
            .Width = @floatFromInt(self.width),
            .Height = @floatFromInt(self.height),
            .MinDepth = 0.0,
            .MaxDepth = 1.0,
        }});
        self.dx12.command_list.RSSetScissorRects(1, &.{.{
            .left = 0,
            .top = 0,
            .right = @intCast(self.width),
            .bottom = @intCast(self.height),
        }});

        const back_buffer_index = self.dx12.swap_chain.GetCurrentBackBufferIndex();
        const back_buffer_descriptor = d3d12.CPU_DESCRIPTOR_HANDLE{ .ptr = self.dx12.rtv_heap_start.ptr + back_buffer_index * self.dx12.device.GetDescriptorHandleIncrementSize(.RTV) };

        command_list.ResourceBarrier(1, &.{.{ .Type = .TRANSITION, .Flags = .{}, .u = .{ .Transition = .{
            .pResource = self.dx12.swap_chain_textures[back_buffer_index],
            .Subresource = d3d12.RESOURCE_BARRIER_ALL_SUBRESOURCES,
            .StateBefore = d3d12.RESOURCE_STATES.PRESENT,
            .StateAfter = .{ .RENDER_TARGET = true },
        } } }});

        command_list.OMSetRenderTargets(1, &.{back_buffer_descriptor}, windows.TRUE, &self.dx12.depth_heap_handle);
        command_list.ClearDepthStencilView(self.dx12.depth_heap_handle, .{ .DEPTH = true }, 1.0, 0, 0, null);
        command_list.ClearRenderTargetView(back_buffer_descriptor, &.{ 0.2, 0.2, 0.8, 1.0 }, 0, null);

        zgui.backend.newFrame(@intCast(self.width), @intCast(self.height));

        // Can draw gui elemenets here.
        if (zgui.begin("Settings", .{ .flags = .{ .always_auto_resize = true } })) {
            _ = zgui.comboFromEnum("Draw Mode", &self.draw_mode);
            zgui.end();
        }

        const geometry = &self.geometry;
        const meshlet_pass = &self.meshlet_pass;
        const meshlet_resources = &meshlet_pass.resources;

        command_list.IASetPrimitiveTopology(.TRIANGLELIST);
        command_list.SetPipelineState(meshlet_pass.pipeline);
        command_list.SetGraphicsRootSignature(meshlet_pass.root_signature);

        command_list.SetGraphicsRootConstantBufferView(0, self.camera_resource.resource.GetGPUVirtualAddress());
        command_list.SetGraphicsRootConstantBufferView(1, self.instances_resource.resource.GetGPUVirtualAddress());

        const heaps = [_]*d3d12.IDescriptorHeap{meshlet_resources.heap.heap};
        command_list.SetDescriptorHeaps(1, &heaps);
        command_list.SetGraphicsRootDescriptorTable(3, meshlet_resources.vertex_buffer_descriptor.gpu_handle);

        for (self.draws.items, 0..) |*draw, i| {
            const mesh = geometry.meshes.items[draw.mesh];

            const dst_instance_ptr = &instances_ptr[i];

            std.mem.copyForwards(u8, std.mem.asBytes(dst_instance_ptr), std.mem.asBytes(&draw.transform));

            const root_const: RootConst = .{
                .vertex_offset = mesh.vertex_offset,
                .meshlet_offset = mesh.meshlet_offset,
                .draw_mode = @intFromEnum(self.draw_mode),
                .instance_id = @intCast(i),
            };

            command_list.SetGraphicsRoot32BitConstants(2, 4, &root_const, 0);
            command_list.DispatchMesh(mesh.num_meshlets, 1, 1);
        }

        const zgui_heaps = [_]*d3d12.IDescriptorHeap{self.zgui_heap.heap};
        command_list.SetDescriptorHeaps(1, &zgui_heaps);
        zgui.backend.draw(command_list);

        command_list.ResourceBarrier(1, &.{.{ .Type = .TRANSITION, .Flags = .{}, .u = .{ .Transition = .{
            .pResource = self.dx12.swap_chain_textures[back_buffer_index],
            .Subresource = d3d12.RESOURCE_BARRIER_ALL_SUBRESOURCES,
            .StateBefore = .{ .RENDER_TARGET = true },
            .StateAfter = d3d12.RESOURCE_STATES.PRESENT,
        } } }});

        hrPanicOnFail(command_list.Close());

        self.dx12.command_queue.ExecuteCommandLists(1, &.{@ptrCast(command_list)});

        self.dx12.present();

        self.draws.clearRetainingCapacity();
    }

    pub fn drawMesh(self: *Renderer, mesh: u32, transform: zmath.Mat) !void {
        try self.draws.append(.{ .mesh = mesh, .transform = zmath.transpose(transform) });
    }
};
