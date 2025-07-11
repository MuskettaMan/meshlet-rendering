const std = @import("std");
const Renderer = @import("renderer.zig").Renderer;
const Scene = @import("scene.zig").Scene;
const zwindows = @import("zwindows");
const zmath = @import("zmath");
const zmesh = @import("zmesh");
const zgui = @import("zgui");
const windows = zwindows.windows;
const d3d12 = zwindows.d3d12;
const hrPanicOnFail = zwindows.hrPanicOnFail;

const Window = @import("win_util.zig").Window;

const content_dir = "content/";

fn castPtrToSlice(comptime T: type, mapped_ptr: *anyopaque) [*]T {
    return @as([*]T, @ptrCast(@alignCast(mapped_ptr)));
}

pub const App = struct {
    renderer: Renderer,
    scene: *Scene,
    window: *Window,
    time: i64,
    delta_time_i64: i64,
    total_time: f32,

    pub fn init(allocator: std.mem.Allocator, window: *Window) !App {
        zmesh.init(allocator);
        zgui.init(allocator);

        _ = zgui.io.addFontFromFile(content_dir ++ "Roboto-Medium.ttf", 16.0);

        var renderer = try Renderer.init(allocator, window);
        const scene = try allocator.create(Scene);
        try Scene.init(scene);

        scene.camera.position = .{ 0.0, 0.0, -10.0, 0.0 };
        scene.camera.view = zmath.inverse(zmath.translation(scene.camera.position[0], scene.camera.position[1], scene.camera.position[2]));
        scene.camera.proj = zmath.perspectiveFovLh(0.25 * std.math.pi, window.aspect_ratio, 0.01, 200.0);

        const camera_ptr = renderer.camera_resource.map();
        defer renderer.camera_resource.unmap();

        // TODO: Simplify and clarify this code.
        zmath.storeMat(castPtrToSlice(f32, camera_ptr)[0..16], zmath.transpose(scene.camera.view));
        zmath.storeMat(castPtrToSlice(f32, camera_ptr)[16..32], zmath.transpose(scene.camera.proj));
        zmath.store(castPtrToSlice(f32, camera_ptr)[32..35], scene.camera.position, 3);

        hrPanicOnFail(renderer.dx12.command_list.Close());
        renderer.dx12.command_queue.ExecuteCommandLists(1, &.{@ptrCast(renderer.dx12.command_list)});
        renderer.dx12.flush();

        return .{ .renderer = renderer, .scene = scene, .window = window, .time = std.time.microTimestamp(), .delta_time_i64 = 0, .total_time = 0 };
    }

    pub fn deinit(self: *App) void {
        self.scene.deinit();
        self.renderer.deinit();
        zmesh.deinit();
        zgui.deinit();
    }

    pub fn update(self: *App) !void {
        const instance_ptr = self.renderer.instance_resource.map();
        defer self.renderer.instance_resource.unmap();

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

                    const dx12 = &self.renderer.dx12;
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

            const scale = 0.6;
            self.scene.model = zmath.scaling(scale, scale, scale);
            self.scene.model = zmath.mul(self.scene.model, zmath.rotationX(std.math.pi / 2.0));
            self.scene.model = zmath.mul(self.scene.model, zmath.rotationY(self.total_time));
            self.scene.model = zmath.mul(self.scene.model, zmath.translation(0.0, -2.5, 0.0));

            zmath.storeMat(castPtrToSlice(f32, instance_ptr)[0..16], zmath.transpose(self.scene.model));

            self.renderer.render();
        }

        self.renderer.dx12.flush();
    }
};
