const std = @import("std");

const DeclarationGenerator = @import("../declaration_generator.zig");
const Game = @import("../root.zig").Game;
pub const components = @import("components.zig");

pub fn exportLua(game: *Game) !void {
    game.exportComponent(components.Button);
}

pub fn exportBuild(generator: *DeclarationGenerator) !void {
    try generator.registerComponentForBuild(components.Button);
}
