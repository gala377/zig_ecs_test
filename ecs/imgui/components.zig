const Vec2 = @import("../utils.zig").Vec2;
const std = @import("std");
const ComponentDeinit = @import("../scene.zig").ComponentDeinit;
const Component = @import("../component.zig").LibComponent;
const ExportLua = @import("../component.zig").ExportLua;
const component_prefix = @import("build_options").components_prefix;

pub const Button = struct {
    pub usingnamespace Component(component_prefix, Button);
    pub usingnamespace ExportLua(Button, .{
        "pos", "size", "title",
    });

    pos: Vec2,
    size: Vec2,
    title: [:0]const u8,
    visible: bool = true,
    clicked: bool = false,

    pub fn deinit(self: *Button, allocator: std.mem.Allocator) void {
        allocator.free(self.title);
    }
};
