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
        const old = try self.components.fetchPut(c.vtable.component_id, c);
        if (old) |prev| {
            _ = prev;
            @panic("replaced already existing component");
        }
    }
}

pub fn removeComponents(self: *Self, components: []ComponentId, allocator: std.mem.Allocator) void {
    for (components) |comp| {
        const kv = self.components.fetchRemove(comp) orelse continue;
        const wrapper = kv.value;
        wrapper.deinit(wrapper.pointer, allocator);
        wrapper.free(wrapper.pointer, allocator);
    }
}

pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
    var components = self.components.valueIterator();
    while (components.next()) |c| {
        c.vtable.deinit(c.pointer, allocator);
        c.vtable.free(c.pointer, allocator);
    }
    self.components.deinit();
}
