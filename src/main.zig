const std = @import("std");
const zgui = @import("zgui");
const zmath = @import("zmath");
const zwindows = @import("zwindows");
const zmesh = @import("zmesh");
const zmesh_data = @import("mesh_data.zig");

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

const window_name = "DX12 Zig";
const content_dir = "content/";

fn processWindowMessage(window: windows.HWND, message: windows.UINT, wparam: windows.WPARAM, lparam: windows.LPARAM) callconv(windows.WINAPI) windows.LRESULT {
    switch (message) {
        windows.WM_KEYDOWN => {
            if (wparam == windows.VK_ESCAPE) {
                windows.PostQuitMessage(0);
                return 0;
            }
        },
        windows.WM_GETMINMAXINFO => {
            var info: *windows.MINMAXINFO = @ptrFromInt(@as(usize, @intCast(lparam)));
            info.ptMinTrackSize.x = 400;
            info.ptMinTrackSize.y = 400;
            return 0;
        },
        windows.WM_DESTROY => {
            windows.PostQuitMessage(0);
            return 0;
        },
        else => {},
    }

    return windows.DefWindowProcA(window, message, wparam, lparam);
}

fn createWindow(width: u32, height: u32) windows.HWND {
    const winclass = windows.WNDCLASSEXA{
        .style = 0,
        .lpfnWndProc = processWindowMessage,
        .cbClsExtra = 0,
        .cbWndExtra = 0,
        .hInstance = @ptrCast(windows.GetModuleHandleA(null)),
        .hIcon = null,
        .hCursor = windows.LoadCursorA(null, @ptrFromInt(32512)),
        .hbrBackground = null,
        .lpszMenuName = null,
        .lpszClassName = window_name,
        .hIconSm = null,
    };
    _ = windows.RegisterClassExA(&winclass);

    const style = windows.WS_OVERLAPPEDWINDOW;

    var rect = windows.RECT{
        .left = 0,
        .top = 0,
        .right = @intCast(width),
        .bottom = @intCast(height),
    };
    _ = windows.AdjustWindowRectEx(&rect, style, windows.FALSE, 0);

    const window = windows.CreateWindowExA(0, window_name, window_name, style + windows.WS_VISIBLE, windows.CW_USEDEFAULT, windows.CW_USEDEFAULT, rect.right - rect.left, rect.bottom - rect.top, null, null, winclass.hInstance, null).?;

    std.log.info("Application window created", .{});

    return window;
}

const Resource = struct {
    resource: *d3d12.IResource,
    buffer_size: usize,

    pub fn map(self: *const Resource) *anyopaque {
        const read_range: d3d12.RANGE = .{ .Begin = 0, .End = 0 };
        var mapped_data: ?*anyopaque = null;
        hrPanicOnFail(self.resource.Map(0, &read_range, &mapped_data));

        return mapped_data.?;
    }
    pub fn unmap(self: *const Resource) void {
        self.resource.Unmap(0, null);
    }
};

fn f32Ptr(mapped_ptr: *anyopaque) [*]f32 {
    return @as([*]f32, @ptrCast(@alignCast(mapped_ptr)));
}

fn createResourceWithSize(name: [:0]const u16, buffer_size: usize, heap_type: d3d12.HEAP_TYPE, device: *d3d12.IDevice9) Resource {
    var resource: ?*d3d12.IResource = null;
    const heap_props = d3d12.HEAP_PROPERTIES.initType(heap_type);
    const buffer_desc = d3d12.RESOURCE_DESC.initBuffer(buffer_size);

    const resource_state = if (heap_type == .UPLOAD) d3d12.RESOURCE_STATES.GENERIC_READ else d3d12.RESOURCE_STATES.COMMON;

    hrPanicOnFail(device.CreateCommittedResource(&heap_props, d3d12.HEAP_FLAGS{}, &buffer_desc, resource_state, null, &d3d12.IID_IResource, @ptrCast(&resource)));

    hrPanicOnFail(resource.?.SetName(name));

    return .{ .resource = resource.?, .buffer_size = buffer_size };
}

fn createResource(comptime T: type, name: [:0]const u16, heap_type: d3d12.HEAP_TYPE, device: *d3d12.IDevice9, min_aligned: bool) Resource {
    const buffer_size = if (min_aligned) (@sizeOf(T) + 255) & ~@as(u32, 255) else @sizeOf(T);

    return createResourceWithSize(name, buffer_size, heap_type, device);
}

