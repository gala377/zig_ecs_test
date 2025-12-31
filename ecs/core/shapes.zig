const std = @import("std");
const rl = @import("raylib");

const component_prefix = @import("build_options").components_prefix;

const ecs = @import("../root.zig");
const Component = ecs.component.LibComponent;

pub const Circle = struct {
    pub const component_info = Component(component_prefix, Circle);
    radius: f32,
};

pub const Rectangle = struct {
    pub const component_info = Component(component_prefix, Rectangle);
    width: f32,
    height: f32,
};
