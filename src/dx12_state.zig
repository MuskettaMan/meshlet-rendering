const std = @import("std");

const zwindows = @import("zwindows");
const windows = zwindows.windows;
const dxgi = zwindows.dxgi;
const d3d12 = zwindows.d3d12;
const d3d12d = zwindows.d3d12d;
const hrPanicOnFail = zwindows.hrPanicOnFail;

pub const Descriptor = struct { index: u32, cpu_handle: d3d12.CPU_DESCRIPTOR_HANDLE, gpu_handle: d3d12.GPU_DESCRIPTOR_HANDLE };

pub const CbvSrvHeap = struct {
    heap: *d3d12.IDescriptorHeap,
    next_free_index: u32 = 0,
    num_descriptors: u32,
    descriptor_size: u32,

    pub fn init(num_descriptors: comptime_int, device: *d3d12.IDevice9) CbvSrvHeap {
        var heap: *d3d12.IDescriptorHeap = undefined;
        hrPanicOnFail(device.CreateDescriptorHeap(&.{
            .Type = .CBV_SRV_UAV,
            .NumDescriptors = num_descriptors,
            .Flags = .{ .SHADER_VISIBLE = true },
            .NodeMask = 0,
        }, &d3d12.IID_IDescriptorHeap, @ptrCast(&heap)));

        return .{ .heap = heap, .num_descriptors = num_descriptors, .descriptor_size = device.GetDescriptorHandleIncrementSize(d3d12.DESCRIPTOR_HEAP_TYPE.CBV_SRV_UAV) };
    }

    pub fn deinit(self: *CbvSrvHeap) void {
        _ = self.heap.Release();
    }

    pub fn allocate(self: *CbvSrvHeap) Descriptor {
        const index = self.next_free_index;
        self.next_free_index += 1;

        var cpu_handle = self.heap.GetCPUDescriptorHandleForHeapStart();
        cpu_handle.ptr += index * self.descriptor_size;

        var gpu_handle = self.heap.GetGPUDescriptorHandleForHeapStart();
        gpu_handle.ptr += index * self.descriptor_size;

        return .{ .index = index, .cpu_handle = cpu_handle, .gpu_handle = gpu_handle };
    }
};

pub const Dx12StateError = error{NotSupported};

