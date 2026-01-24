const std = @import("std");
const ecs = @import("../prelude.zig");

const Component = ecs.Component;
const ExportLua = ecs.ExportLua;

pub const Circle = struct {
    pub const component_info = Component(Circle);
    pub const lua_info = ExportLua(Circle, .{});
    radius: f32,
};

pub const Rectangle = struct {
    pub const component_info = Component(Rectangle);
    pub const lua_info = ExportLua(Rectangle, .{});
    width: f32,
    height: f32,
};
