const rl = @import("raylib");

const component_prefix = @import("build_options").components_prefix;

const ecs = @import("../root.zig");
const Component = ecs.component.LibComponent;
const ExportLua = ecs.lua.export_component.ExportLua;

const Self = @This();

pub const component_info = Component(component_prefix, Self);
pub const lua_info = ExportLua(Self, &.{});

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
