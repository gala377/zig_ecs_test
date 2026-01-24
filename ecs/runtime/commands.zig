const std = @import("std");
const ecs = @import("../prelude.zig");

const component = ecs.component;
const entity = ecs.entity;
const scene = ecs.scene;
const utils = ecs.utils;

const Game = ecs.Game;
const EntityStorage = ecs.EntityStorage;
const Resource = ecs.Resource;
const FrameAllocator = ecs.runtime.allocators.FrameAllocator;
const Component = ecs.Component;

const Self = @This();

const DeferredEntity = struct {
    id: entity.Id,
    components: []component.Opaque,
};

pub const component_info = Component(Self);

entities: std.ArrayList(DeferredEntity),
add_components: std.ArrayList(DeferredEntity),
remove_entities: std.ArrayList(entity.Id),
allocator: std.mem.Allocator,
game: *Game,

pub const Commands = Resource(Self);

pub fn init(game: *Game) Self {
    const allocator = game.getResource(FrameAllocator).get();
    return .{
        .entities = .empty,
        .allocator = allocator.arena.allocator(),
        .remove_entities = .empty,
        .add_components = .empty,
        .game = game,
    };
}

pub fn removeEntity(self: *Self, id: entity.Id) !void {
    try self.remove_entities.append(self.allocator, id);
}

pub fn addEntityWrapped(
    self: *Self,
    id: entity.Id,
    components: []component.Opaque,
) !void {
    try self.entities.append(self.allocator, .{
        .id = id,
        .components = try self.allocator.dupe(
            component.Opaque,
            components,
        ),
    });
}

pub fn addComponents(
    self: *Self,
    entity_id: entity.Id,
    components: anytype,
) !void {
    const tinfo = @typeInfo(@TypeOf(components));
    if (comptime tinfo != .@"struct" and !tinfo.@"struct".is_tuple) {
        @compileError("components of an entity have to be passed as a tuple");
    }
    const infoStruct = tinfo.@"struct";
    var componentsStorage: [infoStruct.fields.len]component.Opaque = undefined;
    inline for (components, 0..) |comp, index| {
        const boxed = try self.allocator.create(@TypeOf(comp));
        boxed.* = comp;
        componentsStorage[index] = component.wrap(
            @TypeOf(comp),
            boxed,
        );
    }
    try self.registerComponentsToAdd(
        entity_id,
        &componentsStorage,
    );
}

fn getCurrentScene(self: *Self) *scene.Scene {
    if (self.game.current_scene) |*s| {
        return s;
    }
    @panic("no current scene");
}
pub fn addSceneEntityWrapped(
    self: *Self,
    components: []component.Opaque,
) !void {
    var cscene = self.getCurrentScene();
    const entity_id = cscene.newId();
    const id = entity.Id{
        .entity_id = entity_id,
        .scene_id = cscene.id,
    };
    return try self.addEntityWrapped(id, components);
}

fn addEntity(self: *Self, id: entity.Id, components: anytype) !void {
    const tinfo = @typeInfo(@TypeOf(components));
    if (comptime tinfo != .@"struct" and !tinfo.@"struct".is_tuple) {
        @compileError("components of an entity have to be passed as a tuple");
    }
    const infoStruct = tinfo.@"struct";
    var componentsStorage: [infoStruct.fields.len + 1]component.Opaque = undefined;
    const boxed_id = try self.allocator.create(entity.Id);
    boxed_id.* = id;
    componentsStorage[0] = component.wrap(entity.Id, boxed_id);
    inline for (components, 1..) |comp, index| {
        const boxed = try self.allocator.create(@TypeOf(comp));
        boxed.* = comp;
        componentsStorage[index] = component.wrap(@TypeOf(comp), boxed);
    }
    try self.addEntityWrapped(id, &componentsStorage);
}

pub fn addSceneEntity(self: *Self, components: anytype) !entity.Id {
    var cscene = self.getCurrentScene();
    const entity_id = cscene.newId();
    const id = entity.Id{
        .entity_id = entity_id,
        .scene_id = cscene.id,
    };
    try self.addEntity(id, components);
    return id;
}

pub fn addGlobalEntity(self: *Self, components: anytype) !entity.Id {
    const entity_id = self.game.newId();
    const id = entity.Id{
        .entity_id = entity_id,
        .scene_id = 0,
    };
    try self.addEntity(id, components);
    return id;
}

pub fn addGlobalEntityWrapped(
    self: *Self,
    entity_id: usize,
    components: []component.Opaque,
) !entity.Id {
    const id = entity.Id{
        .entity_id = entity_id,
        .scene_id = 0,
    };
    try self.addEntityWrapped(id, components);
    return entity_id;
}

fn registerComponentsToAdd(
    self: *Self,
    entity_id: entity.Id,
    components: []component.Opaque,
) !void {
    try self.add_components.append(self.allocator, .{
        .id = entity_id,
        .components = try self.allocator.dupe(
            component.Opaque,
            components,
        ),
    });
}
