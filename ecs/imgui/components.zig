const Vec2 = @import("../utils.zig").Vec2;
const std = @import("std");
const ComponentDeinit = @import("../scene.zig").ComponentDeinit;
const Component = @import("../component.zig").Component;

pub const Button = struct {
    pub usingnamespace Component(Button);

    pos: Vec2,
    size: Vec2,
    title: [:0]const u8,
    visible: bool = true,
    clicked: bool = false,

    pub fn deinit(self: *Button, allocator: std.mem.Allocator) void {
        allocator.free(self.title);
    }
};
