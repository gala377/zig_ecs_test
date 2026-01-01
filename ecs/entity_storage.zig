const std = @import("std");
const builtin = @import("builtin");

const clua = @import("lua_lib").clib;

const assertSorted = @import("utils.zig").assertSorted;
const ComponentId = @import("component.zig").ComponentId;
const DynamicQueryScope = @import("dynamic_query.zig").DynamicQueryScope;
const Entity = @import("entity.zig");
const EntityId = Entity.EntityId;
const PtrTuple = @import("utils.zig").PtrTuple;
const QueryIter = @import("query.zig").QueryIter;
const Sorted = @import("utils.zig").Sorted;
const utils = @import("utils.zig");
const VTableStorage = @import("comp_vtable_storage.zig");

const Self = @This();

pub const ComponentDeinit = *const fn (*anyopaque, allocator: std.mem.Allocator) void;
pub const ComponentFree = *const fn (*anyopaque, allocator: std.mem.Allocator) void;
pub const ComponentLuaPush = *const fn (*anyopaque, state: *clua.lua_State) void;
pub const ComponentFromLua = *const fn (state: *clua.lua_State, storage: *Self) void;

// Maps entities to their respective archetypes so we can
pub const EntityMap = std.AutoHashMap(EntityId, EntityArchetypeRecord);

const EntityArchetypeRecord = struct {
    // archetype that this entity belogs to
    archetype_index: usize,
    // row in this archetype that this entity stores it's components at
    row_id: usize,
};

pub const Archetype = struct {
    /// how many entities are in this archetype
    capacity: usize,
    /// a list of free indexes that things can be allocated at
    freelist: std.AutoHashMap(usize, u8),
    /// stores all the components in the archetype
    components: std.ArrayList(ComponentColumn),
    /// maps component id to the index in the components array
    components_map: std.AutoHashMap(ComponentId, usize),

    /// Sorted list of component ids stored within this archetype.
    ///
    /// can be derived from component_map.each.component_id
    /// or from component_map
    components_ids: []const ComponentId,

    archetype_index: usize,

    pub fn init(allocator: std.mem.Allocator, archetype_index: usize, components_ids: []const ComponentId, vtables: []*const ComponentWrapper.VTable) !@This() {
        var components_map = std.AutoHashMap(ComponentId, usize).init(allocator);
        var components = try std.ArrayList(ComponentColumn).initCapacity(allocator, components_ids.len);
        for (vtables, 0..vtables.len) |vtable, index| {
            try components_map.put(vtable.component_id, index);
            try components.append(allocator, .init(vtable));
        }
        return .{
            .capacity = 0,
            .freelist = .init(allocator),
            .components = components,
            .components_map = components_map,
            .components_ids = components_ids,
            .archetype_index = archetype_index,
        };
    }

    // Returns a handle that can be used to get entities
    // from this archetype. To get next index call
    // nextIndex passing this index as argument.
    pub fn iterIndex(self: *@This()) ?usize {
        if (self.alive() == 0) {
            return null;
        }
        var index: usize = 0;
        // progress index to first one not in freelist
        while (self.freelist.contains(index)) : (index = index + 1) {}
        if (index >= self.capacity) {
            return null;
        }
        return index;
    }
    // Gives you the next index which can be used to get a component.
    //
    // Null if there is no more entities to look at
    pub fn nextIndex(self: *@This(), index: usize) ?usize {
        var new_index = index + 1;
        while (self.freelist.contains(new_index)) : (new_index = new_index + 1) {}
        if (new_index >= self.capacity) {
            return null;
        }
        return new_index;
    }

    // how many entities are in this storage.
    pub fn alive(self: *@This()) usize {
        return self.capacity - self.freelist.count();
    }

    pub fn finalize(self: *@This(), index: usize, allocator: std.mem.Allocator) void {
        for (self.components.items) |*column| {
            const comp = column.getOpaque(index);
            const vtable = column.vtable;
            vtable.deinit(comp, allocator);
        }
    }

    pub fn finalizeById(self: *@This(), index: usize, allocator: std.mem.Allocator, ids: []const ComponentId) void {
        for (ids) |component_id| {
            const component_index = self.components_map.get(component_id) orelse @panic("component is missing");
            const column = &self.components[component_index];
            const comp = column.getOpaque(index);
            const vtable = column.vtable;
            vtable.deinit(comp, allocator);
        }
    }

    pub fn remove(self: *@This(), index: usize) !void {
        std.debug.print("Self is {any}\n", .{self.*});
        std.debug.print("Removign under index {any}\n", .{index});
        try self.freelist.put(index, 0);
    }

    // Does not free memory that has been allocated for ComponentWrapper.
    // This has to be one by the caller.
    pub fn add(self: *@This(), allocator: std.mem.Allocator, components: []const ComponentWrapper) !usize {
        const index = try self.allocate(allocator);
        for (components) |component| {
            const component_id = component.vtable.component_id;
            const column_index = self.components_map.get(component_id) orelse unreachable;
            const pointer_many: [*]const u8 = @ptrCast(@alignCast(component.pointer));
            const pointer: []const u8 = pointer_many[0..component.vtable.size];
            self.components.items[column_index].insertAtUnchecked(index, component_id, pointer);
        }
        return index;
    }

    // Inserts component at the given space, does not free the memory allocated to the component
    pub fn insertUncheked(self: @This(), index: usize, components: []const ComponentWrapper) void {
        for (components) |component| {
            const component_id = component.vtable.component_id;
            const column_index = self.components_map.get(component_id) orelse unreachable;
            const pointer_many: [*]const u8 = @ptrCast(@alignCast(component.pointer));
            const pointer: []const u8 = pointer_many[0..component.vtable.size];
            self.components.items[column_index].insertAtUnchecked(index, component_id, pointer);
        }
    }

    // allocates zeroed space for the given components.
    //
    // Returns index at which entity resides in the archetype.
    pub fn allocate(self: *@This(), allocator: std.mem.Allocator) !usize {
        return self.getFreelistIndex() orelse try self.allocateNewSpace(allocator);
    }

    /// Gets random index from freelist if any.
    ///
    /// Removes index if it has been found.
    fn getFreelistIndex(self: *@This()) ?usize {
        var key_iterator = self.freelist.keyIterator();
        const next_ptr = key_iterator.next() orelse return null;
        const next = next_ptr.*;
        _ = self.freelist.remove(next);
        return next;
    }

    /// **does not insert a value into free list**
    ///
    /// This has to be done manually
    fn allocateNewSpace(self: *@This(), allocator: std.mem.Allocator) !usize {
        for (self.components.items) |*column| {
            const index = try column.allocateNew(allocator);
            std.debug.assert(index == self.capacity);
        }
        const index = self.capacity;
        self.capacity += 1;
        return index;
    }

    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        allocator.free(self.components_ids);
        for (self.components.items) |*column| {
            column.deinit(allocator, &self.freelist);
        }
        self.components.deinit(allocator);
        self.freelist.deinit();
        self.components_map.deinit();
    }
};

