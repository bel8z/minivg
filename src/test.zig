const std = @import("std");

pub const Api = @import("api.zig");
pub const App = Api.App;
pub const math = Api.math;

test {
    std.testing.refAllDecls(@This());
}
