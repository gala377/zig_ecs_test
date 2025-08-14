const Component = @import("../component.zig").LibComponent;
const component_prefix = @import("build_options").components_prefix;

const Self = @This();

pub usingnamespace Component(component_prefix, Self);

x: f32 = 0.0,
y: f32 = 0.0,