pub const ComponentColumn = struct {
    component_size: usize,
    column_size: usize, // can be derived from buffer.items.size / component_size
    component_id: ComponentId,
    vtable: *const ComponentWrapper.VTable,
    // Align to 64 so that everything can be stored without problems
    buffer: std.array_list.Aligned(u8, std.mem.Alignment.@"8"),

    pub fn init(vtable: *const ComponentWrapper.VTable) @This() {
        return .{
            .component_id = vtable.component_id,
            .column_size = 0,
            .component_size = vtable.size,
            .vtable = vtable,
            .buffer = .empty,
        };
    }

    pub fn insertAtUnchecked(self: *@This(), index: usize, component_id: ComponentId, bytes: []const u8) void {
        std.debug.assert(self.vtable.component_id == component_id);
        const buffer_index = index * self.component_size;
        @memcpy(self.buffer.items[buffer_index .. buffer_index + self.component_size], bytes);
    }

    /// allocates zeroed memory in the buffer.
    ///
    /// returns index that can be used to get/insert at the memory.
    pub fn allocateNew(self: *@This(), allocator: std.mem.Allocator) !usize {
        try self.buffer.appendNTimes(allocator, 0, self.component_size);
        return (self.buffer.items.len / self.component_size) - 1;
    }

    pub fn addBytes(self: *@This(), allocator: std.mem.Allocator, component_id: ComponentId, bytes: []const u8) !void {
        std.debug.assert(self.vtable.component_id == component_id);
        try self.buffer.appendSlice(allocator, bytes);
    }

    pub fn getOpaque(self: *@This(), index: usize) *anyopaque {
        std.debug.assert(index < (self.buffer.items.len / self.component_size));
        const buffer_index = index * self.component_size;
        const buffer_pointer = self.buffer.items[buffer_index .. buffer_index + self.component_size];
        return @ptrCast(buffer_pointer);
    }

    pub fn getAs(self: *@This(), index: usize, comptime T: type) *T {
        std.debug.assert(index < (self.buffer.items.len / self.component_size));
        const buffer_index = index * self.component_size;
        const buffer_pointer: []align(@alignOf(T)) u8 = @alignCast(self.buffer.items[buffer_index .. buffer_index + self.component_size]);
        const as_component: *T = std.mem.bytesAsValue(T, buffer_pointer);
        return as_component;
    }

    pub fn deinit(self: *@This(), allocator: std.mem.Allocator, freelist: *std.AutoHashMap(usize, u8)) void {
        const column_size = self.buffer.items.len / self.component_size;
        var index: usize = 0;
        while (index < column_size) : (index += 1) {
            if (freelist.contains(index)) {
                continue;
            }
            const buffer_index = self.component_size * index;
            const buffer_pointer = self.buffer.items[buffer_index .. buffer_index + self.component_size];
            const as_pointer: *anyopaque = @ptrCast(@alignCast(buffer_pointer));
            const component_deinit = self.vtable.deinit;
            component_deinit(as_pointer, allocator);
        }
        self.buffer.deinit(allocator);
    }
};

