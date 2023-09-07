const std = @import("std");

const win32 = @import("win32.zig");
const L = win32.L;
const WINAPI = win32.WINAPI;

// See https://www.khronos.org/registry/OpenGL/extensions/ARB/WGL_ARB_create_context.txt for all
// values
const WGL_CONTEXT_MAJOR_VERSION_ARB = 0x2091;
const WGL_CONTEXT_MINOR_VERSION_ARB = 0x2092;
const WGL_CONTEXT_FLAGS_ARB = 0x2094;
const WGL_CONTEXT_PROFILE_MASK_ARB = 0x9126;
const WGL_CONTEXT_DEBUG_BIT_ARB = 0x0001;
const WGL_CONTEXT_FORWARD_COMPATIBLE_BIT_ARB = 0x0002;
const WGL_CONTEXT_CORE_PROFILE_BIT_ARB = 0x00000001;
const WGL_CONTEXT_COMPATIBILITY_PROFILE_BIT_ARB = 0x00000002;
// See https://www.khronos.org/registry/OpenGL/extensions/ARB/WGL_ARB_pixel_format.txt for all
// values
const WGL_DRAW_TO_WINDOW_ARB = 0x2001;
const WGL_ACCELERATION_ARB = 0x2003;
const WGL_SUPPORT_OPENGL_ARB = 0x2010;
const WGL_DOUBLE_BUFFER_ARB = 0x2011;
const WGL_PIXEL_TYPE_ARB = 0x2013;
const WGL_COLOR_BITS_ARB = 0x2014;
const WGL_DEPTH_BITS_ARB = 0x2022;
const WGL_STENCIL_BITS_ARB = 0x2023;
// See https://registry.khronos.org/OpenGL/extensions/ARB/WGL_ARB_pixel_format.txt
const WGL_FRAMEBUFFER_SRGB_CAPABLE_ARB = 0x20A9;
// See https://registry.khronos.org/OpenGL/extensions/ARB/ARB_multisample.txt
const WGL_SAMPLE_BUFFERS_ARB = 0x2041;
const WGL_SAMPLES_ARB = 0x2042;

const WGL_FULL_ACCELERATION_ARB = 0x2027;
const WGL_TYPE_RGBA_ARB = 0x202B;

const PFD_TYPE_RGBA = 0;

const PFD_MAIN_PLANE = 0;

const PFD_DRAW_TO_WINDOW = 0x00000004;
const PFD_DRAW_TO_BITMAP = 0x00000008;
const PFD_SUPPORT_GDI = 0x00000010;
const PFD_SUPPORT_OPENGL = 0x00000020;
const PFD_GENERIC_ACCELERATED = 0x00001000;
const PFD_GENERIC_FORMAT = 0x00000040;
const PFD_NEED_PALETTE = 0x00000080;
const PFD_NEED_SYSTEM_PALETTE = 0x00000100;
const PFD_DOUBLEBUFFER = 0x00000001;
const PFD_STEREO = 0x00000002;
const PFD_SWAP_LAYER_BUFFERS = 0x00000800;

const PFD_DEPTH_DONTCARE = 0x20000000;
const PFD_DOUBLEBUFFER_DONTCARE = 0x40000000;
const PFD_STEREO_DONTCARE = 0x80000000;

extern "gdi32" fn DescribePixelFormat(
    hdc: win32.HDC,
    iPixelFormat: c_int,
    nBytes: c_uint,
    ppfd: [*c]win32.gdi32.PIXELFORMATDESCRIPTOR,
) callconv(WINAPI) win32.BOOL;

extern "gdi32" fn SetPixelFormat(
    hdc: win32.HDC,
    iPixelFormat: c_int,
    ppfd: [*c]const win32.gdi32.PIXELFORMATDESCRIPTOR,
) callconv(WINAPI) win32.BOOL;

extern "gdi32" fn wglDeleteContext(hglrc: win32.HGLRC) callconv(WINAPI) win32.BOOL;
extern "gdi32" fn wglGetProcAddress(name: win32.LPCSTR) callconv(WINAPI) ?win32.FARPROC;
extern "gdi32" fn wglGetCurrentContext() callconv(WINAPI) ?win32.HGLRC;
extern "gdi32" fn wglGetCurrentDC() callconv(WINAPI) win32.HDC;

const WglCreateContextAttribsARBFn = *const fn (
    hdc: win32.HDC,
    hShareContext: ?win32.HGLRC,
    attribList: [*c]const c_int,
) callconv(WINAPI) ?win32.HGLRC;

