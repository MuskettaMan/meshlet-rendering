const std = @import("std");
const zgui = @import("zgui");
const zmath = @import("zmath");
const zwindows = @import("zwindows");
const zmesh = @import("zmesh");
const zmesh_data = @import("mesh_data.zig");
const winUtil = @import("win_util.zig");

const windows = zwindows.windows;
const dxgi = zwindows.dxgi;
const d3d12 = zwindows.d3d12;
const d3d12d = zwindows.d3d12d;
const hrPanicOnFail = zwindows.hrPanicOnFail;
const Dx12State = @import("dx12_state.zig").Dx12State;
const CbvSrvHeap = @import("dx12_state.zig").CbvSrvHeap;
const Camera = @import("camera.zig").Camera;
const Vertex = zmesh_data.Vertex;
const Mesh = zmesh_data.Mesh;
const Meshlet = zmesh_data.Meshlet;
const Scene = @import("scene.zig").Scene;

const window_name: [:0]const u8 = "DX12 Zig";
const content_dir = "content/";

fn castPtrToSlice(comptime T: type, mapped_ptr: *anyopaque) [*]T {
    return @as([*]T, @ptrCast(@alignCast(mapped_ptr)));
}

const RootConst = struct {
    vertex_offset: u32,
    meshlet_offset: u32,
    draw_mode: u32,
};

