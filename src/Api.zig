const std = @import("std");

// NanoVG
pub const nvg = @import("nanovg");

// Custom libs
pub const math = @import("math.zig");
pub const Vec2 = math.Vec2(f32);

pub const App = opaque {};

pub const Error = std.time.Timer.Error || std.mem.Allocator.Error || error{};

pub const Mouse = struct {
    pos: Vec2 = .{},
    button: packed struct {
        left: bool = false,
        right: bool = false,
        middle: bool = false,
    } = .{},

    pub fn click(mouse: Mouse) bool {
        return (mouse.button.left or mouse.button.middle or mouse.button.right);
    }
};

pub const InitFn = *const fn (api: *@This()) void;

pub const Opts = packed struct {
    blowup: bool = false,
    premult: bool = false,
    dpi: bool = true,
    animations: bool = false,
    srgb: bool = false,
    steady: bool = false,
    fps_percent: bool = false,
};

init: *const fn (allocator: std.mem.Allocator, vg: nvg) Error!*App,
deinit: *const fn (self: *App, allocator: std.mem.Allocator, vg: nvg) void,
update: *const fn (
    self: *App,
    vg: nvg,
    viewport: Vec2,
    cursor: Mouse,
    pixel_size: f32,
    opts: Opts,
) f32,
