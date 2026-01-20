const std = @import("std");
const component_prefix = @import("build_options").components_prefix;

const lua = @import("lua_lib");

const component = @import("component.zig");
const ComponentId = component.ComponentId;
const ComponentWrapper = component.ComponentWrapper;
const utils = @import("utils.zig");
const ExportLua = @import("lua_interop/root.zig").export_component.ExportLua;

pub const EntityId = struct {
    pub const component_info = component.LibComponent(component_prefix, EntityId);
    pub const lua_info = ExportLua(EntityId, .{
        .name_prefix = component_prefix,
    });
    scene_id: usize,
    entity_id: usize,
};

const Self = @This();

id: usize,
// maps component id to the column index
component_columns: std.AutoHashMap(ComponentId, usize),
components_matrix: std.ArrayList(ComponentWrapper),
components: std.AutoHashMap(ComponentId, ComponentWrapper),

pub fn init(id: usize, allocator: std.mem.Allocator) Self {
    return .{
        .id = id,
        .components = .init(allocator),
    };
}

pub fn getComponent(self: *Self, comptime T: type) ?*T {
    const wrapper = self.components.get(utils.dynamicTypeId(T, null)) orelse return null;
    return @ptrCast(@alignCast(wrapper.pointer));
}

pub fn addComponents(self: *Self, components: []ComponentWrapper) !void {
    for (components) |c| {
        const old = try self.components.fetchPut(c.component_id, c);
        if (old) |prev| {
            std.debug.panic("Replacing already existing componentof type  {s} with {s}", .{ prev.value.vtable.name, c.vtable.name });
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
