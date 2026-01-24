const ecs = @import("../prelude.zig");
const Component = ecs.Component;
const ExportLua = ecs.ExportLua;

const Color = @import("color.zig");

const Self = @This();

pub const component_info = Component(Self);
pub const lua_info = ExportLua(Self, .{});

background_color: ?Color = null,

radius_color: ?Color = null,
border_radius: f64 = 0.0,
