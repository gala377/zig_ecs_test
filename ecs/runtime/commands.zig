const std = @import("std");
const component_prefix = @import("build_options").components_prefix;

const component = @import("../component.zig");
const entity = @import("../entity.zig");
const entity_storage = @import("../entity_storage.zig");
const scene = @import("../scene.zig");

const ComponentId = component.ComponentId;
const ComponentWrapper = entity_storage.ComponentWrapper;
const EntityId = entity.EntityId;
const Game = @import("../game.zig").Game;
const Resource = @import("../resource.zig").Resource;
const FrameAllocator = @import("../runtime/allocators.zig").FrameAllocator;

const Self = @This();

const DeferredEntity = struct {
    id: EntityId,
    components: []ComponentWrapper,
};

pub const component_info = component.LibComponent(component_prefix, Self);

entities: std.ArrayList(DeferredEntity),
add_components: std.ArrayList(DeferredEntity),
remove_entities: std.ArrayList(EntityId),
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

pub fn removeEntity(self: *Self, id: EntityId) !void {
    try self.remove_entities.append(self.allocator, id);
}

pub fn addEntityWrapped(self: *Self, id: EntityId, components: []ComponentWrapper) !void {
    try self.entities.append(self.allocator, .{
        .id = id,
        .components = try self.allocator.dupe(ComponentWrapper, components),
    });
}

pub fn addComponents(self: *Self, entity_id: EntityId, components: anytype) !void {
    const tinfo = @typeInfo(@TypeOf(components));
    if (comptime tinfo != .@"struct" and !tinfo.@"struct".is_tuple) {
        @compileError("components of an entity have to be passed as a tuple");
    }
    const infoStruct = tinfo.@"struct";
    var componentsStorage: [infoStruct.fields.len]ComponentWrapper = undefined;
    inline for (components, 0..) |comp, index| {
        const boxed = try self.allocator.create(@TypeOf(comp));
        boxed.* = comp;
        componentsStorage[index] = .{
            .pointer = @ptrCast(@alignCast(boxed)),
            .vtable = try self.game.global_entity_storage.createVTable(@TypeOf(comp)),
        };
    }
    try self.registerComponentsToAdd(entity_id, &componentsStorage);
}

fn getCurrentScene(self: *Self) *scene.Scene {
    if (self.game.current_scene) |*s| {
        return s;
    }
    @panic("no current scene");
}
pub fn addSceneEntityWrapped(self: *Self, components: []ComponentWrapper) !void {
    var cscene = self.getCurrentScene();
    const entity_id = cscene.newId();
    const id = EntityId{
        .entity_id = entity_id,
        .scene_id = cscene.id,
    };
    return try self.addEntityWrapped(id, components);
}

fn addEntity(self: *Self, id: EntityId, components: anytype) !void {
    const tinfo = @typeInfo(@TypeOf(components));
    if (comptime tinfo != .@"struct" and !tinfo.@"struct".is_tuple) {
        @compileError("components of an entity have to be passed as a tuple");
    }
    const infoStruct = tinfo.@"struct";
    var componentsStorage: [infoStruct.fields.len + 1]ComponentWrapper = undefined;
    const boxed_id = try self.allocator.create(EntityId);
    boxed_id.* = id;
    componentsStorage[0] = ComponentWrapper{
        .pointer = @ptrCast(@alignCast(boxed_id)),
        .vtable = try self.game.global_entity_storage.createVTable(EntityId),
    };
    inline for (components, 1..) |comp, index| {
        const boxed = try self.allocator.create(@TypeOf(comp));
        boxed.* = comp;
        componentsStorage[index] = ComponentWrapper{
            .pointer = @ptrCast(@alignCast(boxed)),
            .vtable = try self.game.global_entity_storage.createVTable(@TypeOf(comp)),
        };
    }
    try self.addEntityWrapped(id, &componentsStorage);
}

pub fn addSceneEntity(self: *Self, components: anytype) !EntityId {
    var cscene = self.getCurrentScene();
    const entity_id = cscene.newId();
    const id = EntityId{
        .entity_id = entity_id,
        .scene_id = cscene.id,
    };
    try self.addEntity(id, components);
    return id;
}

pub fn addGlobalEntity(self: *Self, components: anytype) !EntityId {
    const entity_id = self.game.newId();
    const id = EntityId{
        .entity_id = entity_id,
        .scene_id = 0,
    };
    try self.addEntity(id, components);
    return id;
}

pub fn addGlobalEntityWrapped(self: *Self, entity_id: usize, components: []ComponentWrapper) !EntityId {
    const id = EntityId{
        .entity_id = entity_id,
        .scene_id = 0,
    };
    try self.addEntityWrapped(id, components);
    return entity_id;
}

fn registerComponentsToAdd(self: *Self, entity_id: EntityId, components: []ComponentWrapper) !void {
    try self.add_components.append(self.allocator, .{
        .id = entity_id,
        .components = try self.allocator.dupe(ComponentWrapper, components),
    });
}