const WglChoosePixelFormatARBFn = *const fn (
    hdc: win32.HDC,
    piAttribIList: [*c]const c_int,
    pfAttribFList: [*c]const f32,
    nMaxFormats: c_uint,
    piFormats: [*c]c_int,
    nNumFormats: [*c]c_uint,
) callconv(WINAPI) win32.BOOL;

const WglSwapIntervalEXTFn = *const fn (interval: c_int) callconv(WINAPI) win32.BOOL;

var wglCreateContextAttribsARB: WglCreateContextAttribsARBFn = undefined;
var wglChoosePixelFormatARB: WglChoosePixelFormatARBFn = undefined;
var wglSwapIntervalEXT: WglSwapIntervalEXTFn = undefined;

pub fn init() !void {
    // Before we can load extensions, we need a dummy OpenGL context, created using a dummy window.
    // We use a dummy window because you can only set the pixel format for a window once. For the
    // real window, we want to use wglChoosePixelFormatARB (so we can potentially specify options
    // that aren't available in PIXELFORMATDESCRIPTOR), but we can't load and use that before we
    // have a context.

    const window_class = win32.user32.WNDCLASSEXW{
        .style = win32.user32.CS_HREDRAW | win32.user32.CS_VREDRAW | win32.user32.CS_OWNDC,
        .lpfnWndProc = win32.user32.DefWindowProcW,
        .hInstance = win32.getCurrentInstance(),
        .lpszClassName = L("WGL_Boostrap_Window"),
        .lpszMenuName = null,
        .hIcon = null,
        .hIconSm = null,
        .hCursor = null,
        .hbrBackground = null,
    };

    _ = try win32.registerClassExW(&window_class);
    defer win32.unregisterClassW(window_class.lpszClassName, window_class.hInstance) catch unreachable;

    const dummy_window = try win32.createWindowExW(
        0,
        window_class.lpszClassName,
        window_class.lpszClassName,
        win32.WS_OVERLAPPEDWINDOW,
        win32.user32.CW_USEDEFAULT,
        win32.user32.CW_USEDEFAULT,
        win32.user32.CW_USEDEFAULT,
        win32.user32.CW_USEDEFAULT,
        null,
        null,
        window_class.hInstance,
        null,
    );
    defer win32.user32.destroyWindow(dummy_window) catch unreachable;

    const dummy_dc = try win32.user32.getDC(dummy_window);
    defer _ = win32.user32.releaseDC(dummy_window, dummy_dc);

    var pfd = win32.gdi32.PIXELFORMATDESCRIPTOR{
        .nVersion = 1,
        .iPixelType = PFD_TYPE_RGBA,
        .dwFlags = PFD_DRAW_TO_WINDOW | PFD_SUPPORT_OPENGL | PFD_DOUBLEBUFFER,
        .iLayerType = PFD_MAIN_PLANE,
        .cDepthBits = 24,
        .cStencilBits = 8,
        .cColorBits = 32,
        .cAlphaBits = 8,
        .cAlphaShift = 0,
        .cRedBits = 0,
        .cRedShift = 0,
        .cGreenBits = 0,
        .cGreenShift = 0,
        .cBlueBits = 0,
        .cBlueShift = 0,
        .cAccumBits = 0,
        .cAccumRedBits = 0,
        .cAccumGreenBits = 0,
        .cAccumBlueBits = 0,
        .cAccumAlphaBits = 0,
        .cAuxBuffers = 0,
        .bReserved = 0,
        .dwLayerMask = 0,
        .dwVisibleMask = 0,
        .dwDamageMask = 0,
    };

    const pixel_format = win32.gdi32.ChoosePixelFormat(dummy_dc, &pfd);
    if (pixel_format == 0) return error.Unexpected;

    if (SetPixelFormat(dummy_dc, pixel_format, &pfd) == 0) return error.Unexpected;

    const dummy_context = win32.gdi32.wglCreateContext(dummy_dc) orelse return error.Unexpected;
    defer _ = wglDeleteContext(dummy_context);

    try makeCurrent(dummy_dc, dummy_context);
    defer makeCurrent(dummy_dc, null) catch unreachable;

    wglCreateContextAttribsARB = loadProc(
        WglCreateContextAttribsARBFn,
        "wglCreateContextAttribsARB",
    ) orelse return error.Unexpected;

    wglChoosePixelFormatARB = loadProc(
        WglChoosePixelFormatARBFn,
        "wglChoosePixelFormatARB",
    ) orelse return error.Unexpected;

    wglSwapIntervalEXT = loadProc(
        WglSwapIntervalEXTFn,
        "wglSwapIntervalEXT",
    ) orelse return error.Unexpected;
}

