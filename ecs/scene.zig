const std = @import("std");
const ecs = @import("prelude.zig");

const utils = ecs.utils;
const entity = ecs.entity;

const EntityStorage = ecs.EntityStorage;

pub const Scene = struct {
    const Self = @This();

    id: usize,
    inner_id: usize,
    entity_storage: EntityStorage,
    idprovider: utils.IdProvider,

    /// Can be accessed directly to query for components.
    scene_allocator: std.mem.Allocator,

    pub fn init(
        id: usize,
        idprovider: utils.IdProvider,
        allocator: std.mem.Allocator,
    ) !Self {
        return .{
            .id = id,
            .scene_allocator = allocator,
            .inner_id = 0,
            .idprovider = idprovider,
            .entity_storage = try EntityStorage.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.entity_storage.deinit();
    }

    pub fn newEntity(self: *Self, comps: anytype) !entity.Id {
        const id = self.newId();
        const entity_id = entity.Id{
            .scene_id = self.id,
            .entity_id = id,
        };
        const with_id = .{entity_id} ++ comps;
        try self.entity_storage.add(id, with_id);
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
