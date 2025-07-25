const Vec2 = @import("../utils.zig").Vec2;
const std = @import("std");
const ComponentDeinit = @import("../scene.zig").ComponentDeinit;

pub const Button = struct {
    pos: Vec2,
    size: Vec2,
    title: [:0]const u8,
    clicked: bool,

    pub fn deinit(self: *Button, allocator: std.mem.Allocator) void {
        allocator.free(self.title);
    }
};
