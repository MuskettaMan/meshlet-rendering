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
const Renderer = @import("renderer.zig").Renderer;
const MeshletPass = @import("meshlet_pass.zig");
const MeshletResources = @import("meshlet_resources.zig");
const Geometry = @import("geometry.zig");
const App = @import("app.zig").App;

const window_name: [:0]const u8 = "DX12 Zig";



pub fn main() !void {
    _ = windows.CoInitializeEx(null, windows.COINIT_MULTITHREADED);
    defer windows.CoUninitialize();

    _ = windows.SetProcessDPIAware();

    const pageAllocator = std.heap.page_allocator;

    const width: u32 = 1600;
    const height: u32 = 1200;

    var window = winUtil.createWindow(width, height, &window_name);

    var app = try App.init(pageAllocator, &window);
    defer app.deinit();

    try app.update();

}

