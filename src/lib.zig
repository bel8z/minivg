const build_opts = @import("build_options");

// Std stuff
const std = @import("std");
const builtin = @import("builtin");
const assert = std.debug.assert;
const Stopwatch = std.time.Timer;

const Api = @import("Api.zig");
const NanoVg = Api.NanoVg;
const Error = Api.Error;
const Mouse = Api.Mouse;

const math = Api.math;
const Vec2 = Api.Vec2;
const Rect = math.AlignedBox2(f32);
const rect = math.rect;

const PerfGraph = @import("lib/perf_graph.zig");
const Layout = @import("lib/layout.zig");

// Demo stuff
const image_files = [_][]const u8{
    @embedFile("assets/image1.jpg"),
    @embedFile("assets/image2.jpg"),
    @embedFile("assets/image3.jpg"),
    @embedFile("assets/image4.jpg"),
    @embedFile("assets/image5.jpg"),
    @embedFile("assets/image6.jpg"),
    @embedFile("assets/image7.jpg"),
    @embedFile("assets/image8.jpg"),
    @embedFile("assets/image9.jpg"),
    @embedFile("assets/image10.jpg"),
    @embedFile("assets/image11.jpg"),
    @embedFile("assets/image12.jpg"),
};

// Demo stuff
images: [image_files.len]NanoVg.Image = undefined,
// FPS measurement
watch: Stopwatch = undefined,
elapsed: f32 = 0,
fps: PerfGraph = undefined,
layout: Layout = undefined,

const App = @This();

pub export fn initApi(api: *Api) void {
    api.init = init;
    api.deinit = deinit;
    api.update = update;
}

pub fn init(allocator: std.mem.Allocator, nvg: NanoVg) Error!*Api.App {
    var self = try allocator.create(App);

    self.* = std.mem.zeroInit(App, .{});
    self.watch = try Stopwatch.start();
    _ = self.frame();

    for (&self.images, 0..) |*image, i| {
        image.* = nvg.createImageMem(image_files[i], .{});
    }

    // NOTE (Matteo): Name is allocated because static strings are
    // not friendly to hot reloading
    self.fps = PerfGraph.init(try allocator.dupe(u8, "Frame Time"));

    self.layout = Layout.init();

    return @ptrCast(self);
}

pub fn deinit(app: *Api.App, allocator: std.mem.Allocator, nvg: NanoVg) void {
    const self: *App = @ptrCast(@alignCast(app));
    for (self.images) |image| {
        nvg.deleteImage(image);
    }
    allocator.destroy(self);
}

pub fn update(
    app: *Api.App,
    nvg: NanoVg,
    viewport: Vec2,
    cursor: Mouse,
    pixel_size: f32,
    opts: Api.Opts,
) f32 {
    const self: *App = @ptrCast(@alignCast(app));
    const dt = self.frame();

    nvg.beginFrame(viewport.x, viewport.y, 1 / pixel_size);

    // Draw options
    {
        // TODO (Matteo): Improve / cleanup
        nvg.save();
        defer nvg.restore();

        nvg.fontSize(15.0);
        nvg.fontFace("sans");
        nvg.fillColor(NanoVg.rgba(255, 255, 255, 128));
        nvg.textAlign(.{ .horizontal = .left, .vertical = .top });

        var bounds: [4]f32 = undefined;
        _ = nvg.textBounds(0, 0, "long_option_name: off", &bounds);
        const h = bounds[3] - bounds[1];
        const x = viewport.x - bounds[2] - bounds[0];
        var y: f32 = 0;

        const opt_fields = std.meta.fields(@TypeOf(opts));
        inline for (opt_fields) |field| {
            assert(field.type == bool);
            nvg.textAlign(.{ .horizontal = .left, .vertical = .top });
            var adv = nvg.text(x, y, field.name);
            adv = nvg.text(adv, y, ":");
            nvg.textAlign(.{ .horizontal = .right, .vertical = .top });
            _ = nvg.text(viewport.x, y, if (@field(opts, field.name)) "ON" else "OFF");
            y += h;
        }
    }

    // Draw demo stuff
    demo(nvg, cursor, viewport, self.images[0..], self.elapsed, opts);

    // Draw FPS graph
    self.fps.update(dt);
    self.fps.draw(nvg, 5, 5, if (opts.fps_percent) .percent else .fps);

    nvg.endFrame();
    return dt;
}

fn frame(self: *App) f32 {
    const t = @as(f32, @floatFromInt(self.watch.read())) / 1000_000_000.0;
    const dt = t - self.elapsed;
    self.elapsed = t;
    return dt;
}

fn demo(
    nvg: NanoVg,
    m: Mouse,
    viewport: Vec2,
    images: []const NanoVg.Image,
    t: f32,
    opts: Api.Opts,
) void {
    if (opts.animations) {
        drawEyes(nvg, viewport.x - 250, 50, 150, 100, m.pos.x, m.pos.y, t);
        drawParagraph(nvg, viewport.x - 450, 50, 150, 100, m.pos.x, m.pos.y);
        drawGraph(nvg, 0, viewport.y / 2, viewport.x, viewport.y / 2, t);
        colorPicker(nvg, viewport.x - 300, viewport.y - 300, 250, 250, t);

        // Line joints
        drawLines(nvg, 120, viewport.y - 50, 600, 50, t);

        // Line widths
        drawWidths(nvg, 10, 50, 30);

        // Line caps
        drawCaps(nvg, 10, 300, 30);

        drawScissor(nvg, 50, viewport.y - 80, t);
    }

    nvg.save();
    if (opts.blowup) {
        nvg.rotate(@sin(t * 0.3) * 5.0 / 180.0 * math.pi);
        nvg.scale(2.0, 2.0);
    }

    // Widgets
    drawWindow(nvg, "Widgets `n Stuff", 50, 50, 300, 400);
    var x: f32 = 60;
    var y: f32 = 95;
    drawSearchBox(nvg, "Search", x, y, 280, 25);
    y += 40;
    drawDropDown(nvg, "Effects", x, y, 280, 28);
    const popy = y + 14;
    y += 45;

    // Form
    label(nvg, "Login", x, y, 280, 20);
    y += 25;
    textBox(nvg, "Email", x, y, 280, 28);
    y += 35;
    textBox(nvg, "Password", x, y, 280, 28);
    y += 38;
    checkBox(nvg, "Remember me", x, y, 140, 28);
    _ = button(nvg, .Login, "Sign in", rect(x + 138, y, 140, 28), NanoVg.rgba(0, 96, 128, 255), m);
    y += 45;

    // Slider
    label(nvg, "Diameter", x, y, 280, 20);
    y += 25;
    textBoxNum(nvg, "123.00", "px", x + 180, y, 100, 28);
    slider(nvg, 0.4, rect(x, y, 170, 28));
    y += 55;

    _ = button(nvg, .Trash, "Delete", rect(x, y, 160, 28), NanoVg.rgba(128, 16, 8, 255), m);
    _ = button(nvg, .None, "Cancel", rect(x + 170, y, 110, 28), NanoVg.rgba(0, 0, 0, 0), m);

    // Thumbnails box
    drawThumbnails(nvg, 365, popy - 30, 160, 300, images, t);

    nvg.restore();
}

