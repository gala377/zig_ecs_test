const std = @import("std");

const Entity = @import("entity.zig").Entity;

pub const ComponentWrapper = struct {
    pointer: *anyopaque,
    size: usize,
    alignment: usize,
    name: []const u8,
    deinit: ComponentDeinit,
};

pub const EntityId = struct {
    scene_id: usize,
    entity_id: usize,
};

pub const ComponentDeinit = *const fn (*anyopaque, sceneAllocator: std.mem.Allocator) void;

pub const Scene = struct {
    const Self = @This();

    id: usize,
    entities: std.AutoHashMap(usize, Entity),
    scene_allocator: std.mem.Allocator,
    components: std.ArrayList(ComponentWrapper),
    inner_id: usize,

    pub fn init(id: usize, allocator: std.mem.Allocator) Self {
        return .{
            .id = id,
            .entities = .init(allocator),
            .scene_allocator = allocator,
            .components = .init(allocator),
            .inner_id = 0,
        };
    }

    pub fn deinit(self: *Self) void {
        var entities = self.entities.valueIterator();

        while (entities.next()) |entity| {
            entity.deinit();
        }

        self.entities.deinit();
        for (self.components.items) |*comp| {
            const cdeinit = comp.deinit;
            cdeinit(comp.pointer, self.scene_allocator);

            const mem: [*]u8 = @ptrCast(comp.pointer);
            const asSlice: []u8 = mem[0..comp.size];

            self.scene_allocator.rawFree(asSlice, std.mem.Alignment.fromByteUnits(comp.alignment), 0);
            // TODO: dealloc the name if names are only known at runtime, for now we
            // know them at compile time, just for tests

        }
        self.components.deinit();
    }

    pub fn allocComponent(self: *Self, name: []const u8, comp: anytype) !void {
        const cptr = try self.scene_allocator.create(@TypeOf(comp));
        cptr.* = comp;
        const compDeinit: ComponentDeinit = if (comptime std.meta.hasMethod(@TypeOf(comp), "deinit")) @ptrCast(&@TypeOf(comp).deinit) else @ptrCast(emptyDeinit);

        const wrapped: ComponentWrapper = .{
            .pointer = @ptrCast(cptr),
            .alignment = @alignOf(@TypeOf(comp)),
            .size = @sizeOf(@TypeOf(comp)),
            .name = name,
            .deinit = compDeinit,
        };
        std.debug.print("align is {}\n", .{wrapped.alignment});
        try self.components.append(wrapped);
        // TODO: return reference to the component
    }

    pub fn allocEntity(self: *Self, comps: []ComponentWrapper) !EntityId {
        const entity = try Entity.init(self.newId(), self.scene_allocator);
        for (comps) |c| {
            entity.components.put(c.name, c);
        }
        try self.entities.put(entity.id, entity);
        return .{
            .scene_id = self.id,
            .entity_id = entity.id,
        };
    }

    pub fn newId(self: *Self) usize {
        const current = self.inner_id;
        self.inner_id += 1;
        return current;
    }

    pub fn getAllocator(self: *Scene) std.mem.Allocator {
        return self.scene_allocator;
    }

    // pub fn spawnEntity(self: *Scene, components: anytype) void {
    //     inline for (components) |comp| {}
    // }
};

fn emptyDeinit(ptr: *anyopaque, allocator: std.mem.Allocator) void {
    _ = ptr;
    _ = allocator;
}