pub fn main() !void {
    _ = windows.CoInitializeEx(null, windows.COINIT_MULTITHREADED);
    defer windows.CoUninitialize();

    _ = windows.SetProcessDPIAware();

    var width: u32 = 1600;
    var height: u32 = 1200;
    const aspect_ratio = @as(f32, @floatFromInt(width)) / @as(f32, @floatFromInt(height));

    const window = winUtil.createWindow(width, height, &window_name);

    var dx12 = Dx12State.init(window);
    defer dx12.deinit();

    var options7: d3d12.FEATURE_DATA_D3D12_OPTIONS7 = undefined;
    const res = dx12.device.CheckFeatureSupport(.OPTIONS7, &options7, @sizeOf(d3d12.FEATURE_DATA_D3D12_OPTIONS7));
    if (options7.MeshShaderTier == .NOT_SUPPORTED or res != windows.S_OK) {
        _ = windows.MessageBoxA(window, "This applications requires graphics card that supports Mesh Shader " ++
            "(NVIDIA GeForce Turing or newer, AMD Radeon RX 6000 or newer).", "No DirectX 12 Mesh Shader support", windows.MB_OK | windows.MB_ICONERROR);
        return;
    }

    const pageAllocator = std.heap.page_allocator;
    var arena = std.heap.ArenaAllocator.init(pageAllocator);
    defer arena.deinit();

    const arenaAllocator = arena.allocator();

    zgui.init(pageAllocator);
    defer zgui.deinit();

    _ = zgui.io.addFontFromFile(content_dir ++ "Roboto-Medium.ttf", 16.0);

    var zgui_heap = CbvSrvHeap.init(1, dx12.device);
    defer zgui_heap.deinit();
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
    defer zgui.backend.deinit();

    zmesh.init(pageAllocator);
    defer zmesh.deinit();

    var scene = try Scene.init(pageAllocator, arenaAllocator, &dx12);
    defer scene.deinit();

    {
        scene.camera.position = .{ 0.0, 0.0, -10.0, 0.0 };
        scene.camera.view = zmath.inverse(zmath.translation(scene.camera.position[0], scene.camera.position[1], scene.camera.position[2]));
        scene.camera.proj = zmath.perspectiveFovLh(0.25 * std.math.pi, aspect_ratio, 0.01, 200.0);
    
        const camera_ptr = scene.camera_resource.map();
        defer scene.camera_resource.unmap();

        zmath.storeMat(castPtrToSlice(f32, camera_ptr)[0..16], zmath.transpose(scene.camera.view));
        zmath.storeMat(castPtrToSlice(f32, camera_ptr)[16..32], zmath.transpose(scene.camera.proj));
        zmath.store(castPtrToSlice(f32, camera_ptr)[32..35], scene.camera.position, 3);
    }

    var model = zmath.identity();
    const instance_ptr = scene.instance_resource.map();
    defer scene.instance_resource.unmap();
    zmath.storeMat(castPtrToSlice(f32, instance_ptr)[0..16], model);

    hrPanicOnFail(dx12.command_list.Close());
    dx12.command_queue.ExecuteCommandLists(1, &.{@ptrCast(dx12.command_list)});
    dx12.flush();

    var window_rect: windows.RECT = undefined;
    _ = windows.GetClientRect(window, &window_rect);

    var time = std.time.microTimestamp();
    var delta_time_i64: i64 = 0;
    var total_time: f32 = 0;

    var drawMode = DrawMode.Shaded;

    main_loop: while (true) {
        {
            var message = std.mem.zeroes(windows.MSG);

            while (windows.PeekMessageA(&message, null, 0, 0, windows.PM_REMOVE) == windows.TRUE) {
                _ = windows.TranslateMessage(&message);
                _ = windows.DispatchMessageA(&message);
                if (message.message == windows.WM_QUIT) {
                    break :main_loop;
                }
            }

            var rect: windows.RECT = undefined;
            _ = windows.GetClientRect(window, &rect);
            if (rect.right == 0 and rect.bottom == 0) {
                windows.Sleep(10);
                continue :main_loop;
            }

            if (rect.right != window_rect.right or rect.bottom != window_rect.bottom) {
                rect.right = @max(1, rect.right);
                rect.bottom = @max(1, rect.bottom);
                std.log.info("Window resized to {d}x{d}", .{ rect.right, rect.bottom });

                dx12.flush();

                for (dx12.swap_chain_textures) |texture| _ = texture.Release();

                hrPanicOnFail(dx12.swap_chain.ResizeBuffers(0, 0, 0, .UNKNOWN, .{}));

                for (&dx12.swap_chain_textures, 0..) |*texture, i| {
                    hrPanicOnFail(dx12.swap_chain.GetBuffer(@intCast(i), &d3d12.IID_IResource, @ptrCast(&texture.*))); // TODO: try remove &x.*
                }

                for (&dx12.swap_chain_textures, 0..) |texture, i| {
                    dx12.device.CreateRenderTargetView(texture, null, .{ .ptr = dx12.rtv_heap_start.ptr + i * dx12.device.GetDescriptorHandleIncrementSize(.RTV) });
                }
            }

            window_rect = rect;
            width = @intCast(window_rect.right);
            height = @intCast(window_rect.bottom);
        }

        const current_time = std.time.microTimestamp();
        delta_time_i64 = current_time - time;
        time = current_time;

        const delta_time: f32 = @as(f32, @floatFromInt(delta_time_i64)) / @as(f32, std.time.us_per_s);
        total_time += delta_time;

        const scale = 0.6;
        model = zmath.scaling(scale, scale, scale);
        model = zmath.mul(model, zmath.rotationX(std.math.pi / 2.0));
        model = zmath.mul(model, zmath.rotationY(total_time));
        model = zmath.mul(model, zmath.translation(0.0, -2.5, 0.0));

        zmath.storeMat(castPtrToSlice(f32, instance_ptr)[0..16], zmath.transpose(model));

        const command_allocator = dx12.command_allocators[dx12.frame_index];

        hrPanicOnFail(command_allocator.Reset());
        hrPanicOnFail(dx12.command_list.Reset(command_allocator, null));

        dx12.command_list.RSSetViewports(1, &.{.{
            .TopLeftX = 0.0,
            .TopLeftY = 0.0,
            .Width = @floatFromInt(width),
            .Height = @floatFromInt(height),
            .MinDepth = 0.0,
            .MaxDepth = 1.0,
        }});
        dx12.command_list.RSSetScissorRects(1, &.{.{
            .left = 0,
            .top = 0,
            .right = @intCast(width),
            .bottom = @intCast(height),
        }});

        const back_buffer_index = dx12.swap_chain.GetCurrentBackBufferIndex();
        const back_buffer_descriptor = d3d12.CPU_DESCRIPTOR_HANDLE{ .ptr = dx12.rtv_heap_start.ptr + back_buffer_index * dx12.device.GetDescriptorHandleIncrementSize(.RTV) };

        dx12.command_list.ResourceBarrier(1, &.{.{ .Type = .TRANSITION, .Flags = .{}, .u = .{ .Transition = .{
            .pResource = dx12.swap_chain_textures[back_buffer_index],
            .Subresource = d3d12.RESOURCE_BARRIER_ALL_SUBRESOURCES,
            .StateBefore = d3d12.RESOURCE_STATES.PRESENT,
            .StateAfter = .{ .RENDER_TARGET = true },
        } } }});

        dx12.command_list.OMSetRenderTargets(1, &.{back_buffer_descriptor}, windows.TRUE, &dx12.depth_heap_handle);
        dx12.command_list.ClearDepthStencilView(dx12.depth_heap_handle, .{ .DEPTH = true }, 1.0, 0, 0, null);
        dx12.command_list.ClearRenderTargetView(back_buffer_descriptor, &.{ 0.2, 0.2, 0.8, 1.0 }, 0, null);

        zgui.backend.newFrame(@intCast(width), @intCast(height));

        // Can draw gui elemenets here.
        if (zgui.begin("Settings", .{ .flags = .{ .always_auto_resize = true } })) {
            _ = zgui.comboFromEnum("Draw Mode", &drawMode);
            zgui.end();
        }

        dx12.command_list.IASetPrimitiveTopology(.TRIANGLELIST);
        dx12.command_list.SetPipelineState(scene.pipeline);
        dx12.command_list.SetGraphicsRootSignature(scene.root_signature);

        dx12.command_list.SetGraphicsRootConstantBufferView(0, scene.camera_resource.resource.GetGPUVirtualAddress());
        dx12.command_list.SetGraphicsRootConstantBufferView(1, scene.instance_resource.resource.GetGPUVirtualAddress());

        const heaps = [_]*d3d12.IDescriptorHeap{scene.meshlet_heap.heap};
        dx12.command_list.SetDescriptorHeaps(1, &heaps);
        dx12.command_list.SetGraphicsRootDescriptorTable(3, scene.vertex_buffer_descriptor.gpu_handle);

        var pending_meshlets = scene.all_meshes.items[0].num_meshlets;
        while (pending_meshlets > 0) {
            const meshlet_count = @min(pending_meshlets, std.math.maxInt(u16));
            const offset = scene.all_meshes.items[0].num_meshlets - pending_meshlets;

            dx12.command_list.SetGraphicsRoot32BitConstants(2, 3, &.{ scene.all_meshes.items[0].vertex_offset, scene.all_meshes.items[0].index_offset + offset, @intFromEnum(drawMode) }, 0);
            dx12.command_list.DispatchMesh(meshlet_count, 1, 1);

            pending_meshlets -= meshlet_count;
        }

        const zgui_heaps = [_]*d3d12.IDescriptorHeap{zgui_heap.heap};
        dx12.command_list.SetDescriptorHeaps(1, &zgui_heaps);
        zgui.backend.draw(dx12.command_list);

        dx12.command_list.ResourceBarrier(1, &.{.{ .Type = .TRANSITION, .Flags = .{}, .u = .{ .Transition = .{
            .pResource = dx12.swap_chain_textures[back_buffer_index],
            .Subresource = d3d12.RESOURCE_BARRIER_ALL_SUBRESOURCES,
            .StateBefore = .{ .RENDER_TARGET = true },
            .StateAfter = d3d12.RESOURCE_STATES.PRESENT,
        } } }});

        hrPanicOnFail(dx12.command_list.Close());

        dx12.command_queue.ExecuteCommandLists(1, &.{@ptrCast(dx12.command_list)});

        dx12.present();
    }

    dx12.flush();
}

const DrawMode = enum { Wireframe, Shaded };
