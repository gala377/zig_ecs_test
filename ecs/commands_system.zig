const Query = @import("entity_storage.zig").QueryIter;
const Resource = @import("resource.zig").Resource;
const Commands = @import("commands.zig");
const Game = @import("game.zig").Game;

pub fn create_entities(game: *Game) void {
    const commands_res = game.getResource(Commands);
    const commands = commands_res.get();
    for (commands.entities.items) |entity| {
        _ = entity;
    }
}
