const builtin = @import("builtin");
const std = @import("std");
const assert = std.debug.assert;

pub const Api = @This();

// Windows stuff
const win32 = @import("win32.zig");
const L = win32.L;

// NanoVG
pub const NanoVg = @import("nanovg");

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

pub const InitFn = *const fn (api: *Api) void;

pub const Opts = packed struct {
    blowup: bool = false,
    premult: bool = false,
    dpi: bool = true,
    animations: bool = false,
    srgb: bool = false,
    steady: bool = false,
    fps_percent: bool = false,
};

init: *const fn (allocator: std.mem.Allocator, vg: NanoVg) Error!*App,
deinit: *const fn (self: *App, allocator: std.mem.Allocator, vg: NanoVg) void,
update: *const fn (
    self: *App,
    vg: NanoVg,
    viewport: Vec2,
    cursor: Mouse,
    pixel_size: f32,
    opts: Opts,
) f32,

pub const Loader = struct {
    dir: std.fs.IterableDir,
    lib: ?win32.HMODULE = null,
    timestamp: i64 = -1,

    pub fn init(api_: *Api) !Loader {
        var self = Loader{
            .dir = try std.fs.cwd().openIterableDir(
                "../lib",
                .{ .access_sub_paths = false, .no_follow = true },
            ),
        };

        if (builtin.mode == .Debug) {
            const updated = try self.updateInternal(api_);
            assert(updated);
        } else {
            const lib = try win32.LoadLibraryW(L("../lib/app.dll"));
            const init_fn = try win32.loadProc(Api.InitFn, "initApi", lib);
            init_fn(api_);
            self.lib = lib;
        }

        return self;
    }

    pub inline fn update(self: *Loader, api_: *Api) bool {
        return if (builtin.mode == .Debug)
            self.updateInternal(api_) catch false
        else
            true;
    }

    fn updateInternal(self: *Loader, api_: *Api) !bool {
        var result: i64 = self.timestamp;
        var iter = self.dir.iterate();

        while (true) {
            const maybe = try iter.next();
            const entry = maybe orelse break;

            const start = std.ascii.indexOfIgnoreCase(entry.name, "app-") orelse continue;
            const end = std.ascii.indexOfIgnoreCase(entry.name, ".dll") orelse continue;
            const buf = entry.name[start + 4 .. end];

            const timestamp = try std.fmt.parseInt(i64, buf, 10);
            if (timestamp > result) result = timestamp;
        }

        if (result < 0) return error.NotFound;
        if (result == self.timestamp) return false;

        const new_lib = try loadLib(result);
        const init_fn = try win32.loadProc(Api.InitFn, "initApi", new_lib);
        init_fn(api_);

        if (self.lib) |old_lib| {
            win32.FreeLibrary(old_lib);
            assert(self.timestamp > 0);
            self.delete(self.timestamp) catch {}; // Deleting is useful but optional
        }

        self.timestamp = result;
        self.lib = new_lib;
        return true;
    }

    fn loadLib(timestamp: i64) !win32.HMODULE {
        var utf8: [256]u8 = undefined;
        var utf16: [256]u16 = undefined;

        const name = try std.fmt.bufPrint(&utf8, "../lib/app-{}.dll", .{timestamp});
        const len = try std.unicode.utf8ToUtf16Le(&utf16, name);
        utf16[len] = 0;

        return win32.LoadLibraryW(utf16[0..len :0]);
    }

    fn delete(self: *Loader, timestamp: i64) !void {
        var utf8: [256]u8 = undefined;
        try self.dir.dir.deleteFile(try std.fmt.bufPrint(&utf8, "app-{}.dll", .{timestamp}));
        try self.dir.dir.deleteFile(try std.fmt.bufPrint(&utf8, "app-{}.lib", .{timestamp}));
        try self.dir.dir.deleteFile(try std.fmt.bufPrint(&utf8, "app-{}.pdb", .{timestamp}));
    }
};
