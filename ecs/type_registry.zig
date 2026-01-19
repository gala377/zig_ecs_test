const std = @import("std");

const lua = @import("lua_lib");
const clua = lua.clib;

const ComponentWrapper = @import("entity_storage.zig").ComponentWrapper;
const entity_storage = @import("entity_storage.zig");
const utils = @import("utils.zig");

pub const TypeRegistry = struct {
    types: std.AutoHashMap(usize, Deserializers),
    names_to_ids: std.StringHashMap(usize),
    allocator: std.mem.Allocator,

    pub fn new(allocator: std.mem.Allocator) TypeRegistry {
        return .{
            .allocator = allocator,
            .types = .init(allocator),
            .names_to_ids = .init(allocator),
        };
    }

    pub fn deinit(self: *TypeRegistry) void {
        self.types.deinit();
        const keys = self.names_to_ids.keyIterator();
        while (keys.next()) |key| {
            self.allocator.free(key.*);
        }
        self.names_to_ids.deinit();
    }
};

pub const Deserializers = struct {
    fromLau: *const fn (state: *clua.lua_State, allocator: std.mem.Allocator) ?*anyopaque,
    fromJson: *const fn (value: std.json.Value, allocator: std.mem.Allocator) ?*anyopaque,
};

pub fn deserializer(comptime T: type) Deserializers {
    const d = struct {
        fn fromLua(state: *clua.lua_State, allocator: std.mem.Allocator) ?*anyopaque {
            _ = state;
            _ = allocator;
            // we should expect that top is us
            unreachable;
        }
        fn fromJson(value: std.json.Value, allocator: std.mem.Allocator) ?*anyopaque {
            const obj = allocator.create(T) catch @panic("could not allocate memory");
            obj.* = std.json.parseFromValueLeaky(
                T,
                allocator,
                value,
                .{},
            ) catch @panic("could not parse value");
            return @ptrCast(@alignCast(obj));
        }
    };
    return .{
        .fromLua = &d.fromLua,
        .fromJson = &d.fromJson,
    };
}
