pub const components = @import("components.zig");
pub const systems = @import("systems.zig");
const Game = @import("../root.zig").Game;
const system = @import("../root.zig").system;

pub fn addImguiPlugin(game: *Game) !void {
    try game.addSystem(system(systems.draw_imgui));
}
