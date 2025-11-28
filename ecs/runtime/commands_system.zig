const Query = @import("../entity_storage.zig").QueryIter;
const Resource = @import("../resource.zig").Resource;
const commands = @import("commands.zig");
const Game = @import("../game.zig").Game;
const ComponentWrapper = @import("../entity_storage.zig").ComponentWrapper;

pub fn create_entities(commands_res: commands.Commands) void {
    const cmd: *commands = commands_res.get();
    for (cmd.entities.items) |*entity| {
        cmd.game.insertEntity(entity.id, entity.components) catch {
            @panic("inserting entity failed");
        };
    }
    for (cmd.add_components.items) |*entity| {
        const comp_count = entity.components.count();
        const components = cmd.allocator.alloc(ComponentWrapper, comp_count) catch {
            @panic("run out of memory");
        };
        defer cmd.allocator.free(components);

        var citer = entity.components.valueIterator();
        var index: usize = 0;
        while (citer.next()) |c| : (index += 1) {
            components[index] = c.*;
        }
        cmd.game.addComponents(entity.id, components) catch {
            @panic("could not add components to entity");
        };
    }
    cmd.game.removeEntities(cmd.remove_entities.items) catch {
        @panic("removing entity returned error");
    };

    for (cmd.add_components.items) |*entity| {
        entity.components.deinit();
    }
    // clear our owned
    cmd.add_components.clearRetainingCapacity();

    // game took ownership of components map we can clear all of entities
    cmd.entities.clearRetainingCapacity();
    cmd.remove_entities.clearRetainingCapacity();
}