pub fn loadProc(comptime T: type, comptime name: [*:0]const u8) ?T {
    if (wglGetProcAddress(name)) |proc| return @as(T, @ptrCast(proc));

    if (win32.kernel32.GetModuleHandleW(L("opengl32"))) |gl32| {
        if (win32.loadProc(T, name, gl32)) |proc| {
            return proc;
        } else |_| {}
    }

    return null;
}

pub const ContextInfo = struct {
    v_major: u8,
    v_minor: u8 = 0,
    multi_samples: u8 = 0,
};

pub fn createContext(dc: win32.HDC, info: ContextInfo) !win32.HGLRC {
    const pixel_format_attribs = [_]c_int{
        WGL_DRAW_TO_WINDOW_ARB, 1, // GL_TRUE
        WGL_SUPPORT_OPENGL_ARB, 1, // GL_TRUE
        WGL_DOUBLE_BUFFER_ARB, 1, // GL_TRUE
        WGL_FRAMEBUFFER_SRGB_CAPABLE_ARB, 1, // GL_TRUE
        WGL_ACCELERATION_ARB,             WGL_FULL_ACCELERATION_ARB,
        WGL_PIXEL_TYPE_ARB,               WGL_TYPE_RGBA_ARB,
        WGL_COLOR_BITS_ARB,               32,
        WGL_DEPTH_BITS_ARB,               24,
        WGL_STENCIL_BITS_ARB,             8,
        WGL_SAMPLE_BUFFERS_ARB,           if (info.multi_samples > 0) 1 else 0,
        WGL_SAMPLES_ARB,                  @as(c_int, @intCast(info.multi_samples)),
        0,
    };

    var pixel_format: i32 = undefined;
    var num_formats: u32 = undefined;
    if (wglChoosePixelFormatARB(
        dc,
        &pixel_format_attribs,
        0,
        1,
        &pixel_format,
        &num_formats,
    ) == 0) {
        return error.ChoosePixelFormatFailed;
    }

    std.debug.assert(num_formats > 0);

    var pfd: win32.gdi32.PIXELFORMATDESCRIPTOR = undefined;
    if (DescribePixelFormat(dc, pixel_format, @sizeOf(@TypeOf(pfd)), &pfd) == 0) return error.DescribePixelFormatFailed;
    if (SetPixelFormat(dc, pixel_format, &pfd) == 0) return error.SetPixelFormatFailed;

    // Specify that we want to create an OpenGL core profile context
    var context_attribs = [_]c_int{
        WGL_CONTEXT_MAJOR_VERSION_ARB, @as(c_int, @intCast(info.v_major)),
        WGL_CONTEXT_MINOR_VERSION_ARB, @as(c_int, @intCast(info.v_minor)),
        WGL_CONTEXT_FLAGS_ARB,         0,
        0,                             0,
        0,
    };

    if (info.v_major > 2) {
        context_attribs[5] = WGL_CONTEXT_DEBUG_BIT_ARB | WGL_CONTEXT_FORWARD_COMPATIBLE_BIT_ARB;
        context_attribs[6] = WGL_CONTEXT_PROFILE_MASK_ARB;
        context_attribs[7] = WGL_CONTEXT_CORE_PROFILE_BIT_ARB;
    }

    if (wglCreateContextAttribsARB(dc, null, &context_attribs)) |context| {
        return context;
    }

    return error.CannotCreateContext;
}

pub fn deleteContext(context: win32.HGLRC) !void {
    if (wglDeleteContext(context) == 0) return error.Unexpected;
}

pub fn makeCurrent(dc: win32.HDC, gl_context: ?win32.HGLRC) !void {
    if (!win32.gdi32.wglMakeCurrent(dc, gl_context)) return error.Unexpected;
}

pub fn getCurrentContext() ?win32.HGLRC {
    return wglGetCurrentContext();
}

pub fn getCurrentDC() ?win32.HDC {
    return wglGetCurrentDC();
}

pub fn swapBuffers(dc: win32.HDC) !void {
    if (!win32.gdi32.SwapBuffers(dc)) return error.Unexpected;
}

pub fn setSwapInterval(interval: c_int) !void {
    if (wglSwapIntervalEXT(interval) == 0) return error.Unexpected;
}
