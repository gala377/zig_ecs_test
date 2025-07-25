const std = @import("std");
const lua = @import("lua_lib");

pub const Entity = struct {
    const Self = @This();

    id: usize,
    // TODO: Figure out how we will reference components from entities
    components: std.StringHashMap(*anyopaque),

    pub fn init(id: usize, allocator: std.mem.Allocator) Self {
        return .{
            .id = id,
            .components = .init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        // TODO: we need to deinig keys in the components table
        // this is not how we will refer to the components in the future
        // so maybe there is a better way
        self.components.deinit();
    }
};
