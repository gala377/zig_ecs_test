const std = @import("std");

const component_prefix = @import("build_options").components_prefix;
const component = @import("../component.zig");
const Component = component.LibComponent;
const ExportLua = component.ExportLua;
const Resource = @import("../resource.zig").Resource;

// Global allocator to be used by persisting allocations
pub const GlobalAllocator = struct {
    pub const component_info = Component(component_prefix, GlobalAllocator);

    allocator: std.mem.Allocator,
};

// Frame allocator, freed after every frame
pub const FrameAllocator = struct {
    pub const component_info = Component(component_prefix, FrameAllocator);

    allocator: std.mem.Allocator,
    arena: *std.heap.ArenaAllocator,
};

pub fn freeFrameAllocator(allocator_res: Resource(FrameAllocator)) void {
    const allocator = allocator_res.get();
    _ = allocator.arena.reset(.retain_capacity);
}
