const std = @import("std");
const lua = @import("lua_lib");

const component_prefix = @import("build_options").components_prefix;
const component = @import("../component.zig");
const Component = component.LibComponent;
const ExportLua = component.ExportLua;

const Self = @This();

pub const component_info = Component(component_prefix, Self);
pub const lua_info = ExportLua(
    Self,
    .{},
);

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