pub const Dx12State = struct {
    dxgi_factory: *dxgi.IFactory6,
    device: *d3d12.IDevice9,

    swap_chain: *dxgi.ISwapChain3,
    swap_chain_textures: [num_frames]*d3d12.IResource,

    dsv_heap: *d3d12.IDescriptorHeap,
    depth_texture: *d3d12.IResource,
    depth_heap_handle: d3d12.CPU_DESCRIPTOR_HANDLE,

    rtv_heap: *d3d12.IDescriptorHeap,
    rtv_heap_start: d3d12.CPU_DESCRIPTOR_HANDLE,

    frame_fence: *d3d12.IFence,
    frame_fence_event: windows.HANDLE,
    frame_fence_counter: u64 = 0,
    frame_index: u32 = 0,

    command_queue: *d3d12.ICommandQueue,
    command_allocators: [num_frames]*d3d12.ICommandAllocator,
    command_list: *d3d12.IGraphicsCommandList6,

    pub const num_frames = 2;
    pub const debug_enabled = true;
    pub const rtv_format = dxgi.FORMAT.R8G8B8A8_UNORM;
    pub const dsv_format = dxgi.FORMAT.D32_FLOAT;

    pub fn init(window: windows.HWND) Dx12StateError!Dx12State {
        var dxgi_factory: *dxgi.IFactory6 = undefined;

        hrPanicOnFail(dxgi.CreateDXGIFactory2(0, &dxgi.IID_IFactory6, @ptrCast(&dxgi_factory)));

        std.log.info("DXGI factory created", .{});

        {
            var maybe_debug: ?*d3d12d.IDebug1 = null;
            _ = d3d12.GetDebugInterface(&d3d12d.IID_IDebug1, @ptrCast(&maybe_debug));
            if (maybe_debug) |debug| {
                if (debug_enabled) {
                    debug.EnableDebugLayer();
                }
                _ = debug.Release();
            }
        }

        var adapter: *dxgi.IAdapter1 = undefined;
        _ = dxgi_factory.EnumAdapterByGpuPreference(0, .HIGH_PERFORMANCE, &dxgi.IID_IAdapter1, @ptrCast(&adapter));

        var device: *d3d12.IDevice9 = undefined;
        if (d3d12.CreateDevice(@ptrCast(adapter), .@"11_0", &d3d12.IID_IDevice9, @ptrCast(&device)) != windows.S_OK) {
            _ = windows.MessageBoxA(window, "Failed to create Direct3D 12 Device. This applications requires graphics card " ++
                "with DirectX 12 Feature Level 11.0 support.", "Your graphics card driver may be old", windows.MB_OK | windows.MB_ICONERROR);
            return Dx12StateError.NotSupported;
        }
        std.log.info("D3D12 device created", .{});

        var command_queue: *d3d12.ICommandQueue = undefined;
        hrPanicOnFail(device.CreateCommandQueue(&.{
            .Type = .DIRECT,
            .Priority = @intFromEnum(d3d12.COMMAND_QUEUE_PRIORITY.NORMAL),
            .Flags = .{},
            .NodeMask = 0,
        }, &d3d12.IID_ICommandQueue, @ptrCast(&command_queue)));

        std.log.info("D3D12 command queue created", .{});

        var rect: windows.RECT = undefined;
        _ = windows.GetClientRect(window, &rect);

        const width: u32 = @intCast(rect.right);
        const height: u32 = @intCast(rect.bottom);

        var swap_chain: *dxgi.ISwapChain3 = undefined;
        {
            var desc = dxgi.SWAP_CHAIN_DESC{ .BufferDesc = .{ .Width = width, .Height = height, .RefreshRate = .{ .Numerator = 0, .Denominator = 0 }, .Format = rtv_format, .ScanlineOrdering = .UNSPECIFIED, .Scaling = .UNSPECIFIED }, .SampleDesc = .{ .Count = 1, .Quality = 0 }, .BufferUsage = .{ .RENDER_TARGET_OUTPUT = true }, .BufferCount = num_frames, .OutputWindow = window, .Windowed = windows.TRUE, .SwapEffect = .FLIP_DISCARD, .Flags = .{} };
            var temp_swap_chain: *dxgi.ISwapChain = undefined;
            hrPanicOnFail(dxgi_factory.CreateSwapChain(@ptrCast(command_queue), &desc, @ptrCast(&temp_swap_chain)));

            defer _ = temp_swap_chain.Release();

            hrPanicOnFail(temp_swap_chain.QueryInterface(&dxgi.IID_ISwapChain3, @ptrCast(&swap_chain)));
        }

        hrPanicOnFail(dxgi_factory.MakeWindowAssociation(window, .{ .NO_WINDOW_CHANGES = true }));

        var swap_chain_textures: [num_frames]*d3d12.IResource = undefined;

        for (&swap_chain_textures, 0..) |*texture, i| {
            hrPanicOnFail(swap_chain.GetBuffer(@intCast(i), &d3d12.IID_IResource, @ptrCast(&texture.*)));
        }

        std.log.info("Swap chain created", .{});

        var dsv_heap: *d3d12.IDescriptorHeap = undefined;
        hrPanicOnFail(device.CreateDescriptorHeap(&.{
            .Type = .DSV,
            .NumDescriptors = 16,
            .Flags = .{},
            .NodeMask = 0,
        }, &d3d12.IID_IDescriptorHeap, @ptrCast(&dsv_heap)));

        const depth_heap_handle = dsv_heap.GetCPUDescriptorHandleForHeapStart();

        var depth_texture: ?*d3d12.IResource = null;
        const depth_desc = d3d12.RESOURCE_DESC.initDepthBuffer(.R32_TYPELESS, width, height);
        const heap_props = d3d12.HEAP_PROPERTIES.initType(.DEFAULT);
        hrPanicOnFail(device.CreateCommittedResource(&heap_props, d3d12.HEAP_FLAGS{}, &depth_desc, .{ .DEPTH_WRITE = true }, &d3d12.CLEAR_VALUE.initDepthStencil(.D32_FLOAT, 1.0, 0), &d3d12.IID_IResource, @ptrCast(&depth_texture)));

        const dsv_desc = d3d12.DEPTH_STENCIL_VIEW_DESC{ .Format = .D32_FLOAT, .ViewDimension = .TEXTURE2D, .Flags = .{}, .u = .{ .Texture2D = .{ .MipSlice = 0 } } };
        device.CreateDepthStencilView(depth_texture, &dsv_desc, depth_heap_handle);

        var rtv_heap: *d3d12.IDescriptorHeap = undefined;
        hrPanicOnFail(device.CreateDescriptorHeap(&.{
            .Type = .RTV,
            .NumDescriptors = 16,
            .Flags = .{},
            .NodeMask = 0,
        }, &d3d12.IID_IDescriptorHeap, @ptrCast(&rtv_heap)));

        const rtv_heap_start = rtv_heap.GetCPUDescriptorHandleForHeapStart();

        for (swap_chain_textures, 0..) |texture, i| {
            device.CreateRenderTargetView(texture, null, .{ .ptr = rtv_heap_start.ptr + i * device.GetDescriptorHandleIncrementSize(.RTV) });
        }

        std.log.info("RTV heap created", .{});

        var frame_fence: *d3d12.IFence = undefined;
        hrPanicOnFail(device.CreateFence(0, .{}, &d3d12.IID_IFence, @ptrCast(&frame_fence)));

        const frame_fence_event = windows.CreateEventExA(null, "frame_fence_event", 0, windows.EVENT_ALL_ACCESS).?;

        std.log.info("Frame fence event created", .{});

        var command_allocators: [num_frames]*d3d12.ICommandAllocator = undefined;

        for (&command_allocators) |*cmdAlloc| {
            hrPanicOnFail(device.CreateCommandAllocator(.DIRECT, &d3d12.IID_ICommandAllocator, @ptrCast(&cmdAlloc.*)));
        }

        std.log.info("Command allocators created", .{});

        var command_list: *d3d12.IGraphicsCommandList6 = undefined;
        hrPanicOnFail(device.CreateCommandList(0, .DIRECT, command_allocators[0], null, &d3d12.IID_IGraphicsCommandList6, @ptrCast(&command_list)));
        hrPanicOnFail(command_list.Close());

        var options7: d3d12.FEATURE_DATA_D3D12_OPTIONS7 = undefined;
        const res = device.CheckFeatureSupport(.OPTIONS7, &options7, @sizeOf(d3d12.FEATURE_DATA_D3D12_OPTIONS7));
        if (options7.MeshShaderTier == .NOT_SUPPORTED or res != windows.S_OK) {
            _ = windows.MessageBoxA(window, "This applications requires graphics card that supports Mesh Shader " ++
                "(NVIDIA GeForce Turing or newer, AMD Radeon RX 6000 or newer).", "No DirectX 12 Mesh Shader support", windows.MB_OK | windows.MB_ICONERROR);

            return Dx12StateError.NotSupported;
        }

        return .{
            .dxgi_factory = dxgi_factory,
            .device = device,
            .command_queue = command_queue,
            .swap_chain = swap_chain,
            .swap_chain_textures = swap_chain_textures,
            .dsv_heap = dsv_heap,
            .depth_texture = depth_texture.?,
            .depth_heap_handle = depth_heap_handle,
            .rtv_heap = rtv_heap,
            .rtv_heap_start = rtv_heap_start,
            .frame_fence = frame_fence,
            .frame_fence_event = frame_fence_event,
            .command_allocators = command_allocators,
            .command_list = command_list,
        };
    }

    pub fn deinit(dx12: *Dx12State) void {
        _ = dx12.command_list.Release();
        for (dx12.command_allocators) |commandAlloc| _ = commandAlloc.Release();
        _ = dx12.frame_fence.Release();
        _ = windows.CloseHandle(dx12.frame_fence_event);
        _ = dx12.dsv_heap.Release();
        _ = dx12.rtv_heap.Release();
        for (dx12.swap_chain_textures) |swap_chain_texture| _ = swap_chain_texture.Release();
        _ = dx12.swap_chain.Release();
        _ = dx12.command_queue.Release();
        _ = dx12.device.Release();
        _ = dx12.dxgi_factory.Release();
        dx12.* = undefined;
    }

    pub fn present(dx12: *Dx12State) void {
        dx12.frame_fence_counter += 1;

        hrPanicOnFail(dx12.swap_chain.Present(1, .{}));
        hrPanicOnFail(dx12.command_queue.Signal(dx12.frame_fence, dx12.frame_fence_counter));

        const gpu_frame_counter = dx12.frame_fence.GetCompletedValue();
        if ((dx12.frame_fence_counter - gpu_frame_counter) >= num_frames) {
            hrPanicOnFail(dx12.frame_fence.SetEventOnCompletion(gpu_frame_counter + 1, dx12.frame_fence_event));
            windows.WaitForSingleObject(dx12.frame_fence_event, windows.INFINITE) catch {};
        }

        dx12.frame_index = (dx12.frame_index + 1) % num_frames;
    }

    pub fn flush(dx12: *Dx12State) void {
        dx12.frame_fence_counter += 1;

        hrPanicOnFail(dx12.command_queue.Signal(dx12.frame_fence, dx12.frame_fence_counter));
        hrPanicOnFail(dx12.frame_fence.SetEventOnCompletion(dx12.frame_fence_counter, dx12.frame_fence_event));

        windows.WaitForSingleObject(dx12.frame_fence_event, windows.INFINITE) catch {};
    }
};

