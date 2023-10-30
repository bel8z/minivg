pub const PerfGraph = @This();

const std = @import("std");
const nvg = @import("nanovg");

pub const RenderStyle = enum {
    fps,
    ms,
    percent,
};

name: []const u8,
values: [100]f32,
head: usize = 0,

pub fn init(name: []const u8) PerfGraph {
    return PerfGraph{
        .name = name,
        .values = std.mem.zeroes([100]f32),
    };
}

pub fn update(self: *PerfGraph, frame_time: f32) void {
    self.head = (self.head + 1) % self.values.len;
    self.values[self.head] = frame_time;
}

pub fn draw(
    self: *PerfGraph,
    vg: nvg,
    x: f32,
    y: f32,
    style: RenderStyle,
) void {
    var buf: [64]u8 = undefined;

    const avg = self.computeAvg();
    const w = 200;
    const h = 35;

    const target_fps = 60;
    const min_ms = 20;
    const max_fps = target_fps + 20;

    vg.beginPath();
    vg.rect(x, y, w, h);
    vg.fillColor(nvg.rgba(0, 0, 0, 128));
    vg.fill();

    vg.beginPath();
    vg.moveTo(x, y + h);

    switch (style) {
        .fps => {
            for (self.values, 0..) |_, i| {
                var v: f32 = 1.0 / (0.00001 + self.values[(self.head + i) % self.values.len]);
                if (v > max_fps) v = max_fps;
                const vx = x + (@as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(self.values.len - 1))) * w;
                const vy = y + h - ((v / max_fps) * h);
                vg.lineTo(vx, vy);
            }
        },
        .percent => {
            for (self.values, 0..) |_, i| {
                var v: f32 = self.values[(self.head + i) % self.values.len] * 1000 * target_fps;
                if (v > 100) v = 100;
                const vx = x + (@as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(self.values.len - 1))) * w;
                const vy = y + h - ((v / 100) * h);
                vg.lineTo(vx, vy);
            }
        },
        .ms => {
            for (self.values, 0..) |_, i| {
                var v: f32 = self.values[(self.head + i) % self.values.len] * 1000;
                if (v > min_ms) v = min_ms;
                const vx = x + (@as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(self.values.len - 1))) * w;
                const vy = y + h - ((v / min_ms) * h);
                vg.lineTo(vx, vy);
            }
        },
    }

    vg.lineTo(x + w, y + h);
    vg.fillColor(nvg.rgba(255, 192, 0, 128));
    vg.fill();

    vg.fontFace("sans");

    if (self.name.len > 0) {
        vg.fontSize(12);
        vg.textAlign(.{ .vertical = .top });
        vg.fillColor(nvg.rgba(240, 240, 240, 192));
        _ = vg.text(x + 3, y + 3, self.name);
    }

    vg.fontSize(15);
    vg.textAlign(.{ .horizontal = .right, .vertical = .top });
    vg.fillColor(nvg.rgba(240, 240, 240, 255));

    switch (style) {
        .fps => {
            var str = std.fmt.bufPrint(&buf, "{d:.2} FPS", .{1 / avg}) catch unreachable;
            _ = vg.text(x + w - 3, y + 3, str);
            vg.fontSize(13);
            vg.textAlign(.{ .horizontal = .right, .vertical = .baseline });
            vg.fillColor(nvg.rgba(240, 240, 240, 160));
            str = std.fmt.bufPrint(&buf, "{d:.3} ms", .{avg * 1000}) catch unreachable;
            _ = vg.text(x + w - 3, y + h - 3, str);
        },
        .percent => {
            var str = std.fmt.bufPrint(&buf, "{d:.1} %", .{avg * 1000 * min_ms}) catch unreachable;
            _ = vg.text(x + w - 3, y + 3, str);
            vg.fontSize(13);
            vg.textAlign(.{ .horizontal = .right, .vertical = .baseline });
            vg.fillColor(nvg.rgba(240, 240, 240, 160));
            str = std.fmt.bufPrint(&buf, "{d:.3} ms", .{avg * 1000}) catch unreachable;
            _ = vg.text(x + w - 3, y + h - 3, str);
        },
        .ms => {
            const str = std.fmt.bufPrint(&buf, "{d:.2} ms", .{avg * 1000}) catch unreachable;
            _ = vg.text(x + w - 3, y + 3, str);
        },
    }
}

fn computeAvg(self: *PerfGraph) f32 {
    var avg: f32 = 0;
    for (self.values) |value| {
        avg += value;
    }
    return avg / @as(f32, @floatFromInt(self.values.len));
}
