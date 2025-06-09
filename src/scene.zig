const std = @import("std");
const zmath = @import("zmath");
const Camera = @import("camera.zig").Camera;

pub const Scene = struct {
    camera: Camera,
    model: zmath.Mat,

    pub fn init() !Scene {
        
        return Scene{
            .camera = Camera.init(),
            .model = zmath.identity()
        };
    }

    pub fn deinit(self: *Scene) void {
        _ = self;
    }
};
