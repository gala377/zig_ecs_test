const ecs = @import("../prelude.zig");

pub const Position = @import("position.zig");
pub const Color = @import("color.zig");
pub const Style = @import("style.zig");
pub const Vec2 = @import("vec2.zig");
pub const window = @import("window.zig");
pub const shapes = @import("shapes.zig");
pub const Name = @import("name.zig");

pub fn install(game: *ecs.Game) !void {
    try game.type_registry.registerType(Position);
    try game.type_registry.registerType(Color);
    try game.type_registry.registerType(Style);
    try game.type_registry.registerType(Vec2);
    try game.type_registry.registerType(window.WindowOptions);
    try game.type_registry.registerType(shapes.Circle);
    try game.type_registry.registerType(shapes.Rectangle);
    try game.type_registry.registerType(Name);
}
