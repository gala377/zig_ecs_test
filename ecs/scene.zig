const std = @import("std");

const Entity = @import("entity.zig");
const EntityStorage = @import("entity_storage.zig");
const Component = @import("component.zig").LibComponent;
const utils = @import("utils.zig");

pub const ComponentWrapper = struct {
    pointer: *anyopaque,
    size: usize,
    alignment: usize,
    name: []const u8,
    deinit: ComponentDeinit,
};

pub const EntityId = struct {
    pub usingnamespace Component("ecs", EntityId);
    scene_id: usize,
    entity_id: usize,
};

pub const ComponentDeinit = *const fn (*anyopaque, sceneAllocator: std.mem.Allocator) void;

pub const Scene = struct {
    const Self = @This();

    id: usize,
    inner_id: usize,
    entity_storage: EntityStorage,
    idprovider: utils.IdProvider,

    /// Can be accessed directly to query for components.
    scene_allocator: std.mem.Allocator,

    pub fn init(id: usize, idprovider: utils.IdProvider, allocator: std.mem.Allocator) !Self {
        return .{
            .id = id,
            .scene_allocator = allocator,
            .inner_id = 0,
            .idprovider = idprovider,
            .entity_storage = try EntityStorage.init(allocator, idprovider),
        };
    }

    pub fn deinit(self: *Self) void {
        self.entity_storage.deinit();
    }

    pub fn newEntity(self: *Self, comps: anytype) !EntityId {
        const id = self.newId();
        try self.entity_storage.makeEntity(id, comps);
        return .{ .scene_id = self.inner_id, .entity_id = id };
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

fn emptyDeinit(ptr: *anyopaque, allocator: std.mem.Allocator) void {
    _ = ptr;
    _ = allocator;
}
