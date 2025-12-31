const Component = @import("../root.zig").Component;

pub const Size = struct {
    width: i32,
    height: i32,
};

pub const WindowOptions = struct {
    pub const component_info = Component(WindowOptions);

    title: [:0]const u8,
    size: Size,
    targetFps: i32 = 60,
};
