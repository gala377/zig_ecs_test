const std = @import("std");
const ecs = @import("../prelude.zig");

const Component = ecs.Component;
const ExportLua = ecs.ExportLua;

const Self = @This();

pub const component_info = Component(Self);
pub const lua_info = ExportLua(Self, .{});

should_close: bool,
log: [][]const u8,

pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
    for (self.log) |log| {
        allocator.free(log);
    }
    if (self.log.len > 0) {
        allocator.free(self.log);
    }
}
