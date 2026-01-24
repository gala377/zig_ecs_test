const ecs = @import("../prelude.zig");

pub const Size = struct {
    width: i32,
    height: i32,
};

pub const WindowOptions = struct {
    pub const component_info = ecs.Component(WindowOptions);

    title: [:0]const u8,
    size: Size,
    targetFps: i32 = 60,
};
