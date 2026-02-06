const ecs = @import("../prelude.zig");

pub const component_info = ecs.Component(@This());

name: []const u8,

pub fn init(with: []const u8) @This() {
    return .{ .name = with };
}
