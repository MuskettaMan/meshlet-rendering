const zgui = @import("zgui");
const zwindows = @import("zwindows");
const std = @import("std");

const windows = zwindows.windows;

pub fn processWindowMessage(window: windows.HWND, message: windows.UINT, wparam: windows.WPARAM, lparam: windows.LPARAM) callconv(windows.WINAPI) windows.LRESULT {
    switch (message) {
        windows.WM_KEYDOWN => {
            if (wparam == windows.VK_ESCAPE) {
                windows.PostQuitMessage(0);
                return 0;
            }

            zgui.io.addKeyEvent(win32KeyToKey(wparam), true);
        },
        windows.WM_KEYUP => {
            zgui.io.addKeyEvent(win32KeyToKey(wparam), false);
        },
        windows.WM_GETMINMAXINFO => {
            var info: *windows.MINMAXINFO = @ptrFromInt(@as(usize, @intCast(lparam)));
            info.ptMinTrackSize.x = 400;
            info.ptMinTrackSize.y = 400;
            return 0;
        },
        windows.WM_DESTROY => {
            windows.PostQuitMessage(0);
            return 0;
        },
        windows.WM_LBUTTONDOWN => {
            zgui.io.addMouseButtonEvent(.left, true);
        },
        windows.WM_LBUTTONUP => {
            zgui.io.addMouseButtonEvent(.left, false);
        },
        windows.WM_MOUSEMOVE => {
            zgui.io.addMousePositionEvent(@floatFromInt(windows.GET_X_LPARAM(lparam)), @floatFromInt(windows.GET_Y_LPARAM(lparam)));
        },
        windows.WM_MOUSEWHEEL => {
            const wheel: f32 = if (@as(f32, @floatFromInt(windows.GET_WHEEL_DELTA_WPARAM(wparam))) > 0.0) 1.0 else -1.0;
            zgui.io.addMouseWheelEvent(0.0, wheel);
        },
        else => {},
    }

    return windows.DefWindowProcA(window, message, wparam, lparam);
}

pub const Window = struct {
    handle: windows.HWND,
    width: u32,
    height: u32,
    aspect_ratio: f32,
    rect: windows.RECT,
};

pub fn createWindow(width: u32, height: u32, name: *const [:0]const u8) Window {
    const winclass = windows.WNDCLASSEXA{
        .style = 0,
        .lpfnWndProc = processWindowMessage,
        .cbClsExtra = 0,
        .cbWndExtra = 0,
        .hInstance = @ptrCast(windows.GetModuleHandleA(null)),
        .hIcon = null,
        .hCursor = windows.LoadCursorA(null, @ptrFromInt(32512)),
        .hbrBackground = null,
        .lpszMenuName = null,
        .lpszClassName = name.*,
        .hIconSm = null,
    };
    _ = windows.RegisterClassExA(&winclass);

    const style = windows.WS_OVERLAPPEDWINDOW;

    var rect = windows.RECT{
        .left = 0,
        .top = 0,
        .right = @intCast(width),
        .bottom = @intCast(height),
    };
    _ = windows.AdjustWindowRectEx(&rect, style, windows.FALSE, 0);

    const window = windows.CreateWindowExA(0, name.*, name.*, style + windows.WS_VISIBLE, windows.CW_USEDEFAULT, windows.CW_USEDEFAULT, rect.right - rect.left, rect.bottom - rect.top, null, null, winclass.hInstance, null).?;

    _ = windows.GetClientRect(window, &rect);

    std.log.info("Application window created", .{});

    return .{
        .handle = window,
        .width = width,
        .height = height,
        .aspect_ratio = @as(f32, @floatFromInt(width)) / @as(f32, @floatFromInt(height)),
        .rect = rect,
    };
}

fn win32KeyToKey(wparam: usize) zgui.Key {
    const Key = zgui.Key;
    return switch (wparam) {
        0x08 => Key.back_space,
        0x09 => Key.tab,
        0x0D => Key.enter,
        0x10 => Key.left_shift, // ambiguous without lparam
        0x11 => Key.left_ctrl, // ambiguous without lparam
        0x12 => Key.left_alt, // ambiguous without lparam
        0x1B => Key.escape,
        0x20 => Key.space,
        0x21 => Key.page_up,
        0x22 => Key.page_down,
        0x23 => Key.end,
        0x24 => Key.home,
        0x25 => Key.left_arrow,
        0x26 => Key.up_arrow,
        0x27 => Key.right_arrow,
        0x28 => Key.down_arrow,
        0x2D => Key.insert,
        0x2E => Key.delete,

        0x30 => Key.zero,
        0x31 => Key.one,
        0x32 => Key.two,
        0x33 => Key.three,
        0x34 => Key.four,
        0x35 => Key.five,
        0x36 => Key.six,
        0x37 => Key.seven,
        0x38 => Key.eight,
        0x39 => Key.nine,

        0x41 => Key.a,
        0x42 => Key.b,
        0x43 => Key.c,
        0x44 => Key.d,
        0x45 => Key.e,
        0x46 => Key.f,
        0x47 => Key.g,
        0x48 => Key.h,
        0x49 => Key.i,
        0x4A => Key.j,
        0x4B => Key.k,
        0x4C => Key.l,
        0x4D => Key.m,
        0x4E => Key.n,
        0x4F => Key.o,
        0x50 => Key.p,
        0x51 => Key.q,
        0x52 => Key.r,
        0x53 => Key.s,
        0x54 => Key.t,
        0x55 => Key.u,
        0x56 => Key.v,
        0x57 => Key.w,
        0x58 => Key.x,
        0x59 => Key.y,
        0x5A => Key.z,

        0x70 => Key.f1,
        0x71 => Key.f2,
        0x72 => Key.f3,
        0x73 => Key.f4,
        0x74 => Key.f5,
        0x75 => Key.f6,
        0x76 => Key.f7,
        0x77 => Key.f8,
        0x78 => Key.f9,
        0x79 => Key.f10,
        0x7A => Key.f11,
        0x7B => Key.f12,
        0x7C => Key.f13,
        0x7D => Key.f14,
        0x7E => Key.f15,
        0x7F => Key.f16,
        0x80 => Key.f17,
        0x81 => Key.f18,
        0x82 => Key.f19,
        0x83 => Key.f20,
        0x84 => Key.f21,
        0x85 => Key.f22,
        0x86 => Key.f23,
        0x87 => Key.f24,

        // Left/Right modifiers (preferred with GetKeyState or lParam trick)
        0xA0 => Key.left_shift,
        0xA1 => Key.right_shift,
        0xA2 => Key.left_ctrl,
        0xA3 => Key.right_ctrl,
        0xA4 => Key.left_alt,
        0xA5 => Key.right_alt,

        0x5B => Key.left_super,
        0x5C => Key.right_super,
        0x5D => Key.menu,

        else => Key.none,
    };
}
