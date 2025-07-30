pub const components = @import("components.zig");
pub const systems = @import("systems.zig");
pub const Game = @import("../game.zig").Game;

pub fn addImguiPlugin(game: *Game) !void {
    try game.addSystem(systems.draw_imgui);
}
