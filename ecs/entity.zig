const ecs = @import("prelude.zig");

pub const Id = struct {
    pub const component_info = ecs.Component(Id);
    pub const lua_info = ecs.ExportLua(Id, .{});
    scene_id: usize,
    entity_id: usize,
};