pub const Resource = struct {
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

    pub fn deinit(self: *const Resource) void {
        _ = self.resource.Release();
    }
};

pub fn createResourceWithSize(name: [:0]const u16, buffer_size: usize, heap_type: d3d12.HEAP_TYPE, device: *d3d12.IDevice9) Resource {
    var resource: ?*d3d12.IResource = null;
    const heap_props = d3d12.HEAP_PROPERTIES.initType(heap_type);
    const buffer_desc = d3d12.RESOURCE_DESC.initBuffer(buffer_size);

    const resource_state = if (heap_type == .UPLOAD) d3d12.RESOURCE_STATES.GENERIC_READ else d3d12.RESOURCE_STATES.COMMON;

    hrPanicOnFail(device.CreateCommittedResource(&heap_props, d3d12.HEAP_FLAGS{}, &buffer_desc, resource_state, null, &d3d12.IID_IResource, @ptrCast(&resource)));

    hrPanicOnFail(resource.?.SetName(name));

    return .{ .resource = resource.?, .buffer_size = buffer_size };
}

pub fn createResource(comptime T: type, name: [:0]const u16, heap_type: d3d12.HEAP_TYPE, device: *d3d12.IDevice9, min_aligned: bool) Resource {
    const buffer_size = if (min_aligned) (@sizeOf(T) + 255) & ~@as(u32, 255) else @sizeOf(T);

    return createResourceWithSize(name, buffer_size, heap_type, device);
}

pub fn copyBuffer(comptime T: type, name: [:0]const u16, src_data: *const std.ArrayList(T), dest_resource: *const Resource, dx12: *const Dx12State) void {
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
