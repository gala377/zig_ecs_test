const std = @import("std");
const ecs = @import("prelude.zig");

pub const RegistryHandle = usize;
const Self = @This();

handles: std.StringHashMap(usize),
systems: std.ArrayList(ecs.System),
allocator: std.mem.Allocator,

pub fn init(allocator: std.mem.Allocator) Self {
    return .{
        .handles = .init(allocator),
        .systems = .empty,
        .allocator = allocator,
    };
}

pub fn getByHandle(self: *Self, handle: RegistryHandle) ?ecs.System {
    if (self.systems.items.len <= handle) {
        return null;
    }
    return self.systems.items[handle];
}

pub fn resolveName(self: *Self, name: []const u8) ?RegistryHandle {
    return self.handles.get(name);
}

pub fn getByName(self: *Self, name: []const u8) ?ecs.System {
    const index = self.resolveName(name) orelse return null;
    return self.systems.items[index];
}

pub fn register(self: *Self, sys: ecs.System) !RegistryHandle {
    return self.registerAs(sys.name, sys);
}

pub fn registerAs(self: *Self, name: []const u8, sys: ecs.System) !RegistryHandle {
    const index = self.systems.items.len;
    try self.systems.append(self.allocator, sys);
    const label = try self.allocator.dupe(u8, name);
    try self.handles.put(label, index);
    return index;
}

pub fn deinit(self: *Self) void {
    var keys = self.handles.keyIterator();
    while (keys.next()) |k| {
        self.allocator.free(k.*);
    }
    self.handles.deinit();
    self.systems.deinit(self.allocator);
}