// Icons
const Icon = enum(u21) {
    None = 0,

    Search = 0x1F50D,
    CircledCross = 0x2716,
    ChevronRight = 0xE75E,
    Check = 0x2713,
    Login = 0xE740,
    Trash = 0xE729,

    _,
};

fn icon(nvg: NanoVg, x: f32, y: f32, icon_id: Icon) f32 {
    var buf: [8]u8 = undefined;
    nvg.fontFace("icons");
    return nvg.text(x, y, encodeIcon(icon_id, &buf));
}

fn iconBounds(nvg: NanoVg, x: f32, y: f32, icon_id: Icon, bounds: ?*[4]f32) f32 {
    var buf: [8]u8 = undefined;
    nvg.fontFace("icons");
    return nvg.textBounds(x, y, encodeIcon(icon_id, &buf), bounds);
}

fn encodeIcon(icon_cp: Icon, buf: *[8]u8) []const u8 {
    const len = std.unicode.utf8Encode(@intFromEnum(icon_cp), buf[0..]) catch unreachable;
    buf[len] = 0;
    return buf[0..len];
}

// Controls

fn label(nvg: NanoVg, text: [:0]const u8, x: f32, y: f32, w: f32, h: f32) void {
    _ = w;

    nvg.fontSize(15.0);
    nvg.fontFace("sans");
    nvg.fillColor(NanoVg.rgba(255, 255, 255, 128));

    nvg.textAlign(.{ .horizontal = .left, .vertical = .middle });
    _ = nvg.text(x, y + h * 0.5, text);
}

fn textBox(nvg: NanoVg, text: [:0]const u8, x: f32, y: f32, w: f32, h: f32) void {
    drawEditBox(nvg, x, y, w, h);

    nvg.fontSize(17.0);
    nvg.fontFace("sans");
    nvg.fillColor(NanoVg.rgba(255, 255, 255, 64));
    nvg.textAlign(.{ .horizontal = .left, .vertical = .middle });
    _ = nvg.text(x + h * 0.3, y + h * 0.5, text);
}

// TODO (Matteo): Better naming
fn textBoxNum(nvg: NanoVg, text: [:0]const u8, units: [:0]const u8, x: f32, y: f32, w: f32, h: f32) void {
    drawEditBox(nvg, x, y, w, h);

    const uw = nvg.textBounds(0, 0, units, null);

    nvg.fontSize(15.0);
    nvg.fontFace("sans");
    nvg.fillColor(NanoVg.rgba(255, 255, 255, 64));
    nvg.textAlign(.{ .horizontal = .right, .vertical = .middle });
    _ = nvg.text(x + w - h * 0.3, y + h * 0.5, units);

    nvg.fontSize(17.0);
    nvg.fontFace("sans");
    nvg.fillColor(NanoVg.rgba(255, 255, 255, 128));
    nvg.textAlign(.{ .horizontal = .right, .vertical = .middle });
    _ = nvg.text(x + w - uw - h * 0.5, y + h * 0.5, text);
}

fn drawEditBox(nvg: NanoVg, x: f32, y: f32, w: f32, h: f32) void {
    // Edit
    const bg = nvg.boxGradient(x + 1, y + 1 + 1.5, w - 2, h - 2, 3, 4, NanoVg.rgba(255, 255, 255, 32), NanoVg.rgba(32, 32, 32, 32));
    nvg.beginPath();
    nvg.roundedRect(x + 1, y + 1, w - 2, h - 2, 4 - 1);
    nvg.fillPaint(bg);
    nvg.fill();

    nvg.beginPath();
    nvg.roundedRect(x + 0.5, y + 0.5, w - 1, h - 1, 4 - 0.5);
    nvg.strokeColor(NanoVg.rgba(0, 0, 0, 48));
    nvg.stroke();
}

fn checkBox(nvg: NanoVg, text: [:0]const u8, x: f32, y: f32, w: f32, h: f32) void {
    _ = w;

    nvg.fontSize(15.0);
    nvg.fontFace("sans");
    nvg.fillColor(NanoVg.rgba(255, 255, 255, 160));

    nvg.textAlign(.{ .horizontal = .left, .vertical = .middle });
    _ = nvg.text(x + 28, y + h * 0.5, text);

    const bg = nvg.boxGradient(x + 1, y + @round(h * 0.5) - 9 + 1, 18, 18, 3, 3, NanoVg.rgba(0, 0, 0, 32), NanoVg.rgba(0, 0, 0, 92));
    nvg.beginPath();
    nvg.roundedRect(x + 1, y + @round(h * 0.5) - 9, 18, 18, 3);
    nvg.fillPaint(bg);
    nvg.fill();

    nvg.fontSize(33);
    nvg.fillColor(NanoVg.rgba(255, 255, 255, 128));
    nvg.textAlign(.{ .horizontal = .center, .vertical = .middle });
    _ = icon(nvg, x + 9 + 2, y + h * 0.5, .Check);
}

const ButtonState = enum { Idle, Hovered, Pressed };

fn button(
    nvg: NanoVg,
    preicon: Icon,
    text: [:0]const u8,
    bounds: Rect,
    col: NanoVg.Color,
    m: Mouse,
) ButtonState {
    const state = testButton(bounds, m);
    drawButton(nvg, preicon, text, bounds, col, state);
    return state;
}

fn testButton(bounds: Rect, mouse: Mouse) ButtonState {
    if (!bounds.contains(mouse.pos)) return .Idle;
    if (mouse.button.left) return .Pressed;
    return .Hovered;
}

