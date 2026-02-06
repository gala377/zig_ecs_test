const std = @import("std");
const ecs = @import("../prelude.zig");

pub const components = @import("components.zig");

const Game = ecs.Game;

pub fn install(game: *Game) !void {
    try game.type_registry.registerType(components.Button);
}

pub fn exportLua(game: *Game) void {
    game.exportComponent(components.Button);
}
