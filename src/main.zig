const build_opts = @import("build_options");

// Std stuff
const std = @import("std");
const builtin = @import("builtin");
const assert = std.debug.assert;

// Windows stuff
const win32 = @import("win32.zig");
const wgl = @import("wgl.zig");
const L = win32.L;

// Dependencies
const nvg = @import("nanovg");
const Demo = @import("demo");
const PerfGraph = @import("perf");

// TODO (Matteo): Replace with custom gl loader
const c = @cImport({
    @cInclude("glad/glad.h");
});

// Main app
var vg: nvg = undefined;
var demo: Demo = undefined;
var fps = PerfGraph.init(.fps, "Frame Time");
var blowup: bool = false;
var screenshot: bool = false;
var premult: bool = false;

pub fn main() anyerror!void {
    const app_name = "MiniVG";

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
        win32.CW_USEDEFAULT,
        win32.CW_USEDEFAULT,
        null,
        null,
        win_class.hInstance,
        null,
    );

    // Init GL context
    _ = try wgl.init();

    const dc = try win32.getDC(win);
    defer _ = win32.releaseDC(win, dc);
    const ctx = try wgl.createContext(dc, .{ .v_major = 2 });
    _ = try wgl.makeCurrent(dc, ctx);
    try wgl.setSwapInterval(1);

    // Init OpenGL
    // TODO (Matteo): Replace with custom OpenGL loader
    if (c.gladLoadGL() == 0) return error.GLADInitFailed; // try gl.init();
    // gl.enable(GL.FRAMEBUFFER_SRGB);

    // Init NanoVG context
    // TODO (Matteo): Replace with custom gl loader
    vg = try nvg.gl.init(std.heap.page_allocator, .{
        .antialias = true,
        .stencil_strokes = false,
        .debug = true,
    });
    defer vg.deinit();

    // Init demo stuff
    demo.load(vg);
    defer demo.free(vg);

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
        win32.WM_CLOSE => {
            if (wgl.getCurrentContext()) |context| {
                wgl.deleteContext(context) catch unreachable;
            }
            win32.destroyWindow(win) catch unreachable;
        },
        win32.WM_DESTROY => {
            win32.PostQuitMessage(0);
        },
        win32.WM_PAINT => {
            // TODO (Matteo): Measure time
            const t = 0;

            // Fetch viewport information
            var viewport: win32.RECT = undefined;
            _ = win32.GetClientRect(win, &viewport);
            assert(viewport.left == 0 and viewport.top == 0);
            const viewport_w: f32 = @floatFromInt(viewport.right);
            const viewport_h: f32 = @floatFromInt(viewport.bottom);

            // TODO (Matteo): Cursor position must be scaled to be kept in "virtual"
            // pixel coordinates
            var cursor: win32.POINT = undefined;
            _ = win32.GetCursorPos(&cursor);
            _ = win32.ScreenToClient(win, &cursor);

            // Update and render
            c.glViewport(0, 0, viewport.right, viewport.bottom);
            if (premult) {
                c.glClearColor(0, 0, 0, 0);
            } else {
                c.glClearColor(0.3, 0.3, 0.32, 1.0);
            }
            c.glClear(c.GL_COLOR_BUFFER_BIT | c.GL_DEPTH_BUFFER_BIT | c.GL_STENCIL_BUFFER_BIT);

            vg.beginFrame(viewport_w, viewport_h, 1);

            demo.draw(
                vg,
                @floatFromInt(cursor.x),
                @floatFromInt(cursor.y),
                viewport_w,
                viewport_h,
                @floatFromInt(t),
                blowup,
            );
            fps.draw(vg, 5, 5);

            vg.endFrame();

            // TODO: Painting code goes here
            const dc = win32.getDC(win) catch unreachable;
            defer _ = win32.releaseDC(win, dc);
            wgl.swapBuffers(dc) catch unreachable;
        },
        else => return win32.defWindowProcW(win, msg, wparam, lparam),
    }

    return 0;
}