pub const ComponentWrapper = struct {
    pub const VTable = struct {
        size: usize,
        alignment: usize,
        // Should be static
        name: []const u8,
        component_id: ComponentId,
        deinit: ComponentDeinit,
        luaPush: ?ComponentLuaPush,
        fromLua: ?ComponentFromLua,
    };

    pointer: *anyopaque,
    // should be static
    vtable: *const VTable,
};

pub const ArchetypeStorage = struct {
    components: []const ComponentId,
    entities: std.AutoArrayHashMap(usize, Entity),
    // abstract index used to quickly access archetype
    archetype_index: usize,
};

archetypes_v2: std.ArrayList(Archetype),
entity_map: EntityMap,

// archetypes: std.ArrayList(ArchetypeStorage),
components_per_archetype: std.ArrayList(Sorted([]const ComponentId)),
queries_hash: std.AutoHashMap(u64, std.ArrayList(CacheEntry)),
allocator: std.mem.Allocator,
idprovider: utils.IdProvider,
vtable_storage: *VTableStorage,

const CacheEntry = struct {
    components: []const ComponentId,
    exclude: []const ComponentId,
    archetypes: []const usize,
};

pub fn init(allocator: std.mem.Allocator, idprovider: utils.IdProvider, vtable_storage: *VTableStorage) !Self {
    return .{
        //.archetypes = .empty,
        .components_per_archetype = .empty,
        .allocator = allocator,
        .queries_hash = .init(allocator),
        .idprovider = idprovider,
        .vtable_storage = vtable_storage,
        .entity_map = .init(allocator),
        .archetypes_v2 = .empty,
    };
}

// Adds entity with the given id to the storage.
//
// Copies all the components to the allocated space for them.
pub fn add(self: *Self, id: EntityId, components: anytype) !void {
    const tinfo = @typeInfo(@TypeOf(components));
    if (comptime tinfo != .@"struct" and !tinfo.@"struct".is_tuple) {
        @compileError("components of an entity have to be passed as a tuple");
    }
    const components_len = tinfo.@"struct".fields.len;
    var vtables: [components_len]*const ComponentWrapper.VTable = undefined;
    var component_ids: [components_len]ComponentId = undefined;
    var wrappers: [components_len]ComponentWrapper = undefined;
    inline for (components, 0..) |component, index| {
        const vtable = try self.createVTable(@TypeOf(component));
        vtables[index] = vtable;
        component_ids[index] = vtable.component_id;
        const boxed = try self.allocator.create(@TypeOf(component));
        boxed.* = component;
        wrappers[index] = ComponentWrapper{
            .pointer = @ptrCast(boxed),
            .vtable = vtable,
        };
    }
    const storage = try self.findOrCreateArchetype(&component_ids, &vtables);
    const row_id = try storage.add(self.allocator, &wrappers);
    try self.entity_map.put(id, .{
        .archetype_index = storage.archetype_index,
        .row_id = row_id,
    });
    inline for (components, 0..) |component, index| {
        self.allocator.destroy(
            @as(
                *@TypeOf(component),
                @ptrCast(@alignCast(wrappers[index].pointer)),
            ),
        );
    }
}

