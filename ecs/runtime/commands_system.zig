const Query = @import("../entity_storage.zig").QueryIter;
const Resource = @import("../resource.zig").Resource;
const commands = @import("commands.zig");
const Game = @import("../game.zig").Game;
const ComponentWrapper = @import("../component.zig").Opaque;
const std = @import("std");

pub fn create_entities(commands_res: commands.Commands) anyerror!void {
    const cmd: *commands = commands_res.get();
    for (cmd.entities.items) |entity| {
        try cmd.game.newEntityWrapped(entity.id, entity.components);
    }
    for (cmd.add_components.items) |entity| {
        try cmd.game.addComponents(entity.id, entity.components);
    }
    for (cmd.remove_entities.items) |id| {
        std.debug.print("Removing entity {any}\n", .{id});
    }
    try cmd.game.removeEntities(cmd.remove_entities.items);

    // clear our storage.
    // We are using frame allocator so we can skip actually freeing memory.
    // Storage also copies all the components so everything we allocated this frame can also
    // just be simply forgotten.
    cmd.add_components = .empty;
    cmd.entities = .empty;
    cmd.remove_entities = .empty;
}
