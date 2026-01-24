const lua_lib = @import("lua_lib");
const ecs = @import("../prelude.zig");

const Component = ecs.Component;

const Self = @This();

pub const component_info = Component(Self);

lua: *lua_lib.State,