pub fn addWrapped(self: *Self, id: EntityId, components: []const ComponentWrapper) !void {
    var vtables = try self.allocator.alloc(*const ComponentWrapper.VTable, components.len);
    var component_ids = try self.allocator.alloc(ComponentId, components.len);
    defer self.allocator.free(vtables);
    defer self.allocator.free(component_ids);
    for (components, 0..) |component, index| {
        const vtable = component.vtable;
        vtables[index] = vtable;
        component_ids[index] = vtable.component_id;
    }
    const storage = try self.findOrCreateArchetype(component_ids, vtables);
    const row_id = try storage.add(self.allocator, components);
    try self.entity_map.put(id, .{
        .archetype_index = storage.archetype_index,
        .row_id = row_id,
    });
}

/// Removes entities from the storage.
///
/// Runs deinit on all of the components.
pub fn remove(self: *Self, ids: []EntityId) !void {
    for (ids) |id| {
        const record = self.entity_map.get(id) orelse @panic("entity does not have a record");
        const archetype = &self.archetypes_v2.items[record.archetype_index];
        archetype.finalize(record.row_id, self.allocator);
        try archetype.remove(record.row_id);
        _ = self.entity_map.remove(id);
    }
}

pub fn addComponents(self: *Self, entity_id: EntityId, components: []ComponentWrapper) !void {
    // find entity
    const record = self.entity_map.get(entity_id) orelse @panic("entity does not exist");
    std.debug.print("Retrieved record for removal {any}\n", .{record});
    std.debug.print("Archetypes len is {any}\n", .{self.archetypes_v2.items.len});
    const archetype = &self.archetypes_v2.items[record.archetype_index];

    // sanity check
    for (components) |wrapper| {
        const component_id = wrapper.vtable.component_id;
        if (archetype.components_map.contains(component_id)) {
            @panic("adding the same component twice");
        }
    }

    // create table of new components
    var new_components = try self.allocator.alloc(
        ComponentWrapper,
        components.len + archetype.components_ids.len,
    );
    defer self.allocator.free(new_components);
    for (archetype.components.items, 0..) |*column, index| {
        const ptr = column.getOpaque(record.row_id);
        const wrapper: ComponentWrapper = .{
            .vtable = column.vtable,
            .pointer = ptr,
        };
        new_components[index] = wrapper;
    }
    for (components, archetype.components_ids.len..) |component, index| {
        new_components[index] = component;
    }

    // overwrites the old entity map record
    try self.addWrapped(entity_id, new_components);
    // we need to get archetype again as it could get realocated if
    // new archetype has been created.
    var old_archetype = &self.archetypes_v2.items[record.archetype_index];
    try old_archetype.remove(record.row_id);
}

pub fn removeComponents(self: *Self, entity_id: EntityId, components: []ComponentId) !void {
    // find entity
    const record = self.entity_map.get(entity_id) orelse @panic("entity does not exist");
    const archetype = &self.archetypes_v2.items[record.archetype_index];

    // sanity check
    for (components) |wrapper| {
        const component_id = wrapper.vtable.component_id;
        if (!archetype.components_map.contains(component_id)) {
            @panic("removing already removed component");
        }
    }

    // create table of new components
    var new_components = try self.allocator.alloc(
        ComponentWrapper,
        archetype.components_ids.len - components.len,
    );
    defer self.allocator.free(new_components);
    var index: usize = 0;
    for (archetype.components.items) |*column| {
        // skip over components that we want to remove
        for (components) |component_id| {
            if (component_id == column.component_id) {
                continue;
            }
        }
        const ptr = column.getOpaque(record.row_id);
        const wrapper: ComponentWrapper = .{
            .vtable = column.vtable,
            .pointer = ptr,
        };
        new_components[index] = wrapper;
        index += 1;
    }
    // overwrites old entity map
    try self.add(entity_id, new_components);
    // we need to get archetype again as it could get realocated if
    // new archetype has been created.
    var old_archetype = &self.archetypes_v2.items[record.archetype_index];
    // only finalize removed components
    old_archetype.finalizeById(record.row_id, self.allocator, components);
    try old_archetype.remove(record.row_id);
}

