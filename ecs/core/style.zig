const Component = @import("../component.zig").LibComponent;
const component_prefix = @import("build_options").components_prefix;
const Color = @import("color.zig");

const Self = @This();

pub const component_info = Component(component_prefix, Self);

background_color: ?Color = null,

radius_color: ?Color = null,
border_radius: f64 = 0.0,
