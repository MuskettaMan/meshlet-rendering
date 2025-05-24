const std = @import("std");

const zgui = @import("zgui");
const zmath = @import("zmath");
const zwindows = @import("zwindows");
const windows = zwindows.windows;
const dxgi = zwindows.dxgi;
const d3d12 = zwindows.d3d12;
const d3d12d = zwindows.d3d12d;
const hrPanicOnFail = zwindows.hrPanicOnFail;
const Dx12State = @import("dx12_state.zig").Dx12State;
const Camera = @import("camera.zig").Camera;
const Vertex = @import("vertex.zig").Vertex;

const window_name = "DX12 Zig";
const content_dir = "content/";

const vertices = [_]Vertex{ .{ .position = .{ -0.9, -0.9, 0.0, 0.0 } }, .{ .position = .{ 0.0, 0.9, 0.0, 0.0 } }, .{ .position = .{ 0.9, -0.9, 0.0, 0.0 } } };

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
    buffer_size: u32,

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

fn createResource(comptime T: type, device: *d3d12.IDevice9, min_aligned: bool) Resource {
    const buffer_size = if (min_aligned) (@sizeOf(T) + 255) & ~@as(u32, 255) else @sizeOf(T);

    var resource: ?*d3d12.IResource = null;
    const heap_props = d3d12.HEAP_PROPERTIES.initType(.UPLOAD);
    const buffer_desc = d3d12.RESOURCE_DESC.initBuffer(buffer_size);

    hrPanicOnFail(device.CreateCommittedResource(&heap_props, d3d12.HEAP_FLAGS{}, &buffer_desc, d3d12.RESOURCE_STATES.GENERIC_READ, null, &d3d12.IID_IResource, @ptrCast(&resource)));

    return .{ .resource = resource.?, .buffer_size = buffer_size };
}

