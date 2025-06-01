const zmath = @import("zmath");

pub const Camera = struct {
    view: zmath.Mat,
    proj: zmath.Mat,
    position: zmath.Vec,

    pub fn init() Camera {
        return .{ .view = zmath.identity(), .proj = zmath.identity(), .position = .{ 0.0, 0.0, 0.0, 0.0 } };
    }
};
