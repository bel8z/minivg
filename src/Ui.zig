const std = @import("std");
const assert = std.debug.assert;

const nvg = @import("nanovg");

const math = @import("math.zig");
const Vec2 = math.Vec2(f32);
const Rect = math.AlignedBox(f32);
const rect = math.rect;

const Ui = @This();

allocator: std.mem.Allocator,
controls: std.ArrayListUnmanaged(Control) = .{},
active_parent: u32 = root,

const root: u32 = 0;

pub const Size = union(enum) {
    // No requirement (is this useful?)
    Null,

    // Explicit size, with strictness constraint
    Pixels: struct { value: f32, strictness: f32 = 0 },
    Percent: struct { value: f32, strictness: f32 = 0 },

    // Automatic size based on text (e.g. labels), with strictness constraint
    TextContent: struct { strictness: f32 = 0 },

    // Automatic size based on children, with no constraints
    ChildrenSum,
};

pub const ControlOpts = packed struct {
    // Appearance
    border: bool = false,
    text: bool = false,
    background: bool = false,
    shadow: bool = false,
    // Behavior
    clip: bool = false,
    scroll: bool = false,
    interact: bool = false,
    active_animation: bool = false,
};

pub const Control = struct {
    opst: ControlOpts = .{},

    // Intrusive tree structure
    tree: Node,

    // Layout input
    in_size: math.Vec2(Size), // Requested "semantic" size on both axes
    out_rel_pos: Vec2, // Position relative to parent
    out_rect: Rect, // Control rectangle in window coordinates

};

pub const Output = {};

const Node = struct {
    parent: u32,
    prev_child: u32,
    next_child: u32,
};

pub fn init(allocator: std.mem.Allocator) !Ui {
    var ui = Ui{ .allocator = allocator };
    _ = try ui.control_tree.addOne(allocator);
}

fn pushControl(ui: *Ui) !*Control {
    _ = ui;
    error.NotImplemented;
}

fn hash(key: anytype, seed: u64) u64 {
    var hasher = std.hash.Wyhash.init(seed);
    std.hash.autoHash(&hasher, key);
    return hasher.final();
}

fn button(self: *Ui) Output {
    _ = self;
    return .{};
}
