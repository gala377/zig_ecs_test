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

const Self = @This();

const DeferredEntity = struct {
    id: EntityId,
    components: std.AutoHashMap(ComponentId, ComponentWrapper),
};

pub const component_info = component.LibComponent(component_prefix, Self);

entities: std.ArrayList(DeferredEntity),
add_components: std.ArrayList(DeferredEntity),
remove_entities: std.ArrayList(EntityId),
allocator: std.mem.Allocator,
game: *Game,

pub const Commands = Resource(Self);

pub fn init(game: *Game, allocator: std.mem.Allocator) Self {
    return .{
        .entities = .empty,
        .allocator = allocator,
        .remove_entities = .empty,
        .add_components = .empty,
        .game = game,
    };
}

pub fn removeEntity(self: *Self, id: EntityId) !void {
    try self.remove_entities.append(self.allocator, id);
}

pub fn addEntity(self: *Self, id: EntityId, components: []ComponentWrapper) !void {
    var map = std.AutoHashMap(ComponentId, ComponentWrapper).init(self.allocator);
    for (components) |c| {
        try map.put(c.vtable.component_id, c);
    }
    try self.entities.append(self.allocator, .{
        .id = id,
        .components = map,
    });
}

pub fn addComponents(self: *Self, entity_id: EntityId, components: anytype) !void {
    if (entity_id.scene_id == 0) {
        try self.addComponentsToGlobalEntity(entity_id, components);
    } else {
        try self.addComponentsToSceneEntity(entity_id, components);
    }
}

fn registerComponentsToAdd(self: *Self, entity_id: EntityId, components: []ComponentWrapper) !void {
    var map = std.AutoHashMap(ComponentId, ComponentWrapper).init(self.allocator);
    for (components) |c| {
        try map.put(c.vtable.component_id, c);
    }
    try self.add_components.append(self.allocator, .{
        .id = entity_id,
        .components = map,
    });
}

pub fn addComponentsToGlobalEntity(self: *Self, entity_id: EntityId, components: anytype) !void {
    const tinfo = @typeInfo(@TypeOf(components));
    if (comptime tinfo != .@"struct" and !tinfo.@"struct".is_tuple) {
        @compileError("components of an entity have to be passed as a tuple");
    }
    const infoStruct = tinfo.@"struct";
    var componentsStorage: [infoStruct.fields.len]ComponentWrapper = undefined;
    inline for (components, 0..) |comp, index| {
        componentsStorage[index] = try self.game.global_entity_storage.allocComponent(comp);
    }
    try self.registerComponentsToAdd(entity_id, &componentsStorage);
}

pub fn addComponentsToSceneEntity(self: *Self, entity_id: EntityId, components: anytype) !void {
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

    var componentsStorage: [infoStruct.fields.len]ComponentWrapper = undefined;
    inline for (components, 0..) |comp, index| {
        componentsStorage[index] = try cscene.entity_storage.allocComponent(comp);
    }
    try self.registerComponentsToAdd(entity_id, &componentsStorage);
}

pub fn addSceneEntity(self: *Self, components: []ComponentWrapper) !void {
    const cscene = self.game.current_scene orelse return error.noScenePresent;
    const entity_id = cscene.newId();
    const id = EntityId{
        .entity_id = entity_id,
        .scene_id = cscene.id,
        .archetype_id = try cscene.scene_allocator.create(usize),
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
        .archetype_id = try cscene.scene_allocator.create(usize),
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
        .archetype_id = self.game.allocator.create(usize),
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
        .archetype_id = try self.game.allocator.create(usize),
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

    for (self.add_components.items) |*e| {
        var iter = e.components.valueIterator();
        while (iter.next()) |comp| {
            comp.vtable.deinit(comp.pointer, self.game.allocator);
            comp.vtable.free(comp.pointer, self.game.allocator);
        }
        e.components.deinit();
    }

    self.add_components.deinit(self.allocator);
    self.entities.deinit(self.allocator);
    self.remove_entities.deinit(self.allocator);
}
