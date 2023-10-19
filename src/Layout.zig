const c = @cImport({
    @cInclude("layout.h");
});

const Layout = @This();

ctx: c.lay_context,

pub fn init() Layout {
    var self: Layout = undefined;
    c.lay_init_context(&self.ctx);
    return self;
}
