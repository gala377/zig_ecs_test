const std = @import("std");
const ecs = @import("../prelude.zig");

pub const TypeRegistry = struct {
    pub const component_info = ecs.Component(@This());

    registry: *ecs.TypeRegistry,
};

pub const SystemRegistry = struct {
    pub const component_info = ecs.Component(@This());

    registry: *ecs.SystemsRegistry,
};
