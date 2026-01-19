const std = @import("std");

const Game = @import("../root.zig").Game;
pub const components = @import("components.zig");

pub fn exportLua(game: *Game) !void {
    game.exportComponent(components.Button);
}
