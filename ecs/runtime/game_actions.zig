const std = @import("std");
const lua = @import("lua_lib");
const ecs = @import("../root.zig");

const component_prefix = @import("build_options").components_prefix;
const component = ecs.component;
const Component = component.LibComponent;
const ExportLua = ecs.lua.export_component.ExportLua;

const Self = @This();

pub const component_info = Component(component_prefix, Self);
pub const lua_info = ExportLua(
    Self,
    .{
        .name_prefix = component_prefix,
    },
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