fn findOrCreateArchetype(self: *Self, ids: []ComponentId, wrappers: []*const ComponentWrapper.VTable) !*Archetype {
    std.sort.heap(ComponentId, ids, {}, std.sort.asc(ComponentId));
    if (self.findExactArchetypeProvidedSorted(assertSorted(ComponentId, ids))) |ptr| {
        return ptr;
    }
    return self.createArchetype(assertSorted(ComponentId, ids), wrappers);
}

fn findExactArchetypeProvidedSorted(self: *Self, ids: []const ComponentId) ?*Archetype {
    outer: for (self.components_per_archetype.items, 0..) |components, archetype_idx| {
        if (components.len != ids.len) {
            continue;
        }
        for (components, ids) |c1, c2| {
            if (c1 != c2) {
                continue :outer;
            }
        }
        return &self.archetypes_v2.items[archetype_idx];
    }
    return null;
}

fn createArchetype(self: *Self, ids: []ComponentId, wrappers: []*const ComponentWrapper.VTable) !*Archetype {
    // creating archetype invalidates cache
    self.invalidateCache();
    const heaped = try self.allocator.dupe(ComponentId, ids);
    const archetype_index = self.archetypes_v2.items.len;
    const new = try Archetype.init(
        self.allocator,
        archetype_index,
        heaped,
        wrappers,
    );
    try self.archetypes_v2.append(self.allocator, new);
    try self.components_per_archetype.append(self.allocator, heaped);
    return &self.archetypes_v2.items[self.archetypes_v2.items.len - 1];
}

pub fn query(self: *Self, comptime comps: anytype, comptime exclude: anytype) QueryIter(comps) {
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
        componentIds[index] = utils.dynamicTypeId(component, self.idprovider);
    }
    std.sort.heap(ComponentId, &componentIds, {}, std.sort.asc(ComponentId));
    _ = assertSorted(ComponentId, &componentIds);

    const info_exclude = @typeInfo(@TypeOf(exclude));
    if (info_exclude != .@"struct" and !info_exclude.@"struct".is_tuple) {
        @compileError("query accepts a tuple of types");
    }
    const infoStructExclude = info.@"struct";
    var excludeIds: [infoStructExclude.fields.len]ComponentId = undefined;
    inline for (exclude, 0..) |component, index| {
        const tinfo = @typeInfo(@TypeOf(component));
        if (tinfo != .type) {
            @compileError("query accepts a typle of types");
        }
        excludeIds[index] = utils.dynamicTypeId(component, self.idprovider);
    }
    std.sort.heap(ComponentId, &excludeIds, {}, std.sort.asc(ComponentId));
    _ = assertSorted(ComponentId, &excludeIds);

    const cache: []const usize = self.lookupQueryHash(&componentIds, &excludeIds) catch @panic("could not build cache");
    return QueryIter(comps).init(self, componentIds, cache, self.idprovider);
}

pub fn lookupQueryHash(self: *Self, component_ids: Sorted([]ComponentId), exclude_ids: Sorted([]ComponentId)) ![]const usize {
    const query_hash = fnv1a64(component_ids, exclude_ids);
    if (self.queries_hash.get(query_hash)) |cache_entries| {
        for (cache_entries.items) |entry| {
            if (std.mem.eql(ComponentId, entry.components, component_ids)) {
                if (std.mem.eql(ComponentId, entry.exclude, exclude_ids)) {
                    return entry.archetypes;
                }
            }
        }
    }

    //std.debug.print("Building cache {any}\n", .{component_ids});
    var cache = std.ArrayList(usize).empty;
    var next_archetype: usize = 0;
    while (next_archetype < self.archetypes_v2.items.len) {
        const archetype_comps = self.components_per_archetype.items[next_archetype];
        if (!utils.isSubset(component_ids, archetype_comps)) {
            // not a subset, check next archetype
            next_archetype += 1;
            continue;
        }
        if (std.mem.indexOfAny(ComponentId, archetype_comps, exclude_ids)) |_| {
            next_archetype += 1;
            continue;
        }
        try cache.append(self.allocator, next_archetype);
        next_archetype += 1;
    }
    const asSlice = try cache.toOwnedSlice(self.allocator);
    const cache_entry = CacheEntry{
        .archetypes = asSlice,
        .exclude = try self.allocator.dupe(ComponentId, exclude_ids),
        .components = try self.allocator.dupe(ComponentId, component_ids),
    };
    const entry_ptr = self.queries_hash.getPtr(query_hash);
    if (entry_ptr) |ptr| {
        try ptr.append(self.allocator, cache_entry);
    } else {
        var fresh = std.ArrayList(CacheEntry).empty;
        try fresh.append(self.allocator, cache_entry);
        try self.queries_hash.put(query_hash, fresh);
    }
    return asSlice;
}

