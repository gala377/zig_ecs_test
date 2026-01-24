const std = @import("std");
const ecs = @import("../prelude.zig");

const Vec2 = ecs.core.Vec2;
const Component = ecs.Component;
const ExportLua = ecs.ExportLua;

pub const Button = struct {
    pub const component_info = Component(Button);
    pub const lua_info = ExportLua(Button, .{
        .ignored_fields = &.{.title},
    });

    pos: Vec2 = .{ .x = 0.0, .y = 0.0 },
    size: Vec2 = .{ .x = 0.0, .y = 0.0 },
    title: [:0]const u8 = &.{},
    visible: bool = true,
    clicked: bool = false,

    pub fn deinit(self: *Button, allocator: std.mem.Allocator) void {
        allocator.free(self.title);
    }
};
