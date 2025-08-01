const Storage = @import("entity_storage.zig");
const ComponentId = @import("component.zig").ComponentId;
const std = @import("std");
const Entity = @import("entity.zig");
const utils = @import("utils.zig");

// Because dunamic query cannot decide the amount of components at comptime
// the returned components are returned as a slice allocated by the iterator.
//
// This means that after they have been processed the slice has to be freed
// with scope.freeComponentsSlice
//
// Also as there are allocations that Scope needs to do (because of the runtime
// nature of the query) scope has to deinited.
// So the usage actually looks like this.
//
// var scope = storage.dynamicQueryScope(component_ids, .{});
// defer scope.deinit();
//
// var iter = scope.iter();
// while(iter.next()) |components| {
//    defer scope.freeComponentsSlice(components);
//    // do something with component pointers
// }
//
// slices are not freed by deinit in case the caller wants to take ownership of the
// slice, just mind that it uses Storage allocator unless another is passed in options.
//
// var scope = storage.dynamicQueryScope(component_ids, .{ allocator = myAlloc });
pub const DynamicQueryScope = struct {
    component_ids: []const ComponentId,
    sorted_component_ids: []const ComponentId,
    storage: *Storage,
    allocator: std.mem.Allocator,

    pub fn init(storage: *Storage, component_ids: []ComponentId, allocator: std.mem.Allocator) !DynamicQueryScope {
        var sorted = try allocator.dupe(ComponentId, component_ids);
        std.sort.heap(ComponentId, &sorted, {}, std.sort.asc(ComponentId));
        return .{
            .component_ids = component_ids,
            .sorted_component_ids = sorted,
            .storage = storage,
            .allocator = allocator,
        };
    }

    pub fn iter(self: *DynamicQueryScope) DynamicQueryIter {
        return .{
            .component_ids = self.component_ids,
            .sorted_component_ids = self.sorted_component_ids,
            .storage = self.storage,
            .allocator = self.allocator,
        };
    }

    pub fn freeComponentsSlice(self: *DynamicQueryScope, slice: []*anyopaque) void {
        self.allocator.free(slice);
    }

    pub fn deinit(self: *DynamicQueryScope) void {
        self.allocator.free(self.sorted_component_ids);
    }
};

pub const DynamicQueryIter = struct {
    const Self = @This();
    const MetaTableName = @typeName(Self) ++ "_MetaTable";

    component_ids: []const ComponentId,
    sorted_component_ids: []const ComponentId,
    storage: *Storage,
    next_archetype: usize = 0,
    current_entity_iterator: ?std.AutoHashMap(usize, Entity).ValueIterator = null,
    allocator: std.mem.Allocator,

    pub fn next(self: *Self) ?[]*anyopaque {
        if (self.current_entity_iterator) |it| {
            var itt: std.AutoHashMap(usize, Entity).ValueIterator = it;
            if (itt.next()) |entity| {
                return self.getComponentsFromEntity(entity);
            }
            // iterator ended
            self.current_entity_iterator = null;
        }
        while (self.next_archetype < self.storage.archetypes.items.len) {
            const comps = self.storage.components_per_archetype.items[self.next_archetype];
            if (!utils.isSubset(&self.sorted_component_ids, comps)) {
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
                return self.getComponentsFromEntity(entity);
            }
            // no entities in the iterator
            self.current_entity_iterator = null;
            self.next_archetype += 1;
        }
        return null;
    }

    fn getComponentsFromEntity(self: *Self, entity: *Entity) []*anyopaque {
        var res = self.allocator.alloc(*anyopaque, self.component_ids.len) catch {
            @panic("oom");
        };
        for (self.component_ids, 0..) |id, idx| {
            const comp = entity.components.getPtr(id).?;
            res[idx] = comp.pointer;
        }
        return res;
    }
};
