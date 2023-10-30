const build_opts = @import("build_options");

// Std stuff
const std = @import("std");
const builtin = @import("builtin");
const assert = std.debug.assert;

// Windows stuff
const win32 = @import("win32.zig");
const L = win32.L;
const VK_ESCAPE = 0x1B;
const VK_SPACE = 0x20;

// OpenGL stuff
const wgl = @import("exe/wgl.zig");
const GL = @import("exe/gl.zig");
var gl: GL = undefined;

const Api = @import("api.zig");
const math = Api.math;
const Vec2 = Api.Vec2;

// NanoVG context & backend
const NanoVg = Api.NanoVg;
const nvgl = @import("exe/nvgl.zig");
var nvg: NanoVg = undefined;

const App = Api.App;
const Mouse = Api.Mouse;

var api: Api = undefined;
var app: *App = undefined;
var opt = Api.Opts{};

fn print(
    comptime format: []const u8,
    args: anytype,
) void {
    std.debug.print(format, args);
    std.debug.print("\n", .{});
}

pub fn main() anyerror!void {
    const app_name = "MiniVG";

    try win32.setProcessDpiAware();

    if (build_opts.console) {
        if (win32.AttachConsole(std.math.maxInt(u32)) == win32.FALSE) {
            _ = win32.AllocConsole();
            _ = win32.SetConsoleTitleW(L(app_name ++ " - Debug console"));
        }
    }

    var buf: [1024]u8 = undefined;
    print("Startup", .{});
    print("Working directory; {s}", .{std.fs.cwd().realpath(".", &buf) catch unreachable});

    var gpa = std.heap.GeneralPurposeAllocator(.{ .verbose_log = true }){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    // Init window
    print("Creating window...", .{});

    const win_name = L(app_name);

    const win_class = win32.WNDCLASSEXW{
        .style = 0,
        .lpfnWndProc = wndProc,
        .hInstance = win32.getCurrentInstance(),
        .lpszClassName = win_name,
        // Default arrow
        .hCursor = win32.getDefaultCursor(),
        // Don't erase background
        .hbrBackground = null,
        // No icons available
        .hIcon = null,
        .hIconSm = null,
        // No menu
        .lpszMenuName = null,
    };

    _ = try win32.registerClassExW(&win_class);

    const win_flags = win32.WS_OVERLAPPEDWINDOW;
    const win = try win32.createWindowExW(
        0,
        win_name,
        win_name,
        win_flags,
        win32.CW_USEDEFAULT,
        win32.CW_USEDEFAULT,
        800, // win32.CW_USEDEFAULT,
        600, // win32.CW_USEDEFAULT,
        null,
        null,
        win_class.hInstance,
        null,
    );

    const dc = try win32.getDC(win);
    defer _ = win32.releaseDC(win, dc);

    print("Creating window...Done", .{});

    // Init OpenGL
    print("Initializing OpenGL...", .{});

    _ = try wgl.init();
    // TODO (Matteo): Investigate performance issues with 3.3
    const ctx = try wgl.createContext(dc, .{ .v_major = 3, .v_minor = 1 });
    _ = try wgl.makeCurrent(dc, ctx);
    try gl.init();

    print("Initializing OpenGL...Done", .{});

    // Init NanoVG context
    print("Initializing NanoVG...", .{});

    nvg = try nvgl.init(&gl, allocator, .{
        .antialias = true,
        .stencil_strokes = false,
        .debug = true,
    });
    defer nvg.deinit();

    print("Initializing NanoVG...Done", .{});

    // Init fonts
    print("Loading fonts...", .{});

    _ = nvg.createFontMem("icons", @embedFile("assets/entypo.ttf"));
    const sans = nvg.createFontMem("sans", @embedFile("assets/Roboto-Regular.ttf"));
    const bold = nvg.createFontMem("sans-bold", @embedFile("assets/Roboto-Bold.ttf"));
    const emoji = nvg.createFontMem("emoji", @embedFile("assets/NotoEmoji-Regular.ttf"));
    _ = nvg.addFallbackFontId(sans, emoji);
    _ = nvg.addFallbackFontId(bold, emoji);

    print("Loading fonts...Done", .{});

    // Init app
    print("Loading application...", .{});

    var loader = try Api.Loader.init(&api);
    app = try api.init(allocator, nvg);
    defer api.deinit(app, allocator, nvg);

    print("Loading application...Done", .{});

    // Main loop
    print("Enter main loop", .{});

    _ = win32.showWindow(win, win32.SW_SHOWDEFAULT);
    try win32.updateWindow(win);

    var loop_state: enum { Idle, Update, Quit } = .Idle;
    var vsync = !opt.steady; // Force first update
    var msg: win32.MSG = undefined;

    while (loop_state != .Quit) {
        if (loader.update(&api)) {
            // TODO (Matteo): Handle reload?
        }

        if (vsync != opt.steady) {
            try wgl.setSwapInterval(@intFromBool(opt.steady));
            vsync = opt.steady;
        }

        if (vsync) {
            loop_state = .Update;
        } else {
            try win32.waitMessage();
            loop_state = .Idle;
        }

        // Process all input
        while (try win32.peekMessageW(&msg, null, 0, 0, win32.PM_REMOVE)) {
            _ = win32.translateMessage(&msg);
            _ = win32.dispatchMessageW(&msg);

            switch (msg.message) {
                win32.WM_QUIT => {
                    loop_state = .Quit;
                    break;
                },
                win32.WM_PAINT => {
                    // NOTE (Matteo): This must be honored with Begin/EndPaint,
                    // otherwise Windows keeps sending it. To avoid scattered
                    // logic, rendering is done in the main loop only, leaving
                    // WndProc to handle input and "service" messages
                    loop_state = .Update;
                    break;
                },
                else => {},
            }
        }

        if (loop_state == .Update) {
            var ps: win32.PAINTSTRUCT = undefined;
            const paint_dc = win32.beginPaint(win, &ps) catch unreachable;
            defer win32.endPaint(win, &ps) catch unreachable;
            updateAndRender(win, paint_dc);
        }
    }
}

fn wndProc(
    win: win32.HWND,
    msg: u32,
    wparam: win32.WPARAM,
    lparam: win32.LPARAM,
) callconv(win32.WINAPI) win32.LRESULT {
    switch (msg) {
        win32.WM_CLOSE => destroy(win),
        win32.WM_DESTROY => {
            if (wgl.getCurrentContext()) |context| {
                wgl.deleteContext(context) catch unreachable;
            }
            win32.PostQuitMessage(0);
        },
        win32.WM_KEYUP => {
            switch (wparam) {
                VK_ESCAPE => destroy(win),
                'B' => opt.blowup = !opt.blowup,
                'P' => opt.premult = !opt.premult,
                'D' => opt.dpi = !opt.dpi,
                'A' => opt.animations = !opt.animations,
                'R' => opt.srgb = !opt.srgb,
                'S' => opt.steady = !opt.steady,
                'F' => opt.fps_percent = !opt.fps_percent,
                else => {},
            }

            if (!opt.steady) _ = win32.InvalidateRect(win, null, win32.TRUE);
        },
        win32.WM_MOUSEMOVE => {
            if (!opt.steady) _ = win32.InvalidateRect(win, null, win32.TRUE);
        },
        win32.WM_PAINT => {
            // NOTE (Matteo): Just marking the event has being handled, see
            // main loop for actual management.
        },
        else => return win32.defWindowProcW(win, msg, wparam, lparam),
    }

    return 0;
}

inline fn destroy(win: win32.HWND) void {
    win32.destroyWindow(win) catch unreachable;
}

fn updateAndRender(win: win32.HWND, dc: win32.HDC) void {
    // DPI correction
    const dpi = if (opt.dpi) win32.GetDpiForWindow(win) else 96;
    const pixel_size = 96 / @as(f32, @floatFromInt(dpi));

    // Fetch viewport and DPI information
    var viewport_rect: win32.RECT = undefined;
    _ = win32.GetClientRect(win, &viewport_rect);
    assert(viewport_rect.left == 0 and viewport_rect.top == 0);
    if (viewport_rect.right == 0 or viewport_rect.bottom == 0) return;
    const viewport = Vec2.fromInt(.{ viewport_rect.right, viewport_rect.bottom }).mul(pixel_size);

    // TODO (Matteo): Cursor position must be scaled to be kept in "virtual"
    // pixel coordinates
    var cursor_pt: win32.POINT = undefined;
    _ = win32.GetCursorPos(&cursor_pt);
    _ = win32.ScreenToClient(win, &cursor_pt);
    const cursor = Mouse{
        .pos = Vec2.fromInt(cursor_pt).mul(pixel_size),
        .button = .{
            .left = win32.isKeyPressed(0x01), // VK_LBUTTON
            .right = win32.isKeyPressed(0x02), // VK_RBUTTON
            .middle = win32.isKeyPressed(0x04), // VK_MBUTTON
        },
    };

    gl.option(.FRAMEBUFFER_SRGB, opt.srgb);

    // Update and render
    gl.viewport(0, 0, viewport_rect.right, viewport_rect.bottom);
    if (opt.premult) {
        gl.clearColor(0, 0, 0, 0);
    } else {
        gl.clearColor(0.3, 0.3, 0.32, 1.0);
    }
    gl.clear(GL.COLOR_BUFFER_BIT | GL.DEPTH_BUFFER_BIT | GL.STENCIL_BUFFER_BIT);

    _ = api.update(app, nvg, viewport, cursor, pixel_size, opt);

    wgl.swapBuffers(dc) catch unreachable;
}
