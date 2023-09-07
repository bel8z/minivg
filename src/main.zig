const std = @import("std");
const builtin = @import("builtin");

const win32 = @import("win32.zig");
const wgl = @import("wgl.zig");
const L = win32.L;

const build_opts = @import("build_options");

const GL = if (build_opts.opengl) @import("gl.zig") else void;

// TODO (Matteo): Make it local to main (pass to WndProc via window pointer)?
var gl: GL = undefined;

pub fn main() anyerror!void {
    const app_name = "MiniWin" ++ if (build_opts.opengl) "GL" else "";

    if (build_opts.console) {
        _ = win32.AllocConsole();
        _ = win32.SetConsoleTitleW(L(app_name ++ " - Debug console"));
    }

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

    if (build_opts.opengl) {
        _ = try wgl.init();
    } else {
        try win32.BufferedPaint.init();
        defer win32.BufferedPaint.deinit();
    }

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

    if (build_opts.opengl) {
        const dc = try win32.getDC(win);
        defer _ = win32.releaseDC(win, dc);
        const ctx = try createWglContext(dc);
        _ = try wgl.makeCurrent(dc, ctx);
        try wgl.setSwapInterval(1);
        try gl.init();
        gl.enable(GL.FRAMEBUFFER_SRGB);
    }

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
            if (build_opts.opengl) {
                if (wgl.getCurrentContext()) |context| {
                    wgl.deleteContext(context) catch unreachable;
                }
            }
            win32.destroyWindow(win) catch unreachable;
        },
        win32.WM_DESTROY => {
            win32.PostQuitMessage(0);
        },
        win32.WM_PAINT => {
            if (build_opts.opengl) {
                gl.clearColor(0.5, 0, 0.5, 1);
                gl.clear(GL.COLOR_BUFFER_BIT);

                // TODO: Painting code goes here

                const dc = win32.getDC(win) catch unreachable;
                defer _ = win32.releaseDC(win, dc);
                wgl.swapBuffers(dc) catch unreachable;
            } else if (win32.BufferedPaint.begin(win)) |pb| {
                defer pb.end() catch unreachable;

                // TODO: Painting code goes here
                pb.clear(.All) catch unreachable;
            } else |_| unreachable;
        },
        else => return win32.defWindowProcW(win, msg, wparam, lparam),
    }

    return 0;
}

fn createWglContext(dc: win32.HDC) !win32.HGLRC {
    // NOTE (Matteo): I didn't find a way to ask WGL for a core profile context with
    // the highest version available, so the best I could do is trying all versions
    // since 3.0 in decreasing order.
    const OpenGlVersion = struct { major: c_int, minor: c_int };

    const gl_versions = [_]OpenGlVersion{
        .{ .major = 4, .minor = 6 }, // 2018 - #version 460
        .{ .major = 4, .minor = 5 }, // 2017 - #version 450
        .{ .major = 4, .minor = 4 }, // 2014 - #version 440
        .{ .major = 4, .minor = 3 }, // 2013 - #version 430
        .{ .major = 4, .minor = 2 }, // 2011 - #version 420
        .{ .major = 4, .minor = 1 }, // 2010 - #version 410
        .{ .major = 4, .minor = 0 }, // 2010 - #version 400
        .{ .major = 3, .minor = 3 }, // 2010 - #version 330
        .{ .major = 3, .minor = 2 }, // 2009 - #version 150
        .{ .major = 3, .minor = 1 }, // 2009 - #version 140
        .{ .major = 3, .minor = 0 }, // 2009 - #version 130
    };

    for (gl_versions) |ver| {
        if (wgl.createContext(dc, ver.major, ver.minor)) |context| {
            return context;
        } else |_| {}
    }

    return error.CannotCreateContext;
}
