const std = @import("std");

const lua = @import("lua_lib");
const clua = lua.clib;

const ComponentWrapper = @import("entity_storage.zig").ComponentWrapper;
const entity_storage = @import("entity_storage.zig");
const utils = @import("utils.zig");

pub const ComponentId = u64;

pub fn ComponentInfo(comptime name: []const u8) type {
    return struct {
        pub const comp_name = name;
    };
}

pub fn Component(comptime T: type) ComponentInfo(@typeName(T)) {
    return .{};
}

pub fn LibComponent(
    comptime name_prefix: []const u8,
    comptime T: type,
) ComponentInfo(name_prefix ++ "." ++ @typeName(T)) {
    return .{};
}