fn copyBuffer(comptime T: type, name: [:0]const u16, src_data: *const std.ArrayList(T), dest_resource: *const Resource, dx12: *Dx12State) void {
    const upload = createResourceWithSize(name, dest_resource.buffer_size, .UPLOAD, dx12.device);
    const mappedPtr = upload.map();
    defer upload.unmap();

    const dest = @as([*]T, @ptrCast(@alignCast(mappedPtr)));

    for (src_data.items, 0..) |data_element, i| {
        dest[i] = data_element;
    }

    var barrier = d3d12.RESOURCE_BARRIER{ .Type = .TRANSITION, .Flags = .{}, .u = .{ .Transition = .{ .pResource = dest_resource.resource, .StateBefore = .COMMON, .StateAfter = .{ .COPY_DEST = true }, .Subresource = d3d12.RESOURCE_BARRIER_ALL_SUBRESOURCES } } };
    dx12.command_list.ResourceBarrier(1, @ptrCast(&barrier));
    dx12.command_list.CopyBufferRegion(dest_resource.resource, 0, upload.resource, 0, upload.buffer_size);

    barrier.u.Transition.StateBefore = .{ .COPY_DEST = true };
    barrier.u.Transition.StateAfter = .GENERIC_READ;
    dx12.command_list.ResourceBarrier(1, @ptrCast(&barrier));
}

const RootConst = struct {
    vertex_offset: u32,
    meshlet_offset: u32,
};