fn drawButton(
    nvg: NanoVg,
    preicon: Icon,
    text: [:0]const u8,
    bounds: Rect,
    col: NanoVg.Color,
    state: ButtonState,
) void {
    const cornerRadius = 4.0;
    var iw: f32 = 0;
    var r: Rect = undefined;

    const h = bounds.size.y;
    const cen = bounds.center();
    const black = (col.r == 0 and col.g == 0 and col.b == 0 and col.a == 0);
    const alpha: u8 = if (black) 16 else 32;
    const bg = nvg.linearGradient(
        bounds.origin.x,
        bounds.origin.y,
        bounds.origin.x,
        bounds.origin.y + h,
        NanoVg.rgba(255, 255, 255, alpha),
        NanoVg.rgba(0, 0, 0, alpha),
    );
    r = bounds.offset(-2);
    nvg.beginPath();
    nvg.roundedRect(r.origin.x, r.origin.y, r.size.x, r.size.y, cornerRadius - 1.0);

    if (!black) {
        switch (state) {
            .Pressed => {
                var dark = col;
                dark.r = math.clamp(dark.r * 0.8, 0, 1);
                dark.g = math.clamp(dark.g * 0.8, 0, 1);
                dark.b = math.clamp(dark.b * 0.8, 0, 1);
                nvg.fillColor(dark);
            },
            .Hovered => {
                var light = col;
                light.r = math.clamp(light.r * 1.2, 0, 1);
                light.g = math.clamp(light.g * 1.2, 0, 1);
                light.b = math.clamp(light.b * 1.2, 0, 1);
                nvg.fillColor(light);
            },
            else => nvg.fillColor(col),
        }
        nvg.fill();
    }
    nvg.fillPaint(bg);
    nvg.fill();

    r = bounds.offset(-1);
    nvg.beginPath();
    nvg.roundedRect(r.origin.x, r.origin.y, r.size.x, r.size.y, cornerRadius - 0.5);
    nvg.strokeColor(NanoVg.rgba(0, 0, 0, 48));
    nvg.stroke();

    nvg.fontSize(17.0);
    nvg.fontFace("sans-bold");
    const tw = nvg.textBounds(0, 0, text, null);
    if (preicon != .None) {
        nvg.fontSize(h * 1.3);

        iw = iconBounds(nvg, 0, 0, preicon, null);
        iw += h * 0.15;

        nvg.fillColor(NanoVg.rgba(255, 255, 255, 96));
        nvg.textAlign(.{ .horizontal = .left, .vertical = .middle });
        _ = icon(nvg, cen.x - tw * 0.5 - iw * 0.75, cen.y, preicon);
    }

    nvg.fontSize(17.0);
    nvg.fontFace("sans-bold");
    nvg.textAlign(.{ .horizontal = .left, .vertical = .middle });
    nvg.fillColor(NanoVg.rgba(0, 0, 0, 160));
    _ = nvg.text(cen.x - tw * 0.5 + iw * 0.25, cen.y - 1, text);
    nvg.fillColor(NanoVg.rgba(255, 255, 255, 160));
    _ = nvg.text(cen.x - tw * 0.5 + iw * 0.25, cen.y, text);
}

fn slider(nvg: NanoVg, pos: f32, bounds: Rect) void {
    const w = bounds.size.x;
    const h = bounds.size.y;
    const cx = bounds.origin.x + @round(pos * w);
    const cy = bounds.origin.y + @round(h * 0.5);
    const kr = @round(h * 0.25);

    nvg.save();
    nvg.restore();

    // Slot
    var bg = nvg.boxGradient(
        bounds.origin.x,
        cy - 2 + 1,
        w,
        4,
        2,
        2,
        NanoVg.rgba(0, 0, 0, 32),
        NanoVg.rgba(0, 0, 0, 128),
    );
    nvg.beginPath();
    nvg.roundedRect(bounds.origin.x, cy - 2, w, 4, 2);
    nvg.fillPaint(bg);
    nvg.fill();

    // Knob Shadow
    bg = nvg.radialGradient(
        cx,
        cy + 1,
        kr - 3,
        kr + 3,
        NanoVg.rgba(0, 0, 0, 64),
        NanoVg.rgba(0, 0, 0, 0),
    );
    nvg.beginPath();
    nvg.rect(cx - kr - 5, cy - kr - 5, kr * 2 + 5 + 5, kr * 2 + 5 + 5 + 3);
    nvg.circle(cx, cy, kr);
    nvg.pathWinding(NanoVg.Winding.solidity(.hole));
    nvg.fillPaint(bg);
    nvg.fill();

    // Knob
    const knob = nvg.linearGradient(
        bounds.origin.x,
        cy - kr,
        bounds.origin.x,
        cy + kr,
        NanoVg.rgba(255, 255, 255, 16),
        NanoVg.rgba(0, 0, 0, 16),
    );
    nvg.beginPath();
    nvg.circle(cx, cy, kr - 1);
    nvg.fillColor(NanoVg.rgba(40, 43, 48, 255));
    nvg.fill();
    nvg.fillPaint(knob);
    nvg.fill();

    nvg.beginPath();
    nvg.circle(cx, cy, kr - 0.5);
    nvg.strokeColor(NanoVg.rgba(0, 0, 0, 92));
    nvg.stroke();
}

