const builtin = @import("builtin");
const std = @import("std");
const assert = std.debug.assert;
const fs = std.fs;

// Windows stuff
const win32 = @import("win32.zig");
const L = win32.L;

// Custom libs
const math = @import("math.zig");
const Vec2 = math.Vec2(f32);

pub const Api = @This();
pub const NanoVg = @import("nanovg");
pub const App = opaque {};
pub const Rect = math.AlignedBox2(f32);
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
    dpi: bool = false,
    animations: bool = false,
    demo: bool = false,
    srgb: bool = false,
    vsync: u2 = 1,
    fps_percent: bool = false,
};

init: *const fn (allocator: std.mem.Allocator, vg: NanoVg) Error!*App,
deinit: *const fn (self: *App, allocator: std.mem.Allocator, vg: NanoVg) void,
update: *const fn (
    self: *App,
    vg: NanoVg,
    viewport: Rect,
    cursor: Mouse,
    pixel_size: f32,
    opts: Opts,
) f32,

pub const Loader = struct {
    dir_path: []const u8,
    dir: fs.Dir,
    lib: ?win32.HMODULE = null,
    timestamp: i64 = -1,

    // NOTE (Matteo): Static allocation avoids stack overflow
    var buf: [4 * win32.PATH_MAX_WIDE]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buf);
    const alloc = fba.allocator();

    pub fn init(api_: *Api) !Loader {
        const exe_dir = try fs.selfExeDirPathAlloc(alloc);
        const root = fs.path.dirname(exe_dir) orelse exe_dir;
        const lib_path = try fs.path.join(alloc, &.{ root, "lib", "app.dll" });
        const lib_dir = fs.path.dirname(lib_path) orelse unreachable;

        var self = Loader{
            .dir_path = lib_dir,
            .dir = try std.fs.openDirAbsolute(lib_dir, .{
                .access_sub_paths = false,
                .no_follow = true,
                .iterate = true,
            }),
        };

        if (builtin.mode == .Debug) {
            const updated = try self.updateInternal(api_);
            assert(updated);
        } else {
            const lib = try loadLib(lib_path);
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
            const str = entry.name[start + 4 .. end];

            const timestamp = try std.fmt.parseInt(i64, str, 10);
            if (timestamp > result) result = timestamp;
        }

        if (result < 0) return error.NotFound;
        if (result == self.timestamp) return false;

        const new_lib = try self.loadLibTimestamp(result);
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

    fn loadLibTimestamp(self: *Loader, timestamp: i64) !win32.HMODULE {
        const name = try std.fmt.allocPrint(alloc, "app-{}.dll", .{timestamp});
        defer alloc.free(name);

        const path = try fs.path.join(alloc, &.{ self.dir_path, name });
        defer alloc.free(path);

        return loadLib(path);
    }

    fn loadLib(path: []const u8) !win32.HMODULE {
        const path16 = try std.unicode.utf8ToUtf16LeAllocZ(alloc, path);
        defer alloc.free(path16);

        return win32.LoadLibraryW(path16);
    }

    fn delete(self: *Loader, timestamp: i64) !void {
        var utf8: [256]u8 = undefined;
        try self.dir.deleteFile(try std.fmt.bufPrint(&utf8, "app-{}.dll", .{timestamp}));
        try self.dir.deleteFile(try std.fmt.bufPrint(&utf8, "app-{}.lib", .{timestamp}));
        try self.dir.deleteFile(try std.fmt.bufPrint(&utf8, "app-{}.pdb", .{timestamp}));
    }
};
