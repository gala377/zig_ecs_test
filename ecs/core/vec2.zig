const Component = @import("../component.zig").LibComponent;
const component_prefix = @import("build_options").components_prefix;
const ExportLua = @import("../component.zig").ExportLua;

const Self = @This();

pub const component_info = Component(component_prefix, Self);
pub const lua_info = ExportLua(Self, .{});

x: f32,
y: f32,

pub fn add(self: Self, other: Self) Self {
    return .{
        .x = self.x + other.x,
        .y = self.y + other.y,
    };
}

pub fn add_x(self: Self, value: f32) Self {
    return .{
        .x = self.x + value,
        .y = self.y,
    };
}

pub fn add_y(self: Self, value: f32) Self {
    return .{
        .x = self.x,
        .y = self.y + value,
    };
}
