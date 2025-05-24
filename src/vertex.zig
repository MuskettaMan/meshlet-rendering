const zmath = @import("zmath");

pub const Vertex = struct {
    position: zmath.Vec,

    pub fn init(position: zmath.Vec) Vertex {
        return .{ .position = position };
    }
};