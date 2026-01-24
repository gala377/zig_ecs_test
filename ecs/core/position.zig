const ecs = @import("../prelude.zig");

const Component = ecs.Component;
const ExportLua = ecs.ExportLua;

const Self = @This();

pub const component_info = Component(Self);
pub const lua_info = ExportLua(Self, .{});

x: f32 = 0.0,
y: f32 = 0.0,
