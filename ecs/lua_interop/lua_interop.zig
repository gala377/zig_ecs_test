const ecs = @import("../prelude.zig");
pub const export_component = @import("export.zig");
pub const system = @import("system.zig");
pub const script = @import("script.zig");

pub fn install(game: *ecs.Game) !void {
    try game.type_registry.registerType(script.Initialized);
    try game.type_registry.registerType(script.LuaScript);
}
