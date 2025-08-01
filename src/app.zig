const std = @import("std");
const Renderer = @import("renderer.zig").Renderer;
const Scene = @import("scene.zig").Scene;
const zwindows = @import("zwindows");
const zmath = @import("zmath");
const zmesh = @import("zmesh");
const zgui = @import("zgui");
const ModelLoader = @import("model_loader.zig");
const zcgltf = zmesh.io.zcgltf;
const windows = zwindows.windows;
const d3d12 = zwindows.d3d12;
const hrPanicOnFail = zwindows.hrPanicOnFail;

const Window = @import("win_util.zig").Window;

const content_dir = "content/";

fn castPtrToSlice(comptime T: type, mapped_ptr: *anyopaque) [*]T {
    return @as([*]T, @ptrCast(@alignCast(mapped_ptr)));
}

pub const App = struct {
    allocator: std.mem.Allocator,
    renderer: Renderer,
    scene: *Scene,
    window: *Window,
    time: i64,
    delta_time_i64: i64,
    total_time: f32,
    nodes: std.ArrayList(ModelLoader.Node),

    pub fn init(allocator: std.mem.Allocator, window: *Window) !App {
        zmesh.init(allocator);
        zgui.init(allocator);

        var point: windows.POINT = undefined;
        _ = windows.GetCursorPos(&point);
        zgui.io.addMousePositionEvent(@floatFromInt(point.x), @floatFromInt(point.y));

        _ = zgui.io.addFontFromFile(content_dir ++ "Roboto-Medium.ttf", 16.0);

        var renderer = try Renderer.init(allocator, window);
        const scene = try allocator.create(Scene);
        try Scene.init(scene);

        const model = try ModelLoader.load("content/Sponza/Sponza.gltf", allocator);

        for (model.meshes.items) |*mesh| {
            const handle = try renderer.geometry.loadMesh(allocator, mesh);
            _ = handle;
        }

        scene.camera.position = .{ 0.0, 2.0, -10.0, 0.0 };
        scene.camera.view = zmath.inverse(zmath.translation(scene.camera.position[0], scene.camera.position[1], scene.camera.position[2]));
        scene.camera.proj = zmath.perspectiveFovLh(std.math.degreesToRadians(70), window.aspect_ratio, 0.01, 200.0);

        hrPanicOnFail(renderer.dx12.command_list.Close());
        renderer.dx12.command_queue.ExecuteCommandLists(1, &.{@ptrCast(renderer.dx12.command_list)});
        renderer.dx12.flush();

        return .{ .allocator = allocator, .renderer = renderer, .scene = scene, .window = window, .time = std.time.microTimestamp(), .delta_time_i64 = 0, .total_time = 0, .nodes = model.scene };
    }

    pub fn deinit(self: *App) void {
        self.scene.deinit();
        self.renderer.deinit();
        zmesh.deinit();
        zgui.deinit();
    }

    pub fn update(self: *App) !void {
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
                _ = windows.GetClientRect(self.window.handle, &rect);
                if (rect.right == 0 and rect.bottom == 0) {
                    windows.Sleep(10);
                    continue :main_loop;
                }

                if (rect.right != self.window.rect.right or rect.bottom != self.window.rect.bottom) {
                    rect.right = @max(1, rect.right);
                    rect.bottom = @max(1, rect.bottom);
                    std.log.info("Window resized to {d}x{d}", .{ rect.right, rect.bottom });

                    const dx12 = self.renderer.dx12;
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

                self.window.rect = rect;
                self.window.width = @intCast(rect.right);
                self.window.height = @intCast(rect.bottom);
                self.window.aspect_ratio = @as(f32, @floatFromInt(self.window.width)) / @as(f32, @floatFromInt(self.window.height));

                self.renderer.width = self.window.width;
                self.renderer.height = self.window.height;
            }

            const current_time = std.time.microTimestamp();
            self.delta_time_i64 = current_time - self.time;
            self.time = current_time;

            const delta_time: f32 = @as(f32, @floatFromInt(self.delta_time_i64)) / @as(f32, std.time.us_per_s);
            self.total_time += delta_time;

            self.scene.camera.update(delta_time);
            self.renderer.updateCamera(&self.scene.camera);

            //try self.renderer.drawMesh(self.nodes.items[0].mesh, self.nodes.items[0].transform);
            for (self.nodes.items) |*node| {
                try self.renderer.drawMesh(node.mesh, node.transform);
            }

            self.renderer.render();
        }

        self.renderer.dx12.flush();
    }
};
