const std = @import("std");
const lua = @import("lua_lib");
const ComponentWrapper = @import("entity_storage.zig").ComponentWrapper;
const ComponentId = @import("component.zig").ComponentId;

const Self = @This();

id: usize,
components: std.AutoHashMap(ComponentId, ComponentWrapper),

pub fn init(id: usize, allocator: std.mem.Allocator) Self {
    return .{
        .id = id,
        .components = .init(allocator),
    };
}

pub fn addComponents(self: *Self, components: []ComponentWrapper) !void {
    for (components) |c| {
        const old = try self.components.fetchPut(c.component_id, c);
        if (old) |prev| {
            _ = prev;
            @panic("replaced already existing component");
        }
    }
}

pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
    var components = self.components.valueIterator();
    while (components.next()) |c| {
        c.deinit(c.pointer, allocator);
        c.free(c.pointer, allocator);
    }
    self.components.deinit();
}
