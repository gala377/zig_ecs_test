const std = @import("std");
const ecs = @import("../prelude.zig");

const Component = ecs.Component;
const ExportLua = ecs.ExportLua;
const Resource = ecs.Resource;

// Global allocator to be used by persisting allocations
pub const GlobalAllocator = struct {
    pub const component_info = Component(GlobalAllocator);

    allocator: std.mem.Allocator,
};

// Frame allocator, freed after every frame
pub const FrameAllocator = struct {
    pub const component_info = Component(FrameAllocator);

    allocator: std.mem.Allocator,
    arena: *std.heap.ArenaAllocator,
};

pub fn freeFrameAllocator(allocator_res: Resource(FrameAllocator)) void {
    const allocator = allocator_res.get();
    _ = allocator.arena.reset(.retain_capacity);
}