pub fn main() !void {
    _ = windows.CoInitializeEx(null, windows.COINIT_MULTITHREADED);
    defer windows.CoUninitialize();

    _ = windows.SetProcessDPIAware();

    const window = createWindow(1600, 1200);

    var dx12 = Dx12State.init(window);
    defer dx12.deinit();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    //defer gpa.deinit();

    const allocator = gpa.allocator();

    zgui.init(allocator);
    defer zgui.deinit();

    _ = zgui.io.addFontFromFile(content_dir ++ "Roboto-Medium.ttf", 16.0);

    const font_descriptor = dx12.cbv_srv_heap.allocate();

    zgui.backend.init(window, .{
        .device = dx12.device,
        .command_queue = dx12.command_queue,
        .num_frames_in_flight = Dx12State.num_frames,
        .rtv_format = @intFromEnum(Dx12State.rtv_format),
        .dsv_format = @intFromEnum(Dx12State.dsv_format),
        .cbv_srv_heap = dx12.cbv_srv_heap.heap,
        .font_srv_cpu_desc_handle = @bitCast(font_descriptor.cpu_handle),
        .font_srv_gpu_desc_handle = @bitCast(font_descriptor.gpu_handle),
    });
    defer zgui.backend.deinit();

    const root_signature: *d3d12.IRootSignature, const pipeline: *d3d12.IPipelineState = blk: {
        const vs_cso = @embedFile("./shaders/main.vs.cso");
        const ps_cso = @embedFile("./shaders/main.ps.cso");

        const input_element = d3d12.INPUT_ELEMENT_DESC.init("POSITION", 0, dxgi.FORMAT.R32G32B32_FLOAT, 0, 0, .PER_VERTEX_DATA, 0);
        const input_elements = [_]d3d12.INPUT_ELEMENT_DESC{input_element};
        const input_layout = d3d12.INPUT_LAYOUT_DESC.init(&input_elements);

        var pso_desc = d3d12.GRAPHICS_PIPELINE_STATE_DESC.initDefault();
        pso_desc.DepthStencilState.DepthEnable = windows.FALSE;
        pso_desc.RTVFormats[0] = .R8G8B8A8_UNORM;
        pso_desc.NumRenderTargets = 1;
        pso_desc.PrimitiveTopologyType = .TRIANGLE;
        pso_desc.InputLayout = input_layout;
        pso_desc.VS = .{ .pShaderBytecode = vs_cso, .BytecodeLength = vs_cso.len };
        pso_desc.PS = .{ .pShaderBytecode = ps_cso, .BytecodeLength = ps_cso.len };

        var root_signature: *d3d12.IRootSignature = undefined;
        hrPanicOnFail(dx12.device.CreateRootSignature(0, pso_desc.VS.pShaderBytecode.?, pso_desc.VS.BytecodeLength, &d3d12.IID_IRootSignature, @ptrCast(&root_signature)));

        var pipeline: *d3d12.IPipelineState = undefined;
        hrPanicOnFail(dx12.device.CreateGraphicsPipelineState(&pso_desc, &d3d12.IID_IPipelineState, @ptrCast(&pipeline)));

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

    var camera_resource = createResource(Camera, dx12.device, true);
    const camera_ptr = camera_resource.map();
    defer camera_resource.unmap();
    zmath.storeMat(f32Ptr(camera_ptr)[0..16], zmath.transpose(camera.view));
    zmath.storeMat(f32Ptr(camera_ptr)[16..32], zmath.transpose(camera.proj));

    var instance_resource = createResource(zmath.Mat, dx12.device, true);
    const instance_ptr = instance_resource.map();
    defer instance_resource.unmap();
    zmath.storeMat(f32Ptr(instance_ptr)[0..16], model);

    const camera_descriptor = dx12.cbv_srv_heap.allocate();
    const camera_cbv_desc: d3d12.CONSTANT_BUFFER_VIEW_DESC = .{ .BufferLocation = camera_resource.resource.GetGPUVirtualAddress(), .SizeInBytes = camera_resource.bufferSize };
    dx12.device.CreateConstantBufferView(&camera_cbv_desc, camera_descriptor.cpu_handle);

    const instance_descriptor = dx12.cbv_srv_heap.allocate();
    const instance_cbv_desc: d3d12.CONSTANT_BUFFER_VIEW_DESC = .{ .BufferLocation = instance_resource.resource.GetGPUVirtualAddress(), .SizeInBytes = instance_resource.bufferSize };
    dx12.device.CreateConstantBufferView(&instance_cbv_desc, instance_descriptor.cpu_handle);

    const vertex_buffer_resource = createResource(@TypeOf(vertices), dx12.device, false);
    const vertex_buffer: d3d12.VERTEX_BUFFER_VIEW = .{ .BufferLocation = vertex_buffer_resource.resource.GetGPUVirtualAddress(), .SizeInBytes = vertex_buffer_resource.bufferSize, .StrideInBytes = @sizeOf(f32) * 3 };

    const vertex_ptr = vertex_buffer_resource.map();
    const arr: [*][3]f32 = @ptrCast(f32Ptr(vertex_ptr));
    for (vertices, 0..) |value, i| {
        zmath.storeArr3(&arr[i], value.position);
    }
    vertex_buffer_resource.unmap();

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

        // Draw gui.

        dx12.command_list.IASetPrimitiveTopology(.TRIANGLELIST);
        dx12.command_list.SetPipelineState(pipeline);
        dx12.command_list.SetGraphicsRootSignature(root_signature);

        dx12.command_list.IASetVertexBuffers(0, 1, @ptrCast(&vertex_buffer));
        dx12.command_list.SetGraphicsRootConstantBufferView(0, camera_resource.resource.GetGPUVirtualAddress());
        dx12.command_list.SetGraphicsRootConstantBufferView(1, instance_resource.resource.GetGPUVirtualAddress());

        dx12.command_list.DrawInstanced(3, 1, 0, 0);

        dx12.command_list.ResourceBarrier(1, &.{.{ .Type = .TRANSITION, .Flags = .{}, .u = .{ .Transition = .{
            .pResource = dx12.swap_chain_textures[back_buffer_index],
            .Subresource = d3d12.RESOURCE_BARRIER_ALL_SUBRESOURCES,
            .StateBefore = .{ .RENDER_TARGET = true },
            .StateAfter = d3d12.RESOURCE_STATES.PRESENT,
        } } }});

        const heaps = [_]*d3d12.IDescriptorHeap{dx12.cbv_srv_heap.heap};
        dx12.command_list.SetDescriptorHeaps(1, &heaps);
        zgui.backend.draw(dx12.command_list);

        hrPanicOnFail(dx12.command_list.Close());

        dx12.command_queue.ExecuteCommandLists(1, &.{@ptrCast(dx12.command_list)});

        dx12.present();
    }

    dx12.flush();
}
