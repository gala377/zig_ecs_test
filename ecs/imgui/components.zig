const std = @import("std");
const component_prefix = @import("build_options").components_prefix;

const Vec2 = @import("../core/core.zig").Vec2;
const ComponentDeinit = @import("../scene.zig").ComponentDeinit;

const Component = @import("../component.zig").LibComponent;
const ExportLua = @import("../component.zig").ExportLua;

pub const Button = struct {
    pub const component_info = Component(component_prefix, Button);
    pub const lua_info = ExportLua(Button, .{ "pos", "size", "allocator" });

    pos: Vec2 = .{ .x = 0.0, .y = 0.0 },
    size: Vec2 = .{ .x = 0.0, .y = 0.0 },
    title: [:0]const u8,
    visible: bool = true,
    clicked: bool = false,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *Button, allocator: std.mem.Allocator) void {
        _ = allocator;
        self.allocator.free(self.title);
    }
};