pub fn main() !void {
    _ = windows.CoInitializeEx(null, windows.COINIT_MULTITHREADED);
    defer windows.CoUninitialize();

    _ = windows.SetProcessDPIAware();

    const window = createWindow(1600, 1200);

    var dx12 = Dx12State.init(window);
    defer dx12.deinit();

    var options7: d3d12.FEATURE_DATA_D3D12_OPTIONS7 = undefined;
    const res = dx12.device.CheckFeatureSupport(.OPTIONS7, &options7, @sizeOf(d3d12.FEATURE_DATA_D3D12_OPTIONS7));
    if (options7.MeshShaderTier == .NOT_SUPPORTED or res != windows.S_OK) {
        _ = windows.MessageBoxA(window, "This applications requires graphics card that supports Mesh Shader " ++
            "(NVIDIA GeForce Turing or newer, AMD Radeon RX 6000 or newer).", "No DirectX 12 Mesh Shader support", windows.MB_OK | windows.MB_ICONERROR);
        return;
    }

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    //defer gpa.deinit();

    const allocator = gpa.allocator();

    zgui.init(allocator);
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

    zmesh.init(allocator);
    defer zmesh.deinit();

    var all_meshes = std.ArrayList(Mesh).init(allocator);
    defer all_meshes.deinit();
    var all_vertices = std.ArrayList(Vertex).init(allocator);
    defer all_vertices.deinit();
    var all_indices = std.ArrayList(u32).init(allocator);
    defer all_indices.deinit();
    var all_meshlets = std.ArrayList(Meshlet).init(allocator);
    defer all_meshlets.deinit();
    var all_meshlets_data = std.ArrayList(u32).init(allocator);
    defer all_meshlets_data.deinit();

    const path: [:0]const u8 = "content/Cube/Cube.gltf";
    //const path: [:0]const u8 = "content/Avocado.glb";
    try zmesh_data.loadOptimizedMesh(allocator, &path, &all_meshes, &all_vertices, &all_indices, &all_meshlets, &all_meshlets_data);

    const root_signature: *d3d12.IRootSignature, const pipeline: *d3d12.IPipelineState = blk: {
        const ms_cso = @embedFile("./shaders/main.ms.cso");
        const ps_cso = @embedFile("./shaders/main.ps.cso");

        var mesh_state_desc = d3d12.MESH_SHADER_PIPELINE_STATE_DESC.initDefault();
        mesh_state_desc.RTVFormats[0] = .R8G8B8A8_UNORM;
        mesh_state_desc.DepthStencilState.DepthEnable = windows.FALSE;
        mesh_state_desc.NumRenderTargets = 1;
        mesh_state_desc.MS = .{ .pShaderBytecode = ms_cso, .BytecodeLength = ms_cso.len };
        mesh_state_desc.PS = .{ .pShaderBytecode = ps_cso, .BytecodeLength = ps_cso.len };

        var stream = d3d12.PIPELINE_MESH_STATE_STREAM.init(mesh_state_desc);

        var root_signature: *d3d12.IRootSignature = undefined;
        hrPanicOnFail(dx12.device.CreateRootSignature(0, mesh_state_desc.MS.pShaderBytecode.?, mesh_state_desc.MS.BytecodeLength, &d3d12.IID_IRootSignature, @ptrCast(&root_signature)));

        var pipeline: *d3d12.IPipelineState = undefined;
        hrPanicOnFail(dx12.device.CreatePipelineState(&d3d12.PIPELINE_STATE_STREAM_DESC{ .SizeInBytes = @sizeOf(@TypeOf(stream)), .pPipelineStateSubobjectStream = @ptrCast(&stream) }, &d3d12.IID_IPipelineState, @ptrCast(&pipeline)));

        break :blk .{ root_signature, pipeline };
    };
    defer _ = pipeline.Release();
    defer _ = root_signature.Release();

    var width: u32 = 1600;
    var height: u32 = 1200;
    const aspect_ratio = @as(f32, @floatFromInt(width)) / @as(f32, @floatFromInt(height));

    var model = zmath.identity();

    var camera = Camera.init();
    camera.view = zmath.inverse(zmath.translation(0.0, 0.0, -10.0));
    camera.proj = zmath.perspectiveFovLh(0.25 * std.math.pi, aspect_ratio, 0.1, 20.0);

    var camera_resource = createResource(Camera, std.unicode.utf8ToUtf16LeAllocZ(allocator, "CameraBuffer") catch unreachable, .UPLOAD, dx12.device, true);
    const camera_ptr = camera_resource.map();
    defer camera_resource.unmap();
    zmath.storeMat(f32Ptr(camera_ptr)[0..16], zmath.transpose(camera.view));
    zmath.storeMat(f32Ptr(camera_ptr)[16..32], zmath.transpose(camera.proj));

    var instance_resource = createResource(zmath.Mat, std.unicode.utf8ToUtf16LeAllocZ(allocator, "InstanceBuffer") catch unreachable, .UPLOAD, dx12.device, true);
    const instance_ptr = instance_resource.map();
    defer instance_resource.unmap();
    zmath.storeMat(f32Ptr(instance_ptr)[0..16], model);

    var meshlet_heap = CbvSrvHeap.init(16, dx12.device);
    defer meshlet_heap.deinit();

    const camera_descriptor = meshlet_heap.allocate();
    const camera_cbv_desc: d3d12.CONSTANT_BUFFER_VIEW_DESC = .{ .BufferLocation = camera_resource.resource.GetGPUVirtualAddress(), .SizeInBytes = @intCast(camera_resource.buffer_size) };
    dx12.device.CreateConstantBufferView(&camera_cbv_desc, camera_descriptor.cpu_handle);

    const instance_descriptor = meshlet_heap.allocate();
    const instance_cbv_desc: d3d12.CONSTANT_BUFFER_VIEW_DESC = .{ .BufferLocation = instance_resource.resource.GetGPUVirtualAddress(), .SizeInBytes = @intCast(instance_resource.buffer_size) };
    dx12.device.CreateConstantBufferView(&instance_cbv_desc, instance_descriptor.cpu_handle);

    const vertex_buffer_resource = createResourceWithSize(std.unicode.utf8ToUtf16LeAllocZ(allocator, "VertexBuffer") catch unreachable, @sizeOf(Vertex) * all_vertices.items.len, .DEFAULT, dx12.device);
    const vertex_srv_desc = d3d12.SHADER_RESOURCE_VIEW_DESC.initStructuredBuffer(0, @as(u32, @intCast(all_vertices.items.len)), @sizeOf(Vertex));
    const vertex_buffer_descriptor = meshlet_heap.allocate();
    dx12.device.CreateShaderResourceView(vertex_buffer_resource.resource, &vertex_srv_desc, vertex_buffer_descriptor.cpu_handle);

    const index_buffer_resource = createResourceWithSize(std.unicode.utf8ToUtf16LeAllocZ(allocator, "IndexBuffer") catch unreachable, @sizeOf(u32) * all_indices.items.len, .DEFAULT, dx12.device);
    const index_srv_desc = d3d12.SHADER_RESOURCE_VIEW_DESC.initTypedBuffer(.R32_UINT, 0, @as(u32, @intCast(all_indices.items.len)));
    const index_buffer_descriptor = meshlet_heap.allocate();
    dx12.device.CreateShaderResourceView(index_buffer_resource.resource, &index_srv_desc, index_buffer_descriptor.cpu_handle);

    const meshlet_buffer_resource = createResourceWithSize(std.unicode.utf8ToUtf16LeAllocZ(allocator, "MeshletBuffer") catch unreachable, @sizeOf(Meshlet) * all_meshlets.items.len, .DEFAULT, dx12.device);
    const meshlet_srv_desc = d3d12.SHADER_RESOURCE_VIEW_DESC.initStructuredBuffer(0, @as(u32, @intCast(all_meshlets.items.len)), @sizeOf(Meshlet));
    const meshlet_buffer_descriptor = meshlet_heap.allocate();
    dx12.device.CreateShaderResourceView(meshlet_buffer_resource.resource, &meshlet_srv_desc, meshlet_buffer_descriptor.cpu_handle);

    const meshlet_data_buffer_resource = createResourceWithSize(std.unicode.utf8ToUtf16LeAllocZ(allocator, "MeshletDataBuffer") catch unreachable, @sizeOf(u32) * all_meshlets_data.items.len, .DEFAULT, dx12.device);
    const meshlet_data_srv_desc = d3d12.SHADER_RESOURCE_VIEW_DESC.initTypedBuffer(.R32_UINT, 0, @as(u32, @intCast(all_meshlets_data.items.len)));
    const meshlet_data_buffer_descriptor = meshlet_heap.allocate();
    dx12.device.CreateShaderResourceView(meshlet_data_buffer_resource.resource, &meshlet_data_srv_desc, meshlet_data_buffer_descriptor.cpu_handle);

    hrPanicOnFail(dx12.command_allocators[0].Reset());
    hrPanicOnFail(dx12.command_list.Reset(dx12.command_allocators[0], null));

    copyBuffer(Vertex, std.unicode.utf8ToUtf16LeAllocZ(allocator, "VertexUploadBuffer") catch unreachable, &all_vertices, &vertex_buffer_resource, &dx12);
    copyBuffer(u32, std.unicode.utf8ToUtf16LeAllocZ(allocator, "IndexUploadBuffer") catch unreachable, &all_indices, &index_buffer_resource, &dx12);
    copyBuffer(Meshlet, std.unicode.utf8ToUtf16LeAllocZ(allocator, "MeshletUploadBuffer") catch unreachable, &all_meshlets, &meshlet_buffer_resource, &dx12);
    copyBuffer(u32, std.unicode.utf8ToUtf16LeAllocZ(allocator, "MeshletDataUploadBuffer") catch unreachable, &all_meshlets_data, &meshlet_data_buffer_resource, &dx12);

    hrPanicOnFail(dx12.command_list.Close());
    dx12.command_queue.ExecuteCommandLists(1, &.{@ptrCast(dx12.command_list)});
    dx12.flush();

    var window_rect: windows.RECT = undefined;
    _ = windows.GetClientRect(window, &window_rect);

    var time = std.time.microTimestamp();
    var delta_time_i64: i64 = 0;
    var total_time: f32 = 0;

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

        model = zmath.rotationY(total_time);

        zmath.storeMat(f32Ptr(instance_ptr)[0..16], zmath.transpose(model));

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

        dx12.command_list.OMSetRenderTargets(1, &.{back_buffer_descriptor}, windows.TRUE, null);
        dx12.command_list.ClearRenderTargetView(back_buffer_descriptor, &.{ 0.2, 0.2, 0.8, 1.0 }, 0, null);

        zgui.backend.newFrame(@intCast(width), @intCast(height));

        // Can draw gui elemenets here.

        dx12.command_list.IASetPrimitiveTopology(.TRIANGLELIST);
        dx12.command_list.SetPipelineState(pipeline);
        dx12.command_list.SetGraphicsRootSignature(root_signature);

        dx12.command_list.SetGraphicsRootConstantBufferView(0, camera_resource.resource.GetGPUVirtualAddress());
        dx12.command_list.SetGraphicsRootConstantBufferView(1, instance_resource.resource.GetGPUVirtualAddress());

        dx12.command_list.SetGraphicsRoot32BitConstants(2, 2, &.{ all_meshes.items[0].vertex_offset, all_meshes.items[0].index_offset }, 0);

        const heaps = [_]*d3d12.IDescriptorHeap{meshlet_heap.heap};
        dx12.command_list.SetDescriptorHeaps(1, &heaps);
        dx12.command_list.SetGraphicsRootDescriptorTable(3, vertex_buffer_descriptor.gpu_handle);

        dx12.command_list.DispatchMesh(all_meshes.items[0].num_meshlets, 1, 1);

        dx12.command_list.ResourceBarrier(1, &.{.{ .Type = .TRANSITION, .Flags = .{}, .u = .{ .Transition = .{
            .pResource = dx12.swap_chain_textures[back_buffer_index],
            .Subresource = d3d12.RESOURCE_BARRIER_ALL_SUBRESOURCES,
            .StateBefore = .{ .RENDER_TARGET = true },
            .StateAfter = d3d12.RESOURCE_STATES.PRESENT,
        } } }});

        const zgui_heaps = [_]*d3d12.IDescriptorHeap{zgui_heap.heap};
        dx12.command_list.SetDescriptorHeaps(1, &zgui_heaps);
        zgui.backend.draw(dx12.command_list);

        hrPanicOnFail(dx12.command_list.Close());

        dx12.command_queue.ExecuteCommandLists(1, &.{@ptrCast(dx12.command_list)});

        dx12.present();
    }

    dx12.flush();
}