fn colorPicker(nvg: NanoVg, x: f32, y: f32, w: f32, h: f32, t: f32) void {
    const hue = @sin(t * 0.12);
    var paint: NanoVg.Paint = undefined;

    nvg.save();
    nvg.restore();

    const cx = x + w * 0.5;
    const cy = y + h * 0.5;
    const r1 = (if (w < h) w else h) * 0.5 - 5.0;
    const r0 = r1 - 20.0;
    const aeps = 0.5 / r1; // half a pixel arc length in radians (2pi cancels out).

    var i: f32 = 0;
    while (i < 6) : (i += 1) {
        const a0 = i / 6.0 * math.pi * 2.0 - aeps;
        const a1 = (i + 1.0) / 6.0 * math.pi * 2.0 + aeps;
        nvg.beginPath();
        nvg.arc(cx, cy, r0, a0, a1, .cw);
        nvg.arc(cx, cy, r1, a1, a0, .ccw);
        nvg.closePath();
        const ax = cx + @cos(a0) * (r0 + r1) * 0.5;
        const ay = cy + @sin(a0) * (r0 + r1) * 0.5;
        const bx = cx + @cos(a1) * (r0 + r1) * 0.5;
        const by = cy + @sin(a1) * (r0 + r1) * 0.5;
        paint = nvg.linearGradient(ax, ay, bx, by, NanoVg.hsla(a0 / (math.pi * 2.0), 1.0, 0.55, 255), NanoVg.hsla(a1 / (math.pi * 2.0), 1.0, 0.55, 255));
        nvg.fillPaint(paint);
        nvg.fill();
    }

    nvg.beginPath();
    nvg.circle(cx, cy, r0 - 0.5);
    nvg.circle(cx, cy, r1 + 0.5);
    nvg.strokeColor(NanoVg.rgba(0, 0, 0, 64));
    nvg.strokeWidth(1.0);
    nvg.stroke();

    // Selector
    nvg.save();
    nvg.translate(cx, cy);
    nvg.rotate(hue * math.pi * 2);

    // Marker on
    nvg.strokeWidth(2.0);
    nvg.beginPath();
    nvg.rect(r0 - 1, -3, r1 - r0 + 2, 6);
    nvg.strokeColor(NanoVg.rgba(255, 255, 255, 192));
    nvg.stroke();

    paint = nvg.boxGradient(r0 - 3, -5, r1 - r0 + 6, 10, 2, 4, NanoVg.rgba(0, 0, 0, 128), NanoVg.rgba(0, 0, 0, 0));
    nvg.beginPath();
    nvg.rect(r0 - 2 - 10, -4 - 10, r1 - r0 + 4 + 20, 8 + 20);
    nvg.rect(r0 - 2, -4, r1 - r0 + 4, 8);
    nvg.pathWinding(NanoVg.Winding.solidity(.hole));
    nvg.fillPaint(paint);
    nvg.fill();

    // Center triangle
    const r = r0 - 6;
    var ax = -0.5 * r; // @cos(120.0 / 180.0 * math.pi) * r;
    var ay = 0.86602540378 * r; // @sin(120.0 / 180.0 * math.pi) * r;
    const bx = -0.5 * r; // @cos(-120.0 / 180.0 * math.pi) * r;
    const by = -0.86602540378 * r; // @sin(-120.0 / 180.0 * math.pi) * r;
    nvg.beginPath();
    nvg.moveTo(r, 0);
    nvg.lineTo(ax, ay);
    nvg.lineTo(bx, by);
    nvg.closePath();
    paint = nvg.linearGradient(r, 0, ax, ay, NanoVg.hsla(hue, 1.0, 0.5, 255), NanoVg.rgba(255, 255, 255, 255));
    nvg.fillPaint(paint);
    nvg.fill();
    paint = nvg.linearGradient((r + ax) * 0.5, (0 + ay) * 0.5, bx, by, NanoVg.rgba(0, 0, 0, 0), NanoVg.rgba(0, 0, 0, 255));
    nvg.fillPaint(paint);
    nvg.fill();
    nvg.strokeColor(NanoVg.rgba(0, 0, 0, 64));
    nvg.stroke();

    // Select circle on triangle
    ax = -0.5 * r * 0.3; // @cos(120.0 / 180.0 * math.pi) * r * 0.3;
    ay = 0.86602540378 * r * 0.4; // @sin(120.0 / 180.0 * math.pi) * r * 0.4;
    nvg.strokeWidth(2.0);
    nvg.beginPath();
    nvg.circle(ax, ay, 5);
    nvg.strokeColor(NanoVg.rgba(255, 255, 255, 192));
    nvg.stroke();

    paint = nvg.radialGradient(ax, ay, 7, 9, NanoVg.rgba(0, 0, 0, 64), NanoVg.rgba(0, 0, 0, 0));
    nvg.beginPath();
    nvg.rect(ax - 20, ay - 20, 40, 40);
    nvg.circle(ax, ay, 7);
    nvg.pathWinding(NanoVg.Winding.solidity(.hole));
    nvg.fillPaint(paint);
    nvg.fill();

    nvg.restore();
}

fn drawWindow(nvg: NanoVg, title: [:0]const u8, x: f32, y: f32, w: f32, h: f32) void {
    const cornerRadius = 3;
    var shadowPaint: NanoVg.Paint = undefined;
    var headerPaint: NanoVg.Paint = undefined;

    nvg.save();

    // Window
    nvg.beginPath();
    nvg.roundedRect(x, y, w, h, cornerRadius);
    nvg.fillColor(NanoVg.rgba(28, 30, 34, 192));
    nvg.fill();

    // Drop shadow
    shadowPaint = nvg.boxGradient(x, y + 2, w, h, cornerRadius * 2, 10, NanoVg.rgba(0, 0, 0, 128), NanoVg.rgba(0, 0, 0, 0));
    nvg.beginPath();
    nvg.rect(x - 10, y - 10, w + 20, h + 30);
    nvg.roundedRect(x, y, w, h, cornerRadius);
    nvg.pathWinding(NanoVg.Winding.solidity(.hole));
    nvg.fillPaint(shadowPaint);
    nvg.fill();

    // Header
    headerPaint = nvg.linearGradient(x, y, x, y + 15, NanoVg.rgba(255, 255, 255, 8), NanoVg.rgba(0, 0, 0, 16));
    nvg.beginPath();
    nvg.roundedRect(x + 1, y + 1, w - 2, 30, cornerRadius - 1);
    nvg.fillPaint(headerPaint);
    nvg.fill();
    nvg.beginPath();
    nvg.moveTo(x + 0.5, y + 0.5 + 30);
    nvg.lineTo(x + 0.5 + w - 1, y + 0.5 + 30);
    nvg.strokeColor(NanoVg.rgba(0, 0, 0, 32));
    nvg.stroke();

    nvg.fontSize(15.0);
    nvg.fontFace("sans-bold");
    nvg.textAlign(.{ .horizontal = .center, .vertical = .middle });

    nvg.fontBlur(2);
    nvg.fillColor(NanoVg.rgba(0, 0, 0, 128));
    _ = nvg.text(x + w / 2, y + 16 + 1, title);

    nvg.fontBlur(0);
    nvg.fillColor(NanoVg.rgba(220, 220, 220, 160));
    _ = nvg.text(x + w / 2, y + 16, title);

    nvg.restore();
}

fn drawDropDown(nvg: NanoVg, text: [:0]const u8, x: f32, y: f32, w: f32, h: f32) void {
    const cornerRadius = 4.0;

    const bg = nvg.linearGradient(x, y, x, y + h, NanoVg.rgba(255, 255, 255, 16), NanoVg.rgba(0, 0, 0, 16));
    nvg.beginPath();
    nvg.roundedRect(x + 1, y + 1, w - 2, h - 2, cornerRadius - 1.0);
    nvg.fillPaint(bg);
    nvg.fill();

    nvg.beginPath();
    nvg.roundedRect(x + 0.5, y + 0.5, w - 1, h - 1, cornerRadius - 0.5);
    nvg.strokeColor(NanoVg.rgba(0, 0, 0, 48));
    nvg.stroke();

    nvg.fontSize(17.0);
    nvg.fontFace("sans");
    nvg.fillColor(NanoVg.rgba(255, 255, 255, 160));
    nvg.textAlign(.{ .horizontal = .left, .vertical = .middle });
    _ = nvg.text(x + h * 0.3, y + h * 0.5, text);

    nvg.fontSize(h * 1.3);
    nvg.fillColor(NanoVg.rgba(255, 255, 255, 64));
    nvg.textAlign(.{ .horizontal = .center, .vertical = .middle });
    _ = icon(nvg, x + w - h * 0.5, y + h * 0.5, .ChevronRight);
}

