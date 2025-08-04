const zmath = @import("zmath");
const std = @import("std");
const zgui = @import("zgui");

pub const Camera = struct {
    view: zmath.Mat,
    proj: zmath.Mat,
    position: zmath.Vec,
    yaw: f32,
    pitch: f32,
    speed: f32,
    sensitivity: f32,

    direction: zmath.Vec,
    up: zmath.Vec,
    right: zmath.Vec,

    prev_mouse_pos: [2]f32,

    pub fn init() Camera {
        var mouse_pos = zgui.getMousePos();
        if (mouse_pos[0] > 10000 or mouse_pos[0] < 0.0) mouse_pos[0] = 0.0;
        if (mouse_pos[1] > 10000 or mouse_pos[1] < 0.0) mouse_pos[1] = 0.0;

        return .{
            .view = zmath.identity(),
            .proj = zmath.identity(),
            .position = zmath.f32x4(0.0, 0.0, 3.0, 0.0),
            .yaw = -90.0, // facing -Z
            .pitch = 0.0,
            .speed = 5.0,
            .sensitivity = 0.1,
            .direction = zmath.f32x4(0.0, 0.0, -1.0, 0.0),
            .up = zmath.f32x4(0.0, 1.0, 0.0, 0.0),
            .right = zmath.f32x4(1.0, 0.0, 0.0, 0.0),
            .prev_mouse_pos = mouse_pos,
        };
    }

    pub fn update(self: *Camera, delta_time: f32) void {
        const io = zgui.io;
        const velocity = self.speed * delta_time;

        var mouse_pos = zgui.getMousePos();
        if (mouse_pos[0] > 10000 or mouse_pos[0] < 0.0) mouse_pos[0] = 0.0;
        if (mouse_pos[1] > 10000 or mouse_pos[1] < 0.0) mouse_pos[1] = 0.0;
        var mouse_delta: [2]f32 = .{ self.prev_mouse_pos[0] - mouse_pos[0], self.prev_mouse_pos[1] - mouse_pos[1] };
        self.prev_mouse_pos = mouse_pos;

        if (!zgui.isMouseDown(.left)) {
            mouse_delta[0] = 0.0;
            mouse_delta[1] = 0.0;
        }
        //std.debug.print("delta x {} delta y {}\n", .{ mouse_delta[0], mouse_delta[1] });

        if (!io.getWantCaptureMouse()) {
            self.yaw -= mouse_delta[0] * self.sensitivity;
            self.pitch += mouse_delta[1] * self.sensitivity;
            self.pitch = std.math.clamp(self.pitch, -89.0, 89.0);
        }

        // Update direction based on yaw and pitch
        const yaw_rad = std.math.degreesToRadians(self.yaw);
        const pitch_rad = std.math.degreesToRadians(self.pitch);

        const dir = zmath.normalize3(zmath.f32x4(
            @cos(pitch_rad) * @sin(yaw_rad),
            @sin(pitch_rad),
            @cos(yaw_rad) * @cos(pitch_rad),
            1.0,
        ));

        const world_up: zmath.Vec = .{ 0.0, 1.0, 0.0, 0.0 };

        self.direction = dir;
        self.right = zmath.normalize3(zmath.cross3(world_up, self.direction));
        self.up = zmath.cross3(self.direction, self.right);

        // Movement
        if (zgui.isKeyDown(zgui.Key.w)) self.position = self.position + (self.direction * zmath.splat(zmath.Vec, velocity));
        if (zgui.isKeyDown(zgui.Key.s)) self.position = self.position - (self.direction * zmath.splat(zmath.Vec, velocity));
        if (zgui.isKeyDown(zgui.Key.a)) self.position = self.position - (self.right * zmath.splat(zmath.Vec, velocity));
        if (zgui.isKeyDown(zgui.Key.d)) self.position = self.position + (self.right * zmath.splat(zmath.Vec, velocity));
        if (zgui.isKeyDown(zgui.Key.space)) self.position = self.position + (self.up * zmath.splat(zmath.Vec, velocity));
        if (zgui.isKeyDown(zgui.Key.left_shift)) self.position = self.position - (self.up * zmath.splat(zmath.Vec, velocity));

        const lookAt = zmath.lookToLh(self.position, dir, world_up);

        self.view = lookAt;
    }
};
