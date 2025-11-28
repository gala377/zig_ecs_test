const ComponentWrapper = @import("entity_storage.zig").ComponentWrapper;
const std = @import("std");

allocator: std.mem.Allocator,
name_to_id: std.StringHashMap(u64),
vtables: std.AutoHashMap(u64, *ComponentWrapper.VTable),

const Self = @This();

pub fn init(allocator: std.mem.Allocator) Self {
    return .{
        .allocator = allocator,
        .name_to_id = .init(allocator),
        .vtables = .init(allocator),
    };
}

pub fn get(self: *Self, comp_id: u64) ?*ComponentWrapper.VTable {
    return self.vtables.get(comp_id);
}

pub fn new(self: *Self, comp_id: u64, vtable: ComponentWrapper.VTable) !*ComponentWrapper.VTable {
    const mem = try self.allocator.create(ComponentWrapper.VTable);
    mem.* = vtable;
    try self.vtables.put(comp_id, mem);
    const name = try self.allocator.dupe(u8, vtable.name);
    try self.name_to_id.put(name, comp_id);
    return self.vtables.get(comp_id).?;
}

pub fn deinit(self: *Self) void {
    var values = self.vtables.valueIterator();
    while (values.next()) |vtable| {
        self.allocator.destroy(vtable.*);
    }
    var names = self.name_to_id.keyIterator();
    while (names.next()) |name| {
        self.allocator.free(name.*);
    }
    self.vtables.deinit();
    self.name_to_id.deinit();
}
