const std = @import("std");

const Entity = @import("entity.zig");
const EntityId = Entity.EntityId;
const ExportLua = @import("component.zig").ExportLua;
const EntityStorage = @import("entity_storage.zig");
const Component = @import("component.zig").LibComponent;
const utils = @import("utils.zig");
const VTableStorage = @import("comp_vtable_storage.zig");

pub const Scene = struct {
    const Self = @This();

    id: usize,
    inner_id: usize,
    entity_storage: EntityStorage,
    idprovider: utils.IdProvider,

    /// Can be accessed directly to query for components.
    scene_allocator: std.mem.Allocator,

    pub fn init(id: usize, idprovider: utils.IdProvider, allocator: std.mem.Allocator, vtable_storage: *VTableStorage) !Self {
        return .{
            .id = id,
            .scene_allocator = allocator,
            .inner_id = 0,
            .idprovider = idprovider,
            .entity_storage = try EntityStorage.init(allocator, idprovider, vtable_storage),
        };
    }

    pub fn deinit(self: *Self) void {
        self.entity_storage.deinit();
    }

    pub fn newEntity(self: *Self, comps: anytype) !EntityId {
        const id = self.newId();
        const entity_id = EntityId{
            .scene_id = self.id,
            .entity_id = id,
            .archetype_id = try self.scene_allocator.create(usize),
        };
        const with_id = .{entity_id} ++ comps;
        try self.entity_storage.makeEntity(id, with_id);
        return entity_id;
    }

    pub fn newId(self: *Self) usize {
        const current = self.inner_id;
        self.inner_id += 1;
        return current;
    }

    pub fn getAllocator(self: *Scene) std.mem.Allocator {
        return self.scene_allocator;
    }
};