fn drawSearchBox(nvg: NanoVg, text: [:0]const u8, x: f32, y: f32, w: f32, h: f32) void {
    const cornerRadius = h / 2 - 1;

    // Edit
    const bg = nvg.boxGradient(x, y + 1.5, w, h, h / 2, 5, NanoVg.rgba(0, 0, 0, 16), NanoVg.rgba(0, 0, 0, 92));
    nvg.beginPath();
    nvg.roundedRect(x, y, w, h, cornerRadius);
    nvg.fillPaint(bg);
    nvg.fill();

    nvg.fontSize(h * 1.3);
    nvg.fontFace("icons");
    nvg.fillColor(NanoVg.rgba(255, 255, 255, 64));
    nvg.textAlign(.{ .horizontal = .center, .vertical = .middle });
    _ = icon(nvg, x + h * 0.55, y + h * 0.55, .Search);

    nvg.fontSize(17.0);
    nvg.fontFace("sans");
    nvg.fillColor(NanoVg.rgba(255, 255, 255, 32));

    nvg.textAlign(.{ .horizontal = .left, .vertical = .middle });
    _ = nvg.text(x + h * 1.05, y + h * 0.5, text);

    nvg.fontSize(h * 1.3);
    nvg.fillColor(NanoVg.rgba(255, 255, 255, 32));
    nvg.textAlign(.{ .horizontal = .center, .vertical = .middle });
    _ = icon(nvg, x + w - h * 0.55, y + h * 0.55, .CircledCross);
}

fn drawEyes(nvg: NanoVg, x: f32, y: f32, w: f32, h: f32, mx: f32, my: f32, t: f32) void {
    const ex = w * 0.23;
    const ey = h * 0.5;
    const lx = x + ex;
    const ly = y + ey;
    const rx = x + w - ex;
    const ry = y + ey;
    const br = (if (ex < ey) ex else ey) * 0.5;
    const blink = 1 - math.pow(f32, @sin(t * 0.5), 200) * 0.8;

    var bg = nvg.linearGradient(
        x,
        y + h * 0.5,
        x + w * 0.1,
        y + h,
        NanoVg.rgba(0, 0, 0, 32),
        NanoVg.rgba(0, 0, 0, 16),
    );
    nvg.beginPath();
    nvg.ellipse(lx + 3.0, ly + 16.0, ex, ey);
    nvg.ellipse(rx + 3.0, ry + 16.0, ex, ey);
    nvg.fillPaint(bg);
    nvg.fill();

    bg = nvg.linearGradient(
        x,
        y + h * 0.25,
        x + w * 0.1,
        y + h,
        NanoVg.rgba(220, 220, 220, 255),
        NanoVg.rgba(128, 128, 128, 255),
    );
    nvg.beginPath();
    nvg.ellipse(lx, ly, ex, ey);
    nvg.ellipse(rx, ry, ex, ey);
    nvg.fillPaint(bg);
    nvg.fill();

    var dx = (mx - rx) / (ex * 10);
    var dy = (my - ry) / (ey * 10);
    var d = @sqrt(dx * dx + dy * dy);
    if (d > 1.0) {
        dx /= d;
        dy /= d;
    }
    dx *= ex * 0.4;
    dy *= ey * 0.5;
    nvg.beginPath();
    nvg.ellipse(lx + dx, ly + dy + ey * 0.25 * (1 - blink), br, br * blink);
    nvg.fillColor(NanoVg.rgba(32, 32, 32, 255));
    nvg.fill();

    dx = (mx - rx) / (ex * 10);
    dy = (my - ry) / (ey * 10);
    d = @sqrt(dx * dx + dy * dy);
    if (d > 1.0) {
        dx /= d;
        dy /= d;
    }
    dx *= ex * 0.4;
    dy *= ey * 0.5;
    nvg.beginPath();
    nvg.ellipse(rx + dx, ry + dy + ey * 0.25 * (1 - blink), br, br * blink);
    nvg.fillColor(NanoVg.rgba(32, 32, 32, 255));
    nvg.fill();

    var gloss = nvg.radialGradient(lx - ex * 0.25, ly - ey * 0.5, ex * 0.1, ex * 0.75, NanoVg.rgba(255, 255, 255, 128), NanoVg.rgba(255, 255, 255, 0));
    nvg.beginPath();
    nvg.ellipse(lx, ly, ex, ey);
    nvg.fillPaint(gloss);
    nvg.fill();

    gloss = nvg.radialGradient(rx - ex * 0.25, ry - ey * 0.5, ex * 0.1, ex * 0.75, NanoVg.rgba(255, 255, 255, 128), NanoVg.rgba(255, 255, 255, 0));
    nvg.beginPath();
    nvg.ellipse(rx, ry, ex, ey);
    nvg.fillPaint(gloss);
    nvg.fill();
}

