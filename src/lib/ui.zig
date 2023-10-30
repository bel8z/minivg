const std = @import("std");
const assert = std.debug.assert;

const nvg = @import("nanovg");

const math = @import("math.zig");
const Vec2 = math.Vec2(f32);
const Rect = math.AlignedBox(f32);
const rect = math.rect;

const Ui = @This();

allocator: std.mem.Allocator,
controls: std.MultiArrayList(Control) = .{},
id_stack: std.ArrayListUnmanaged(u64) = .{},
parent_stack: std.ArrayListUnmanaged(u32) = .{},

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

pub const Features = packed struct {
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
    features: Features = .{},

    // Intrusive tree structure
    tree: Node,

    // Layout input
    in_size: math.Vec2(Size), // Requested "semantic" size on both axes

    // Persist data
    key: Key,
    layout: LayoutOutput,
};

const LayoutOutput = struct {
    rel_pos: Vec2, // Position relative to parent
    rect: Rect, // Control rectangle in window coordinates
};

const Key = struct {
    id: u64,
    updated: u64,
};

pub const Output = {};

const Node = struct {
    parent: u32,
    prev_child: u32,
    next_child: u32,
};

pub fn init(allocator: std.mem.Allocator) !Ui {
    var ui = Ui{ .allocator = allocator };

    // NOTE (Matteo): Stacks are fixed in size (256 should be enough) and so are
    // allocated first as persistent memory
    try ui.id_stack.ensureTotalCapacity(allocator, 256);
    try ui.parent_stack.ensureTotalCapacity(allocator, 256);

    // Store dummy root control
    _ = try ui.controls.addOne(allocator);
}

pub fn button(ui: *Ui, label: []const u8) Output {
    const id = ui.getId(label);
    const slot = ui.getControl(id, 0);
    if (slot == 0) unreachable; // TODO (Matteo): Handle out of memory

    var ctrl = ui.controls.get();

    const feats = Features{
        .background = true,
        .border = true,
        .text = true,
        .interact = true,
        .active_animation = true,
    };

    if (!std.meta.eql(ctrl.features, feats)) {
        // TODO (Matteo): Discard input if the features from previous frame differ?
    }

    // TODO (Matteo): Process interaction with pre-computed layout
    var out = Output{};

    // TODO (Matteo): Update layout requirements

    // TODO (Matteo): Update features

    return out;
}

pub fn getId(ui: *Ui, key: anytype) u64 {
    return hash(key, ui.id_stack.getLast());
}

fn getControl(ui: *Ui, id: u64, last_frame: u32) u32 {
    const controls = ui.controls.slice();
    var free_slot: usize = 0;

    // Iterate keys to find a control with the given id, dropping controls that
    // were not updated last frame in the process
    for (controls.items(.key), 0..) |*key, index| {
        if (key.id == id) {
            key.updated = last_frame;
            return index;
        }

        if (key.updated < last_frame) {
            key.updated = 0;
            key.id = 0;
        }

        if (key.id == 0) free_slot = index;
    }

    if (free_slot == 0) {
        free_slot = ui.controls.addOne(ui.allocator) catch return 0;
        ui.controls.set(free_slot, .{ .key = .{ .id = id, .updated = last_frame } });
    }

    return @intCast(free_slot);
}

fn hash(key: anytype, seed: u64) u64 {
    var hasher = std.hash.Wyhash.init(seed);
    std.hash.autoHash(&hasher, key);
    return hasher.final();
}
