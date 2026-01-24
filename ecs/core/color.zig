const rl = @import("raylib");
const ecs = @import("../prelude.zig");

const Component = ecs.Component;
const ExportLua = ecs.ExportLua;

const Self = @This();

pub const component_info = Component(Self);
pub const lua_info = ExportLua(Self, .{});

r: u8,
g: u8,
b: u8,
a: u8,

pub const white: Self = .{
    .r = 255,
    .g = 255,
    .b = 255,
    .a = 255,
};

pub const black: Self = .{
    .r = 0,
    .g = 0,
    .b = 0,
    .a = 255,
};
