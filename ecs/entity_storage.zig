const std = @import("std");
const Entity = @import("entity.zig");
const ComponentId = @import("component.zig").ComponentId;
const Sorted = @import("utils.zig").Sorted;
const PtrTuple = @import("utils.zig").PtrTuple;
const assertSorted = @import("utils.zig").assertSorted;
const utils = @import("utils.zig");
const DynamicQueryScope = @import("dynamic_query.zig").DynamicQueryScope;
const clua = @import("lua_lib").clib;

pub const ComponentDeinit = *const fn (*anyopaque, allocator: std.mem.Allocator) void;
pub const ComponentFree = *const fn (*anyopaque, allocator: std.mem.Allocator) void;
pub const ComponentLuaPush = *const fn (*anyopaque, state: *clua.lua_State) void;

pub const ComponentWrapper = struct {
    pointer: *anyopaque,
    size: usize,
    alignment: usize,
    // Should be static
    name: []const u8,
    component_id: ComponentId,
    deinit: ComponentDeinit,
    free: ComponentFree,
    luaPush: ?ComponentLuaPush,
};

pub const ArchetypeStorage = struct {
    components: []const ComponentId,
    entities: std.AutoHashMap(usize, Entity),
};

archetypes: std.ArrayList(ArchetypeStorage),
components_per_archetype: std.ArrayList(Sorted([]const ComponentId)),
allocator: std.mem.Allocator,

const Self = @This();

pub fn init(allocator: std.mem.Allocator) !Self {
    return .{
        .archetypes = .init(allocator),
        .components_per_archetype = .init(allocator),
        .allocator = allocator,
    };
}

pub fn makeEntity(self: *Self, id: usize, components: anytype) !void {
    const tinfo = @typeInfo(@TypeOf(components));
    if (comptime tinfo != .@"struct" and !tinfo.@"struct".is_tuple) {
        @compileError("components of an entity have to be passed as a tuple");
    }
    const infoStruct = tinfo.@"struct";
    var componentsStorage: [infoStruct.fields.len]ComponentWrapper = undefined;
    var componentIds: [infoStruct.fields.len]ComponentId = undefined;
    inline for (components, 0..) |component, index| {
        componentsStorage[index] = try self.allocComponent(component);
        componentIds[index] = @TypeOf(component).comp_id;
    }
    var entity = Entity.init(id, self.allocator);
    try entity.addComponents(&componentsStorage);
    const storage = try self.findOrCreateArchetype(&componentIds);
    const putres = try storage.entities.fetchPut(id, entity);
    if (putres) |old| {
        _ = old;
        @panic("replacing existing entity");
    }
}

pub fn insertEntity(self: *Self, id: usize, components: std.AutoHashMap(ComponentId, ComponentWrapper)) !void {
    std.debug.print("Inserting entity\n", .{});
    var component_ids = try self.allocator.alloc(ComponentId, components.count());
    defer self.allocator.free(component_ids);
    var keys = components.keyIterator();
    var idx: usize = 0;
    while (keys.next()) |cid| {
        component_ids[idx] = cid.*;
        idx += 1;
    }
    std.sort.heap(ComponentId, component_ids, void{}, std.sort.asc(ComponentId));
    // global entity
    const archetype = try self.findOrCreateArchetype(component_ids);
    if (archetype.entities.contains(id)) {
        return error.entityAlreadyExists;
    }
    const entity = Entity{
        .id = id,
        .components = components,
    };
    try archetype.entities.put(id, entity);
}

fn findOrCreateArchetype(self: *Self, ids: []ComponentId) !*ArchetypeStorage {
    std.sort.heap(ComponentId, ids, {}, std.sort.asc(ComponentId));
    if (self.findExactArchetypeProvidedSorted(assertSorted(ComponentId, ids))) |ptr| {
        return ptr;
    }
    return self.createArchetype(assertSorted(ComponentId, ids));
}

fn createArchetype(self: *Self, ids: Sorted([]ComponentId)) !*ArchetypeStorage {
    const heaped = try self.allocator.dupe(ComponentId, ids);
    const new = ArchetypeStorage{
        .components = heaped,
        .entities = .init(self.allocator),
    };
    try self.archetypes.append(new);
    try self.components_per_archetype.append(heaped);
    return &self.archetypes.items[self.archetypes.items.len - 1];
}

fn findExactArchetypeProvidedSorted(self: *Self, ids: Sorted([]ComponentId)) ?*ArchetypeStorage {
    outer: for (self.components_per_archetype.items, 0..) |components, archetype_idx| {
        if (components.len != ids.len) {
            continue;
        }
        for (components, ids) |c1, c2| {
            if (c1 != c2) {
                continue :outer;
            }
        }
        return &self.archetypes.items[archetype_idx];
    }
    return null;
}

