const zmath = @import("zmath");

pub const Camera = struct {
    view: zmath.Mat,
    proj: zmath.Mat,

    pub fn init() Camera {
        return .{ .view = zmath.identity(), .proj = zmath.identity() };
    }
};
