const Query = @import("../entity_storage.zig").QueryIter;
const Resource = @import("../resource.zig").Resource;
const commands = @import("commands.zig");
const Game = @import("../game.zig").Game;

pub fn create_entities(commands_res: commands.Commands) void {
    const cmd: *commands = commands_res.get();
    for (cmd.entities.items) |*entity| {
        cmd.game.insertEntity(entity.id, entity.components) catch {
            @panic("inserting entity failed");
        };
    }
    cmd.game.removeEntities(cmd.remove_entities.items) catch {
        @panic("removing entity returned error");
    };
    // game took ownership of components map we can clear all of entities
    cmd.entities.clearRetainingCapacity();
    cmd.remove_entities.clearRetainingCapacity();
}
