const component_prefix = @import("build_options").components_prefix;

const ecs = @import("../root.zig");
const Component = ecs.component.LibComponent;
const ExportLua = ecs.lua.export_component.ExportLua;

const Self = @This();

pub const component_info = Component(component_prefix, Self);
pub const lua_info = ExportLua(Self, .{});

x: f32 = 0.0,
y: f32 = 0.0,
