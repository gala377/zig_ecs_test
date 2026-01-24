const ecs = @import("prelude.zig");
const component = ecs.component;
const utils = ecs.utils;

const PtrTuple = utils.PtrTuple;
const Archetype = ecs.EntityStorage.Archetype;

pub fn QueryIter(comptime Components: anytype) type {
    const Storage = @import("entity_storage.zig");
    const Len = @typeInfo(@TypeOf(Components)).@"struct".fields.len;
    return struct {
        const Iter = @This();
        component_ids: [Len]component.Id,
        storage: *Storage,
        next_archetype: usize = 0,
        cache: []const usize,

        archetype_entity_index: usize = 0,
        archetype_entities: usize = 0,
        archetype: ?*Archetype = null,

        pub fn init(storage: *Storage, component_ids: [Len]component.Id, cache: []const usize) Iter {
            return .{
                .component_ids = component_ids,
                .storage = storage,
                .cache = cache,
            };
        }

        pub fn next(self: *Iter) ?PtrTuple(Components) {
            const archetype = self.archetype orelse {
                // archetype has not been initialized yet
                return self.progressToNextArchetype(self.cache);
            };
            self.archetype_entity_index = archetype.nextIndex(self.archetype_entity_index) orelse {
                // archetype is emtptu
                return self.progressToNextArchetype(self.cache);
            };
            return self.getComponentsFromCurrentArchetype();
        }

        pub fn progressToNextArchetype(self: *Iter, cache: []const usize) ?PtrTuple(Components) {
            while (self.next_archetype < cache.len) {
                const archetype_index = cache[self.next_archetype];
                self.archetype = &self
                    .storage
                    .archetypes
                    .items[archetype_index];
                self.next_archetype += 1;
                self.archetype_entity_index = self.archetype.?.iterIndex() orelse {
                    // archetype is empty
                    continue;
                };
                return self.getComponentsFromCurrentArchetype();
            }
            return null;
        }

        pub fn getComponentsFromCurrentArchetype(self: *Iter) PtrTuple(Components) {
            var res: PtrTuple(Components) = undefined;
            inline for (Components, 0..) |Component, idx| {
                const id = utils.typeId(Component);
                const comp_column = self.archetype.?.components_map.get(id) orelse unreachable;
                const comp_ptr = self.archetype.?.components.items[comp_column].getAs(
                    self.archetype_entity_index,
                    Component,
                );
                res[idx] = comp_ptr;
            }
            return res;
        }
    };
}