fn drawParagraph(nvg: NanoVg, x_arg: f32, y_arg: f32, width: f32, height: f32, mx: f32, my: f32) void {
    var x = x_arg;
    var y = y_arg;
    _ = height;
    var rows: [3]NanoVg.TextRow = undefined;
    var glyphs: [100]NanoVg.GlyphPosition = undefined;
    var text = "This is longer chunk of text.\n  \n  Would have used lorem ipsum but she    was busy jumping over the lazy dog with the fox and all the men who came to the aid of the party.🎉";
    var start: []const u8 = undefined;
    var lnum: i32 = 0;
    var px: f32 = undefined;
    var bounds: [4]f32 = undefined;
    const hoverText = "Hover your mouse over the text to see calculated caret position.";
    var gx: f32 = undefined;
    var gy: f32 = undefined;
    var gutter: i32 = 0;

    nvg.save();

    nvg.fontSize(15.0);
    nvg.fontFace("sans");
    nvg.textAlign(.{ .vertical = .top });
    var lineh: f32 = undefined;
    nvg.textMetrics(null, null, &lineh);

    // The text break API can be used to fill a large buffer of rows,
    // or to iterate over the text just few lines (or just one) at a time.
    // The "next" variable of the last returned item tells where to continue.
    start = text;
    var nrows = nvg.textBreakLines(start, width, &rows);
    while (nrows != 0) : (nrows = nvg.textBreakLines(start, width, &rows)) {
        var i: u32 = 0;
        while (i < nrows) : (i += 1) {
            const row = &rows[i];
            const hit = mx > x and mx < (x + width) and my >= y and my < (y + lineh);

            nvg.beginPath();
            nvg.fillColor(NanoVg.rgba(255, 255, 255, if (hit) 64 else 16));
            nvg.rect(x + row.minx, y, row.maxx - row.minx, lineh);
            nvg.fill();

            nvg.fillColor(NanoVg.rgba(255, 255, 255, 255));
            _ = nvg.text(x, y, row.text);

            if (hit) {
                var caretx = if (mx < x + row.width / 2) x else x + row.width;
                px = x;
                const nglyphs = nvg.textGlyphPositions(x, y, row.text, &glyphs);
                for (glyphs[0..nglyphs], 0..) |glyph, j| {
                    const x0 = glyph.x;
                    const x1 = if (j + 1 < nglyphs) glyphs[j + 1].x else x + row.width;
                    gx = x0 * 0.3 + x1 * 0.7;
                    if (mx >= px and mx < gx)
                        caretx = glyph.x;
                    px = gx;
                }
                nvg.beginPath();
                nvg.fillColor(NanoVg.rgba(255, 192, 0, 255));
                nvg.rect(caretx, y, 1, lineh);
                nvg.fill();

                gutter = lnum + 1;
                gx = x - 10;
                gy = y + lineh / 2;
            }
            lnum += 1;
            y += lineh;
        }
        // Keep going...
        start = rows[nrows - 1].next;
    }

    if (gutter != 0) {
        var buf: [16]u8 = undefined;
        const txt = std.fmt.bufPrint(&buf, "{}", .{gutter}) catch unreachable;
        nvg.fontSize(12.0);
        nvg.textAlign(.{ .horizontal = .right, .vertical = .middle });

        _ = nvg.textBounds(gx, gy, txt, &bounds);

        nvg.beginPath();
        nvg.fillColor(NanoVg.rgba(255, 192, 0, 255));
        nvg.roundedRect(@round(bounds[0] - 4), @round(bounds[1] - 2), @round(bounds[2] - bounds[0]) + 8, @round(bounds[3] - bounds[1]) + 4, (@round(bounds[3] - bounds[1]) + 4) / 2 - 1);
        nvg.fill();

        nvg.fillColor(NanoVg.rgba(32, 32, 32, 255));
        _ = nvg.text(gx, gy, txt);
    }

    y += 20.0;

    nvg.fontSize(11.0);
    nvg.textAlign(.{ .vertical = .top });
    nvg.textLineHeight(1.2);

    _ = nvg.textBoxBounds(x, y, 150, hoverText, &bounds);

    // Fade the tooltip out when close to it.
    gx = math.clamp(mx, bounds[0], bounds[2]) - mx;
    gy = math.clamp(my, bounds[1], bounds[3]) - my;
    const a = math.clamp(@sqrt(gx * gx + gy * gy) / 30.0, 0, 1);
    nvg.globalAlpha(a);

    nvg.beginPath();
    nvg.fillColor(NanoVg.rgba(220, 220, 220, 255));
    nvg.roundedRect(bounds[0] - 2, bounds[1] - 2, @round(bounds[2] - bounds[0]) + 4, @round(bounds[3] - bounds[1]) + 4, 3);
    px = @round((bounds[2] + bounds[0]) / 2);
    nvg.moveTo(px, bounds[1] - 10);
    nvg.lineTo(px + 7, bounds[1] + 1);
    nvg.lineTo(px - 7, bounds[1] + 1);
    nvg.fill();

    nvg.fillColor(NanoVg.rgba(0, 0, 0, 220));
    nvg.textBox(x, y, 150, hoverText);

    nvg.restore();
}

fn drawGraph(nvg: NanoVg, x: f32, y: f32, w: f32, h: f32, t: f32) void {
    const dx = w / 5.0;

    const samples = [_]f32{
        (1 + @sin(t * 1.2345 + @cos(t * 0.33457) * 0.44)) * 0.5,
        (1 + @sin(t * 0.68363 + @cos(t * 1.3) * 1.55)) * 0.5,
        (1 + @sin(t * 1.1642 + @cos(t * 0.33457) * 1.24)) * 0.5,
        (1 + @sin(t * 0.56345 + @cos(t * 1.63) * 0.14)) * 0.5,
        (1 + @sin(t * 1.6245 + @cos(t * 0.254) * 0.3)) * 0.5,
        (1 + @sin(t * 0.345 + @cos(t * 0.03) * 0.6)) * 0.5,
    };

    var sx: [6]f32 = undefined;
    var sy: [6]f32 = undefined;
    for (samples, 0..) |sample, i| {
        sx[i] = x + @as(f32, @floatFromInt(i)) * dx;
        sy[i] = y + h * sample * 0.8;
    }

    // Graph background
    var bg = nvg.linearGradient(x, y, x, y + h, NanoVg.rgba(0, 160, 192, 0), NanoVg.rgba(0, 160, 192, 64));
    nvg.beginPath();
    nvg.moveTo(sx[0], sy[0]);
    var i: u32 = 1;
    while (i < 6) : (i += 1)
        nvg.bezierTo(sx[i - 1] + dx * 0.5, sy[i - 1], sx[i] - dx * 0.5, sy[i], sx[i], sy[i]);
    nvg.lineTo(x + w, y + h);
    nvg.lineTo(x, y + h);
    nvg.fillPaint(bg);
    nvg.fill();

    // Graph line
    nvg.beginPath();
    nvg.moveTo(sx[0], sy[0] + 2);
    i = 1;
    while (i < 6) : (i += 1)
        nvg.bezierTo(sx[i - 1] + dx * 0.5, sy[i - 1] + 2, sx[i] - dx * 0.5, sy[i] + 2, sx[i], sy[i] + 2);
    nvg.strokeColor(NanoVg.rgba(0, 0, 0, 32));
    nvg.strokeWidth(3.0);
    nvg.stroke();

    nvg.beginPath();
    nvg.moveTo(sx[0], sy[0]);

    i = 1;
    while (i < 6) : (i += 1)
        nvg.bezierTo(sx[i - 1] + dx * 0.5, sy[i - 1], sx[i] - dx * 0.5, sy[i], sx[i], sy[i]);
    nvg.strokeColor(NanoVg.rgba(0, 160, 192, 255));
    nvg.strokeWidth(3.0);
    nvg.stroke();

    // Graph sample pos
    i = 0;
    while (i < 6) : (i += 1) {
        bg = nvg.radialGradient(sx[i], sy[i] + 2, 3.0, 8.0, NanoVg.rgba(0, 0, 0, 32), NanoVg.rgba(0, 0, 0, 0));
        nvg.beginPath();
        nvg.rect(sx[i] - 10, sy[i] - 10 + 2, 20, 20);
        nvg.fillPaint(bg);
        nvg.fill();
    }

    nvg.beginPath();
    i = 0;
    while (i < 6) : (i += 1)
        nvg.circle(sx[i], sy[i], 4.0);
    nvg.fillColor(NanoVg.rgba(0, 160, 192, 255));
    nvg.fill();
    nvg.beginPath();
    i = 0;
    while (i < 6) : (i += 1)
        nvg.circle(sx[i], sy[i], 2.0);
    nvg.fillColor(NanoVg.rgba(220, 220, 220, 255));
    nvg.fill();

    nvg.strokeWidth(1.0);
}

