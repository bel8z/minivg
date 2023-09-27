const build_opts = @import("build_options");

// Std stuff
const std = @import("std");
const builtin = @import("builtin");
const assert = std.debug.assert;

// Windows stuff
const win32 = @import("win32.zig");
const L = win32.L;

// Custom libs
const math = @import("math.zig");
const Vec2 = math.Vec2(f32);
const Rect = math.AlignedBox(f32);
const rect = math.rect;
const Ui = @import("ui.zig");

// OpenGL stuff
const wgl = @import("wgl.zig");
const GL = @import("gl.zig");
var gl: GL = undefined;

// NanoVG context & backend
const nvg = @import("nanovg");
const nvgl = @import("nvgl.zig");
var vg: nvg = undefined;

const App = @import("App.zig");
const Mouse = App.Mouse;

var app: *App = undefined;

pub fn main() anyerror!void {
    const app_name = "MiniVG";
    const allocator = std.heap.page_allocator;

    try win32.setProcessDpiAware();

    if (build_opts.console) {
        _ = win32.AllocConsole();
        _ = win32.SetConsoleTitleW(L(app_name ++ " - Debug console"));
    }

    // Init window
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

    // Init GL context
    _ = try wgl.init();

    const dc = try win32.getDC(win);
    defer _ = win32.releaseDC(win, dc);
    // TODO (Matteo): Investigate performance issues with 3.3
    const ctx = try wgl.createContext(dc, .{ .v_major = 3, .v_minor = 1 });
    _ = try wgl.makeCurrent(dc, ctx);
    try wgl.setSwapInterval(1);

    // Init OpenGL
    try gl.init();

    // Init NanoVG context
    vg = try nvgl.init(&gl, allocator, .{
        .antialias = true,
        .stencil_strokes = false,
        .debug = true,
    });
    defer vg.deinit();

    // Init fonts
    _ = vg.createFontMem("icons", @embedFile("assets/entypo.ttf"));
    const sans = vg.createFontMem("sans", @embedFile("assets/Roboto-Regular.ttf"));
    const bold = vg.createFontMem("sans-bold", @embedFile("assets/Roboto-Bold.ttf"));
    const emoji = vg.createFontMem("emoji", @embedFile("assets/NotoEmoji-Regular.ttf"));
    _ = vg.addFallbackFontId(sans, emoji);
    _ = vg.addFallbackFontId(bold, emoji);

    // Init app
    app = try allocator.create(App);
    try app.init(vg);
    defer app.deinit(vg);

    // Main loop
    _ = win32.showWindow(win, win32.SW_SHOWDEFAULT);
    try win32.updateWindow(win);

    var msg: win32.MSG = undefined;

    while (true) {
        win32.getMessageW(&msg, null, 0, 0) catch |err| switch (err) {
            error.Quit => break,
            else => return err,
        };

        _ = win32.translateMessage(&msg);
        _ = win32.dispatchMessageW(&msg);
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
            const VK_ESCAPE = 0x1B;
            const VK_SPACE = 0x20;

            switch (wparam) {
                VK_ESCAPE => destroy(win),
                VK_SPACE => app.blowup = !app.blowup,
                'P' => app.premult = !app.premult,
                'D' => app.dpi = !app.dpi,
                'A' => app.animations = !app.animations,
                'F' => app.srgb = !app.srgb,
                else => {},
            }
        },
        win32.WM_PAINT => {
            // DPI correction
            const dpi = if (app.dpi) win32.GetDpiForWindow(win) else 96;
            const pixel_size = 96 / @as(f32, @floatFromInt(dpi));

            // Fetch viewport and DPI information
            var viewport_rect: win32.RECT = undefined;
            _ = win32.GetClientRect(win, &viewport_rect);
            assert(viewport_rect.left == 0 and viewport_rect.top == 0);
            if (viewport_rect.right == 0 or viewport_rect.bottom == 0) return 0;
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

            gl.option(.FRAMEBUFFER_SRGB, app.srgb);

            // Update and render
            gl.viewport(0, 0, viewport_rect.right, viewport_rect.bottom);
            if (app.premult) {
                gl.clearColor(0, 0, 0, 0);
            } else {
                gl.clearColor(0.3, 0.3, 0.32, 1.0);
            }
            gl.clear(GL.COLOR_BUFFER_BIT | GL.DEPTH_BUFFER_BIT | GL.STENCIL_BUFFER_BIT);

            _ = app.update(vg, viewport, cursor, pixel_size);

            // TODO: Painting code goes here
            const dc = win32.getDC(win) catch unreachable;
            defer _ = win32.releaseDC(win, dc);
            wgl.swapBuffers(dc) catch unreachable;
        },

        else => return win32.defWindowProcW(win, msg, wparam, lparam),
    }

    return 0;
}

inline fn destroy(win: win32.HWND) void {
    win32.destroyWindow(win) catch unreachable;
}
