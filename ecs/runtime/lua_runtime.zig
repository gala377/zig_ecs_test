const lua_lib = @import("lua_lib");

const component_prefix = @import("build_options").components_prefix;
const component = @import("../component.zig");
const Component = component.LibComponent;

const Self = @This();

pub const component_info = Component(component_prefix, Self);

lua: *lua_lib.State,