fn drawSpinner(nvg: NanoVg, cx: f32, cy: f32, r: f32, t: f32) void {
    const a0 = 0.0 + t * 6;
    const a1 = math.pi + t * 6;
    const r0 = r;
    const r1 = r * 0.75;

    nvg.save();

    nvg.beginPath();
    nvg.arc(cx, cy, r0, a0, a1, .cw);
    nvg.arc(cx, cy, r1, a1, a0, .ccw);
    nvg.closePath();
    const ax = cx + @cos(a0) * (r0 + r1) * 0.5;
    const ay = cy + @sin(a0) * (r0 + r1) * 0.5;
    const bx = cx + @cos(a1) * (r0 + r1) * 0.5;
    const by = cy + @sin(a1) * (r0 + r1) * 0.5;
    const paint = nvg.linearGradient(ax, ay, bx, by, NanoVg.rgba(0, 0, 0, 0), NanoVg.rgba(0, 0, 0, 128));
    nvg.fillPaint(paint);
    nvg.fill();

    nvg.restore();
}

fn drawThumbnails(nvg: NanoVg, x: f32, y: f32, w: f32, h: f32, images: []const NanoVg.Image, t: f32) void {
    const cornerRadius = 3.0;
    const thumb = 60.0;
    const arry = 30.5;
    const stackh = @as(f32, @floatFromInt(images.len / 2)) * (thumb + 10.0) + 10.0;
    const u = (1 + @cos(t * 0.5)) * 0.5;
    const uu = (1 - @cos(t * 0.2)) * 0.5;

    nvg.save();

    // Drop shadow
    var shadowPaint = nvg.boxGradient(x, y + 4, w, h, cornerRadius * 2.0, 20, NanoVg.rgba(0, 0, 0, 128), NanoVg.rgba(0, 0, 0, 0));
    nvg.beginPath();
    nvg.rect(x - 10, y - 10, w + 20, h + 30);
    nvg.roundedRect(x, y, w, h, cornerRadius);
    nvg.pathWinding(NanoVg.Winding.solidity(.hole));
    nvg.fillPaint(shadowPaint);
    nvg.fill();

    // Window
    nvg.beginPath();
    nvg.roundedRect(x, y, w, h, cornerRadius);
    nvg.moveTo(x - 10, y + arry);
    nvg.lineTo(x + 1, y + arry - 11);
    nvg.lineTo(x + 1, y + arry + 11);
    nvg.fillColor(NanoVg.rgba(200, 200, 200, 255));
    nvg.fill();

    nvg.save();
    nvg.scissor(x, y, w, h);
    nvg.translate(0, -(stackh - h) * u);

    const dv = 1.0 / @as(f32, @floatFromInt(images.len - 1));

    for (images, 0..) |image, i| {
        var tx = x + 10;
        var ty = y + 10;
        tx += @as(f32, @floatFromInt(i % 2)) * (thumb + 10.0);
        ty += @as(f32, @floatFromInt(i / 2)) * (thumb + 10.0);
        var imgw: i32 = undefined;
        var imgh: i32 = undefined;
        nvg.imageSize(image, &imgw, &imgh);
        var ix: f32 = undefined;
        var iy: f32 = undefined;
        var iw: f32 = undefined;
        var ih: f32 = undefined;
        if (imgw < imgh) {
            iw = thumb;
            ih = iw * @as(f32, @floatFromInt(imgh)) / @as(f32, @floatFromInt(imgw));
            ix = 0;
            iy = -(ih - thumb) * 0.5;
        } else {
            ih = thumb;
            iw = ih * @as(f32, @floatFromInt(imgw)) / @as(f32, @floatFromInt(imgh));
            ix = -(iw - thumb) * 0.5;
            iy = 0;
        }

        const v = @as(f32, @floatFromInt(i)) * dv;
        const a = math.clamp((uu - v) / dv, 0, 1);

        if (a < 1.0) {
            drawSpinner(nvg, tx + thumb / 2.0, ty + thumb / 2.0, thumb * 0.25, t);
        }

        const imgPaint = nvg.imagePattern(tx + ix, ty + iy, iw, ih, 0.0 / 180.0 * math.pi, image, a);
        nvg.beginPath();
        nvg.roundedRect(tx, ty, thumb, thumb, 5);
        nvg.fillPaint(imgPaint);
        nvg.fill();

        shadowPaint = nvg.boxGradient(tx - 1, ty, thumb + 2.0, thumb + 2.0, 5, 3, NanoVg.rgba(0, 0, 0, 128), NanoVg.rgba(0, 0, 0, 0));
        nvg.beginPath();
        nvg.rect(tx - 5, ty - 5, thumb + 10.0, thumb + 10.0);
        nvg.roundedRect(tx, ty, thumb, thumb, 6);
        nvg.pathWinding(NanoVg.Winding.solidity(.hole));
        nvg.fillPaint(shadowPaint);
        nvg.fill();

        nvg.beginPath();
        nvg.roundedRect(tx + 0.5, ty + 0.5, thumb - 1.0, thumb - 1.0, 4 - 0.5);
        nvg.strokeWidth(1.0);
        nvg.strokeColor(NanoVg.rgba(255, 255, 255, 192));
        nvg.stroke();
    }
    nvg.restore();

    // Hide fades
    var fadePaint = nvg.linearGradient(x, y, x, y + 6, NanoVg.rgba(200, 200, 200, 255), NanoVg.rgba(200, 200, 200, 0));
    nvg.beginPath();
    nvg.rect(x + 4, y, w - 8, 6);
    nvg.fillPaint(fadePaint);
    nvg.fill();

    fadePaint = nvg.linearGradient(x, y + h, x, y + h - 6, NanoVg.rgba(200, 200, 200, 255), NanoVg.rgba(200, 200, 200, 0));
    nvg.beginPath();
    nvg.rect(x + 4, y + h - 6, w - 8, 6);
    nvg.fillPaint(fadePaint);
    nvg.fill();

    // Scroll bar
    shadowPaint = nvg.boxGradient(x + w - 12 + 1, y + 4 + 1, 8, h - 8, 3, 4, NanoVg.rgba(0, 0, 0, 32), NanoVg.rgba(0, 0, 0, 92));
    nvg.beginPath();
    nvg.roundedRect(x + w - 12, y + 4, 8, h - 8, 3);
    nvg.fillPaint(shadowPaint);
    nvg.fill();

    const scrollh = (h / stackh) * (h - 8);
    shadowPaint = nvg.boxGradient(x + w - 12 - 1, y + 4 + (h - 8 - scrollh) * u - 1, 8, scrollh, 3, 4, NanoVg.rgba(220, 220, 220, 255), NanoVg.rgba(128, 128, 128, 255));
    nvg.beginPath();
    nvg.roundedRect(x + w - 12 + 1, y + 4 + 1 + (h - 8 - scrollh) * u, 8 - 2, scrollh - 2, 2);
    nvg.fillPaint(shadowPaint);
    nvg.fill();

    nvg.restore();
}

