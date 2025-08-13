const ComponentId = @import("component.zig").ComponentId;
const Entity = @import("entity.zig");
const utils = @import("utils.zig");
const PtrTuple = utils.PtrTuple;
const ComponentWrapper = @import("entity_storage.zig").ComponentWrapper;

pub fn QueryIter(comptime Components: anytype) type {
    const Storage = @import("entity_storage.zig");
    const Len = @typeInfo(@TypeOf(Components)).@"struct".fields.len;
    return struct {
        const Iter = @This();
        component_ids: [Len]ComponentId,
        storage: *Storage,
        next_archetype: usize = 0,
        current_entity_iterator_pos: usize = 0,
        current_entity_iterator: []Entity = &.{},
        cache: []const usize,
        idprovider: utils.IdProvider,

        pub fn init(storage: *Storage, component_ids: [Len]ComponentId, cache: []const usize, idprovider: utils.IdProvider) Iter {
            return .{
                .component_ids = component_ids,
                .storage = storage,
                .cache = cache,
                .idprovider = idprovider,
            };
        }

        pub fn next(self: *Iter) ?PtrTuple(Components) {
            if (self.current_entity_iterator_pos < self.current_entity_iterator.len) {
                const entity: *Entity = &self.current_entity_iterator[self.current_entity_iterator_pos];
                self.current_entity_iterator_pos += 1;
                return self.getComponentsFromEntity(entity);
            }
            return self.lookupCached(self.cache);
        }

        fn lookupCached(self: *Iter, cache: []const usize) ?PtrTuple(Components) {
            while (self.next_archetype < cache.len) {
                const archetype_index = cache[self.next_archetype];
                self.current_entity_iterator = self
                    .storage
                    .archetypes
                    .items[archetype_index]
                    .entities
                    .values();
                self.current_entity_iterator_pos = 0;
                self.next_archetype += 1;
                if (self.current_entity_iterator_pos < self.current_entity_iterator.len) {
                    const entity: *Entity = &self.current_entity_iterator[self.current_entity_iterator_pos];
                    self.current_entity_iterator_pos += 1;
                    return self.getComponentsFromEntity(entity);
                }
            }
            return null;
        }

        fn getComponentsFromEntity(self: *Iter, entity: *Entity) PtrTuple(Components) {
            var res: PtrTuple(Components) = undefined;
            inline for (Components, 0..) |Component, idx| {
                const id = utils.dynamicTypeId(Component, self.idprovider);
                const comp: *ComponentWrapper = entity.components.getPtr(id).?;
                const asptr: *Component = @ptrCast(@alignCast(comp.pointer));
                res[idx] = asptr;
            }
            return res;
        }
    };
}
