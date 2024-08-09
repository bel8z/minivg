const std = @import("std");
const assert = std.debug.assert;

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

// TODO (Matteo): Expose these types?
const Vec2 = c.lay_vec2;
const Vec4 = c.lay_vec4;

pub const Item = struct { id: u32 };

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

pub fn runItem(self: *Layout, item: Item) void {
    c.lay_run_item(&self.ctx, item.id);
}

pub fn createItem(self: *Layout) Item {
    return Item{ .id = c.lay_item(&self.ctx) };
}

// NOTE (Matteo): I found the nomenclature of the tree manipulation operations confusing:
// - lay_insert: inserts an item into another item, forming a parent - child relationship
// - lay_push  : like lay_insert, but puts the new item as the first child in a parent instead of as the last
// - lay_append: inserts an item as a sibling after another item.
// So basically lay_insert is a push back/append/LIFO operation, lay_push is a
// push front/prepend/FIFO operation and lay_append is an actual insertion...

pub fn addFirst(self: *Layout, parent: Item, item: Item) void {
    c.lay_push(&self.ctx, parent, item);
}

pub fn addLast(self: *Layout, parent: Item, item: Item) void {
    c.lay_insert(&self.ctx, parent.id, item.id);
}

pub fn addNext(self: *Layout, prev: Item, item: Item) void {
    c.lay_append(&self.ctx, prev.id, item.id);
}

// TODO (Matteo): Size operations
// lay_get_size
// lay_get_size_xy
// lay_set_size
// lay_set_size_xy

pub fn getRect(self: *Layout, item: Item) [4]f32 {
    return c.lay_get_rect(&self.ctx, item.id);
}
