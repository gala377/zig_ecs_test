const std = @import("std");
const entity = @import("./entity.zig");
const scene = @import("scene.zig");
const entity_storage = @import("./entity_storage.zig");
const component = @import("./component.zig");
const Resource = @import("resource.zig").Resource;

const EntityId = scene.EntityId;
const ComponentId = component.ComponentId;
const ComponentWrapper = entity_storage.ComponentWrapper;
const Game = @import("./game.zig").Game;

const Self = @This();

const DeferredEntity = struct {
    id: EntityId,
    components: std.AutoHashMap(ComponentId, ComponentWrapper),
};

pub usingnamespace component.LibComponent("ecs", Self);

entities: std.ArrayList(DeferredEntity),
remove_entities: std.ArrayList(EntityId),
allocator: std.mem.Allocator,
game: *Game,

pub const Commands = Resource(Self);

pub fn init(game: *Game, allocator: std.mem.Allocator) Self {
    return .{
        .entities = .init(allocator),
        .allocator = allocator,
        .remove_entities = .init(allocator),
        .game = game,
    };
}

pub fn removeEntity(self: *Self, id: EntityId) !void {
    try self.remove_entities.append(id);
}

pub fn addEntity(self: *Self, id: EntityId, components: []ComponentWrapper) !void {
    var map = std.AutoHashMap(ComponentId, ComponentWrapper).init(self.allocator);
    for (components) |c| {
        try map.put(c.vtable.component_id, c);
    }
    try self.entities.append(.{
        .id = id,
        .components = map,
    });
}

pub fn addSceneEntity(self: *Self, components: []ComponentWrapper) !void {
    const cscene = self.game.current_scene orelse return error.noScenePresent;
    const entity_id = cscene.newId();
    const id = EntityId{
        .entity_id = entity_id,
        .scene_id = cscene.id,
    };
    return try self.addEntity(id, components);
}

pub fn newSceneEntity(self: *Self, components: anytype) !EntityId {
    const cscene = if (self.game.current_scene) |*cscene| ret: {
        break :ret cscene;
    } else {
        return error.noScenePresent;
    };
    const tinfo = @typeInfo(@TypeOf(components));
    if (comptime tinfo != .@"struct" and !tinfo.@"struct".is_tuple) {
        @compileError("components of an entity have to be passed as a tuple");
    }
    const infoStruct = tinfo.@"struct";

    const entity_id = cscene.newId();
    const id = EntityId{
        .entity_id = entity_id,
        .scene_id = cscene.id,
    };
    var componentsStorage: [infoStruct.fields.len + 1]ComponentWrapper = undefined;
    componentsStorage[0] = try cscene.entity_storage.allocComponent(id);
    inline for (components, 1..) |comp, index| {
        componentsStorage[index] = try cscene.entity_storage.allocComponent(comp);
    }
    try self.addEntity(id, &componentsStorage);
    return id;
}

pub fn newGlobalEntity(self: *Self, components: anytype) !EntityId {
    const tinfo = @typeInfo(@TypeOf(components));
    if (comptime tinfo != .@"struct" and !tinfo.@"struct".is_tuple) {
        @compileError("components of an entity have to be passed as a tuple");
    }
    const infoStruct = tinfo.@"struct";
    var componentsStorage: [infoStruct.fields.len + 1]ComponentWrapper = undefined;
    const entity_id = self.game.newId();
    componentsStorage[0] = try self.game.global_entity_storage.allocComponent(EntityId{
        .entity_id = entity_id,
        .scene_id = 0,
    });
    inline for (components, 1..) |comp, index| {
        componentsStorage[index] = try self.game.global_entity_storage.allocComponent(comp);
    }
    return try self.addGlobalEntity(entity_id, &components);
}

pub fn addGlobalEntity(self: *Self, entity_id: usize, components: []ComponentWrapper) !EntityId {
    const id = EntityId{
        .entity_id = entity_id,
        .scene_id = 0,
    };
    try self.addEntity(id, components);
    return entity_id;
}

pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
    _ = allocator;
    // entities that have not been added yet
    for (self.entities.items) |*e| {
        var iter = e.components.valueIterator();
        while (iter.next()) |comp| {
            comp.vtable.deinit(comp.pointer, self.game.allocator);
            comp.vtable.free(comp.pointer, self.game.allocator);
        }
        e.components.deinit();
    }
    self.entities.deinit();
    self.remove_entities.deinit();
}
