pub const components = @import("components.zig");
pub const systems = @import("systems.zig");
const Game = @import("../root.zig").Game;
const DeclarationGenerator = @import("../declaration_generator.zig");
const system = @import("../root.zig").system;

pub fn addImguiPlugin(game: *Game) !void {
    try game.addSystem(system(systems.draw_imgui));
}

pub fn exportLua(game: *Game) !void {
    game.exportComponent(components.Button);
}

pub fn exportBuild(generator: *DeclarationGenerator) !void {
    try generator.registerComponentForBuild(components.Button);
}