pub fn QueryIter(comptime Components: anytype) type {
    const Storage = @This();
    const Len = @typeInfo(@TypeOf(Components)).@"struct".fields.len;
    return struct {
        const Iter = @This();
        component_ids: [Len]ComponentId,
        storage: *Storage,
        next_archetype: usize = 0,
        current_entity_iterator: ?std.AutoHashMap(usize, Entity).ValueIterator = null,

        pub fn init(storage: *Storage, component_ids: [Len]ComponentId) Iter {
            return .{
                .component_ids = component_ids,
                .storage = storage,
            };
        }

        pub fn next(self: *Iter) ?PtrTuple(Components) {
            if (self.current_entity_iterator) |it| {
                var itt: std.AutoHashMap(usize, Entity).ValueIterator = it;
                if (itt.next()) |entity| {
                    return getComponentsFromEntity(entity);
                }
                // iterator ended
                self.current_entity_iterator = null;
            }
            while (self.next_archetype < self.storage.archetypes.items.len) {
                const comps = self.storage.components_per_archetype.items[self.next_archetype];
                if (!utils.isSubset(&self.component_ids, comps)) {
                    // not a subset, check next archetype
                    self.next_archetype += 1;
                    continue;
                }
                self.current_entity_iterator = self
                    .storage
                    .archetypes
                    .items[self.next_archetype]
                    .entities
                    .valueIterator();
                if (self.current_entity_iterator.?.next()) |entity| {
                    // after out value iterator runs out we have to check next arcehtypr
                    self.next_archetype += 1;
                    return getComponentsFromEntity(entity);
                }
                // no entities in the iterator
                self.current_entity_iterator = null;
                self.next_archetype += 1;
            }
            return null;
        }

        fn getComponentsFromEntity(entity: *Entity) PtrTuple(Components) {
            var res: PtrTuple(Components) = undefined;
            inline for (Components, 0..) |Component, idx| {
                const id = Component.comp_id;
                const comp: *ComponentWrapper = entity.components.getPtr(id).?;
                const asptr: *Component = @ptrCast(@alignCast(comp.pointer));
                res[idx] = asptr;
            }
            return res;
        }
    };
}

pub fn query(self: *Self, comptime comps: anytype) QueryIter(comps) {
    const info = @typeInfo(@TypeOf(comps));
    if (info != .@"struct" and !info.@"struct".is_tuple) {
        @compileError("query accepts a tuple of types");
    }
    const infoStruct = info.@"struct";
    var componentIds: [infoStruct.fields.len]ComponentId = undefined;
    inline for (comps, 0..) |component, index| {
        const tinfo = @typeInfo(@TypeOf(component));
        if (tinfo != .type) {
            @compileError("query accepts a typle of types");
        }
        componentIds[index] = component.comp_id;
    }
    std.sort.heap(ComponentId, &componentIds, {}, std.sort.asc(ComponentId));
    _ = assertSorted(ComponentId, &componentIds);
    return QueryIter(comps).init(self, componentIds);
}

pub const DynamicScopeOptions = struct {
    allocator: ?std.mem.Allocator = null,
};

/// Returns a scope object that can be used to crete dynamic query iterator.
/// Scope has to be freed after the query has been used.
///
/// Does not take ownership of the components slice. It has be the freed by the caller.
pub fn dynamicQueryScope(self: *Self, components: []const ComponentId, options: DynamicScopeOptions) !DynamicQueryScope {
    const allocator = options.allocator orelse self.allocator;
    return .init(self, components, allocator);
}

fn findSubsetArchetypeProvidedSorted(self: *Self, ids: Sorted([]ComponentId)) ?*ArchetypeStorage {
    outer: for (self.components_per_archetype.items, 0..) |components, archetype_idx| {
        if (components.len < ids.len) {
            continue;
        }
        var comp_idx = 0;
        var ids_idx = 0;
        while (comp_idx < components.len) {
            while (ids_idx < ids.len) {
                const comp_id = components[comp_idx];
                const ids_id = ids[ids_idx];
                if (comp_id == ids_id) {
                    comp_idx += 1;
                    ids_idx += 1;
                } else if (comp_id < ids_id) {
                    comp_id += 1;
                } else if (comp_id > ids_id) {
                    // component is higher, meaing we did not find a match
                    // for the given id - so this is not the archetype
                    continue :outer;
                } else {
                    unreachable;
                }
            }
        }
        if (ids_idx == ids.len) {
            // we went through all of the ids so we have a mathc
            return &self.archetypes.items[archetype_idx];
        }
    }
    return null;
}

pub fn allocComponent(self: *Self, comp: anytype) !ComponentWrapper {
    const Component = @TypeOf(comp);
    // if (comptime !std.meta.fieldNames(Component, "is_component_marker")) {
    //     const msg = "Type " ++ @typeName(Component) ++ " is not a component. Add `pub usingnamespace Component(" ++ @typeName(Component) ++ ")`.";
    //     @compileError(msg);
    // }
    const cptr = try self.allocator.create(@TypeOf(comp));
    cptr.* = comp;

    const compDeinit: ComponentDeinit = if (comptime std.meta.hasMethod(Component, "deinit"))
        @ptrCast(&Component.deinit)
    else
        @ptrCast(&emptyDeinit);

    const compLuaPush: ?ComponentLuaPush = if (comptime std.meta.hasFn(Component, "luaPush"))
        @ptrCast(&Component.luaPush)
    else
        null;
    const wrapped: ComponentWrapper = .{
        .pointer = @ptrCast(cptr),
        .alignment = @alignOf(Component),
        .size = @sizeOf(Component),
        .component_id = Component.comp_id,
        .name = Component.comp_name,
        .deinit = compDeinit,
        .free = componentFree(Component),
        .luaPush = compLuaPush,
    };
    return wrapped;
}

pub fn deinit(self: Self) void {
    self.components_per_archetype.deinit();
    for (self.archetypes.items) |*archetype| {
        self.allocator.free(archetype.components);
        var it = archetype.entities.valueIterator();
        while (it.next()) |entity| {
            entity.deinit(self.allocator);
        }
        archetype.entities.deinit();
    }
    self.archetypes.deinit();
}

pub fn componentFree(comptime T: type) ComponentFree {
    return @ptrCast(&struct {
        pub fn inner(ptr: *T, allocator: std.mem.Allocator) void {
            allocator.destroy(ptr);
        }
    }.inner);
}

fn emptyDeinit(ptr: *anyopaque, allocator: std.mem.Allocator) void {
    _ = ptr;
    _ = allocator;
}
