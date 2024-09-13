const std = @import("std");
const assert = std.debug.assert;

const math = @import("../math.zig");
const Vec2 = math.Vec2(f32);
const Rect = math.AlignedBox2(f32);

const c = @cImport({
    @cDefine("LAY_FLOAT", "1");
    @cInclude("layout.h");
});

comptime {
    // Sanity checks - I prefer exposing standard types "as is" instead of aliases
    assert(c.lay_id == u32);
    assert(c.lay_scalar == f32);
    assert(@sizeOf(c.lay_vec2) == @sizeOf([2]f32));
    assert(@sizeOf(c.lay_vec4) == @sizeOf([4]f32));
}

pub const Layout = @This();

ctx: c.lay_context,

pub fn init() Layout {
    var self: Layout = undefined;
    c.lay_init_context(&self.ctx);
    return self;
}

pub fn deinit(self: *Layout) void {
    c.lay_destroy_context(&self.ctx);
}

pub fn reserveCapacity(self: *Layout, count: u32) void {
    c.lay_reserve_items_capacity(&self.ctx, count);
}

pub fn reset(self: *Layout) void {
    c.lay_reset_context(&self.ctx);
}

pub fn run(self: *Layout) void {
    c.lay_run_context(&self.ctx);
}

// TODO (Matteo): Is making this a fat pointer a bad idea?
pub const Item = struct {
    id: u32,
    ctx: *c.lay_context,

    pub fn create(layout: *Layout) Item {
        const ctx = &layout.ctx;
        return Item{
            .id = c.lay_item(ctx),
            .ctx = ctx,
        };
    }

    pub fn run(self: Item) void {
        c.lay_run_item(self.ctx, self.id);
    }

    // TODO (Matteo): Size operations
    // lay_get_size
    // lay_get_size_xy
    // lay_set_size
    // lay_set_size_xy

    pub fn getSize(self: Item) Vec2 {
        return c.lay_get_size(self.ctx, self.id);
    }

    pub fn getRect(self: Item) Rect {
        const rect = c.lay_get_rect(self.ctx, self.id);
        return math.rect(rect[0], rect[1], rect[2], rect[3]);
    }

    // NOTE (Matteo): I found the nomenclature of the tree manipulation operations confusing:
    // - lay_insert: inserts an item into another item, forming a parent - child relationship
    // - lay_push  : like lay_insert, but puts the new item as the first child in a parent instead of as the last
    // - lay_append: inserts an item as a sibling after another item.
    // So basically lay_insert is a push back/append/LIFO operation, lay_push is a
    // push front/prepend/FIFO operation and lay_append is an actual insertion...

    pub fn addFirst(parent: Item, item: Item) void {
        assert(parent.ctx == item.ctx);
        c.lay_push(parent.ctx, parent.id, item.id);
    }

    pub fn addLast(parent: Item, item: Item) void {
        assert(parent.ctx == item.ctx);
        c.lay_insert(parent.ctx, parent.id, item.id);
    }

    pub fn addNext(prev: Item, item: Item) void {
        c.lay_append(prev.ctx, prev.id, item.id);
    }
};