fn drawLines(nvg: NanoVg, x: f32, y: f32, w: f32, h: f32, t: f32) void {
    _ = h;
    const pad = 5.0;
    const s = w / 9.0 - pad * 2.0;
    const joins = [_]NanoVg.LineJoin{ .miter, .round, .bevel };
    const caps = [_]NanoVg.LineCap{ .butt, .round, .square };
    const pts = [_]f32{
        -s * 0.25 + @cos(t * 0.3) * s * 0.5, @sin(t * 0.3) * s * 0.5,
        -s * 0.25,                           0,
        s * 0.25,                            0,
        s * 0.25 + @cos(-t * 0.3) * s * 0.5, @sin(-t * 0.3) * s * 0.5,
    };

    nvg.save();
    defer nvg.restore();

    for (caps, 0..) |cap, i| {
        for (joins, 0..) |join, j| {
            const fx = x + s * 0.5 + (@as(f32, @floatFromInt(i)) * 3 + @as(f32, @floatFromInt(j))) / 9.0 * w + pad;
            const fy = y - s * 0.5 + pad;

            nvg.lineCap(cap);
            nvg.lineJoin(join);

            nvg.strokeWidth(s * 0.3);
            nvg.strokeColor(NanoVg.rgba(0, 0, 0, 160));
            nvg.beginPath();
            nvg.moveTo(fx + pts[0], fy + pts[1]);
            nvg.lineTo(fx + pts[2], fy + pts[3]);
            nvg.lineTo(fx + pts[4], fy + pts[5]);
            nvg.lineTo(fx + pts[6], fy + pts[7]);
            nvg.stroke();

            nvg.lineCap(.butt);
            nvg.lineJoin(.bevel);

            nvg.strokeWidth(1.0);
            nvg.strokeColor(NanoVg.rgba(0, 192, 255, 255));
            nvg.beginPath();
            nvg.moveTo(fx + pts[0], fy + pts[1]);
            nvg.lineTo(fx + pts[2], fy + pts[3]);
            nvg.lineTo(fx + pts[4], fy + pts[5]);
            nvg.lineTo(fx + pts[6], fy + pts[7]);
            nvg.stroke();
        }
    }
}

fn drawWidths(nvg: NanoVg, x: f32, y0: f32, width: f32) void {
    nvg.save();
    defer nvg.restore();

    nvg.strokeColor(NanoVg.rgba(0, 0, 0, 255));

    var y = y0;
    var i: usize = 0;
    while (i < 20) : (i += 1) {
        const w = (@as(f32, @floatFromInt(i)) + 0.5) * 0.1;
        nvg.strokeWidth(w);
        nvg.beginPath();
        nvg.moveTo(x, y);
        nvg.lineTo(x + width, y + width * 0.3);
        nvg.stroke();
        y += 10;
    }
}

fn drawCaps(nvg: NanoVg, x: f32, y: f32, width: f32) void {
    const caps = [_]NanoVg.LineCap{ .butt, .round, .square };
    const lineWidth = 8.0;

    nvg.save();
    defer nvg.restore();

    nvg.beginPath();
    nvg.rect(x - lineWidth / 2.0, y, width + lineWidth, 40);
    nvg.fillColor(NanoVg.rgba(255, 255, 255, 32));
    nvg.fill();

    nvg.beginPath();
    nvg.rect(x, y, width, 40);
    nvg.fillColor(NanoVg.rgba(255, 255, 255, 32));
    nvg.fill();

    nvg.strokeWidth(lineWidth);
    for (caps, 0..) |cap, i| {
        nvg.lineCap(cap);
        nvg.strokeColor(NanoVg.rgba(0, 0, 0, 255));
        nvg.beginPath();
        nvg.moveTo(x, y + @as(f32, @floatFromInt(i)) * 10 + 5);
        nvg.lineTo(x + width, y + @as(f32, @floatFromInt(i)) * 10 + 5);
        nvg.stroke();
    }
}

fn drawScissor(nvg: NanoVg, x: f32, y: f32, t: f32) void {
    nvg.save();
    defer nvg.restore();

    // Draw first rect and set scissor to it's area.
    nvg.translate(x, y);
    nvg.rotate(NanoVg.degToRad(5));
    nvg.beginPath();
    nvg.rect(-20, -20, 60, 40);
    nvg.fillColor(NanoVg.rgba(255, 0, 0, 255));
    nvg.fill();
    nvg.scissor(-20, -20, 60, 40);

    // Draw second rectangle with offset and rotation.
    nvg.translate(40, 0);
    nvg.rotate(t);

    // Draw the intended second rectangle without any scissoring.
    nvg.save();
    nvg.resetScissor();
    nvg.beginPath();
    nvg.rect(-20, -10, 60, 30);
    nvg.fillColor(NanoVg.rgba(255, 128, 0, 64));
    nvg.fill();
    nvg.restore();

    // Draw second rectangle with combined scissoring.
    nvg.intersectScissor(-20, -10, 60, 30);
    nvg.beginPath();
    nvg.rect(-20, -10, 60, 30);
    nvg.fillColor(NanoVg.rgba(255, 128, 0, 255));
    nvg.fill();
}
