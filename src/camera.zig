const zmath = @import("zmath");

pub const Camera = struct {
    mat: zmath.Mat,

    pub fn init(mat: zmath.Mat) Camera {
        return .{ .mat = mat };
    }
};