pub const DynamicScopeOptions = struct {
    allocator: ?std.mem.Allocator = null,
};

/// Returns a scope object that can be used to crete dynamic query iterator.
/// Scope has to be freed after the query has been used.
///
/// Does not take ownership of the components slice. It has be the freed by the caller.
pub fn dynamicQueryScope(self: *Self, components: []const ComponentId, exclude: []const ComponentId, options: DynamicScopeOptions) !DynamicQueryScope {
    const allocator = options.allocator orelse self.allocator;
    return .init(self, components, exclude, allocator);
}

pub fn createVTable(self: *Self, comptime Component: type) !*ComponentWrapper.VTable {
    const id = utils.dynamicTypeId(Component, self.idprovider);
    if (self.vtable_storage.get(id)) |vtable| {
        return vtable;
    }
    const compDeinit: ComponentDeinit = if (comptime std.meta.hasMethod(Component, "deinit"))
        @ptrCast(&Component.deinit)
    else
        @ptrCast(&emptyDeinit);

    const compLuaPush: ?ComponentLuaPush = if (comptime @hasDecl(Component, "lua_info"))
        @ptrCast(&@TypeOf(Component.lua_info).luaPush)
    else
        null;
    const wrapperFromLua: ?ComponentFromLua = if (comptime @hasDecl(Component, "lua_info"))
        @ptrCast(&@TypeOf(Component.lua_info).wrapperFromLua)
    else
        null;
    const vtable: ComponentWrapper.VTable = .{
        .alignment = @alignOf(Component),
        .size = @sizeOf(Component),
        .component_id = id,
        .name = @TypeOf(Component.component_info).comp_name,
        .deinit = compDeinit,
        .luaPush = compLuaPush,
        .fromLua = wrapperFromLua,
    };
    return try self.vtable_storage.new(id, vtable);
}

pub fn createWrapper(self: *Self, comptime Component: type, cptr: *Component) !ComponentWrapper {
    return .{
        .pointer = @ptrCast(cptr),
        .vtable = try self.createVTable(Component),
    };
}

pub fn deinit(self: *Self) void {
    self.components_per_archetype.deinit(self.allocator);
    self.entity_map.deinit();
    for (self.archetypes_v2.items) |*archetype| {
        archetype.deinit(self.allocator);
    }
    self.archetypes_v2.deinit(self.allocator);
    self.invalidateCache();
    self.queries_hash.deinit();
}

fn invalidateCache(self: *Self) void {
    var iter = self.queries_hash.valueIterator();
    while (iter.next()) |c| {
        for (c.items) |item| {
            self.allocator.free(item.archetypes);
            self.allocator.free(item.exclude);
            self.allocator.free(item.components);
        }
        c.deinit(self.allocator);
    }
    self.queries_hash.clearRetainingCapacity();
}

fn emptyDeinit(ptr: *anyopaque, allocator: std.mem.Allocator) void {
    _ = ptr;
    _ = allocator;
}

pub fn fnv1a64(data: []const u64, exclude_data: []const u64) u64 {
    var hash: u64 = 0xcbf29ce484222325; // FNV offset basis
    const prime: u64 = 0x100000001b3; // FNV prime

    for (data) |x| {
        const bytes = std.mem.asBytes(&x);
        for (bytes) |b| {
            hash ^= @as(u64, b);
            hash *%= prime; // *= prime, wrapping multiply
        }
    }

    for (exclude_data) |x| {
        const bytes = std.mem.asBytes(&x);
        for (bytes) |b| {
            hash ^= @as(u64, b);
            hash *%= prime; // *= prime, wrapping multiply
        }
    }

    return hash;
}
